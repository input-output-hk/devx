#! /usr/bin/env nix-shell
#! nix-shell -i bash -p zstd
set -euo pipefail

# FIXME: this file should not be longer needed if we succeed to rely only on
# hydra latest build product!
# https://input-output-hk.github.io/adrestia/cardano-wallet/contributing/Hydra

SYSTEMS=("x86_64-linux")

# Generated with: % nix key generate-secret --key-name s3.zw3rk.com
# echo "${NIX_STORE_SECRET_KEY}" > ./secret-key

for system in "${SYSTEMS[@]}"; do
    DEV_SHELL="${system}.${FLAKE_DEV_SHELL}"
    FLAKE=".#closures.x86_64-linux.${DEV_SHELL}-closure --no-write-lock-file --refresh --system ${system} --accept-flake-config"
    # shellcheck disable=SC2086
    nix build ${FLAKE}
#    nix store sign --key-file ./secret-key --recursive ./result
    # shellcheck disable=SC2046
    # nix path-info --derivation .#devShells.x86_64-linux.ghc8107-static-minimal
    # nix print-dev-env .#devShells.x86_64-linux.ghc8107-static-minimal
    #nix --offline --extra-experimental-features "nix-command flakes" \
    #            print-dev-env (./result >> $out

    #nix-store --export $(nix-store -qR ./result) | zstd -z8T8 > "${DEV_SHELL}.zstd"
    # shellcheck disable=SC2086
    #nix print-dev-env ${FLAKE} > "${DEV_SHELL}.sh"

    # cleanup; so we don't run out of disk space, or retain too much in the nix store.
    rm result "${DEV_SHELL}.zstd" "${DEV_SHELL}.sh"
done
