# AI-augmented coding on AurumOS

AurumOS ships three coding assistants pre-wired against your local Ollama
runtime — no API key, no token quota, no data leaving the box. Adding a cloud
key (Anthropic, OpenAI) on top is one line of config.

| Tool         | Surface        | Best for                                    |
|--------------|----------------|---------------------------------------------|
| Continue.dev | VSCode extension | Inline chat, tab-autocomplete, RAG over the workspace |
| Aider        | Terminal CLI   | Multi-file refactors, surgical whole-file edits with git diffs |
| Claude Code  | Terminal CLI   | Agentic tasks: run tests, read docs, iterate on a fix end-to-end |

All three are launchable from the dock / Spotlight (`Cmd+Space`, type "aider"
or "claude").

---

## Profile-aware local models

AurumOS detects your VRAM at install time and picks the right Qwen2.5-Coder
size for your machine. The chosen model is stored in
`/etc/aurum/profile.conf` as `AURUM_OLLAMA_DEFAULT`:

| Profile     | VRAM      | Default model         |
|-------------|-----------|-----------------------|
| lite        | 0 / CPU   | `qwen2.5-coder:1.5b`  |
| standard    | 6–12 GB   | `qwen2.5-coder:7b`    |
| pro         | 12–16 GB  | `qwen2.5-coder:14b`   |
| workstation | 24 GB+    | `qwen2.5-coder:32b`   |

If you upgrade your GPU (or just want to try a different model), re-run:

```bash
sudo aurum-detect-profile          # re-classify hardware
aurum-configure-continue           # regenerate ~/.continue/config.json
```

`aurum-configure-continue` backs up the previous config to
`~/.continue/config.json.bak.<timestamp>` first.

---

## Continue.dev (VSCode)

The extension is pre-installed and the config at `~/.continue/config.json`
already points at `http://localhost:11434` with your tier's model. To use it:

1. Open any project in VSCode.
2. Press `Cmd+L` (or `Ctrl+L`) to open the Continue chat panel.
3. Highlight code and press `Cmd+I` for inline edits.
4. Tab-autocomplete uses the small `qwen2.5-coder:1.5b` model regardless of
   tier — it has to be fast enough to keep up with typing.

### Adding cloud models

Open `~/.continue/config.json` and paste your key into the matching entry:

```json
{
  "title": "Claude 3.5 Sonnet (API)",
  "provider": "anthropic",
  "model": "claude-3-5-sonnet-20241022",
  "apiKey": "sk-ant-..."
}
```

Or set env vars in `~/.config/fish/conf.d/aurum-secrets.fish` (or your shell's
equivalent) — Continue.dev reads `ANTHROPIC_API_KEY` and `OPENAI_API_KEY` for
entries with `"apiKey": ""`.

### Workspace embeddings (RAG)

Continue.dev uses the `nomic-embed-text` Ollama model for codebase embeddings.
The installer pre-pulled it if Ollama was running at install time; if not:

```bash
ollama pull nomic-embed-text
```

Index your workspace from the Continue panel: `@codebase <your question>`.

---

## When to use Aider vs Claude Code

Both are terminal-first, both edit files in your repo, both can call local
Ollama or cloud models. The choice is mostly about workflow.

### Use **Aider** when...

- You want explicit `add file → ask → review diff → commit` cycles.
- You want to control exactly which files the model sees (token budget).
- You want git-native diffs (Aider can auto-commit each turn; we ship this
  **disabled** in `~/Templates/.aider.conf.yml` because most users prefer
  reviewing before commit).
- You're running fully offline against the local model.

```bash
cd ~/projects/my-repo
aider src/foo.py tests/test_foo.py   # explicit files
# or
aider                                 # let aider discover files via /add later
```

The shipped config in `~/Templates/.aider.conf.yml` defaults to
`ollama/<your-tier's-model>` with `weak-model = ollama/qwen2.5-coder:1.5b` for
commit-message generation and other fast tasks. Copy it into a project to
override per-repo.

To use Claude or GPT-4 with Aider:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
aider --model anthropic/claude-3-5-sonnet-20241022

export OPENAI_API_KEY=sk-...
aider --model gpt-4o
```

### Use **Claude Code** when...

- You want an *agent*, not a chat — let it run `pytest`, read error output,
  edit, retry, until tests pass.
- The task spans many files and you don't want to manually `/add` each one.
- You're OK paying API tokens for the autonomy (Claude Code currently has no
  Ollama backend).

```bash
export ANTHROPIC_API_KEY=sk-ant-...
cd ~/projects/my-repo
claude                                # interactive
# or
claude "fix the failing tests in tests/auth/"
```

### CLAUDE.md

Claude Code reads `CLAUDE.md` in your project root as durable context — build
commands, code style, gotchas it should know about. AurumOS ships a starter
template at `~/Templates/CLAUDE.md`; copy it into a new project:

```bash
cp ~/Templates/CLAUDE.md ~/projects/my-repo/CLAUDE.md
$EDITOR ~/projects/my-repo/CLAUDE.md
```

---

## Setting API keys

For shell sessions, persist them in your shell rc:

```bash
# ~/.config/fish/conf.d/aurum-secrets.fish (AurumOS default shell is fish)
set -x ANTHROPIC_API_KEY sk-ant-...
set -x OPENAI_API_KEY sk-...
```

Or in bash/zsh:

```bash
# ~/.bashrc or ~/.zshrc
export ANTHROPIC_API_KEY=sk-ant-...
export OPENAI_API_KEY=sk-...
```

`chmod 600` the file so it's user-readable only. Don't commit it.

For VSCode (Continue.dev): paste into `~/.continue/config.json` as shown above.

---

## Cheat sheet

| Want to...                              | Run                                  |
|-----------------------------------------|--------------------------------------|
| Switch local model after GPU upgrade    | `sudo aurum-detect-profile && aurum-configure-continue` |
| Pull a different code model             | `ollama pull qwen2.5-coder:14b`      |
| List installed Ollama models            | `ollama list`                        |
| Reset Continue config to AurumOS default | `aurum-configure-continue`           |
| See Aider's effective config            | `aider --show-config`                |
| Start Claude Code with a task           | `claude "<task>"`                    |
| Templates folder                        | `~/Templates/` (`CLAUDE.md`, `.cursorrules`, `.aider.conf.yml`) |
