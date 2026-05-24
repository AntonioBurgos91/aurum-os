# Deep Learning quickstart

AurumOS ships PyTorch, JAX, TensorFlow and vLLM pre-installed and verified.
This guide walks through opening your first notebook, switching CUDA toolkits,
and serving a local LLM.

## Verify the stack
```bash
aurum-dl-verify
```

This runs `tests/dl_smoke.py` (import + GPU visibility) followed by
`tests/dl_bench.py` (4096×4096 matmul + H2D bandwidth). On a healthy
machine you should see 4 green PASSED lines and a JSON report at
`~/.local/state/aurum-dl-verify.json`.

## Open a notebook
- **JupyterLab** — Press `Cmd+Space`, type `jupyter`, hit Enter. JupyterLab
  launches inside the AurumOS DL venv at `/opt/aurum-dl-venv`. Files live in
  `~/notebooks/`.
- **Marimo** — Same launcher path; or `marimo edit ~/notebooks/foo.py`. Marimo
  notebooks are pure Python files, so they diff and version-control cleanly.

## Quick PyTorch sanity check
```python
import torch
print(torch.cuda.is_available())            # True
print(torch.cuda.get_device_name(0))        # e.g. NVIDIA RTX 4090
x = torch.randn(2048, 2048, device="cuda")
y = x @ x
torch.cuda.synchronize()
print(y.shape)
```

## Local LLM serving
- **Ollama** is installed but **not** auto-started at boot (reasoning: ADR-0006
  performance budget). Start it on demand:
  ```bash
  sudo systemctl start ollama.service
  ollama run llama3.1
  ```
- **vLLM** runs in your venv:
  ```bash
  python -m vllm.entrypoints.openai.api_server \
      --model meta-llama/Llama-3.1-8B-Instruct --port 8000
  ```
  vLLM downloads the weights from Hugging Face on first run.

## Where things live
| What                       | Path                             |
|----------------------------|----------------------------------|
| DL venv (read-only system) | `/opt/aurum-dl-venv`             |
| User venvs                 | `~/venvs/`                       |
| Notebooks                  | `~/notebooks/`                   |
| Datasets                   | `~/datasets/`                    |
| Models                     | `~/models/`                      |
| Verify report              | `~/.local/state/aurum-dl-verify.json` |

The Finder sidebar pins all four ML directories under the "ML" section.
