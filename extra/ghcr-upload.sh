#! /usr/bin/env nix-shell
#! nix-shell -i bash -p zstd -p oras
set -euox pipefail

nix build ".#hydraJobs.${DEV_SHELL}" --show-trace
nix-store --export $(nix-store -qR result) | zstd -z8T8 >${DEV_SHELL} | tee store-paths.txt
if [[ ! $(tail -n 1 store-paths.txt) =~ "devx" ]]; then exit 1; fi
oras push ghcr.io/input-output-hk/devx:${DEV_SHELL} ${DEV_SHELL}
