#!/usr/bin/env python3
# PROFILE: lite | standard | pro | workstation
# REQUIREMENTS: 2 GB RAM driver; model lives in Ollama
# MODEL: ollama/qwen2.5:7b (override with $AURUM_MODEL)
#
# Outlines enforces output structure at *generation* time by masking the
# token distribution against a compiled finite-state machine. The output is
# *guaranteed* to satisfy the schema - there is no parser to fail, no retry
# loop. This recipe targets the Ollama HTTP API via outlines's `models.openai`
# adapter (Ollama exposes an OpenAI-compatible /v1/chat/completions endpoint).
"""Outlines: guaranteed-valid JSON via json_schema generation."""

from __future__ import annotations

import json
import os

import outlines
from pydantic import BaseModel, Field

MODEL = os.environ.get("AURUM_MODEL", "qwen2.5:7b")  # raw Ollama tag, no prefix
OLLAMA_BASE = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")


class Person(BaseModel):
    name: str = Field(..., min_length=1, max_length=80)
    age: int = Field(..., ge=0, le=130)
    city: str
    hobbies: list[str] = Field(..., min_length=1, max_length=5)


def build_model() -> outlines.models.OpenAI:
    """Ollama serves an OpenAI-compatible API at /v1; outlines speaks it natively."""
    return outlines.models.openai(
        MODEL,
        base_url=f"{OLLAMA_BASE}/v1",
        api_key="ollama",  # Ollama ignores the key but the client demands one
    )


def main() -> None:
    model = build_model()
    generator = outlines.generate.json(model, Person)
    prompt = (
        "Return a JSON object describing a fictional person who lives in "
        "Buenos Aires."
    )
    person: Person = generator(prompt)
    print(json.dumps(person.model_dump(), indent=2))


if __name__ == "__main__":
    main()
