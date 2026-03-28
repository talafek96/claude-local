#!/usr/bin/env bash
# claude-local: shell integration for routing Claude Code to a local vLLM server.
# Source this file from .bashrc or .zshrc. It provides:
#   - claude()       : wrapper that injects env vars when routing is enabled
#   - claude-local   : management command (on/off/status/config/edit)

CLAUDE_LOCAL_DIR="${CLAUDE_LOCAL_DIR:-$HOME/.config/claude-local}"

claude-local() {
  local cmd="${1:-status}"
  case "$cmd" in
    on|enable)
      if [ ! -f "$CLAUDE_LOCAL_DIR/config.env" ]; then
        echo "error: no config found at $CLAUDE_LOCAL_DIR/config.env"
        echo "run: claude-local config <endpoint> <model>"
        return 1
      fi
      touch "$CLAUDE_LOCAL_DIR/enabled"
      echo "routing: LOCAL"
      # shellcheck disable=SC1091
      . "$CLAUDE_LOCAL_DIR/config.env" 2>/dev/null
      echo "  endpoint: ${ANTHROPIC_BASE_URL:-<not set>}"
      echo "  model:    ${ANTHROPIC_DEFAULT_SONNET_MODEL:-<not set>}"
      ;;
    off|disable)
      rm -f "$CLAUDE_LOCAL_DIR/enabled"
      echo "routing: CLOUD (Anthropic servers)"
      ;;
    status)
      if [ -f "$CLAUDE_LOCAL_DIR/enabled" ] && [ -f "$CLAUDE_LOCAL_DIR/config.env" ]; then
        echo "routing: LOCAL"
        # shellcheck disable=SC1091
        . "$CLAUDE_LOCAL_DIR/config.env" 2>/dev/null
        echo "  endpoint: ${ANTHROPIC_BASE_URL:-<not set>}"
        echo "  model:    ${ANTHROPIC_DEFAULT_SONNET_MODEL:-<not set>}"
        # Quick health check
        if command -v curl >/dev/null 2>&1; then
          if curl -sf "${ANTHROPIC_BASE_URL}/v1/models" >/dev/null 2>&1; then
            echo "  server:   UP"
          else
            echo "  server:   DOWN"
          fi
        fi
      else
        echo "routing: CLOUD (Anthropic servers)"
      fi
      ;;
    config)
      local endpoint="${2:-}"
      local model="${3:-}"
      if [ -z "$endpoint" ] || [ -z "$model" ]; then
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
      echo "config saved to $CLAUDE_LOCAL_DIR/config.env"
      echo "  endpoint: $endpoint"
      echo "  model:    $model"
      ;;
    edit)
      "${EDITOR:-vi}" "$CLAUDE_LOCAL_DIR/config.env"
      ;;
    help|--help|-h)
      cat <<'EOF'
claude-local: route Claude Code to a local vLLM server

commands:
  on|enable          enable local routing
  off|disable        disable local routing (use Anthropic cloud)
  status             show current routing state and server health
  config <url> <m>   set endpoint URL and model name
  edit               open config in $EDITOR

examples:
  claude-local config http://localhost:8000 qwen3-8b
  claude-local on
  claude               # now talks to local vLLM
  claude-local off
  claude               # now talks to Anthropic cloud
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
  # Resolve the real claude binary (skip this function)
  local real_claude
  real_claude="$(command -v claude 2>/dev/null)"
  if [ -z "$real_claude" ]; then
    echo "error: claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
    return 1
  fi

  if [ -f "$CLAUDE_LOCAL_DIR/enabled" ] && [ -f "$CLAUDE_LOCAL_DIR/config.env" ]; then
    # Build env var arguments from config
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
