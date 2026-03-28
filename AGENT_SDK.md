# Using the Claude Agent SDK with a Local vLLM Server

This document explains how to use the [Claude Agent SDK](https://github.com/anthropics/claude-agent-sdk-python) (`claude-agent-sdk`) to run Claude Code programmatically against a local vLLM server. It is written for both humans and AI agents.

## What the SDK is

The Claude Agent SDK is a Python wrapper around the `claude` CLI. It spawns `claude` as a subprocess with `--print --output-format stream-json`, then yields structured Python objects (messages, tool calls, results) back to your code.

Because it uses the CLI under the hood, routing works the same way as the shell: set environment variables → the CLI sends requests to your vLLM instead of Anthropic.

## Prerequisites

- Python 3.10+
- A running vLLM server with **tool calling enabled** (see [README.md](README.md#vllm-server-requirements))
- The `claude` CLI installed (`npm install -g @anthropic-ai/claude-code`), or let the SDK use its bundled copy

## Install

```bash
uv add claude-agent-sdk
# or in a script with PEP 723 inline metadata:
# dependencies = ["claude-agent-sdk"]
```

## Core concept: the `env` dict

`ClaudeAgentOptions` accepts an `env` parameter — a `dict[str, str]` of environment variables passed to the `claude` subprocess. This is how you route to vLLM:

```python
VLLM_ENV = {
    "ANTHROPIC_BASE_URL": "http://localhost:8000",
    "ANTHROPIC_API_KEY": "local",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "qwen3-8b",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "qwen3-8b",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "qwen3-8b",
    "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
}
```

Do **not** set `ANTHROPIC_AUTH_TOKEN` alongside `ANTHROPIC_API_KEY` — having both causes an auth conflict warning.

To use different models per tier (e.g. a large model for opus, a fast model for haiku), set each key to a different `--served-model-name` from your vLLM instance.

## API: `query()` — one-shot tasks

`query()` is an async generator that yields messages. It starts a new session, runs until completion or `max_turns`, then exits.

```python
import anyio
from claude_agent_sdk import query, ClaudeAgentOptions

async def main():
    options = ClaudeAgentOptions(
        env=VLLM_ENV,
        max_turns=1,
    )
    async for msg in query(prompt="What is 2+2?", options=options):
        print(msg)

anyio.run(main)
```

## API: `ClaudeSDKClient` — multi-turn sessions

For interactive or multi-turn use, use the client directly:

```python
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

async def main():
    options = ClaudeAgentOptions(
        env=VLLM_ENV,
        max_turns=10,
        allowed_tools=["Bash", "Read", "Write", "Edit"],
        permission_mode="acceptEdits",
        cwd="/path/to/project",
    )
    async with ClaudeSDKClient(options=options) as client:
        await client.query("Read main.py and explain what it does")
        async for msg in client.receive_response():
            print(msg)

        await client.query("Add error handling to the parse function")
        async for msg in client.receive_response():
            print(msg)

anyio.run(main)
```

## Message types

The SDK yields these message types:

```python
from claude_agent_sdk import (
    AssistantMessage,   # Model output (text and/or tool calls)
    UserMessage,        # Tool results fed back to the model
    SystemMessage,      # Session init metadata (tools list, model, session_id)
    ResultMessage,      # Final result when the session ends
    TextBlock,          # Text content inside AssistantMessage.content
    ToolUseBlock,       # Tool call inside AssistantMessage.content
)
```

Handling them:

```python
def handle(msg):
    if isinstance(msg, AssistantMessage):
        for block in msg.content:
            if isinstance(block, TextBlock):
                print(block.text)
            elif isinstance(block, ToolUseBlock):
                print(f"Tool: {block.name}({block.input})")
    elif isinstance(msg, ResultMessage):
        print(f"Done: {msg.result}")
        if msg.is_error:
            print(f"Errors: {msg.errors}")
```

## Available tools

When routed to vLLM, the SDK exposes the full Claude Code toolset. The `SystemMessage` at session start lists them all. Common ones:

- **Bash** — run shell commands
- **Read** — read file contents
- **Write** — create/overwrite a file
- **Edit** — surgical string replacement in a file
- **Glob** — find files by pattern
- **Grep** — search file contents
- **WebFetch** — fetch a URL
- **TodoWrite** — manage a task list
- **Task** — spawn a subagent

## Controlling permissions

`allowed_tools` is a whitelist of tools that run without prompting. `permission_mode` controls the default for unlisted tools:

```python
options = ClaudeAgentOptions(
    env=VLLM_ENV,
    allowed_tools=["Bash", "Read", "Write", "Edit", "Glob", "Grep"],
    permission_mode="acceptEdits",  # auto-accept file edits
)
```

To block specific tools:

```python
options = ClaudeAgentOptions(
    env=VLLM_ENV,
    disallowed_tools=["WebFetch", "WebSearch"],
)
```

## Custom tools (in-process MCP)

You can define Python functions as tools that the model can call, without running a separate MCP server process:

```python
from claude_agent_sdk import tool, create_sdk_mcp_server, ClaudeAgentOptions, ClaudeSDKClient

@tool("lookup_user", "Look up a user by ID", {"user_id": int})
async def lookup_user(args):
    user_id = args["user_id"]
    # your logic here
    return {"content": [{"type": "text", "text": f"User {user_id}: Alice"}]}

server = create_sdk_mcp_server(name="my-tools", version="1.0.0", tools=[lookup_user])

options = ClaudeAgentOptions(
    env=VLLM_ENV,
    mcp_servers={"my-tools": server},
    allowed_tools=["mcp__my-tools__lookup_user"],
)
```

## Hooks: intercepting the agent loop

Hooks let you inject logic at specific points — before/after tool use, on each assistant message, etc.

```python
from claude_agent_sdk import ClaudeAgentOptions, ClaudeSDKClient, HookMatcher

async def block_rm(input_data, tool_use_id, context):
    if input_data["tool_name"] == "Bash":
        cmd = input_data["tool_input"].get("command", "")
        if "rm -rf" in cmd:
            return {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": "rm -rf is blocked",
                }
            }
    return {}

options = ClaudeAgentOptions(
    env=VLLM_ENV,
    hooks={"PreToolUse": [HookMatcher(matcher="Bash", hooks=[block_rm])]},
)
```

## Key `ClaudeAgentOptions` fields

| Field | Type | What it does |
|-------|------|-------------|
| `env` | `dict[str, str]` | Env vars for the claude subprocess. This is how you route to vLLM. |
| `max_turns` | `int` | Max agent loop iterations before stopping. |
| `allowed_tools` | `list[str]` | Tools that run without permission prompts. |
| `disallowed_tools` | `list[str]` | Tools the model cannot use at all. |
| `permission_mode` | `str` | `"default"`, `"acceptEdits"`, or `"bypassPermissions"`. |
| `cwd` | `str` | Working directory for the session. |
| `system_prompt` | `str` | Override or extend the system prompt. |
| `model` | `str` | Model alias (`"sonnet"`, `"opus"`, `"haiku"`). |
| `mcp_servers` | `dict` | MCP servers (external or in-process SDK servers). |
| `hooks` | `dict` | Hook functions keyed by event name. |
| `max_budget_usd` | `float` | Spending cap (only meaningful with Anthropic cloud). |
| `cli_path` | `str` | Path to a specific `claude` binary. |
| `effort` | `str` | `"low"`, `"medium"`, `"high"`, `"max"`. |

## Complete working example

See [`poc_agent_sdk.py`](poc_agent_sdk.py) for a tested script that runs three demos (simple query, Bash tool use, file Write+Read) against a local vLLM server.

```bash
# Run with defaults (localhost:8002, qwen3-8b)
uv run poc_agent_sdk.py

# Override endpoint and model
VLLM_URL=http://192.168.200.10:8000 MODEL=my-model uv run poc_agent_sdk.py
```

## Pitfalls

- **Do not set both `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN`** in the `env` dict. Use only `ANTHROPIC_API_KEY`. Having both causes Claude Code to emit a warning and potentially misbehave.
- **vLLM must have `--enable-auto-tool-choice --tool-call-parser hermes`** (or the correct parser for your model). Without this, any tool call from Claude Code returns a 400 error.
- **`--max-model-len` must be at least 42K.** Claude Code's system prompt is ~9K tokens and it requests 32K output tokens. If the model's native context is shorter, set `VLLM_ALLOW_LONG_MAX_MODEL_LEN=1` when starting vLLM.
- **`query()` is async.** You need `anyio.run()` or an async context to use it.
- **The SDK spawns the `claude` CLI as a subprocess.** Shell functions (like the `claude()` wrapper from `claude-local.sh`) are not visible to it. Always use the `env` dict for programmatic routing.
