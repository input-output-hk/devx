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
# We use overrideAttrs to:
#
#   1. Set propagatedNativeBuildInputs on the derivation
#   2. Write the $out/nix-support/propagated-native-build-inputs file
#
# Step 2 is critical: writeShellApplication uses writeTextFile internally,
# which does NOT run stdenv.mkDerivation's fixupPhase. That fixupPhase is
# what normally materializes the propagatedNativeBuildInputs derivation
# attribute into the $out/nix-support/propagated-native-build-inputs file
# that setup.sh's findInputs reads at runtime. Without the file on disk,
# setting the attribute alone has no effect — setup.sh never sees it.
#
# With the file in place, when stdenv's setup.sh processes the wrapper
# from buildInputs or nativeBuildInputs, it:
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
    let
      allPropagated = runtimeInputs;
      # Space-separated store paths for the propagation file, matching the
      # format that stdenv's setup.sh findInputs expects.
      propagatedPathsStr = builtins.concatStringsSep " "
        (map (dep: "${dep}") allPropagated);
    in
    (pkgs.writeShellApplication args).overrideAttrs (old: {
      propagatedNativeBuildInputs =
        (old.propagatedNativeBuildInputs or []) ++ allPropagated;

      # writeShellApplication (via writeTextFile) does NOT run stdenv's
      # fixupPhase, so the propagatedNativeBuildInputs attribute is never
      # materialized into the nix-support/ file that setup.sh reads.
      # We create it explicitly in postInstall.
      postInstall = (old.postInstall or "") + ''
        mkdir -p $out/nix-support
        echo "${propagatedPathsStr}" > $out/nix-support/propagated-native-build-inputs
      '';
    });
}
