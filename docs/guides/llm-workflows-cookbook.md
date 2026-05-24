# LLM workflows cookbook — when to pick DSPy / Instructor / Outlines / Pydantic-AI

AurumOS ships four overlapping libraries for turning an LLM into a
*programmable component*. They all install on every profile (the
inference happens in Ollama, not in the library), and they all interop
through LiteLLM, so you can mix and match in the same project.

This cookbook implements the same task — **"extract a structured
calendar event from a sentence"** — four times, then explains when you'd
pick each.

The task:

> Input: `"Schedule a sync with Alice and Bob on Wednesday at 2pm for 45 minutes about the Q3 roadmap."`
>
> Output: a typed object with `title`, `day`, `start_hour`,
> `duration_min`, `attendees`.

## Setup (one-time, all examples)

```bash
# All four libraries are already on every AurumOS profile.
python3 -c 'import dspy, instructor, outlines, pydantic_ai; print("ok")'

# All examples talk to local Ollama, so make sure it's up:
systemctl --user status ollama
ollama pull qwen2.5:7b   # standard tier default; lite users: qwen2.5:1.5b
export AURUM_MODEL="ollama/qwen2.5:7b"   # overrides recipe defaults
```

---

## 1. DSPy — *declarative*, optimised at compile time

```python
import dspy
from pydantic import BaseModel
from typing import Literal

dspy.configure(lm=dspy.LM("ollama/qwen2.5:7b",
                          api_base="http://localhost:11434",
                          max_tokens=256, temperature=0))

class CalendarEvent(BaseModel):
    title: str
    day: Literal["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    start_hour: int
    duration_min: int
    attendees: list[str]

class ExtractEvent(dspy.Signature):
    """Extract a calendar event from a natural-language sentence."""
    text: str = dspy.InputField()
    event: CalendarEvent = dspy.OutputField()

extract = dspy.Predict(ExtractEvent)
result = extract(text="Schedule a sync with Alice and Bob on Wednesday "
                      "at 2pm for 45 minutes about the Q3 roadmap.").event
print(result.model_dump_json(indent=2))
```

* **You never write a prompt string.** DSPy synthesises one from the
  `Signature` docstring + field descriptions.
* You can wrap `extract` in `BootstrapFewShot` and DSPy will *find its
  own few-shot examples* from a tiny `trainset` — see
  `recipes/dspy/01_simple_qa.py`.
* Works with any model LiteLLM understands.

**Pick DSPy when:**

* You have ≥ 10 labelled examples and care about quality.
* You want to swap models later (DSPy re-optimises the prompt).
* Your task has multiple stages (`ChainOfThought`, `ReAct`) that you'd
  otherwise glue together manually.

---

## 2. Instructor — *Pydantic-typed* drop-in for LiteLLM/OpenAI

```python
import instructor
import litellm
from pydantic import BaseModel, Field
from typing import Literal

class CalendarEvent(BaseModel):
    title: str = Field(..., description="short title, max 8 words")
    day: Literal["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    start_hour: int = Field(..., ge=0, le=23)
    duration_min: int = Field(..., gt=0, le=24 * 60)
    attendees: list[str] = Field(default_factory=list)

client = instructor.from_litellm(litellm.completion, mode=instructor.Mode.JSON)

event = client.chat.completions.create(
    model="ollama/qwen2.5:7b",
    response_model=CalendarEvent,
    max_retries=2,
    messages=[
        {"role": "system", "content": "Extract the event into the schema."},
        {"role": "user", "content":
            "Schedule a sync with Alice and Bob on Wednesday at 2pm "
            "for 45 minutes about the Q3 roadmap."},
    ],
)
print(event.model_dump_json(indent=2))
```

* The return value **is** a Pydantic model instance — no `json.loads`,
  no `dict["foo"]`.
* `max_retries=2` re-prompts with the validation error if the model
  returns invalid JSON.
* Mirrors the OpenAI SDK's `chat.completions.create` API, so it's a
  drop-in for any code that already uses LiteLLM or `openai`.

**Pick Instructor when:**

* You want the *most natural* Python API for typed output.
* You don't need prompt optimisation — your model is good enough out of
  the box.
* You're already on LiteLLM / OpenAI and want minimum diff.

See `recipes/instructor/01_structured_output.py` for a runnable copy.

---

## 3. Outlines — *constrained generation* at the token level

```python
import outlines
from pydantic import BaseModel, Field
from typing import Literal

class CalendarEvent(BaseModel):
    title: str
    day: Literal["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    start_hour: int = Field(..., ge=0, le=23)
    duration_min: int = Field(..., gt=0, le=24 * 60)
    attendees: list[str]

# Outlines speaks directly to the local model — no Ollama HTTP hop.
# For Ollama-served models, use the Ollama backend (Outlines ≥ 0.1):
model = outlines.models.ollama("qwen2.5:7b", base_url="http://localhost:11434")
generator = outlines.generate.json(model, CalendarEvent)

event = generator(
    "Schedule a sync with Alice and Bob on Wednesday at 2pm "
    "for 45 minutes about the Q3 roadmap."
)
print(event.model_dump_json(indent=2))
```

