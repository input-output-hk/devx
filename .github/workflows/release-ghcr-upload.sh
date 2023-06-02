#! /usr/bin/env nix-shell
#! nix-shell -i bash -p zstd -p oras
set -euox pipefail

if ! { [ "${GITHUB_REF:-}" == "refs/heads/master" ] || [[ "${GITHUB_REF:-}" = refs/heads/release* ]]; }; then
  exit 0;
else
  oras push ghcr.io/input-output-hk/cardano-node:${IMAGE_NAME} ${IMAGE_NAME}
fi
