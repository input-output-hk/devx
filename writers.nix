# writeShellApplicationWithRuntime — a drop-in replacement for writeShellApplication
# that also propagates runtimeInputs to dependent environments.
#
# ─── The problem ───────────────────────────────────────────────────────────────
#
# nixpkgs' writeShellApplication accepts a `runtimeInputs` parameter and
# compiles it into the wrapper script as:
#
#   export PATH="${lib.makeBinPath runtimeInputs}:$PATH"
#
# This means the runtime inputs are only on PATH **inside the wrapper script
# itself**. They are NOT exposed as derivation attributes — not in
# propagatedNativeBuildInputs, not in passthru, nowhere.
#
# When a wrapper built this way is placed into a mkShell's buildInputs or
# nativeBuildInputs, `nix develop` reconstructs the environment by evaluating
# the shell derivation and walking all inputs. The Nix C++ evaluator (used by
# `nix develop` / `nix print-dev-env`) follows the full derivation closure, so
# it discovers everything transitively — including the runtimeInputs baked into
# wrapper scripts.
#
# However, devx generates `-env` container scripts at **evaluation time** using
# devShellTools. These scripts export raw derivation attributes and then
# `source "$stdenv/setup"` to reconstruct the environment. stdenv's setup.sh
# walks dependencies via the `findInputs` function (stdenv/setup lines 715-806),
# which reads `$pkg/nix-support/propagated-*` metadata files to discover
# transitive inputs. It does NOT look inside wrapper scripts.
#
# The result: any program in the -env container that is NOT the wrapper itself
# (e.g. GHC's stage0 bootstrap cabal, or any script that shells out to curl)
# cannot find the wrapper's runtimeInputs on PATH.
#
# ─── The fix ───────────────────────────────────────────────────────────────────
#
# We use overrideAttrs to add propagatedNativeBuildInputs to the wrapper
# derivation. When stdenv's setup.sh processes the wrapper from
# nativeBuildInputs, it:
#
#   1. Adds $wrapper/bin to PATH  (the wrapper itself)
#   2. Reads $wrapper/nix-support/propagated-native-build-inputs
#   3. Recursively calls findInputs on each propagated input
#   4. Adds $curl/bin, $cabal-install/bin, etc. to PATH
#
# This makes runtimeInputs visible to the ENTIRE shell environment, not just
# inside the wrapper. The wrapper still has its own inline PATH injection
# (via writeShellApplication), so it works in both contexts.
#
# ─── Why not upstream? ─────────────────────────────────────────────────────────
#
# Ideally, nixpkgs' writeShellApplication would set propagatedNativeBuildInputs
# from runtimeInputs by default. Until that happens, this wrapper bridges
# the gap. If upstream adopts this, this file becomes a no-op passthrough
# and can be removed.
#
# ─── Usage ─────────────────────────────────────────────────────────────────────
#
#   let writers = import ./writers.nix { inherit pkgs; };
#   in writers.writeShellApplicationWithRuntime {
#     name = "cabal";
#     runtimeInputs = [ cabal-install pkgs.curl ];
#     text = ''...'';
#   }
#
{ pkgs }:
{
  writeShellApplicationWithRuntime = args@{ runtimeInputs ? [], ... }:
    (pkgs.writeShellApplication args).overrideAttrs (old: {
      propagatedNativeBuildInputs =
        (old.propagatedNativeBuildInputs or []) ++ runtimeInputs;
    });
}
