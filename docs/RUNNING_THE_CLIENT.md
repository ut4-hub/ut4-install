# Running the UT4 client

Step-by-step for getting the UT4 pre-alpha (`XAN-3525360`) Linux client up
and talking to a self-hosted master server.

For the full architecture, see [DEPLOYMENT.md](./DEPLOYMENT.md). This page
focuses on **what you need to install and run**.

## What you need

- A Linux machine (NixOS or any distro with Nix installed)
- About 25 GB of free disk space (the client zip is ~11 GB, extracts to ~22 GB)
- Network access to whichever master server you want to use (default:
  `master-ut4.timiimit.com`)
- For the dedicated-server path: another ~30 GB for the server zip
- Optional but recommended: a hybrid-GPU laptop will use NVIDIA Optimus
  automatically (`/proc/driver/nvidia`); pure-AMD/Intel machines work too

## Run the client (no install)

```bash
nix run github:ut4-hub/ut4-install
```

That's it. The first run downloads the game; subsequent runs are instant.

If you don't have flakes enabled in your Nix config, add this to
`~/.config/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

## Two client variants

```bash
# Stock client + UT4UU plugin (auth-token login dialog)
nix run github:ut4-hub/ut4-install#ut4-client

# Stock client without UT4UU (username/password login dialog — recommended)
nix run github:ut4-hub/ut4-install#ut4-client-no-uu
```

The **no-uu** path matches Epic's original 2017 login UX: enter your
username or email and password directly. The **uu** path requires
copy-pasting a long-lived auth token into the UT4UU dialog.

## Persistent install (home-manager)

```nix
# flake.nix
{
  inputs.ut4-hub.url = "github:ut4-hub/ut4-install";
}

# home.nix
{ inputs, pkgs, ... }: {
  home.packages = [
    inputs.ut4-hub.packages.${pkgs.system}.ut4-client-no-uu
  ];
}
```

Then `ut4` is available in your `$PATH`.

## What happens on first launch

The launcher:

1. Verifies the UE4 binary exists under `LinuxNoEditor/`
2. Seeds `~/Documents/UnrealTournament/Saved/Config/LinuxNoEditor/Engine.ini`
   from the bundled template (only if you don't have one yet — idempotent)
3. Detects NVIDIA via `/proc/driver/nvidia` and sets PRIME offload env vars
   if present
4. `exec`s `UE4-Linux-Shipping` under `steam-run` with `-opengl4`

The Engine.ini template redirects Epic prod hostnames to a master server.
By default this points at `master-ut4.timiimit.com`; override via the
`masterServerDomain` flake arg or by editing the seeded `Engine.ini`
post-install.

## Point the client at your own master server

Some Epic hostnames are hardcoded in the binary (`.rodata`). Engine.ini
can't redirect those — you need either:

1. **DNS hijack + local nginx** (the
   [`ut4-redirect`](https://github.com/itpick/nix-config/blob/main/modules/nixos/ut4-redirect/default.nix)
   NixOS module does this), or
2. **A reachable HTTPS master server** that matches the Epic hostname
   (impractical without controlling DNS / TLS for `*.epicgames.com`)

For local dev, the `ut4-redirect` module is the easiest path. See
[DEPLOYMENT.md § Hostname hijacking](./DEPLOYMENT.md#hostname-hijacking-via-nix-configs-ut4-redirect-module).

## Run a dedicated hub server

```bash
nix run github:ut4-hub/ut4-install#ut4-server -- \
  UnrealTournament 'FR-MeltDown?Game=/Script/UnrealTournament.UTFlagRunGame?MatchmakingSession=1?BotFill=10?MinPlayers=1?MaxPlayerWait=1?QuickMatch=1' \
  -epicapp=UnrealTournamentDev -epicenv=Prod -Unattended \
  -log -port=7779 -queryport=7789
```

The server package includes the AUTPartyBeaconHost binary patch (see
[DEPLOYMENT.md § Binary patches](./DEPLOYMENT.md#binary-patches)). For
QuickPlay support, pair it with the
[blitz-watchdog](https://github.com/ut4-hub/UT4MasterServer/blob/smoke-stack-integration/scripts/blitz-watchdog.sh)
to relaunch on match completion.

## Applying the binary patch to an existing install (no Nix)

If you already extracted the server zip yourself and don't want to
rebuild via Nix, run the standalone tool:

```bash
git clone https://github.com/ut4-hub/ut4-install
./ut4-install/scripts/apply-binary-patches.sh /path/to/your/LinuxServer
```

The script is idempotent (re-running on an already-patched install is a
no-op) and verifies the expected upstream bytes before writing — fails
loudly if the binary has changed.

## Troubleshooting

### Login dialog says "Please enter a valid email address"

`ut4-client-no-uu` requires master-server side support for password
grants. If the master returns an unhelpful error, check the API logs:

```bash
docker logs -f ut4ms-smoke-api 2>&1 | grep -i oauth
```

### Black screen / shader compile failures

The launcher uses `-opengl4`. On systems where this falls back to a broken
iGPU stack, you'll see dark rendering. Confirm NVIDIA detection:

```bash
# Inside steam-run:
__NV_PRIME_RENDER_OFFLOAD=1 glxinfo | grep "OpenGL renderer"
# Should report your dGPU
```

### Quick Play tile spins forever

Most often: no Ranked server is registered with the master. Check the
matchmaker DB:

```bash
docker exec ut4ms-smoke-mongo mongosh \
  "mongodb://smoke:smokepass@127.0.0.1:27017/?authSource=admin" \
  --quiet --eval 'db.getSiblingDB("ut4master").gameservers.find({}, {Name:1,Attributes:1}).pretty()'
```

You should see at least one server with `UT_RANKED_i: 1`. If not, the
dedicated server isn't reaching the master server's heartbeat endpoint.

### Announcement panel body box is just a spinner

That's a known UT4 client bug (`SUTWebBrowserPanel::Construct` never
invokes `ConstructPanel` for inline panels — CEF is never instantiated).
Workaround: set `MinHeight: 0` in
`UnrealTournmentMCPAnnouncement.json`. The title still renders. See
[UT4MasterServer's DEPLOYMENT doc](https://github.com/ut4-hub/UT4MasterServer/blob/smoke-stack-integration/docs/DEPLOYMENT.md#cloudstorage--motd--announcements)
for details.
