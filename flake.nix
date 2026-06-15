{
  description = "ut4-hub: Unreal Tournament 4 pre-alpha for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # The master server every component points at by default. NixOS module
        # consumers can override per-deployment via services.ut4Hub.masterServer.domain;
        # client-side users can also override at flake-input level by overlaying
        # ut4-launcher and ut4-engine-ini-template.
        masterServerDomain = "master-ut4.timiimit.com";

        fetchOras = import ./pkgs/lib/fetchOras.nix {
          inherit (pkgs) stdenv oras cacert;
        };

        ut4Base = import ./pkgs/ut4-base.nix {
          inherit pkgs fetchOras;
        };
        ut4UU = import ./pkgs/ut4-ut4uu.nix { inherit pkgs; };
        engineIni = import ./pkgs/ut4-engine-ini-template.nix {
          inherit pkgs masterServerDomain;
        };
        launcher = import ./pkgs/ut4-launcher.nix {
          inherit pkgs masterServerDomain;
        };
        ut4Client = import ./pkgs/ut4-client.nix {
          inherit
            pkgs
            ut4Base
            ut4UU
            engineIni
            launcher
            ;
        };
        ut4ClientNoUU = import ./pkgs/ut4-client-no-uu.nix {
          inherit
            pkgs
            ut4Base
            engineIni
            launcher
            ;
        };
        ut4Server = import ./pkgs/ut4-server.nix {
          inherit pkgs ut4Base;
        };
      in
      {
        packages = {
          ut4-client = ut4Client;
          ut4-client-no-uu = ut4ClientNoUU;
          ut4-server = ut4Server;
          default = ut4Client;
        };

        apps.default = {
          type = "app";
          program = "${ut4Client}/bin/ut4";
        };

        checks.vm-hub = import ./tests/vm-hub.nix { inherit pkgs; };
      }
    )
    // {
      nixosModules.ut4Hub = import ./modules/ut4-hub-server.nix;
      nixosModules.ut4MasterServer = import ./modules/ut4-master-server.nix;

      overlays.default = final: prev: {
        ut4-hub = {
          ut4-client = self.packages.${prev.system or "x86_64-linux"}.ut4-client;
          ut4-client-no-uu = self.packages.${prev.system or "x86_64-linux"}.ut4-client-no-uu;
          ut4-server = self.packages.${prev.system or "x86_64-linux"}.ut4-server;
        };
      };
    };
}
