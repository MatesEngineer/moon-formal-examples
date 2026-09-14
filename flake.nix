{
  description = "Worked examples of MoonBit's formal verification, with the solvers pinned";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Versioned, prebuilt MoonBit toolchains, mirrored to the overlay's own
    # GitHub releases. Upstream publishes only a rolling `latest`, so a lock
    # against that URL can stop resolving once upstream moves; the mirror gives
    # an immutable URL per version instead. It also handles patchelf and the
    # standard-library bundle, which is the rest of what a hand-rolled
    # derivation for this has to get right.
    moonbit-overlay.url = "github:moonbit-community/moonbit-overlay";
  };

  outputs =
    {
      self,
      nixpkgs,
      moonbit-overlay,
    }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];

      # The exact toolchain every measurement in the README was taken with.
      # `.` becomes `_` and `+` becomes `-` in the attribute name.
      toolchain = "v0_10_12-1634b282e-94521db";

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ moonbit-overlay.overlays.default ];
        };
      forEach = f: nixpkgs.lib.genAttrs systems (system: f (pkgsFor system));
    in
    {
      packages = forEach (pkgs: rec {
        moonbit = pkgs.moonbit-bin.moonbit.${toolchain};
        default = moonbit;
      });

      devShells = forEach (pkgs: {
        default = pkgs.mkShell {
          name = "moon-formal-examples";

          packages = [
            pkgs.moonbit-bin.moonbit.${toolchain}

            # The solvers, and only the solvers.
            #
            # Why3 itself is not here, and does not need to be. The MoonBit
            # toolchain ships Why3's data and drivers under `share/why3` and
            # its `why3server` under `lib/why3`, and `moon prove` drives those
            # directly. Verified by proving this repository with no `why3` on
            # PATH at all.
            #
            # That matters beyond tidiness: nixpkgs' `why3` is built from
            # OCaml, so depending on it drags an OCaml toolchain into a closure
            # that otherwise has none.
            #
            # Two solvers rather than one, because they close different goals
            # and the strategy tries each in turn. See tools/scripts/why3-config.sh.
            pkgs.z3
            pkgs.cvc5
          ];

          shellHook = ''
            echo "moon-formal-examples"
            echo "  moon   $(moon version 2>/dev/null | head -n1)"
            echo "  z3     $(z3 --version 2>/dev/null | head -n1)"
            echo "  cvc5   $(cvc5 --version 2>/dev/null | head -n1)"
            echo
            echo "  ./tools/scripts/prove.sh   discharge every proof obligation"
            echo "  moon -C src test           run the tests"
            echo

            # `moon` keeps its mutable registry and caches under MOON_HOME;
            # only the toolchain itself comes from the store.
            export MOON_HOME="''${MOON_HOME:-$HOME/.moon}"
          '';
        };
      });

      formatter = forEach (pkgs: pkgs.nixfmt);
    };
}
