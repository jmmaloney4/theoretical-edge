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

          # Create the new post script
          create-post = let
            createPostScript = pkgs.writeText "create_post.py" ''
              #!/usr/bin/env python3
              import os
              import re
              from datetime import date

              def slugify(text: str) -> str:
                  s = text.lower()
                  s = re.sub(r"[^a-z0-9\s-]", "", s)
                  s = re.sub(r"\s+", "-", s.strip())
                  return s

              def prompt(prompt_text: str, default: str = "") -> str:
                  resp = input(f"{prompt_text} " + (f"[{default}] " if default else ""))
                  return resp.strip() or default

              def main():
                  # 1. Gather info
                  title = prompt("Post title:")
                  subtitle = prompt("Post subtitle (optional):", "")
                  author = prompt("Author name:", os.getenv("USER", ""))
                  cats   = prompt("Categories (comma-separated):", "")
                  draft_flag = prompt("Draft? (y/N):", "N").lower()
                  draft = "true" if draft_flag in ("y", "yes") else "false"
                  
                  # 2. Date & slug
                  today = date.today().isoformat()             # e.g. "2025-06-20"
                  slug  = slugify(title)                       # e.g. "my-new-post"
                  folder = f"{today}-{slug}"                   # e.g. "2025-06-20-my-new-post"
                  
                  # 3. Make directory
                  post_dir = os.path.join("posts", folder)
                  os.makedirs(post_dir, exist_ok=True)
                  
                  # 4. Write index.qmd
                  filepath = os.path.join(post_dir, "index.qmd")
                  fm_lines = [
                      "---",
                      f"title: \"{title}\"",
                  ]
                  
                  if subtitle:
                      fm_lines.append(f"subtitle: \"{subtitle}\"")
                  
                  fm_lines.extend([
                      f"author: \"{author}\"",
                      f"date: {today}",
                      "categories: [" + ", ".join(c.strip() for c in cats.split(",") if c.strip()) + "]",
                      f"draft: {draft}",
                      "format: html",
                      "execute:",
                      "  echo: true",
                      "  warning: false",
                      "---",
                      "",
                      "<!-- start writing your post here -->"
                  ])
                  with open(filepath, "w") as f:
                      f.write("\n".join(fm_lines))
                  
                  print(f"\n✔ Created new post at:\n  {filepath}\n")

              if __name__ == "__main__":
                  main()
            '';
          in pkgs.writeShellApplication {
            name = "create-post";
            runtimeInputs = [pkgs.python3];
            text = ''
              python3 ${createPostScript}
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
            self'.packages.create-post
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

              # Create a new blog post
              new-post:
                ${lib.getExe self'.packages.create-post}
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
