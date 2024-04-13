# We build the Docker image from a Dockerfile rather than from a Nix expression
# This is because VSCode DevContainer / GitHub Codespace run an install script
# at first launch that mostly consider your machine to be Debian-based.
FROM ubuntu:rolling
# TODO: But there is likely a better immutable way to build this image ...
# https://github.com/input-output-hk/devx-aux/issues/115
WORKDIR /workspaces

ARG PLATFORM="x86_64-linux"
ARG TARGET_PLATFORM=""
ARG COMPILER_NIX_NAME="ghc96"
ARG VARIANT=""
ARG IOG="-iog"

RUN DEBIAN_FRONTEND=noninteractive \
 && apt-get update \
 && apt-get -y install curl gh git grep jq nix rsync zstd \
 && curl -L https://raw.githubusercontent.com/input-output-hk/actions/latest/devx/support/fetch-docker.sh -o fetch-docker.sh \
 && chmod +x fetch-docker.sh \
 && ./fetch-docker.sh input-output-hk/devx $PLATFORM.$COMPILER_NIX_NAME$TARGET_PLATFORM$VARIANT$IOG-env | zstd -d | nix-store --import | tee store-paths.txt

RUN cat <<EOF >> $HOME/.bashrc
source $(grep -m 1 -e '-env.sh$' store-paths.txt)
EOF

# This enforce those settings in DevContainer whatever "Settings Sync" user preferences ...
# ... VSCode DevContainer and GitHub Codespace does not look for the same settings file ><'
RUN mkdir -p $HOME/.vscode-server/data/Machine/ \
 && mkdir -p $HOME/.vscode-remote/data/Machine/ \
 && bash -ic 'echo -e "{\n \
    \"haskell.manageHLS\": \"PATH\",\n \
    \"haskell.serverEnvironment\": { \"PATH\": \"$PATH\" },\n \
    \"haskell.serverExecutablePath\": \"$(which haskell-language-server)\"\n \
}" > $HOME/.vscode-server/data/Machine/settings.json' \
 && cp $HOME/.vscode-server/data/Machine/settings.json $HOME/.vscode-remote/data/Machine/settings.json

# FIXME: Consider moving this script into a Nix `writeShellApplication` trivial builder within the closure ...
# ... but that means I should figure it out how to pass to it $COMPILER_NIX_NAME as input?
RUN mkdir -p /usr/local/bin/ \
 && cat <<EOF >> /usr/local/bin/on-create-command
#!/usr/bin/env bash

PROJECT_DIR=\$(find /workspaces/ -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print -quit)
if [ -n "\$PROJECT_DIR" ]; then
    pushd \$PROJECT_DIR > /dev/null
    # HLS error (Couldn't load cradle for ghc libdir) if `cabal update` has never been run in project using cardano-haskell-packages ...
    echo "Running `cabal update` ..."
    bash -ic "cabal update"
    # GitHub Codespaces should have \$GITHUB_TOKEN already set.
    if [ -n "\$GITHUB_TOKEN" ]; then
        COMMIT_HASH=\$(git rev-parse HEAD)
        echo "Attempting to download HLS cache from GitHub Artifact (cache-\$COMMIT_HASH-$COMPILER_NIX_NAME) for faster first launch ..."
        gh run download -D .download -n "cache-\$COMMIT_HASH-$COMPILER_NIX_NAME"
        rsync -a .download/work/cardano-base/cardano-base/dist-newstyle .
        rm -r .download
    else
        echo "\\\$GITHUB_TOKEN is not set. Skipping HLS cache download."
    fi
    popd > /dev/null
fi
EOF
RUN chmod +x /usr/local/bin/on-create-command
