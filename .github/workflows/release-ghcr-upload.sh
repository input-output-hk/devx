#! /usr/bin/env bash
set -euox pipefail

docker load < dockerImage
docker image tag inputoutput/cardano-node:$GITHUB_SHA ghcr.io/input-output-hk/cardano-node:$GITHUB_REF_NAME
docker push ghcr.io/input-output-hk/cardano-node:$GITHUB_REF_NAME
docker load < submitApiDockerImage
docker image tag inputoutput/cardano-submit-api:$GITHUB_SHA ghcr.io/input-output-hk/cardano-submit-api:$GITHUB_REF_NAME
docker push ghcr.io/input-output-hk/cardano-submit-api:$GITHUB_REF_NAME
