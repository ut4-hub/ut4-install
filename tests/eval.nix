# Pure eval tests for ut4-hub derivations. These don't realize anything (no
# network, no build); they only check that derivations evaluate to expected
# names and that fixed-output hashes match what's pinned.
#
# Run: nix eval --raw -f tests/eval.nix
(
  {
    pkgs ? import <nixpkgs> {
      config.allowUnfree = true;
    },
  }:
  let
    fetchOras = import ../pkgs/lib/fetchOras.nix {
      inherit (pkgs) stdenv oras cacert;
    };

    # 1. fetchOras emits a derivation with the expected outputHash and name.
    fetchOrasResult = fetchOras {
      reference = "ghcr.io/example/test:latest";
      sha256 = "0000000000000000000000000000000000000000000000000000";
    };
  in
  assert fetchOrasResult.outputHash == "0000000000000000000000000000000000000000000000000000";
  # Nix sanitizes colons in derivation names to hyphens.
  assert fetchOrasResult.name == "fetchOras-test-latest";
  "ok"
)
{ }
