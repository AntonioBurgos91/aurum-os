#!/usr/bin/env python3
# PROFILE: lite | standard | pro | workstation
# REQUIREMENTS: 2 GB RAM driver
# MODEL: ollama/qwen2.5:7b (override with $AURUM_MODEL)
#
# Pydantic-AI is Pydantic's take on agent frameworks: every tool's input AND
# output is a Pydantic model, the LM call is one method, and the agent's
# response is statically-typed. This recipe wires a single tool
# (`get_weather`) and asks the agent a question that requires calling it.
"""Pydantic-AI: minimal agent with one tool, talking to local Ollama."""

from __future__ import annotations

import os

from pydantic_ai import Agent
from pydantic_ai.models.openai import OpenAIModel
from pydantic_ai.providers.openai import OpenAIProvider

# Pydantic-AI ships an OpenAI-flavoured model adapter that works with any
# OpenAI-compatible endpoint, which is exactly what Ollama exposes at /v1.
MODEL_NAME = os.environ.get("AURUM_MODEL", "qwen2.5:7b")
OLLAMA_BASE = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")

model = OpenAIModel(
    MODEL_NAME,
    provider=OpenAIProvider(base_url=f"{OLLAMA_BASE}/v1", api_key="ollama"),
)

agent = Agent(
    model=model,
    system_prompt=(
        "You are a concise assistant. When asked about the weather you MUST "
        "call the get_weather tool; do not invent values."
    ),
)


@agent.tool_plain
def get_weather(city: str) -> str:
    """Return a one-line weather summary for ``city``.

    This is a stub; in a real agent it would call an HTTP weather API.
    """
    fixtures = {
        "buenos aires": "23 C, partly cloudy, light breeze",
        "paris":        "11 C, overcast, drizzle",
        "tokyo":        "18 C, clear",
    }
    return fixtures.get(city.lower(), f"sorry, no data for {city}")


def main() -> None:
    result = agent.run_sync("What's the weather like in Paris right now?")
    print(result.output)


if __name__ == "__main__":
    main()
