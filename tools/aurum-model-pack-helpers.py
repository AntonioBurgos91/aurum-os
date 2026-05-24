#!/usr/bin/env python3
# ==============================================================================
# AurumOS aurum-model-pack — Python helpers / core implementation (Wave 9)
#
# This is the full implementation of the CLI; the sibling `aurum-model-pack`
# bash script is a thin shim that just runs `python3 <this file> "$@"`.
# Keeping the heavy logic in Python lets us use huggingface_hub (when
# available) and pyyaml without bash JSON gymnastics.
#
# The CLI must work in three modes:
#   1. Live system  — manifests under /etc/aurum/model-packs/, cache under
#                     ~/.cache/aurum/models/, runs `ollama` and downloads
#                     via huggingface_hub.snapshot_download().
#   2. Dev checkout — manifests under <repo>/distro/assets/model-packs/.
#                     We resolve relative to this file's location when the
#                     /etc path doesn't exist.
#   3. Docker preview / CI — pyyaml optional (tiny fallback parser), `ollama`
#                            absent, no real downloads. The smoke commands
#                            (`list`, `info`, `--json list`) must still work.
#
# Progress protocol (consumed by Agent H's GUI via QProcess stdout):
#     PROGRESS:<pack-id>:<percent>
#     DONE:<pack-id>
#     ERROR:<pack-id>:<message>
#     INFO:<message>
# Each event is exactly one line, flushed immediately.
# ==============================================================================

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

# ---------------------------------------------------------------------------
# Paths & constants
# ---------------------------------------------------------------------------

PROFILE_CONF = Path(os.environ.get("AURUM_PROFILE_CONF", "/etc/aurum/profile.conf"))
CACHE_ROOT = Path(
    os.environ.get(
        "AURUM_MODEL_CACHE",
        str(Path.home() / ".cache" / "aurum" / "models"),
    )
)
INSTALLED_DIR = CACHE_ROOT / ".installed"

# Manifests live at /etc/aurum/model-packs/ on a real install; fall back to the
# in-repo asset dir for `bash tools/aurum-model-pack list` during development.
_THIS_FILE = Path(__file__).resolve()
_REPO_MANIFEST_DIR = _THIS_FILE.parent.parent / "distro" / "assets" / "model-packs"
MANIFEST_DIRS = [
    Path(os.environ["AURUM_MODEL_PACKS_DIR"])
    if "AURUM_MODEL_PACKS_DIR" in os.environ
    else None,
    Path("/etc/aurum/model-packs"),
    _REPO_MANIFEST_DIR,
]
MANIFEST_DIRS = [p for p in MANIFEST_DIRS if p is not None]

PROFILE_RANK = {"lite": 0, "standard": 1, "pro": 2, "workstation": 3}

# ---------------------------------------------------------------------------
# Logging — must stay machine-parseable; never colorize stdout.
# ---------------------------------------------------------------------------


def emit(line: str) -> None:
    """Print one event line to stdout, flushed (QProcess reads line-by-line)."""
    sys.stdout.write(line.rstrip("\n") + "\n")
    sys.stdout.flush()


def info(msg: str) -> None:
    emit(f"INFO:{msg}")


def progress(pack_id: str, percent: int) -> None:
    pct = max(0, min(100, int(percent)))
    emit(f"PROGRESS:{pack_id}:{pct}")


def done(pack_id: str) -> None:
    emit(f"DONE:{pack_id}")


def error(pack_id: str, msg: str) -> None:
    # Strip newlines from the message so the line stays single-line for parsers.
    flat = " ".join(str(msg).splitlines()).strip()
    emit(f"ERROR:{pack_id}:{flat}")


def warn(msg: str) -> None:
    sys.stderr.write(f"[aurum-model-pack] WARN: {msg}\n")
    sys.stderr.flush()


