# see https://haskell-language-server.readthedocs.io/en/latest/support/ghc-version-support.html
# so we assume "latest" for all hls.
# for hlint however, we need hlint-3.3 for ghc-8.10.7.
let
  fixed-versions = { "hlint" = { "ghc8107" = { version = "3.4.1"; };
                                 "ghc902"  = { version = "3.5"; };
                                 "ghc928"  = { version = "3.6.1"; };
                               }; };
  cabalProjectLocal = ''
        repository head.hackage.ghc.haskell.org
          url: https://ghc.gitlab.haskell.org/head.hackage/
          secure: True
          key-threshold: 3
          root-keys:
             f76d08be13e9a61a377a85e2fb63f4c5435d40f8feb3e12eb05905edb8cdea89
             26021a13b401500c8eb2761ca95c61f2d625bfef951b939a8124ed12ecf07329
             7541f32a4ccca4f97aea3b22f5e593ba2c0267546016b992dfadcd2fe944e55d
          --sha256: sha256-aVI93DtHziicNn2mGli0YE+bC5BeT7mOQQETp2Thi68=

        if impl(ghc < 9.11)
          active-repositories: hackage.haskell.org
        else
          active-repositories: hackage.haskell.org, head.hackage.ghc.haskell.org
  '';
in
compiler-nix-name: tool: {
  # for HLS, we rely on the cabal.project configuration from the upstream project to have the correct configuration.
  # Building HLS from hackage requires setting all those constraints as well, and just isn't practical to do for each
  # HLS release. Therefore we rely on the HLS upstream repository to provide the proper configuration information.
  haskell-language-server = {pkgs, ...}: rec {
      # Use the github source of HLS that is tested with haskell.nix CI
      src = { "ghc8107" = pkgs.haskell-nix.sources."hls-2.2"; }.${compiler-nix-name} or pkgs.haskell-nix.sources."hls-2.4";
      # `tool` normally ignores the `cabal.project` (if there is one in the hackage source).
      # We need to use the github one (since it has settings to make hls build).
      cabalProject = __readFile (src + "/cabal.project");
      inherit cabalProjectLocal;
      # sha256 for a `source-repository-package` in the `cabal.project` file.
      sha256map."https://github.com/pepeiborra/ekg-json"."7a0af7a8fd38045fd15fb13445bdcc7085325460" = "sha256-fVwKxGgM0S4Kv/4egVAAiAjV7QB5PBqMVMCfsv7otIQ=";
  };
  happy = { version = "1.20.1.1"; inherit cabalProjectLocal; };
  alex = { version = "3.2.7.3"; inherit cabalProjectLocal; };
}.${tool} or fixed-versions.${tool}.${compiler-nix-name} or {}
