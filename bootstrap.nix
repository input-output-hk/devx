# This is an experiment around the idea of statically evaluating and cache a
# closure to reduce overall bootstrap time latency and artifacts download size
# of a given developer shell.
#
# The whole thing could be seen as a binary/build cache, but rather at
# closure-level than at derivation-level.

{ devShells, pkgs, supportedSystems, ... }:
with builtins;
let
  # TODO: rather use `pkgs.writeShellApplication` so the script content run
  # against `shellcheck`?
  bootstrapScript = pkgs.writeTextFile {
    name = "bootstrap-devx.sh";
    text = ''
      #! /bin/bash
      set -euo pipefail

      # End-user DevX could also be potentially improved through this script: e.g,
      # by helping new users to set up Nix using Determinate Systems new installer,
      # or detect that it's used in a GA context and advise installing Nix with Cachix install Nix action.

      # 0. Ensure user have nix installed...
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

      # 1. Retrieve user system arch-os value...
      UNAME_OUT="$(uname -a)"
      ARCH="$(echo "$UNAME_OUT" | awk '{print $NF}' | tr '[:upper:]' '[:lower:]')"
      OS="$(echo "$UNAME_OUT" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
      if [[ "$ARCH" == arm64* ]]; then ARCH="aarch64"; fi
      if [[ "$OS" == darwin* ]]; then OS="darwin"; fi
      if [[ "$OS" == linux*  ]]; then OS="linux"; fi
      SYSTEM="$ARCH-$OS"
      DEVSHELL="$1"

      # 2. Generate per system / devShell shell snippet...
      ${toString (map (system: toString (attrValues (mapAttrs (name: value: ''
          if [[ "$SYSTEM" == "${system}" && "$DEVSHELL" == "${name}" ]]; then
            # TODO: @angerman not sure if drvPath is what we want here?
            if [[ ! -e ${value.drvPath} ]]; then
              echo "Warning: this script should be run (the first time) as a trusted Nix user:"
              echo "https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-trusted-users"
              echo "n.b. root is by default the only trusted user on a fresh nix setup!"
              # TODO: ... have to add trusted key in nix.conf?!
              curl "https://ci.zw3rk.com/job/input-output-hk-devx/pullrequest-25/$DEVSHELL-closure.$SYSTEM/latest/download/1" | unzip | nix-store --import
            fi
            # TODO: We should have -source of this in the /nix/store somewhere, with the `flake.nix` file. So we _should_ be able to do `nix develop /nix/store/...-source#$devshell`?
            curl "https://ci.zw3rk.com/job/input-output-hk-devx/pullrequest-25/$DEVSHELL-closure.$SYSTEM/latest/download/2" | sh
            exit 0
          fi
        '') devShells))) supportedSystems)}
    '';
  };

in pkgs.runCommand "bootstrap-devx" { } ''
  mkdir -p $out/nix-support
  echo "file binary-dist \"$out/bootstrap-devx.sh\"" > $out/nix-support/hydra-build-products
  cp ${bootstrapScript} $out/bootstrap-devx.sh
''