# ---------------------------------------------------------------------------
# YAML loading — prefer pyyaml; fall back to a tiny purpose-built parser so
# the CLI works in stripped-down containers / CI without `pip install pyyaml`.
# ---------------------------------------------------------------------------


def _load_yaml(path: Path) -> dict[str, Any]:
    try:
        import yaml  # type: ignore

        with path.open("r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
        if not isinstance(data, dict):
            raise ValueError(f"{path}: top-level YAML must be a mapping")
        return data
    except ImportError:
        return _minimal_yaml_load(path)


def _minimal_yaml_load(path: Path) -> dict[str, Any]:
    """
    Tiny YAML subset parser — handles only what our manifests use:
      - 2-space indented mappings
      - lists of scalars (`- foo`) or lists of mappings (`- key: val`)
      - block scalars `>` and `|` (folded into a single string)
      - line comments starting with `#`
      - quoted strings ("..." or '...'), integers, floats, true/false/null
    NOT a general YAML parser; sufficient for distro/assets/model-packs/*.yaml.
    """
    raw = path.read_text(encoding="utf-8").splitlines()
    # Strip trailing comments + blank lines, but preserve indentation.
    lines: list[tuple[int, str]] = []  # (indent, content)
    i = 0
    while i < len(raw):
        line = raw[i]
        stripped = line.rstrip()
        # Skip pure comments / blanks at the structural level.
        if not stripped.strip() or stripped.lstrip().startswith("#"):
            i += 1
            continue
        # Strip inline `# ...` comments unless inside quotes (simple heuristic:
        # only strip when the `#` is preceded by whitespace).
        m = re.search(r"\s+#", stripped)
        if m:
            stripped = stripped[: m.start()].rstrip()
        indent = len(line) - len(line.lstrip(" "))
        lines.append((indent, stripped.lstrip(" ")))
        i += 1

    pos = [0]

    def _scalar(v: str) -> Any:
        v = v.strip()
        if not v:
            return None
        if v.lower() in ("null", "~"):
            return None
        if v.lower() == "true":
            return True
        if v.lower() == "false":
            return False
        if (v.startswith('"') and v.endswith('"')) or (
            v.startswith("'") and v.endswith("'")
        ):
            return v[1:-1]
        # Inline flow list like ["a", "b"] — common in our manifests for
        # the `files:` field. Strict JSON-ish split is good enough; anything
        # weird falls back to the raw string.
        if v.startswith("[") and v.endswith("]"):
            inner = v[1:-1].strip()
            if not inner:
                return []
            parts = [p.strip() for p in inner.split(",")]
            return [_scalar(p) for p in parts]
        # int / float
        if re.fullmatch(r"-?\d+", v):
            try:
                return int(v)
            except ValueError:
                pass
        if re.fullmatch(r"-?\d+\.\d+", v):
            try:
                return float(v)
            except ValueError:
                pass
        return v

    def _parse_block(my_indent: int) -> Any:
        # Decide list vs mapping by looking at first line at this indent.
        if pos[0] >= len(lines):
            return None
        first_indent, first_content = lines[pos[0]]
        if first_indent < my_indent:
            return None
        if first_content.startswith("- "):
            return _parse_list(my_indent)
        return _parse_map(my_indent)

    def _parse_map(my_indent: int) -> dict[str, Any]:
        out: dict[str, Any] = {}
        while pos[0] < len(lines):
            indent, content = lines[pos[0]]
            if indent < my_indent:
                break
            if indent > my_indent:
                # Shouldn't happen at map level — bail.
                break
            if content.startswith("- "):
                break
            if ":" not in content:
                raise ValueError(f"{path}: expected `key: value` at `{content}`")
            key, _, rest = content.partition(":")
            key = key.strip()
            rest = rest.strip()
            pos[0] += 1
            if rest in (">", "|", ">-", "|-"):
                # Block scalar: gather indented lines until indent <= my_indent.
                parts: list[str] = []
                while pos[0] < len(lines):
                    sub_indent, sub_content = lines[pos[0]]
                    if sub_indent <= my_indent:
                        break
                    parts.append(sub_content)
                    pos[0] += 1
                out[key] = " ".join(parts) if rest.startswith(">") else "\n".join(parts)
            elif rest == "":
                # Nested block — either map or list.
                out[key] = _parse_block(my_indent + 2)
            else:
                out[key] = _scalar(rest)
        return out

    def _parse_list(my_indent: int) -> list[Any]:
        out: list[Any] = []
        while pos[0] < len(lines):
            indent, content = lines[pos[0]]
            if indent < my_indent or not content.startswith("- "):
                break
            if indent > my_indent:
                break
            item = content[2:].strip()
            pos[0] += 1
            if ":" in item and not (item.startswith('"') or item.startswith("'")):
                # List item is the first key of a mapping.
                key, _, rest = item.partition(":")
                key = key.strip()
                rest = rest.strip()
                m: dict[str, Any] = {}
                if rest == "":
                    m[key] = _parse_block(my_indent + 4)
                else:
                    m[key] = _scalar(rest)
                # Subsequent keys at indent my_indent+2 belong to this item.
                while pos[0] < len(lines):
                    sub_indent, sub_content = lines[pos[0]]
                    if sub_indent != my_indent + 2 or sub_content.startswith("- "):
                        break
                    if ":" not in sub_content:
                        break
                    k2, _, r2 = sub_content.partition(":")
                    k2 = k2.strip()
                    r2 = r2.strip()
                    pos[0] += 1
                    if r2 in (">", "|", ">-", "|-"):
                        parts: list[str] = []
                        while pos[0] < len(lines):
                            si, sc = lines[pos[0]]
                            if si <= my_indent + 2:
                                break
                            parts.append(sc)
                            pos[0] += 1
                        m[k2] = (
                            " ".join(parts) if r2.startswith(">") else "\n".join(parts)
                        )
                    elif r2 == "":
                        m[k2] = _parse_block(my_indent + 4)
                    else:
                        m[k2] = _scalar(r2)
                out.append(m)
            else:
                out.append(_scalar(item))
        return out

    result = _parse_block(0)
    if not isinstance(result, dict):
        raise ValueError(f"{path}: top-level YAML must be a mapping (got {type(result).__name__})")
    return result


# ---------------------------------------------------------------------------
# Manifest model
# ---------------------------------------------------------------------------


@dataclass
class ModelEntry:
    source: str                  # "ollama" | "hf"
    raw: dict[str, Any] = field(default_factory=dict)

    @property
    def display_name(self) -> str:
        if self.source == "ollama":
            return self.raw.get("name", "<unknown>")
        if self.source == "hf":
            return self.raw.get("repo", "<unknown>")
        return "<unknown>"

    @property
    def size_bytes(self) -> int:
        return int(self.raw.get("size_bytes") or 0)

    @property
    def min_profile(self) -> str | None:
        return self.raw.get("min_profile")


@dataclass
class Manifest:
    id: str
    title: str
    description: str
    size_bytes: int
    min_profile: str
    docs_url: str
    models: list[ModelEntry]
    tags: list[str]
    path: Path
    raw: dict[str, Any]

    @classmethod
    def load(cls, path: Path) -> "Manifest":
        data = _load_yaml(path)
        models_raw = data.get("models") or []
        models = [ModelEntry(source=m.get("source", ""), raw=m) for m in models_raw]
        return cls(
            id=str(data.get("id") or path.stem),
            title=str(data.get("title") or path.stem.title()),
            description=str(data.get("description") or "").strip(),
            size_bytes=int(data.get("size_bytes") or 0),
            min_profile=str(data.get("min_profile") or "lite"),
            docs_url=str(data.get("docs_url") or ""),
            models=models,
            tags=list(data.get("tags") or []),
            path=path,
            raw=data,
        )


def discover_manifests() -> list[Manifest]:
    """Find every *.yaml in the first MANIFEST_DIRS entry that exists."""
    for d in MANIFEST_DIRS:
        if d.is_dir():
            yamls = sorted(d.glob("*.yaml")) + sorted(d.glob("*.yml"))
            if yamls:
                out: list[Manifest] = []
                for y in yamls:
                    try:
                        out.append(Manifest.load(y))
                    except Exception as exc:  # noqa: BLE001
                        warn(f"failed to load {y}: {exc}")
                # Deduplicate by id (last wins) but keep order.
                seen: dict[str, Manifest] = {}
                for m in out:
                    seen[m.id] = m
                return list(seen.values())
    return []


def load_manifest(pack_id: str) -> Manifest:
    for m in discover_manifests():
        if m.id == pack_id:
            return m
    raise SystemExit(f"unknown pack: {pack_id!r} (run `aurum-model-pack list`)")


# ---------------------------------------------------------------------------
# Profile gating
# ---------------------------------------------------------------------------


def current_profile() -> str:
    """Read AURUM_PROFILE from /etc/aurum/profile.conf; default to 'standard'."""
    env_override = os.environ.get("AURUM_PROFILE")
    if env_override:
        return env_override.strip().lower()
    if PROFILE_CONF.is_file():
        for raw_line in PROFILE_CONF.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("AURUM_PROFILE="):
                val = line.split("=", 1)[1].strip().strip('"').strip("'").lower()
                if val:
                    return val
    return "standard"


def profile_rank(p: str) -> int:
    return PROFILE_RANK.get(p.lower(), 0)


def profile_meets(required: str, have: str) -> bool:
    return profile_rank(have) >= profile_rank(required)


# ---------------------------------------------------------------------------
# Install state (sentinel files)
# ---------------------------------------------------------------------------


def is_installed(pack_id: str) -> bool:
    return (INSTALLED_DIR / pack_id).is_file()


def write_sentinel(pack_id: str, models_installed: list[str]) -> None:
    INSTALLED_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "pack_id": pack_id,
        "installed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "models": models_installed,
        "profile": current_profile(),
    }
    (INSTALLED_DIR / pack_id).write_text(json.dumps(payload, indent=2), encoding="utf-8")


