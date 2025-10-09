{
  description = "";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    neat-flakes.url = "github:wawwior/neat-flakes";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    inputs@{ self, ... }:

    inputs.neat-flakes.lib.eachSystem
      [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ]
      (
        system:
        let

          pkgs = inputs.nixpkgs.legacyPackages.${system};

          craneLib = inputs.crane.mkLib pkgs;

          src = craneLib.cleanCargoSource ./.;

          commonArgs = {
            inherit src;
            strictDeps = true;

            buildInputs = [ ];
          };

          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          crane-package = craneLib.buildPackage (
            commonArgs
            // {
              inherit cargoArtifacts;
            }
          );
        in
        {
          checks.${system} = {
            inherit crane-package;

            clippy = craneLib.cargoClippy (
              commonArgs
              // {
                inherit cargoArtifacts;
              }
            );

            doc = craneLib.cargoDoc (
              commonArgs
              // {
                inherit cargoArtifacts;
              }
            );

            fmt = craneLib.cargoFmt {
              inherit src;
            };

            deny = craneLib.cargoDeny {
              inherit src;
            };
          };

          packages.${system} = {
            default = crane-package;
          };

          devShells.${system} = {
            default = craneLib.devShell {
              checks = self.checks.${system};

              packages = [
                pkgs.rust-analyzer
              ];
            };
          };
        }
      );
}
