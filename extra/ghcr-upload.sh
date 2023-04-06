#! /usr/bin/env nix-shell
#! nix-shell -i bash -p zstd -p oras
set -euo pipefail

nix build ".#hydraJobs.${DEV_SHELL}"
nix-store --export $(nix-store -qR result) | zstd -z8T8 >${DEV_SHELL}
oras push ghcr.io/input-output-hk/devx:${DEV_SHELL} ${DEV_SHELL}
