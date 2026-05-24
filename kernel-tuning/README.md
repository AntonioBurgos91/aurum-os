# AurumOS Kernel Tuning and Optimizations

This directory contains configuration scripts and configuration rules to optimize Linux kernel parameters for low-latency deep learning training and inference.

## Key Configurations
1. **BORE Scheduler & CPU Performance**: Custom scheduler parameters prioritizing compute workloads. CPU governor defaults to `performance`.
2. **Memory Optimizations**:
   - Transparent HugePages (`always`) to reduce translation lookaside buffer (TLB) misses.
   - Disabling traditional swap to ensure training workloads remain in RAM.
   - ZRAM creation using `zstd` compression algorithm.
   - NUMA balancing parameters tuned for multiple GPU systems.
3. **GPU Interconnect & Network**:
   - GPU IRQ affinity settings to pin handler execution close to CPU sockets.
   - Network tuning (TCP buffers, queue lengths) optimized for high-throughput dataset syncs.
