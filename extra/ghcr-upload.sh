#! /usr/bin/env nix-shell
#! nix-shell -i bash -p zstd -p oras -p jq
set -euox pipefail

: "${DEV_SHELL:?'DEV_SHELL is not set'}"
: "${SHELL_NIX_PATH:?'SHELL_NIX_PATH is not set'}"

# retry three times in case of intermittent network errors.
nix-store -r "$SHELL_NIX_PATH" || nix-store -r "$SHELL_NIX_PATH" || nix-store -r "$SHELL_NIX_PATH"
#nix build ".#hydraJobs.${DEV_SHELL}" --show-trace --accept-flake-config
nix-store --export $(nix-store -qR "$SHELL_NIX_PATH") | tee store-paths.txt | zstd -z8T8 >${DEV_SHELL}
if [[ ! $(tail -n 1 store-paths.txt) =~ "devx" ]]; then exit 1; fi
oras push ghcr.io/input-output-hk/devx:${DEV_SHELL} ${DEV_SHELL}