def read_sentinel(pack_id: str) -> dict[str, Any] | None:
    p = INSTALLED_DIR / pack_id
    if not p.is_file():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return {"pack_id": pack_id, "installed_at": "unknown", "models": []}


def remove_sentinel(pack_id: str) -> None:
    p = INSTALLED_DIR / pack_id
    if p.is_file():
        p.unlink()


# ---------------------------------------------------------------------------
# Cache size helpers
# ---------------------------------------------------------------------------


def dir_size_bytes(root: Path) -> int:
    if not root.is_dir():
        return 0
    total = 0
    for dirpath, _dirs, files in os.walk(root, followlinks=False):
        for f in files:
            try:
                total += (Path(dirpath) / f).stat().st_size
            except OSError:
                pass
    return total


def fmt_bytes(n: int) -> str:
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    f = float(n)
    for u in units:
        if f < 1024 or u == units[-1]:
            return f"{f:.1f} {u}" if u != "B" else f"{int(f)} {u}"
        f /= 1024
    return f"{n} B"


# ---------------------------------------------------------------------------
# Ollama + HF download wrappers
# ---------------------------------------------------------------------------


def have_command(name: str) -> bool:
    return shutil.which(name) is not None


def ollama_already_has(model_name: str) -> bool:
    """Return True if `ollama list` shows the tag already pulled."""
    if not have_command("ollama"):
        return False
    try:
        out = subprocess.run(
            ["ollama", "list"], capture_output=True, text=True, timeout=10, check=False
        )
        return any(model_name in line for line in out.stdout.splitlines())
    except (subprocess.TimeoutExpired, OSError):
        return False


