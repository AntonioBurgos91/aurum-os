#!/usr/bin/env python3
# PROFILE: lite | standard | pro | workstation
# REQUIREMENTS: 4 GB RAM (driver only; model runs in Ollama)
# MODEL: ollama/qwen2.5:7b (override with $AURUM_MODEL)
#
# DSPy "hello world": declare a Signature, hand it to a Predict module, then
# optimise it with BootstrapFewShot on a 3-example toy dataset. The point is
# to show the *declarative* style - you never write a prompt string. DSPy
# compiles one for you and (once optimised) memoises few-shot exemplars.
"""DSPy simple QA — declarative single-turn question answering."""

from __future__ import annotations

import os

import dspy
from dspy.teleprompt import BootstrapFewShot

# --- LM wiring ------------------------------------------------------------
# DSPy 2.5 standardised on `dspy.LM`, which is a thin wrapper around LiteLLM.
# That means any model string LiteLLM understands works here, including
# `ollama/<tag>` (local) and `openai/gpt-4o-mini` (remote).
MODEL = os.environ.get("AURUM_MODEL", "ollama/qwen2.5:7b")
OLLAMA_BASE = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")

lm = dspy.LM(model=MODEL, api_base=OLLAMA_BASE, max_tokens=256, temperature=0.0)
dspy.configure(lm=lm)


# --- Signature ------------------------------------------------------------
class BasicQA(dspy.Signature):
    """Answer the user's question in one short sentence."""

    question: str = dspy.InputField()
    answer: str = dspy.OutputField(desc="one sentence, factual")


# --- Tiny training set used by BootstrapFewShot ---------------------------
TRAINSET = [
    dspy.Example(question="What is the capital of France?",
                 answer="Paris is the capital of France.").with_inputs("question"),
    dspy.Example(question="Who wrote the play Hamlet?",
                 answer="William Shakespeare wrote Hamlet.").with_inputs("question"),
    dspy.Example(question="What gas do plants absorb from the air?",
                 answer="Plants absorb carbon dioxide from the air.").with_inputs("question"),
]


def _exact_match(example: dspy.Example, pred, trace=None) -> bool:
    """Crude metric: did the gold key phrase end up in the prediction?"""
    gold = example.answer.lower().split(".")[0]  # first clause
    return gold[:20] in (pred.answer or "").lower()


def build_program() -> dspy.Module:
    """Return an *optimised* Predict module."""
    base = dspy.Predict(BasicQA)
    optimiser = BootstrapFewShot(metric=_exact_match, max_bootstrapped_demos=2)
    return optimiser.compile(student=base, trainset=TRAINSET)


def main() -> None:
    program = build_program()
    question = "What language is spoken in Brazil?"
    print(f"Q: {question}")
    print(f"A: {program(question=question).answer}")


if __name__ == "__main__":
    main()
