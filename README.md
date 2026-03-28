# claude-local

Route [Claude Code](https://docs.anthropic.com/en/docs/claude-code) to a local [vLLM](https://docs.vllm.ai/) server with one command. Switch between your own hardware and Anthropic's cloud on the fly.

## Why

Claude Code is an excellent agentic coding tool. But it only talks to Anthropic's API by default. If you have local GPU hardware running vLLM (which natively speaks the Anthropic Messages API), you can use Claude Code with your own models -- fully private, zero cost per token.

This repo provides a shell integration that:
- Wraps the `claude` command transparently
- Injects the right environment variables to redirect traffic to your vLLM server
- Lets you toggle between local and cloud with `claude-local on` / `claude-local off`
- Persists your choice across all terminal sessions via a state file

## Install

```bash
git clone https://github.com/talafek96/claude-local.git
cd claude-local
bash install.sh http://localhost:8000 my-model
```

The installer will:
1. Check for (or install) the `claude` CLI
2. Write your config to `~/.config/claude-local/config.env`
3. Add a single source line to your `.bashrc` / `.zshrc`
4. Enable local routing by default

Then open a new terminal, or:
```bash
source claude-local.sh
```

## Usage

```bash
# Check current routing
claude-local status

# Use claude (routed to local vLLM)
claude

# Switch to Anthropic cloud
claude-local off
claude          # now uses Anthropic servers

# Switch back to local
claude-local on

# Reconfigure endpoint or model
claude-local config http://192.168.200.10:8000 qwen3-8b

# Edit config directly
claude-local edit
```

## How it works

`claude-local.sh` defines a shell function `claude()` that shadows the real binary. On every invocation it checks `~/.config/claude-local/enabled`:

- **File exists:** reads `config.env`, passes the env vars to `claude` via `env(1)`. The variables are scoped to the claude process only -- nothing leaks into your shell.
- **File absent:** calls the real `claude` binary directly, no modifications.

The toggle (`claude-local on/off`) simply creates or removes that file. Because the check happens at invocation time (not at shell startup), flipping the switch in one terminal takes effect everywhere immediately.

### Environment variables used

| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_BASE_URL` | Points Claude Code at your vLLM server |
| `ANTHROPIC_API_KEY` | Dummy value (vLLM doesn't need auth) |
| `ANTHROPIC_AUTH_TOKEN` | Required by Claude Code, any value works |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | Model name for Opus-tier requests |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | Model name for Sonnet-tier requests |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Model name for Haiku-tier requests |

## vLLM setup

vLLM 0.17+ natively implements the Anthropic Messages API. Start it with tool calling enabled:

```bash
vllm serve your-model \
  --served-model-name my-model \
  --host 0.0.0.0 --port 8000 \
  --max-model-len 131072 \
  --enable-auto-tool-choice \
  --tool-call-parser hermes
```

Then configure claude-local to point at it:

```bash
claude-local config http://localhost:8000 my-model
claude-local on
claude
```

### Important notes

- **Tool calling is required.** Claude Code uses tools (file editing, bash, etc.) extensively. You must pass `--enable-auto-tool-choice --tool-call-parser <parser>` when starting vLLM. Without these, Claude Code will fail with a `400 BadRequestError`.
- **Context length matters.** Claude Code's system prompt is ~9K tokens and it requests up to 32K output tokens. Set `--max-model-len` high enough to accommodate both (at least 42K, ideally 131K). If the model's native context is shorter, use `VLLM_ALLOW_LONG_MAX_MODEL_LEN=1`.
- **Tool call parser depends on model.** Qwen3 models use `hermes`. Check [vLLM tool calling docs](https://docs.vllm.ai/en/stable/features/tool_calling.html) for other architectures.

## Uninstall

```bash
bash uninstall.sh
```

Removes shell integration and config. Does not uninstall the `claude` CLI itself.

## Requirements

- Node.js (for the `claude` CLI)
- A running vLLM server with Anthropic Messages API support (vLLM 0.17+)
- bash or zsh
