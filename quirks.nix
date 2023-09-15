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
  '';
}
