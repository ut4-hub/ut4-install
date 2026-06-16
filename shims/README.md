# UT4 LD_PRELOAD shims

Local-only experimentation. Each `.so` here hot-patches the running UT4
Linux client at load time without modifying the on-disk binary.

## libut4_friends_fix.so

**Status: WIP — works partially, causes delayed segfault.**

Re-enables the in-game friends popup on the Linux UT4 client, which
ships with `UUTLocalPlayer::ToggleFriendsAndChat` compiled to a 70-byte
stub on Linux (`#if PLATFORM_LINUX return FReply::Handled();` at
`UTLocalPlayer.cpp:6254`).

### What it does

1. Constructor spawns a watcher thread (because the UT4 .so is loaded by
   UE4's module subsystem _after_ main, so the constructor can't see it
   yet).
2. Watcher polls `dl_iterate_phdr` until `libUE4-UnrealTournament-Linux-Shipping.so`
   is loaded, then:
   - Resolves symbols (`GetFriendsPopup`, `SetShowingFriendsPopup`,
     `AddViewportWidgetContent`, `GetGameInstance`, `GetGameViewportClient`)
     via `dlopen(..., RTLD_NOLOAD)` + `dlsym`.
   - Computes the vtable slot for `UUTLocalPlayer::ToggleFriendsAndChat`
     at `load_base + 0x225b010 + 0x7f0`. (`+0x7f0`, NOT `+0x7e0` as one
     earlier analysis said — that slot is `PrevTutorial`.)
   - `mprotect` + writes the slot to point at our replacement.
3. Replacement constructs the friends popup, sets `bShowingFriendsMenu`,
   adds the widget to the viewport.

### Where it breaks today

The chain `GetFriendsPopup → SetShowingFriendsPopup → AddViewportWidgetContent`
returns successfully (no immediate crash), but the engine segfaults seconds
later — likely because we're passing the popup `TSharedPtr` to a function
that expects `TSharedRef`, and the ref-controller doesn't satisfy the
non-null invariant. The compiled `AddViewportWidgetContent` signature
takes a `TSharedRef<SWidget>` by value (16 bytes, passed in two regs);
our `TSharedPtr` from `GetFriendsPopup` may have a null ref controller.

To fix:
- Track the exact ABI of `TSharedRef` vs `TSharedPtr` and either upgrade
  the `TSharedPtr` to a `TSharedRef` manually, or call a different
  symbol that takes a `TSharedPtr`.
- Verify the viewport pointer is valid at click time (not yet validated).

### Build

```
nix-shell -p gcc --run "g++ -shared -fPIC -O2 -pthread \
  -o libut4_friends_fix.so ut4_friends_fix.cpp -ldl -lpthread"
```

### Use

Edit `/home/lucas/Games/UT4/launch.sh`, uncomment:

```
LD_PRELOAD=/home/lucas/Games/UT4-shims/libut4_friends_fix.so \
```

### What's verified

- Vtable address resolution: ✅ (verified via `readelf -r` for symbol
  `_ZN14UUTLocalPlayer20ToggleFriendsAndChatEv` reloc at `0x225b800`)
- Symbol resolution: ✅ (all 5 helpers resolved)
- Vtable mprotect + write: ✅
- Replacement fires on click: ✅ (`ToggleFriendsAndChat fired self=...`
  visible in client log)
- Widget actually renders: ❌ (crash)

### Reference

Engine source for the function we're trying to re-enable:
`/home/lucas/code/unrealtournament/UnrealTournament/Source/UnrealTournament/Private/UTLocalPlayer.cpp:6252-6279`
