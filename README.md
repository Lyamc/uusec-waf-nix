# uusec-waf-nix

NixOS module for [UUSEC WAF](https://github.com/Safe3/uusec-waf). It runs the upstream engine on the host. There is no Docker and no docker-compose.

Upstream does not publish the engine source. The `uusec/waf` image contains `/uuwaf/waf-service` (a static Go binary) and an OpenResty/nginx built with prefix `/uuwaf`. This package downloads that image by digest, unpacks `/uuwaf`, and points the dynamic linker at Nix libraries. MariaDB comes from NixOS.

The WAF binaries stay under the upstream GPL. The Nix expressions in this repository are MIT.

## Install

Channel-based NixOS:

```nix
{
  imports = [
    "${builtins.fetchTarball {
      url = "https://github.com/Lyamc/uusec-waf-nix/archive/main.tar.gz";
    }}/nix/module.nix"
  ];

  services.uusec-waf = {
    enable = true;
    openFirewall = true; # TCP 80, 443, and the admin UI on 4443
  };
}
```

Flake:

```nix
{
  inputs.uusec-waf-nix.url = "github:Lyamc/uusec-waf-nix";

  outputs = { nixpkgs, uusec-waf-nix, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      modules = [
        uusec-waf-nix.nixosModules.default
        {
          services.uusec-waf.enable = true;
          services.uusec-waf.openFirewall = true;
        }
      ];
    };
  };
}
```

`services.uusec-waf.enable = true` is enough. It enables MariaDB on `127.0.0.1:3306`, creates the `uuwaf` database, and generates `/var/lib/uusec-waf/db-password`.

Then open `https://<host>:4443`. The default account is `admin` / `#Passw0rd`.

## What is wired up

| Upstream container | This module |
| --- | --- |
| `uusec/waf` on the host network | `uusec-waf.service`, prefix `/uuwaf` |
| MySQL 5.7 on port 6612 | NixOS MariaDB on `127.0.0.1:3306` |
| `./waf_config` | `/var/lib/uusec-waf/web/conf` |
| `./waf_acme` | `/var/lib/uusec-waf/acme` |
| `./waf_logs` | `/var/lib/uusec-waf/logs` |
| nginx disk cache in `/tmp` | `/var/cache/uusec-waf` |

Ports 777 (captcha) and 4447 (local admin API) listen on the host and are not added to the firewall. Port 4443 is the management UI.

Stock nginx config is copied into `/var/lib/uusec-waf/conf` on first start and kept across rebuilds. The GeoIP database is refreshed from the package on each start. `resolver.conf` is rewritten from `services.uusec-waf.resolver`, or from the first `nameserver` in `/etc/resolv.conf`.

## Options

- `services.uusec-waf.openFirewall` opens 80, 443, and 4443.
- `services.uusec-waf.openProxyFirewall` opens only 80 and 443.
- `services.uusec-waf.openAdminFirewall` opens only 4443.
- `services.uusec-waf.language` sets `UUWAF_LANGUAGE` (`en` or `zh`).
- `services.uusec-waf.database.createLocal = false` plus `database.host`, `database.port`, `database.user`, and `database.passwordFile` uses a database you already run.

## Version

The packaged release is UUSEC WAF 7.2.5, image digest `sha256:d7061e418ed5dd705f084091edc8fbb75c73bf369a4674699fe55ad910c2c574`. Bump `nix/release.nix`, set `imageHash` to `lib.fakeHash`, build, and put the reported hash back.
