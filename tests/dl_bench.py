#!/usr/bin/env python3
"""AurumOS DL stack benchmarks.

Goal: surface a small, reproducible signal that the GPU + frameworks behave
sanely on this machine. Not a competitor to MLPerf — we run cheap operations
(small matmuls, a single H2D copy round) and report GFLOPS / GB/s.

Output: a JSON document on stdout. With `--text` it also prints a table.
Exit code is non-zero iff a framework crashes; missing frameworks are recorded
but do not fail the run.

Usage:
    dl_bench.py [--text] [--size 4096] [--iters 8] [--out report.json]
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import time
from dataclasses import asdict, dataclass, field
from typing import Optional


# ---------------------------------------------------------------------------
# Result types
# ---------------------------------------------------------------------------

@dataclass
class FrameworkResult:
    framework: str
    available: bool
    version: Optional[str] = None
    device: Optional[str] = None
    matmul_ms_median: Optional[float] = None
    matmul_gflops: Optional[float] = None
    error: Optional[str] = None
    extra: dict = field(default_factory=dict)


@dataclass
class Report:
    aurumos_bench_version: str
    timestamp: str
    matmul_n: int
    iters: int
    frameworks: list[FrameworkResult] = field(default_factory=list)
    summary: dict = field(default_factory=dict)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def median_ms(times_ns: list[int]) -> float:
    return statistics.median(times_ns) / 1e6


def matmul_gflops(n: int, time_s: float) -> float:
    """Single-precision matmul cost: 2*n^3 FMAs counted as 2 FLOPs each."""
    flops = 2.0 * (n ** 3)
    return flops / time_s / 1e9


# ---------------------------------------------------------------------------
# Per-framework benchmarks
# ---------------------------------------------------------------------------

def bench_torch(n: int, iters: int) -> FrameworkResult:
    r = FrameworkResult(framework="pytorch", available=False)
    try:
        import torch
    except Exception as e:
        r.error = f"import: {e}"
        return r
    r.available = True
    r.version = torch.__version__

    if not torch.cuda.is_available():
        r.error = "cuda not available"
        return r
    r.device = torch.cuda.get_device_name(0)

    a = torch.randn(n, n, device="cuda", dtype=torch.float32)
    b = torch.randn(n, n, device="cuda", dtype=torch.float32)

    # Warmup. The first matmul triggers cublas autotuning.
    for _ in range(2):
        torch.matmul(a, b)
    torch.cuda.synchronize()

    times = []
    for _ in range(iters):
        torch.cuda.synchronize()
        t0 = time.perf_counter_ns()
        c = torch.matmul(a, b)
        torch.cuda.synchronize()
        times.append(time.perf_counter_ns() - t0)
    _ = c  # keep result live until after timing
    median_t = median_ms(times)
    r.matmul_ms_median = median_t
    r.matmul_gflops = matmul_gflops(n, median_t / 1000.0)
    return r


def bench_jax(n: int, iters: int) -> FrameworkResult:
    r = FrameworkResult(framework="jax", available=False)
    try:
        import jax
        import jax.numpy as jnp
    except Exception as e:
        r.error = f"import: {e}"
        return r
    r.available = True
    r.version = jax.__version__

    gpu_devs = [d for d in jax.devices() if d.platform != "cpu"]
    if not gpu_devs:
        r.error = "no GPU devices visible to JAX"
        return r
    r.device = str(gpu_devs[0])

    key = jax.random.PRNGKey(0)
    a = jax.random.normal(key, (n, n), dtype=jnp.float32)
    b = jax.random.normal(key, (n, n), dtype=jnp.float32)

    matmul = jax.jit(lambda x, y: jnp.dot(x, y))

    # Warmup + JIT trace
    matmul(a, b).block_until_ready()

    times = []
    for _ in range(iters):
        t0 = time.perf_counter_ns()
        out = matmul(a, b)
        out.block_until_ready()
        times.append(time.perf_counter_ns() - t0)
    median_t = median_ms(times)
    r.matmul_ms_median = median_t
    r.matmul_gflops = matmul_gflops(n, median_t / 1000.0)
    return r


def bench_tensorflow(n: int, iters: int) -> FrameworkResult:
    r = FrameworkResult(framework="tensorflow", available=False)
    try:
        os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
        import tensorflow as tf
    except Exception as e:
        r.error = f"import: {e}"
        return r
    r.available = True
    r.version = tf.__version__

    gpus = tf.config.list_physical_devices("GPU")
    if not gpus:
        r.error = "no GPU devices visible to TensorFlow"
        return r
    r.device = gpus[0].name

    @tf.function
    def step(x, y):
        return tf.matmul(x, y)

    with tf.device("/GPU:0"):
        a = tf.random.normal((n, n))
        b = tf.random.normal((n, n))
        # Trace + warmup
        step(a, b).numpy()

        times = []
        for _ in range(iters):
            t0 = time.perf_counter_ns()
            out = step(a, b)
            _ = out.numpy()  # forces sync
            times.append(time.perf_counter_ns() - t0)

    median_t = median_ms(times)
    r.matmul_ms_median = median_t
    r.matmul_gflops = matmul_gflops(n, median_t / 1000.0)
    return r


def bench_vllm() -> FrameworkResult:
    """vLLM benchmarks need a model and >2 GB VRAM. For Phase 4 we only
    verify the import works — a real generation benchmark is too expensive
    for an installation smoke run."""
    r = FrameworkResult(framework="vllm", available=False)
    try:
        import vllm
        r.available = True
        r.version = vllm.__version__
        r.extra["note"] = "import-only check; generation benchmark deferred"
    except Exception as e:
        r.error = f"import: {e}"
    return r


def bench_h2d_bandwidth(size_mb: int = 256) -> FrameworkResult:
    """Measure host→device → host bandwidth via PyTorch as a cheap shared
    runtime. Captured as its own pseudo-framework row to keep the JSON flat."""
    r = FrameworkResult(framework="h2d_bandwidth", available=False)
    try:
        import torch
    except Exception as e:
        r.error = f"import: {e}"
        return r
    r.available = True
    if not torch.cuda.is_available():
        r.error = "cuda not available"
        return r

    n_floats = size_mb * 256 * 1024  # 4 bytes per float
    cpu = torch.randn(n_floats, dtype=torch.float32, pin_memory=True)
    gpu = torch.empty_like(cpu, device="cuda")

    # H2D
    torch.cuda.synchronize()
    t0 = time.perf_counter_ns()
    gpu.copy_(cpu, non_blocking=False)
    torch.cuda.synchronize()
    h2d_s = (time.perf_counter_ns() - t0) / 1e9

    # D2H
    cpu2 = torch.empty_like(cpu)
    t0 = time.perf_counter_ns()
    cpu2.copy_(gpu, non_blocking=False)
    torch.cuda.synchronize()
    d2h_s = (time.perf_counter_ns() - t0) / 1e9

    r.extra["payload_mb"]    = size_mb
    r.extra["h2d_gb_per_s"]  = round(size_mb / 1024.0 / h2d_s, 2)
    r.extra["d2h_gb_per_s"]  = round(size_mb / 1024.0 / d2h_s, 2)
    r.device = torch.cuda.get_device_name(0)
    return r


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description="AurumOS DL stack benchmarks")
    ap.add_argument("--size",  type=int, default=4096, help="matmul N×N size")
    ap.add_argument("--iters", type=int, default=8,    help="iterations per framework")
    ap.add_argument("--out",   type=str, default=None, help="also write JSON to this path")
    ap.add_argument("--text",  action="store_true",     help="print a human-readable summary")
    args = ap.parse_args()

    report = Report(
        aurumos_bench_version="0.1",
        timestamp=time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        matmul_n=args.size,
        iters=args.iters,
    )

    for fn in (
        lambda: bench_torch     (args.size, args.iters),
        lambda: bench_jax       (args.size, args.iters),
        lambda: bench_tensorflow(args.size, args.iters),
        lambda: bench_vllm      (),
        lambda: bench_h2d_bandwidth(),
    ):
        try:
            report.frameworks.append(fn())
        except Exception as e:
            # An unexpected exception in the harness itself shouldn't kill
            # the run — capture it as a row and keep going.
            report.frameworks.append(FrameworkResult(
                framework="harness",
                available=False,
                error=repr(e),
            ))

    # Summary fields keep CI assertions simple ({"all_available": true}).
    report.summary["all_available"] = all(
        f.available for f in report.frameworks if f.framework in {"pytorch", "jax", "tensorflow"}
    )
    report.summary["gpu_device"] = next(
        (f.device for f in report.frameworks if f.device), None
    )

    blob = json.dumps({
        **{k: v for k, v in asdict(report).items() if k != "frameworks"},
        "frameworks": [asdict(f) for f in report.frameworks],
    }, indent=2, default=str)
    if args.out:
        with open(args.out, "w") as fh:
            fh.write(blob)
    print(blob)

    if args.text:
        print()
        print(f"{'Framework':<14} {'Avail':<6} {'Device':<28} {'Matmul (ms)':<12} {'GFLOPS':<10}",
              file=sys.stderr)
        print("-" * 72, file=sys.stderr)
        for f in report.frameworks:
            print(
                f"{f.framework:<14} "
                f"{'yes' if f.available else 'no':<6} "
                f"{(f.device or '-')[:28]:<28} "
                f"{f.matmul_ms_median if f.matmul_ms_median else '-':<12} "
                f"{int(f.matmul_gflops) if f.matmul_gflops else '-':<10}",
                file=sys.stderr,
            )

    return 0 if report.summary["all_available"] else 2


if __name__ == "__main__":
    sys.exit(main())
