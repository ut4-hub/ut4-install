#!/usr/bin/env bash
# Fetch the UT4 client zip from archive.org, verify the pinned sha256, chunk
# it, and push to ghcr.io/ut4-hub/client as an ORAS artifact with provenance
# annotations.
#
# Required env:
#   EXPECTED_SHA256 - the sha256 (hex) pinned in pkgs/ut4-base.nix
#   GITHUB_TOKEN    - injected by GitHub Actions
#   GITHUB_ACTOR    - injected by GitHub Actions
#
# Optional env:
#   TAG       - artifact tag (default: xan-3525360)
#   REGISTRY  - registry path (default: ghcr.io/ut4-hub/client)
set -euo pipefail

UPSTREAM_URL="https://archive.org/download/unreal-tournament-4-pre-alpha/UnrealTournament-Client-XAN-3525360-Linux.zip"
EXPECTED_SHA256="${EXPECTED_SHA256:-}"
TAG="${TAG:-xan-3525360}"
REGISTRY="${REGISTRY:-ghcr.io/ut4-hub/client}"
CHUNK_BYTES=$(( 4 * 1024 * 1024 * 1024 ))  # 4 GiB chunks (under GHCR's ~5 GB cap)

if [[ -z "${EXPECTED_SHA256}" ]]; then
  echo "EXPECTED_SHA256 must be set" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

echo "→ Fetching upstream zip..."
curl -fL --retry 5 --retry-delay 5 -o "${work}/client.zip" "${UPSTREAM_URL}"

echo "→ Verifying sha256..."
actual=$(sha256sum "${work}/client.zip" | awk '{print $1}')
if [[ "${actual}" != "${EXPECTED_SHA256}" ]]; then
  echo "Hash mismatch!" >&2
  echo "  Expected: ${EXPECTED_SHA256}" >&2
  echo "  Got:      ${actual}" >&2
  exit 1
fi
echo "  ok"

echo "→ Splitting into chunks of ${CHUNK_BYTES} bytes..."
mkdir -p "${work}/chunks"
split -b "${CHUNK_BYTES}" -d -a 1 "${work}/client.zip" "${work}/chunks/part-"

echo "→ Authenticating to GHCR..."
echo "${GITHUB_TOKEN}" | oras login ghcr.io -u "${GITHUB_ACTOR}" --password-stdin

echo "→ Pushing artifact ${REGISTRY}:${TAG}..."
pushd "${work}/chunks" >/dev/null
oras push "${REGISTRY}:${TAG}" \
  --artifact-type "application/vnd.ut4-hub.client+zip" \
  --annotation "org.opencontainers.image.source=https://github.com/ut4-hub/ut4-install" \
  --annotation "io.ut4-hub.upstream.url=${UPSTREAM_URL}" \
  --annotation "io.ut4-hub.upstream.sha256=${EXPECTED_SHA256}" \
  --annotation "io.ut4-hub.upstream.fetched-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --annotation "io.ut4-hub.purpose=Faster mirror of the archive.org-hosted UT4 pre-alpha (same sha256 as upstream)." \
  part-*
popd >/dev/null

echo "✓ Pushed ${REGISTRY}:${TAG}"
