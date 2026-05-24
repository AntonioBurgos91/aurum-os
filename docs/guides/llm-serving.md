# LLM Serving on AurumOS

AurumOS ships four ways to serve LLMs locally. They're not redundant — each
optimises for a different workload. This guide tells you which to pick.

> **TL;DR (RTX 5060 / 8 GB owner):** use **vLLM with AWQ** for chat and code,
> **LiteLLM** for "one endpoint to rule them all" routing, **SGLang** when
> you need strict JSON-schema output, and **TGI** when you're reproducing a
> Hugging Face Space.
>
> **TL;DR (no GPU, `lite` profile):** only **LiteLLM** runs — point it at
> OpenAI/Anthropic for cloud, or at the Wave 7 Ollama install (port 11434)
> for local CPU inference.

## The four servers

| Server      | Port  | Strength                                          | Weakness                                  | Profiles               |
|-------------|-------|---------------------------------------------------|-------------------------------------------|------------------------|
| **LiteLLM** | 4000  | OpenAI-compatible proxy → any backend             | Just a router; doesn't run the model      | **all** (lite included)|
| **vLLM**    | 8000  | Highest throughput on quantized weights (AWQ/GPTQ)| Less polished structured-output           | standard / pro / workstation |
| **SGLang**  | 30000 | Best structured output (JSON schema, regex)       | Newer; some quirks with very long contexts| standard / pro / workstation |
| **TGI**     | 8080  | HF-canonical; runs every checkpoint on HF Hub OOB | Slower than vLLM on quantized models      | standard / pro / workstation |

All four expose **OpenAI-compatible HTTP** (`/v1/chat/completions`,
`/v1/completions`, `/v1/embeddings` where applicable), so you can point any
OpenAI SDK client at them by changing only `base_url`.

## Profile-tier recommendations

| Profile     | Hardware              | Default models the launchers pick           |
|-------------|-----------------------|---------------------------------------------|
| `lite`      | No GPU / CPU only     | LiteLLM only → routes to Ollama + cloud     |
| `standard`  | RTX 5060 / 4060, 8 GB | Qwen2.5-7B-Instruct-AWQ (vLLM, SGLang)      |
| `pro`       | RTX 5070 / 4070, 16 GB| Qwen2.5-14B-Instruct-AWQ                    |
| `workstation`| RTX 5090 / A6000+, 24+ GB | Qwen2.5-32B-Instruct-AWQ                |

Override per-launch with `VLLM_MODEL=…`, `SGLANG_MODEL=…`, `TGI_MODEL=…`
in the environment.

## Choosing between them

### "I want OpenAI-shape APIs from many backends, no GPU work" → **LiteLLM**

```bash
aurum-launch-litellm
# → http://localhost:4000/v1
# Reads /etc/aurum/litellm-config.yaml. Default config exposes:
#   model_name: gpt-4o              → openai/gpt-4o            (needs OPENAI_API_KEY)
#   model_name: claude-3-5-sonnet   → anthropic/...            (needs ANTHROPIC_API_KEY)
#   model_name: qwen-local          → ollama_chat/qwen2.5:7b   (Wave 7 Ollama)
#   model_name: llama-local         → ollama_chat/llama3.2:3b
```

```python
from openai import OpenAI
c = OpenAI(base_url="http://localhost:4000/v1", api_key="anything")
c.chat.completions.create(model="qwen-local", messages=[...])  # → Ollama
c.chat.completions.create(model="gpt-4o", messages=[...])       # → OpenAI
```

Edit `/etc/aurum/litellm-config.yaml` to add models; the launcher reloads
on the next start. **Works on every profile, including `lite`.**

### "I want maximum chat-completion throughput on my one GPU" → **vLLM**

```bash
aurum-launch-vllm
# → http://localhost:8000/v1
# Picks Qwen2.5-7B-Instruct-AWQ by default on RTX 5060 (resident: ~6 GB VRAM).
# Reads $AURUM_VLLM_DEFAULT_ARGS from profile.conf for quantization +
# memory-utilization flags.
```

Best when you're hammering a single model with concurrent requests (agent
batches, dataset annotation, eval sweeps). AWQ-quantized weights fit
comfortably in 8 GB and run within ~10–20 % of fp16 quality at 2–3× the
tokens/sec.

### "I need strict JSON-schema output" → **SGLang**

```bash
aurum-launch-sglang
# → http://localhost:30000/v1
```

SGLang's `regex` / `json_schema` constrained-decoding paths are the most
battle-tested. Use it for tool-calling agents, structured extraction, or
anywhere a malformed JSON token costs a retry. Same AWQ defaults as vLLM.

### "I'm reproducing a Hugging Face Space / paper" → **TGI**

```bash
aurum-launch-tgi
# → http://localhost:8080/v1
```

TGI is the binary HF runs behind most demo Spaces. If you're matching
published metrics or running a checkpoint the author tested with TGI, this
will reproduce more reliably than vLLM (different kernels, different
sampling). The shipped binary doesn't support AWQ — use the bf16 weights.

## Stacking them

The recommended Wave 8 stack on a `standard` box:

```
                 LiteLLM (:4000)              ← all your scripts point here
                /    |     |    \
               /     |     |     \
           OpenAI  Anthropic  Ollama  vLLM (:8000)
           (cloud) (cloud)   (:11434) (RTX 5060, AWQ)
```

Define a model_name in `/etc/aurum/litellm-config.yaml` that targets your
local vLLM:

```yaml
- model_name: qwen-vllm
  litellm_params:
    model: openai/qwen2.5-7b-awq
    api_base: http://localhost:8000/v1
    api_key: "ignored"   # vLLM accepts any string
```

Now every script in your stack — Aider, Continue.dev, custom Python — can
route to your GPU via `model="qwen-vllm"` against `localhost:4000`.

## Troubleshooting

**`aurum-launch-vllm` says "not supported on profile=lite".**
Correct — vLLM has no CPU runtime. Either:
- Use `aurum-launch-litellm` and let it route to Ollama / OpenAI.
- If this machine has an RTX GPU but was misdetected as `lite`, regenerate
  the profile: `sudo /usr/local/bin/aurum-detect-profile`.

**vLLM / SGLang installs were skipped during post-install.**
On a CPU-only ISO build (Docker preview, CI) the install script catches the
"no CUDA wheel" failure and continues. Re-run
`bash /usr/share/aurum-os/post-install/07-install-llm-serving.sh` after
installing CUDA (or after booting on real GPU hardware).

**`http://localhost:4000/health` returns 404.**
LiteLLM's liveness endpoint is `/health/liveliness` (with the typo, theirs
not ours). Use that or `/health/readiness` instead.

**TGI binary missing on first launch.**
The post-install script ships only the fetcher stub. `aurum-launch-tgi`
runs the fetcher on first launch (~300 MB download). Requires network
access.

## See also

- `recipes/serving/` — Python recipes that exercise each server
- `docs/guides/dl-quickstart.md` — the broader DL stack overview
- `docs/guides/hardware-profiles.md` — how `AURUM_PROFILE` is detected
