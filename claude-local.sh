#!/usr/bin/env bash
# claude-local: shell integration for routing Claude Code to a local vLLM server.
# Source this file from .bashrc or .zshrc. It provides:
#   - claude()       : wrapper that injects env vars when routing is enabled
#   - claude-local   : management command (on/off/status/config/edit)

CLAUDE_LOCAL_DIR="${CLAUDE_LOCAL_DIR:-$HOME/.config/claude-local}"

_claude_local_show_config() {
  if [ ! -f "$CLAUDE_LOCAL_DIR/config.env" ]; then
    echo "no config yet"
    echo "run: claude-local config <endpoint> <model>"
    return 1
  fi
  # shellcheck disable=SC1091
  (. "$CLAUDE_LOCAL_DIR/config.env" 2>/dev/null
   echo "  endpoint: ${ANTHROPIC_BASE_URL:-<not set>}"
   echo "  model:    ${ANTHROPIC_DEFAULT_SONNET_MODEL:-<not set>}"
   echo "  file:     $CLAUDE_LOCAL_DIR/config.env")
}

claude-local() {
  local cmd="${1:-status}"
  case "$cmd" in
    on|enable)
      if [ ! -f "$CLAUDE_LOCAL_DIR/config.env" ]; then
        echo "error: no config found"
        echo "run: claude-local config <endpoint> <model>"
        return 1
      fi
      touch "$CLAUDE_LOCAL_DIR/enabled"
      echo "routing: LOCAL"
      _claude_local_show_config
      ;;
    off|disable)
      rm -f "$CLAUDE_LOCAL_DIR/enabled"
      echo "routing: CLOUD (Anthropic servers)"
      ;;
    status)
      if [ -f "$CLAUDE_LOCAL_DIR/enabled" ] && [ -f "$CLAUDE_LOCAL_DIR/config.env" ]; then
        echo "routing: LOCAL"
        _claude_local_show_config
        if command -v curl >/dev/null 2>&1; then
          # shellcheck disable=SC1091
          (. "$CLAUDE_LOCAL_DIR/config.env" 2>/dev/null
           if curl -sf "${ANTHROPIC_BASE_URL}/v1/models" >/dev/null 2>&1; then
             echo "  server:   UP"
           else
             echo "  server:   DOWN"
           fi)
        fi
      else
        echo "routing: CLOUD (Anthropic servers)"
        if [ -f "$CLAUDE_LOCAL_DIR/config.env" ]; then
          echo "(local config exists but routing is off — run: claude-local on)"
        fi
      fi
      ;;
    config)
      local endpoint="${2:-}"
      local model="${3:-}"
      if [ -z "$endpoint" ]; then
        # No args: show current config
        echo "current config:"
        _claude_local_show_config
        echo ""
        echo "to change: claude-local config <endpoint> <model>"
        echo "to edit:   claude-local edit"
        return 0
      fi
      if [ -z "$model" ]; then
        echo "error: missing model name"
        echo "usage: claude-local config <endpoint> <model>"
        echo ""
        echo "examples:"
        echo "  claude-local config http://localhost:8000 qwen3-8b"
        echo "  claude-local config http://192.168.200.10:8000 my-model"
        return 1
      fi
      mkdir -p "$CLAUDE_LOCAL_DIR"
      cat > "$CLAUDE_LOCAL_DIR/config.env" <<EOF
ANTHROPIC_BASE_URL=${endpoint}
ANTHROPIC_API_KEY=local
ANTHROPIC_AUTH_TOKEN=local
ANTHROPIC_DEFAULT_OPUS_MODEL=${model}
ANTHROPIC_DEFAULT_SONNET_MODEL=${model}
ANTHROPIC_DEFAULT_HAIKU_MODEL=${model}
CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1
EOF
      echo "config saved:"
      echo "  endpoint: $endpoint"
      echo "  model:    $model"
      echo "  file:     $CLAUDE_LOCAL_DIR/config.env"
      ;;
    edit)
      "${EDITOR:-vi}" "$CLAUDE_LOCAL_DIR/config.env"
      ;;
    help|--help|-h)
      cat <<'EOF'
claude-local: route Claude Code to a local vLLM server

commands:
  status             show routing state, config, and server health (default)
  on                 enable local routing
  off                disable local routing (use Anthropic cloud)
  config             show current endpoint and model
  config <url> <m>   set endpoint URL and model name
  edit               open config file in $EDITOR
  help               show this help

examples:
  claude-local config http://localhost:8000 qwen3-8b
  claude-local on
  claude                # talks to local vLLM
  claude-local off
  claude                # talks to Anthropic cloud

config file: ~/.config/claude-local/config.env
EOF
      ;;
    *)
      echo "unknown command: $cmd (try: claude-local help)"
      return 1
      ;;
  esac
}

# Wrapper: intercepts `claude` calls and injects env vars when routing is active.
# Uses env(1) so the variables are scoped to the claude process only.
claude() {
  local real_claude
  real_claude="$(command -v claude 2>/dev/null)"
  if [ -z "$real_claude" ]; then
    echo "error: claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
    return 1
  fi

  if [ -f "$CLAUDE_LOCAL_DIR/enabled" ] && [ -f "$CLAUDE_LOCAL_DIR/config.env" ]; then
    local env_args=()
    while IFS='=' read -r key value; do
      [ -z "$key" ] && continue
      [[ "$key" =~ ^# ]] && continue
      env_args+=("${key}=${value}")
    done < "$CLAUDE_LOCAL_DIR/config.env"
    env "${env_args[@]}" "$real_claude" "$@"
  else
    "$real_claude" "$@"
  fi
}
