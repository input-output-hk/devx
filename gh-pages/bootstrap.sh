#! /bin/bash
set -euo pipefail

# FIXME: this file should not be longer needed if we succeed to rely only on
# hydra latest build product!
# https://input-output-hk.github.io/adrestia/cardano-wallet/contributing/Hydra

# End-user DevX could also be potentially improved through this script: e.g,
# by helping new users to set up Nix using Determinate Systems new installer,
# or detect that it's used in a GA context and advise installing Nix with Cachix install Nix action.

# TODO: you can give it a try with ...
# curl --proto '=https' --tlsv1.2 -sSf -L https://yvan-sraka.github.io/devx/ | sh -s -- ghc8107-static-minimal

if ! command -v nix >/dev/null 2>&1; then
  echo "This script requires nix to be installed; you don't appear to have nix available ..."
  if [ "$GITHUB_ACTIONS" == "true" ]; then
    echo "... and it seems that you run it inside a GitHub Action!

You can setup Nix using https://github.com/cachix/install-nix-action, e.g.:

  - name: Install Nix with good defaults
    uses: cachix/install-nix-action
    with:
      extra_nix_config: |
        trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
        substituters = https://cache.iog.io/ https://cache.nixos.org/"
    # TODO: explain how to use the shell with something better than:
    #
    # - name: Add devx-shell
    #   run: |
    #     echo $PATH
    #     cat <<EOF > /usr/local/bin/devx-shell
    #     #!/bin/bash
    #     nix develop github:input-output-hk/devx#ghc8107-static-minimal \
    #       --command /usr/bin/bash <(echo 'eval "\$shellHook\"'; cat "$1")
    #     EOF
    #     chmod +x /usr/local/bin/devx-shell
    # - name: Build
    #   shell: devx-shell {0}
    #   run: |
    #     cabal update
    #     cabal build
    exit 1
  else
    echo "... we can run https://github.com/DeterminateSystems/nix-installer for you!"
    echo "Do you want to install nix now? (y/n)"
    read -r answer
    case "$answer" in
      y|Y)
        curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
        ;;
      *)
        echo "Feel free to install (or not) nix your way :)"
        exit 1
        ;;
    esac
  fi
fi
# TODO: figure out the best way of doing ...
#
# if [[ -e /nix/store/...path-to-rc file ]]; then
#   <launch directly>
# else
#   curl + import + launch
# fi
#
# ... rather than?
nix develop "github:yvan-sraka/static-closure#$1" --impure --no-write-lock-file --refresh --accept-flake-config
