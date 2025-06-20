{
  inputs = {
    ### Nixpkgs ###
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    ### Flake / Project Inputs ###
    flake-parts.url = "github:hercules-ci/flake-parts";

    flake-root.url = "github:srid/flake-root";

    just-flake.url = "github:juspay/just-flake";

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      # inputs.flake-utils.inputs.systems.follows = "systems";
    };

    systems.url = "github:nix-systems/default";

    treefmt = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-parts,
    flake-root,
    just-flake,
    pre-commit-hooks,
    systems,
    treefmt,
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} ({
      withSystem,
      inputs,
      ...
    }: {
      systems = import systems;
      imports = [
        flake-root.flakeModule
        just-flake.flakeModule
        pre-commit-hooks.flakeModule
        treefmt.flakeModule
      ];

      perSystem = {
        config,
        self',
        inputs',
        pkgs,
        system,
        lib,
        ...
      }: {
        packages = {
          # Define the Python environment for Quarto
          pythonEnv = pkgs.python3.withPackages (ps:
            with ps; [
              matplotlib
              numpy
            ]);

          # Create a wrapped Quarto executable
          quarto = pkgs.writeShellApplication {
            name = "quarto";
            runtimeInputs = [pkgs.quarto self'.packages.pythonEnv];
            text = ''
              # Ensure pythonEnv's bin is prioritized in PATH
              export PATH="${self'.packages.pythonEnv}/bin:$PATH"
              # Execute the original quarto command
              exec ${lib.getExe pkgs.quarto} "$@"
            '';
          };
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [
            config.just-flake.outputs.devShell
            config.pre-commit.devShell
            config.treefmt.build.devShell
          ];
          buildInputs = with pkgs; [
            # Use the wrapped quarto in the dev shell
            self'.packages.quarto
            self'.packages.pythonEnv
          ];
        };

        just-flake.features = {
          treefmt.enable = true;
          preview = {
            enable = true;
            justfile = ''
              # Preview the quarto project
              preview:
                ${lib.getExe self'.packages.quarto} preview
            '';
          };
        };

        pre-commit = {
          check.enable = true;
          settings.hooks.treefmt.enable = true;
          settings.settings.treefmt.package = config.treefmt.build.wrapper;
        };

        treefmt.config = {
          inherit (config.flake-root) projectRootFile;
          package = pkgs.treefmt;
          programs.alejandra.enable = true;
        };
        formatter = config.treefmt.build.wrapper;
      };
    });
}
