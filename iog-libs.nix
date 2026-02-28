# iog-libs.nix — Canonical list of IOG-specific dependencies.
#
# Copyright 2025 Input Output Group
# SPDX-License-Identifier: Apache-2.0
#
# Imported by dynamic.nix, static.nix, cross-js.nix, cross-windows.nix.
# When adding a new IOG library, update the relevant category here
# and each consumer file will pick it up automatically.
#
# The `static` flag controls whether linked libraries resolve to their
# static-* variants (for musl cross-compilation in static.nix).
{ pkgs, static ? false }:
let
  # For linked libraries, resolve to static-* variants when building
  # static shells (musl cross-compilation).
  resolve = name:
    if static
    then builtins.getAttr ("static-" + name) pkgs
    else builtins.getAttr name pkgs;
in {
  # Cryptographic libraries required by the Cardano stack.
  # Present in ALL shell types (dynamic, static, cross-js, cross-windows).
  crypto = map resolve [ "libblst" "libsodium-vrf" "secp256k1" ];

  # Data-storage libraries (ouroboros-consensus / cardano-lmdb).
  # Dynamic and static shells only — not meaningful for JS/Windows cross.
  data = map resolve [ "lmdb" ];

  # Development/CI tools (not linked into builds). Dynamic and static only.
  tools = with pkgs; [ cbor-diag cddl gh icu jq yq-go ];

  # Minimal tool set for cross-compilation targets (CDDL/CBOR validation).
  cross-tools = with pkgs; [ cbor-diag cddl ];
}
