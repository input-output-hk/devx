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
        });
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
         cddl-tools = (final: prev: {
          cbor-diag = final.callPackage ./pkgs/cbor-diag { };
          cddl = final.callPackage ./pkgs/cddl { };          
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
         in rec {
           # These are for checking IOG projects build in an environment
           # without haskell packages built by haskell.nix.
           #
           # Usage:
           #
           # nix develop github:input-output-hk/devx#ghc924 --no-write-lock-file -c cabal build
           #
           devShells =
             let compilers = pkgs: builtins.removeAttrs pkgs.haskell-nix.compiler
               # Exclude old versions of GHC to speed up `nix flake check`
               [ "ghc844"
                 "ghc861" "ghc862" "ghc863" "ghc864" "ghc865"
                 "ghc881" "ghc882" "ghc883" "ghc884"
                 "ghc8101" "ghc8102" "ghc8103" "ghc8104" "ghc8105" "ghc8106" "ghc810420210212"
                 "ghc901"
                 "ghc921" "ghc922" "ghc923"];
             in (__mapAttrs (compiler-nix-name: compiler:
              pkgs.mkShell {
                shellHook = with pkgs; ''
                  export PS1="\[\033[01;33m\][\w]$\[\033[00m\] "

                  ${figlet}/bin/figlet -f rectangles 'IOG Haskell Shell'
                  function cabal() {
                    case "$1" in 
                      build) 
                        ${haskell-nix.cabal-install.${compiler-nix-name}}/bin/cabal \
                          "$@"
                      ;;
                      clean)
                        ${haskell-nix.cabal-install.${compiler-nix-name}}/bin/cabal "$@"
                      ;;
                      *)
                        ${haskell-nix.cabal-install.${compiler-nix-name}}/bin/cabal "$@"
                      ;;
                    esac
                  }
                '';
                buildInputs = [
                  compiler
                  pkgs.haskell-nix.cabal-install.${compiler-nix-name}
                  pkgs.pkgconfig
                  # for libstdc++; ghc not being able to find this properly is bad,
                  # it _should_ probably call out to a g++ or clang++ but doesn't.
                  pkgs.stdenv.cc.cc.lib

                  pkgs.cddl
                  pkgs.cbor-diag

                ] ++ map pkgs.lib.getDev (with pkgs; [ libsodium-vrf secp256k1 R_4_1_3 zlib openssl ] ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux systemd);
              }) (compilers pkgs) //
              (let static-pkgs = if pkgs.stdenv.hostPlatform.isLinux then pkgs.pkgsCross.musl64 else pkgs; in
              pkgs.lib.mapAttrs' (compiler-nix-name: compiler: 
                pkgs.lib.nameValuePair "${compiler-nix-name}-static" (static-pkgs.mkShell (rec {
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
                  NIX_CABAL_FLAGS = pkgs.lib.optionals static-pkgs.stdenv.hostPlatform.isMusl [
                    "--with-ghc=x86_64-unknown-linux-musl-ghc"
                    "--with-ghc-pkg=x86_64-unknown-linux-musl-ghc-pkg"
                    "--with-hsc2hs=x86_64-unknown-linux-musl-hsc2hs"
                    # ensure that the linker knows we want a static build product
                    "--enable-executable-static"
                  ];
                  hardeningDisable = pkgs.lib.optionals static-pkgs.stdenv.hostPlatform.isMusl [ "format" "pie" ];

                  CABAL_PROJECT_LOCAL_TEMPLATE = with static-pkgs; ''
                  package digest
                    extra-lib-dirs: ${zlib}/lib
                  constraints:
                    HsOpenSSL +use-pkg-config,
                    zlib +pkg-config
                  '';

                  shellHook = with static-pkgs; ''
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
                        ${haskell-nix.cabal-install.${compiler-nix-name}}/bin/cabal \
                          "$@" \
                          $NIX_CABAL_FLAGS \
                          --disable-shared --enable-static \
                          --ghc-option=-L${lib.getLib static-gmp}/lib \
                          --ghc-option=-L${lib.getLib static-libsodium-vrf}/lib \
                          --ghc-option=-L${lib.getLib static-secp256k1}/lib \
                          --ghc-option=-L${lib.getLib static-openssl}/lib
                      ;;
                      clean)
                        ${haskell-nix.cabal-install.${compiler-nix-name}}/bin/cabal "$@"
                      ;;
                      *)
                        ${haskell-nix.cabal-install.${compiler-nix-name}}/bin/cabal $NIX_CABAL_FLAGS "$@"
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
                  buildInputs = (with static-pkgs; [
                    # for libstdc++; ghc not being able to find this properly is bad,
                    # it _should_ probably call out to a g++ or clang++ but doesn't.
                    stdenv.cc.cc.lib
                  ]) ++ map pkgs.lib.getDev (with static-pkgs; [ libsodium-vrf secp256k1 static-gmp
                    # R_4_1_3
                    zlib
                    openssl
                  ]);

                  nativeBuildInputs = [ (compiler.override { enableShared = true; }) ] ++ (with static-pkgs; [
                    haskell-nix.cabal-install.${compiler-nix-name}
                    pkgconfig
                    stdenv.cc.cc.lib
                    cddl
                    cbor-diag
                  ]);
                }))) (compilers static-pkgs.buildPackages)));
        hydraJobs = devShells;
       });
}