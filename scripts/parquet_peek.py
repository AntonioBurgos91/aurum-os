#!/usr/bin/env python3
"""parquet_peek — emit a tiny JSON summary of a parquet file.

Called by libs/ml-integrations/ml_integrations.cpp::preview_parquet.
Reads the first `rows` rows and the file's schema, prints JSON to stdout.

Stays decoupled from any Python venv: imports inside main() so an import
failure produces a clean JSON error instead of a traceback the C++ side
would have to filter.

Usage: parquet_peek.py <path> <rows>
"""

from __future__ import annotations

import json
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(json.dumps({"error": "usage: parquet_peek.py <path> <rows>"}))
        return 2

    path = sys.argv[1]
    try:
        rows = max(1, min(int(sys.argv[2]), 200))
    except ValueError:
        rows = 20

    # Polars first (faster preview), fall back to pyarrow if polars isn't
    # installed in the active venv.
    try:
        import polars as pl
        head = pl.scan_parquet(path).head(rows).collect()
        out = {
            "rows":   pl.scan_parquet(path).select(pl.len()).collect().item(),
            "schema": [{"name": n, "type": str(t)} for n, t in head.schema.items()],
            "head":   head.to_dicts(),
        }
        print(json.dumps(out, default=str))
        return 0
    except ImportError:
        pass
    except Exception as exc:  # noqa: BLE001 -- surface a clean JSON error
        print(json.dumps({"error": f"polars: {exc}"}))
        return 1

    try:
        import pyarrow.parquet as pq
        meta = pq.read_metadata(path)
        schema = pq.read_schema(path)
        table = pq.read_table(path).slice(0, rows)
        out = {
            "rows":   meta.num_rows,
            "schema": [{"name": f.name, "type": str(f.type)} for f in schema],
            "head":   table.to_pylist(),
        }
        print(json.dumps(out, default=str))
        return 0
    except Exception as exc:  # noqa: BLE001
        print(json.dumps({"error": f"pyarrow: {exc}"}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
