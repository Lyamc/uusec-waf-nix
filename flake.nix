{
  description = "Native NixOS module for UUSEC WAF";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forEach = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forEach (system: {
        default = nixpkgs.legacyPackages.${system}.callPackage ./nix/package.nix {
          libcrypt = nixpkgs.legacyPackages.${system}.libxcrypt-legacy;
        };
        uusec-waf = self.packages.${system}.default;
      });

      overlays.default = final: _prev: {
        uusec-waf = self.packages.${final.stdenv.hostPlatform.system}.default;
      };

      nixosModules.default = ./nix/module.nix;
      nixosModules.uusec-waf = self.nixosModules.default;
    };
}
