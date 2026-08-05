{
  description = "Secure AI Agent Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    jail-nix.url = "sourcehut:~alexdavid/jail.nix";
    flake-utils.url = "github:numtide/flake-utils";
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

  outputs =
    {
      nixpkgs,
      jail-nix,
      llm-agents,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        jail = jail-nix.lib.init pkgs;

        # Define the Security Policy
        commonJailOptions = with jail.combinators; [
          network # access to the internet for API calls
          time-zone # Neutralize the time to UTC for privacy
          no-new-session # Prevents the agent from detaching background processes

          (readwrite (noescape "~/.cache/uv"))
          (readwrite (noescape "~/.agents"))
          (readwrite (noescape "~/.cargo"))
          (readwrite (noescape "~/.npm"))

          (set-env "EDITOR" "vim")
          # (readwrite (noescape "~/.config/vim"))

          (set-env "COLORTERM" "truecolor")

          (add-runtime ''
            RUNTIME_ARGS+=(
              --dir /usr
              --dir /usr/bin
              --ro-bind "${pkgs.coreutils}/bin/env" /usr/bin/env
              --ro-bind "${pkgs.bash}/bin/bash" /bin/bash
            )
          '')

          (add-runtime ''
            if [ -z "$PROJECT_DIR" ]; then
              echo "Error: PROJECT_DIR environment variable is not set" >&2
              exit 1
            fi
            if [ -d "$PROJECT_DIR" ]; then
              RUNTIME_ARGS+=(--bind "$PROJECT_DIR" "$PROJECT_DIR")
            else
              echo "Error: PROJECT_DIR '$PROJECT_DIR' does not exist" >&2
              exit 1
            fi
          '')
          (try-fwd-env "PROJECT_DIR")

          # (set-env "HTTP_PROXY" "http://127.0.0.1:8888")
          # (set-env "HTTPS_PROXY" "http://127.0.0.1:8888")
        ];

        commonPkgs =
          with pkgs;
          [
            bash
            curl
            wget
            git
            vim-full
            jq
            which
            fd
            gnused
            gnugrep
            ripgrep
            gawkInteractive
            findutils
            diffutils
            ps
            direnv
            file

            nodejs

            # Claude Code and Gemini Hooks
            uv
            ty
            ruff
            python313
            just

            # formatter
            prettier
            nixfmt
            shfmt
          ]
          ++ [
            llm-agents.packages.${system}.openspec
          ];

        claude-code-pkg = pkgs.writeShellScriptBin "claude" ''
          exec ${llm-agents.packages.${system}.claude-code}/bin/claude --dangerously-skip-permissions "$@"
        '';

        gemini-cli-pkg = pkgs.writeShellScriptBin "gemini" ''
          exec ${llm-agents.packages.${system}.gemini-cli}/bin/gemini --approval-mode=yolo "$@"
        '';

        opencode-pkg = pkgs.writeShellScriptBin "opencode" ''
          exec ${llm-agents.packages.${system}.opencode}/bin/opencode --auto "$@"
        '';

        codex-pkg = pkgs.writeShellScriptBin "codex" ''
          codex_args=()
          project_dir="''${PROJECT_DIR:-$PWD}"
          if [ -n "$project_dir" ]; then
            project_dir_escaped="''${project_dir//\\/\\\\}"
            project_dir_escaped="''${project_dir_escaped//\"/\\\"}"
            codex_args+=(
              --cd "$project_dir"
              --config "projects={\"$project_dir_escaped\"={trust_level=\"trusted\"}}"
            )
          fi

          exec ${
            llm-agents.packages.${system}.codex
          }/bin/codex --dangerously-bypass-approvals-and-sandbox "''${codex_args[@]}" "$@"
        '';

        # --- The Sandboxes ---
        makeJailedClaude =
          {
            extraPkgs ? [ ],
          }:
          jail "jailed-claude" claude-code-pkg (
            with jail.combinators;
            (
              commonJailOptions
              ++ [
                (set-env "ANTHROPIC_MODEL" "claude-opus-5")
                (readwrite (noescape "~/.claude"))
                (readwrite (noescape "~/.claude.json"))

                (add-pkg-deps commonPkgs)
                (add-pkg-deps extraPkgs)
              ]
            )
          );

        makeJailedGemini =
          {
            extraPkgs ? [ ],
          }:
          jail "jailed-gemini" gemini-cli-pkg (
            with jail.combinators;
            (
              commonJailOptions
              ++ [
                (readwrite (noescape "~/.gemini"))

                (add-pkg-deps commonPkgs)
                (add-pkg-deps extraPkgs)
              ]
            )
          );

        makeJailedCodex =
          {
            extraPkgs ? [ ],
          }:
          jail "jailed-codex" codex-pkg (
            with jail.combinators;
            (
              commonJailOptions
              ++ [
                (readwrite (noescape "~/.codex"))

                (add-pkg-deps commonPkgs)
                (add-pkg-deps extraPkgs)
              ]
            )
          );

        makeJailedOpenCode =
          {
            extraPkgs ? [ ],
          }:
          jail "jailed-opencode" opencode-pkg (
            with jail.combinators;
            (
              commonJailOptions
              ++ [
                (readwrite (noescape "~/.config/opencode"))
                (readwrite (noescape "~/.local/share/opencode"))
                (readwrite (noescape "~/.local/state/opencode"))

                # Persist caches to prevent re-downloading models and packages
                (readwrite (noescape "~/.cache/opencode"))

                (add-pkg-deps commonPkgs)
                (add-pkg-deps extraPkgs)
              ]
            )
          );

        debug = jail "debug" pkgs.bashInteractive (
          with jail.combinators;
          (
            commonJailOptions
            ++ [
              (add-pkg-deps commonPkgs)
              (add-pkg-deps [ codex-pkg ])
            ]
          )
        );
      in
      {
        lib = {
          inherit makeJailedClaude;
          inherit makeJailedGemini;
          inherit makeJailedCodex;
          inherit makeJailedOpenCode;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            (makeJailedClaude { })
            (makeJailedGemini { })
            (makeJailedCodex { })
            (makeJailedOpenCode { })
            debug
          ];
        };
      }
    );
}
