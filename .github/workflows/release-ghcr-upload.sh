#! /usr/bin/env bash
set -euox pipefail

docker load < dockerImage
docker image tag inputoutput/cardano-node:a7803c24de6a97d72cd025f71631ea65d078c19e ghcr.io/input-output-hk/cardano-node:$GITHUB_REF_NAME
docker push ghcr.io/input-output-hk/cardano-node:$GITHUB_REF_NAME
docker load < submitApiDockerImage
docker image tag inputoutput/cardano-submit-api:a7803c24de6a97d72cd025f71631ea65d078c19e ghcr.io/input-output-hk/cardano-submit-api:$GITHUB_REF_NAME
docker push ghcr.io/input-output-hk/cardano-submit-api:$GITHUB_REF_NAME
