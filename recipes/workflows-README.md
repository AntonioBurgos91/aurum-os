# AurumOS LLM workflow recipes

Companion to `README.md` (which covers fine-tuning and quantization). This
file documents the *orchestration* layer: declarative prompt programs,
schema-driven structured output, constrained generation, agent frameworks,
and MCP. All of these run on every profile (`lite`...`workstation`) because
they call out to Ollama / LiteLLM rather than holding a model in memory.

Installed by `distro/post-install/08-install-llm-workflows.sh` from
`distro/packages/pip-requirements-workflows.txt`.

## Default backend

Every recipe defaults to:

- **Model**: `ollama/qwen2.5:7b` (override with `AURUM_MODEL=...`)
- **Endpoint**: `http://localhost:11434` (override with `OLLAMA_BASE_URL=...`)

Swap to LiteLLM proxy:

```bash
export AURUM_MODEL=openai/gpt-4o-mini
export OLLAMA_BASE_URL=http://localhost:4000   # LiteLLM proxy
```

## Recipes

| Path                                     | Library      | Demonstrates                                |
|------------------------------------------|--------------|---------------------------------------------|
| `dspy/01_simple_qa.py`                   | DSPy         | Signature + BootstrapFewShot optimization    |
| `dspy/02_rag_pipeline.py`                | DSPy         | Retrieve -> ChainOfThought composition       |
| `instructor/01_structured_output.py`     | Instructor   | Pydantic model + `from_litellm`              |
| `instructor/02_validation_retry.py`      | Instructor   | Custom validators + automatic retry          |
| `outlines/01_json_schema.py`             | Outlines     | FSM-masked JSON-schema generation            |
| `outlines/02_regex_constraint.py`        | Outlines     | Regex-constrained token generation           |
| `pydantic-ai/01_agent.py`                | Pydantic-AI  | Agent with a single tool                     |
| `pydantic-ai/02_dependencies.py`         | Pydantic-AI  | Dependency injection via `RunContext`        |
| `mcp/templates/python-server/`           | MCP (Python) | Server template + `claude mcp add` recipe    |
| `mcp/templates/typescript-server/`       | MCP (TS)     | Server template (Node + Zod)                 |

## Run any recipe

```bash
# Make sure Ollama is up and the model is pulled.
ollama serve &
ollama pull qwen2.5:7b

# Then just run.
python3 recipes/dspy/01_simple_qa.py
```

## Scaffold a new MCP server

```bash
aurum-mcp-template create ./my-server      # Python template by default
aurum-mcp-template create ./my-server --ts # TypeScript template
```

See `recipes/mcp/README.md` for protocol overview and `claude mcp add`
registration commands.

## Why these libraries?

The 2025-2026 paradigm shift: AI engineers no longer write raw prompt
strings. They declare:

- a **schema** (Pydantic + Instructor / Outlines / Pydantic-AI) and let the
  framework coerce output;
- a **program** (DSPy Signatures + Modules) and let the framework optimise
  the prompt;
- a **capability surface** (MCP server) and let the host agent discover and
  call tools at runtime.

The libraries shipped here are the current standard-bearers for each of
those moves.
