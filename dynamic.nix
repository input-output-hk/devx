# define a development shell for dynamically linked applications (default)
{ system, pkgs, compiler, compiler-nix-name, withHLS ? true, withHlint ? true }:
let tool-version-map = import ./tool-map.nix;
    tool = tool-name: pkgs.haskell-nix.tool compiler-nix-name tool-name (tool-version-map compiler-nix-name tool-name);
    cabal-install = tool "cabal"; in
pkgs.mkShell {
    # The `cabal` overrride in this shell-hook doesn't do much yet. But
    # we may need to massage cabal a bit, so we'll leave it in here for
    # consistency with the one in static.nix.
    shellHook = with pkgs; ''
        export PS1="\[\033[01;33m\][\w]$\[\033[00m\] "

        ${figlet}/bin/figlet -f rectangles 'IOG Haskell Shell'
        function cabal() {
        case "$1" in
            build)
            ${cabal-install}/bin/cabal "$@"
            ;;
            clean)
            ${cabal-install}/bin/cabal "$@"
            ;;
            *)
            ${cabal-install}/bin/cabal "$@"
            ;;
        esac
        }
    '' ++ (if system == "darwin-aarch64" || system == "darwin-x86_64" then ''
    # this one is only needed on macOS right now, due to a bug in loading libcrypto.
    export DYLD_LIBRARY_PATH=$(pkg-config --libs-only-L libcrypto|cut -c 3-)
    '' else "");
    buildInputs = [
        compiler
        cabal-install
        pkgs.pkgconfig
        # for libstdc++; ghc not being able to find this properly is bad,
        # it _should_ probably call out to a g++ or clang++ but doesn't.
        pkgs.stdenv.cc.cc.lib

        pkgs.cddl
        pkgs.cbor-diag

    ] ++ map pkgs.lib.getDev (
        with pkgs;
        [
            libsodium-vrf
            secp256k1
            R_4_1_3
            zlib
            openssl
            pcre
        ]
        ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux systemd
    )
    ++ pkgs.lib.optional withHLS (tool "haskell-language-server")
    ++ pkgs.lib.optional withHlint (tool "hlint")
    ;
}
