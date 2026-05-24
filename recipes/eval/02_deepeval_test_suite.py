#!/usr/bin/env python3
"""
recipes/eval/02_deepeval_test_suite.py
======================================

A pytest-style DeepEval test suite. DeepEval treats LLM outputs like ordinary
unit tests — each metric is an `assert` you can wire into CI.

Run:
    pytest recipes/eval/02_deepeval_test_suite.py
    # or via the unified CLI (uses `deepeval test run` if available):
    aurum-eval deepeval recipes/eval/02_deepeval_test_suite.py

Metrics demonstrated:
  * AnswerRelevancyMetric — does the answer address the prompt?
  * HallucinationMetric   — does the answer contradict the source context?
  * GEval (custom)        — bring-your-own judge prompt for project-specific
                            quality bars (here: "concise enough to fit in a
                            Slack message").

Tests are written to PASS on a well-behaved LLM and FAIL on common failure
modes. That makes this file double as a smoke test for the eval stack itself.
"""

from __future__ import annotations

import os
import pytest

# Route DeepEval's judge LLM through the AurumOS LiteLLM proxy so we don't
# require an OpenAI key. DeepEval honours OPENAI_API_BASE + OPENAI_API_KEY
# env vars when its OpenAI provider is active; LiteLLM proxy is wire-compatible.
os.environ.setdefault("OPENAI_API_BASE", os.getenv("LITELLM_BASE", "http://localhost:4000"))
os.environ.setdefault("OPENAI_API_KEY", "sk-anything")  # LiteLLM ignores

# DeepEval's import surface moved a couple of times in the 1.x → 1.5 window.
# Wrap the imports so a missing class triggers a `pytest.skip` instead of a
# hard collection error.
try:
    from deepeval import assert_test
    from deepeval.test_case import LLMTestCase
    from deepeval.metrics import AnswerRelevancyMetric, HallucinationMetric, GEval
    from deepeval.metrics.g_eval import LLMTestCaseParams
except ImportError as e:
    pytest.skip(f"deepeval missing required symbols: {e}", allow_module_level=True)


# ── Test 1: answer relevancy ──────────────────────────────────────────────────
def test_answer_relevancy_for_simple_qa():
    """The model's answer should clearly address the user's question."""
    case = LLMTestCase(
        input="What is the capital of France?",
        actual_output="Paris is the capital of France.",
        # `context` is the ground-truth source for the metric to compare against;
        # `retrieval_context` is what your RAG actually pulled. Here they match.
        context=["France is a country in Western Europe. Its capital is Paris."],
        retrieval_context=["France is a country in Western Europe. Its capital is Paris."],
    )
    # threshold=0.7 is DeepEval's recommended floor for production answers.
    assert_test(case, [AnswerRelevancyMetric(threshold=0.7)])


# ── Test 2: hallucination ─────────────────────────────────────────────────────
def test_no_hallucination_when_answer_grounded():
    """If the answer is fully supported by context, the hallucination metric
    should score it as non-hallucinated (score below the configured threshold,
    which DeepEval inverts: lower = better for hallucination)."""
    case = LLMTestCase(
        input="When was the Eiffel Tower completed?",
        actual_output="The Eiffel Tower was completed in 1889.",
        context=[
            "The Eiffel Tower was constructed from 1887 to 1889 as the entrance "
            "to the 1889 World's Fair in Paris."
        ],
    )
    # HallucinationMetric: threshold is the MAX score we'll tolerate.
    assert_test(case, [HallucinationMetric(threshold=0.3)])


# ── Test 3: custom GEval criterion ───────────────────────────────────────────
def test_answer_is_concise_enough_for_chat():
    """A custom rubric the upstream metrics don't cover: 'concise enough that
    the answer fits in a single Slack message' (i.e. < ~40 words). We express
    that as a GEval judge prompt — GEval prompts the judge LLM with this
    rubric and parses a score back."""
    metric = GEval(
        name="Conciseness",
        criteria="Determine whether the actual output is concise enough to fit "
                 "in a single Slack message (under 40 words) while still "
                 "answering the question completely.",
        evaluation_params=[LLMTestCaseParams.INPUT, LLMTestCaseParams.ACTUAL_OUTPUT],
        threshold=0.7,
    )
    case = LLMTestCase(
        input="What is photosynthesis?",
        actual_output="Photosynthesis is how plants turn sunlight, water, and "
                      "CO2 into glucose and oxygen.",
    )
    assert_test(case, [metric])
