#!/usr/bin/env python3
# PROFILE: lite | standard | pro | workstation
# REQUIREMENTS: 2 GB RAM driver
# MODEL: ollama/qwen2.5:7b (override with $AURUM_MODEL)
#
# Pydantic-AI's dependency-injection system lets every tool receive a typed
# `RunContext[Deps]` carrying request-scoped state - a DB handle, an HTTP
# client, the calling user, feature flags, etc. The agent itself is global;
# the `deps` object is per-call. This pattern keeps tools pure (easy to test)
# while still giving them access to side-effecting resources.
"""Pydantic-AI: dependency injection through RunContext."""

from __future__ import annotations

import os
from dataclasses import dataclass, field

from pydantic_ai import Agent, RunContext
from pydantic_ai.models.openai import OpenAIModel
from pydantic_ai.providers.openai import OpenAIProvider

MODEL_NAME = os.environ.get("AURUM_MODEL", "qwen2.5:7b")
OLLAMA_BASE = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")


@dataclass
class Deps:
    """Per-request dependencies handed to every tool call."""

    user_id: str
    catalog: dict[str, float] = field(default_factory=dict)


model = OpenAIModel(
    MODEL_NAME,
    provider=OpenAIProvider(base_url=f"{OLLAMA_BASE}/v1", api_key="ollama"),
)

agent = Agent(
    model=model,
    deps_type=Deps,
    system_prompt=(
        "You are a shop assistant. Look up real prices with the lookup_price "
        "tool. Reject products that aren't in the catalog."
    ),
)


@agent.tool
def lookup_price(ctx: RunContext[Deps], product: str) -> str:
    """Return the price of ``product`` for the calling user, or 'unknown'."""
    price = ctx.deps.catalog.get(product.lower())
    if price is None:
        return f"unknown product: {product}"
    return f"user={ctx.deps.user_id} product={product} price=${price:.2f}"


def main() -> None:
    deps = Deps(
        user_id="u-42",
        catalog={"widget": 9.99, "gadget": 24.5, "thingamajig": 1.0},
    )
    result = agent.run_sync(
        "How much does a widget cost?",
        deps=deps,
    )
    print(result.output)


if __name__ == "__main__":
    main()
