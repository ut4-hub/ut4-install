# Dedicated-server base install: fetched separately from the client because
# archive.org hosts the server as a distinct ~870MB zip
# (UnrealTournament-Server-XAN-3525360-Linux.zip). The server zip extracts to
# LinuxServer/ (not LinuxNoEditor/).
#
# Patches applied:
#   - execstack cleared on RWE .so files (kernel refuses RWE GNU_STACK)
#   - UE4Server-Linux-Shipping chmod +x
{ pkgs }:
let
  inherit (pkgs)
    stdenv
    lib
    fetchurl
    unzip
    coreutils
    ;
  # `--clear-execstack` was added in patchelf 0.18 (nixpkgs default is 0.15).
  patchelf = pkgs.patchelfUnstable;

  build = "xan-3525360";
  upstreamUrl =
    "https://archive.org/download/unreal-tournament-4-pre-alpha/"
    + "UnrealTournament-Server-XAN-3525360-Linux.zip";
  # Hash verified locally on 2026-06-15 against archive.org artifact.
  upstreamSha256 = "sha256-dS/l3IYrWLhTDv3sFLybCpMneu2NaNysCZQ84vNKrPM=";
in
stdenv.mkDerivation {
  name = "ut4-server-base-${build}";

  src = fetchurl {
    url = upstreamUrl;
    sha256 = upstreamSha256;
  };

  nativeBuildInputs = [
    unzip
    patchelf
    coreutils
  ];

  unpackPhase = ''
    runHook preUnpack
    unzip -q $src
    runHook postUnpack
  '';

  buildPhase = ''
    runHook preBuild
    # Clear executable-stack flag on every .so that has GNU_STACK = RWE so
    # modern kernels accept the dlopen calls.
    find LinuxServer -type f -name '*.so' | while read -r so; do
      if readelf -lW "$so" 2>/dev/null | awk '/GNU_STACK/ && $7=="RWE" {found=1} END{exit !found}'; then
        patchelf --clear-execstack "$so"
      fi
    done
    chmod +x LinuxServer/Engine/Binaries/Linux/UE4Server-Linux-Shipping
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r LinuxServer $out/
    runHook postInstall
  '';

  meta = {
    description = "UT4 pre-alpha dedicated server install (XAN-3525360, Linux)";
    homepage = "https://archive.org/details/unreal-tournament-4-pre-alpha";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.unfree;
  };

  passthru = {
    inherit upstreamUrl upstreamSha256 build;
  };
}
