#! /usr/bin/env nix-shell
#! nix-shell -i bash -p zstd -p oras
set -euox pipefail

if ! { [ "${GITHUB_REF:-}" == "refs/heads/hkm/cardano-node-ghcr-test" ] || [[ "${GITHUB_REF:-}" = refs/heads/release* ]]; }; then
  exit 0;
else
  oras push --artifact-type application/vnd.docker.image.v1+tar.gz ghcr.io/input-output-hk/devx:${IMAGE_FILE} ${IMAGE_FILE}
fi
