#!/usr/bin/env python3
"""
recipes/observability/01_langfuse_trace_litellm.py
==================================================

Instrument every LiteLLM call with Langfuse so prompts, completions, model,
latency, token counts and cost land in the local Langfuse UI at
http://localhost:3030 (or cloud.langfuse.com if you exported LANGFUSE_HOST).

Why LiteLLM? It's the AurumOS Wave 8 proxy on :4000 — every LLM call in the
distro flows through it, so instrumenting LiteLLM gives you one-stop coverage
of every model your scripts touch (Ollama local, OpenAI, Anthropic, …).

Setup (one-time):
    # Open Langfuse: aurum-launch-langfuse
    # In the UI → Settings → API Keys → create a pair, then:
    export LANGFUSE_PUBLIC_KEY=pk-lf-...
    export LANGFUSE_SECRET_KEY=sk-lf-...
    export LANGFUSE_HOST=http://localhost:3030

Run:
    python recipes/observability/01_langfuse_trace_litellm.py

Output:
    A trace appears in the Langfuse UI under the "aurum-recipe" project.
    Click into it to see the prompt, completion, latency and token usage.
"""

from __future__ import annotations

import os
import sys

# --- 1. Wire LiteLLM into Langfuse -------------------------------------------
# LiteLLM has first-class Langfuse integration: assign "langfuse" to its
# `success_callback` (and `failure_callback`) list, and every completion is
# auto-traced. No manual span creation needed.
import litellm

litellm.success_callback = ["langfuse"]
litellm.failure_callback = ["langfuse"]

# Optional: assert the env vars exist so we don't silently send zero traces
# because the user forgot the export step.
for var in ("LANGFUSE_PUBLIC_KEY", "LANGFUSE_SECRET_KEY"):
    if not os.getenv(var):
        sys.stderr.write(
            f"[recipe] WARNING: {var} not set — traces will not reach Langfuse. "
            "See the docstring for setup.\n"
        )

# --- 2. Make a call through the AurumOS LiteLLM proxy ------------------------
# AurumOS Wave 8 (Agent B) runs LiteLLM as a proxy on http://localhost:4000.
# We point at it with `api_base=` and use a model name the proxy knows about
# (ollama/qwen2.5-coder:7b on `standard`; ollama/qwen2.5-coder:1.5b on `lite`).
LITELLM_BASE = os.getenv("LITELLM_BASE", "http://localhost:4000")
MODEL = os.getenv("AURUM_RECIPE_MODEL", "ollama/qwen2.5-coder:1.5b")

response = litellm.completion(
    model=MODEL,
    api_base=LITELLM_BASE,
    messages=[
        {"role": "system", "content": "You are a terse, helpful coding assistant."},
        {"role": "user", "content": "Write a Python one-liner that reverses a string."},
    ],
    # Add metadata that Langfuse will surface as filterable tags in the UI —
    # makes it easy to slice traces by experiment / commit hash / user.
    metadata={
        "trace_name": "aurum-recipe-langfuse-litellm",
        "tags": ["aurum-recipes", "wave8", "agent-e"],
    },
)

print(response.choices[0].message.content)
print("\n[recipe] check the trace at http://localhost:3030 → Traces tab.")
