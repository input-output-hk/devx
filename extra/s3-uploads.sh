#! /usr/bin/env nix-shell
#! nix-shell -i bash -p awscli zstd

DEV_SHELLS=(
    "ghc8107"
    "ghc902"
    "ghc925"
    "ghc8107-minimal"
    "ghc902-minimal"
    "ghc925-minimal"
    "ghc8107-static-minimal"
    "ghc902-static-minimal"
    "ghc925-static-minimal"
)

SYSTEMS=("aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux")

# shellcheck disable=SC2034
AWS_DEFAULT_REGION=us-east-1
# shellcheck disable=SC2034
AWS_ACCESS_KEY_ID="$1"
# shellcheck disable=SC2034
AWS_SECRET_ACCESS_KEY="$2"

# Generated with: % nix key generate-secret --key-name s3.zw3rk.com
echo "$3" > ./secret-key

for system in "${SYSTEMS[@]}"; do
    for devShell in "${DEV_SHELLS[@]}"; do
        nix build ".#devShells.${system}.${devShell}"
        nix store sign --key-file ./secret-key --recursive ./result
        # shellcheck disable=SC2046
        nix-store --export $(nix-store -qR result) | zstd -z8T8 > "${system}.${devShell}.zstd"
        nix print-dev-env ".#devShells.${system}.${devShell}" > "${system}.${devShell}.sh"
        aws --endpoint-url https://s3.zw3rk.com s3 cp "./${system}.${devShell}.sh" s3://devx/
        aws --endpoint-url https://s3.zw3rk.com s3 cp "./${system}.${devShell}.zstd" s3://devx/
    done
done
