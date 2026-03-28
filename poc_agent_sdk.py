# /// script
# requires-python = ">=3.10"
# dependencies = ["claude-agent-sdk"]
# ///
"""
POC: Use the Claude Agent SDK with a local vLLM server.

The SDK wraps the `claude` CLI, giving you programmatic access to
Claude Code's full toolset (Read, Write, Edit, Bash, etc.) — but
routed to your own vLLM instance instead of Anthropic's cloud.

Usage:
    # Make sure your vLLM server is running with tool calling enabled,
    # then adjust VLLM_URL and MODEL below, and run:
    uv run poc_agent_sdk.py

    # Or with a custom endpoint:
    VLLM_URL=http://192.168.200.10:8000 MODEL=my-model uv run poc_agent_sdk.py
"""

import os
import anyio
from claude_agent_sdk import (
    query,
    ClaudeAgentOptions,
    AssistantMessage,
    ResultMessage,
    TextBlock,
    ToolUseBlock,
)

# ---------------------------------------------------------------------------
# Configuration — override with env vars or edit directly
# ---------------------------------------------------------------------------
VLLM_URL = os.environ.get("VLLM_URL", "http://localhost:8002")
MODEL = os.environ.get("MODEL", "qwen3-8b")

VLLM_ENV = {
    "ANTHROPIC_BASE_URL": VLLM_URL,
    "ANTHROPIC_API_KEY": "local",
    "ANTHROPIC_AUTH_TOKEN": "local",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": MODEL,
    "ANTHROPIC_DEFAULT_SONNET_MODEL": MODEL,
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": MODEL,
    "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
}


def print_message(msg):
    """Pretty-print a single SDK message."""
    if isinstance(msg, AssistantMessage):
        for block in msg.content:
            if isinstance(block, TextBlock):
                print(f"[assistant] {block.text}")
            elif isinstance(block, ToolUseBlock):
                print(f"[tool_use]  {block.name}({block.input})")
    elif isinstance(msg, ResultMessage):
        if msg.result:
            print(f"[result] {msg.result[:300]}")
        if msg.is_error:
            print(f"[error] {msg.errors}")
    else:
        print(f"[{type(msg).__name__}] {msg}")


async def demo_simple_query():
    """Basic one-shot query — no tools, just text."""
    print("=" * 60)
    print("Demo 1: Simple query")
    print("=" * 60)

    options = ClaudeAgentOptions(
        env=VLLM_ENV,
        max_turns=1,
        permission_mode="acceptEdits",
    )

    async for msg in query(prompt="What is 2+2? Reply with just the number.", options=options):
        print_message(msg)
    print()


async def demo_tool_use():
    """Query that triggers tool use (Bash)."""
    print("=" * 60)
    print("Demo 2: Tool use (Bash)")
    print("=" * 60)

    options = ClaudeAgentOptions(
        env=VLLM_ENV,
        max_turns=3,
        allowed_tools=["Bash"],
        permission_mode="acceptEdits",
        cwd="/tmp",
    )

    async for msg in query(
        prompt="Use bash to list the files in /tmp. Show me the output.",
        options=options,
    ):
        print_message(msg)
    print()


async def demo_file_creation():
    """Query that creates a file and reads it back."""
    print("=" * 60)
    print("Demo 3: File creation (Write + Read)")
    print("=" * 60)

    options = ClaudeAgentOptions(
        env=VLLM_ENV,
        max_turns=5,
        allowed_tools=["Write", "Read", "Bash"],
        permission_mode="acceptEdits",
        cwd="/tmp",
    )

    async for msg in query(
        prompt=(
            "Create a file /tmp/hello_from_sdk.txt containing 'Hello from the Claude Agent SDK "
            "running on local vLLM!', then read it back and show me the contents."
        ),
        options=options,
    ):
        print_message(msg)
    print()


async def main():
    print(f"vLLM endpoint: {VLLM_URL}")
    print(f"Model:         {MODEL}")
    print()

    await demo_simple_query()
    await demo_tool_use()
    await demo_file_creation()


if __name__ == "__main__":
    anyio.run(main)
