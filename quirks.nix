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
    if [ "$GITHUB_ACTIONS" = "true" ]; then
	    echo "::notice::Hint: to reproduce this environment locally, use either:" \
           "\`nix develop github:input-output-hk/devx#${flavor}\`, or" \
           "\`docker run -it -v \$(pwd):/workspaces ghcr.io/input-output-hk/devx-devcontainer:x86_64-linux.${flavor}\`"
    fi
  '';
}
