#!/usr/bin/env python3
# PROFILE: lite | standard | pro | workstation
# REQUIREMENTS: 2 GB RAM driver
# MODEL: ollama/qwen2.5:7b (override with $AURUM_MODEL)
#
# Demonstrates Instructor's "validate -> retry with the error" loop. A custom
# `@field_validator` rejects clearly-bogus output (e.g. an email field that
# is not actually an email, or a sentiment outside the allowed enum). When
# the LM produces invalid JSON or a model instance that fails validation,
# Instructor reissues the call up to `max_retries` times with the validation
# error message appended so the model can self-correct.
"""Instructor: custom validators + automatic retries."""

from __future__ import annotations

import os
import re
from typing import Literal

import instructor
import litellm
from pydantic import BaseModel, Field, field_validator

MODEL = os.environ.get("AURUM_MODEL", "ollama/qwen2.5:7b")
OLLAMA_BASE = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")
os.environ.setdefault("OLLAMA_API_BASE", OLLAMA_BASE)

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class SupportTicket(BaseModel):
    """Triaged support ticket extracted from a free-text message."""

    customer_email: str = Field(..., description="contact address")
    sentiment: Literal["positive", "neutral", "negative"]
    summary: str = Field(..., max_length=240)

    @field_validator("customer_email")
    @classmethod
    def _email_shape(cls, v: str) -> str:
        if not _EMAIL_RE.match(v):
            # The error message is what Instructor relays back to the LM.
            raise ValueError(
                f"customer_email must look like 'user@host.tld'; got {v!r}"
            )
        return v.lower()

    @field_validator("summary")
    @classmethod
    def _no_pii_phone(cls, v: str) -> str:
        if re.search(r"\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b", v):
            raise ValueError("summary must not contain a phone number (PII)")
        return v


client = instructor.from_litellm(litellm.completion, mode=instructor.Mode.JSON)


def triage(message: str) -> SupportTicket:
    return client.chat.completions.create(
        model=MODEL,
        response_model=SupportTicket,
        max_retries=3,  # let the model self-heal validator failures
        messages=[
            {
                "role": "system",
                "content": (
                    "Triage the customer message into the schema. "
                    "Lowercase the email. Do not include phone numbers."
                ),
            },
            {"role": "user", "content": message},
        ],
    )


def main() -> None:
    msg = (
        "Hi - this is ALICE@Example.COM. My account stopped syncing yesterday "
        "and it's incredibly frustrating, please help."
    )
    ticket = triage(msg)
    print(ticket.model_dump_json(indent=2))


if __name__ == "__main__":
    main()
