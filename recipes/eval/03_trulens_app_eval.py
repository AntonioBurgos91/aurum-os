#!/usr/bin/env python3
"""
recipes/eval/03_trulens_app_eval.py
===================================

Wrap a tiny RAG-style function with TruLens feedback functions. TruLens
records every invocation to ~/.trulens/default.sqlite and computes feedback
scores (relevance, groundedness, etc.) asynchronously — open the dashboard
with `tru.run_dashboard()` to inspect results.

Run:
    python recipes/eval/03_trulens_app_eval.py
    # or:
    aurum-eval trulens recipes/eval/03_trulens_app_eval.py

Output:
    A streamlit dashboard URL is printed at the end. Open it to browse
    every invocation, its feedback scores, and the prompt/response trail.
"""

from __future__ import annotations

import os
import sys

# --- 1. Initialise TruLens ---------------------------------------------------
# `Tru` (alias `TruSession` in 1.x) is the global tracker. By default it uses
# a SQLite DB at ~/.trulens/default.sqlite — perfect for single-user local dev.
try:
    from trulens.core import TruSession
    tru = TruSession()
except ImportError:
    sys.stderr.write(
        "[recipe] trulens.core not importable. Ensure 'trulens>=1.0' is "
        "installed (it's in pip-requirements-observability.txt).\n"
    )
    sys.exit(1)

# Optional: nuke previous runs so the dashboard shows only this run's data.
# Comment out to accumulate history across invocations.
tru.reset_database()

# --- 2. Define the app being evaluated ---------------------------------------
# We mimic a 2-step RAG pipeline: retrieve, then generate. Both functions are
# plain Python — TruLens instruments them via the `@instrument` decorator.
from trulens.apps.custom import instrument, TruCustomApp

class TinyRAG:
    """A pretend RAG app over a 2-doc 'corpus'."""

    CORPUS = {
        "doc1": "Paris is the capital of France. It is known for the Eiffel Tower.",
        "doc2": "Berlin is the capital of Germany. It is known for the Brandenburg Gate.",
    }

    @instrument
    def retrieve(self, query: str) -> list[str]:
        """Return docs that mention any word of the query (toy BM25)."""
        q_words = {w.lower().strip("?.,") for w in query.split()}
        return [
            text for text in self.CORPUS.values()
            if any(w in text.lower() for w in q_words)
        ]

    @instrument
    def query(self, q: str) -> str:
        docs = self.retrieve(q)
        joined = " ".join(docs) if docs else "[no docs retrieved]"
        # Toy "generation": return the first sentence of the joined context.
        return joined.split(". ")[0] + "."

app = TinyRAG()

# --- 3. Define feedback functions -------------------------------------------
# Feedback functions are graded by a judge LLM. We use the LiteLLM proxy
# (Wave 8 Agent B) so the recipe runs without an OpenAI key.
try:
    from trulens.providers.litellm import LiteLLM
    from trulens.core import Feedback, Select
except ImportError as e:
    sys.stderr.write(f"[recipe] trulens providers/core not available: {e}\n")
    sys.exit(0)

provider = LiteLLM(
    model_engine=os.getenv("AURUM_RECIPE_MODEL", "ollama/qwen2.5-coder:1.5b"),
    api_base=os.getenv("LITELLM_BASE", "http://localhost:4000"),
)

# `relevance`: does the final answer address the input question?
f_relevance = (
    Feedback(provider.relevance, name="answer_relevance")
    .on_input_output()  # binds to (main_input, main_output) automatically
)
# `context_relevance`: how relevant are the retrieved docs to the query?
# We bind it to the output of `retrieve()` via Select traversal.
f_context_relevance = (
    Feedback(provider.context_relevance, name="context_relevance")
    .on_input()
    .on(Select.RecordCalls.retrieve.rets[:])  # each retrieved doc
    .aggregate(lambda scores: sum(scores) / len(scores) if scores else 0.0)
)

# --- 4. Wrap the app and run a handful of queries ---------------------------
tru_app = TruCustomApp(
    app,
    app_name="aurum-tinyrag",
    app_version="0.1",
    feedbacks=[f_relevance, f_context_relevance],
)

QUESTIONS = [
    "What is the capital of France?",
    "What landmark is Germany known for?",
    "Who painted the Mona Lisa?",   # no doc in corpus — expect low context_relevance
]

with tru_app as recording:
    for q in QUESTIONS:
        ans = app.query(q)
        print(f"Q: {q}\nA: {ans}\n")

# --- 5. Surface results ------------------------------------------------------
# Feedback functions run asynchronously; flush so the SQLite DB is current
# before we print the leaderboard.
records, feedback = tru.get_records_and_feedback(app_ids=[tru_app.app_id])
print("=== Leaderboard ===")
print(tru.get_leaderboard(app_ids=[tru_app.app_id]))

print("\n[recipe] start the TruLens dashboard with:")
print("           python -c 'from trulens.core import TruSession; TruSession().run_dashboard()'")
print("         (opens a streamlit UI on http://localhost:8484 by default).")
