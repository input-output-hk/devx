# Developer Experience Repo

To obtain a development shell for hacking on haskell based projects at use

```
nix develop github:input-output-hk/devx#ghc8107 --no-write-lock-file --refresh
```

if you want to pick a specific system (e.g. you are on an apple silicon mac, and want to switch between different architectures):

```
nix develop github:input-output-hk/devx#ghc8107 --no-write-lock-file --refresh --system x86_64-darwin
```
or
```
nix develop github:input-output-hk/devx#ghc8107 --no-write-lock-file --refresh --system aarch64-darwin
```

To use a different compiler, chose `#ghc925` instead of `#ghc8107` or similar. There are also other configurations:

- `#ghc8107-minimal` (same as `#ghc8107`, but without `haskell-langauge-server` or `hlint`).
- `#ghc8107-static` (same as `#ghc8107`, but configured to produce static outputs instead of dynamically linked ones).
- `#ghc8107-static-minimal` (same as `#ghc8107-static`, but configured without `haskell-language-server` or `hlint`).
