# ut4-hub

A NixOS flake that packages **Unreal Tournament 4 pre-alpha** (build
`XAN-3525360`, Linux client) so you can launch it with one command, and an
optional NixOS module to run a dedicated hub server. Master-server traffic
defaults to [master-ut4.timiimit.com](https://ut4.timiimit.com).

## Quickstart

```bash
nix run github:ut4-hub/ut4-install
```

That's it. The first run downloads ~11 GB (extracted to ~22 GB) into your Nix
store. Subsequent runs are instant. You need `experimental-features =
nix-command flakes` in your Nix config.

## Install patterns

### Try once (ad-hoc)

```bash
nix run github:ut4-hub/ut4-install
```

### Persistent install via home-manager

```nix
# flake.nix
inputs.ut4-hub.url = "github:ut4-hub/ut4-install";

# home.nix
{ inputs, pkgs, ... }: {
  home.packages = [
    inputs.ut4-hub.packages.${pkgs.system}.ut4-client
    # or: inputs.ut4-hub.packages.${pkgs.system}.ut4-client-no-uu
  ];
}
```

### NixOS module: run a dedicated server

```nix
# flake.nix
inputs.ut4-hub.url = "github:ut4-hub/ut4-install";

# configuration.nix
{ inputs, config, pkgs, ... }: {
  imports = [ inputs.ut4-hub.nixosModules.ut4Hub ];

  services.ut4Hub = {
    enable = true;
    package = inputs.ut4-hub.packages.${pkgs.system}.ut4-server;
    serverName = "My UT4 Hub";
    masterServer.domain = "master-ut4.timiimit.com";
    masterServer.tokenFile = config.sops.secrets.ut4-hub-token.path;
  };
}
```

Provide the master-server token via `sops-nix` or `agenix`:

```nix
sops.secrets.ut4-hub-token = {
  owner = "ut4";
  group = "ut4";
};
```

Get the token by registering a hub at <https://ut4.timiimit.com>.

## Provenance

The base game pak is a bit-for-bit copy of the publicly-archived
[UT4 pre-alpha on archive.org](https://archive.org/details/unreal-tournament-4-pre-alpha).
The GHCR mirror at `ghcr.io/ut4-hub/client:xan-3525360` exists purely for
faster downloads — the sha256 pinned in `flake.nix` matches archive.org's,
and the flake falls back to archive.org automatically if the mirror is
unavailable.

License of this flake: MIT. The license covers only the Nix code in this
repository — game assets remain Epic's IP and are fetched, not redistributed
under our license.

## Acknowledgments

- [**timiimit**](https://github.com/timiimit) for UT4UU, the
  [UT4MasterServer](https://github.com/timiimit/UT4MasterServer)
  re-implementation, and [ut4.timiimit.com](https://ut4.timiimit.com)
  hosting.
- [**archive.org**](https://archive.org) for keeping the pre-alpha alive.
- [**jmortley/netcodeplus-launcher**](https://github.com/jmortley/netcodeplus-launcher)
  — NetcodePlus is a separate ongoing community effort to improve UT4's
  online netcode. Watch that repo for upstream work we may want to integrate
  later.

## Troubleshooting

### "VivoxToken failed to load" / executable-stack errors

Already patched in `ut4-base` via `patchelf --clear-execstack`. If you see it
anyway, your `ut4-base` build is stale — `nix store gc && nix run
github:ut4-hub/ut4-install` to rebuild from the latest input.

### Hyprland: clicks don't reach the game window

Hyprland doesn't auto-focus new XWayland windows by default. Click on the UT4
window first, *then* press `~` for the console or click menus.

### Auth flow opens Epic's site instead of timiimit's

If you have UT4UU enabled (the default `ut4-client` package does), you need to
configure its master-server-domain via the **in-game console**: open the game,
press `~`, type `uu settings`, navigate to the **Other** tab, find **Master
Server Domain**, set it to `master-ut4.timiimit.com`, click **APPLY**, restart
the game. UT4UU does not honor the `Engine.ini` redirect — it stores its own
config separately.

If you're using `ut4-client-no-uu`, the `Engine.ini` redirect handles it
directly and you log in with credentials in the dialog.

### Black ground, torn lines, missing geometry (hybrid GPU laptops)

On laptops with both an integrated and discrete GPU (Framework AMD + NVIDIA
hybrid, Optimus, AMD APU + dGPU, etc.), the default `launch.sh` may run UT4 on
the iGPU, which can produce horizontal tearing lines and patches of unrendered
ground. Force the discrete GPU and try the OpenGL3 RHI:

```sh
# add to launch.sh before the exec line
__NV_PRIME_RENDER_OFFLOAD=1
__GLX_VENDOR_LIBRARY_NAME=nvidia       # NVIDIA dGPU
__VK_LAYER_NV_optimus=NVIDIA_only
__GL_SYNC_TO_VBLANK=1
vblank_mode=3
mesa_glthread=false

# and pass -opengl3 instead of -opengl4
```

Verify the GPU UT4 actually picked by tailing the log for `LogRHI: GL_RENDERER:`.
For AMD-only dGPU systems, drop the `__NV_*`/`__GLX_*` vars and instead use
`DRI_PRIME=1` to select the discrete adapter.

### "I really don't have my Engine.ini under ~/Documents/..."

The launcher seeds it on first run *only if it doesn't already exist*. If you
need to re-seed (e.g., after changing the master server domain), delete
`~/Documents/UnrealTournament/Saved/Config/LinuxNoEditor/Engine.ini` and
relaunch.

## Contributing

The flake is small. PRs welcome. The single hard constraint is that we never
host content that doesn't originate from a published, addressable archive
(archive.org or upstream GitHub releases). Don't propose checking in game
binaries to the repo itself; the GHCR mirror is the right place for that and
its content is reproducible from the upstream archive.org hash.

See `docs/` (TBD) for design and implementation plan documents.
