# define a development shell for dynamically linked applications (default)
{ self, pkgs, compiler, compiler-nix-name, toolsModule, withHLS ? true, withHlint ? true, withIOG ? true }:
let tool-version-map = import ./tool-map.nix;
    tool = tool-name: pkgs.haskell-nix.tool compiler-nix-name tool-name [(tool-version-map compiler-nix-name tool-name) toolsModule];
    cabal-install = pkgs.haskell-nix.nix-tools-unchecked.exes.cabal;
    # add a trace helper. This will trace a message about disabling a component despite requesting it, if it's not supported in that compiler.
    compiler-not-in = compiler-list: name: (if __elem compiler-nix-name compiler-list then __trace "No ${name}. Not yet compatible with ${compiler-nix-name}" false else true);

    # * wrapped tools:
    # fixup-nix-deps allows us to drop dylibs from macOS executables that can be
    # linked directly.
    #
    # FIXME: this is the same as in static.nix; and we should probably put this into
    #        a shared file. It will also not work for anything that has more than
    #        the system libs linked.
    fixup-nix-deps = pkgs.writeShellApplication {
        name = "fixup-nix-deps";
        text = ''
        for nixlib in $(otool -L "$1" |awk '/nix\/store/{ print $1 }'); do
            case "$nixlib" in
            *libiconv.dylib) install_name_tool -change "$nixlib" /usr/lib/libiconv.dylib "$1" ;;
            *libffi.*.dylib) install_name_tool -change "$nixlib" /usr/lib/libffi.dylib   "$1" ;;
            *libz.dylib)     install_name_tool -change "$nixlib" /usr/lib/libz.dylib     "$1" ;;
            *) ;;
            esac
        done
        '';
    };

    # this wrapped-cabal is for now the identity, but it's the same logic we
    # have in the static configuration, and we may imagine needing to inject
    # some flags into cabal (temporarily), hence we'll keep this functionality
    # here.
    wrapped-cabal = pkgs.writeShellApplication {
        name = "cabal";
        runtimeInputs = [ cabal-install ];
        text = ''
        case "$1" in
            build) cabal "$@"
            ;;
            clean|unpack) cabal "$@"
            ;;
            *) cabal "$@"
            ;;
        esac
        '';
    };
in
pkgs.mkShell {
    # The `cabal` overrride in this shell-hook doesn't do much yet. But
    # we may need to massage cabal a bit, so we'll leave it in here for
    # consistency with the one in static.nix.
    shellHook = with pkgs; ''
        export PS1="\[\033[01;33m\][\w]$\[\033[00m\] "
        ${figlet}/bin/figlet -f rectangles 'IOG Haskell Shell'
        echo "Revision (input-output-hk/devx): ${if self ? rev then self.rev else "unknown/dirty checkout"}."
        # change the CABAL_HOME so it doesn't confict with the default .cabal store outside of the shell
        # which might have a different environment (and thus cflags, ldflags, ...) rendering them mutually
        # incompatbile.
        export CABAL_DIR=$HOME/.cabal-devx
        echo "CABAL_DIR set to $CABAL_DIR"
    ''
    # this one is only needed on macOS right now, due to a bug in loading libcrypto.
    # The build will error with -6 due to "loading libcrypto in an unsafe way"
    + lib.optionalString stdenv.hostPlatform.isMacOS
    ''
    export DYLD_LIBRARY_PATH="${lib.getLib openssl}/lib"
    '';

    buildInputs = [
        wrapped-cabal
        fixup-nix-deps
        compiler
    ] ++ (with pkgs; [
        (pkgs.pkg-config or pkgconfig)
        # for libstdc++; ghc not being able to find this properly is bad,
        # it _should_ probably call out to a g++ or clang++ but doesn't.
        stdenv.cc.cc.lib
    ]) ++ map pkgs.lib.getDev (
        with pkgs;
        [
            zlib
            pcre
            openssl
        ]
        ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux systemd
    )
    ++ pkgs.lib.optional (withHLS && (compiler-not-in (["ghc99"] ++ pkgs.lib.optional (pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64) "ghc902") "Haskell Language Server")) (tool "haskell-language-server")
    ++ pkgs.lib.optional (withHlint && (compiler-not-in (["ghc981" "ghc99"] ++ pkgs.lib.optional (pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64) "ghc902") "HLint")) (tool "hlint")
    ++ pkgs.lib.optional withIOG
        (with pkgs; [
            cddl
            cbor-diag
            #R_4_1_3      # for plutus
            #postgresql   # for db-sync
            gh
            jq
            yq-go
        ]
        ++ map pkgs.lib.getDev (with pkgs; [ libblst libsodium-vrf secp256k1 R_4_1_3 postgresql icu ]))
    ;
}
