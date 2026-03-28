#!/usr/bin/env bash
set -euo pipefail

# claude-local installer
#
# What this does:
#   1. Checks that the `claude` CLI is installed (installs it if not)
#   2. Adds shell integration to .bashrc / .zshrc so `claude-local` and
#      the `claude` wrapper are available in every new terminal
#
# It does NOT configure an endpoint. After install, run:
#   claude-local config <endpoint> <model>

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${CLAUDE_LOCAL_DIR:-$HOME/.config/claude-local}"
SHELL_INTEGRATION="$REPO_DIR/claude-local.sh"
EXTRA_RC_FILES=()

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rc) EXTRA_RC_FILES+=("$2"); shift 2 ;;
    --rc=*) EXTRA_RC_FILES+=("${1#--rc=}"); shift ;;
    -h|--help)
      echo "usage: bash install.sh [--rc <file>]..."
      echo ""
      echo "options:"
      echo "  --rc <file>   shell rc file to add integration to (repeatable)"
      echo "                default: ~/.bashrc and ~/.zshrc"
      echo ""
      echo "examples:"
      echo "  bash install.sh"
      echo "  bash install.sh --rc ~/.bashrc_private"
      echo "  bash install.sh --rc ~/.bashrc_private --rc ~/.zshrc"
      exit 0
      ;;
    *) echo "unknown flag: $1 (try --help)"; exit 1 ;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { printf "${CYAN}==> %s${NC}\n" "$*"; }
ok()    { printf "${GREEN} ok %s${NC}\n" "$*"; }
warn()  { printf "${YELLOW}warn %s${NC}\n" "$*"; }
fail()  { printf "${RED}err %s${NC}\n" "$*"; exit 1; }

# ------------------------------------------------------------------
# 1. Check / install Claude Code CLI
# ------------------------------------------------------------------
info "checking for claude CLI..."
if command -v claude >/dev/null 2>&1; then
  ok "claude $(claude --version 2>/dev/null || echo '?') found"
else
  info "installing claude CLI..."
  if command -v npm >/dev/null 2>&1; then
    npm install -g @anthropic-ai/claude-code
    ok "claude installed"
  elif command -v npx >/dev/null 2>&1; then
    warn "npm not found but npx is available; claude will run via npx"
  else
    fail "node/npm not found. Install Node.js first: https://nodejs.org"
  fi
fi

# ------------------------------------------------------------------
# 2. Create config directory
# ------------------------------------------------------------------
mkdir -p "$CONFIG_DIR"

# ------------------------------------------------------------------
# 3. Add shell integration to .bashrc / .zshrc
# ------------------------------------------------------------------
SOURCE_LINE="[ -f \"$SHELL_INTEGRATION\" ] && . \"$SHELL_INTEGRATION\""

add_to_shell() {
  local rc="$1"
  if grep -qF "claude-local.sh" "$rc" 2>/dev/null; then
    ok "$rc already has claude-local integration"
  else
    printf '\n# claude-local: route claude to local vLLM\n%s\n' "$SOURCE_LINE" >> "$rc"
    ok "added to $rc"
  fi
}

info "adding shell integration..."
if [ ${#EXTRA_RC_FILES[@]} -gt 0 ]; then
  # User specified explicit rc files — use only those
  for rc in "${EXTRA_RC_FILES[@]}"; do
    add_to_shell "$rc"
  done
else
  # Default: existing .bashrc and/or .zshrc
  found=false
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] && { add_to_shell "$rc"; found=true; }
  done
  if [ "$found" = false ]; then
    add_to_shell "$HOME/.bashrc"
  fi
fi

# ------------------------------------------------------------------
# 4. Done — tell the user what to do next
# ------------------------------------------------------------------
printf "\n"
printf "${GREEN}Installed.${NC}\n"
printf "\n"
printf "Activate in this shell:\n"
printf "  source %s\n" "$SHELL_INTEGRATION"
printf "\n"
printf "Then configure your vLLM endpoint:\n"
printf "  claude-local config <endpoint-url> <model-name>\n"
printf "  claude-local on\n"
printf "\n"
printf "Example:\n"
printf "  claude-local config http://localhost:8000 qwen3-8b\n"
printf "  claude-local on\n"
printf "  claude\n"
printf "\n"
printf "New terminals will have claude-local available automatically.\n"
