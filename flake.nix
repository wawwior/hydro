{
  description = "";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    neat-flakes.url = "github:wawwior/neat-flakes";
    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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

          pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [ (import inputs.rust-overlay) ];
          };

          inherit (pkgs) lib;

          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain (
            pkgs:
            pkgs.rust-bin.selectLatestNightlyWith (
              toolchain:
              toolchain.default.override {
                targets = [
                  "x86_64-unknown-linux-gnu"
                  "aarch64-unknown-linux-gnu"
                  "x86_64-apple-darwin"
                  "aarch64-apple-darwin"
                ];
              }
            )
          );

          targetInfo = {
            "x86_64-linux" = {
              target = "x86_64-unknown-linux-gnu";
              interpreter = "/lib64/ld-linux-x86-64.so.2";
              flags = "-C link-arg=-fuse-ld=lld";
              dist-name = "linux-x86_64";
            };
            "aarch64-linux" = {
              target = "aarch64-unknown-linux-gnu";
              interpreter = "/lib/ld-linux-aarch64.so.1";
              flags = "";
              dist-name = "linux-aarch64";
            };
            "x86_64-darwin" = {
              target = "x86_64-apple-darwin";
              interpreter = "";
              flags = "";
              dist-name = "macos-intel";
            };
            "aarch64-darwin" = {
              target = "aarch64-apple-darwin";
              interpreter = "";
              flags = "";
              dist-name = "macos-arm";
            };
          };

          inherit (targetInfo.${system})
            target
            interpreter
            flags
            dist-name
            ;

          root = ./.;

          src = lib.fileset.toSource {
            inherit root;
            fileset = lib.fileset.unions [
              (craneLib.fileset.commonCargoSources root)
              (lib.fileset.maybeMissing ./assets)
            ];
          };

          crateName = (craneLib.crateNameFromCargoToml { cargoToml = ./Cargo.toml; }).pname;

          commonArgs = {
            inherit src;

            pname = "${crateName}-${dist-name}";

            strictDeps = true;
            doCheck = false;

            nativeBuildInputs = [
              pkgs.pkg-config
              pkgs.llvmPackages.bintools
            ];

            buildInputs = [

            ];
          };

          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          packages = rec {
            default = craneLib.buildPackage (
              commonArgs
              // {

                inherit cargoArtifacts;

                CARGO_BUILD_TARGET = target;

                cargoExtraArgs = "--no-default-features";
              }
              // lib.optionalAttrs (flags != "") {
                CARGO_BUILD_RUSTFLAGS = flags;
              }
              // lib.optionalAttrs (interpreter != "") {
                postFixup = ''
                  patchelf --set-interpreter ${interpreter} $out/bin/${crateName}
                '';
              }
            );
            tarball = mkTarball default;
          };

          mkTarball =
            package:
            pkgs.stdenv.mkDerivation rec {

              inherit (package) version;

              pname = "${package.pname}-archive";

              src = ./.;

              buildInputs = [ package ];

              buildPhase = ''
                mkdir $out
              '';

              installPhase = ''
                tar -cf ${pname}.tar.gz -C ${package}/bin .
                cp ${pname}.tar.gz $out
              '';

            };

        in
        {
          checks.${system} = {
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
                cargoClippyExtraArgs = "--all-targets -- --deny warnings";
              }
            );

            fmt = craneLib.cargoFmt {
              inherit src;
            };

            deny = craneLib.cargoDeny {
              inherit src;
            };
          }
          // packages;

          packages.${system} = packages;

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
