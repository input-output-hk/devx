#!/bin/bash

TOKEN=$(curl --silent https://ghcr.io/token\?scope\=repository:$1:pull | jq -r .token)

# Read the manifest file from the docker image containing our nix-store closure and extract the layer url.
BLOB=$(curl \
--silent \
--request 'GET' \
--header "Authorization: Bearer $TOKEN" \
--header "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
--header "Accept: application/vnd.docker.distribution.manifest.v2+json" \
--header "Accept: application/vnd.oci.image.manifest.v1+json" \
"https://ghcr.io/v2/$1/manifests/$2" | tee manifest.json | jq -r '.layers[0].digest')

# Download the docker image layer that contains our nix store closure, and import it.
curl \
--location \
--request GET \
--header "Authorization: Bearer ${TOKEN}" \
"https://ghcr.io/v2/$1/blobs/${BLOB}"
