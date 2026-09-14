{
  description = "Worked examples of MoonBit's formal verification, with the solvers pinned";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];
      lock = builtins.fromJSON (builtins.readFile ./tools/nix/toolchain.lock.json);

      # The MoonBit toolchain is distributed as prebuilt binaries under a
      # licence nixpkgs classifies as unfree. Allowing it here, by name, keeps
      # `nix develop` working without asking every reader to set
      # `NIXPKGS_ALLOW_UNFREE`, and without blanket-allowing anything else.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "moonbit" ];
        };
      forEach = f: nixpkgs.lib.genAttrs systems (system: f (pkgsFor system));
    in
    {
      packages = forEach (pkgs: rec {
        moonbit = pkgs.callPackage ./tools/nix/moonbit.nix { inherit lock; };
        default = moonbit;
      });

      devShells = forEach (
        pkgs:
        let
          moonbit = pkgs.callPackage ./tools/nix/moonbit.nix { inherit lock; };
        in
        {
          default = pkgs.mkShell {
            name = "moon-formal-examples";

            packages = [
              moonbit # `moon`, and with it `moon prove`
              pkgs.why3 # what `moon prove` translates the contracts into
              pkgs.z3 # ...and the solvers Why3 hands the goals to. Two, not
              pkgs.cvc5 # one: they close different goals, and the strategy runs
              #           both. See tools/scripts/why3-config.sh.
              pkgs.jq # for re-pinning the toolchain lock
            ];

            shellHook = ''
              echo "moon-formal-examples"
              echo "  moon   $(moon version 2>/dev/null | head -n1)"
              echo "  why3   $(why3 --version 2>/dev/null | head -n1)"
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
        }
      );

      # `nix run .#update-toolchain` re-pins the rolling upstream artifacts.
      apps = forEach (pkgs: {
        update-toolchain = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "update-toolchain" ''
            set -eu
            export PATH="${pkgs.lib.makeBinPath [ pkgs.jq pkgs.gnutar pkgs.gzip ]}:$PATH"
            exec "$PWD/tools/scripts/nix/update-toolchain.sh" "$@"
          ''}/bin/update-toolchain";
        };
      });

      formatter = forEach (pkgs: pkgs.nixfmt);
    };
}
