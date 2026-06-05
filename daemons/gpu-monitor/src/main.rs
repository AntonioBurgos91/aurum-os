// ==============================================================================
// AurumOS System Telemetry Daemon  (NVIDIA NVML · AMD sysfs · CPU/RAM fallback)
//
// Object path:  /org/aurumos/GpuMonitor
// Interface:    org.aurumos.GpuMonitor
// Bus name:     org.aurumos.GpuMonitorService
//
// Consumers (aurum-dock, aurum-menubar) poll the methods below at ~1 Hz.
//
// Telemetry source is auto-detected at startup, in priority order:
//   1. NVML        — NVIDIA GPU (utilization, VRAM, temp, power) via libnvidia-ml
//   2. AMD sysfs   — Radeon/amdgpu via /sys/class/drm + hwmon (real iGPU/dGPU data)
//   3. CPU/RAM     — /proc/stat + /proc/meminfo + hwmon (k10temp/coretemp)
//
// Every value is REAL on every path. There is no synthetic/simulated mode:
// the `source_kind` method tells the UI which backend is live so it can label
// the readout honestly ("GPU" vs "iGPU" vs "CPU").
// ==============================================================================

use std::sync::Arc;
use std::time::Duration;

use nvml_wrapper::{enum_wrappers::device::TemperatureSensor, Nvml};
use tokio::sync::Mutex;
use zbus::{connection::Builder, interface};

use gpu_monitor::{
    cpu_busy_from_jiffies, microwatts_to_milliwatts, millidegrees_to_celsius, parse_meminfo,
    parse_proc_stat_cpu_line, GpuState,
};

struct GpuMonitor {
    state: Arc<Mutex<GpuState>>,
}

// zbus 4 maps Rust `fn search` → wire `Search` (PascalCase) by default.
// The C++ clients call the snake_case names that match the docs, so we pin
// each method's wire name explicitly to keep the documented contract.
#[interface(name = "org.aurumos.GpuMonitor")]
impl GpuMonitor {
    #[zbus(name = "gpu_name")]
    async fn gpu_name(&self) -> String {
        self.state.lock().await.name.clone()
    }
    #[zbus(name = "gpu_utilization")]
    async fn gpu_utilization(&self) -> u32 {
        self.state.lock().await.utilization
    }
    #[zbus(name = "vram_total")]
    async fn vram_total(&self) -> u64 {
        self.state.lock().await.vram_total
    }
    #[zbus(name = "vram_used")]
    async fn vram_used(&self) -> u64 {
        self.state.lock().await.vram_used
    }
    #[zbus(name = "temperature")]
    async fn temperature(&self) -> u32 {
        self.state.lock().await.temperature
    }
    #[zbus(name = "power_draw_mw")]
    async fn power_draw_mw(&self) -> u32 {
        self.state.lock().await.power_draw_mw
    }
    // NEW: lets the UI label the readout honestly (GPU vs iGPU vs CPU).
    #[zbus(name = "source_kind")]
    async fn source_kind(&self) -> String {
        self.state.lock().await.source_kind.clone()
    }
}

// ── small sysfs helpers ───────────────────────────────────────────────────
fn read_str(path: &str) -> Option<String> {
    std::fs::read_to_string(path)
        .ok()
        .map(|s| s.trim().to_string())
}
fn read_u64(path: &str) -> Option<u64> {
    read_str(path).and_then(|s| s.parse().ok())
}

// ── Backend selection ─────────────────────────────────────────────────────
enum Backend {
    // Nvml is ~9.7 KB; box it so the enum isn't dominated by the variant that's
    // unused on the common (non-NVIDIA) path. Keeps clippy::large_enum_variant
    // happy and the daemon's CI gate (`clippy -D warnings`) green.
    Nvml(Box<Nvml>),
    AmdSysfs(AmdPaths),
    Cpu(CpuReader),
}

// ── AMD / amdgpu via sysfs ─────────────────────────────────────────────────
// Reads real iGPU/dGPU telemetry from /sys/class/drm/cardN/device and the
// matching hwmon node. No root needed — these are world-readable.
struct AmdPaths {
    card_dir: String, // /sys/class/drm/cardN/device
    hwmon_temp: Option<String>,
    hwmon_power: Option<String>,
    name: String,
}

