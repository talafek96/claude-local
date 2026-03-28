#!/usr/bin/env bash
set -euo pipefail

# claude-local installer
# Installs Claude Code CLI (if needed) and sets up local vLLM routing.

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${CLAUDE_LOCAL_DIR:-$HOME/.config/claude-local}"
SHELL_INTEGRATION="$REPO_DIR/claude-local.sh"

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
info "setting up $CONFIG_DIR..."
mkdir -p "$CONFIG_DIR"

# ------------------------------------------------------------------
# 3. Configure endpoint (interactive or from arguments)
# ------------------------------------------------------------------
ENDPOINT="${1:-}"
MODEL="${2:-}"

if [ -z "$ENDPOINT" ]; then
  if [ -f "$CONFIG_DIR/config.env" ]; then
    info "existing config found, keeping it"
  else
    printf "\n"
    printf "${CYAN}vLLM endpoint URL${NC} (e.g. http://localhost:8000): "
    read -r ENDPOINT
    printf "${CYAN}Served model name${NC} (e.g. qwen3-8b): "
    read -r MODEL
  fi
fi

if [ -n "$ENDPOINT" ] && [ -n "$MODEL" ]; then
  cat > "$CONFIG_DIR/config.env" <<EOF
ANTHROPIC_BASE_URL=${ENDPOINT}
ANTHROPIC_API_KEY=local
ANTHROPIC_AUTH_TOKEN=local
ANTHROPIC_DEFAULT_OPUS_MODEL=${MODEL}
ANTHROPIC_DEFAULT_SONNET_MODEL=${MODEL}
ANTHROPIC_DEFAULT_HAIKU_MODEL=${MODEL}
CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1
EOF
  ok "config written to $CONFIG_DIR/config.env"
fi

# ------------------------------------------------------------------
# 4. Add shell integration to .bashrc / .zshrc
# ------------------------------------------------------------------
SOURCE_LINE="[ -f \"$SHELL_INTEGRATION\" ] && . \"$SHELL_INTEGRATION\""

add_to_shell() {
  local rc="$1"
  if [ -f "$rc" ]; then
    if grep -qF "claude-local.sh" "$rc" 2>/dev/null; then
      ok "$rc already has claude-local integration"
    else
      printf '\n# claude-local: route claude to local vLLM\n%s\n' "$SOURCE_LINE" >> "$rc"
      ok "added to $rc"
    fi
  fi
}

info "adding shell integration..."
add_to_shell "$HOME/.bashrc"
add_to_shell "$HOME/.zshrc"

# If neither exists, create .bashrc entry
if [ ! -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.zshrc" ]; then
  printf '\n# claude-local: route claude to local vLLM\n%s\n' "$SOURCE_LINE" >> "$HOME/.bashrc"
  ok "created $HOME/.bashrc with claude-local integration"
fi

# ------------------------------------------------------------------
# 5. Enable routing by default
# ------------------------------------------------------------------
if [ -f "$CONFIG_DIR/config.env" ]; then
  touch "$CONFIG_DIR/enabled"
  ok "local routing enabled"
fi

# ------------------------------------------------------------------
# 6. Done
# ------------------------------------------------------------------
printf "\n"
printf "${GREEN}Installation complete!${NC}\n"
printf "\n"
printf "Quick start:\n"
printf "  source %s        # activate in current shell\n" "$SHELL_INTEGRATION"
printf "  claude-local status              # check routing state\n"
printf "  claude                           # uses local vLLM\n"
printf "  claude-local off                 # switch to Anthropic cloud\n"
printf "  claude                           # uses Anthropic cloud\n"
printf "  claude-local on                  # switch back to local\n"
printf "\n"
printf "Or open a new terminal -- it's already configured.\n"
