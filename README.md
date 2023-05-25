# The Developer Experience Shell

This repo contains a `nix develop` shell for haskell. It's primary purpose is to
help get a development shell for haskell products quickly and across multiple
operating systems (and architectures).

It requires [`nix` to be installed](https://nixos.org/download.html).

On a system with `nix`, (linux, macOS, windows WSL) you can use

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

## Compilers and Flavours

There are multiple compilers available, and usually the latest for each series
from 8.10 to 9.6 (a slight delay between the official release announcement and
the compiler showing up in the devx shell is expected due to integration work
necessary). The current available ones are: `ghc8107`, `ghc902`, `ghc945`, and
`ghc961`.

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