* Outlines biases the token sampler so **invalid JSON is impossible** —
  there's no retry loop, the output is guaranteed valid.
* Works with regex, EBNF grammars, and JSON schemas. Useful when the
  output format is exotic (e.g. a SQL `WHERE` clause).
* Has the most control, the highest learning curve, and the strictest
  model-backend requirements (works best with logit-access backends
  like `vllm` and `llama.cpp`).

**Pick Outlines when:**

* You *cannot* tolerate a single malformed output (e.g. parsing into a
  strict downstream system).
* You're running on vLLM or llama.cpp and can pass logits around.
* Your schema is unusual — regex, CFG, custom grammars.

---

## 4. Pydantic-AI — *agent* framework, Pydantic all the way down

```python
from pydantic import BaseModel, Field
from pydantic_ai import Agent
from pydantic_ai.models.openai import OpenAIModel   # works for Ollama via OpenAI-compat
from typing import Literal

class CalendarEvent(BaseModel):
    title: str = Field(..., description="short title, max 8 words")
    day: Literal["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    start_hour: int = Field(..., ge=0, le=23)
    duration_min: int = Field(..., gt=0, le=24 * 60)
    attendees: list[str] = Field(default_factory=list)

model = OpenAIModel("qwen2.5:7b", base_url="http://localhost:11434/v1")
agent = Agent(model, result_type=CalendarEvent,
              system_prompt="Extract the calendar event into the schema.")

run = agent.run_sync(
    "Schedule a sync with Alice and Bob on Wednesday at 2pm "
    "for 45 minutes about the Q3 roadmap."
)
print(run.data.model_dump_json(indent=2))
```

* `Agent` is built around *tools* + *typed results*; one-shot extraction
  is the simplest case.
* Streaming, dependency injection, message-history threading, and
  retries are built-in.
* `agent.tool` decorator lets the model call Python functions you mark
  as tools — useful for "do RAG, then summarise" pipelines.

**Pick Pydantic-AI when:**

* You're building an *agent* (multi-turn, tool-using), not a one-shot
  extractor.
* You want the most Pydantic-native ergonomics across the whole flow.
* You like FastAPI's style — Pydantic-AI is its spiritual cousin.

---

## Side-by-side decision table

| Concern                          | DSPy        | Instructor | Outlines    | Pydantic-AI |
|----------------------------------|-------------|------------|-------------|-------------|
| Typed Pydantic output            | ✅          | ✅✅✅      | ✅          | ✅✅         |
| Guaranteed valid output (no retry) | ⚠️ retry  | ⚠️ retry   | ✅✅✅       | ⚠️ retry    |
| Auto-optimised prompt            | ✅✅✅       | ❌         | ❌          | ❌          |
| Multi-step / agent loop          | ✅ (Module) | ❌         | ❌          | ✅✅✅        |
| Provider portability             | ✅✅ (LiteLLM)| ✅✅ (LiteLLM)| ⚠️ subset | ✅✅          |
| Streaming                        | ✅          | ✅         | ✅          | ✅✅✅        |
| Tool / function calling          | ✅ (ReAct)  | ✅         | ❌          | ✅✅✅        |
| Plays well with Ollama           | ✅✅         | ✅✅        | ✅          | ✅✅         |
| Learning curve                   | medium      | low        | high        | medium      |

## Combining libraries

These libraries *compose*. Common patterns:

* **DSPy + Outlines** — DSPy writes the prompt, Outlines enforces the
  format. Outlines has an experimental DSPy adapter.
* **Pydantic-AI + Instructor** — use Pydantic-AI for the agent loop and
  Instructor inside a tool function that needs typed output.
* **Any of the above + Phoenix** — `phoenix.otel.register()` once at
  startup, and every LiteLLM call gets a trace in the in-process
  Phoenix UI on `:6006` (see Wave 8 observability).

```python
# Trace every example above:
from phoenix.otel import register
register(project_name="aurum-cookbook")   # done
```

## Where to learn more

* **DSPy** — https://dspy.ai/ ; the `BootstrapFewShot` + `MIPRO`
  optimisers are where it shines.
* **Instructor** — https://python.useinstructor.com/ ; the
  `instructor.Maybe[T]` and `instructor.Iterable[T]` types are gold.
* **Outlines** — https://outlines.dev/ ; read the *Choices* and *CFG*
  pages for the killer features.
* **Pydantic-AI** — https://ai.pydantic.dev/ ; the *Tools* and
  *Dependency injection* sections.
* **AurumOS recipes** — `recipes/dspy/`, `recipes/instructor/`,
  `recipes/outlines/`, `recipes/pydantic-ai/` (when present),
  `recipes/mcp/` for the related Model Context Protocol stack.

## TL;DR

* Doing one-shot typed extraction? **Instructor**.
* Need bulletproof output, can run on vLLM/llama.cpp? **Outlines**.
* Building a multi-turn agent? **Pydantic-AI**.
* Have a benchmark dataset and want the model to teach itself the
  prompt? **DSPy**.
