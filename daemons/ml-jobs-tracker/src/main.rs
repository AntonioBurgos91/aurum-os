// ==============================================================================
// AurumOS ML jobs tracker
//
// Polls the user's MLflow tracking server every ~10s and republishes the
// recent / active runs on the session bus so:
//   * aurum-menubar's "active jobs" badge can pulse on RUNNING.
//   * aurum-notifications can fire when a run transitions to FINISHED/FAILED.
//
// The daemon also re-reads ~/.config/aurum/mlops.toml on SIGHUP and on every
// poll cycle (cheap), so aurum-settings's "Save" round-trips without needing
// systemctl reload.
//
// D-Bus surface:
//   bus name    org.aurumos.MlJobsTrackerService
//   object      /org/aurumos/MlJobsTracker
//   interface   org.aurumos.MlJobsTracker
//   methods     runs() -> a(sssssx)   (run_id, experiment_id, name, status, ts_iso, duration_s)
//               tracking_uri() -> s
//               last_error() -> s
//               poke()  -> ()         (force an immediate refresh)
// ==============================================================================

use ml_jobs_tracker::{config, mlflow};

use std::sync::Arc;
use std::time::Duration;

use tokio::sync::Mutex;
use zbus::{connection::Builder, interface};

use ml_jobs_tracker::config::Config;
use ml_jobs_tracker::mlflow::RunSummary;

struct State {
    cfg: Config,
    runs: Vec<RunSummary>,
    last_error: String,
}

impl State {
    fn new() -> Self {
        Self {
            cfg: config::load(),
            runs: Vec::new(),
            last_error: String::new(),
        }
    }
}

struct Service {
    state: Arc<Mutex<State>>,
    notify_poke: Arc<tokio::sync::Notify>,
}

// Keep wire names snake_case to match the docs + future menubar callers.
#[interface(name = "org.aurumos.MlJobsTracker")]
impl Service {
    /// Wire-friendly tuple: (run_id, experiment_id, name, status, iso_start, duration_s)
    #[zbus(name = "runs")]
    async fn runs(&self) -> Vec<(String, String, String, String, String, i64)> {
        let s = self.state.lock().await;
        s.runs
            .iter()
            .map(|r| {
                let iso = chrono_iso_from_ms(r.start_ms);
                (
                    r.run_id.clone(),
                    r.experiment_id.clone(),
                    r.name.clone(),
                    r.status.clone(),
                    iso,
                    r.duration_s,
                )
            })
            .collect()
    }

    #[zbus(name = "tracking_uri")]
    async fn tracking_uri(&self) -> String {
        self.state.lock().await.cfg.mlflow.tracking_uri.clone()
    }

    #[zbus(name = "last_error")]
    async fn last_error(&self) -> String {
        self.state.lock().await.last_error.clone()
    }

    #[zbus(name = "poke")]
    async fn poke(&self) {
        self.notify_poke.notify_one();
    }
}

// Tiny ISO-8601 formatter (no external chrono dep — we already pull tokio).
fn chrono_iso_from_ms(ms: i64) -> String {
    let secs = ms / 1000;
    let nanos = ((ms.rem_euclid(1000)) as u32) * 1_000_000;
    let dt = std::time::UNIX_EPOCH + Duration::new(secs as u64, nanos);
    let dur = dt
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or(Duration::ZERO);
    // Year/month/day from civil_from_days (Howard Hinnant's algorithm).
    let days = (dur.as_secs() / 86400) as i64;
    let secs_today = (dur.as_secs() % 86400) as u32;
    let (y, m, d) = civil_from_days(days);
    let (h, mi, s) = (secs_today / 3600, (secs_today / 60) % 60, secs_today % 60);
    format!("{y:04}-{m:02}-{d:02}T{h:02}:{mi:02}:{s:02}Z")
}

// Convert days-since-1970-01-01 to (year, month, day).
fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = (z - era * 146097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 {
        (mp + 3) as u32
    } else {
        (mp - 9) as u32
    };
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d)
}

async fn poll_loop(state: Arc<Mutex<State>>, notify_poke: Arc<tokio::sync::Notify>) {
    loop {
        // Re-load config every cycle so the user can edit and save in
        // aurum-settings without restarting us.
        {
            let mut s = state.lock().await;
            s.cfg = config::load();
        }

        let (uri, exp) = {
            let s = state.lock().await;
            (
                s.cfg.mlflow.tracking_uri.clone(),
                s.cfg.mlflow.experiment.clone(),
            )
        };
        let client = match mlflow::Client::new(&uri) {
            Ok(c) => c,
            Err(e) => {
                let mut s = state.lock().await;
                s.runs.clear();
                s.last_error = format!("reqwest client build: {e}");
                log::warn!("reqwest client build failed: {e}");
                tokio::select! {
                    _ = tokio::time::sleep(Duration::from_secs(10)) => {}
                    _ = notify_poke.notified() => {}
                }
                continue;
            }
        };

        match client.experiment_id_for(&exp).await {
            Ok(Some(id)) => match client.recent_runs(&id, 25).await {
                Ok(runs) => {
                    let mut s = state.lock().await;
                    s.runs = runs;
                    s.last_error.clear();
                }
                Err(e) => {
                    let mut s = state.lock().await;
                    s.last_error = format!("recent_runs: {e}");
                    log::warn!("recent_runs failed: {e}");
                }
            },
            Ok(None) => {
                let mut s = state.lock().await;
                s.runs.clear();
                s.last_error = format!("experiment '{exp}' not found at {uri}");
            }
            Err(e) => {
                let mut s = state.lock().await;
                s.runs.clear();
                s.last_error = format!("experiment lookup: {e}");
                log::warn!("experiment lookup failed: {e}");
            }
        }

        tokio::select! {
            _ = tokio::time::sleep(Duration::from_secs(10)) => {}
            _ = notify_poke.notified() => {
                log::info!("poke received; refreshing immediately");
            }
        }
    }
}

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    log::info!("starting aurum-ml-jobs-tracker");

    let state = Arc::new(Mutex::new(State::new()));
    let notify = Arc::new(tokio::sync::Notify::new());

    let _conn = Builder::session()?
        .name("org.aurumos.MlJobsTrackerService")?
        .serve_at(
            "/org/aurumos/MlJobsTracker",
            Service {
                state: state.clone(),
                notify_poke: notify.clone(),
            },
        )?
        .build()
        .await?;

    tokio::spawn(poll_loop(state, notify));
    log::info!("D-Bus ready at org.aurumos.MlJobsTrackerService");

    tokio::signal::ctrl_c().await?;
    Ok(())
}
