#!/usr/bin/env bash

SOURCE_DIR="$HOME/repo/important/jailed-agents"

AGENT_CMD=""
DEBUG_MODE=false

reject_home_project_dir() {
  local project_dir
  local home_dir

  project_dir=$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P)
  home_dir=$(cd "$HOME" 2>/dev/null && pwd -P)

  if [ "$project_dir" = "$home_dir" ]; then
    echo "Error: Refusing to launch from home directory. Run this from a project directory instead."
    exit 1
  fi
}

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
  --claude)
    AGENT_CMD="jailed-claude"
    shift
    ;;
  --gemini)
    AGENT_CMD="jailed-gemini"
    shift
    ;;
  --codex)
    AGENT_CMD="jailed-codex"
    shift
    ;;
  --opencode)
    AGENT_CMD="jailed-opencode"
    shift
    ;;
  --debug)
    DEBUG_MODE=true
    shift
    ;;
  -h | --help)
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Options:"
    echo "  --claude    Run Claude agent"
    echo "  --gemini    Run Gemini agent"
    echo "  --codex     Run Codex agent"
    echo "  --opencode  Run OpenCode agent"
    echo "  --debug     Run debug shell"
    echo "  -h, --help  Show this help message"
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    exit 1
    ;;
  esac
done

if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR=$(pwd)
fi
reject_home_project_dir
export PROJECT_DIR

if [ "$DEBUG_MODE" = true ]; then
  exec nix develop "$SOURCE_DIR" -c debug
fi

if [ -z "$AGENT_CMD" ]; then
  echo "Error: No agent specified. Use --claude, --gemini, --codex, or --opencode"
  exit 1
fi

if [ ! -f "$SOURCE_DIR/flake.nix" ]; then
  echo "Error: Source flake.nix not found in $SOURCE_DIR"
  exit 1
fi

echo "Running $AGENT_CMD on $PROJECT_DIR..."
exec nix develop "$SOURCE_DIR" -c "$AGENT_CMD"
