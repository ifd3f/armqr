{
  description = "QR Tattoo Redirector";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    naersk.url = "github:nix-community/naersk/master";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, utils, rust-overlay, naersk, ... }:
    let inherit (nixpkgs) lib;
    in {
      overlays = {
        default = final: prev: {
          inherit (self.packages.${prev.system}) armqr;
        };

        build = lib.composeManyExtensions [
          rust-overlay.overlays.default
          naersk.overlay
          (final: prev: {
            rust-toolchain = final.rust-bin.nightly."2022-11-04";
            naersk = prev.naersk.override {
              rustc = final.rust-toolchain.minimal;
              cargo = final.rust-toolchain.minimal;
            };

            armqr = with final;
              final.naersk.buildPackage {
                src = ./.;

                buildInputs = [ openssl.dev ];
                nativeBuildInputs = [ pkgconfig ];
                PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
              };
          })
        ];
      };

      nixosModules.default = import ./nixos-module.nix;

      nixosConfigurations.demo = lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.default
          ({ pkgs, lib, ... }: {
            system.stateVersion = "22.11";
            nixpkgs.overlays = [ self.overlays.default ];
            services.armqr = {
              enable = true;
              port = 14323;
            };
            users.users.dev = {
              isNormalUser = true;
              password = "password";
              extraGroups = [ "wheel" ];
            };
            security.sudo.wheelNeedsPassword = false;
            virtualisation.vmVariant = {
              virtualisation.forwardPorts = [{
                from = "host";
                host.port = 8080;
                guest.port = 14323;
              }];
            };
          })
        ];
      };
    } // utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.build ];
        };
      in rec {
        packages = {
          default = packages.armqr;
          armqr = pkgs.armqr;
          vm-demo = self.nixosConfigurations.demo.config.system.build.vm;
        };

        apps = {
          armqr = utils.lib.mkApp {
            name = "armqr";
            drv = packages.armqr;
          };
          default = apps.armqr;
        };

        devShells.default = with pkgs;
          mkShell {
            buildInputs = [
              (rust-toolchain.default.override {
                extensions = [ "rust-src" "rust-analysis" "clippy" "rustfmt" ];
              })
            ];
          };
      });
}
