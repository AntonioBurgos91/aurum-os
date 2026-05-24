#!/usr/bin/env python3
# PROFILE: lite | standard | pro | workstation
# REQUIREMENTS: 2 GB RAM driver; runs against Ollama via LiteLLM
# MODEL: ollama/qwen2.5:7b (override with $AURUM_MODEL)
#
# Instructor patches LiteLLM so `client.chat.completions.create(...)` returns
# a *Pydantic model instance* instead of an OpenAI-style dict. The model is
# coerced + validated; on JSON-parse failure Instructor retries with the
# parser error message appended to the prompt.
"""Instructor: typed structured output via from_litellm."""

from __future__ import annotations

import os
from typing import Literal

import instructor
import litellm
from pydantic import BaseModel, Field

MODEL = os.environ.get("AURUM_MODEL", "ollama/qwen2.5:7b")
OLLAMA_BASE = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")

# LiteLLM looks at api_base per-call; set the env once for the entire run.
os.environ.setdefault("OLLAMA_API_BASE", OLLAMA_BASE)


class CalendarEvent(BaseModel):
    """A parsed calendar event."""

    title: str = Field(..., description="short title, max 8 words")
    day: Literal["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    start_hour: int = Field(..., ge=0, le=23)
    duration_min: int = Field(..., gt=0, le=24 * 60)
    attendees: list[str] = Field(default_factory=list)


# Mode.JSON works with any provider that respects a JSON response format;
# for Ollama we use Mode.JSON which prompts the model to emit pure JSON.
client = instructor.from_litellm(litellm.completion, mode=instructor.Mode.JSON)


def parse_event(text: str) -> CalendarEvent:
    return client.chat.completions.create(
        model=MODEL,
        response_model=CalendarEvent,
        messages=[
            {"role": "system", "content": "Extract the event into the schema."},
            {"role": "user", "content": text},
        ],
        max_retries=2,
    )


def main() -> None:
    text = (
        "Schedule a sync with Alice and Bob on Wednesday at 2pm "
        "for 45 minutes about the Q3 roadmap."
    )
    event = parse_event(text)
    print(event.model_dump_json(indent=2))


if __name__ == "__main__":
    main()
