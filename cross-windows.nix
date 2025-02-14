{ self, pkgs, compiler, compiler-nix-name, toolsModule, withHLS ? true, withHlint ? true, withIOG ? true  }:
let tool-version-map = (import ./tool-map.nix) self;
    tool = tool-name: pkgs.pkgsBuildBuild.haskell-nix.tool compiler-nix-name tool-name [(tool-version-map compiler-nix-name tool-name) toolsModule];
    cabal-install = tool "cabal";
    haskell-tools =
         pkgs.lib.optionalAttrs (withHLS && (compiler-not-in (
           # it appears we can't get HLS build with 9.8 yet.
           pkgs.lib.optional (builtins.compareVersions compiler.version "9.7" >= 0) compiler-nix-name
        ++ pkgs.lib.optional (pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64) "ghc902") "Haskell Language Server")) { hls = tool "haskell-language-server"; }
      // pkgs.lib.optionalAttrs (withHlint && (compiler-not-in (
           pkgs.lib.optional (builtins.compareVersions compiler.version "9.8" >= 0) compiler-nix-name
        ++ pkgs.lib.optional (pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64) "ghc902") "HLint")) { hlint = tool "hlint"; };
    # add a trace helper. This will trace a message about disabling a component despite requesting it, if it's not supported in that compiler.
    compiler-not-in = compiler-list: name: (if __elem compiler-nix-name compiler-list then __trace "No ${name}. Not yet compatible with ${compiler-nix-name}" false else true);
    # Exclude zstd support for now, since it's currently broken on mingw32W64:
    # https://github.com/NixOS/nixpkgs/issues/333338
    curl = pkgs.curl.override ({
      zstdSupport = false;
      pslSupport = false;
    });
    # Haskell.nix pulls in cabal-install 3.10.3.0 which will not build with 9.10+. In that
    # case, build with 9.8
    native-cabal-install =
      if builtins.compareVersions compiler.version "9.10" >= 0 then
        pkgs.pkgsBuildBuild.haskell-nix.cabal-install.ghc982
      else
        pkgs.pkgsBuildBuild.haskell-nix.cabal-install.${compiler-nix-name};
    inherit (pkgs.haskell-nix.iserv-proxy-exes.${compiler-nix-name}) iserv-proxy iserv-proxy-interpreter;

    dllPkgs = [
      pkgs.libffi
      pkgs.gmp
      pkgs.windows.mcfgthreads
      pkgs.windows.mingw_w64_pthreads
      pkgs.buildPackages.gcc.cc
    ] ++ pkgs.lib.optionals withIOG [
      (pkgs.libsodium-vrf or pkgs.libsodium)
      pkgs.openssl.bin
      pkgs.secp256k1
    ];
    wineIservWrapperScript = pkgs.pkgsBuildBuild.writeScriptBin "iserv-wrapper" ''
        #!${pkgs.pkgsBuildBuild.stdenv.shell}
        set -euo pipefail
        # unset the configureFlags.
        # configure should have run already
        # without restting it, wine might fail
        # due to a too large environment.
        unset configureFlags
        PORT=$((5000 + $RANDOM % 5000))
        (>&2 echo "---> Starting ${iserv-proxy-interpreter.exeName} on port $PORT")
        REMOTE_ISERV=$(mktemp -d)
        ln -s ${iserv-proxy-interpreter}/bin/* $REMOTE_ISERV
        # Normally this would come from comp-builder.nix
        for p in ${pkgs.lib.concatStringsSep " " dllPkgs}; do
          find "$p" -iname '*.dll' -exec ln -sf {} $REMOTE_ISERV \;
          find "$p" -iname '*.dll.a' -exec ln -sf {} $REMOTE_ISERV \;
        done
        # Some DLLs have a `lib` prefix but we attempt to load them without the prefix.
        # This was a problem for `double-conversion` package when used in TH code.
        # Creating links from the `X.dll` to `libX.dll` works around this issue.
        (
        cd $REMOTE_ISERV
        for l in lib*.dll; do
          ln -s "$l" "''${l#lib}"
        done
        )
        WINEDLLOVERRIDES="winemac.drv=d" WINEDEBUG=warn-all,fixme-all,-menubuilder,-mscoree,-ole,-secur32,-winediag WINEPREFIX=$TMP ${pkgs.pkgsBuildBuild.winePackages.minimal}/bin/wine64 $REMOTE_ISERV/${iserv-proxy-interpreter.exeName} tmp $PORT &
        (>&2 echo "---| ${iserv-proxy-interpreter.exeName} should have started on $PORT")
        RISERV_PID="$!"
        ${iserv-proxy}/bin/iserv-proxy $@ 127.0.0.1 "$PORT"
        (>&2 echo "---> killing ${iserv-proxy-interpreter.exeName}...")
        kill $RISERV_PID
      '';

    # * wrapped tools:
    # A cabal-install wrapper that sets the appropriate static flags
    wrapped-cabal = pkgs.pkgsBuildBuild.writeShellApplication {
        name = "cabal";
        runtimeInputs = [ cabal-install curl ];
        text = ''
        # We do not want to quote NIX_CABAL_FLAGS
        # it will leave an empty argument, if they are empty.
        # shellcheck disable=SC2086
        case "$1" in
            build)
            cabal \
                "$@" \
                $NIX_CABAL_FLAGS
            ;;
            clean|unpack)
            cabal "$@"
            ;;
            *)
            cabal $NIX_CABAL_FLAGS "$@"
            ;;
        esac
        '';
    };
    wrapped-hsc2hs = pkgs.pkgsBuildBuild.writeShellApplication {
        name = "${compiler.targetPrefix}hsc2hs";
        text = ''
          ${compiler}/bin/${compiler.targetPrefix}hsc2hs --cross-compile --via-asm "$@"
        '';
    };
    wrapped-ghc = pkgs.pkgsBuildBuild.writeShellApplication {
        name = "${compiler.targetPrefix}ghc";
        text = ''
          ${compiler}/bin/${compiler.targetPrefix}ghc \
            -fexternal-interpreter \
            -pgmi ${wineIservWrapperScript}/bin/iserv-wrapper \
            -L${pkgs.windows.mingw_w64_pthreads}/lib \
            -L${pkgs.windows.mingw_w64_pthreads}/bin \
            -L${pkgs.gmp}/lib \
            "$@"
        '';
    };
    wine-test-wrapper = pkgs.pkgsBuildBuild.writeScriptBin "${compiler.targetPrefix}test-wrapper" ''
        #!${pkgs.pkgsBuildBuild.stdenv.shell}
        set -euo pipefail
        # Link all the DLLs we might need into one place so we can add
        # just that one location to WINEPATH.
        DLLS=$(mktemp -d)
        for p in ${pkgs.lib.concatStringsSep " " dllPkgs}; do
          find "$p" -iname '*.dll' -exec ln -sf {} $DLLS \;
          find "$p" -iname '*.dll.a' -exec ln -sf {} $DLLS \;
        done
        # Some DLLs have a `lib` prefix but we attempt to load them without the prefix.
        # This was a problem for `double-conversion` package when used in TH code.
        # Creating links from the `X.dll` to `libX.dll` works around this issue.
        (
        cd $DLLS
        for l in lib*.dll; do
          ln -s "$l" "''${l#lib}"
        done
        )
        WINEPATH=$DLLS WINEDLLOVERRIDES="winemac.drv=d" WINEDEBUG=warn-all,fixme-all,-menubuilder,-mscoree,-ole,-secur32,-winediag WINEPREFIX=$TMP ${pkgs.pkgsBuildBuild.winePackages.minimal}/bin/wine64 "$@"
      '';
    quirks = (import ./quirks.nix { inherit pkgs; });
in
pkgs.pkgsBuildBuild.mkShell ({
    # Note [cabal override]:
    #
    # We need to override the `cabal` command and pass --ghc-options for the
    # libraries. This is fairly annoying, but necessary, as ghc will otherwise
    # pick up the dynamic libraries, instead of the static ones.
    #
    # Note [static gmp]:
    #
    # We can only link GMP statically, because the thing we are linking is fully
    # open source, and licenses accordingly.  Otherwise we'd have to link gmp
    # dynamically.  This requirement will be gone with gmp-bignum.
    #
    NIX_CABAL_FLAGS = [
    "--with-ghc=x86_64-w64-mingw32-ghc"
    "--with-ghc-pkg=x86_64-w64-mingw32-ghc-pkg"
    "--with-hsc2hs=x86_64-w64-mingw32-hsc2hs"
    # We use the test-wrapper option here so that tests are executed through
    # WINE, as we can't run windows test natively.
    "--test-wrapper=x86_64-w64-mingw32-test-wrapper"
    # ensure that the linker knows we want a static build product
    # "--enable-executable-static"
    ];

    inherit (quirks) CABAL_PROJECT_LOCAL_TEMPLATE;

    shellHook =
      with pkgs;
      let flavor = "${compiler-nix-name}-windows"
                  + lib.optionalString (!withHLS && !withHlint) "-minimal"
                  + lib.optionalString withIOG                  "-iog"
                  ;
      in ''
      export PS1="\[\033[01;33m\][\w]$\[\033[00m\] "
      ${pkgsBuildBuild.figlet}/bin/figlet -f rectangles 'IOG Haskell Shell'
      ${pkgsBuildBuild.figlet}/bin/figlet -f small "*= Windows =*"
      echo "Revision (input-output-hk/devx): ${if self ? rev then self.rev else "unknown/dirty checkout"}."
      export CABAL_DIR=$HOME/.cabal-windows
      echo "CABAL_DIR set to $CABAL_DIR"
      echo ""
    '' + (quirks.hint flavor) + quirks.shellHook;
    buildInputs = [];

    nativeBuildInputs = [
        wrapped-ghc
        wrapped-hsc2hs
        wrapped-cabal
        wine-test-wrapper
        compiler
        native-cabal-install
    ]
    ++ (with pkgs; [
        buildPackages.bintools.bintools
        stdenv.cc
        (pkgsBuildBuild.pkg-config or pkgsBuildBuild.pkgconfig)
        (tool "happy")
        (tool "alex")
        stdenv.cc.cc.lib ])
    ++ map pkgs.lib.getDev (with pkgs; [
        zlib pcre openssl
        windows.mcfgthreads
        windows.mingw_w64_pthreads
    ])
    ++ builtins.attrValues haskell-tools
    ++ pkgs.lib.optional withIOG
        (with pkgs.pkgsBuildBuild; [ cddl cbor-diag ]
        ++ map pkgs.lib.getDev (with pkgs; [
            libblst libsodium-vrf secp256k1
        ]))
    ;

    passthru = {
      plans = if haskell-tools == {} then {} else
        pkgs.pkgsBuildBuild.linkFarm "plans"
          (builtins.mapAttrs (_: t: t.project.plan-nix) haskell-tools);
    };
})
