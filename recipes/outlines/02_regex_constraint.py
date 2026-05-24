#!/usr/bin/env python3
# PROFILE: lite | standard | pro | workstation
# REQUIREMENTS: 2 GB RAM driver
# MODEL: ollama/qwen2.5:7b (override with $AURUM_MODEL)
#
# Sometimes you need a token-level guarantee that's tighter than "valid JSON":
# a phone number, an ISO date, a license plate, a SKU code. Outlines accepts
# any Python regex and compiles it into the same FSM-masking machinery used
# by `generate.json`. The model literally cannot emit a character that would
# break the pattern.
"""Outlines: regex-constrained generation (phone numbers)."""

from __future__ import annotations

import os
import re

import outlines

MODEL = os.environ.get("AURUM_MODEL", "qwen2.5:7b")
OLLAMA_BASE = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")

# North-American phone number, optionally country-coded.
#   +1 555-123-4567
#   (555) 123-4567
#   555.123.4567
PHONE_RE = r"(\+1[\s-]?)?(\(\d{3}\)|\d{3})[\s.-]\d{3}[\s.-]\d{4}"


def main() -> None:
    model = outlines.models.openai(
        MODEL,
        base_url=f"{OLLAMA_BASE}/v1",
        api_key="ollama",
    )
    generator = outlines.generate.regex(model, PHONE_RE)
    prompt = (
        "Give me a single fictional US phone number for a fake character. "
        "Return only the number, nothing else."
    )
    number = generator(prompt)
    print(f"generated: {number}")
    # Belt-and-braces sanity check; the FSM should make this impossible to fail.
    assert re.fullmatch(PHONE_RE, number), "regex constraint was violated"


if __name__ == "__main__":
    main()
