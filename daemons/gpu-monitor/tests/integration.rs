// =====================================================================
// gpu-monitor integration tests
//
// These exercise the REAL pure-logic functions exported from the crate
// library (`gpu_monitor::*`) — jiffies→% CPU math, /proc/stat and
// /proc/meminfo parsing, hwmon unit conversions, and the GpuState shape.
// Previously these were "mirror" tests that re-implemented the math; now
// they call the production code directly, so a regression in the daemon's
// logic actually fails a test (and coverage attributes back to src/lib.rs).
//
// The real-hardware NVML path stays #[ignore] — it needs a CUDA host.
// =====================================================================

use gpu_monitor::{
    cpu_busy_from_jiffies, microwatts_to_milliwatts, millidegrees_to_celsius, parse_meminfo,
    parse_proc_stat_cpu_line, GpuState,
};

#[test]
fn gpu_state_default_is_zeroed_numeric_fields() {
    // Before the first poll the D-Bus surface must report "no data yet".
    let s = GpuState::default();
    assert_eq!(s.utilization, 0);
    assert_eq!(s.vram_total, 0);
    assert_eq!(s.vram_used, 0);
    assert_eq!(s.temperature, 0);
    assert_eq!(s.power_draw_mw, 0);
    assert_eq!(s.source_kind, "none");
}

#[test]
fn gpu_state_is_clone_eq() {
    // The D-Bus methods clone the state under a mutex; Clone must round-trip.
    let s = GpuState {
        name: "AMD Radeon (amdgpu)".into(),
        source_kind: "amd-sysfs".into(),
        utilization: 42,
        vram_total: 536_870_912,
        vram_used: 100_000_000,
        temperature: 58,
        power_draw_mw: 12_000,
    };
    assert_eq!(s, s.clone());
}

#[test]
fn cpu_busy_75_percent_from_jiffies_delta() {
    // With prev=(0,0) there IS a delta vs zero, so the first sample already
    // reports a value: dTotal=1000, dIdle=850 → 100*(1000-850)/1000 = 15%.
    // (The daemon's very first reading is against prev=0; this documents that.)
    let baseline = [100u64, 0, 50, 800, 50]; // total=1000, idle+iowait=850
    let (busy0, idle0, total0) = cpu_busy_from_jiffies(&baseline, 0, 0);
    assert_eq!(busy0, 15);
    assert_eq!(idle0, 850);
    assert_eq!(total0, 1000);

    // Next sample vs the previous one: total=2000 (Δ1000), idle+iowait=1100
    // (Δ250) → busy = 100*(1000-250)/1000 = 75%.
    let next = [850u64, 0, 50, 1050, 50];
    let (busy1, _, _) = cpu_busy_from_jiffies(&next, idle0, total0);
    assert_eq!(busy1, 75);
}

#[test]
fn cpu_busy_is_zero_when_no_delta() {
    // Same totals twice → dTotal=0 → 0% (and no panic / div-by-zero).
    let vals = [100u64, 0, 50, 800, 50];
    let (busy, idle, total) = cpu_busy_from_jiffies(&vals, 850, 1000);
    assert_eq!(busy, 0);
    assert_eq!(idle, 850);
    assert_eq!(total, 1000);
}

#[test]
fn cpu_busy_is_clamped_and_tolerates_short_input() {
    // Fewer than 5 fields → safe 0, carrying prev values forward.
    let (busy, idle, total) = cpu_busy_from_jiffies(&[1, 2, 3], 7, 9);
    assert_eq!((busy, idle, total), (0, 7, 9));
    // Fully busy: idle unchanged, total grows → ~100%.
    let (busy_full, _, _) = cpu_busy_from_jiffies(&[1100, 0, 0, 800, 50], 850, 1000);
    assert_eq!(busy_full, 100);
}

#[test]
fn parse_proc_stat_extracts_cpu_jiffies() {
    let stat = "cpu  100 0 50 800 50 0 0 0 0 0\ncpu0 25 0 12 200 12\nintr 12345\n";
    let vals = parse_proc_stat_cpu_line(stat);
    assert_eq!(vals, vec![100, 0, 50, 800, 50, 0, 0, 0, 0, 0]);
    // Wire it to the math: this is exactly what read_cpu_busy does. Against
    // prev=(0,0) the delta is the absolute jiffies → 15% for this sample.
    let (busy, _, _) = cpu_busy_from_jiffies(&vals, 0, 0);
    assert_eq!(busy, 15);
    // Malformed first line → empty.
    assert!(parse_proc_stat_cpu_line("garbage\n").is_empty());
}

#[test]
fn meminfo_used_is_total_minus_available() {
    let info = "\
MemTotal:       32182036 kB
MemFree:         1000000 kB
MemAvailable:   24692352 kB
Buffers:          500000 kB
";
    let (total, used) = parse_meminfo(info);
    assert_eq!(total, 32_182_036 * 1024);
    assert_eq!(used, (32_182_036 - 24_692_352) * 1024);
    assert!(used <= total);
}

#[test]
fn meminfo_missing_fields_are_zero() {
    let (total, used) = parse_meminfo("SomethingElse: 123 kB\n");
    assert_eq!(total, 0);
    assert_eq!(used, 0);
}

#[test]
fn hwmon_millidegrees_convert_to_celsius() {
    assert_eq!(millidegrees_to_celsius(71_250), 71);
    assert_eq!(millidegrees_to_celsius(57_000), 57);
    assert_eq!(millidegrees_to_celsius(0), 0);
}

#[test]
fn hwmon_microwatts_convert_to_milliwatts() {
    assert_eq!(microwatts_to_milliwatts(25_000_000), 25_000);
    assert_eq!(microwatts_to_milliwatts(999), 0); // sub-mW rounds down
}

#[tokio::test]
#[ignore] // run with `cargo test -- --ignored` on a CUDA host
async fn nvml_initializes_on_real_gpu() {
    // Documentation test for the NVML path. On a real NVIDIA host, Nvml::init()
    // returns Ok with device_count >= 1 and device_by_index(0) succeeds with
    // plausible util/temp/power. Not linkable without hardware in CI.
    eprintln!("Run aurum-gpu-monitor on a real NVIDIA GPU; assert util/temp/power are plausible.");
}
