// ==============================================================================
// AurumOS GPU Telemetry Daemon (NVML → D-Bus session bus)
//
// Object path:  /org/aurumos/GpuMonitor
// Interface:    org.aurumos.GpuMonitor
// Bus name:     org.aurumos.GpuMonitorService
//
// Consumers (aurum-dock, aurum-menubar) poll the methods below at ~1 Hz.
// Falls back to a deterministic simulation when no NVIDIA hardware is present
// so the UI is still developable on a non-NVIDIA machine.
// ==============================================================================

use std::sync::Arc;
use std::time::Duration;

use nvml_wrapper::{enum_wrappers::device::TemperatureSensor, Nvml};
use tokio::sync::Mutex;
use zbus::{connection::Builder, interface};

#[derive(Debug, Clone)]
struct GpuState {
    name: String,
    utilization: u32,    // %
    vram_total: u64,     // bytes
    vram_used: u64,      // bytes
    temperature: u32,    // °C
    power_draw_mw: u32,  // milliwatts
}

impl Default for GpuState {
    fn default() -> Self {
        Self {
            name: "Initializing…".into(),
            utilization: 0,
            vram_total: 0,
            vram_used: 0,
            temperature: 0,
            power_draw_mw: 0,
        }
    }
}

struct GpuMonitor {
    state: Arc<Mutex<GpuState>>,
}

// zbus 4 maps Rust `fn search` → wire `Search` (PascalCase) by default.
// The C++ clients (aurum-dock, aurum-menubar, aurum-settings) call the
// snake_case names that match the docs/READMEs, so we explicitly pin each
// method's wire name here to keep the documented contract.
#[interface(name = "org.aurumos.GpuMonitor")]
impl GpuMonitor {
    #[zbus(name = "gpu_name")]
    async fn gpu_name(&self) -> String         { self.state.lock().await.name.clone() }
    #[zbus(name = "gpu_utilization")]
    async fn gpu_utilization(&self) -> u32     { self.state.lock().await.utilization }
    #[zbus(name = "vram_total")]
    async fn vram_total(&self) -> u64          { self.state.lock().await.vram_total }
    #[zbus(name = "vram_used")]
    async fn vram_used(&self) -> u64           { self.state.lock().await.vram_used }
    #[zbus(name = "temperature")]
    async fn temperature(&self) -> u32         { self.state.lock().await.temperature }
    #[zbus(name = "power_draw_mw")]
    async fn power_draw_mw(&self) -> u32       { self.state.lock().await.power_draw_mw }
}

// Pull one round of metrics from a real NVML device into the shared state.
async fn poll_real(nvml: &Nvml, state: &Arc<Mutex<GpuState>>) {
    let device = match nvml.device_by_index(0) {
        Ok(d) => d,
        Err(e) => {
            log::warn!("device_by_index(0) failed: {e}");
            return;
        }
    };

    let name        = device.name().unwrap_or_else(|_| "NVIDIA GPU".into());
    let util        = device.utilization_rates().map(|r| r.gpu).unwrap_or(0);
    let mem         = device.memory_info().ok();
    let temp        = device.temperature(TemperatureSensor::Gpu).unwrap_or(0);
    let power       = device.power_usage().unwrap_or(0);

    let mut s = state.lock().await;
    s.name          = name;
    s.utilization   = util;
    s.vram_total    = mem.as_ref().map(|m| m.total).unwrap_or(0);
    s.vram_used     = mem.as_ref().map(|m| m.used).unwrap_or(0);
    s.temperature   = temp;
    s.power_draw_mw = power;
}

// Headless simulation: a slow sinusoid so the UI shows life.
fn step_sim(sim_angle: &mut f64, s: &mut GpuState) {
    *sim_angle += 0.1;
    s.name          = "Simulated RTX 4090".into();
    s.utilization   = (50.0 + 30.0 * sim_angle.sin()) as u32;
    s.vram_total    = 25_769_803_776; // 24 GiB
    s.vram_used     = (4_000_000_000.0 + 2_000_000_000.0 * sim_angle.cos()) as u64;
    s.temperature   = (45.0 + 10.0 * sim_angle.sin()) as u32;
    s.power_draw_mw = (120_000.0 + 80_000.0 * sim_angle.sin().abs()) as u32;
}

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    log::info!("starting aurum-gpu-monitor");

    let shared = Arc::new(Mutex::new(GpuState::default()));

    // Try NVML once; if it doesn't initialize we stay in sim mode forever.
    let nvml = match Nvml::init() {
        Ok(n) => {
            log::info!("NVML initialized");
            Some(n)
        }
        Err(e) => {
            log::warn!("NVML unavailable ({e}); running in simulation mode");
            None
        }
    };

    // Polling task
    let poll_state = shared.clone();
    tokio::spawn(async move {
        let mut sim_angle = 0.0_f64;
        loop {
            match &nvml {
                Some(nvml) => poll_real(nvml, &poll_state).await,
                None => {
                    let mut s = poll_state.lock().await;
                    step_sim(&mut sim_angle, &mut s);
                }
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

    // Block on SIGTERM/SIGINT instead of an infinite sleep so systemd can shut us down cleanly.
    tokio::signal::ctrl_c().await?;
    log::info!("shutdown requested");
    Ok(())
}