fn detect_amd() -> Option<AmdPaths> {
    // Find the first card exposing gpu_busy_percent (an amdgpu device).
    for n in 0..8 {
        let dir = format!("/sys/class/drm/card{n}/device");
        if std::path::Path::new(&format!("{dir}/gpu_busy_percent")).exists() {
            // Locate the hwmon subdir for this device (temp/power inputs).
            let mut hwmon_temp = None;
            let mut hwmon_power = None;
            let hwmon_root = format!("{dir}/hwmon");
            if let Ok(entries) = std::fs::read_dir(&hwmon_root) {
                for e in entries.flatten() {
                    let p = e.path();
                    let t = format!("{}/temp1_input", p.display());
                    if std::path::Path::new(&t).exists() {
                        hwmon_temp = Some(t);
                    }
                    let pw = format!("{}/power1_average", p.display());
                    if std::path::Path::new(&pw).exists() {
                        hwmon_power = Some(pw);
                    } else {
                        let pw2 = format!("{}/power1_input", p.display());
                        if std::path::Path::new(&pw2).exists() {
                            hwmon_power = Some(pw2);
                        }
                    }
                }
            }
            // Device marketing name, if the kernel exposes it.
            let name = read_str(&format!("{dir}/product_name"))
                .filter(|s| !s.is_empty())
                .unwrap_or_else(|| "AMD Radeon (amdgpu)".into());
            return Some(AmdPaths {
                card_dir: dir,
                hwmon_temp,
                hwmon_power,
                name,
            });
        }
    }
    None
}

async fn poll_amd(p: &AmdPaths, state: &Arc<Mutex<GpuState>>) {
    let util = read_u64(&format!("{}/gpu_busy_percent", p.card_dir)).unwrap_or(0) as u32;
    let vram_total = read_u64(&format!("{}/mem_info_vram_total", p.card_dir)).unwrap_or(0);
    let vram_used = read_u64(&format!("{}/mem_info_vram_used", p.card_dir)).unwrap_or(0);
    let temp = p
        .hwmon_temp
        .as_ref()
        .and_then(|f| read_u64(f))
        .map(millidegrees_to_celsius)
        .unwrap_or(0);
    let power_mw = p
        .hwmon_power
        .as_ref()
        .and_then(|f| read_u64(f))
        .map(microwatts_to_milliwatts) // µW → mW
        .unwrap_or(0);

    let mut s = state.lock().await;
    s.name = p.name.clone();
    s.source_kind = "amd-sysfs".into();
    s.utilization = util;
    s.vram_total = vram_total;
    s.vram_used = vram_used;
    s.temperature = temp;
    s.power_draw_mw = power_mw;
}

// ── CPU / RAM fallback ─────────────────────────────────────────────────────
// Real CPU busy% (delta of /proc/stat jiffies), RAM total/used from
// /proc/meminfo, and package temperature from k10temp/coretemp hwmon.
struct CpuReader {
    name: String,
    hwmon_temp: Option<String>,
    prev_idle: u64,
    prev_total: u64,
}

fn detect_cpu() -> CpuReader {
    let name = std::fs::read_to_string("/proc/cpuinfo")
        .ok()
        .and_then(|c| {
            c.lines()
                .find(|l| l.starts_with("model name"))
                .and_then(|l| l.split(':').nth(1))
                .map(|s| s.trim().to_string())
        })
        .unwrap_or_else(|| "CPU".into());

    // Find a package-temp hwmon (k10temp on AMD, coretemp on Intel).
    let mut hwmon_temp = None;
    if let Ok(entries) = std::fs::read_dir("/sys/class/hwmon") {
        for e in entries.flatten() {
            let dir = e.path();
            let nm = read_str(&format!("{}/name", dir.display())).unwrap_or_default();
            if nm == "k10temp" || nm == "coretemp" || nm == "acpitz" {
                let t = format!("{}/temp1_input", dir.display());
                if std::path::Path::new(&t).exists() {
                    hwmon_temp = Some(t);
                    if nm != "acpitz" {
                        break; // prefer a real CPU sensor over acpitz
                    }
                }
            }
        }
    }
    CpuReader {
        name,
        hwmon_temp,
        prev_idle: 0,
        prev_total: 0,
    }
}

