# The Developer Experience Shell

This repository contains a `nix develop` shell for Haskell. Its primary purpose
is to help get a development shell for Haskell quickly and across multiple
operating systems (and architectures).

It requires [`nix` to be installed](https://nixos.org/download.html).

> [!IMPORTANT]
> The README previously suggested to add your current user to `trusted-users`,
> but this is essentially equivalent to giving that user root access to the
> system.

## Getting Started

Once you have `nix` installed:
- Add `experimental-features = nix-command flakes` to your
  `$XDG_CONFIG_HOME/nix/nix.conf` file to enable Nix flakes.
- You should manually add necessary substituters and trusted public keys to your
  `/etc/nix/nix.conf`:
  ```
  allow-import-from-derivation = "true";
  extra-substituters = https://cache.iog.io https://cache.zw3rk.com
  extra-trusted-public-keys = "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" "loony-tools:pr9m4BkM/5/eSTZlkQyRt57Jz7OMBxNSUiMC4FkcNfk="
  ```
- Ensure that `nix-daemon` is running (`systemctl status nix-daemon` on
  `systemd`-based systems).

Then, (on Linux, macOS, windows WSL) you can use:
```bash
nix develop github:input-output-hk/devx#ghc96 --no-write-lock-file --refresh
```

To obtain a haskell development shell for GHC 8.10.7 including `cabal-install`,
as well as `hls` and `hlint`. If you are on macOS on an Apple Silicon chip
(M1, M2, ...), and want to switch between Intel (x86_64) and Apple Silicon
(aarch64), you can do this by simply passing the corresponding
`--system` argument:
```bash
nix develop github:input-output-hk/devx#ghc810 --no-write-lock-file --refresh --system x86_64-darwin
# ... or:
nix develop github:input-output-hk/devx#ghc810 --no-write-lock-file --refresh --system aarch64-darwin
```

## `direnv` integration

If you use [`direnv`](https://direnv.net), you can integrate this shell by creating an `.envrc` file with the following content:
```
# https://github.com/nix-community/nix-direnv A fast, persistent use_nix/use_flake implementation for direnv:
if ! has nix_direnv_version || ! nix_direnv_version 2.3.0; then
  source_url "https://raw.githubusercontent.com/nix-community/nix-direnv/2.3.0/direnvrc" "sha256-Dmd+j63L84wuzgyjITIfSxSD57Tx7v51DMxVZOsiUD8="
fi
# https://github.com/input-output-hk/devx Slightly opinionated shared GitHub Action for Cardano-Haskell projects 
use flake "github:input-output-hk/devx#ghc810-iog"
```

Refer to [`direnv` and `devx`](./docs/direnv.md) guide for more information.

## VSCode DevContainer / GitHub CodeSpace support

To make this developer shell available in VSCode DevContainer or GitHub CodeSpace, simply add a file named `.devcontainer/devcontainer.json` with the following content:
```json
{
   "image":"ghcr.io/input-output-hk/devx-devcontainer:x86_64-linux.ghc96-iog",
   "postCreateCommand": "post-create-command",
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
This configuration will work immediately in GitHub CodeSpace! For local VSCode DevContainer, you need Docker and the [VSCode extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers). For guidance on this, you can follow the [Microsoft tutorial](https://code.visualstudio.com/docs/devcontainers/tutorial).

It's also advised to enable GitHub CodeSpace prebuilds in your repository settings, follow the instructions provided in the [GitHub documentation](https://docs.github.com/en/codespaces/prebuilding-your-codespaces/configuring-prebuilds). This will significantly enhance your development experience by reducing the setup time when opening a new CodeSpace.

List of images available: `ghc810-iog`, `ghc96-iog`, `ghc810-js-iog`, `ghc96-js-iog`, `ghc810-windows-iog`, `ghc96-windows-iog`.

> [!TIP]
> If you wish to utilize the DevContainer as a normal Docker container outside of GitHub or VSCode, remember to prefix your commands with `bash -ic`. This is necessary because the Nix developer environment is loaded through `~/.bashrc`.
> E.g., `docker run -it ghcr.io/input-output-hk/devx-devcontainer:x86_64-linux.ghc96-iog bash -ic "cabal --version"`

## Compilers and Flavors

There are multiple compilers available, and usually the latest for each series
from 8.10 to 9.6 (a slight delay between the official release announcement and
the compiler showing up in the devx shell is expected due to integration work
necessary). The current available ones are: `ghc810`, `ghc90`, `ghc92`, `ghc94`, and
`ghc96` (these are the same ones as in [haskell.nix](https://github.com/input-output-hk/haskell.nix) and may contain patches for defects in the official releases).

### Flavors

There are various flavors available as suffixes to the compiler names (e.g. `#ghc810-minimal-iog`).

| Flavor | Description | Example | Included |
| - | - | - | - |
| empty | General Haskell Dev | `#ghc810` | `ghc`, `cabal-install`, `hls`, `hlint` |
| `-iog` | IOG Haskell Dev | `#ghc810` | adds `sodium-vrf`, `blst`, `secp256k1` |
| `-iog-full` | IOG Haskell Dev | `#ghc810` | adds `sodium-vrf`, `blst`, `secp256k1`, `R`, `postgresql` |
| `-minimal` | Only GHC, and Cabal | `#ghc810-minimal` | drops `hls`, `hlint` |
| `-static` | Building static binaries | `#ghc810-static` | Static Haskell Cross-Compiler |
| `-js` | JavaScript Cross-Compiler | `#ghc810-js` | JavaScript Haskell Cross-Compiler |
| `-windows` | Windows Cross-Compiler | `#ghc810-windows` | Windows Haskell Cross-Compiler |

These can then be combined following this schema:
```
#ghc<ver>[-js|-windows|-static][-minimal][-iog]
```
For example:
```bash
nix develop github:input-output-hk/devx#ghc810-windows-minimal-iog --no-write-lock-file --refresh
```
... would provide a development shell with a windows cross-compiler as well as cabal, and the IOG specific libraries, but no Haskell Language Server (`hls`), and no HLint.

A full list of all available `devShells` can be seen with:
```bash
nix flake show github:input-output-hk/devx
```

## To Go Further

### Customizing with `haskell.nix`

The `devx` shell utilizes `haskell.nix` for a consistent development environment across platforms. Direct use of `haskell.nix` allows for greater customization by adapting Nix expressions to specific project needs, `haskell.nix` turn a Cabal or Stack projects into a Nix expression. For more details, see the [`haskell.nix` documentation](https://input-output-hk.github.io/haskell.nix/).

### Automating with IOG GitHub Actions

The `devx` GitHub Action, alongside other IOG-provided actions, supports automated workflows for Haskell projects. More information can be found in the [IOG GitHub Actions repository](https://github.com/input-output-hk/actions).

> [!NOTE]
> For commercial support, please don't hesitate to reach out at devx@iohk.io
