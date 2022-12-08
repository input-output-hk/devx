# see https://haskell-language-server.readthedocs.io/en/latest/support/ghc-version-support.html
# so we assume "latest" for all hls. 
# for hlint however, we need hlint-3.3 for ghc-8.10.7.
let fixed-versions = { "hlint" = { "ghc8107" = "3.3"; }; }; in
compiler-nix-name: tool: fixed-versions.${tool}.${compiler-nix-name} or "latest"