fn read_cpu_busy(reader: &mut CpuReader) -> u32 {
    // Read /proc/stat; the pure jiffies→% math lives in the library so it can
    // be unit-tested without touching the filesystem.
    let stat = match std::fs::read_to_string("/proc/stat") {
        Ok(s) => s,
        Err(_) => return 0,
    };
    let vals = parse_proc_stat_cpu_line(&stat);
    let (busy, idle, total) = cpu_busy_from_jiffies(&vals, reader.prev_idle, reader.prev_total);
    reader.prev_idle = idle;
    reader.prev_total = total;
    busy
}

fn read_mem() -> (u64, u64) {
    // Read /proc/meminfo; the parsing lives in the library for unit testing.
    match std::fs::read_to_string("/proc/meminfo") {
        Ok(info) => parse_meminfo(&info),
        Err(_) => (0, 0),
    }
}

async fn poll_cpu(reader: &mut CpuReader, state: &Arc<Mutex<GpuState>>) {
    let busy = read_cpu_busy(reader);
    let (mem_total, mem_used) = read_mem();
    let temp = reader
        .hwmon_temp
        .as_ref()
        .and_then(|f| read_u64(f))
        .map(millidegrees_to_celsius)
        .unwrap_or(0);

    let mut s = state.lock().await;
    s.name = reader.name.clone();
    s.source_kind = "cpu".into();
    s.utilization = busy;
    s.vram_total = mem_total;
    s.vram_used = mem_used;
    s.temperature = temp;
    s.power_draw_mw = 0; // no portable per-package power on the CPU path
}

// Pull one round of metrics from a real NVML device into the shared state.
async fn poll_nvml(nvml: &Nvml, state: &Arc<Mutex<GpuState>>) {
    let device = match nvml.device_by_index(0) {
        Ok(d) => d,
        Err(e) => {
            log::warn!("device_by_index(0) failed: {e}");
            return;
        }
    };
    let name = device.name().unwrap_or_else(|_| "NVIDIA GPU".into());
    let util = device.utilization_rates().map(|r| r.gpu).unwrap_or(0);
    let mem = device.memory_info().ok();
    let temp = device.temperature(TemperatureSensor::Gpu).unwrap_or(0);
    let power = device.power_usage().unwrap_or(0);

    let mut s = state.lock().await;
    s.name = name;
    s.source_kind = "nvml".into();
    s.utilization = util;
    s.vram_total = mem.as_ref().map(|m| m.total).unwrap_or(0);
    s.vram_used = mem.as_ref().map(|m| m.used).unwrap_or(0);
    s.temperature = temp;
    s.power_draw_mw = power;
}

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    log::info!("starting aurum-gpu-monitor");

    let shared = Arc::new(Mutex::new(GpuState::default()));

    // Detect the best available telemetry backend, in priority order.
    let backend = match Nvml::init() {
        Ok(n) => {
            log::info!("backend: NVML (NVIDIA GPU)");
            Backend::Nvml(Box::new(n))
        }
        Err(e) => {
            log::info!("NVML unavailable ({e}); trying amdgpu sysfs");
            match detect_amd() {
                Some(amd) => {
                    log::info!("backend: amdgpu sysfs ({})", amd.name);
                    Backend::AmdSysfs(amd)
                }
                None => {
                    let cpu = detect_cpu();
                    log::info!("backend: CPU/RAM fallback ({})", cpu.name);
                    Backend::Cpu(cpu)
                }
            }
        }
    };

    // Polling task — every value published is real for the active backend.
    let poll_state = shared.clone();
    tokio::spawn(async move {
        let mut backend = backend;
        loop {
            match &mut backend {
                Backend::Nvml(nvml) => poll_nvml(nvml, &poll_state).await,
                Backend::AmdSysfs(amd) => poll_amd(amd, &poll_state).await,
                Backend::Cpu(cpu) => poll_cpu(cpu, &poll_state).await,
            }
            tokio::time::sleep(Duration::from_millis(1000)).await;
        }
    });

    // Publish on the session bus.
    let _conn = Builder::session()?
        .name("org.aurumos.GpuMonitorService")?
        .serve_at("/org/aurumos/GpuMonitor", GpuMonitor { state: shared })?
        .build()
        .await?;

    log::info!("D-Bus interface ready at org.aurumos.GpuMonitorService /org/aurumos/GpuMonitor");

    tokio::signal::ctrl_c().await?;
    log::info!("shutdown requested");
    Ok(())
}
