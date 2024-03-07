FROM ubuntu:rolling
WORKDIR /workspaces

ARG PLATFORM="x86_64-linux"
ARG TARGET_PLATFORM=""
ARG COMPILER_NIX_NAME="ghc96"
ARG MINIMAL="false"
ARG IOG="true"

RUN DEBIAN_FRONTEND=noninteractive \
 && apt-get update \
 && apt-get -y install curl gh git grep jq nix rsync zstd \
 && curl -L https://raw.githubusercontent.com/input-output-hk/actions/latest/devx/support/fetch-docker.sh -o fetch-docker.sh \
 && chmod +x fetch-docker.sh \
 && SUFFIX='' \
 && if [ "$MINIMAL" = "true" ]; then SUFFIX="${SUFFIX}-minimal"; fi \
 && if [ "$IOG" = "true" ]; then SUFFIX="${SUFFIX}-iog"; fi \
 && if [ "$IOG_FULL" = "true" ]; then SUFFIX="${SUFFIX}-iog-full"; fi \
 && ./fetch-docker.sh input-output-hk/devx $PLATFORM.$COMPILER_NIX_NAME$TARGET_PLATFORM${SUFFIX}-env | zstd -d | nix-store --import | tee store-paths.txt

RUN cat <<EOF >> $HOME/.bashrc
source $(grep -m 1 -e '-env.sh$' store-paths.txt)
EOF

# This enforce those settings in DevContainer whatever "Settings Sync" user preferences ...
RUN mkdir -p $HOME/.vscode-server/data/Machine/ \
 && cat <<EOF >> $HOME/.vscode-server/data/Machine/settings.json
{ "haskell.manageHLS": "PATH" }
EOF

# FIXME: Consider moving this script into a Nix `writeShellApplication` trivial builder within the closure ...
# ... but that means I should figure it out how to pass to it $COMPILER_NIX_NAME as input?
RUN mkdir -p /usr/local/bin/ \
 && cat <<EOF >> /usr/local/bin/post-create-command
#!/usr/bin/env bash

PROJECT_DIR=\$(find /workspaces/ -mindepth 1 -maxdepth 1 -type d)
if [ -n "\$PROJECT_DIR" ]; then
    pushd \$PROJECT_DIR > /dev/null
    # GitHub Codespaces should have \$GH_TOKEN already set.
    if [ -n "\$GH_TOKEN" ]; then
        COMMIT_HASH=\$(git rev-parse HEAD)
        echo "Attempting to download HLS cache from GitHub Artifact (cache-\$COMMIT_HASH-$COMPILER_NIX_NAME) for faster first launch ..."
        gh run download -D .download -n "cache-\$COMMIT_HASH-$COMPILER_NIX_NAME"
        rsync -a .download/work/cardano-base/cardano-base/dist-newstyle .
        rm -r .download
    else
        echo "\\\$GH_TOKEN is not set. Skipping HLS cache download."
    fi
    # HLS error (Couldn't load cradle for ghc libdir) if `cabal update` has never been run in project using cardano-haskell-packages ...
    echo "Running `cabal update` ..."
    bash -c "cabal update"
    popd > /dev/null
fi
EOF
RUN chmod +x /usr/local/bin/post-create-command
