#!/usr/bin/env python3
# PROFILE: lite | standard | pro | workstation
# REQUIREMENTS: 4 GB RAM driver; retriever is stubbed - swap in a real index
# MODEL: ollama/qwen2.5:7b (override with $AURUM_MODEL)
#
# RAG pipeline implemented as a *composable* DSPy module. The retriever is a
# stub (in-memory passages + a ColBERTv2 hook commented out) so the recipe
# runs with zero external services. To go live, point `dspy.ColBERTv2(url=...)`
# at a hosted index or swap in a Qdrant / Chroma client behind the same
# `dspy.Retrieve(...)` interface.
"""DSPy RAG pipeline: retrieve -> reason -> answer."""

from __future__ import annotations

import os

import dspy

MODEL = os.environ.get("AURUM_MODEL", "ollama/qwen2.5:7b")
OLLAMA_BASE = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")

lm = dspy.LM(model=MODEL, api_base=OLLAMA_BASE, max_tokens=512, temperature=0.0)
dspy.configure(lm=lm)


# --- Retriever stub --------------------------------------------------------
# Production: `rm = dspy.ColBERTv2(url='http://your-colbert:8080/api/search')`
# Or `dspy.QdrantRM(collection_name=..., qdrant_client=...)` if you index
# locally. Here we ship a tiny in-memory list so the recipe is self-contained.
CORPUS = [
    "DSPy is a framework from Stanford NLP for declarative prompt programs.",
    "DSPy 2.5 replaced the old Module/Signature API with a cleaner typed one.",
    "DSPy compiles natural-language Signatures into optimised LM calls.",
    "BootstrapFewShot picks few-shot exemplars from a training set automatically.",
    "DSPy works with any LiteLLM-compatible model, including Ollama locally.",
]


class StubRetriever(dspy.Retrieve):
    """Trivial keyword retriever for the recipe; replace with a real backend."""

    def __init__(self, corpus: list[str], k: int = 3) -> None:
        super().__init__(k=k)
        self.corpus = corpus

    def forward(self, query: str, k: int | None = None) -> dspy.Prediction:
        k = k or self.k
        terms = {t.lower() for t in query.split() if len(t) > 3}
        ranked = sorted(
            self.corpus,
            key=lambda p: -sum(1 for t in terms if t in p.lower()),
        )
        return dspy.Prediction(passages=ranked[:k])


dspy.configure(rm=StubRetriever(CORPUS, k=3))


# --- RAG module ------------------------------------------------------------
class AnswerWithContext(dspy.Signature):
    """Answer the question using ONLY the supplied context. Be concise."""

    context: list[str] = dspy.InputField(desc="retrieved passages")
    question: str = dspy.InputField()
    answer: str = dspy.OutputField()


class RAG(dspy.Module):
    """Retrieve-then-generate pipeline."""

    def __init__(self, k: int = 3) -> None:
        super().__init__()
        self.retrieve = dspy.Retrieve(k=k)
        self.generate = dspy.ChainOfThought(AnswerWithContext)

    def forward(self, question: str) -> dspy.Prediction:
        ctx = self.retrieve(question).passages
        return self.generate(context=ctx, question=question)


def main() -> None:
    rag = RAG(k=3)
    q = "What does DSPy 2.5 change about the API?"
    out = rag(question=q)
    print(f"Q: {q}")
    print(f"A: {out.answer}")


if __name__ == "__main__":
    main()
