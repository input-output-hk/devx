#! /usr/bin/env nix-shell
#! nix-shell -i python3 -p python3

import os
import timeit

DEV_SHELLS = [
    "ghc8107",
    "ghc902",
    "ghc925",
    "ghc8107-minimal",
    "ghc902-minimal",
    "ghc925-minimal",
    "ghc8107-static-minimal",
    "ghc902-static-minimal",
    "ghc925-static-minimal",
]

def bench(flake):
    T = {}
    for devShell in DEV_SHELLS:
        os.system(f"nix-collect-garbage -d")
        x = lambda number: round(timeit.timeit(lambda: os.system(
            f'nix develop "github:{flake}#{devShell}"\
            --impure --no-write-lock-file --refresh --accept-flake-config --command true'
        ), number=number), 2)
        T[devShell] = {"bootstrap": x(1), "reload": x(10)}
    return T

print([bench("input-output-hk/devx"), bench("yvan-sraka/static-closure")])
