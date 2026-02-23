{
    description = "Minimal devshell flake for haskell";

    inputs.haskellNix.url = "github:input-output-hk/haskell.nix";
    inputs.nixpkgs.follows = "haskellNix/nixpkgs-2511";
    inputs.flake-utils.url = "github:numtide/flake-utils";
    inputs.iohk-nix.url = "github:input-output-hk/iohk-nix";
    inputs.cabal.url = "github:stable-haskell/cabal";
    inputs.cabal.flake = false;

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
          # Each wrapper exports the derivation's raw attributes (buildInputs,
          # nativeBuildInputs, stdenv, etc.) then sources $stdenv/setup to run
          # all setup hooks (cc-wrapper, pkg-config-wrapper, etc.). This gives
          # the same environment as `nix develop`: full PATH, NIX_CFLAGS_COMPILE,
          # NIX_LDFLAGS, PKG_CONFIG_PATH, and all other hook-computed variables.
          let
            mkEnvScript = name: drv:
              let
                inherit (pkgs) lib;

                # Extract all derivation attributes as string-valued env vars.
                # This includes stdenv, buildInputs, nativeBuildInputs, initialPath,
                # and all user-defined variables (NIX_CABAL_FLAGS, etc.).
                # These seed stdenv's setup.sh which iterates over build inputs
                # and runs their setup hooks to populate NIX_CFLAGS_COMPILE,
                # NIX_LDFLAGS, PKG_CONFIG_PATH, PATH, etc.
                drvEnv = pkgs.devShellTools.unstructuredDerivationInputEnv {
                  inherit (drv) drvAttrs;
                } // pkgs.devShellTools.derivationOutputEnv {
                  outputList = drv.outputs;
                  outputMap = drv;
                };

                # Filter to exportable variables. We keep build-input variables
                # (stdenv, buildInputs, nativeBuildInputs, initialPath, etc.)
                # because setup.sh needs them to drive the setup hook machinery.
                # Only truly internal nix plumbing is excluded.
                exportableEnv = lib.filterAttrs (varName: value:
                  ! lib.elem varName [
                    # Nix builder internals (meaningless outside sandbox)
                    "out" "outputs" "args" "builder"
                    "__structuredAttrs" "__ignoreNulls"
                    "preferLocalBuild" "allowSubstitutes"
                    "allowedReferences" "allowedRequisites"
                    "disallowedReferences" "disallowedRequisites"
                    # Handled separately after setup.sh
                    "shellHook"
                    # Darwin sandbox internals
                    "__darwinAllowLocalNetworking" "__sandboxProfile"
                    "__propagatedSandboxProfile" "__impureHostDeps"
                    "__propagatedImpureHostDeps"
                  ]
                  && value != ""
                  && value != null
                  && ! lib.isList value
                  && ! lib.isAttrs value
                  && ! lib.isFunction value
                ) drvEnv;

                envExports = lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (varName: value:
                    "declare -x ${varName}=${lib.escapeShellArg (toString value)}"
                  ) exportableEnv
                );

                shellHook = drv.shellHook or "";

              in pkgs.writeTextFile {
                name = "devx";
                executable = true;
                text = ''
                  #!${pkgs.bash}/bin/bash

                  # Raw derivation environment variables. These seed stdenv's
                  # setup.sh with build inputs, compiler paths, and other
                  # attributes needed to initialize the full dev environment.
                  ${envExports}

                  # setup.sh expects Nix builder runtime variables that are
                  # only set inside `nix build`. When running directly
                  # (container, CI, CLI) we provide sensible defaults.
                  if [ -z "''${NIX_BUILD_TOP:-}" ]; then
                    export NIX_BUILD_TOP="$(mktemp -d)"
                    export TMPDIR="$NIX_BUILD_TOP"
                    export TMP="$NIX_BUILD_TOP"
                    export TEMP="$NIX_BUILD_TOP"
                    export TEMPDIR="$NIX_BUILD_TOP"
                    export NIX_STORE="/nix/store"
                    export out="$NIX_BUILD_TOP/out"
                    mkdir -p "$out"
                  fi

                  # Development shells must not enforce store-path purity.
                  # The stdenv preHook defaults NIX_ENFORCE_PURITY to 1, which
                  # causes the cc-wrapper to reject -I/-L flags pointing outside
                  # /nix/store/ (e.g. the cabal package store at $CABAL_DIR/store/).
                  # Setting it to empty before sourcing setup.sh makes the preHook's
                  # ''${NIX_ENFORCE_PURITY-1} keep the empty value instead of defaulting.
                  export NIX_ENFORCE_PURITY=

                  # Source stdenv's setup.sh to initialize the development
                  # environment. This runs all setup hooks (cc-wrapper,
                  # pkg-config-wrapper, etc.) and populates NIX_CFLAGS_COMPILE,
                  # NIX_LDFLAGS, PKG_CONFIG_PATH, PATH, etc. — exactly like
                  # `nix develop` does.
                  _DEVX_HOME="''${HOME:-}"
                  source "$stdenv/setup"

                  # Restore settings for interactive / script use.
                  # setup.sh enables strict mode and may reset HOME.
                  set +eu +o pipefail
                  [ -n "$_DEVX_HOME" ] && export HOME="$_DEVX_HOME"
                  unset _DEVX_HOME

                  # Shell hook from mkShell
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
              pkgs.runCommand "${name}-env-test" {} ''
                # Save the test output path before sourcing the devshell
                # environment — setup.sh resets output-related variables.
                _TEST_OUT="$out"

                # Source the environment script. This exports drvAttrs and
                # runs source "$stdenv/setup", giving us the full development
                # environment with all tools on PATH.
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
                touch "$_TEST_OUT"
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
