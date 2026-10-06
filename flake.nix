{
  description = "nightlightd — zero-config screen colour temperature daemon for X11";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nix-community/naersk";
    naersk.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, naersk }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];

      mkPkg = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          naersk-lib = naersk.lib."${system}";
        in
        pkgs.callPackage ./nix/package.nix {
          inherit (pkgs) stdenv lib pkg-config patchelf
            libX11 libXrandr libXcursor libXi libxkbcommon mesa libglvnd;
          cargo = pkgs.cargo;
          rustc = pkgs.rustc;
          naersk = naersk-lib;
        };

      forAllSystems = f:
        builtins.listToAttrs (builtins.map (system: {
          name = system;
          value = f system;
        }) supportedSystems);
    in
    {
      packages = forAllSystems (system: {
        nightlightd = mkPkg system;
        default = self.packages.${system}.nightlightd;
      });

      apps = forAllSystems (system: rec {
        nightlightd = flake-utils.lib.mkApp {
          drv = self.packages.${system}.nightlightd;
          name = "nightlightd";
        };
        nightlight-tray = flake-utils.lib.mkApp {
          drv = self.packages.${system}.nightlightd;
          name = "nightlight-tray";
        };
        nightlight-panel = flake-utils.lib.mkApp {
          drv = self.packages.${system}.nightlightd;
          name = "nightlight-panel";
        };
        nightlight-tui = flake-utils.lib.mkApp {
          drv = self.packages.${system}.nightlightd;
          name = "nightlight-tui";
        };
      });
    };
}