#! /usr/bin/env nix-shell
#! nix-shell -i bash -p zstd -p oras

oras pull ghcr.io/input-output-hk/devx:$1
