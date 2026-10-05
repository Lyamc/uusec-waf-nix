# Native UUSEC WAF. The upstream project distributes the engine as a container
# image. This module runs that engine on the host.
#
#   imports = [ /path/to/uusec-waf-nix/nix/module.nix ];
#
#   services.uusec-waf = {
#     enable = true;
#     openFirewall = true;
#   };
#
# Admin UI: https://<host>:4443  (user admin, password #Passw0rd).
# Proxy listeners: 80 and 443. Captcha and the local admin API stay on
# 777 and 4447 and are not opened in the firewall.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.uusec-waf;

  package = cfg.package;

  firewallPorts = lib.optional cfg.openProxyFirewall 80
    ++ lib.optional cfg.openProxyFirewall 443
    ++ lib.optional cfg.openAdminFirewall 4443;
in
{
  options.services.uusec-waf = {
    enable = lib.mkEnableOption "UUSEC WAF";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix {
        libcrypt = pkgs.libxcrypt-legacy;
      };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The uusec-waf package. It unpacks the upstream release and patches its dynamic linker.";
    };

    prefix = lib.mkOption {
      type = lib.types.path;
      default = "/uuwaf";
      description = ''
        Absolute prefix the upstream binaries were built with.
        Changing this does not relocate the engine. nginx and waf-service
        look up /uuwaf unless this stays at the compiled prefix.
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/uusec-waf";
      description = "Mutable configuration, ACME data, logs, and the generated database password.";
    };

    cacheDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/cache/uusec-waf";
      description = "HTTP cache directory. The packaged nginx config points proxy_cache_path here.";
    };

    language = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "zh";
      description = "Value of UUWAF_LANGUAGE. Null leaves the upstream default.";
    };

    resolver = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "1.1.1.1";
      description = ''
        IP address written into nginx resolver.conf.
        Null uses the first nameserver in /etc/resolv.conf.
      '';
    };

    ipv6 = lib.mkEnableOption "IPv6 in the nginx resolver directive" // {
      default = false;
    };

    openProxyFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open TCP 80 and 443.";
    };

    openAdminFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open TCP 4443, the management UI.";
    };

    # Kept so `services.uusec-waf.openFirewall = true` does what people expect.
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open TCP 80, 443, and 4443.";
    };

    extraEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = lib.literalExpression ''
        {
          UUWAF_RESOLVER = "resolver 1.1.1.1 valid=30s ipv6=off;";
        }
      '';
      description = "Extra environment variables for waf-service.";
    };

    database = {
      createLocal = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable the NixOS MariaDB service, create the uuwaf database, and
          create a password user that can connect over TCP to 127.0.0.1.
        '';
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Database host used in UUWAF_DB_DSN.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 3306;
        description = "Database port used in UUWAF_DB_DSN.";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "uuwaf";
        description = "Database name.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "uuwaf";
        description = "Database user.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = "${cfg.stateDir}/db-password";
        defaultText = lib.literalExpression ''"''${stateDir}/db-password"'';
        description = ''
          File containing the database password, one line, no newline required.
          When createLocal is true and the file is missing, the service creates
          it with a random password. The password is not stored in the Nix store.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (cfg.prefix != "/uuwaf") ''
      services.uusec-waf.prefix is compiled into the upstream nginx as /uuwaf.
      Other prefixes will not relocate the engine.
    '';

    assertions = [
      {
        assertion = cfg.database.passwordFile != null || !cfg.database.createLocal;
        message = "services.uusec-waf.database.passwordFile is required when createLocal is true.";
      }
    ];

    networking.firewall.allowedTCPPorts = firewallPorts
      ++ lib.optionals cfg.openFirewall [ 80 443 4443 ];

    services.mysql = lib.mkIf cfg.database.createLocal {
      enable = true;
      package = lib.mkDefault pkgs.mariadb;
      ensureDatabases = [ cfg.database.name ];
      settings.mysqld = {
        bind-address = lib.mkDefault "127.0.0.1";
        port = lib.mkDefault cfg.database.port;
        max_connections = lib.mkDefault 512;
        skip-name-resolve = lib.mkDefault true;
      };
    };

    services.logrotate.settings."/var/lib/uusec-waf/logs/*.log" = {
      files = "${cfg.stateDir}/logs/*.log";
      frequency = "daily";
      rotate = 30;
      compress = true;
      missingok = true;
      notifempty = true;
      dateext = true;
      sharedscripts = true;
      postrotate = ''
        if [ -s ${cfg.stateDir}/logs/uuwaf.pid ]; then
          kill -USR1 "$(cat ${cfg.stateDir}/logs/uuwaf.pid)" 2>/dev/null || true
        fi
      '';
    };

    systemd.services.uusec-waf = {
      description = "UUSEC WAF";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ] ++ lib.optional cfg.database.createLocal "mysql.service";
      after = [ "network-online.target" ] ++ lib.optional cfg.database.createLocal "mysql.service";
      path = [
        pkgs.mariadb
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
      ];

      environment = {
        UUSEC_WAF_PREFIX = cfg.prefix;
        UUSEC_WAF_STATE = cfg.stateDir;
        UUSEC_WAF_CACHE = cfg.cacheDir;
        UUSEC_WAF_IPV6 = if cfg.ipv6 then "on" else "off";
        UUWAF_DB_HOST = cfg.database.host;
        UUWAF_DB_PORT = toString cfg.database.port;
        UUWAF_DB_USER = cfg.database.user;
        UUWAF_DB_NAME = cfg.database.name;
        ZONEINFO = "${pkgs.tzdata}/share/zoneinfo";
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      } // lib.optionalAttrs (cfg.resolver != null) {
        UUSEC_WAF_RESOLVER = cfg.resolver;
      } // lib.optionalAttrs (cfg.database.passwordFile != null) {
        UUWAF_DB_PASSWORD_FILE = cfg.database.passwordFile;
      } // lib.optionalAttrs (cfg.language != null) {
        UUWAF_LANGUAGE = cfg.language;
      } // cfg.extraEnv;

      preStart = ''
        set -eu
        install -d -m 0755 ${lib.escapeShellArg cfg.stateDir}
        install -d -m 0755 ${lib.escapeShellArg cfg.cacheDir}
        ${lib.optionalString cfg.database.createLocal ''
          if [ ! -s ${lib.escapeShellArg cfg.database.passwordFile} ]; then
            umask 077
            tr -dc A-Za-z0-9 < /dev/urandom | head -c 32 > ${lib.escapeShellArg cfg.database.passwordFile}
            chmod 600 ${lib.escapeShellArg cfg.database.passwordFile}
          fi
        ''}
        ${package}/bin/uusec-waf-prepare
        ${lib.optionalString cfg.database.createLocal ''
          pw=$(cat ${lib.escapeShellArg cfg.database.passwordFile})
          ${pkgs.util-linux}/bin/runuser -u ${config.services.mysql.user} -- \
            ${pkgs.mariadb}/bin/mysql -N <<SQL
          CREATE DATABASE IF NOT EXISTS \`${cfg.database.name}\` CHARACTER SET utf8mb4;
          CREATE USER IF NOT EXISTS '${cfg.database.user}'@'${cfg.database.host}' IDENTIFIED BY '$pw';
          ALTER USER '${cfg.database.user}'@'${cfg.database.host}' IDENTIFIED BY '$pw';
          GRANT ALL PRIVILEGES ON \`${cfg.database.name}\`.* TO '${cfg.database.user}'@'${cfg.database.host}';
          FLUSH PRIVILEGES;
          SQL
        ''}
      '';

      serviceConfig = {
        Type = "simple";
        ExecStart = "${package}/bin/uusec-waf";
        Restart = "on-failure";
        RestartSec = 3;
        TimeoutStopSec = "240s";
        LimitNOFILE = 102400;
        LimitNPROC = 65535;
        WorkingDirectory = cfg.prefix;
      };
    };
  };
}
