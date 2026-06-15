# ut4-hub

A NixOS flake that packages **Unreal Tournament 4 pre-alpha** (build
`XAN-3525360`, Linux client) so you can launch it with one command, and an
optional NixOS module to run a dedicated hub server. Master-server traffic
defaults to [master-ut4.timiimit.com](https://ut4.timiimit.com).

## Quickstart

```bash
nix run github:ut4-hub/ut4-hub
```

That's it. The first run downloads ~11 GB (extracted to ~22 GB) into your Nix
store. Subsequent runs are instant. You need `experimental-features =
nix-command flakes` in your Nix config.

## Install patterns

### Try once (ad-hoc)

```bash
nix run github:ut4-hub/ut4-hub
```

### Persistent install via home-manager

```nix
# flake.nix
inputs.ut4-hub.url = "github:ut4-hub/ut4-hub";

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
inputs.ut4-hub.url = "github:ut4-hub/ut4-hub";

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

## Provenance & legal

UT4 pre-alpha was an Epic Games project that was effectively abandoned in
2018. The cooked binaries were never explicitly licensed for redistribution.
This project relies on archive.org's long-standing community hosting and
Epic's de-facto tolerance.

- **Upstream canonical source:** <https://archive.org/details/unreal-tournament-4-pre-alpha>
- **GHCR mirror** (bit-for-bit identical, for cache locality): `ghcr.io/ut4-hub/client:xan-3525360`
- **DMCA / takedown contact:** `dmca@ut4-hub.example` ← **must be replaced with a real address before this repo is publicly announced**
- **License of this flake:** MIT (does **not** extend to Epic's assets)

If you're at Epic and want this taken down, please reach out via the contact
above; the flake is built to fall through to archive.org automatically so end
users won't notice.

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
github:ut4-hub/ut4-hub` to rebuild from the latest input.

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
