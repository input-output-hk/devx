FROM ubuntu:rolling
WORKDIR /workspaces

ARG PLATFORM="x86_64-linux"
ARG TARGET_PLATFORM=""
ARG COMPILER_NIX_NAME="ghc961"
ARG MINIMAL="true"
ARG IOG="false"

RUN DEBIAN_FRONTEND=noninteractive \
 && apt-get update \
 && apt-get -y install curl git jq nix zstd \
 && curl -L https://raw.githubusercontent.com/input-output-hk/actions/latest/devx/support/fetch-docker.sh -o fetch-docker.sh \
 && chmod +x fetch-docker.sh \
 && SUFFIX='' \
 && if [ "$MINIMAL" = "true" ]; then SUFFIX="${SUFFIX}-minimal"; fi \
 && if [ "$IOG" = "true" ]; then SUFFIX="${SUFFIX}-iog"; fi \
 && ./fetch-docker.sh input-output-hk/devx $PLATFORM.$COMPILER_NIX_NAME$TARGET_PLATFORM${SUFFIX}-env | zstd -d | nix-store --import | tee store-paths.txt \
 && apt-get -y remove curl git jq nix zstd \
 && apt-get -y autoremove \
 && apt-get -y autoclean

# `tail -n 2 X | head -n 1` seems a bit fragile way to get `ghc8107-iog-env.sh` derivation path ...
RUN echo "source $(tail -n 2 store-paths.txt | head -n 1)" >> $HOME/.bashrc
