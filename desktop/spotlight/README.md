# aurum-spotlight

Centered overlay launched by `Cmd+Space`. Aggregates five in-process plugins:

| Plugin       | Trigger                              | Backend                                            |
|--------------|--------------------------------------|----------------------------------------------------|
| Applications | bare                                 | `core-services::scan_desktop_entries()`            |
| Files        | bare (≥ 2 chars)                     | D-Bus → `aurum-spotlight-indexer` (tantivy)        |
| Calculator   | math expression                      | `QJSEngine` with regex gate                        |
| HuggingFace  | `hf:` / `hf ` / `model:`             | `huggingface.co/api/models?search=...`             |
| arXiv        | `arxiv:` / `arxiv ` / `paper:`       | `export.arxiv.org/api/query` (Atom XML)            |

| File                       | Role                                       |
|----------------------------|--------------------------------------------|
| `main.cpp`                 | Plugin registration + QML bridge           |
| `search_aggregator.*`      | Fan-out + `generation` for stale dedup     |
| `plugins/`                 | One file per plugin                        |
| `Spotlight.qml`            | Glass overlay + keyboard nav               |

Plugin authoring: see [`docs/guides/spotlight-plugins.md`](../../docs/guides/spotlight-plugins.md).
