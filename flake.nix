{
    description = "Minimal devshell flake for haskell";

    inputs.haskellNix.url = "github:input-output-hk/haskell.nix";
    inputs.nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    inputs.flake-utils.url = "github:hamishmack/flake-utils/hkm/nested-hydraJobs";
    inputs.iohk-nix.url = "github:input-output-hk/iohk-nix";

    outputs = { self, nixpkgs, flake-utils, haskellNix, iohk-nix }:
    let overlays = {
        inherit (iohk-nix.overlays) crypto;
        # add static-$pkg for a few packages to be able to pull them im explicitly.
        static-libs = (final: prev: {
          static-libsodium-vrf = final.libsodium-vrf.overrideDerivation (old: {
            configureFlags = old.configureFlags ++ [ "--disable-shared" ];
          });
          static-secp256k1 = final.secp256k1.overrideDerivation (old: {
            configureFlags = old.configureFlags ++ ["--enable-static" "--disable-shared" ];
          });
          static-gmp = (final.gmp.override { withStatic = true; }).overrideDerivation (old: {
            configureFlags = old.configureFlags ++ ["--enable-static" "--disable-shared" ];
          });
          static-openssl = (final.openssl.override { static = true; });
          static-zlib = final.zlib.override { shared = false; };
          static-pcre = final.pcre.override { shared = false; };
        });
         # the haskell inline-r package depends on internals of the R
         # project that have been hidden in R 4.2+. See
         # https://github.com/tweag/HaskellR/issues/374
         oldR = (final: prev: {
           R_4_1_3 = final.R.overrideDerivation (old: rec {
             version = "4.1.3";
             patches = []; # upstream patches will most likely break this build, as they are specific to a different version.
             src = final.fetchurl {
               url = "https://cran.r-project.org/src/base/R-${final.lib.versions.major version}/${old.pname}-${version}.tar.gz";
               sha256 = "sha256-Ff9bMzxhCUBgsqUunB2OxVzELdAp45yiKr2qkJUm/tY="; };
             });
         });
         cddl-tools = (final: prev: {
          cbor-diag = final.callPackage ./pkgs/cbor-diag { };
          cddl = final.callPackage ./pkgs/cddl { };
         });
       };
       supportedSystems = [
            "x86_64-linux"
            "x86_64-darwin"
            "aarch64-linux"
            "aarch64-darwin"
       ];
    in flake-utils.lib.eachSystem supportedSystems (system:
      let
           pkgs = import nixpkgs {
             overlays = [haskellNix.overlay] ++ builtins.attrValues overlays;
             inherit system;
             inherit (haskellNix) config;
           };
           # These are for checking IOG projects build in an environment
           # without haskell packages built by haskell.nix.
           #
           # Usage:
           #
           # nix develop github:input-output-hk/devx#ghc924 --no-write-lock-file -c cabal build
           #
           static-pkgs = if pkgs.stdenv.hostPlatform.isLinux
                         then if pkgs.stdenv.hostPlatform.isAarch64
                              then pkgs.pkgsCross.aarch64-multiplatform-musl
                              else pkgs.pkgsCross.musl64
                         else pkgs;
           js-pkgs = pkgs.pkgsCross.ghcjs;
           windows-pkgs = pkgs.pkgsCross.mingwW64;
           devShellsWithToolsModule = toolsModule:
             let compilers = pkgs: builtins.removeAttrs pkgs.haskell-nix.compiler
                # Exclude old versions of GHC to speed up `nix flake check`
                [ "ghc844"
                  "ghc861" "ghc862" "ghc863" "ghc864" "ghc865"
                  "ghc881" "ghc882" "ghc883" "ghc884"
                  "ghc8101" "ghc8102" "ghc8103" "ghc8104" "ghc8105" "ghc8106" "ghc810420210212"
                  "ghc901"
                  "ghc921" "ghc922" "ghc923" "ghc924" "ghc925" "ghc926" "ghc927"
                  "ghc941" "ghc942" "ghc943" "ghc944" "ghc945" "ghc946"
                  "ghc96020230302"
                  "ghc961"
                  "ghc9820230704"
                 ];
                 js-compilers = pkgs: builtins.removeAttrs (compilers pkgs)
                 [
                  "ghc902"
                  "ghc928"
                  "ghc947"
                 ];
                 windows-compilers = pkgs:
                   pkgs.lib.optionalAttrs (__elem system ["x86_64-linux"])
                   (builtins.removeAttrs (compilers pkgs)
                     [
                     ]);
             in (builtins.mapAttrs (compiler-nix-name: compiler:
                  import ./dynamic.nix { inherit pkgs self compiler compiler-nix-name toolsModule; withIOG = false; }
                  ) (compilers pkgs)
              // pkgs.lib.mapAttrs' (compiler-nix-name: compiler:
                  pkgs.lib.nameValuePair "${compiler-nix-name}-minimal" (
                    import ./dynamic.nix { inherit pkgs self compiler compiler-nix-name toolsModule; withHLS = false; withHlint = false; withIOG = false; }
                  )) (compilers pkgs)
              // pkgs.lib.mapAttrs' (compiler-nix-name: compiler:
                  pkgs.lib.nameValuePair "${compiler-nix-name}-static" (
                    import ./static.nix { pkgs = static-pkgs; inherit self compiler compiler-nix-name toolsModule; withIOG = false; }
                  )) (compilers static-pkgs.buildPackages)
              // pkgs.lib.mapAttrs' (compiler-nix-name: compiler:
                  pkgs.lib.nameValuePair "${compiler-nix-name}-static-minimal" (
                    import ./static.nix { pkgs = static-pkgs; inherit self compiler compiler-nix-name toolsModule; withHLS = false; withHlint = false; withIOG = false; }
                  )) (compilers static-pkgs.buildPackages)
              // pkgs.lib.mapAttrs' (compiler-nix-name: compiler:
                  pkgs.lib.nameValuePair "${compiler-nix-name}-js" (
                    import ./cross-js.nix { pkgs = js-pkgs.buildPackages; inherit self compiler compiler-nix-name toolsModule; }
                  )) (js-compilers js-pkgs.buildPackages)
              // pkgs.lib.mapAttrs' (compiler-nix-name: compiler:
                  pkgs.lib.nameValuePair "${compiler-nix-name}-js-minimal" (
                    import ./cross-js.nix { pkgs = js-pkgs.buildPackages; inherit self compiler compiler-nix-name toolsModule; withHLS = false; withHlint = false; }
                  )) (js-compilers js-pkgs.buildPackages)
              // pkgs.lib.mapAttrs' (compiler-nix-name: compiler:
                  pkgs.lib.nameValuePair "${compiler-nix-name}-windows" (
                    import ./cross-windows.nix { pkgs = windows-pkgs; inherit self compiler compiler-nix-name; }
                  )) (windows-compilers windows-pkgs.buildPackages)
              // pkgs.lib.mapAttrs' (compiler-nix-name: compiler:
                  pkgs.lib.nameValuePair "${compiler-nix-name}-windows-minimal" (
                    import ./cross-windows.nix { pkgs = windows-pkgs; inherit self compiler compiler-nix-name; withHLS = false; withHlint = false; }
                  )) (windows-compilers windows-pkgs.buildPackages)
              // pkgs.lib.mapAttrs' (compiler-nix-name: compiler:
                  pkgs.lib.nameValuePair "${compiler-nix-name}-iog" (
                    import ./dynamic.nix { inherit pkgs self compiler compiler-nix-name toolsModule; withIOG = true; }
                  )) (compilers pkgs)
              // pkgs.lib.mapAttrs' (compiler-nix-name: compiler:
                  pkgs.lib.nameValuePair "${compiler-nix-name}-minimal-iog" (
                    import ./dynamic.nix { inherit pkgs self compiler compiler-nix-name toolsModule; withHLS = false; withHlint = false; withIOG = true; }
                  )) (compilers pkgs)
              // pkgs.lib.mapAttrs' (compiler-nix-name: compiler:
                  pkgs.lib.nameValuePair "${compiler-nix-name}-static-iog" (
                    import ./static.nix { pkgs = static-pkgs; inherit self compiler compiler-nix-name toolsModule; withIOG = true; }
                  )) (compilers static-pkgs.buildPackages)
              // pkgs.lib.mapAttrs' (compiler-nix-name: compiler:
                  pkgs.lib.nameValuePair "${compiler-nix-name}-static-minimal-iog" (
                    import ./static.nix { pkgs = static-pkgs; inherit self compiler compiler-nix-name toolsModule; withHLS = false; withHlint = false; withIOG = true; }
                  )) (compilers static-pkgs.buildPackages)
              // pkgs.lib.mapAttrs' (compiler-nix-name: compiler:
                  pkgs.lib.nameValuePair "${compiler-nix-name}-js-iog" (
                    import ./cross-js.nix { pkgs = js-pkgs.buildPackages; inherit self compiler compiler-nix-name toolsModule; withIOG = true; }
                  )) (js-compilers js-pkgs.buildPackages)
              // pkgs.lib.mapAttrs' (compiler-nix-name: compiler:
                  pkgs.lib.nameValuePair "${compiler-nix-name}-js-minimal-iog" (
                    import ./cross-js.nix { pkgs = js-pkgs.buildPackages; inherit self compiler compiler-nix-name toolsModule; withHLS = false; withHlint = false; withIOG = true; }
                  )) (js-compilers js-pkgs.buildPackages)
              // pkgs.lib.mapAttrs' (compiler-nix-name: compiler:
                  pkgs.lib.nameValuePair "${compiler-nix-name}-windows-iog" (
                    import ./cross-windows.nix { pkgs = windows-pkgs; inherit self compiler compiler-nix-name; withIOG = true; }
                  )) (windows-compilers windows-pkgs.buildPackages)
              // pkgs.lib.mapAttrs' (compiler-nix-name: compiler:
                  pkgs.lib.nameValuePair "${compiler-nix-name}-windows-minimal-iog" (
                    import ./cross-windows.nix { pkgs = windows-pkgs; inherit self compiler compiler-nix-name; withHLS = false; withHlint = false; withIOG = true; }
                  )) (windows-compilers windows-pkgs.buildPackages)
             );
        devShells = devShellsWithToolsModule {};
        # Eval must be done on linux when we use hydra to build environment
        # scripts for other platforms.  That way a linux GHA can download the
        # cached files without needing access to the actual build platform.
        devShellsWithEvalOnLinux = devShellsWithToolsModule { evalSystem = "x86_64-linux"; };
      in {
        inherit devShells;
        hydraJobs = devShells // {
          # *-dev sentinel job. Singals all -env have been built.
          required = pkgs.runCommand "test-dependencies" {
              _hydraAggregate = true;
              constituents = map (name: "${system}.${name}-env") (builtins.attrNames devShellsWithEvalOnLinux);
            } "touch  $out";
          } // (pkgs.lib.mapAttrs' (name: drv:
            pkgs.lib.nameValuePair "${name}-env" (
            let env = pkgs.runCommand "${name}-env.sh" {
                requiredSystemFeatures = [ "recursive-nix" ];
                nativeBuildInputs = [ pkgs.nix ];
              } ''
              nix --offline --extra-experimental-features "nix-command flakes" \
                print-dev-env ${drv.drvPath} >> $out
            '';
            # this needs to be linux.  It would be great if we could have this
            # eval platform agnostic, but flakes don't permit this.  A the
            # platform where we build the docker images is linux (github
            # ubuntu runners), this needs to be evaluable on linux.
            in (import nixpkgs { system = "x86_64-linux"; }).writeTextFile {
              name = "devx";
              executable = true;
              text = ''
                #!/bin/bash

                set -euo pipefail

                source ${env}
                source "$1"
              '';
              meta = {
                description = "DevX shell";
                longDescription = ''
                  The DevX shell is supposed to be used with GitHub Actions, and
                  can be used by setting the default shell to:

                    shell: devx {0}
                '';
                homepage = "https://github.com/input-output-hk/devx";
                license = pkgs.lib.licenses.asl20;
                platforms = pkgs.lib.platforms.unix;
              };
            })) devShellsWithEvalOnLinux) // {
          };
        packages.cabalProjectLocal.static        = (import ./quirks.nix { pkgs = static-pkgs; static = true; }).template;
        packages.cabalProjectLocal.cross-js      = (import ./quirks.nix { pkgs = js-pkgs;                    }).template;
        packages.cabalProjectLocal.cross-windows = (import ./quirks.nix { pkgs = windows-pkgs;               }).template;
       });

    # --- Flake Local Nix Configuration ----------------------------
    nixConfig = {
      extra-substituters = [
        "https://cache.iog.io"
        # We only have zw3rk cache in here, because it provide aarch64-linux and aarch64-darwin.
        "https://cache.zw3rk.com"
      ];
      extra-trusted-public-keys = [
        "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
        "loony-tools:pr9m4BkM/5/eSTZlkQyRt57Jz7OMBxNSUiMC4FkcNfk="
      ];
      # post-build-hook = "./upload-to-cache.sh";
      allow-import-from-derivation = "true";
    };
    # --------------------------------------------------------------
}
