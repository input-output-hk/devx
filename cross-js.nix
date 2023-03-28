{ pkgs, compiler, compiler-nix-name, withHLS ? true, withHlint ? true, withIOG ? true  }:
let tool-version-map = import ./tool-map.nix;
    tool = tool-name: pkgs.haskell-nix.tool compiler-nix-name tool-name (tool-version-map compiler-nix-name tool-name);
    cabal-install = tool "cabal";
    # add a trace helper. This will trace a message about disabling a component despite requesting it, if it's not supported in that compiler.
    compiler-not-in = compiler-list: name: (if __elem compiler-nix-name compiler-list then __trace "No ${name}. Not yet compatible with ${compiler-nix-name}" false else true);    

    # * wrapped tools:
    # A cabal-install wrapper that sets the appropriate static flags
    wrapped-cabal = pkgs.writeShellApplication {
        name = "cabal";
        runtimeInputs = [ cabal-install ];
        text = with pkgs; ''
        # We do not want to quote NIX_CABAL_FLAGS
        # it will leave an empty argument, if they are empty.
        # shellcheck disable=SC2086
        case "$1" in
            build)
            cabal \
                "$@" \
                $NIX_CABAL_FLAGS 
            ;;
            clean)
            cabal "$@"
            ;;
            *)
            cabal $NIX_CABAL_FLAGS "$@"
            ;;
        esac        
        '';
    };    
in
pkgs.mkShell ({
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
    NIX_CABAL_FLAGS = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isGhcjs [
    "--with-ghc=javascript-unknown-linux-ghcjs-ghc"
    "--with-ghc-pkg=javascript-unknown-linux-ghcjs-pkg"
    "--with-hsc2hs=javascript-unknown-linux-ghcjs-hsc2hs"
    # ensure that the linker knows we want a static build product
    # "--enable-executable-static"
    ];
    # hardeningDisable = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isMusl [ "format" "pie" ];

    CABAL_PROJECT_LOCAL_TEMPLATE = with pkgs; ''
    package digest
    constraints:
    HsOpenSSL +use-pkg-config,
    zlib +pkg-config
    pcre-lite +pkg-config
    '';

    shellHook = with pkgs; ''
    export PS1="\[\033[01;33m\][\w]$\[\033[00m\] "
    ${figlet}/bin/figlet -f rectangles 'IOG Haskell Shell'
    ${figlet}/bin/figlet -f small "*= JS edition =*"
    export CABAL_DIR=$HOME/.cabal-js
    echo "CABAL_DIR set to $CABAL_DIR"
    '';
    buildInputs = [];

    nativeBuildInputs = [ wrapped-cabal compiler ] ++ (with pkgs; [
        haskell-nix.cabal-install.${compiler-nix-name}
        pkgconfig
        stdenv.cc.cc.lib ]) ++ (with pkgs.buildPackages; [
    ])
    ++ pkgs.lib.optional (withHLS && (compiler-not-in ["ghc961"] "Haskell Language Server")) (tool "haskell-language-server")
    ++ pkgs.lib.optional (withHlint && (compiler-not-in ["ghc961"] "HLint")) (tool "hlint")
    ++ pkgs.lib.optional withIOG
        (with pkgs; [ cddl cbor-diag ]
        ++ map pkgs.lib.getDev (with pkgs; [
            libsodium-vrf secp256k1 #R_4_1_3
        ]))
    ;
})
