#!/usr/bin/env bash
# Apply the binary patches that ut4-install bakes into ut4-server.
#
# Use this when you already extracted the UT4 dedicated server zip yourself
# and want to apply the same patches the Nix flake applies during build,
# without rebuilding via Nix.
#
# Usage:
#   ./apply-binary-patches.sh /path/to/LinuxServer
#
# Patches applied (verified before and after):
#   1. AUTPartyBeaconHost::ProcessReservationRequest IsValid bypass
#      file:   UnrealTournament/Binaries/Linux/libUE4Server-UnrealTournament-Linux-Shipping.so
#      offset: 0x1036b2f
#      change: 74 11 (JZ short jump) -> 90 90 (NOPs)
#      why:    Ranked sessions return to UTEmptyServerGameMode after each
#              match. Without this NOP, the empty-mode server refuses
#              QuickPlay reservations with
#              "UTState->ReservationData.IsValid() == false". The patched
#              server still accepts reservations; pair with the watchdog
#              (UT4MasterServer/scripts/blitz-watchdog.sh) so it relaunches
#              into FlagRun before the client lands.
#
# Re-applying is safe (idempotent — already-patched bytes pass the after-check).

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/LinuxServer" >&2
  exit 2
fi

LINUX_SERVER=$1
if [[ ! -d $LINUX_SERVER ]]; then
  echo "error: $LINUX_SERVER is not a directory" >&2
  exit 2
fi

# --- Patch 1: AUTPartyBeaconHost::ProcessReservationRequest IsValid bypass ---

UTLIB="$LINUX_SERVER/UnrealTournament/Binaries/Linux/libUE4Server-UnrealTournament-Linux-Shipping.so"
OFFSET=0x1036b2f
EXPECTED=7411    # 74 11 = JZ short
REPLACEMENT=9090 # 90 90 = NOP NOP

if [[ ! -f $UTLIB ]]; then
  echo "error: $UTLIB not found — is this a valid LinuxServer directory?" >&2
  exit 2
fi

before=$(dd if="$UTLIB" bs=1 skip=$((OFFSET)) count=2 status=none | od -An -tx1 | tr -d ' \n')
case "$before" in
  "$EXPECTED")
    printf '\x90\x90' | dd of="$UTLIB" bs=1 seek=$((OFFSET)) count=2 conv=notrunc status=none
    after=$(dd if="$UTLIB" bs=1 skip=$((OFFSET)) count=2 status=none | od -An -tx1 | tr -d ' \n')
    if [[ $after != "$REPLACEMENT" ]]; then
      echo "patch1: write failed, bytes are '$after'" >&2
      exit 1
    fi
    echo "patch1: AUTPartyBeaconHost IsValid bypass applied"
    ;;
  "$REPLACEMENT")
    echo "patch1: already applied (bytes are '$REPLACEMENT'), skipping"
    ;;
  *)
    echo "patch1: offset $(printf '0x%x' $OFFSET) has unexpected bytes '$before' (expected '$EXPECTED')" >&2
    echo "  The upstream binary may have changed. Re-disassemble" >&2
    echo "  AUTPartyBeaconHost::ProcessReservationRequest and update the offset." >&2
    exit 1
    ;;
esac

echo "done."