def install_ollama_model(
    pack_id: str,
    model: ModelEntry,
    base_pct: int,
    span_pct: int,
    dry_run: bool,
) -> bool:
    name = model.display_name
    if ollama_already_has(name):
        info(f"{pack_id}: ollama already has {name}; skipping")
        progress(pack_id, base_pct + span_pct)
        return True
    if dry_run:
        info(f"{pack_id}: [dry-run] would `ollama pull {name}`")
        progress(pack_id, base_pct + span_pct)
        return True
    if not have_command("ollama"):
        error(pack_id, f"ollama CLI not found; cannot pull {name}")
        return False

    info(f"{pack_id}: ollama pull {name}")
    # Parse Ollama's progress lines: "pulling abc123: 42% ▕████  ▏  1.2 GB/2.8 GB"
    proc = subprocess.Popen(
        ["ollama", "pull", name],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    pct_re = re.compile(r"(\d{1,3})\s*%")
    last_pct = -1
    assert proc.stdout is not None
    for line in proc.stdout:
        m = pct_re.search(line)
        if m:
            sub = int(m.group(1))
            mapped = base_pct + (sub * span_pct) // 100
            if mapped != last_pct:
                progress(pack_id, mapped)
                last_pct = mapped
    rc = proc.wait()
    if rc != 0:
        error(pack_id, f"ollama pull {name} exited with code {rc}")
        return False
    progress(pack_id, base_pct + span_pct)
    return True


def install_hf_files(
    pack_id: str,
    model: ModelEntry,
    base_pct: int,
    span_pct: int,
    dry_run: bool,
) -> bool:
    repo = model.raw.get("repo", "")
    files = model.raw.get("files") or []
    dest = os.path.expanduser(str(model.raw.get("dest") or CACHE_ROOT / "hf" / repo))
    dest_path = Path(dest)
    if dry_run:
        info(
            f"{pack_id}: [dry-run] would fetch {len(files)} file(s) from {repo} "
            f"-> {dest_path}"
        )
        progress(pack_id, base_pct + span_pct)
        return True

    try:
        from huggingface_hub import hf_hub_download  # type: ignore
    except ImportError:
        error(
            pack_id,
            "huggingface_hub not installed (apt: python3-huggingface-hub or "
            "pip install huggingface_hub)",
        )
        return False

    dest_path.mkdir(parents=True, exist_ok=True)
    info(f"{pack_id}: huggingface_hub fetch {repo} ({len(files)} file(s)) -> {dest_path}")
    step = max(1, span_pct // max(1, len(files)))
    cur = base_pct
    for i, fname in enumerate(files, 1):
        try:
            hf_hub_download(
                repo_id=repo,
                filename=fname,
                local_dir=str(dest_path),
            )
        except Exception as exc:  # noqa: BLE001
            error(pack_id, f"hf_hub_download({repo}, {fname}) failed: {exc}")
            return False
        cur = min(base_pct + span_pct, base_pct + i * step)
        progress(pack_id, cur)
    progress(pack_id, base_pct + span_pct)
    return True


# ---------------------------------------------------------------------------
# Pack-level install / remove
# ---------------------------------------------------------------------------


def filter_models_by_profile(
    manifest: Manifest, profile: str, force: bool
) -> tuple[list[ModelEntry], list[ModelEntry]]:
    """Split into (will_install, skipped_due_to_profile)."""
    install: list[ModelEntry] = []
    skipped: list[ModelEntry] = []
    for m in manifest.models:
        req = m.min_profile or manifest.min_profile
        if profile_meets(req, profile) or force:
            install.append(m)
        else:
            skipped.append(m)
    return install, skipped


def install_pack(pack_id: str, force: bool = False, dry_run: bool = False) -> int:
    manifest = load_manifest(pack_id)
    profile = current_profile()

    # Pack-level profile gate.
    if not profile_meets(manifest.min_profile, profile) and not force:
        error(
            pack_id,
            f"profile gate: pack requires '{manifest.min_profile}', "
            f"current is '{profile}'. Re-run with --force to override.",
        )
        return 2

    if is_installed(pack_id) and not force:
        info(f"{pack_id}: already installed (sentinel present); use --force to reinstall")
        done(pack_id)
        return 0

    to_install, skipped = filter_models_by_profile(manifest, profile, force)
    for s in skipped:
        info(
            f"{pack_id}: skipping {s.display_name} "
            f"(requires profile '{s.min_profile}', have '{profile}')"
        )

    if not to_install:
        error(pack_id, "no installable models for current profile")
        return 2

    CACHE_ROOT.mkdir(parents=True, exist_ok=True)
    INSTALLED_DIR.mkdir(parents=True, exist_ok=True)

    n = len(to_install)
    span = 100 // n
    installed_names: list[str] = []
    progress(pack_id, 0)
    for i, m in enumerate(to_install):
        base = i * span
        if m.source == "ollama":
            ok = install_ollama_model(pack_id, m, base, span, dry_run)
        elif m.source == "hf":
            ok = install_hf_files(pack_id, m, base, span, dry_run)
        else:
            error(pack_id, f"unknown source {m.source!r} for {m.display_name}")
            return 1
        if not ok:
            return 1
        installed_names.append(f"{m.source}:{m.display_name}")

    write_sentinel(pack_id, installed_names)
    progress(pack_id, 100)
    done(pack_id)
    return 0


def remove_pack(pack_id: str) -> int:
    manifest = load_manifest(pack_id)
    sentinel = read_sentinel(pack_id)
    if sentinel is None:
        info(f"{pack_id}: not installed (no sentinel); nothing to do")
        return 0

    # Remove Ollama models (best-effort).
    if have_command("ollama"):
        for m in manifest.models:
            if m.source == "ollama":
                name = m.display_name
                info(f"{pack_id}: ollama rm {name}")
                subprocess.run(
                    ["ollama", "rm", name],
                    capture_output=True,
                    text=True,
                    check=False,
                )

    # Remove HF download directories that we own.
    for m in manifest.models:
        if m.source == "hf":
            dest = Path(os.path.expanduser(str(m.raw.get("dest") or "")))
            # Only delete inside the aurum cache root or aurum-comfyui tree.
            if dest and (
                str(dest).startswith(str(CACHE_ROOT))
                or str(dest).startswith("/opt/aurum-comfyui/")
            ):
                for fname in m.raw.get("files") or []:
                    fp = dest / Path(fname).name
                    if fp.is_file():
                        try:
                            fp.unlink()
                            info(f"{pack_id}: removed {fp}")
                        except OSError as exc:
                            warn(f"failed to remove {fp}: {exc}")
            else:
                warn(f"{pack_id}: refusing to delete files outside cache root: {dest}")

    remove_sentinel(pack_id)
    done(pack_id)
    return 0


# ---------------------------------------------------------------------------
# Command implementations
# ---------------------------------------------------------------------------


def cmd_list(json_out: bool) -> int:
    manifests = discover_manifests()
    profile = current_profile()
    rows = []
    for m in manifests:
        rows.append(
            {
                "id": m.id,
                "title": m.title,
                "description": m.description,
                "size_bytes": m.size_bytes,
                "size_human": fmt_bytes(m.size_bytes),
                "min_profile": m.min_profile,
                "state": "installed" if is_installed(m.id) else "not_installed",
                "available_for_profile": profile_meets(m.min_profile, profile),
                "docs_url": m.docs_url,
                "tags": m.tags,
                "model_count": len(m.models),
            }
        )

    if json_out:
        emit(json.dumps({"profile": profile, "packs": rows}, indent=2))
        return 0

    if not rows:
        info("no model packs found (looked in: " + ", ".join(str(p) for p in MANIFEST_DIRS) + ")")
        return 0

    # Human table.
    sys.stdout.write(f"Profile: {profile}\n\n")
    sys.stdout.write(
        f"{'ID':<14} {'STATE':<14} {'PROFILE':<12} {'SIZE':>10}  TITLE\n"
    )
    sys.stdout.write("-" * 78 + "\n")
    for r in rows:
        avail = "" if r["available_for_profile"] else " (gated)"
        sys.stdout.write(
            f"{r['id']:<14} {r['state']:<14} "
            f"{r['min_profile'] + avail:<12} "
            f"{r['size_human']:>10}  {r['title']}\n"
        )
    sys.stdout.flush()
    return 0


def cmd_info(pack_id: str, json_out: bool) -> int:
    m = load_manifest(pack_id)
    profile = current_profile()
    sentinel = read_sentinel(pack_id)
    payload: dict[str, Any] = {
        "id": m.id,
        "title": m.title,
        "description": m.description,
        "size_bytes": m.size_bytes,
        "size_human": fmt_bytes(m.size_bytes),
        "min_profile": m.min_profile,
        "current_profile": profile,
        "available_for_profile": profile_meets(m.min_profile, profile),
        "docs_url": m.docs_url,
        "tags": m.tags,
        "installed": sentinel is not None,
        "install_info": sentinel,
        "manifest_path": str(m.path),
        "models": [
            {
                "source": me.source,
                "name": me.display_name,
                "size_bytes": me.size_bytes,
                "size_human": fmt_bytes(me.size_bytes),
                "min_profile": me.min_profile,
                "role": me.raw.get("role"),
                "dest": me.raw.get("dest"),
                "files": me.raw.get("files"),
            }
            for me in m.models
        ],
    }

    if json_out:
        emit(json.dumps(payload, indent=2))
        return 0

    out = sys.stdout
    out.write(f"{m.title}  ({m.id})\n")
    out.write("=" * (len(m.title) + len(m.id) + 4) + "\n")
    out.write(f"{m.description}\n\n")
    out.write(f"Total size      : {fmt_bytes(m.size_bytes)}\n")
    out.write(f"Min profile     : {m.min_profile}\n")
    out.write(f"Current profile : {profile}")
    out.write("" if profile_meets(m.min_profile, profile) else "  (GATED)")
    out.write("\n")
    out.write(f"Installed       : {'yes' if sentinel else 'no'}\n")
    if sentinel:
        out.write(f"  installed_at  : {sentinel.get('installed_at')}\n")
    out.write(f"Docs            : {m.docs_url}\n")
    if m.tags:
        out.write(f"Tags            : {', '.join(m.tags)}\n")
    out.write(f"Manifest        : {m.path}\n")
    out.write(f"\nModels ({len(m.models)}):\n")
    for me in m.models:
        gate = f"  (>= {me.min_profile})" if me.min_profile else ""
        out.write(
            f"  - [{me.source:<6}] {me.display_name:<40} "
            f"{fmt_bytes(me.size_bytes):>10}{gate}\n"
        )
    out.flush()
    return 0


def cmd_cache_size(json_out: bool) -> int:
    total = dir_size_bytes(CACHE_ROOT)
    if json_out:
        emit(json.dumps({"path": str(CACHE_ROOT), "size_bytes": total}, indent=2))
    else:
        sys.stdout.write(f"{CACHE_ROOT}: {fmt_bytes(total)} ({total} bytes)\n")
    return 0


def cmd_clear_cache(yes: bool, json_out: bool) -> int:
    if not CACHE_ROOT.exists():
        info(f"cache {CACHE_ROOT} does not exist; nothing to clear")
        return 0
    total = dir_size_bytes(CACHE_ROOT)
    if not yes:
        sys.stderr.write(
            f"About to delete {CACHE_ROOT} ({fmt_bytes(total)}).\n"
            f"Re-run with --yes to confirm.\n"
        )
        return 1
    # Walk children explicitly so we don't `rm -rf` a symlinked target.
    for child in CACHE_ROOT.iterdir():
        if child.is_dir() and not child.is_symlink():
            shutil.rmtree(child, ignore_errors=True)
        else:
            try:
                child.unlink()
            except OSError:
                pass
    if json_out:
        emit(json.dumps({"cleared_bytes": total}, indent=2))
    else:
        info(f"cleared {fmt_bytes(total)} from {CACHE_ROOT}")
    return 0


def cmd_refresh(json_out: bool) -> int:
    """
    Re-scan installed state — for now this means:
      - For every Ollama model in every manifest, check if `ollama list` has
        it; if all models for a pack are present and no sentinel exists,
        write one. If a sentinel exists but no models can be confirmed,
        leave it (we don't auto-uninstall — too dangerous).
    Returns a small report.
    """
    report = {"added_sentinels": [], "kept_sentinels": [], "missing": []}
    for m in discover_manifests():
        models_present = 0
        for me in m.models:
            if me.source == "ollama" and ollama_already_has(me.display_name):
                models_present += 1
            elif me.source == "hf":
                dest = Path(os.path.expanduser(str(me.raw.get("dest") or "")))
                files = me.raw.get("files") or []
                if files and all((dest / Path(f).name).exists() for f in files):
                    models_present += 1
        if models_present == len(m.models) and m.models and not is_installed(m.id):
            write_sentinel(m.id, [f"{me.source}:{me.display_name}" for me in m.models])
            report["added_sentinels"].append(m.id)
        elif is_installed(m.id):
            report["kept_sentinels"].append(m.id)
        else:
            report["missing"].append(m.id)

    if json_out:
        emit(json.dumps(report, indent=2))
    else:
        info(f"refresh: added={report['added_sentinels']} kept={report['kept_sentinels']}")
    return 0


# ---------------------------------------------------------------------------
# Argparse wiring
# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="aurum-model-pack",
        description="AurumOS model pack manager (Wave 9).",
    )
    p.add_argument(
        "--json", action="store_true", help="emit JSON instead of human output"
    )
    p.add_argument(
        "--force",
        action="store_true",
        help="bypass profile gates / reinstall over existing sentinel",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="report what would happen without downloading",
    )
    p.add_argument(
        "--yes",
        action="store_true",
        help="non-interactive confirmation (for clear-cache)",
    )

    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list", help="list all model packs and their state")
    s_info = sub.add_parser("info", help="show manifest details for a pack")
    s_info.add_argument("pack_id")
    s_install = sub.add_parser("install", help="install a pack")
    s_install.add_argument("pack_id")
    s_remove = sub.add_parser("remove", help="uninstall a pack and reclaim disk")
    s_remove.add_argument("pack_id")
    sub.add_parser("cache-size", help="total bytes under ~/.cache/aurum/models/")
    sub.add_parser("clear-cache", help="delete entire model cache (warns first)")
    sub.add_parser("refresh", help="re-scan installed state from disk + ollama")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.cmd == "list":
            return cmd_list(args.json)
        if args.cmd == "info":
            return cmd_info(args.pack_id, args.json)
        if args.cmd == "install":
            return install_pack(args.pack_id, force=args.force, dry_run=args.dry_run)
        if args.cmd == "remove":
            return remove_pack(args.pack_id)
        if args.cmd == "cache-size":
            return cmd_cache_size(args.json)
        if args.cmd == "clear-cache":
            return cmd_clear_cache(args.yes, args.json)
        if args.cmd == "refresh":
            return cmd_refresh(args.json)
    except SystemExit:
        raise
    except KeyboardInterrupt:
        sys.stderr.write("\ninterrupted\n")
        return 130
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"[aurum-model-pack] fatal: {exc}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
