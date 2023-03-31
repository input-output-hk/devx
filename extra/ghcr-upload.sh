#! /usr/bin/env nix-shell
#! nix-shell -i bash -p zstd
set -euox pipefail

# FIXME: this file should not be longer needed if we succeed to rely only on
# hydra latest build product!
# https://input-output-hk.github.io/adrestia/cardano-wallet/contributing/Hydra

SYSTEMS=("x86_64-linux")

# Generated with: % nix key generate-secret --key-name s3.zw3rk.com
# echo "${NIX_STORE_SECRET_KEY}" > ./secret-key

for system in "${SYSTEMS[@]}"; do
    DEV_SHELL="${system}.${FLAKE_DEV_SHELL}"
    FLAKE=".#closures.${DEV_SHELL}-closure --no-write-lock-file --refresh --system ${system} --accept-flake-config"
    # shellcheck disable=SC2086
    nix build ${FLAKE}
    skopeo copy "dir:$(./extra/mk-docker-manifest.sh result/closure.zstd)" "docker://ghcr.io/input-output-hk/devx:latest"

    # cleanup; so we don't run out of disk space, or retain too much in the nix store.
    rm result
done
