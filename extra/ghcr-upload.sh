#! /usr/bin/env nix-shell
#! nix-shell -i bash -p zstd -p oras -p jq
set -euox pipefail

: "${DEV_SHELL:?'DEV_SHELL is not set'}"
: "${SHELL_NIX_PATH:?'SHELL_NIX_PATH is not set'}"

# retry three times in case of intermittent network errors.
nix-store -r "$SHELL_NIX_PATH" || nix-store -r "$SHELL_NIX_PATH" || nix-store -r "$SHELL_NIX_PATH"
# Collect closure paths and export them as a zstd-compressed NAR archive.
# Save the path list separately for verification — nix-store --export
# produces binary output (contains null bytes) which can't be inspected
# with text tools like tail/grep.
CLOSURE_PATHS=$(nix-store -qR "$SHELL_NIX_PATH")
nix-store --export $CLOSURE_PATHS | zstd -z8T8 >${DEV_SHELL}
# Verify the environment script is included in the closure.
# The wrapper script is always named "devx" for compatibility with
# input-output-hk/actions/devx/action.yml which matches on that name.
if ! echo "$CLOSURE_PATHS" | grep -q "devx$"; then exit 1; fi
oras push ghcr.io/input-output-hk/devx:${DEV_SHELL} ${DEV_SHELL}
