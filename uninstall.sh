#!/usr/bin/env bash
set -euo pipefail

# claude-local uninstaller
# Removes shell integration and config. Does NOT uninstall the claude CLI itself.

CONFIG_DIR="${CLAUDE_LOCAL_DIR:-$HOME/.config/claude-local}"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { printf "${CYAN}==> %s${NC}\n" "$*"; }
ok()    { printf "${GREEN} ok %s${NC}\n" "$*"; }

# Remove source lines from shell configs
remove_from_shell() {
  local rc="$1"
  if [ -f "$rc" ] && grep -qF "claude-local" "$rc" 2>/dev/null; then
    sed -i '/claude-local/d' "$rc"
    ok "removed from $rc"
  fi
}

info "removing shell integration..."
remove_from_shell "$HOME/.bashrc"
remove_from_shell "$HOME/.zshrc"

info "removing config..."
if [ -d "$CONFIG_DIR" ]; then
  rm -rf "$CONFIG_DIR"
  ok "removed $CONFIG_DIR"
fi

printf "\n${GREEN}Uninstalled.${NC} Restart your shell or open a new terminal.\n"
printf "Claude CLI is still installed. To remove it: npm uninstall -g @anthropic-ai/claude-code\n"
