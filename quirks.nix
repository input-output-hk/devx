{ pkgs, static ? false }: rec {
  CABAL_PROJECT_LOCAL_TEMPLATE = with pkgs; ''
  package digest
  ${if static then "extra-lib-dirs: ${zlib}/lib ${pcre}/lib" else ""}
  constraints:
    HsOpenSSL +use-pkg-config,
    zlib +pkg-config,
    pcre-lite +pkg-config
  '';
  template = pkgs.writeTextFile {
    name = "cabal.project.local";
    text = CABAL_PROJECT_LOCAL_TEMPLATE;
  };
  shellHook = ''
    echo "Quirks:"
    echo -e "\tif you have the zlib, HsOpenSSL, or digest package in your dependency tree, please make sure to"
    echo -e "\tcat ${template} >> cabal.project.local"
    function patchProjectLocal() {
      cat ${template} >> "$1"
    }
    echo ""
  '';
  hint = flavor: ''
    if [[ "x''${GITHUB_ACTIONS:-}" == xtrue ]]; then
        PREFIX="::notice::Hint:"
    else
        PREFIX="Hint:"
    fi
    if [[ "x''${GITHUB_ACTIONS:-}" == xtrue || "x''${CODESPACES:-}" == xtrue ]]; then
        echo "$PREFIX to reproduce this environment locally, use either:" \
             "\`nix develop github:input-output-hk/devx#${flavor}\`, or" \
             "\`docker run -it -v \$(pwd):/workspaces ghcr.io/input-output-hk/devx-devcontainer:x86_64-linux.${flavor}\`"
    fi
    if [[ "x''${CODESPACES:-}" == xtrue ]]; then
        echo "Quirks:"
        echo -e "\tThe Haskell VSCode extension might ask you \"How do you want the extension to manage/discover HLS and the relevant toolchain?\""
        echo -e "\tChoose \"Manually via PATH\", not \"Automatically via GHCup\""
    fi
  '';
}
