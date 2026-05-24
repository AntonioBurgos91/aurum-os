#!/usr/bin/env python3
"""
recipes/eval/01_ragas_rag_eval.py
=================================

Evaluate a tiny RAG pipeline with Ragas. We use a 3-row synthetic dataset so
the recipe runs end-to-end in ~30 seconds on CPU. Swap the dataset for your
own to evaluate a real corpus.

Ragas metrics computed:
  * faithfulness        — does the answer stay grounded in the retrieved ctx?
  * answer_relevancy    — does the answer address the question?
  * context_precision   — is the retrieved ctx actually relevant?
  * context_recall      — does the ctx cover what the ground truth claims?

Run:
    python recipes/eval/01_ragas_rag_eval.py
    # or via the unified CLI:
    aurum-eval ragas <(python recipes/eval/01_ragas_rag_eval.py --dump-json)
"""

from __future__ import annotations

import json
import os
import sys

# --- 1. Build a tiny ground-truth dataset ------------------------------------
# Real-world: pull this from your evaluation suite or a labelled subset of
# production traffic exported from Langfuse.
SAMPLES = [
    {
        "question": "Who wrote 'Pride and Prejudice'?",
        "answer": "Jane Austen wrote Pride and Prejudice, published in 1813.",
        "contexts": [
            "Pride and Prejudice is an 1813 novel of manners by Jane Austen.",
            "Jane Austen (1775-1817) was an English novelist.",
        ],
        "ground_truth": "Jane Austen wrote Pride and Prejudice.",
    },
    {
        "question": "What is the boiling point of water at sea level?",
        "answer": "Water boils at 100 degrees Celsius at sea level.",
        "contexts": [
            "At standard atmospheric pressure (1 atm), water boils at 100 °C.",
        ],
        "ground_truth": "100 degrees Celsius (212 °F) at 1 atmosphere.",
    },
    {
        "question": "What is the capital of Australia?",
        "answer": "Sydney is the capital of Australia.",  # deliberately wrong
        "contexts": [
            "Canberra is the capital city of Australia.",
            "Sydney is the largest city in Australia.",
        ],
        "ground_truth": "Canberra is the capital of Australia.",
    },
]

# Allow the recipe to dump the dataset as JSON so it can be piped into
# `aurum-eval ragas /dev/stdin` for a CLI-driven workflow.
if "--dump-json" in sys.argv:
    for row in SAMPLES:
        print(json.dumps(row))
    sys.exit(0)

# --- 2. Convert to HF Datasets ----------------------------------------------
from datasets import Dataset
ds = Dataset.from_list(SAMPLES)

# --- 3. Run Ragas ------------------------------------------------------------
# Ragas uses an LLM as a judge under the hood. By default it tries the OpenAI
# API. For air-gapped / local-only AurumOS users, point it at the LiteLLM
# proxy (which routes to Ollama). Ragas 0.2+ accepts a langchain-style chat
# model object — we use ChatLiteLLM as the bridge.
try:
    from langchain_community.chat_models import ChatLiteLLM
    judge_llm = ChatLiteLLM(
        model=os.getenv("AURUM_RECIPE_MODEL", "ollama/qwen2.5-coder:1.5b"),
        api_base=os.getenv("LITELLM_BASE", "http://localhost:4000"),
        temperature=0.0,
    )
    judge_kwargs = {"llm": judge_llm}
except ImportError:
    # Fall back to whatever Ragas's default judge picks up. If the user has
    # OPENAI_API_KEY set it works; otherwise Ragas raises a clear error.
    judge_kwargs = {}

from ragas import evaluate
from ragas.metrics import (
    faithfulness,
    answer_relevancy,
    context_precision,
    context_recall,
)

result = evaluate(
    ds,
    metrics=[faithfulness, answer_relevancy, context_precision, context_recall],
    **judge_kwargs,
)
print(result)
# The third sample's wrong-answer should drive faithfulness + context_recall
# down — a useful smoke-test for users who want to verify Ragas is working.
