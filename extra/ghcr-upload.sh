#! /usr/bin/env nix-shell
#! nix-shell -i bash -p zstd -p oras
set -euox pipefail

nix build ".#hydraJobs.${DEV_SHELL}" --show-trace
echo <<EOF >${DEV_SHELL}
#!/bin/bash
BODY=\$(grep -n '# NIX_STORE' "\$0" | cut -d ':' -f 1)
tail -n +\$((MARKER_LINE + 1)) "\$0" | nix-store --import
exit 0
cp $(readlink result) \$1
# NIX_STORE
EOF

nix-store --export $(nix-store -qR result) >> ${DEV_SHELL}
zstd -z8T8 ${DEV_SHELL} ${DEV_SHELL}.zst
oras push ghcr.io/input-output-hk/devx:${DEV_SHELL} ${DEV_SHELL}.zst
