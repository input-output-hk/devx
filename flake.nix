{
    description = "Minimal devshell flake for haskell";

    inputs.haskellNix.url = "github:input-output-hk/haskell.nix";
    inputs.nixpkgs.follows = "haskellNix/nixpkgs-2511";
    inputs.flake-utils.url = "github:numtide/flake-utils";
    inputs.iohk-nix.url = "github:input-output-hk/iohk-nix";
    inputs.cabal.url = "github:stable-haskell/cabal";
    inputs.cabal.flake = false;
    inputs.cabal-experimental.url = "github:stable-haskell/cabal?ref=stable-haskell/feature/cross-compile";
    inputs.cabal-experimental.flake = false;

    outputs = { self, nixpkgs, flake-utils, haskellNix, iohk-nix, ... }:
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
          static-libblst = final.libblst.overrideDerivation (old: {
            configureFlags = old.configureFlags ++ [ "--enable-static" "--disable-shared" ];
            buildPhase = ''
              runHook preBuild
              ./build.sh
              runHook postBuild
            '';
            postFixup = "";
          });
         });

         # nixpkgs defines happy = justStaticExecutables haskellPackages.happy
         # which sets disallowGhcReference = true. In nixpkgs-2511, this causes
         # the build to fail because the happy binary transitively references GHC
         # through happy-lib (happy -> happy-lib -> ghc). The postFixup only
         # removes $out/lib but cannot break the reference chain through happy-lib
         # which lives in the Nix store. We override to disable the GHC reference
         # check while keeping the rest of justStaticExecutables behavior.
         build-fixes = (final: prev: {
           happy = final.haskell.lib.compose.overrideCabal (drv: {
             disallowGhcReference = false;
           }) prev.happy;
         });

         cddl-tools = (final: prev: {
          cbor-diag = final.callPackage ./pkgs/cbor-diag { };
          cddl = final.callPackage ./pkgs/cddl { };
         });

         musl = (final: prev: prev.lib.optionalAttrs prev.stdenv.hostPlatform.isMusl {
           # We don't need a ruby static build. We're only interested in producing static
           # outputs, not necessarily build tools.
           ruby = prev.pkgsBuildBuild.ruby;

           # OpenSSL 3.6.0 test 82-test_ocsp_cert_chain.t fails in the nix sandbox
           # because the OCSP stapling test requires network/timing conditions that
           # aren't reliably available during cross-compilation builds. Only 1 of 3888
           # tests fails, and it's unrelated to the actual crypto functionality.
           openssl = prev.openssl.overrideAttrs (old: {
             preCheck = (old.preCheck or "") + ''
               rm -f test/recipes/82-test_ocsp_cert_chain.t
             '';
           });

           # PostgreSQL fixes for musl cross-compilation:
           #
           # nixpkgs-2511 postgresql/generic.nix has multiple issues with
           # musl64 because pkgsCross.musl64 doesn't set isStatic=true:
           #
           # 1. jitSupport defaults true → pulls in LLVM build inputs.
           # 2. perlSupport defaults true → musl perl lacks shared libperl.
           # 3. pythonSupport/tclSupport default true → adds plpython3/pltcl
           #    outputs. These are unnecessary for musl cross-builds and
           #    each extra output widens the nix-copy window, exacerbating
           #    the min-free GC race on darwin builders.
           # 4. generic.nix switches to LLVM stdenv+bintools for LTO when
           #    GCC is used. Cross-compiled LLVM 20 OOMs on darwin builders.
           #    We override llvmPackages_20 to prevent the switch (avoids
           #    LLVM dependency), then explicitly disable LTO with -fno-lto
           #    since GCC LTO + GNU ld is broken for postgresql (.ltrans
           #    link failures). Can't use hardeningDisable=["lto"] because
           #    "lto" is not a recognized hardening flag on musl cross.
           # 5. outputChecks unconditionally reference llvmPackages.llvm.
           postgresql = (prev.postgresql.override {
             jitSupport = false;
             perlSupport = false;
             pythonSupport = false;
             tclSupport = false;
             # Prevent the LTO stdenv switch: provide normal GCC-based
             # musl stdenv as llvmPackages_20, making the switch a no-op.
             llvmPackages_20 = prev.llvmPackages_20 // {
               inherit (prev) stdenv;
               bintools = prev.stdenv.cc.bintools;
             };
           }).overrideAttrs (old: {
             # Explicitly disable LTO since we're using GCC + GNU ld
             # (not the LLVM bintools the stdenv switch would provide).
             env = (old.env or {}) // {
               NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " -fno-lto";
             };
             doCheck = false;
             outputChecks = {};
             separateDebugInfo = false;
             disallowedReferences = [];
             # Break multi-output reference cycles. Nix refuses to register
             # outputs that form cycles. The cycles are:
             #   dev ↔ out: dev has .pc files referencing out; out has
             #              baked-in dev paths from configure
             #   lib ↔ out: lib has embedded out paths (share/locale refs
             #              in libpq); out links against lib
             # Fix: strip dev refs from out+lib, strip out refs from lib.
             # out→lib is the only legitimate runtime dependency.
             postFixup = (old.postFixup or "") + ''
               find "$out" -name '*.la' -delete
               find "$out" -type f -exec remove-references-to -t "$dev" {} +
               find "$lib" -name '*.la' -delete
               find "$lib" -type f -exec remove-references-to -t "$dev" {} +
               find "$lib" -type f -exec remove-references-to -t "$out" {} +
             '';
           });
         });
       };
       supportedSystems = [
            "x86_64-linux"
            "x86_64-darwin"
            "aarch64-linux"
            "aarch64-darwin"
       ];
    in let flake-outputs = flake-utils.lib.eachSystem supportedSystems (system:
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
           # nix develop github:input-output-hk/devx#ghc96 --no-write-lock-file -c cabal build
           #
           static-pkgs = if pkgs.stdenv.hostPlatform.isLinux
                         then if pkgs.stdenv.hostPlatform.isAarch64
                              then pkgs.pkgsCross.aarch64-multiplatform-musl
                              else pkgs.pkgsCross.musl64
                         else pkgs;
           js-pkgs = pkgs.pkgsCross.ghcjs;
           windows-pkgs = pkgs.pkgsCross.mingwW64;
           devShellsWithToolsModule = toolsModule:
             # Map the compiler-nix-name to a final compiler-nix-name the way haskell.nix
             # projects do (that way we can use short names)
             let compilers = pkgs: pkgs.lib.genAttrs [
                      "ghc96"
                      "ghc98"
                      "ghc910"
                      "ghc912"] (short-name: rec {
                         inherit pkgs self toolsModule;
                         compiler-nix-name = pkgs.haskell-nix.resolve-compiler-name short-name;
                         compiler = pkgs.buildPackages.haskell-nix.compiler.${compiler-nix-name};
                       });
                 js-compilers = pkgs: builtins.removeAttrs (compilers pkgs)
                 [
                  "ghc90"
                  "ghc92"
                  "ghc94"
                  "ghc910"
                 ];
                 # Windows cross-compilation disabled pending nixpkgs-2511
                 # crossThreadsStdenv fix (mcfgthread/pthreads bootstrap).
                 windows-compilers = _pkgs: {};
             in (builtins.mapAttrs (short-name: args:
                  import ./dynamic.nix (args // { withIOG = false; })
                  ) (compilers pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-minimal" (
                    import ./dynamic.nix (args // { withHLS = false; withHlint = false; withIOG = false; })
                  )) (compilers pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-minimal-ghc" (
                    import ./dynamic.nix (args // { withHLS = false; withHlint = false; withIOG = false; withGHCTooling = true; })
                  )) (compilers pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-static" (
                    import ./static.nix (args // { withIOG = false; })
                  )) (compilers static-pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-static-minimal" (
                    import ./static.nix (args // {  withHLS = false; withHlint = false; withIOG = false; })
                  )) (compilers static-pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-js" (
                    import ./cross-js.nix (args // { pkgs = js-pkgs.pkgsBuildBuild; })
                  )) (js-compilers js-pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-js-minimal" (
                    import ./cross-js.nix (args // { pkgs = js-pkgs.buildPackages; withHLS = false; withHlint = false; })
                  )) (js-compilers js-pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-windows" (
                    import ./cross-windows.nix args
                  )) (windows-compilers windows-pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-windows-minimal" (
                    import ./cross-windows.nix (args // { withHLS = false; withHlint = false; })
                  )) (windows-compilers windows-pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-iog" (
                    import ./dynamic.nix (args // { withIOG = true; })
                  )) (compilers pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-minimal-iog" (
                    import ./dynamic.nix (args // { withHLS = false; withHlint = false; withIOG = true; })
                  )) (compilers pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-iog-full" (
                    import ./dynamic.nix (args // { withIOGFull = true; })
                  )) (compilers pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                    pkgs.lib.nameValuePair "${short-name}-minimal-iog-full" (
                    import ./dynamic.nix (args // { withHLS = false; withHlint = false; withIOGFull = true; })
                  )) (compilers pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-static-iog" (
                    import ./static.nix (args // { withIOG = true; })
                  )) (compilers static-pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-static-iog-full" (
                    import ./static.nix (args // { withIOG = true; withIOGFull = true;})
                  )) (compilers static-pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-static-minimal-iog" (
                    import ./static.nix (args // { withHLS = false; withHlint = false; withIOG = true; })
                  )) (compilers static-pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-static-minimal-iog-full" (
                    import ./static.nix (args // { withHLS = false; withHlint = false; withIOG = true; withIOGFull = true; })
                  )) (compilers static-pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-js-iog" (
                    import ./cross-js.nix (args // { pkgs = js-pkgs.buildPackages; withIOG = true; })
                  )) (js-compilers js-pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-js-minimal-iog" (
                    import ./cross-js.nix (args // { pkgs = js-pkgs.buildPackages;  withHLS = false; withHlint = false; withIOG = true; })
                  )) (js-compilers js-pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-windows-iog" (
                    import ./cross-windows.nix (args // { withIOG = true; })
                  )) (windows-compilers windows-pkgs)
              // pkgs.lib.mapAttrs' (short-name: args:
                  pkgs.lib.nameValuePair "${short-name}-windows-minimal-iog" (
                    import ./cross-windows.nix (args // { withHLS = false; withHlint = false; withIOG = true; })
                  )) (windows-compilers windows-pkgs)
             );
        devShells = devShellsWithToolsModule {};
        # Eval must be done on linux when we use hydra to build environment
        # scripts for other platforms.  That way a linux GHA can download the
        # cached files without needing access to the actual build platform.
        devShellsWithEvalOnLinux = devShellsWithToolsModule { evalSystem = "x86_64-linux"; };
      in {
        inherit devShells;
        hydraJobs = devShells // {
          # *-dev sentinel job. Signals all -env have been built.
          required = pkgs.runCommand "required dependencies (${system})" {
              _hydraAggregate = true;
              constituents = map (name: "${system}.${name}-env") (builtins.attrNames devShellsWithEvalOnLinux);
            } "touch  $out";
          } // (
          # Generate environment wrapper scripts at evaluation time.
          # This avoids:
          # - IFD (Import From Derivation) which forces cross-platform builds during eval
          # - recursive-nix which is not supported on remote builders
          #
          # We construct the PATH from buildInputs/nativeBuildInputs using lib.makeBinPath,
          # and include other environment variables and the shellHook.
          let
            mkEnvScript = name: drv:
              let
                inherit (pkgs) lib;

                # Collect all input packages that should contribute to PATH
                # This mirrors what stdenv's setup.sh does when setting up the shell
                # Note: Some inputs may contain nested lists, so we flatten first
                allBuildInputs = lib.flatten [
                  (drv.buildInputs or [])
                  (drv.nativeBuildInputs or [])
                  (drv.propagatedBuildInputs or [])
                  (drv.propagatedNativeBuildInputs or [])
                ];

                # Construct PATH from all inputs' bin directories
                # This is equivalent to what `nix develop` does internally
                binPath = lib.makeBinPath allBuildInputs;

                # Extract other environment variables from derivation attributes
                drvEnv = pkgs.devShellTools.unstructuredDerivationInputEnv {
                  inherit (drv) drvAttrs;
                } // pkgs.devShellTools.derivationOutputEnv {
                  outputList = drv.outputs;
                  outputMap = drv;
                };

                # Filter to only include user-defined environment variables
                # (variables explicitly set via mkShell { FOO = "bar"; })
                filteredEnv = lib.filterAttrs (varName: value:
                  # Skip internal nix build variables
                  ! lib.elem varName [
                    "out" "outputs" "args" "builder" "system" "name"
                    "__structuredAttrs" "__ignoreNulls"
                    "preferLocalBuild" "allowSubstitutes"
                    "allowedReferences" "allowedRequisites"
                    "disallowedReferences" "disallowedRequisites"
                    "stdenv" "buildInputs" "nativeBuildInputs"
                    "propagatedBuildInputs" "propagatedNativeBuildInputs"
                    "depsBuildBuild" "depsBuildBuildPropagated"
                    "depsBuildTarget" "depsBuildTargetPropagated"
                    "depsHostHost" "depsHostHostPropagated"
                    "depsTargetTarget" "depsTargetTargetPropagated"
                    "strictDeps" "phases" "prePhases" "postPhases"
                    "buildPhase" "installPhase" "checkPhase" "configurePhase"
                    "unpackPhase" "patchPhase" "fixupPhase" "distPhase"
                    "dontUnpack" "dontConfigure" "dontBuild" "dontInstall"
                    "dontFixup" "dontStrip" "dontPatchELF" "dontPatchShebangs"
                    "cmakeFlags" "mesonFlags" "configureFlags"
                    "makeFlags" "buildFlags" "installFlags" "checkFlags"
                    "doCheck" "doInstallCheck" "patches"
                    # Also skip shellHook as we handle it separately
                    "shellHook"
                    # Skip darwin-specific internal vars
                    "__darwinAllowLocalNetworking" "__sandboxProfile"
                    "__propagatedSandboxProfile" "__impureHostDeps"
                    "__propagatedImpureHostDeps"
                  ]
                  # Skip empty or null values
                  && value != ""
                  && value != null
                  # Skip list/attrset values (can't be exported as shell vars directly)
                  && ! lib.isList value
                  && ! lib.isAttrs value
                  # Skip functions
                  && ! lib.isFunction value
                ) drvEnv;

                # Generate declare -x statements for user-defined environment variables
                envExports = lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (varName: value:
                    "declare -x ${varName}=${lib.escapeShellArg (toString value)}"
                  ) filteredEnv
                );

                # Extract shellHook if present
                shellHook = drv.shellHook or "";

              in pkgs.writeTextFile {
                name = "devx";
                executable = true;
                text = ''
                  #! /usr/bin/env nix-shell
                  #! nix-shell -i bash -p bash

                  # Set PATH from mkShell's buildInputs
                  # Prepend to existing PATH to include system tools
                  export PATH="${binPath}''${PATH:+:$PATH}"

                  # User-defined environment variables from mkShell
                  ${envExports}

                  # Shell hook from mkShell
                  # Note: We don't use strict mode (set -euo pipefail) here because
                  # the shellHook is user-provided code that may reference unset variables
                  ${shellHook}

                  # Source the user's script if provided
                  if [ -n "''${1:-}" ]; then
                    source "$1"
                  fi
                '';
              };
          in
          pkgs.lib.mapAttrs' (name: drv:
            pkgs.lib.nameValuePair "${name}-env" (mkEnvScript name drv)
          ) devShells
          # Smoke-test each -env.sh script: source it in a sandbox and verify
          # that the essential tools (ghc, cabal, pkg-config, and optionally HLS)
          # are functional. Catches PATH construction errors, missing packages,
          # and broken shellHooks that would produce unusable containers.
          // pkgs.lib.mapAttrs' (name: drv:
            let
              inherit (pkgs) lib;
              envScript = mkEnvScript name drv;
              # HLS is only available when:
              #   - not a -minimal variant (withHLS was true)
              #   - not a -js variant (JS backend)
              #   - not a -windows variant (cross-windows)
              #   - compiler version < 9.11 (ghc912+ not yet supported)
              hasHLS = !(lib.hasInfix "-minimal" name)
                    && !(lib.hasInfix "-js" name)
                    && !(lib.hasInfix "-windows" name)
                    && !(lib.hasInfix "ghc912" name);
            in lib.nameValuePair "${name}-env-test" (
              pkgs.runCommand "${name}-env-test" {
                nativeBuildInputs = [ pkgs.bash ];
              } ''
                # Source the environment script to set up PATH and env vars
                source ${envScript}

                # For cross-compilation shells (static/musl, JS), the GHC binary
                # has a target prefix (e.g. x86_64-unknown-linux-musl-ghc).
                # Extract the correct name from NIX_CABAL_FLAGS if set.
                GHC_CMD="ghc"
                if [[ -n "''${NIX_CABAL_FLAGS:-}" ]]; then
                  for flag in $NIX_CABAL_FLAGS; do
                    case "$flag" in
                      --with-ghc=*) GHC_CMD="''${flag#--with-ghc=}" ;;
                    esac
                  done
                fi

                echo "=== Testing ${name} ==="
                echo -n "GHC: "; $GHC_CMD --version
                echo -n "Cabal: "; cabal --version | head -1
                echo -n "pkg-config packages: "; pkg-config --list-all | wc -l
                ${lib.optionalString hasHLS ''
                  echo -n "HLS: "; haskell-language-server --version || true
                ''}
                echo "=== ${name}: OK ==="
                touch $out
              '')
          ) devShells)
          // (pkgs.lib.mapAttrs' (name: drv:
            pkgs.lib.nameValuePair "${name}-plans" drv.plans) devShells);
        packages.cabalProjectLocal-static        = (import ./quirks.nix { pkgs = static-pkgs; static = true; }).template;
        packages.cabalProjectLocal-cross-js      = (import ./quirks.nix { pkgs = js-pkgs;                    }).template;
        packages.cabalProjectLocal-cross-windows = (import ./quirks.nix { pkgs = windows-pkgs;               }).template;
       });
     # we use flake-outputs here to inject a required job that aggregates all required jobs.
     in flake-outputs // {
          hydraJobs = flake-outputs.hydraJobs // {
            required = (import nixpkgs { system = "x86_64-linux"; }).runCommand "required dependencies" {
              _hydraAggregate = true;
              constituents = map (s: "${s}.required") supportedSystems;
            } "touch  $out";
          };
        };
}
