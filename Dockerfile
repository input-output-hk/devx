FROM ubuntu:rolling
WORKDIR /workspaces

ARG PLATFORM="x86_64-linux"
ARG TARGET_PLATFORM=""
ARG COMPILER_NIX_NAME="ghc96"
ARG MINIMAL="false"
ARG IOG="true"

RUN DEBIAN_FRONTEND=noninteractive \
 && apt-get update \
 && apt-get -y install curl gh git grep jq nix zstd \
 && curl -L https://raw.githubusercontent.com/input-output-hk/actions/latest/devx/support/fetch-docker.sh -o fetch-docker.sh \
 && chmod +x fetch-docker.sh \
 && SUFFIX='' \
 && if [ "$MINIMAL" = "true" ]; then SUFFIX="${SUFFIX}-minimal"; fi \
 && if [ "$IOG" = "true" ]; then SUFFIX="${SUFFIX}-iog"; fi \
 && ./fetch-docker.sh input-output-hk/devx $PLATFORM.$COMPILER_NIX_NAME$TARGET_PLATFORM${SUFFIX}-env | zstd -d | nix-store --import | tee store-paths.txt

# FIXME: Consider moving this script into a Nix `writeShellApplication` trivial builder within the closure...
RUN cat <<EOF >> $HOME/.bashrc
# n.b. GitHub Codespaces are populated with \$GH_TOKEN already set
if [ -z "\$GH_TOKEN" ]; then
    echo "A GitHub token is required for downloading HLS cache (optionnal)."
    read -p "Would you like to enter your GitHub token now? (y/n) " yn
    case \$yn in
        [Yy]* ) 
            read -sp "Enter your GitHub token: " GH_TOKEN; 
            export GH_TOKEN;;
        [Nn]* ) 
            return;;
        * ) 
            echo "Invalid response. Please answer yes (y) or no (n)."; 
            return;;
    esac
fi
CACHE_DIR="\$HOME/.cache"
if [ ! -d "\$CACHE_DIR" ]; then
    echo "Attempting to download HLS cache from GitHub Artifact for faster first launch ..."
    mkdir -p \$CACHE_DIR
    pushd \$CACHE_DIR > /dev/null
    PROJECT_DIR=\$(find /workspaces/ -mindepth 1 -maxdepth 1 -type d)
    if [ -n "\$PROJECT_DIR" ]; then
        CACHE_REV=\$(git -C "\$PROJECT_DIR" rev-parse HEAD)
        gh run download -n "cache-\$CACHE_REV-$COMPILER_NIX_NAME"
    fi
    popd > /dev/null
fi
source \$(grep -m 1 -e '-env.sh$' store-paths.txt)
EOF