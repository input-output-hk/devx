#!/usr/bin/env bash
set -euo pipefail

# End-user DevX could also be potentially improved through this script: e.g,
# by helping new users to set up Nix using Determinate Systems new installer,
# or detect that it's used in a GitHub Actions context and advise installing Nix with Cachix's
# install Nix action.

verbosity=1

while getopts "v" opt; do
  case $opt in
    v) verbosity=$((verbosity + 1));;
    *) echo "Invalid option: -$OPTARG" >&2; exit 1;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
  local level="$1"
  local msg="$2"
  local color="$NC"

  case "$level" in
    DEBUG) color="$BLUE"  ;;
    INFO)  color="$GREEN" ;;
    WARN)  color="$YELLOW";;
    ERROR) color="$RED"   ;;
    *) echo "Unknown log level: $level" >&2; return 1;;
  esac

  if [ $verbosity -ge 2 ] || [ "$level" != "DEBUG" ]; then
    echo -e "${color}${level}: ${NC}${msg}"
  fi
}

log "INFO" "This script will set up nix and direnv, with opinionated default for Haskell development."


log "INFO" "[1/7] Install nix if it's not already installed ..."

if ! which nix >/dev/null 2>&1; then
    if [ "$GITHUB_ACTIONS" == "true" ]; then
        log "ERROR" "This script requires nix to be installed; you don't appear to have nix available. Since it seems that you're running this inside a GitHub Action, you can set up Nix using https://github.com/cachix/install-nix-action, e.g.:

      - name: Install Nix with good defaults
        uses: cachix/install-nix-action@v20
        with:
          extra_nix_config: |
            trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ= loony-tools:pr9m4BkM/5/eSTZlkQyRt57Jz7OMBxNSUiMC4FkcNfk=
            substituters = https://cache.iog.io/ https://cache.zw3rk.com/ https://cache.nixos.org/
          nix_path: nixpkgs=channel:nixos-unstable"
        exit 1
    else
        log "DEBUG" "nix is not installed. Would you like to install it now? (y/n)"
        read -r confirm
        if [[ "$confirm" == [yY] || "$confirm" == [yY][eE][sS] ]]; then
            log "DEBUG" "Installing nix..."
            curl -L https://nixos.org/nix/install | sh
            . "$HOME/.nix-profile/etc/profile.d/nix.sh"
            log "DEBUG" "nix installed successfully."
        else
            log "ERROR" "nix is required for the setup process. Please install nix and re-run the script."
            exit 1
        fi
    fi
else
    log "DEBUG" "nix is already installed."
fi


log "INFO" "[2/7] Tweak nix.conf with good defaults (may need sudo) ..."

if [ -z "${XDG_CONFIG_HOME:-}" ]; then
    XDG_CONFIG_HOME="$HOME/.config"
fi

nix_conf_file="$XDG_CONFIG_HOME/nix/nix.conf"
if grep -q "experimental-features" "$nix_conf_file"; then
    log "WARN" "The 'experimental-features' option already exists in '$nix_conf_file'. Please check that it's set to 'experimental-features = nix-command flakes'."
    echo "Press ENTER to open $nix_conf_file in $EDITOR:"
    read -r confirm
    $EDITOR "$nix_conf_file"
else
    echo "experimental-features = nix-command flakes" >> "$nix_conf_file"
    log "DEBUG" "'experimental-features = nix-command flakes' added to nix configuration."
fi

nix_conf_file="/etc/nix/nix.conf"

check_and_append_config() {
    local key="$1"
    local value="$2"
    if grep -q "^$key" "$nix_conf_file"; then
        echo "WARN: The '$key' option already exists in '$nix_conf_file'."
        echo "You expected to add '$key = $value'."
        echo "Press ENTER to open $nix_conf_file in $EDITOR for manual inspection:"
        read -r confirm
        sudo $EDITOR "$nix_conf_file"
    else
        echo "$key = $value" | sudo tee -a "$nix_conf_file" > /dev/null
        log "DEBUG" "'$key = $value' added to system-wide nix configuration."
    fi
}

check_and_append_config "allow-import-from-derivation" "true"
check_and_append_config "extra-substituters" "https://cache.iog.io https://cache.zw3rk.com"
check_and_append_config "extra-trusted-public-keys" "\"hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=\" \"loony-tools:pr9m4BkM/5/eSTZlkQyRt57Jz7OMBxNSUiMC4FkcNfk=\""

