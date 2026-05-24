# ml-integrations

Quick Look preview helpers for the DL-native formats AurumOS surfaces in
Finder + Spotlight:

| Format        | Backend                                                      |
|---------------|--------------------------------------------------------------|
| `.ipynb`      | `QJsonDocument` (in-process, no deps)                         |
| `.safetensors`| Manual LE u64 header + JSON body parse (in-process)           |
| `.parquet`    | Shells out to [`scripts/parquet_peek.py`](../../scripts/parquet_peek.py) — polars-first, pyarrow-fallback |

Dispatcher:
```cpp
QJsonObject preview = aurum::ml::preview(path);
// → { kind, supported, preview: {...} | null, error: str | null }
```

Future MLflow / W&B Python client wrappers will live here too; for v0.1 the
tracker daemon talks REST directly from Rust.
