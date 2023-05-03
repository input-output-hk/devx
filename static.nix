{ self, pkgs, compiler, compiler-nix-name, toolsModule, withHLS ? true, withHlint ? true, withIOG ? true }:
let tool-version-map = import ./tool-map.nix;
    tool = tool-name: pkgs.pkgsBuildBuild.haskell-nix.tool compiler-nix-name tool-name [(tool-version-map compiler-nix-name tool-name) toolsModule];
    cabal-install = tool "cabal";
    # add a trace helper. This will trace a message about disabling a component despite requesting it, if it's not supported in that compiler.
    compiler-not-in = compiler-list: name: (if __elem compiler-nix-name compiler-list then __trace "No ${name}. Not yet compatible with ${compiler-nix-name}" false else true);

    # * wrapped tools:
    # fixup-nix-deps allows us to drop dylibs from macOS executables that can be
    # linked directly.
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
                $NIX_CABAL_FLAGS \
                --disable-shared --enable-static \
                --ghc-option=-L${lib.getLib static-gmp}/lib \
                --ghc-option=-L${lib.getLib static-libsodium-vrf}/lib \
                --ghc-option=-L${lib.getLib static-secp256k1}/lib \
                --ghc-option=-L${lib.getLib static-openssl}/lib
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
    NIX_CABAL_FLAGS = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isMusl [
    "--with-ghc=${if pkgs.stdenv.hostPlatform.isAarch64 then "aarch64" else "x86_64"}-unknown-linux-musl-ghc"
    "--with-ghc-pkg=${if pkgs.stdenv.hostPlatform.isAarch64 then "aarch64" else "x86_64"}-unknown-linux-musl-ghc-pkg"
    "--with-hsc2hs=${if pkgs.stdenv.hostPlatform.isAarch64 then "aarch64" else "x86_64"}-unknown-linux-musl-hsc2hs"
    # ensure that the linker knows we want a static build product
    "--enable-executable-static"
    ];
    hardeningDisable = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isMusl [ "format" "pie" ];

    CABAL_PROJECT_LOCAL_TEMPLATE = with pkgs; ''
    package digest
    extra-lib-dirs: ${zlib}/lib ${pcre}/lib
    constraints:
    HsOpenSSL +use-pkg-config,
    zlib +pkg-config
    pcre-lite +pkg-config
    '';

    shellHook = with pkgs; ''
        export PS1="\[\033[01;33m\][\w]$\[\033[00m\] "
        ${figlet}/bin/figlet -f rectangles 'IOG Haskell Shell'
        ${figlet}/bin/figlet -f small "*= static edition =*"
        echo "Revision (input-output-hk/devx): ${if self ? rev then self.rev else "unknown/dirty checkout"}."
        echo "NOTE (macos): you can use fixup-nix-deps FILE, to fix iconv, ffi, and zlib dependencies that point to the /nix/store"
        export CABAL_DIR=$HOME/.cabal-static
        echo "CABAL_DIR set to $CABAL_DIR"
        echo "Quirks:"
        echo "${pkgs.libsodium-vrf.drvPath}"
        echo -e "\tif you have the zlib, HsOpenSSL, or digest package in your dependency tree, please make sure to"
        echo -e "\techo \"\$CABAL_PROJECT_LOCAL_TEMPLATE\" > cabal.project.local"
    '';
    
    # these are _target_ libs, e.g. ones we want to link the build
    # product against. These are also the ones that showup in the
    # PKG_CONFIG_PATH.
    buildInputs = (with pkgs; [
        # for libstdc++; ghc not being able to find this properly is bad,
        # it _should_ probably call out to a g++ or clang++ but doesn't.
        stdenv.cc.cc.lib
    ]) ++ map pkgs.lib.getDev (with pkgs; [
        static-gmp

        zlib
        pcre
        openssl
    ] ++ pkgs.lib.optional withIOG (with pkgs; [
        libblst libsodium-vrf secp256k1 #R_4_1_3
    ]));

    # these are _native_ libs, we need to drive the compilation environment
    # they will _not_ be part of the final build product.
    nativeBuildInputs = [
        wrapped-cabal
        fixup-nix-deps
        # We are happy to use a _shared_ compiler; we only want the build
        # products to be static.
        (compiler.override { enableShared = true; })
    ] ++ (with pkgs; [
        pkgconfig
        stdenv.cc.cc.lib ]) ++ (with pkgs.buildPackages; [
    ])
    ++ pkgs.lib.optional (withHLS && (compiler-not-in (["ghc961"] ++ pkgs.lib.optional (pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64) "ghc902") "Haskell Language Server")) (tool "haskell-language-server")
    ++ pkgs.lib.optional (withHlint && (compiler-not-in (["ghc961"] ++ pkgs.lib.optional (pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64) "ghc902") "HLint")) (tool "hlint")
    ++ pkgs.lib.optional withIOG (with pkgs; [ cddl cbor-diag ])
    ;
})
