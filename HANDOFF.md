# Handoff: ut4-hub scaffold

This repo was scaffolded autonomously by Claude on 2026-06-14 from a design
spec + implementation plan that live in
`/home/lucas/nix-config/docs/superpowers/{specs,plans}/`.

## Where things stand

### Completed (committed locally)

| Plan Task | What | Notes |
|-----------|------|-------|
| 1 | Bootstrap `flake.nix`, `flake.lock`, `.gitignore` | `nix flake check` passes |
| 2 | `pkgs/lib/fetchOras.nix` + `tests/eval.nix` | Helper for chunked OCI artifact fetches |
| 3 | `pkgs/ut4-base.nix` (eval-only) | Sha256 still placeholder — see Task 17 below |
| 4 | `pkgs/ut4-ut4uu.nix` | Real sha256 pinned; builds for real (~41 MB) |
| 5 | `pkgs/ut4-engine-ini-template.nix` | Builds; templates `master-ut4.timiimit.com` correctly |
| 6 | `pkgs/ut4-launcher.nix` | Builds; tested-equivalent to our nix-config launcher |
| 7 | `pkgs/ut4-client.nix` | `symlinkJoin` with `postBuild` GAME_ROOT fix (see review note below) |
| 8 | `pkgs/ut4-client-no-uu.nix` | Stock UT4 variant |
| 9 | `pkgs/ut4-server.nix` | Server-side launcher |
| 10 | Flake wired (`packages`, `apps`, `nixosModules.ut4Hub`, `overlays.default`) | `nix flake check` passes |
| 11 | `modules/ut4-hub-server.nix` + `tests/module-eval.nix` | Module evaluates with sops-friendly `tokenFile` option |
| 12 | `README.md` | Quickstart + 3 install patterns + provenance + ack + troubleshooting |
| 13 | `LICENSE` | MIT with Epic asset exclusion preamble |
| 14 | `.github/workflows/ci.yml` | Flake check + light builds on PR/push |
| 15 | `.github/workflows/mirror.yml` + `ci/push-mirror.sh` | Weekly chunked ORAS push to `ghcr.io/ut4-hub/client` |
| 16 | `.github/workflows/release.yml` | Release on `v*` tag |
| 19 | `tests/vm-hub.nix` | NixOS VM test for the module; wired into `checks.vm-hub` |

### Plan review note (deviation from plan)

The plan's Task 7 had a bug: it used `${placeholder "out"}/..` inside a
`writeShellApplication` to find `GAME_ROOT`, which resolves to the
*wrapperLayer*'s output, not the `symlinkJoin`'s. The implemented `ut4-client`
uses `postBuild` on the `symlinkJoin` so that `bash $out` is baked into the
wrapper at the join's own output path. Same fix applied in `ut4-client-no-uu`.

### Skipped — needs you

| Plan Task | What | Why skipped |
|-----------|------|-------------|
| 17 | Fill in real upstream sha256 in `pkgs/ut4-base.nix` | Requires the 11 GB archive.org download (`nix-prefetch-url`, ~1–2h). Heavy bandwidth — declined to run autonomously. **Easy step 1 when you return.** |
| 18 | Integration build of `ut4-client` (smoke test) | Same 11 GB download + ~25 GB free disk. Once Task 17 is done, run `nix build .#ut4-client -L` to validate end-to-end. |
| 20 | Publish to GitHub + Flakehub | Needs your GitHub auth and judgment calls (repo visibility, branch protection). |

### To pick up where this left off

1. **Pin the real upstream sha256:**
   ```bash
   nix-prefetch-url \
     "https://archive.org/download/unreal-tournament-4-pre-alpha/UnrealTournament-Client-XAN-3525360-Linux.zip"
   ```
   Wait ~1–2 hours. Take the printed sha256 (base32 format) and replace the
   `upstreamSha256 = "0000…";` line in `pkgs/ut4-base.nix`.

   Or use the sha256 in hex form via:
   ```bash
   curl -sL "<url>" | sha256sum
   ```
   and prefix with `sha256-` after base64-encoding (use `nix-hash --to-sri` to
   convert formats).

2. **Smoke test:**
   ```bash
   nix build .#ut4-client -L
   ./result/bin/ut4
   ```

3. **Create the GitHub repo and push:**
   ```bash
   gh repo create ut4-hub/ut4-hub --public \
     --description "NixOS flake for Unreal Tournament 4 pre-alpha (Linux, XAN-3525360)"
   git remote add origin git@github.com:ut4-hub/ut4-hub.git
   git push -u origin main
   ```

4. **Run the mirror workflow once manually** in GitHub Actions, wait ~1–2h
   for the chunked ORAS push to complete. Subsequent `ut4-base` builds will
   pull from `ghcr.io/ut4-hub/client:xan-3525360` instead of archive.org.

5. **Tag a release and submit to Flakehub:**
   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```
   Then add the repo at <https://flakehub.com>.

## Test status

- `nix flake check`: passes (post Task 11)
- `nix eval --raw -f tests/eval.nix`: prints `ok`
- `nix eval --raw -f tests/module-eval.nix`: prints `ok`
- `nix build .#checks.x86_64-linux.vm-hub`: running at handoff time; check
  `/tmp/claude-1000/.../tasks/b8r56gtoq.output` for status. If it succeeded,
  the module is end-to-end-verified. If not, see Notes below.

## Open questions for you

- Confirm `master-ut4.timiimit.com` as the default master server (currently
  hardcoded in `flake.nix`). Anyone wanting their own master server can
  override via the module option or by overlaying the launcher derivation.
- **Phase B scope** (separate spec, not started). Per 2026-06-15: includes
  - `master-prod`: self-hosted UT4MasterServer tracking `main`
  - `master-dev`: self-hosted UT4MasterServer tracking a branch/release tag
  - smoke tests against both (register / log in / register a hub / run a match)
  - `hub-against-timiimit`: deploy the `services.ut4Hub` module against
    timiimit's existing `master-ut4.timiimit.com` (proves the hub module
    end-to-end without depending on our own master being up first)
  Needs its own brainstorm on: hosting target (NixOS module vs Docker on a
  remote box vs deploy-rs to a fresh host), Cloudflare-tunnel topology, MongoDB
  state management, certificate strategy, dev/prod promotion workflow.

## References

- Spec: `~/nix-config/docs/superpowers/specs/2026-06-14-ut4-hub-flake-design.md`
- Plan: `~/nix-config/docs/superpowers/plans/2026-06-14-ut4-hub-flake.md`
- Upstream: <https://archive.org/details/unreal-tournament-4-pre-alpha>
- UT4UU: <https://github.com/timiimit/UT4UU-Public>
- Master server source: <https://github.com/timiimit/UT4MasterServer>
- Master server hub: <https://ut4.timiimit.com>
