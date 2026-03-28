# claude-local

Route [Claude Code](https://docs.anthropic.com/en/docs/claude-code) to a local [vLLM](https://docs.vllm.ai/) server. Toggle between local and Anthropic cloud with one command.

## Quick start

```bash
# 1. Install (adds shell integration to .bashrc/.zshrc)
git clone https://github.com/talafek96/claude-local.git
cd claude-local
bash install.sh

# 2. Activate in current shell (new terminals get this automatically)
source claude-local.sh

# 3. Point at your vLLM server
claude-local config http://localhost:8000 qwen3-8b

# 4. Enable local routing
claude-local on

# 5. Use claude — it now talks to your local server
claude
```

## Configuration

All configuration goes through `claude-local config`:

```bash
# Show current config (endpoint, model, config file path)
claude-local config

# Set endpoint and model
claude-local config http://localhost:8000 qwen3-8b

# Point at a remote server
claude-local config http://192.168.200.10:8000 my-model

# Edit the config file directly (for advanced env var tweaks)
claude-local edit
```

The config lives at `~/.config/claude-local/config.env`. It's a plain file of `KEY=VALUE` lines — the environment variables that get passed to `claude` when local routing is on.

## Switching between local and cloud

```bash
claude-local on      # route to local vLLM
claude-local off     # route to Anthropic cloud
claude-local status  # show which mode is active + server health
```

The toggle takes effect immediately across all terminals (no restart needed). When routing is off, `claude` behaves exactly as if claude-local wasn't installed.

## How it works

`claude-local.sh` defines a shell function `claude()` that shadows the real binary. On every invocation it checks a state file (`~/.config/claude-local/enabled`):

- **File present:** reads `config.env`, passes the env vars to `claude` via `env(1)`. Variables are scoped to the claude process only — nothing leaks into your shell.
- **File absent:** calls the real `claude` binary with no modifications.

The key environment variables:

- `ANTHROPIC_BASE_URL` — points Claude Code at your vLLM server
- `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` — dummy values (vLLM doesn't need auth, but Claude Code requires these to be set)
- `ANTHROPIC_DEFAULT_OPUS_MODEL` / `ANTHROPIC_DEFAULT_SONNET_MODEL` / `ANTHROPIC_DEFAULT_HAIKU_MODEL` — your model's served name, used for all tiers

## vLLM server requirements

vLLM 0.17+ natively implements the Anthropic Messages API. Two things are critical:

**1. Tool calling must be enabled.** Claude Code uses tools (file editing, bash, etc.) and will fail with `400 BadRequestError` without this:

```bash
vllm serve your-model \
  --served-model-name my-model \
  --host 0.0.0.0 --port 8000 \
  --enable-auto-tool-choice \
  --tool-call-parser hermes
```

**2. Context length must be large enough.** Claude Code's system prompt is ~9K tokens and it requests up to 32K output tokens. Set `--max-model-len` to at least 42K. If the model's native context is shorter, set `VLLM_ALLOW_LONG_MAX_MODEL_LEN=1`.

The `--tool-call-parser` depends on model architecture — Qwen3 uses `hermes`. See [vLLM tool calling docs](https://docs.vllm.ai/en/stable/features/tool_calling.html).

## Uninstall

```bash
bash uninstall.sh
```

Removes shell integration and config. Does not uninstall the `claude` CLI itself.

## Requirements

- Node.js (for the `claude` CLI)
- A running vLLM server with Anthropic Messages API support (vLLM 0.17+)
- bash or zsh
