#! /usr/bin/env bash
set -euox pipefail

if ! { [ "${GITHUB_REF:-}" == "refs/heads/hkm/cardano-node-ghcr-test" ] || [[ "${GITHUB_REF:-}" = refs/heads/release* ]]; }; then
  exit 0;
else
  docker load < dockerImage
  docker image tag inputoutput/cardano-node:$GITHUB_SHA ghcr.io/input-output-hk/cardano-node:$GITHUB_REF_NAME
  docker push ghcr.io/input-output-hk/cardano-node:$GITHUB_REF_NAME
  docker load < submitApiDockerImage
  docker image tag inputoutput/cardano-submit-api:$GITHUB_SHA ghcr.io/input-output-hk/cardano-submit-api:$GITHUB_REF_NAME
  docker push ghcr.io/input-output-hk/cardano-submit-api:$GITHUB_REF_NAME
fi
