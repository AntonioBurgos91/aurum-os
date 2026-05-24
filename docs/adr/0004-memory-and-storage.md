# ADR 0004: Memory and Storage Configurations

## Status
Approved

## Context
Deep Learning workloads process massive datasets (GBs to TBs of images, text, and weights) and place severe pressure on system memory. When system RAM runs low and starts swapping, throughput drops by orders of magnitude, causing training processes or model loading to hang. Similarly, filesystem overhead can throttle data loader performance.

## Decision
1. Default file system: **bcachefs** for root partition (supporting snapshots, native compression, multi-device setup).
2. Memory limits:
   - Completely disable traditional disk swap partitions or swap files.
   - Use **ZRAM** compressed with the `zstd` algorithm as a fallback for high-memory spikes.
   - Force Transparent HugePages (THP) to `always` instead of `madvise` to decrease TLB overhead on large memory operations.

## Consequences
- **Pros**:
  - bcachefs offers performance matching ext4/xfs with modern features (snapshots, zstd filesystem-level compression).
  - Disabling physical disk swap protects GPU-bound training jobs from grinding to a halt when memory is exhausted (fails fast or runs in ZRAM instead of paging to disk).
  - HugePages speeds up standard allocations for large tensor tables.
- **Cons**:
  - Out-of-memory (OOM) events will trigger faster if ZRAM is saturated (expected behavior for DL training: it is better to crash and log rather than swap and waste electricity for days).
  - bcachefs is relatively new in the Linux kernel mainline, requiring monitoring of system stability.
