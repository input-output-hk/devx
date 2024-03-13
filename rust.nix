# Developer shell for Rust programming language
# =============================================
#
# This heavily relies on https://github.com/oxalica/rust-overlay
#
# You can spawn a Rust development shell by running:
#
#     nix develop "github:input-output-hk/devx#rust"
#
# You can specify a channel by replacing `#rust` by `#rust-beta` or
# `#rust-nightly` (by default the shell will use the latest stable), or
# directly specify a Rust version, e.g., `#rust-1.66.1`.

{ pkgs ? import <nixpkgs> { overlays = [ (import <rust-overlay>) ]; } }:
with builtins;
let
  rust-channels = [ "stable" "beta" "nightly" ];
  rust-versions = [
    "1.66.1"
    "1.65.0"
    "1.64.0"
    "1.63.0"
    "1.62.1"
    "1.61.0"
    "1.60.0"
    "1.59.0"
    "1.58.1"
    "1.57.0"
    "1.56.1"
  ];
  shell = channel: version: {
    name = "rust-${channel}-${version}";
    value = with pkgs;
      mkShell {
        nativeBuildInputs = [
          openssl
          pkg-config
          ((if channel == "nightly" then
            rust-bin.selectLatestNightlyWith (toolchain: toolchain.default)
          else
            rust-bin.${channel}.${version}.default).override {
              extensions = [ "rust-src" ];
            })
          rust-analyzer
        ];
        PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
        RUST_BACKTRACE = 1;
      };
  };
  toolchains = listToAttrs ((map (x: shell x "latest") rust-channels)
                         ++ (map (x: shell "stable" x) rust-versions));
  fix = import ./fix-devshells.nix { inherit pkgs; };
in fix (toolchains // { rust = toolchains.rust-stable-latest; }
                   // (listToAttrs ((map (x: { name = "rust-${x}"; value = toolchains."rust-${x}-latest"; }) rust-channels)
                                 ++ (map (x: { name = "rust-${x}"; value = toolchains."rust-stable-${x}"; }) rust-versions))))
