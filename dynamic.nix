# define a development shell for dynamically linked applications (default)
{ self, pkgs, compiler, compiler-nix-name, toolsModule, withHLS ? true, withHlint ? true, withIOG ? true, withIOGFull ? false, withGHCTooling ? false }:
let tool-version-map = (import ./tool-map.nix) self;
    tool = tool-name: pkgs.pkgsBuildBuild.haskell-nix.tool compiler-nix-name tool-name [(tool-version-map compiler-nix-name tool-name) toolsModule];
    cabal-install = tool "cabal";
    haskell-tools =
         pkgs.lib.optionalAttrs (withHLS && (compiler-not-in (
           pkgs.lib.optional (builtins.compareVersions compiler.version "9.11" >= 0) compiler-nix-name
        ++ pkgs.lib.optional (pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64) "ghc902") "Haskell Language Server")) { hls = tool "haskell-language-server"; }
      // pkgs.lib.optionalAttrs (withHlint && (compiler-not-in (
           pkgs.lib.optional (builtins.compareVersions compiler.version "9.11" >= 0) compiler-nix-name
        ++ pkgs.lib.optional (pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64) "ghc902") "HLint")) { hlint = tool "hlint"; };
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

    # this wrapped-cabal is for now the identity, but it's the same logic we
    # have in the static configuration, and we may imagine needing to inject
    # some flags into cabal (temporarily), hence we'll keep this functionality
    # here.
    wrapped-cabal = pkgs.writeShellApplication {
        name = "cabal";
        runtimeInputs = [ cabal-install pkgs.curl ];
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
    quirks = (import ./quirks.nix { inherit pkgs; });
in
pkgs.mkShell {
    # The `cabal` overrride in this shell-hook doesn't do much yet. But
    # we may need to massage cabal a bit, so we'll leave it in here for
    # consistency with the one in static.nix.
    shellHook =
        with pkgs;
        let flavor = "${compiler-nix-name}"
                   + lib.optionalString (!withHLS && !withHlint) "-minimal"
                   + lib.optionalString withIOG                  "-iog"
                   + lib.optionalString withIOGFull              "-full"
                   + lib.optionalString withGHCTooling           "-ghc"
                   ;
        in ''
        export PS1="\[\033[01;33m\][\w]$\[\033[00m\] "
        ${figlet}/bin/figlet -f rectangles 'IOG Haskell Shell'
        echo "Revision (input-output-hk/devx): ${if self ? rev then self.rev else "unknown/dirty checkout"}."
        # change the CABAL_HOME so it doesn't confict with the default .cabal store outside of the shell
        # which might have a different environment (and thus cflags, ldflags, ...) rendering them mutually
        # incompatbile.
        export CABAL_DIR=$HOME/.cabal-devx
        echo "CABAL_DIR set to $CABAL_DIR"
        echo ""
    '' + (quirks.hint flavor)
    # this one is only needed on macOS right now, due to a bug in loading libcrypto.
    # The build will error with -6 due to "loading libcrypto in an unsafe way"
    + lib.optionalString stdenv.hostPlatform.isMacOS
    ''
    export DYLD_LIBRARY_PATH="${lib.getLib openssl}/lib"
    ''
    + lib.optionalString withGHCTooling ''
    export HADRIAN_CONFIGURE_FLAGS="--with-gmp-includes=\"${lib.getDev gmp}/include\" --with-gmp-libraries=\"${lib.getLib gmp}/lib\""
    echo "HADRIAN_CONFIGURE_FLAGS set to $HADRIAN_CONFIGURE_FLAGS"
    echo "To build GHC, run"
    echo "  ./boot"
    echo "  ./configure \"$HADRIAN_CONFIGURE_FLAGS\""
    echo "  ./hadrian/build -j"
    '';

    buildInputs =
      let
        inherit (pkgs) lib stdenv;
        inherit (lib) attrValues optional optionals;
      in [
        wrapped-cabal
        fixup-nix-deps
        compiler
        # for libstdc++; ghc not being able to find this properly is bad,
        # it _should_ probably call out to a g++ or clang++ but doesn't.
        stdenv.cc.cc.lib
      ]
      ++ (with pkgs; [
        openssl
        pcre
        pkg-config
        zlib
      ])
      ++ optional stdenv.hostPlatform.isLinux pkgs.systemd
      ++ optionals withIOG (
        with pkgs; [
          cbor-diag
          cddl
          gh
          icu
          jq
          libblst
          libsodium-vrf
          secp256k1
          yq-go
        ]
        ++ optionals withIOGFull (
          [ postgresql ] ++ (optional stdenv.hostPlatform.isAarch64 R)
        )
      )
      ++ attrValues haskell-tools
      ++ optionals withGHCTooling (
        with pkgs; [ python3 automake autoconf alex happy git libffi.dev ]
      )
    ;

    passthru = {
      plans = if haskell-tools == {} then {} else
        pkgs.pkgsBuildBuild.linkFarm "plans"
          (builtins.mapAttrs (_: t: t.project.plan-nix) haskell-tools);
    };
}
