// LD_PRELOAD shim that wires the UT4 main-menu "online" button
// (UUTLocalPlayer::ToggleFriendsAndChat) on Linux to actually open the
// friends popup, instead of returning FReply::Handled() like the
// compiled-out PLATFORM_LINUX stub does.
//
// Strategy:
//   1. constructor finds libUE4-UnrealTournament-Linux-Shipping.so via
//      dl_iterate_phdr to get its load base.
//   2. compute the vtable address for UUTLocalPlayer (sym _ZTV14UUTLocalPlayer
//      at file offset 0x225b010, slot for ToggleFriendsAndChat at +0x7e0).
//   3. mprotect that page RW, rewrite the slot to point at our replacement,
//      mprotect back to R.
//   4. our replacement calls GetFriendsPopup() + SetShowingFriendsPopup(true)
//      and adds the widget to the viewport via UGameViewportClient::
//      AddViewportWidgetContent.
//
// Build:
//   g++ -shared -fPIC -O2 -o libut4_friends_fix.so ut4_friends_fix.cpp -ldl
//
// Use:
//   LD_PRELOAD=/path/libut4_friends_fix.so /path/UE4-Linux-Shipping ...

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <atomic>
#include <thread>
#include <chrono>
#include <dlfcn.h>
#include <link.h>
#include <sys/mman.h>
#include <unistd.h>

// -------- UE4 types ----------
struct FReply { uint8_t raw[0xa8]; };
struct TSharedPtr { void* p; void* sr; };

// Symbol mangled names (versioned UE4 suffix is implicit on the dynamic linker side)
extern "C" {
    // The replacement we'll plug into the vtable. UE4's return-by-value FReply
    // uses sret: %rdi = pointer to return slot, %rsi = this.
    typedef FReply* (*ToggleFn)(FReply* ret, void* self);

    // dlsym targets — resolved at runtime from the UT4 image
    typedef TSharedPtr* (*GetFriendsPopup_t)(TSharedPtr* ret, void* self);
    typedef void (*SetShowingFriendsPopup_t)(void* self, bool);
    typedef void (*AddViewportWidgetContent_t)(void* self, TSharedPtr widget, int zorder);
}

// Helpers from libUE4-Engine for getting the viewport client
typedef void* (*GetGameInstance_t)(const void* localPlayer);
typedef void* (*GetGameViewportClient_t)(const void* gameInstance);

static GetFriendsPopup_t s_GetFriendsPopup = nullptr;
static SetShowingFriendsPopup_t s_SetShowingFriendsPopup = nullptr;
static AddViewportWidgetContent_t s_AddViewportWidgetContent = nullptr;
static GetGameInstance_t s_GetGameInstance = nullptr;
static GetGameViewportClient_t s_GetGameViewportClient = nullptr;

// Time gate — the popup work is unsafe to fire during engine init (some
// code path calls ToggleFriendsAndChat from LoginStatusChanged or similar
// before the viewport / menu are fully constructed). Skip the popup work
// until enough time has elapsed since the shim loaded.
static std::chrono::steady_clock::time_point s_shim_loaded_at;
static constexpr int kSettleSeconds = 15;

static bool s_logged_once = false;

// FReply::Handled() byte pattern (matches the stripped Linux stub).
static void stamp_handled(FReply* ret)
{
    std::memset(ret, 0, sizeof(*ret));
    ret->raw[0] = 1;
    *reinterpret_cast<uint32_t*>(&ret->raw[0xa0]) = 0x702;
}

// Replacement that the vtable slot will point to.
extern "C" FReply* ut4_friends_fix_Toggle(FReply* ret, void* self)
{
    if (!s_logged_once) {
        s_logged_once = true;
        fprintf(stderr, "[ut4-friends-fix] ToggleFriendsAndChat fired self=%p\n", self);
    }

    // Time gate — early calls (during engine init / login status churn)
    // crash if we try to mount the popup widget. Mimic the stub for the
    // first kSettleSeconds, then let real user clicks through.
    auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::steady_clock::now() - s_shim_loaded_at).count();
    if (elapsed < kSettleSeconds) {
        stamp_handled(ret);
        return ret;
    }

    if (!s_GetFriendsPopup || !self) {
        stamp_handled(ret);
        return ret;
    }

    TSharedPtr popup{};
    s_GetFriendsPopup(&popup, self);

    stamp_handled(ret);

    if (s_SetShowingFriendsPopup) {
        s_SetShowingFriendsPopup(self, true);
    }

    // Add the popup widget to the viewport so it actually renders.
    // Chain: ULocalPlayer::GetGameInstance() → UGameInstance::GetGameViewportClient()
    if (s_GetGameInstance && s_GetGameViewportClient && s_AddViewportWidgetContent && popup.p && popup.sr) {
        void* gi = s_GetGameInstance(self);
        if (gi) {
            void* vp = s_GetGameViewportClient(gi);
            if (vp) {
                static bool added_once = false;
                if (!added_once) {
                    added_once = true;
                    fprintf(stderr, "[ut4-friends-fix] adding popup widget to viewport vp=%p popup=%p sr=%p (elapsed=%lds)\n",
                        vp, popup.p, popup.sr, (long)elapsed);
                }
                s_AddViewportWidgetContent(vp, popup, 200);
            }
        }
    }

    return ret;
}

