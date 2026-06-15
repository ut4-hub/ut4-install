# Base UT4 install: fetch the Linux client zip (preferring the GHCR mirror,
# with archive.org as the fallback the user can opt into via override), unpack,
# patch VivoxToken's executable-stack flag (modern kernels refuse to load it
# otherwise), and chmod the engine binaries executable.
{ pkgs, fetchOras }:
let
  inherit (pkgs)
    stdenv
    lib
    unzip
    patchelf
    coreutils
    ;

  build = "xan-3525360";
  upstreamUrl =
    "https://archive.org/download/unreal-tournament-4-pre-alpha/"
    + "UnrealTournament-Client-XAN-3525360-Linux.zip";

  # Placeholder. Replace with the real hash via:
  #   nix-prefetch-url <upstreamUrl>
  # before any release / real build. Eval still works with the placeholder.
  upstreamSha256 = "0000000000000000000000000000000000000000000000000000";

  source = fetchOras {
    reference = "ghcr.io/ut4-hub/client:${build}";
    sha256 = upstreamSha256;
  };
in
stdenv.mkDerivation {
  name = "ut4-base-${build}";
  src = source;

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
    # Clear executable-stack flag on VivoxToken so glibc dlopen accepts it on
    # modern kernels (default refuses RWE GNU_STACK).
    patchelf --clear-execstack \
      LinuxNoEditor/UnrealTournament/Plugins/NotForLicensees/VivoxToken/Binaries/Linux/libUE4-VivoxToken-Linux-Shipping.so
    chmod +x LinuxNoEditor/Engine/Binaries/Linux/UE4-Linux-Shipping
    chmod +x LinuxNoEditor/Engine/Binaries/Linux/UE4Server-Linux-Shipping || true
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r LinuxNoEditor $out/
    runHook postInstall
  '';

  meta = {
    description = "UT4 pre-alpha base install (XAN-3525360, Linux client)";
    homepage = "https://archive.org/details/unreal-tournament-4-pre-alpha";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.unfree; # Epic's; redistributed under abandonment precedent.
  };

  # Fallback metadata so consumers know where to find this without the mirror.
  passthru = {
    inherit upstreamUrl upstreamSha256 build;
  };
}
