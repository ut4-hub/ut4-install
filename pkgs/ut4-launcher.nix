# UT4 client launcher: wraps UE4-Linux-Shipping under steam-run with the
# environment we determined empirically:
#   - SDL_VIDEODRIVER=x11 (UE4 has no native Wayland; route through XWayland)
#   - LD_LIBRARY_PATH augmented with nss/nspr/gconf/libxscrnsaver and the
#     engine's own Binaries/Linux dir (so plugin dlopens resolve UE4 Core)
#   - Launch flags: -SaveToUserDir -opengl4 -epicapp=UnrealTournamentDev
#     -epicenv=Prod -EpicPortal
#
# GAME_ROOT must be exported by the caller (the symlinkJoin wrapper does this).
{ pkgs, masterServerDomain }:
let
  inherit (pkgs)
    writeShellApplication
    steam-run
    nss
    nspr
    libxscrnsaver
    coreutils
    gnused
    ;
  gconf = pkgs.gnome2.GConf;
in
writeShellApplication {
  name = "ut4-launcher";
  runtimeInputs = [
    steam-run
    coreutils
    gnused
  ];
  text = ''
    set -euo pipefail

    : "''${GAME_ROOT:?GAME_ROOT not set; do not invoke ut4-launcher directly}"

    GAME="''${GAME_ROOT}/LinuxNoEditor"
    BIN="''${GAME}/Engine/Binaries/Linux/UE4-Linux-Shipping"

    if [[ ! -x "''${BIN}" ]]; then
      echo "UT4 binary missing or non-executable: ''${BIN}" >&2
      exit 1
    fi

    # Seed Engine.ini if the user doesn't have one yet (idempotent).
    USER_CFG="''${HOME}/Documents/UnrealTournament/Saved/Config/LinuxNoEditor"
    mkdir -p "''${USER_CFG}"
    if [[ ! -f "''${USER_CFG}/Engine.ini" ]]; then
      install -m 644 "''${GAME_ROOT}/share/ut4-hub/Engine.ini.template" "''${USER_CFG}/Engine.ini"
    fi

    # Seed UT4UU's master-server-domain config if UT4UU is present and the
    # user doesn't have one yet.
    UU_CFG="''${HOME}/Documents/UnrealTournament/Saved/UU"
    if [[ -d "''${GAME}/UnrealTournament/Plugins/UT4UU" ]]; then
      mkdir -p "''${UU_CFG}"
      if [[ ! -f "''${UU_CFG}/MasterServer.cfg" ]]; then
        echo "${masterServerDomain}" > "''${UU_CFG}/MasterServer.cfg"
      fi
    fi

    ENGINE_LIB="''${GAME}/Engine/Binaries/Linux"
    EXTRA_LD="${nss}/lib:${nspr}/lib:${gconf}/lib:${libxscrnsaver}/lib"

    # On hybrid-GPU laptops (NVIDIA Optimus / PRIME) the iGPU's OpenGL stack
    # rejects -opengl4 with shader compile failures. Detect NVIDIA at runtime
    # and route UE4 onto the discrete GPU.
    nvidia_env=()
    if [[ -e /proc/driver/nvidia ]]; then
      nvidia_env=(
        env
        __NV_PRIME_RENDER_OFFLOAD=1
        __GLX_VENDOR_LIBRARY_NAME=nvidia
        __VK_LAYER_NV_optimus=NVIDIA_only
        __GL_SYNC_TO_VBLANK=1
        vblank_mode=3
        mesa_glthread=false
      )
    fi

    cd "''${GAME}"
    SDL_VIDEODRIVER=x11 \
    LD_LIBRARY_PATH="''${ENGINE_LIB}:''${EXTRA_LD}:''${LD_LIBRARY_PATH:-}" \
    exec "''${nvidia_env[@]}" ${steam-run}/bin/steam-run \
      ./Engine/Binaries/Linux/UE4-Linux-Shipping \
      UnrealTournament -SaveToUserDir -opengl4 \
      -epicapp=UnrealTournamentDev -epicenv=Prod -EpicPortal "$@"
  '';
}
