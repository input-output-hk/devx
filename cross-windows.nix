{ pkgs, compiler, compiler-nix-name, withHLS ? true, withHlint ? true, withIOG ? true  }:
let tool-version-map = import ./tool-map.nix;
    tool = tool-name: pkgs.pkgsBuildBuild.haskell-nix.tool compiler-nix-name tool-name (tool-version-map compiler-nix-name tool-name);
    cabal-install = tool "cabal";
    # add a trace helper. This will trace a message about disabling a component despite requesting it, if it's not supported in that compiler.
    compiler-not-in = compiler-list: name: (if __elem compiler-nix-name compiler-list then __trace "No ${name}. Not yet compatible with ${compiler-nix-name}" false else true);

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

    nativeBuildInputs = [ wrapped-hsc2hs wrapped-cabal compiler ] ++ (with pkgs; [
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
