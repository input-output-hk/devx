{
    description = "Minimal devshell flake for haskell";

    inputs.haskellNix.url = "github:input-output-hk/haskell.nix";
    inputs.nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    inputs.flake-utils.url = "github:numtide/flake-utils";

    outputs = { self, nixpkgs, flake-utils, haskellNix }: 
    let overlays = {
         crypto = final: prev: {
          libsodium-vrf = final.callPackage ({ stdenv, lib, fetchFromGitHub, autoreconfHook }:
            stdenv.mkDerivation rec {
                name = "libsodium-1.0.18";

                src = fetchFromGitHub {
                    owner = "input-output-hk";
                    repo = "libsodium";
                    rev = "11bb20dba02b013bf1d83e3c16c51eab2ff07efc";
                    sha256 = "1h9fcwra610vmh0inkdkqs3bfs83xl5dk146dqx440wwh9pn4n4w";
                };

                nativeBuildInputs = [ autoreconfHook ];

                configureFlags = [ "--enable-static" ];

                outputs = [ "out" "dev" ];
                separateDebugInfo = stdenv.isLinux && stdenv.hostPlatform.libc != "musl";

                enableParallelBuilding = true;

                doCheck = true;

                meta = with lib; {
                    description = "A modern and easy-to-use crypto library - VRF fork";
                    homepage = "http://doc.libsodium.org/";
                    license = licenses.isc;
                    maintainers = [ "tdammers" "nclarke" ];
                    platforms = platforms.all;
                };
            }) {};
        };
         # the haskell inline-r package depends on internals of the R
         # project that have been hidden in R 4.2+. See
         # https://github.com/tweag/HaskellR/issues/374
         oldR = (final: prev: {
           R_4_1_3 = final.R.overrideDerivation (old: rec {
             version = "4.1.3";
             patches = []; # upstream patches will most likely break this build, as they are specific to a different version.
             src = final.fetchurl {
               url = "https://cran.r-project.org/src/base/R-${final.lib.versions.major version}/${old.pname}-${version}.tar.gz";
               sha256 = "sha256-Ff9bMzxhCUBgsqUunB2OxVzELdAp45yiKr2qkJUm/tY="; };
             });
         });
       };
       supportedSystems = [
            "x86_64-linux"
            "x86_64-darwin"
            "aarch64-linux"
            "aarch64-darwin"
       ];       
    in flake-utils.lib.eachSystem supportedSystems (system:
         let 
           pkgs = import nixpkgs {
             overlays = [haskellNix.overlay] ++ __attrValues overlays;
             inherit system;
             inherit (haskellNix) config;
           };
         in {
           # These are for checking IOG projects build in an environment
           # without haskell packages built by haskell.nix.
           #
           # Usage:
           #
           # nix develop github:input-output-hk/devx#ghc924 --no-write-lock-file -c cabal build
           #
           devShells =
             let compilers = builtins.removeAttrs pkgs.haskell-nix.compiler
               # Exclude old versions of GHC to speed up `nix flake check`
               [ "ghc844"
                 "ghc861" "ghc862" "ghc863" "ghc864"
                 "ghc881" "ghc882" "ghc883"
                 "ghc8101" "ghc8102" "ghc8103" "ghc8104" "ghc8105" "ghc8106" "ghc810420210212"
                 "ghc901"
                 "ghc921" "ghc922" "ghc923"];

                 static-libsodium-vrf = pkgs.libsodium-vrf.overrideDerivation (old: { configureFlags = old.configureFlags ++ [ "--disable-shared" ]; });
                 static-secp256k1 = pkgs.secp256k1.overrideDerivation (old: { configureFlags = old.configureFlags ++ ["--enable-static" "--disable-shared" ]; });
                 static-gmp = (pkgs.gmp.override { withStatic = true; }).overrideDerivation (old: { configureFlags = old.configureFlags ++ ["--enable-static" "--disable-shared" ]; });
                 
             in (__mapAttrs (compiler-nix-name: compiler:
              pkgs.mkShell {
                buildInputs = [
                  compiler
                  pkgs.haskell-nix.cabal-install.${compiler-nix-name}
                  pkgs.pkgconfig
                  # for libstdc++; ghc not being able to find this properly is bad,
                  # it _should_ probably call out to a g++ or clang++ but doesn't.
                  pkgs.stdenv.cc.cc.lib
                ] ++ map pkgs.lib.getDev (with pkgs; [ libsodium-vrf secp256k1 R_4_1_3 zlib openssl ] ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux systemd);
              }) compilers //
              pkgs.lib.mapAttrs' (compiler-nix-name: compiler: 
                pkgs.lib.nameValuePair "${compiler-nix-name}-static" (pkgs.mkShell {
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
                  shellHook = ''
                  echo "WARNING: Due to quirks in HsOpenSSL, you want to run the following..."
                  echo "ln -s ${pkgs.lib.getDev pkgs.openssl}/lib/libcrypto.dylib $HOME/.cabal/store/ghc-8.10.7/lib/"
                  echo "ln -s ${pkgs.lib.getDev pkgs.openssl}/lib/libssl.dylib    $HOME/.cabal/store/ghc-8.10.7/lib/"
                  echo ""
                  echo "NOTE (macos): you can use fixup-nix-deps FILE, to fix iconv and ffi dependencies that point to the /nix/store"

                  function cabal() {
                    case "$1" in 
                      build) 
                        ${pkgs.haskell-nix.cabal-install.${compiler-nix-name}}/bin/cabal \
                          $@ --disable-shared --enable-static --ghc-option=-L${static-gmp}/lib --ghc-option=-L${static-libsodium-vrf}/lib --ghc-option=-L${static-secp256k1}/lib
                      ;;
                      *)
                        ${pkgs.haskell-nix.cabal-install.${compiler-nix-name}}/bin/cabal $@
                      ;;
                    esac
                  }

                  function fixup-nix-deps() {
                    for nixlib in $(otool -L "$1" |awk '/nix\/store/{ print $1 }'); do
                      case "$nixlib" in
                        *libiconv.dylib) install_name_tool -change "$nixlib" /usr/lib/libiconv.dylib "$1" ;;
                        *libffi.*.dylib) install_name_tool -change "$nixlib" /usr/lib/libffi.dylib   "$1" ;;
                        *) ;;
                      esac
                    done
                  }
                  '';
                  buildInputs = [
                    compiler
                    pkgs.haskell-nix.cabal-install.${compiler-nix-name}
                    pkgs.pkgconfig
                    # for libstdc++; ghc not being able to find this properly is bad,
                    # it _should_ probably call out to a g++ or clang++ but doesn't.
                    pkgs.stdenv.cc.cc.lib
                  ] ++ map pkgs.lib.getDev (with pkgs; [ static-libsodium-vrf static-secp256k1 static-gmp
                    R_4_1_3
                    (zlib.static)
                    (openssl.override { static = true; })
                  ] ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux systemd);                  
                })) compilers);
       });
}