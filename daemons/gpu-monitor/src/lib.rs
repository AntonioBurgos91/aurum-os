//! Pure, hardware-independent telemetry logic for aurum-gpu-monitor.
//!
//! The daemon binary (`main.rs`) wires these helpers to real backends
//! (NVML / amdgpu sysfs / /proc). Everything here is deterministic and unit
//! testable without a GPU or root: parsing /proc/stat + /proc/meminfo, unit
//! conversions (millidegrees→°C, micro/milliwatts→mW), and the shared
//! `GpuState` shape. Keeping them in the library (vs private in main.rs) lets
//! the integration tests exercise the REAL code and coverage attribute it.

/// Snapshot published over D-Bus. Mirrors the daemon's internal state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GpuState {
    pub name: String,
    pub source_kind: String, // "nvml" | "amd-sysfs" | "cpu" | "none"
    pub utilization: u32,    // % busy
    pub vram_total: u64,     // bytes (or RAM total on the cpu backend)
    pub vram_used: u64,      // bytes (or RAM used on the cpu backend)
    pub temperature: u32,    // °C
    pub power_draw_mw: u32,  // milliwatts (0 if unmeasurable)
}

impl Default for GpuState {
    fn default() -> Self {
        Self {
            name: "Initializing…".into(),
            source_kind: "none".into(),
            utilization: 0,
            vram_total: 0,
            vram_used: 0,
            temperature: 0,
            power_draw_mw: 0,
        }
    }
}

/// CPU busy% from two consecutive /proc/stat readings.
///
/// `vals` are the whitespace-separated numbers after the leading "cpu" token
/// (user, nice, system, idle, iowait, ...). `prev_idle`/`prev_total` carry the
/// previous sample; returns (busy_percent, new_idle, new_total). Busy is
/// clamped to 0..=100. Returns 0% busy when there's no delta (first sample or
/// an idle tick), never panics, and tolerates a short `vals`.
pub fn cpu_busy_from_jiffies(vals: &[u64], prev_idle: u64, prev_total: u64) -> (u32, u64, u64) {
    if vals.len() < 5 {
        return (0, prev_idle, prev_total);
    }
    let idle = vals[3] + vals.get(4).copied().unwrap_or(0); // idle + iowait
    let total: u64 = vals.iter().sum();

    let d_total = total.saturating_sub(prev_total);
    let d_idle = idle.saturating_sub(prev_idle);

    if d_total == 0 {
        return (0, idle, total);
    }
    let busy = 100.0 * (d_total.saturating_sub(d_idle) as f64) / (d_total as f64);
    (busy.round().clamp(0.0, 100.0) as u32, idle, total)
}

/// Parse the first "cpu " line of /proc/stat into the jiffy values after the
/// leading token. Returns an empty vec if the line is missing/malformed.
pub fn parse_proc_stat_cpu_line(stat: &str) -> Vec<u64> {
    let line = stat.lines().next().unwrap_or("");
    if !line.starts_with("cpu") {
        return Vec::new();
    }
    line.split_whitespace()
        .skip(1)
        .filter_map(|v| v.parse().ok())
        .collect()
}

/// Parse /proc/meminfo contents into (total_bytes, used_bytes), where
/// used = MemTotal - MemAvailable. Missing fields are treated as 0.
pub fn parse_meminfo(info: &str) -> (u64, u64) {
    let mut total_kb = 0u64;
    let mut avail_kb = 0u64;
    for line in info.lines() {
        if let Some(v) = line.strip_prefix("MemTotal:") {
            total_kb = v
                .split_whitespace()
                .next()
                .and_then(|x| x.parse().ok())
                .unwrap_or(0);
        } else if let Some(v) = line.strip_prefix("MemAvailable:") {
            avail_kb = v
                .split_whitespace()
                .next()
                .and_then(|x| x.parse().ok())
                .unwrap_or(0);
        }
    }
    let total = total_kb * 1024;
    let used = total.saturating_sub(avail_kb * 1024);
    (total, used)
}

/// hwmon temperature is in millidegrees Celsius; convert to whole °C.
pub fn millidegrees_to_celsius(millideg: u64) -> u32 {
    (millideg / 1000) as u32
}

/// hwmon power inputs are in microwatts (amdgpu) — convert to milliwatts.
pub fn microwatts_to_milliwatts(uw: u64) -> u32 {
    (uw / 1000) as u32
}
