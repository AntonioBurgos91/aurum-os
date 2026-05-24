#!/usr/bin/env python3
"""
Aurum-Sequoia file-type icon generator.

Reads `_manifest.json` and `_folder_manifest.json`, picks the matching template
under `_templates/`, performs placeholder substitution, and writes one SVG per
entry into this directory.

Idempotent: re-running overwrites in place. The script is intentionally
dependency-free (stdlib only) so it works in any Python 3.6+ environment.
"""
from __future__ import annotations
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TEMPLATES = ROOT / "_templates"
FILE_MANIFEST = ROOT / "_manifest.json"
FOLDER_MANIFEST = ROOT / "_folder_manifest.json"


def render_file_icons() -> int:
    manifest = json.loads(FILE_MANIFEST.read_text(encoding="utf-8"))
    count = 0
    for entry in manifest:
        name = entry["name"]
        category = entry["category"]
        color = entry["color"]
        label = entry["label"]
        tpl_path = TEMPLATES / f"{category}-base.svg"
        if not tpl_path.exists():
            print(f"  ! missing template for category={category} (entry {name})",
                  file=sys.stderr)
            continue
        svg = tpl_path.read_text(encoding="utf-8")
        svg = svg.replace("{{COLOR}}", color).replace("{{LABEL}}", label)
        out = ROOT / f"{name}.svg"
        out.write_text(svg, encoding="utf-8")
        count += 1
    return count


def render_folder_icons() -> int:
    manifest = json.loads(FOLDER_MANIFEST.read_text(encoding="utf-8"))
    tpl = (TEMPLATES / "folder-base.svg").read_text(encoding="utf-8")
    count = 0
    for entry in manifest:
        svg = (tpl
               .replace("{{COLOR}}", entry["color"])
               .replace("{{COLOR_DARK}}", entry["color_dark"])
               .replace("{{GLYPH}}", entry.get("glyph", "")))
        out = ROOT / f"{entry['name']}.svg"
        out.write_text(svg, encoding="utf-8")
        count += 1
    return count


def main() -> int:
    if not TEMPLATES.is_dir():
        print(f"missing {TEMPLATES}", file=sys.stderr)
        return 1
    n_files = render_file_icons()
    n_folders = render_folder_icons()
    print(f"generated {n_files} file-type icons + {n_folders} folder icons "
          f"({n_files + n_folders} total) in {ROOT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
