# see https://haskell-language-server.readthedocs.io/en/latest/support/ghc-version-support.html
# so we assume "latest" for all hls.
# for hlint however, we need hlint-3.3 for ghc-8.10.7.
let fixed-versions = { "hlint" = { "ghc8107" = { version = "3.3"; }; }; }; in
compiler-nix-name: tool: {
  # for HLS, we rely on the cabal.project configuration from the upstream project to have the correct configuration.
  # Building HLS from hackage requires setting all those constraints as well, and just isn't practical to do for each
  # HLS release. Therefore we rely on the HLS upstream repository to provide the proper configuration information.
  haskell-language-server = {pkgs, ...}: rec {
      # Use the github source of HLS that is tested with haskell.nix CI
      src = pkgs.haskell-nix.sources."hls-2.0";
      # `tool` normally ignores the `cabal.project` (if there is one in the hackage source).
      # We need to use the github one (since it has settings to make hls build).
      cabalProject = __readFile (src + "/cabal.project");
      # sha256 for a `source-repository-package` in the `cabal.project` file.
      sha256map."https://github.com/pepeiborra/ekg-json"."7a0af7a8fd38045fd15fb13445bdcc7085325460" = "sha256-fVwKxGgM0S4Kv/4egVAAiAjV7QB5PBqMVMCfsv7otIQ=";
  };
  happy = { version = "1.20.1.1"; };
  alex = { version = "3.2.7.3"; };
}.${tool} or fixed-versions.${tool}.${compiler-nix-name} or {}
