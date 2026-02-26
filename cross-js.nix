{ self, pkgs, compiler, compiler-nix-name, toolsModule, withHLS ? true, withHlint ? true, withIOG ? true  }:
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

    writers = import ./writers.nix { inherit pkgs; };

    # * wrapped tools:
    # A cabal-install wrapper that sets the appropriate static flags.
    # See writers.nix for why writeShellApplicationWithRuntime is needed.
    wrapped-cabal = writers.writeShellApplicationWithRuntime {
        name = "cabal";
        runtimeInputs = [ cabal-install pkgs.curl pkgs.cacert ];
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
          ${compiler}/bin/${compiler.targetPrefix}hsc2hs --cross-compile "$@"
        '';
    };
    quirks = (import ./quirks.nix { inherit pkgs; });
in
pkgs.mkShell ({
    # curl's built-in CA bundle path is /no-cert-file.crt (a sentinel from
    # nixpkgs when cacert is absent at build time). curl does NOT check
    # SSL_CERT_FILE — only CURL_CA_BUNDLE and its built-in path. Set both
    # so curl and OpenSSL-based tools find the CA bundle in containers.
    CURL_CA_BUNDLE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
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
    "--with-ghc=javascript-unknown-ghcjs-ghc"
    "--with-ghc-pkg=javascript-unknown-ghcjs-ghc-pkg"
    "--with-hsc2hs=javascript-unknown-ghcjs-hsc2hs"
    # ensure that the linker knows we want a static build product
    # "--enable-executable-static"
    ];
    # hardeningDisable = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isMusl [ "format" "pie" ];

    inherit (quirks) CABAL_PROJECT_LOCAL_TEMPLATE;

    shellHook =
        with pkgs;
        let flavor = "${compiler-nix-name}-js"
                   + lib.optionalString (!withHLS && !withHlint) "-minimal"
                   + lib.optionalString withIOG                  "-iog"
                   ;
        in ''
        export PS1="\[\033[01;33m\][\w]$\[\033[00m\] "
        ${figlet}/bin/figlet -f rectangles 'IOG Haskell Shell'
        ${figlet}/bin/figlet -f small "*= JS edition =*"
        echo "Revision (input-output-hk/devx): ${if self ? rev then self.rev else "unknown/dirty checkout"}."
        export CABAL_DIR=$HOME/.cabal-js
        echo "CABAL_DIR set to $CABAL_DIR"
        echo ""
    '' + (quirks.hint flavor) + quirks.shellHook;
    buildInputs = [];

    nativeBuildInputs = [ wrapped-hsc2hs wrapped-cabal compiler ] ++ (with pkgs; [
        nodejs # helpful to evaluate output on the commandline.
        cabal-install
        (pkgs.pkg-config or pkgconfig)
        (tool "happy")
        (tool "alex")
        perl
        stdenv.cc.cc.lib
        which
    ]) ++ (with pkgs.buildPackages; [
    ])
    ++ builtins.attrValues haskell-tools
    ++ pkgs.lib.optional withIOG
        (with pkgs; [ cddl cbor-diag ]
        ++ map pkgs.lib.getDev (with pkgs; [
            libblst libsodium-vrf secp256k1
        ]))
    ;

    passthru = {
      plans = if haskell-tools == {} then {} else
        pkgs.pkgsBuildBuild.linkFarm "plans"
          (builtins.mapAttrs (_: t: t.project.plan-nix) haskell-tools);
    };
})
