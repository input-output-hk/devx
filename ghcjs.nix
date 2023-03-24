{ pkgs, compiler, compiler-nix-name, withHLS ? true, withHlint ? true  }:
let tool-version-map = import ./tool-map.nix;
    tool = tool-name: pkgs.haskell-nix.tool compiler-nix-name tool-name (tool-version-map compiler-nix-name tool-name);
    cabal-install = tool "cabal"; in
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
    constraints:
    HsOpenSSL +use-pkg-config,
    zlib +pkg-config
    pcre-lite +pkg-config
    '';

    shellHook = with pkgs; ''
    export PS1="\[\033[01;33m\][\w]$\[\033[00m\] "
    ${figlet}/bin/figlet -f rectangles 'IOG Haskell Shell'
    ${figlet}/bin/figlet -f small "*= static edition =*"
    echo "NOTE (macos): you can use fixup-nix-deps FILE, to fix iconv, ffi, and zlib dependencies that point to the /nix/store"
    export CABAL_DIR=$HOME/.cabal-static
    echo "CABAL_DIR set to $CABAL_DIR"
    echo "Quirks:"
    echo -e "\tif you have the zlib, HsOpenSSL, or digest package in your dependency tree, please make sure to"
    echo -e "\techo \"\$CABAL_PROJECT_LOCAL_TEMPLATE\" > cabal.project.local"
    function cabal() {
    case "$1" in
        build)
        ${cabal-install}/bin/cabal \
            "$@" \
            $NIX_CABAL_FLAGS \
            --disable-shared --enable-static \
        ;;
        clean)
        ${cabal-install}/bin/cabal "$@"
        ;;
        *)
        ${cabal-install}/bin/cabal $NIX_CABAL_FLAGS "$@"
        ;;
    esac
    }

    function fixup-nix-deps() {
    for nixlib in $(otool -L "$1" |awk '/nix\/store/{ print $1 }'); do
        case "$nixlib" in
        *libiconv.dylib) install_name_tool -change "$nixlib" /usr/lib/libiconv.dylib "$1" ;;
        *libffi.*.dylib) install_name_tool -change "$nixlib" /usr/lib/libffi.dylib   "$1" ;;
        *libz.dylib)     install_name_tool -change "$nixlib" /usr/lib/libz.dylib     "$1" ;;
        *) ;;
        esac
    done
    }
    '';
    buildInputs = [];

    nativeBuildInputs = [ (compiler.override { enableShared = true; }) ] ++ (with pkgs; [
        haskell-nix.cabal-install.${compiler-nix-name}
        pkgconfig
        stdenv.cc.cc.lib ]) ++ (with pkgs.buildPackages; [
        cddl
        cbor-diag
    ])
    ++ pkgs.lib.optional withHLS (tool "haskell-language-server")
    ++ pkgs.lib.optional withHlint (tool "hlint")
    ;
})
