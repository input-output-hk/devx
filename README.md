# The Developer Experience Shell

This repo contains a `nix develop` shell for haskell. Its primary purpose is to
help get a development shell for haskell quickly and across multiple
operating systems (and architectures).

It requires [`nix` to be installed](https://nixos.org/download.html).

Once you have `nix` installed you can check that everything is working correctly:
* Make sure to add `experimental-features = nix-command flakes` and `accept-flake-config = true` lines to `$XDG_CONFIG_HOME/nix/nix.conf` file ;
* Make sure your `$USER` is trusted `grep 'trusted-users' /etc/nix/nix.conf`, otherwise add it to `/etc/nix/nix.conf` and restart `nix-daemon` ;
* Make sure the `nix-daemon` is running using `systemctl status nix-daemon` (if your OS is `systemd`-based).

Once you have `nix`, (linux, macOS, windows WSL) you can use

```bash
nix develop github:input-output-hk/devx#ghc8107 --no-write-lock-file --refresh
```

to obtain a haskell evelopment shell for GHC 8.10.7 including `cabal-install`,
as well as `hls` and `hlint`. If you are on macOS on an apple silicon chip (M1, M2, ...),
and want to switch between Intel (x86_64) and Apple Silicon (aarch64), you can do
this by simply passing the corresponding `--system` argument:

```bash
nix develop github:input-output-hk/devx#ghc8107 --no-write-lock-file --refresh --system x86_64-darwin
```
or
```bash
nix develop github:input-output-hk/devx#ghc8107 --no-write-lock-file --refresh --system aarch64-darwin
```

## `direnv` integration

If you use [`direnv`](https://direnv.net), you can integrate this shell with:
```
# https://github.com/nix-community/nix-direnv A fast, persistent use_nix/use_flake implementation for direnv:
if ! has nix_direnv_version || ! nix_direnv_version 2.3.0; then
  source_url "https://raw.githubusercontent.com/nix-community/nix-direnv/2.3.0/direnvrc" "sha256-Dmd+j63L84wuzgyjITIfSxSD57Tx7v51DMxVZOsiUD8="
fi
# https://github.com/input-output-hk/devx Slightly opinionated shared GitHub Action for Cardano-Haskell projects 
use flake "github:input-output-hk/devx#ghc8107-iog"
```

Refer to [`direnv` and `devx`](./docs/direnv.md) guide for more information.

## VSCode DevContainer / GitHub CodeSpace support

To make this developer shell available in VSCode DevContainer or GitHub CodeSpace, simply add a file named `.devcontainer/devcontainer.json` with the following content:
```json
{
   "image":"ghcr.io/input-output-hk/devx-devcontainer:ghc8107",
   "customizations":{
      "vscode":{
         "extensions":[
            "haskell.haskell"
         ],
         "settings":{
            "haskell.manageHLS":"PATH"
         }
      }
   }
}
```
This configuration will work immediately in GitHub CodeSpace! For local VSCode DevContainer, you need Docker and the VSCode extension https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers. For guidance on this, you can follow the official Microsoft tutorial at https://code.visualstudio.com/docs/devcontainers/tutorial.

## Compilers and Flavours

There are multiple compilers available, and usually the latest for each series
from 8.10 to 9.6 (a slight delay between the official release announcement and
the compiler showing up in the devx shell is expected due to integration work
necessary). The current available ones are: `ghc8107`, `ghc902`, `ghc928`,`ghc945`, and
`ghc962` (these are the same ones as in [haskell.nix](https://github.com/input-output-hk/haskell.nix) and may contain patches for defects in the official releases).

### Flavours
There are various flavours available as suffixes to the compiler names (e.g. `#ghc8107-minimal-iog`).

| Flavour | Description | Example | Included |
| - | - | - | - |
| empty | General Haskell Dev | `#ghc8107` | `ghc`, `cabal-install`, `hls`, `hlint` |
| `-iog` | IOG Haskell Dev | `#ghc8107` | adds `sodium-vrf`, `blst`, `secp256k1`, `R`, `postgresql` |
| `-minimal` | Only GHC, and Cabal | `#ghc8107-minimal` | drops `hls`, `hlint` |
| `-static` | Building static binaries | `#ghc8107-static` | static haskell cross compiler |
| `-js` | JavaScript Cross Compiler | `#ghc8107-js` | javascript haskell cross compiler |
| `-windows` | Windows Cross Compiler | `#ghc8107-windows` | windows haskell cross compiler |

these can then be comined following this schema:
```
#ghc<ver>[-js|-windows|-static][-minimal][-iog]
```
For example
```bash
nix develop github:input-output-hk/devx#ghc8107-windows-minimal-iog --no-write-lock-file --refresh
```
would provide a development shell with a windows cross compiler as well as cabal, and the IOG specific libraries, but no Haskell Language Server (hls), and no HLint.

A full list of all available `devShells` can be see with:
```bash
nix flake show github:input-output-hk/devx
```
