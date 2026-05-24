#!/usr/bin/env python3
"""
recipes/observability/02_phoenix_trace_dspy.py
==============================================

Instrument a DSPy program with Arize Phoenix using OpenInference. Phoenix is
the right answer on `lite` profiles: it runs in-process (no Docker, no
Postgres), persists to SQLite under ~/.phoenix, and the UI is one click away
via `aurum-launch-phoenix`.

DSPy ("declarative self-improving Python") is HF's prompt-programming library.
We use a trivial Predict module — the point is to show the trace, not the LM.

Prereqs:
    aurum-launch-phoenix    # opens http://localhost:6007 in Falkon
    # In another shell or after closing the browser, run this script.

Run:
    python recipes/observability/02_phoenix_trace_dspy.py

Output:
    Spans appear in the Phoenix UI Spans tab. Each `Predict` call becomes a
    parent span with the prompt as input attribute and the completion as
    output, plus the underlying LM call as a child span with token counts.
"""

from __future__ import annotations

import os
import sys

# --- 1. Start (or attach to) the Phoenix session ----------------------------
# `phoenix.launch_app()` is idempotent — if a server is already running on
# port 6007 (e.g. because the user ran aurum-launch-phoenix first), it
# reuses it instead of throwing. We catch the exception just in case.
import phoenix as px

try:
    session = px.launch_app(port=int(os.getenv("PHOENIX_PORT", "6007")))
    print(f"[recipe] phoenix UI: {session.url}")
except Exception as e:
    print(f"[recipe] reusing existing phoenix instance ({e})")

# --- 2. Register the OpenInference auto-instrumentor for DSPy ---------------
# This monkey-patches dspy.Predict (and friends) to emit OTel spans on every
# call. The spans go to Phoenix's OTLP collector on :6006 automatically — we
# don't need to wire up exporters by hand.
from openinference.instrumentation.dspy import DSPyInstrumentor
DSPyInstrumentor().instrument()

# --- 3. Build and run a DSPy program ----------------------------------------
try:
    import dspy
except ImportError:
    sys.stderr.write(
        "[recipe] dspy not installed — install with:\n"
        "    pip install --break-system-packages dspy-ai\n"
        "DSPy isn't in the observability requirements file because it pulls "
        "heavier transitive deps; users who want this recipe install it ad-hoc.\n"
    )
    sys.exit(0)  # graceful no-op so CI doesn't red-fail this recipe

# Configure DSPy to talk to the AurumOS LiteLLM proxy. DSPy's `dspy.LM`
# accepts an OpenAI-compatible base URL.
lm = dspy.LM(
    model=os.getenv("AURUM_RECIPE_MODEL", "openai/ollama/qwen2.5-coder:1.5b"),
    api_base=os.getenv("LITELLM_BASE", "http://localhost:4000"),
    api_key="sk-anything",  # LiteLLM proxy ignores keys by default
    cache=False,
)
dspy.configure(lm=lm)

class TersePredict(dspy.Signature):
    """Answer a question in fewer than 20 words."""
    question = dspy.InputField()
    answer = dspy.OutputField()

predict = dspy.Predict(TersePredict)
result = predict(question="Why is the sky blue?")
print("answer:", result.answer)
print("\n[recipe] check the spans at http://localhost:6007 → Spans tab.")
