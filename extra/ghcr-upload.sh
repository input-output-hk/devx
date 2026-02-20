#! /usr/bin/env nix-shell
#! nix-shell -i bash -p zstd -p oras -p jq
set -euox pipefail

: "${DEV_SHELL:?'DEV_SHELL is not set'}"
: "${SHELL_NIX_PATH:?'SHELL_NIX_PATH is not set'}"

# retry three times in case of intermittent network errors.
nix-store -r "$SHELL_NIX_PATH" || nix-store -r "$SHELL_NIX_PATH" || nix-store -r "$SHELL_NIX_PATH"
#nix build ".#hydraJobs.${DEV_SHELL}" --show-trace --accept-flake-config
nix-store --export $(nix-store -qR "$SHELL_NIX_PATH") | tee store-paths.txt | zstd -z8T8 >${DEV_SHELL}
# Verify the environment script is included in the closure
# The script filename ends with -env.sh (e.g., ghc96-env.sh, ghc98-static-iog-env.sh)
if [[ ! $(tail -n 1 store-paths.txt) =~ "-env.sh" ]]; then exit 1; fi
oras push ghcr.io/input-output-hk/devx:${DEV_SHELL} ${DEV_SHELL}
