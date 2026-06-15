# NixOS VM test for the services.ut4Hub module. Asserts the systemd unit
# starts, Engine.ini is rendered with the configured master server domain,
# and Server.ini contains the token read from masterServer.tokenFile.
#
# Uses a fake server binary that just sleeps, so the VM doesn't need the
# 11 GB ut4-base.
{
  pkgs ? import <nixpkgs> {
    config.allowUnfree = true;
  },
}:
pkgs.testers.nixosTest {
  name = "ut4-hub-server";

  nodes.machine =
    { ... }:
    {
      imports = [ ../modules/ut4-hub-server.nix ];

      services.ut4Hub = {
        enable = true;
        serverName = "VM Test Hub";
        masterServer.domain = "example.invalid";
        masterServer.tokenFile = pkgs.writeText "fake-token" "test-token-12345";
        package = pkgs.runCommand "fake-ut4-server" { } ''
          mkdir -p $out/bin
          cat > $out/bin/ut4-server <<'EOF'
          #!/bin/sh
          echo "fake ut4-server starting; args: $*"
          sleep 3600
          EOF
          chmod +x $out/bin/ut4-server
        '';
      };
    };

  testScript = ''
    machine.wait_for_unit("ut4-hub.service")
    machine.succeed("test -f /var/lib/ut4-hub/Documents/UnrealTournament/Saved/Config/LinuxServer/Engine.ini")
    machine.succeed("grep -q example.invalid /var/lib/ut4-hub/Documents/UnrealTournament/Saved/Config/LinuxServer/Engine.ini")
    machine.succeed("grep -q 'MasterServerToken=test-token-12345' /var/lib/ut4-hub/Documents/UnrealTournament/Saved/Config/LinuxServer/Server.ini")
    print("VM hub test passed.")
  '';
}
