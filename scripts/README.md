# scripts/

Out-of-process helpers the Qt binaries shell out to. Anything here is staged
to `/usr/local/share/aurum-os/scripts/` by the ISO builder.

| Script              | Caller                                         | Why a script               |
|---------------------|------------------------------------------------|----------------------------|
| `parquet_peek.py`   | `libs/ml-integrations::preview_parquet()`      | Avoids linking Arrow C++ into every Qt binary; polars/pyarrow live in the DL venv |

When adding a helper, name it lowercase-underscored, give it a single
responsibility, and have it print JSON to stdout — the C++ side expects
machine-readable output, not log lines.
