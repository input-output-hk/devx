ARG platform=x86_64-linux
ARG target_platform=""
ARG compiler_nix_name=ghc961
ARG minimal=true
ARG iog=false

FROM ubuntu:rolling
WORKDIR /workspaces

RUN apt-get update \
 && yes | apt-get install curl git jq nix zstd \
 && curl -L https://raw.githubusercontent.com/input-output-hk/actions/latest/devx/support/fetch-docker.sh -o fetch-docker.sh \
 && chmod +x fetch-docker.sh \
 && SUFFIX='' \
 && if [ "$minimal" = true ]; then SUFFIX="${SUFFIX}-minimal"; fi \
 && if [ "$iog" = true ]; then SUFFIX="${SUFFIX}-iog"; fi \
 && ./fetch-docker.sh input-output-hk/devx $platform.$compiler_nix_name$target_platform$SUFFIX-env | zstd -d | nix-store --import | tee store-paths.txt \
 && yes | apt-get remove curl jq nix zstd \
 && yes | apt-get autoremove \
 && yes | apt-get autoclean

# `tail -n 2 X | head -n 1` seems a bit fragile way to get `ghc8107-iog-env.sh` derivation path ...
RUN echo "source $(tail -n 2 store-paths.txt | head -n 1)" >> $HOME/.bashrc
