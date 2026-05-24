# LLM observability and eval

AurumOS ships five tools for tracing, monitoring and evaluating LLM apps.
They overlap on purpose — each excels at a different stage of the workflow.

## The stack at a glance

| Tool        | What it's for                                | Where it runs            | Profile      |
|-------------|----------------------------------------------|--------------------------|--------------|
| Langfuse    | Persistent trace + cost dashboard for production | Self-hosted on :3030 (Docker) or cloud.langfuse.com | standard+ (self-host); lite uses cloud |
| Phoenix     | In-process span viewer for dev-loop debugging | Python process, :6007    | all          |
| Ragas       | RAG-specific metrics (faithfulness, context_*) | One-shot CLI / pytest | all          |
| DeepEval    | pytest-style LLM unit tests                  | pytest                   | all          |
| TruLens     | Continuous app evaluation with feedback fns  | Embedded SQLite + Streamlit dashboard | all |

## When to use what

**You shipped an app and want to know what users are doing.** → Langfuse.
Every prompt + completion + cost lives in one searchable dashboard. The
recipe at `recipes/observability/01_langfuse_trace_litellm.py` instruments
the AurumOS LiteLLM proxy in two lines.

**You're debugging a single chain locally.** → Phoenix.
Lower setup cost than Langfuse (no Docker, no Postgres). Just
`aurum-launch-phoenix` and inspect spans as your script runs. The recipe at
`recipes/observability/02_phoenix_trace_dspy.py` shows the DSPy auto-
instrumentation pattern; the same `openinference-instrumentation-*` packages
exist for LangChain, LiteLLM, LlamaIndex and others.

**You have a labelled RAG dataset and need a number.** → Ragas.
The four metrics it ships (faithfulness, answer_relevancy, context_precision,
context_recall) are well-understood and reproducible. See
`recipes/eval/01_ragas_rag_eval.py` and `aurum-eval ragas <file>`.

**You want the eval suite to fail your CI.** → DeepEval.
It plugs into pytest. Add an `assert_test(case, [metric])` to any test file
and `aurum-eval deepeval <file>` runs it. See
`recipes/eval/02_deepeval_test_suite.py`.

**You want continuous quality monitoring of a deployed app.** → TruLens.
Wrap your app once, define feedback functions, and TruLens scores every
invocation in the background. See `recipes/eval/03_trulens_app_eval.py`.

## Profile-specific behaviour

`distro/post-install/10-install-observability.sh` installs all five Python
libraries on every profile (they're small). Only the **self-hosted Langfuse
Docker stack** is profile-gated:

| Profile        | Action                                                          |
|----------------|-----------------------------------------------------------------|
| lite           | Pip libs only. Use cloud.langfuse.com (free tier) for the UI.   |
| standard+      | Pip libs + `/opt/aurum-langfuse/docker-compose.yml` written and images pre-pulled. |

To upgrade a `lite` install: edit `/etc/aurum/profile.conf`, set
`AURUM_PROFILE=standard`, and re-run `10-install-observability.sh`.

## Pointing Python at cloud Langfuse

On `lite`, export these in `~/.profile`:
```bash
export LANGFUSE_PUBLIC_KEY=pk-lf-...
export LANGFUSE_SECRET_KEY=sk-lf-...
export LANGFUSE_HOST=https://cloud.langfuse.com
```
Every recipe in `recipes/observability/` then works unchanged.

## Pointing Python at the self-hosted Langfuse

On `standard+`, after `aurum-launch-langfuse`:
1. Open http://localhost:3030, log in as `admin@aurum.local` /
   `aurum-default-changeme` (rotate this on first login).
2. Settings → API Keys → Create.
3. Export the pair plus `LANGFUSE_HOST=http://localhost:3030`.

## Where state lives

| Tool        | Path                                       |
|-------------|--------------------------------------------|
| Langfuse DB | `/var/lib/aurum-langfuse/db/` (bind mount) |
| Langfuse env | `/opt/aurum-langfuse/.env` (chmod 600)    |
| Phoenix DB  | `~/.phoenix/`                              |
| TruLens DB  | `~/.trulens/default.sqlite`                |

## Useful commands

```bash
aurum-launch-langfuse           # docker compose up + open Falkon
aurum-launch-phoenix            # bg python launcher + open Falkon
aurum-eval ragas dataset.json   # score a labelled dataset
aurum-eval deepeval tests/      # run DeepEval tests
aurum-eval trulens app.py       # run a TruLens-instrumented script
```
