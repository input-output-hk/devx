#! /usr/bin/env nix-shell
#! nix-shell -i bash -p zstd
set -euo pipefail

nix build ".#hydraJobs.${DEV_SHELL}"
nix-store --export $(nix-store -qR result) | zstd -z8T8 > closure.zstd
skopeo copy "dir:$(./extra/mk-docker-manifest.sh closure.zstd)" "docker://ghcr.io/input-output-hk/devx:${DEV_SHELL}"