// Find the load base of libUE4-UnrealTournament-Linux-Shipping.so
struct FindContext {
    uintptr_t base = 0;
    const char* needle = "libUE4-UnrealTournament-Linux-Shipping.so";
};

static int find_so_cb(struct dl_phdr_info* info, size_t, void* data)
{
    auto* ctx = static_cast<FindContext*>(data);
    if (!info->dlpi_name || !*info->dlpi_name) return 0;
    if (std::strstr(info->dlpi_name, ctx->needle)) {
        ctx->base = info->dlpi_addr;
        return 1;
    }
    return 0;
}

static std::atomic<bool> s_patched{false};

static bool try_install_vtable_patch()
{
    FindContext ctx;
    dl_iterate_phdr(find_so_cb, &ctx);
    if (!ctx.base) {
        return false;
    }

    // _ZTV14UUTLocalPlayer at vaddr 0x225b010 (from nm -D).
    // ToggleFriendsAndChat's vtable slot is at 0x225b800 — verified via
    //   readelf -r → R_X86_64_64 at 0x225b800 → _ZN14UUTLocalPlayer20ToggleFriendsAndChatEv.
    // That's offset +0x7f0 (NOT +0x7e0 — that one points at PrevTutorial).
    // SUTMenuBase calls `call *0x7e0(%rcx)` which is PrevTutorial; the actual
    // virtual dispatch for ToggleFriendsAndChat goes elsewhere, likely via
    // an inlined call site we haven't located yet. Patch +0x7f0 anyway —
    // if the click goes through it, our replacement fires.
    const uintptr_t kVtableVAddr = 0x225b010;
    const uintptr_t kSlotOffset = 0x7f0;

    uintptr_t slot_addr = ctx.base + kVtableVAddr + kSlotOffset;
    void** slot = reinterpret_cast<void**>(slot_addr);

    // UT4 module symbols aren't in the GLOBAL scope (UE4 dlopens its modules
    // with RTLD_LOCAL). dlopen the .so explicitly to pull a handle.
    void* ut_so = dlopen("libUE4-UnrealTournament-Linux-Shipping.so",
                         RTLD_NOLOAD | RTLD_LAZY);
    if (!ut_so) {
        fprintf(stderr, "[ut4-friends-fix] dlopen of UT4 .so failed: %s\n", dlerror());
    }

    s_GetFriendsPopup = (GetFriendsPopup_t)dlsym(ut_so ? ut_so : RTLD_DEFAULT,
        "_ZN14UUTLocalPlayer15GetFriendsPopupEv");
    s_SetShowingFriendsPopup = (SetShowingFriendsPopup_t)dlsym(ut_so ? ut_so : RTLD_DEFAULT,
        "_ZN14UUTLocalPlayer22SetShowingFriendsPopupEb");
    s_AddViewportWidgetContent = (AddViewportWidgetContent_t)dlsym(RTLD_DEFAULT,
        "_ZN19UGameViewportClient24AddViewportWidgetContentE10TSharedRefI7SWidgetL7ESPMode0EEi");
    s_GetGameInstance = (GetGameInstance_t)dlsym(RTLD_DEFAULT,
        "_ZNK12ULocalPlayer15GetGameInstanceEv");
    s_GetGameViewportClient = (GetGameViewportClient_t)dlsym(RTLD_DEFAULT,
        "_ZNK13UGameInstance21GetGameViewportClientEv");

    fprintf(stderr, "[ut4-friends-fix] base=0x%lx slot=%p old=%p Popup=%p SetShow=%p AddVWC=%p\n",
        ctx.base, slot, *slot,
        s_GetFriendsPopup, s_SetShowingFriendsPopup, s_AddViewportWidgetContent);

    // mprotect the page containing slot, write new value, restore protection
    long page_sz = sysconf(_SC_PAGESIZE);
    uintptr_t page_start = slot_addr & ~(uintptr_t)(page_sz - 1);
    if (mprotect((void*)page_start, page_sz, PROT_READ | PROT_WRITE) != 0) {
        perror("[ut4-friends-fix] mprotect RW");
        return false;
    }
    *slot = (void*)&ut4_friends_fix_Toggle;
    if (mprotect((void*)page_start, page_sz, PROT_READ) != 0) {
        perror("[ut4-friends-fix] mprotect R");
        // not fatal
    }
    fprintf(stderr, "[ut4-friends-fix] vtable slot 0x%lx now -> %p\n", slot_addr, *slot);
    return true;
}

static void watcher_thread()
{
    // UT4 modules are loaded lazily by UE4's module subsystem AFTER main(),
    // so the constructor can't see the .so. Poll until it appears.
    for (int i = 0; i < 600; ++i) { // up to 60s
        if (try_install_vtable_patch()) {
            s_patched.store(true);
            return;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    fprintf(stderr, "[ut4-friends-fix] gave up after 60s waiting for UT4 .so\n");
}

// LD_PRELOAD constructor
__attribute__((constructor))
static void ut4_friends_fix_init()
{
    s_shim_loaded_at = std::chrono::steady_clock::now();
    fprintf(stderr, "[ut4-friends-fix] loaded; starting watcher\n");
    // Detached thread polls for UT4 .so load
    std::thread(watcher_thread).detach();
}
