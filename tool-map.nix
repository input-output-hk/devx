# see https://haskell-language-server.readthedocs.io/en/latest/support/ghc-version-support.html
# so we assume "latest" for all hls. 
# for hlint however, we need hlint-3.3 for ghc-8.10.7.
let fixed-versions = { "hlint" = { "ghc8107" = "3.3"; }; }; in
compiler-nix-name: tool:
  if tool == "haskell-language-server"
    then {pkgs, ...}: rec {
      # Use the github source of HLS that is tested with haskell.nix CI
      src = pkgs.haskell-nix.sources."hls-1.10";
      # `tool` normally ignores the `cabal.project` (if there is one in the hackage source).
      # We need to use the github one (since it has settings to make hls build).
      cabalProject = __readFile (src + "/cabal.project");
      # sha256 for a `source-repository-package` in the `cabal.project` file.
      sha256map."https://github.com/pepeiborra/ekg-json"."7a0af7a8fd38045fd15fb13445bdcc7085325460" = "sha256-fVwKxGgM0S4Kv/4egVAAiAjV7QB5PBqMVMCfsv7otIQ=";
    }
  else fixed-versions.${tool}.${compiler-nix-name} or "latest"