log "INFO" "[3/7] Restart nix-daemon (need sudo) ..."

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if which systemctl >/dev/null 2>&1 && systemctl is-active --quiet systemd; then
        log "DEBUG" "Restarting nix-daemon..."
        sudo systemctl restart nix-daemon.service
    else
        log "WARN" "Please restart nix-daemon manually."
        echo "Press ENTER to continue ..."
        read -r confirm
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    if which launchctl >/dev/null 2>&1; then
        log "DEBUG" "Restarting nix-daemon..."
        sudo launchctl kickstart -k system/org.nixos.nix-daemon
    else
        log "WARN" "Please restart nix-daemon manually."
        echo "Press ENTER to continue ..."
        read -r confirm
    fi
fi


log "INFO" "[4/7] Install direnv if it's not already installed ..."

if ! which direnv >/dev/null 2>&1; then
    log "DEBUG" "direnv is not installed. Would you like to install it now? (y/n)"
    read -r confirm
    if [[ "$confirm" == [yY] || "$confirm" == [yY][eE][sS] ]]; then
        log "DEBUG" "Installing direnv..."
        nix profile install nixpkgs#direnv
        log "DEBUG" "direnv installed successfully."
    else
        log "ERROR" "direnv is required for the setup process. Please install direnv and re-run the script."
        exit 1
    fi
else
    log "DEBUG" "direnv is already installed."
fi


log "INFO" "[5/7] Hook direnv into the user shell ..."

# shellcheck disable=SC2016
if grep -q 'direnv hook' "$HOME/.bashrc"; then
    log "DEBUG" "direnv seems already hooked into '$HOME/.bashrc'."
else
    echo 'eval "$(direnv hook bash)"' >> "$HOME/.bashrc"
    log "DEBUG" "direnv hook added to '$HOME/.bashrc'."
fi
# shellcheck disable=SC2016
if ! which zsh >/dev/null 2>&1 || grep -q 'direnv hook' "$HOME/.zshrc"; then
    log "DEBUG" "zsh isn't in PATH or direnv seems already hooked into '$HOME/.zshrc'."
else
    echo 'eval "$(direnv hook zsh)"' >> "$HOME/.zshrc"
    log "DEBUG" "direnv hook added to '$HOME/.zshrc'."
fi
# shellcheck disable=SC2016
if ! which fish >/dev/null 2>&1 || grep -q 'direnv hook' "$XDG_CONFIG_HOME/fish/config.fish"; then
    log "DEBUG" "fish isn't in PATH or direnv seems already hooked into '$XDG_CONFIG_HOME/fish/config.fish'."
else
    echo 'eval "$(direnv hook fish)"' >> "$XDG_CONFIG_HOME/fish/config.fish"
    log "DEBUG" "direnv hook added to '$XDG_CONFIG_HOME/fish/config.fish'."
fi


log "INFO" "[6/7] Configure .envrc in the project directory ..."

if [ -f ".envrc" ]; then
    log "DEBUG" ".envrc file already exists."
else
    echo 'if ! has nix_direnv_version || ! nix_direnv_version 2.3.0; then
        source_url "https://raw.githubusercontent.com/nix-community/nix-direnv/2.3.0/direnvrc" "sha256-Dmd+j63L84wuzgyjITIfSxSD57Tx7v51DMxVZOsiUD8="
    fi' >> ".envrc"
    if [ -f "flake.nix" ]; then
        echo "use flake" >> ".envrc"
    elif [ -f "shell.nix" ]; then
        echo "use nix" >> ".envrc"
    else
        # FIXME: maybe we could ask interactively what compiler version and shell flavor the user want to use?
        echo "use flake \"github:input-output-hk/devx#ghc8107-iog\"" >> ".envrc"
    fi
    log "DEBUG" "Successfully created and populated .envrc file."
fi


log "INFO" "[7/7] Allow direnv to load the .envrc ..."

direnv allow
log "DEBUG" ".envrc configuration allowed."

log "INFO" "Setup process is complete! 🎉"

# FIXME: maybe directly install VSCode extension with `code --install-extension pinage404.nix-extension-pack; code --install-extension haskell.haskell` if `code` is in PATH?!
log "INFO" "For proper editor integration, you need to install the direnv extension for your specific editor. E.g., if you use VSCode, search for \"direnv\" in the extensions marketplace and install the plugin. Reload your editor and you're all set!"
