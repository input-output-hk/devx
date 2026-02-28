# extra/discover-env.nix — Discover -env closure store paths from the flake.
#
# Copyright 2026 Input Output Group
# SPDX-License-Identifier: Apache-2.0
#
# Used by the GHA upload workflow as a fallback when Hydra does not create
# individual GitHub check-runs for cached builds.  Evaluates the flake's
# hydraJobs and returns a JSON array of {config, build_path, short_name}
# for every -env attribute on the given platform.
#
# Usage:
#   nix eval ".#hydraJobs.<platform>" --json --apply "import ./extra/discover-env.nix \"<platform>\""
#
platform: jobs:
let
  envNames = builtins.filter
    (n: builtins.match ".*-env" n != null)
    (builtins.attrNames jobs);
in map (name: {
  config = platform + "." + name;
  build_path = builtins.unsafeDiscardStringContext (toString jobs.${name});
  short_name = name;
}) envNames
