# What does this fix?
# ===================
#
# If you define a developer shell like:
#
#     devShells."rust-1.66.1" = mkShell { … };
#
# … and you try to use with:
#
#     nix develop ".#rust-1.66.1"
#
# … you will get an error!
#
# Because Nix is looking for something like:
#
#     devShells.rust-1."66"."1" = mkShell { … };
#
# The following code will therefore transform an attribute set of the form
#    { "rust-1.66.1" = expr; }
# into
#    { "rust-1.66.1" = expr;
#      rust-1 = { "66" = { "1" = expr; }; };
#    }

{ pkgs ? import <nixpkgs> }:
with builtins;
let
  fix = name: value: {
    name = head name;
    value = let xs = tail name;
    in if xs == [ ] then value else (listToAttrs [ (fix xs value) ]);
  };
in devShells:
foldl' (x: y: (pkgs.lib.recursiveUpdate (listToAttrs [ y ]) x)) { }
(map (name: fix (filter isString (split "\\." name)) devShells.${name})
  (attrNames devShells))
