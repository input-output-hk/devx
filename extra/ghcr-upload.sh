#! /usr/bin/env nix-shell
#! nix-shell -i bash -p zstd
set -euo pipefail

FLAKE=".#closures.${DEV_SHELL}-closure --no-write-lock-file --refresh --accept-flake-config"
nix build ${FLAKE}
skopeo copy "dir:$(./extra/mk-docker-manifest.sh result/closure.zstd)" "docker://ghcr.io/input-output-hk/devx:${DEV_SHELL}"
