# NixOS module that runs the full UT4MasterServer stack (API + web UI +
# MongoDB) via virtualisation.oci-containers. Mirrors timiimit's
# docker-compose.yml architecture but as declarative NixOS containers.
#
# The container images are built+published by ut4-hub's CI from timiimit's
# upstream source (see .github/workflows/build-master-server.yml). Defaults
# point at ghcr.io/ut4-hub/master-server-* tags; override via options.
#
# This module does NOT terminate TLS — front it with cloudflared, nginx +
# acme, or whatever your host already runs. The API listens on `apiPort` and
# the web UI on `webPort`, both on localhost by default.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ut4MasterServer;

  # Subnet for the inter-container network. Single instance per host.
  networkName = "ut4ms-net";

  containerNames = {
    api = "ut4ms-api";
    web = "ut4ms-web";
    mongo = "ut4ms-mongo";
  };
in
{
  options.services.ut4MasterServer = {
    enable = lib.mkEnableOption "Unreal Tournament 4 Master Server stack";

    backend = lib.mkOption {
      type = lib.types.enum [
        "podman"
        "docker"
      ];
      default = "podman";
      description = "OCI container backend.";
    };

    environment = lib.mkOption {
      type = lib.types.enum [
        "Production"
        "Development"
      ];
      default = "Production";
      description = ''
        ASP.NET environment. Production hosts main; Development hosts a
        branch/release tag and is the right choice for the dev instance.
      '';
    };

    api = {
      image = lib.mkOption {
        type = lib.types.str;
        default = "ghcr.io/ut4-hub/master-server-api:main";
        example = "ghcr.io/ut4-hub/master-server-api:v0.3.0";
        description = "OCI image reference for the API service.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 5000;
        description = "Host port to expose the API on (bound to 127.0.0.1).";
      };
    };

    web = {
      image = lib.mkOption {
        type = lib.types.str;
        default = "ghcr.io/ut4-hub/master-server-web:main";
        example = "ghcr.io/ut4-hub/master-server-web:v0.3.0";
        description = "OCI image reference for the web UI service.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 5001;
        description = "Host port to expose the web UI on (bound to 127.0.0.1).";
      };
    };

    mongo = {
      image = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/library/mongo:7";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 27017;
        description = "Host port for the mongo server (bound to 127.0.0.1).";
      };
      database = lib.mkOption {
        type = lib.types.str;
        default = "ut4masterserver";
      };
      rootUsername = lib.mkOption {
        type = lib.types.str;
        default = "ut4ms";
      };
      rootPasswordFile = lib.mkOption {
        type = lib.types.path;
        description = ''
          File containing the MongoDB root password. Use sops-nix or agenix;
          never inline the password.
        '';
      };
      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/ut4-master-server/mongo";
      };
    };

    domain = lib.mkOption {
      type = lib.types.str;
      example = "master-ut4.example.com";
      description = ''
        Public domain the API will be served at. Used in CORS / OAuth
        redirect URL generation. TLS termination is handled outside this
        module (cloudflared, nginx, etc.).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.backend = cfg.backend;

    virtualisation.oci-containers.containers = {
      ${containerNames.mongo} = {
        image = cfg.mongo.image;
        environment = {
          MONGO_INITDB_ROOT_USERNAME = cfg.mongo.rootUsername;
          MONGO_INITDB_DATABASE = cfg.mongo.database;
        };
        environmentFiles = [
          # The systemd preStart hook writes this file from rootPasswordFile.
          "/run/ut4-master-server/mongo.env"
        ];
        volumes = [
          "${cfg.mongo.dataDir}:/data/db"
        ];
        ports = [
          "127.0.0.1:${toString cfg.mongo.port}:27017"
        ];
        extraOptions = [
          "--network=${networkName}"
          "--network-alias=mongo"
        ];
      };

      ${containerNames.api} = {
        image = cfg.api.image;
        environment = {
          ASPNETCORE_ENVIRONMENT = cfg.environment;
          UT4MS_PUBLIC_DOMAIN = cfg.domain;
        };
        environmentFiles = [
          "/run/ut4-master-server/api.env"
        ];
        ports = [
          "127.0.0.1:${toString cfg.api.port}:80"
        ];
        extraOptions = [
          "--network=${networkName}"
          "--network-alias=api"
        ];
        dependsOn = [ containerNames.mongo ];
      };

      ${containerNames.web} = {
        image = cfg.web.image;
        ports = [
          "127.0.0.1:${toString cfg.web.port}:8080"
        ];
        extraOptions = [
          "--network=${networkName}"
          "--network-alias=web"
        ];
      };
    };

    # The oci-containers backend doesn't auto-create user-defined networks,
    # so we do it ourselves before any container starts.
    systemd.services."ut4ms-network" = {
      description = "Create ut4-master-server container network";
      wantedBy = [ "multi-user.target" ];
      after = [ "${cfg.backend}.service" ];
      requires = [ "${cfg.backend}.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${cfg.backend} network exists ${networkName} \
          || ${cfg.backend} network create ${networkName}
      '';
      path = [ pkgs.${cfg.backend} ];
    };

    # Render secret-bearing env files at activation time. The password
    # *file* path is in /nix/store (safe); the secret content is read by
    # the systemd unit at start time and written to /run (tmpfs).
    systemd.services."ut4ms-secrets" = {
      description = "Materialize UT4MasterServer secrets";
      wantedBy = [ "multi-user.target" ];
      before = [
        "${cfg.backend}-${containerNames.mongo}.service"
        "${cfg.backend}-${containerNames.api}.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        mkdir -p /run/ut4-master-server
        chmod 0700 /run/ut4-master-server
        MONGO_PW=$(cat ${cfg.mongo.rootPasswordFile})
        printf 'MONGO_INITDB_ROOT_PASSWORD=%s\n' "$MONGO_PW" \
          > /run/ut4-master-server/mongo.env
        # API talks to mongo as the root user; same password.
        printf 'MongoDb__ConnectionString=mongodb://%s:%s@mongo:27017/%s?authSource=admin\n' \
          "${cfg.mongo.rootUsername}" "$MONGO_PW" "${cfg.mongo.database}" \
          > /run/ut4-master-server/api.env
        chmod 0600 /run/ut4-master-server/*.env
      '';
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.mongo.dataDir} 0700 root root - -"
    ];

    # Wire ordering: secrets → mongo → api/web.
    systemd.services."${cfg.backend}-${containerNames.mongo}" = {
      after = [
        "ut4ms-network.service"
        "ut4ms-secrets.service"
      ];
      requires = [
        "ut4ms-network.service"
        "ut4ms-secrets.service"
      ];
    };
    systemd.services."${cfg.backend}-${containerNames.api}" = {
      after = [
        "ut4ms-network.service"
        "ut4ms-secrets.service"
      ];
      requires = [
        "ut4ms-network.service"
        "ut4ms-secrets.service"
      ];
    };
    systemd.services."${cfg.backend}-${containerNames.web}" = {
      after = [ "ut4ms-network.service" ];
      requires = [ "ut4ms-network.service" ];
    };
  };
}
