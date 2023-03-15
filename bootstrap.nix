# This is an experiment around the idea of statically evaluating and cache a
# closure to reduce overall bootstrap time latency and artifacts download size
# of a given developer shell.
#
# The whole thing could be seen as a binary/build cache, but rather at
# closure-level than at derivation-level.

{ devShells, pkgs, supportedSystems, ... }:
with builtins;
let
  closure = drv:
    pkgs.runCommand "test" {
      requiredSystemFeatures = [ "recursive-nix" ];
      nativeBuildInputs = [ pkgs.nix ];
    } ''
      mkdir -p $out/nix-support
      HOME=$(mktemp -d)
      # TODO: replace zstd by zip?
      nix-store --export "${drv}" | zstd -z8T8 > $out/closure.zstd"
      echo "file binary-dist \"$out/closure.zstd\"" > $out/nix-support/hydra-build-products
    '';
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
      # TODO: @angerman is it okay to just say that devShell is first CLI arg?!
      DEVSHELL="$1"

      # 2. Generate per system / devShell shell snippet...
      ${toString (map (system: toString (attrValues (mapAttrs (name: value: ''
          if [[ "$SYSTEM" == "${system}" && "$DEVSHELL" == "${name}" ]]; then
            # Check if ${closure value} exists...
            if [[ ! -e ${value} ]]; then
              echo "Warning: this script should be run (the first time) as a trusted Nix user:"
              echo "https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-trusted-users"
              echo "n.b. root is by default the only trusted user on a fresh nix setup!"
              # TODO: I should also ensure that zstd is available on user machine ... replace zstd by zip?
              curl "TODO: the right /latest/ url hydra with closure build product" | zstd -d | nix-store --import
            fi
            # TODO: This should rather be the fallback ... and this be just the loading of `nix print-dev-env` output
            nix develop "github:input-output-hk/devx#$devshell" --no-write-lock-file --refresh
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
