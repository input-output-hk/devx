{ self, pkgs, compiler, compiler-nix-name, toolsModule, withHLS ? true, withHlint ? true, withIOG ? true, withIOGFull ? false }:
let tool-version-map = (import ./tool-map.nix) self;
    tool = tool-name: pkgs.pkgsBuildBuild.haskell-nix.tool compiler-nix-name tool-name [(tool-version-map compiler-nix-name tool-name) toolsModule];
    cabal-install = tool "cabal";
    haskell-tools =
        pkgs.lib.optionalAttrs (withHLS && (compiler-not-in (
           pkgs.lib.optional (builtins.compareVersions compiler.version "9.11" >= 0) compiler-nix-name) "Haskell Language Server")) { hls = tool "haskell-language-server"; }
      // pkgs.lib.optionalAttrs (withHlint && (compiler-not-in (
           pkgs.lib.optional (builtins.compareVersions compiler.version "9.11" >= 0) compiler-nix-name) "HLint")) { hlint = tool "hlint"; };
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
            *libiconv.dylib)    install_name_tool -change "$nixlib" /usr/lib/libiconv.dylib   "$1" ;;
            *libiconv.2.dylib)  install_name_tool -change "$nixlib" /usr/lib/libiconv.2.dylib "$1" ;;
            *libffi.*.dylib)    install_name_tool -change "$nixlib" /usr/lib/libffi.dylib     "$1" ;;
            *libc++.*.dylib)    install_name_tool -change "$nixlib" /usr/lib/libc++.dylib     "$1" ;;
            *libz.dylib)        install_name_tool -change "$nixlib" /usr/lib/libz.dylib       "$1" ;;
            *libresolv.*.dylib) install_name_tool -change "$nixlib" /usr/lib/libresolv.dylib  "$1" ;;
            *) ;;
          esac
        done
      '';
    };
    # A cabal-install wrapper that sets the appropriate static flags
    wrapped-cabal = let
        cabalRuntimeInputs = [ cabal-install pkgs.curl ];
      in (pkgs.writeShellApplication {
        name = "cabal";
        runtimeInputs = cabalRuntimeInputs;
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
                --ghc-option=-L${lib.getLib static-libblst}/lib \
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
      }).overrideAttrs (old: {
        # Propagate runtimeInputs so $stdenv/setup adds them to PATH for the
        # whole shell environment. writeShellApplication only injects them
        # inside the wrapper script itself; without propagation, other programs
        # in -env container scripts (e.g. GHC's bootstrap cabal) can't find them.
        propagatedNativeBuildInputs = (old.propagatedNativeBuildInputs or []) ++ cabalRuntimeInputs;
      });
    quirks = (import ./quirks.nix { inherit pkgs; static = true; });
in
pkgs.mkShell (rec {
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

    inherit (quirks) CABAL_PROJECT_LOCAL_TEMPLATE;

    # This is required to prevent
    #
    #    WARNING: [...]ghc is loading libcrypto in an unsafe way
    #    [...]
    #    The build process terminated with exit code -6
    #
    # We want to load the libcrypto from the openssl path, not from
    # the system path.
    DYLD_LIBRARY_PATH= with pkgs; "${lib.getLib openssl}/lib";

    shellHook =
        with pkgs;
        let flavor = "${compiler-nix-name}-static"
                   + lib.optionalString (!withHLS && !withHlint) "-minimal"
                   + lib.optionalString withIOG                  "-iog"
                   ;
        in ''
        export PS1="\[\033[01;33m\][\w]$\[\033[00m\] "
        export DYLD_LIBRARY_PATH="${DYLD_LIBRARY_PATH}";
        ${figlet}/bin/figlet -f rectangles 'IOG Haskell Shell'
        ${figlet}/bin/figlet -f small "*= static edition =*"
        echo "Revision (input-output-hk/devx): ${if self ? rev then self.rev else "unknown/dirty checkout"}."
        echo "NOTE (macos): you can use fixup-nix-deps FILE, to fix iconv, ffi, and zlib dependencies that point to the /nix/store"
        export CABAL_DIR=$HOME/.cabal-static
        echo "CABAL_DIR set to $CABAL_DIR"
        echo "DYLD_LIBRARY_PATH set to $DYLD_LIBRARY_PATH"
        echo ""
    '' + (quirks.hint flavor) + quirks.shellHook;
    # these are _target_ libs, e.g. ones we want to link the build
    # product against. These are also the ones that showup in the
    # PKG_CONFIG_PATH.
    buildInputs = with pkgs; ([
        # for libstdc++; ghc not being able to find this properly is bad,
        # it _should_ probably call out to a g++ or clang++ but doesn't.
        stdenv.cc.cc.lib
    ]) ++ map lib.getDev ([
        pcre
        static-gmp
        static-openssl
        static-zlib
    ] ++ lib.optionals withIOG [
        static-libblst
        static-libsodium-vrf
        static-secp256k1
        icu           # for cardano-cli
        gh
        jq
        yq-go
    ] ++ lib.optionals withIOGFull [
        # for plutus; but unavailable for static/aarch64, or static even.
        # R fails in almost any direction. For now, we just disable it.
        (if (pkgs.stdenv.hostPlatform.isAarch64 || pkgs.stdenv.hostPlatform.isMusl) then null else R)
        postgresql # for db-sync
    ]);

    # these are _native_ libs, we need to drive the compilation environment
    # they will _not_ be part of the final build product.
    nativeBuildInputs = [
        wrapped-cabal
        fixup-nix-deps
        # We are happy to use a _shared_ compiler; we only want the build
        # products to be static.
        (compiler.override { enableShared = true; })
    ] ++ (with pkgs; [
        (pkgs.pkg-config or pkgconfig)
        stdenv.cc.cc.lib ]) ++ (with pkgs.buildPackages; [
    ])
    ++ builtins.attrValues haskell-tools
    ++ pkgs.lib.optional withIOG (with pkgs; [ cddl cbor-diag ])
    ;

    passthru = {
      plans = if haskell-tools == {} then {} else
        pkgs.pkgsBuildBuild.linkFarm "plans"
          (builtins.mapAttrs (_: t: t.project.plan-nix) haskell-tools);
    };
})
