{ pkgs, compiler, compiler-nix-name, withHLS ? true, withHlint ? true, withIOG ? true  }:
let tool-version-map = import ./tool-map.nix;
    tool = tool-name: pkgs.pkgsBuildBuild.haskell-nix.tool compiler-nix-name tool-name (tool-version-map compiler-nix-name tool-name);
    cabal-install = tool "cabal";
    # add a trace helper. This will trace a message about disabling a component despite requesting it, if it's not supported in that compiler.
    compiler-not-in = compiler-list: name: (if __elem compiler-nix-name compiler-list then __trace "No ${name}. Not yet compatible with ${compiler-nix-name}" false else true);

    inherit (pkgs.haskell-nix.iserv-proxy-exes.${compiler-nix-name}) iserv-proxy iserv-proxy-interpreter;

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
        pkgsHostTargetAsString="${pkgs.lib.concatStringsSep " " ([
          pkgs.libffi
          pkgs.gmp
          pkgs.windows.mcfgthreads
          pkgs.windows.mingw_w64_pthreads
          pkgs.buildPackages.gcc.cc
        ] ++ pkgs.lib.optionals withIOG [
          (pkgs.libsodium-vrf or pkgs.libsodium)
          pkgs.openssl.bin
          pkgs.secp256k1
        ])}"
        for p in $pkgsHostTargetAsString; do
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
        # Not sure why this `unset` helps.  It might avoids some kind of overflow issue.  We see `wine` fail to start when building `cardano-wallet-cli` test `unit`.
        unset pkgsHostTargetAsString
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
        runtimeInputs = [ cabal-install ];
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
    # ensure that the linker knows we want a static build product
    # "--enable-executable-static"
    ];

    CABAL_PROJECT_LOCAL_TEMPLATE = ''
    package digest
    constraints:
    HsOpenSSL +use-pkg-config,
    zlib +pkg-config
    pcre-lite +pkg-config
    '';

    shellHook = with pkgs; ''
    export PS1="\[\033[01;33m\][\w]$\[\033[00m\] "
    ${pkgsBuildBuild.figlet}/bin/figlet -f rectangles 'IOG Haskell Shell'
    ${pkgsBuildBuild.figlet}/bin/figlet -f small "*= Windows =*"
    export CABAL_DIR=$HOME/.cabal-windows
    echo "CABAL_DIR set to $CABAL_DIR"
    '';
    buildInputs = [];

    nativeBuildInputs = [ wrapped-ghc wrapped-hsc2hs wrapped-cabal compiler ] ++ (with pkgs; [
        buildPackages.bintools.bintools
        stdenv.cc
        pkgsBuildBuild.haskell-nix.cabal-install.${compiler-nix-name}
        pkgsBuildBuild.pkgconfig
        (pkgs.pkgsBuildBuild.haskell-nix.tool compiler-nix-name "happy" "1.20.1.1")
        (pkgs.pkgsBuildBuild.haskell-nix.tool compiler-nix-name "alex" "3.2.7.3")
        stdenv.cc.cc.lib ])
    ++ pkgs.lib.optional (withHLS && (compiler-not-in ["ghc961"] "Haskell Language Server")) (tool "haskell-language-server")
    ++ pkgs.lib.optional (withHlint && (compiler-not-in ["ghc961"] "HLint")) (tool "hlint")
    ++ pkgs.lib.optional withIOG
        (with pkgs.buildPackages; [ cddl cbor-diag ]
        ++ map pkgs.lib.getDev (with pkgs; [
            libsodium-vrf secp256k1 #R_4_1_3
        ]))
    ;
})
