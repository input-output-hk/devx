# Setting up your Haskell environment with `direnv`, the `devx` developer environment, and various code editors

This tutorial guides you through setting up your Haskell development environment using `direnv`, the `devx` developer environment, and different editors (VSCode, Emacs, and Vim).

## Why do I want this?

Haskell's development often requires managing multiple versions of GHC and different sets of dependencies. Traditionally, this can be quite challenging and error-prone, especially when you need to switch back and forth between projects with different configurations.

By utilizing `direnv`, the `devx` developer environment, and editor integrations, you gain a flexible and robust development environment. `direnv` automatically adjusts your shell environment depending on your current directory. The `devx` developer environment provides a consistent Haskell development environment across different projects, and the editor integrations make sure you can use this setup within your preferred IDE.

## What is `direnv`, and why use it?

`direnv` is an environment switcher for the shell. It knows how to hook into Bash, Zsh, and Fish shell to load or unload environment variables depending on the current directory. This allows project-specific environment settings to be loaded automatically as you move between different project directories.

## Prerequisites

Ensure you have the following installed on your machine:

- [`nix`](https://nixos.org/)
- [`direnv`](https://direnv.net/)
- Your choice of editor (VSCode, Emacs, or Vim)

To install `nix`, follow the steps provided on the [Nix installer page](https://nixos.org/download.html). To utilize our cache, it's essential that you're recognized as a trusted user. You can check your `nix` configuration to see if you're listed in `trusted-users` by running `nix show-config | grep 'trusted-users'`.

If you're not listed, you need to add the line `trusted-users = $USER` in your configuration file. Additionally, two more lines should be added: `experimental-features = nix-command flakes` and `accept-flake-config = true` for the convenince of having flake features enabled globaly.

You should add the `trusted-users` line in `/etc/nix/nix.conf`, others options could be added there or in `$XDG_CONFIG_HOME/nix/nix.conf` if you only want to change the configuration of your current user. After making these edits, remember to restart the `nix-daemon`. If you use a Linux distribution based on `systemd`, you can do so by running `sudo systemctl restart nix-daemon`, if you're running macOS, it's `launchctl kickstart -k system/org.nixos.nix-daemon`.

## Install and configure `direnv`

Detailed instructions for installing `direnv` can be found on the [official `direnv` documentation](https://direnv.net/docs/installation.html). Depending on your operating system and preference, there may be package manager options, or you can install from source.

Once `direnv` is installed, you need to hook it into your shell. The process for this varies depending on what shell you use, but in general, you need to add a line to your shell initialization file (`.bashrc`, `.zshrc`, `config.fish`, etc.):

```bash
# Bash
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc

# Zsh
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc

# Fish
echo 'direnv hook fish | source' >> ~/.config/fish/config.fish
```

Remember to restart your shell or open a new terminal window to apply these changes.

Next, you'll need to enable `direnv` for your project directories. When you navigate into a directory with a `.envrc` file, `direnv` will block the environment until you approve the changes by running `direnv allow`.

### Pitfalls

`direnv` can be a bit tricky to get working. Some common issues include:

- Forgetting to add the `direnv` hook to your shell's configuration file.
- Navigating to a directory before you've approved its `.envrc` file.
- Forgetting to restart your shell or open a new terminal after setting up `direnv`.

Be sure to follow the installation and setup instructions carefully, and consult the [`direnv` documentation](https://direnv.net/docs/troubleshooting.html) if you encounter problems.

## Example Haskell project

Let's start by creating a simple `hello` Haskell application. First, navigate to your preferred working directory, then:

```bash
$ cabal unpack hello
$ cd hello
```

This will generate a basic `Main.hs` file with a _"Hello, World!"_ program.

## Configure `direnv` for your project

Create a `.envrc` file in the root directory of your Haskell project, and add the following content:

```bash
# https://github.com/nix-community/nix-direnv A fast, persistent use_nix/use_flake implementation for direnv:
if ! has nix_direnv_version || ! nix_direnv_version 2.3.0; then
  source_url "https://raw.githubusercontent.com/nix-community/nix-direnv/2.3.0/direnvrc" "sha256-Dmd+j63L84wuzgyjITIfSxSD57Tx7v51DMxVZOsiUD8="
fi
# https://github.com/input-output-hk/devx Slightly opinionated shared GitHub Action for Cardano-Haskell projects 
use flake "github:input-output-hk/devx#ghc8107-iog"
```

This will tell `direnv` to instantiate a shell with the same environment as `nix develop github:input-output-hk/devx#ghc8107-iog`, when changing into the folder where the `.envrc` resides.

You can also pin the flake to a specific version. This is a good practice to ensure reproducibility across different machines and systems. Refer to the Nix Flakes documentation on how to do this. Then, allow Direnv to take effect:

```bash
$ direnv allow
```

`direnv` will use the specified flake to provide a shell with all the Haskell development tools you need, as configured in the Devx repository.

## Setting up your editor

This setup should work with any editor that has support for language severs and the ability to use direnv to instantiate the necessary environment (`PATH`, ...). We will focus on the three most popular ones right now: VSCode, Emacs and Vim.

### Visual Studio Code (VSCode)

First, ensure that you have the following extensions installed:

- [Nix Extension Pack](https://marketplace.visualstudio.com/items?itemName=pinage404.nix-extension-pack)
- [Haskell](https://marketplace.visualstudio.com/items?itemName=haskell.haskell)

The Nix Extension Pack brings `direnv` support, while the Haskell extension provides support for the Haskell Language Server.

When using `direnv` with VSCode, ensure that VSCode has the correct environment loaded. Restart VSCode or reload the window once the shell has been instantiated. If you're on a platform where launching VSCode from the terminal is supported, you can also launch VSCode with `code .` from the terminal within the `direnv` environment.

### Emacs

For Emacs, ensure you have the following packages installed:

- [`lsp-mode`](https://github.com/emacs-lsp/lsp-mode)
- [`lsp-haskell`](https://github.com/emacs-lsp/lsp-haskell)

You can use the following config for `direnv` and `lsp-haskell`:

```emacs-lisp
;; direnv
(use-package direnv
  :config
  (direnv-mode))

;; Haskell Language Server
(use-package lsp-mode
  :commands lsp
  :config
  (require 'lsp-haskell)
  (add-hook 'haskell-mode-hook #'lsp))
```

Now, when you open a Haskell file in your project, `direnv` should automatically load your environment, and lsp-haskell should start providing IDE-like features.

### Vim

For Vim, we recommend the [`direnv.vim`](https://github.com/direnv/direnv.vim) and [`haskell-vim`](https://github.com/neovimhaskell/haskell-vim) plugins. You can install these plugins using a plugin manager like [`vim-plug`](https://github.com/junegunn/vim-plug). 

Another useful plugin is [coc.nvim](https://github.com/neoclide/coc.nvim) which can be leveraged for a rich editing experience in Vim. However, this is a suggestion and not a requirement. Choose the tools and plugins that best suit your workflow.

Add the following to your `.vimrc` file:

```vim
" direnv
Plug 'direnv/direnv.vim'

" Haskell Language Server
Plug 'neovimhaskell/haskell-vim'
```

After installing and reloading Vim, when you open a Haskell file in your project, `direnv` should automatically load your environment, and the Haskell Language Server should start providing IDE-like features.

---

Remember that this tutorial provides a very basic setup. You can further customize your environment and editor to better fit your workflow. Happy coding!

> **Note**
> You can run the whole tutorial (except the IDE configuration part) in one command `curl https://input-output-hk.github.io/devx | sh` (handy if you have several machines to configure) :)
