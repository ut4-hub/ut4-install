# ut4-install — deployment guide

How the client+server packages in this flake fit into a working UT4
ecosystem, and how to wire them up against a self-hosted master server
(see [ut4-hub/UT4MasterServer](https://github.com/ut4-hub/UT4MasterServer)).

The sibling repo's [docs/DEPLOYMENT.md](https://github.com/ut4-hub/UT4MasterServer/blob/smoke-stack-integration/docs/DEPLOYMENT.md)
covers the master-server side. This document covers the client and
dedicated-server side — packaging, binary patches, and the auth + Quick
Play paths the game exercises against the master.

## Architecture

```
+---------------------+        +-------------------------+
|  UT4 client (Linux) |        |  UT4 dedicated server   |
|  XAN-3525360        |        |  XAN-3525360            |
|                     |        |                         |
|  pkgs/ut4-client    |        |  pkgs/ut4-server        |
|    -no-uu.nix       |        |    + ut4-server-base    |
+----------+----------+        +------------+------------+
           |                                |
   Engine.ini override                      | UE4Server -port 7779
           |                                |
           v                                v
   +------------------------------------------+
   |  nginx hostname hijack                   |
   |  (nix-config: modules/nixos/ut4-redirect)|
   |  intercepts Epic prod hostnames          |
   +-----------------+------------------------+
                     |
                     v
   +------------------------------------------+
   |  UT4MasterServer smoke stack (docker)    |
   |  - api  (.NET 6, port 5000)              |
   |  - web  (nginx, port 5001)               |
   |  - xmpp (ejabberd, port 5222)            |
   |  - mongo (port 27017)                    |
   |  - mailpit (dev SMTP, port 8025)         |
   +------------------------------------------+
```

## What this flake produces

| Output                          | What it is                                       |
|---------------------------------|--------------------------------------------------|
| `packages.ut4-client`           | Stock client + UT4UU plugin + Engine.ini template |
| `packages.ut4-client-no-uu`     | Stock client without UT4UU — the **login-without-auth-token path** |
| `packages.ut4-server`           | Dedicated server + AUTPartyBeaconHost binary patch baked in |
| `apps.default`                  | `nix run` → launches `ut4-client`                |
| `nixosModules.ut4Hub`           | Run a dedicated hub server as a systemd service  |
| `nixosModules.ut4MasterServer`  | Optional: pull the master-server containers      |

## The two client paths

Stock UT4 hardcodes Epic's MCP URLs. Two ways to redirect it at a self-hosted
master server:

### Path A — `ut4-client-no-uu` (recommended)

The stock client receives **username/email + password** directly in the login
dialog (no auth-token dance). Works because the master server's
`/account/api/oauth/token` accepts `grant_type=password` with a stock UT4
client.

- No third-party plugin needed
- Login UX matches Epic's original 2017 launcher
- Forgot-password flow is in-game-clickable (see *Forgot-password redirect*)

### Path B — `ut4-client` (UT4UU plugin)

Adds the [UT4UU](https://github.com/Letgam3rs/UT4UU) plugin, which provides
a Slate UI for entering a long-lived auth token. Required if your master
server doesn't accept password grants, otherwise just user-hostile.

## Engine.ini overrides

`pkgs/ut4-engine-ini-template.nix` produces an `Engine.ini` with `[URL]`
sections forcing the prod hostnames to your master server. The launcher
seeds this into `~/Documents/UnrealTournament/Saved/Config/LinuxNoEditor/`
on first run.

This handles **everything the binary doesn't hardcode in `strings`**. Hosts
the binary hardcodes (e.g. `friends-public-service-prod06.ol.epicgames.com`,
`xmpp-service-prod.ol.epicgames.com`) still need DNS-level interception — see
[ut4-redirect](#hostname-hijacking-via-nix-configs-ut4-redirect-module).

## Binary patches

Reproducible patches applied at derivation time via `dd` + `od` verify-then-flip.

### AUTPartyBeaconHost::IsValid bypass

- **File**: `libUE4Server-UnrealTournament-Linux-Shipping.so`
- **Offset**: `0x1036b2f`
- **Edit**: `74 11` (JZ short jump) → `90 90` (NOPs)
- **Why**: Ranked sessions transition the world to `UTEmptyServerGameMode`
  between matches. Without this patch, the empty-mode server rejects
  QuickPlay reservation requests with `UTState->ReservationData.IsValid() ==
  false`. The NOPs skip the validity check so the empty server still accepts
  reservations; the [blitz-watchdog](https://github.com/ut4-hub/UT4MasterServer/blob/smoke-stack-integration/scripts/blitz-watchdog.sh)
  takes care of restarting it into FlagRun mode for the next match.
- **Source**: [`pkgs/ut4-server-base.nix`](../pkgs/ut4-server-base.nix)
  (look for `partyBeaconPatch*`).
- **Build-time guard**: if the upstream bytes ever change, the build fails
  before patching — see the `dd | od -An -tx1` check.

## Quick Play end-to-end recipe

The in-game **Quick Play** tile (main menu → "Quick Play" → "Blitz") wants
a server that is:

1. Registered in matchmaker as `UT_RANKED_i=1` with a valid `UT_PLAYLISTID_i`
2. Currently accepting reservations (passes the AUTPartyBeaconHost check
   above)
3. Running the requested gamemode (`UTFlagRunGame` for Blitz)

This flake's `ut4-server`, combined with the master server's auto-inject +
auto-promote logic, gets you there. Launch the dedicated server with:

```
URL='FR-MeltDown?Game=/Script/UnrealTournament.UTFlagRunGame?MaxPlayers=10?MatchmakingSession=1?BotFill=10?MinPlayers=1?MaxPlayerWait=1?QuickMatch=1'
ut4-server UnrealTournament "$URL" \
  -epicapp=UnrealTournamentDev -epicenv=Prod -Unattended \
  -log -port=7779 -queryport=7789
```

Key URL params (each is mandatory):

| Param                     | Purpose                                                  |
|---------------------------|----------------------------------------------------------|
| `?MatchmakingSession=1`   | Spawns `AUTGameSessionRanked` (the class that creates `AUTPartyBeaconHost`) |
| `?BotFill=N`              | Auto-fills bots up to N players                          |
| `?MinPlayers=1`           | Starts the match with only one human                     |
| `?MaxPlayerWait=1`        | Triggers the bot fill timer after 1 second               |
| `?QuickMatch=1`           | Flags the session as QuickPlay-eligible                  |

Server flags:

| Flag           | Purpose                                                       |
|----------------|---------------------------------------------------------------|
| `-Unattended`  | Bypasses `CheckForPossibleRestart` (otherwise restarts at 60s)|
| `-port=7779`   | Game traffic                                                  |
| `-queryport=7789` | Status / heartbeat                                         |

Wrap this with the watchdog so it survives match completion:
[`blitz-watchdog.sh`](https://github.com/ut4-hub/UT4MasterServer/blob/smoke-stack-integration/scripts/blitz-watchdog.sh)
(env-var configurable).

## Hostname hijacking via nix-config's ut4-redirect module

Engine.ini can't override hostnames the binary embeds in `.rodata`. Those
require DNS hijack + a local nginx with a wildcard cert.

The `ut4-redirect` module in `nix-config` (host module) does this for
`*.epicgames.com` traffic and proxies it at:
- `:443` → local master server (`127.0.0.1:5000`)
- `:5222` → local ejabberd (`127.0.0.1:5222`)

If you're not using that module, you need an equivalent: hijack
`*-public-service-*.ol.epicgames.com` and proxy to your master server.

**TLS SAN gotcha**: the wildcard `*.epicgames.com` does **not** cover
`friends-public-service-prod06.ol.epicgames.com` — wildcard is one label
deep. Either issue separate per-service certs or use `*.ol.epicgames.com`
(also one label, so still misses second-level subdomains — issue an
explicit SAN for each prod service).

## Smoke test

```
# Client comes up and shows the master-server login page:
nix run github:ut4-hub/ut4-install#ut4-client-no-uu

# Server registers in matchmaker and accepts QuickPlay reservations:
nix run github:ut4-hub/ut4-install#ut4-server -- \
  UnrealTournament 'FR-MeltDown?Game=/Script/UnrealTournament.UTFlagRunGame?MatchmakingSession=1?BotFill=10?MinPlayers=1?MaxPlayerWait=1?QuickMatch=1' \
  -epicapp=UnrealTournamentDev -epicenv=Prod -Unattended -log -port=7779

# Master server's matchmaker GET returns your server with auto-injected attrs:
curl 'http://127.0.0.1:5000/ut/api/matchmaking/session/matchMakingRequest?keyName=UT_PLAYLISTID_i&keyValue=51'
```

## NixOS module: dedicated hub

```nix
{ inputs, ... }: {
  imports = [ inputs.ut4-hub.nixosModules.ut4Hub ];

  services.ut4Hub = {
    enable = true;
    serverName = "Dallas Pick Blitz";
    map = "FR-MeltDown";
    gameMode = "/Script/UnrealTournament.UTFlagRunGame";
    port = 7779;
    queryPort = 7789;
    masterServer.domain = "your-master.example.com";
  };
}
```

The module composes `ut4-server` (binary patch included) + a systemd unit
that runs the launcher under the watchdog pattern.
