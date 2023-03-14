#! /usr/bin/env nix-shell
#! nix-shell -i bash -p awscli zstd
set -euo pipefail

if [ "$GA_HOST_OS" == "ubuntu-latest" ]; then
    SYSTEMS=("x86_64-linux") # TODO: aarch64-linux
fi
if [ "$GA_HOST_OS" == "macOS-latest" ]; then
    SYSTEMS=("x86_64-darwin") # TODO: aarch64-darwin
fi

# `awscli` doesn't seems to provide a stateless mode :')
aws configure set aws_access_key_id "${AWS_ACCESS_KEY_ID}"
aws configure set aws_secret_access_key "${AWS_SECRET_ACCESS_KEY}"

# Generated with: % nix key generate-secret --key-name s3.zw3rk.com
echo "${NIX_STORE_SECRET_KEY}" > ./secret-key

for system in "${SYSTEMS[@]}"; do
    DEV_SHELL="${system}.${FLAKE_DEV_SHELL}"
    FLAKE=".#devShells.${DEV_SHELL} --no-write-lock-file --refresh --system ${system} --accept-flake-config"
    # shellcheck disable=SC2086
    nix build ${FLAKE}
    nix store sign --key-file ./secret-key --recursive ./result
    # shellcheck disable=SC2046
    nix-store --export $(nix-store -qR ./result) | zstd -z8T8 > "${DEV_SHELL}.zstd"
    # shellcheck disable=SC2086
    nix print-dev-env ${FLAKE} > "${DEV_SHELL}.sh"
    aws --endpoint-url https://s3.zw3rk.com s3 cp "./${DEV_SHELL}.zstd" s3://devx/
    aws --endpoint-url https://s3.zw3rk.com s3 cp "./${DEV_SHELL}.sh" s3://devx/
    rm result
done
