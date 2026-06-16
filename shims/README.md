# UT4 LD_PRELOAD shims

Local-only experimentation. Each `.so` here hot-patches the running UT4
Linux client at load time without modifying the on-disk binary.

## libut4_friends_fix.so

**Status: WIP — fires correctly, still causes a delayed segfault on the
real click path.**

Re-enables the in-game friends popup on the Linux UT4 client, which
ships with `UUTLocalPlayer::ToggleFriendsAndChat` compiled to a 70-byte
stub on Linux (`#if PLATFORM_LINUX return FReply::Handled();` at
`UTLocalPlayer.cpp:6254`).

### Architecture

1. Constructor records load time + spawns a watcher thread (because
   the UT4 .so is loaded by UE4's module subsystem *after* main, so
   the constructor can't see it yet).
2. Watcher polls `dl_iterate_phdr` until
   `libUE4-UnrealTournament-Linux-Shipping.so` is loaded, then:
   - dlopens it with `RTLD_NOLOAD|RTLD_LAZY` to get a handle
   - resolves 5 symbols (`GetFriendsPopup`, `SetShowingFriendsPopup`,
     `AddViewportWidgetContent`, `GetGameInstance`, `GetGameViewportClient`)
   - computes the vtable slot at `load_base + 0x225b010 + 0x7f0`
     (verified via `readelf -r` — slot +0x7e0 is `PrevTutorial`, NOT
     `ToggleFriendsAndChat`)
   - mprotect + writes the slot to point at our replacement
3. Replacement is gated by a **15-second settle window**: early calls
   (LoginStatusChanged etc.) get a no-op `FReply::Handled()` like the
   original stub. After settle, real user clicks go through the popup
   construction path.

### Current failure mode

After settle, the chain `GetFriendsPopup → SetShowingFriendsPopup →
AddViewportWidgetContent` succeeds (widget gets added, no immediate
crash). The engine then crashes ~15 seconds later with `Signal=11`,
likely during the widget's first tick or render.

Looking at the source path the shipping client compiled out:
```cpp
FriendsMenu = GetFriendsPopup();
GEngine->GameViewport->AddViewportWidgetContent(
    SNew(SOverlay) + SOverlay::Slot() [ FriendsMenu.ToSharedRef() ],
    200);
```

We're skipping the `SNew(SOverlay) + SOverlay::Slot() [...]` wrapping
and passing the raw popup TSharedPtr directly. The unwrapped widget
can't be ticked/rendered safely inside the viewport overlay, leading
to the delayed crash.

### Open work to ship this

Implement the SOverlay wrap. Either:
- Construct `SOverlay` + `SOverlay::FSlot` via Slate's `SNew` macros at
  runtime (requires linking against UE4's Slate symbols correctly), or
- Find an existing UE4 helper that takes a single TSharedRef<SWidget>
  and wraps it for AddViewportWidgetContent (none spotted yet)
- Skip the AddViewportWidgetContent call entirely and try to use a
  different existing UE4 path (e.g. `OpenDialog`-style) — but the
  popup is not a `SUTDialogBase` so the existing dialog helpers don't
  apply

### Build

```
nix-shell -p gcc --run "g++ -shared -fPIC -O2 -pthread \
  -o libut4_friends_fix.so ut4_friends_fix.cpp -ldl -lpthread"
```

### Use

Edit `/home/lucas/Games/UT4/launch.sh`, uncomment the LD_PRELOAD line.
**Warning**: game will run normally for ~15s after a friends-button
click then segfault.

### What's verified

- Vtable address resolution: ✅ (verified via `readelf -r` for symbol
  `_ZN14UUTLocalPlayer20ToggleFriendsAndChatEv` reloc at `0x225b800`,
  slot offset `+0x7f0`)
- Symbol resolution: ✅ (all 5 helpers resolved via dlopen+dlsym)
- Vtable mprotect + write: ✅
- 15s settle window prevents init crashes: ✅
- Replacement fires on real user click after settle: ✅
  (`ToggleFriendsAndChat fired ... (elapsed=20s)`)
- Widget added to viewport: ✅ (no immediate failure)
- Widget actually renders without crashing engine: ❌

### Reference

Engine source for the function we're trying to re-enable:
`/home/lucas/code/unrealtournament/UnrealTournament/Source/UnrealTournament/Private/UTLocalPlayer.cpp:6252-6279`
