//! Minimal MLflow REST client.
//!
//! Only the two endpoints we actually need for the menubar/notifications:
//!   * search_experiments — to find the experiment id by name.
//!   * search_runs        — to list active or recently completed runs.
//!
//! Schema reference: MLflow REST API 2.0.
//! https://mlflow.org/docs/latest/rest-api.html

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize)]
pub struct RunSummary {
    pub run_id:        String,
    pub experiment_id: String,
    pub name:          String,
    pub status:        String,   // RUNNING / FINISHED / FAILED / KILLED / SCHEDULED
    pub start_ms:      i64,
    pub duration_s:    i64,      // (now - start_ms) when running, (end-start) when finished
}

#[derive(Debug, Deserialize)]
struct Experiment { experiment_id: String, name: String }
#[derive(Debug, Deserialize)]
struct ExperimentsResp { #[serde(default)] experiments: Vec<Experiment> }

#[derive(Debug, Deserialize)]
struct RunInfo {
    run_id:        String,
    experiment_id: String,
    status:        String,
    start_time:    i64,
    #[serde(default)] end_time: Option<i64>,
    #[serde(default)] run_name: String,
}
#[derive(Debug, Deserialize)]
struct Run { info: RunInfo }
#[derive(Debug, Deserialize)]
struct RunsResp { #[serde(default)] runs: Vec<Run> }

#[derive(Debug, Serialize)]
struct SearchRunsReq<'a> {
    experiment_ids: Vec<&'a str>,
    filter:         &'a str,
    max_results:    i32,
    order_by:       Vec<&'a str>,
}

pub struct Client {
    base: String,
    http: reqwest::Client,
}

impl Client {
    /// Build a new MLflow REST client targeting `base` (no trailing slash needed).
    ///
    /// Returns an error if reqwest fails to build the underlying HTTP client —
    /// typically a TLS init failure (e.g. missing system roots when rustls is
    /// configured to use the platform store). Propagating instead of panicking
    /// keeps the daemon up: the poll loop will surface the error via
    /// `last_error()` on D-Bus.
    pub fn new(base: &str) -> Result<Self, reqwest::Error> {
        let base = base.trim_end_matches('/').to_string();
        let http = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(8))
            .build()?;
        Ok(Self { base, http })
    }

    pub fn endpoint(&self, path: &str) -> String {
        format!("{}/api/2.0/mlflow/{}", self.base, path)
    }

    pub async fn experiment_id_for(&self, name: &str) -> Result<Option<String>, reqwest::Error> {
        let resp: ExperimentsResp = self.http
            .post(self.endpoint("experiments/search"))
            .json(&serde_json::json!({ "max_results": 100 }))
            .send().await?
            .error_for_status()?
            .json().await?;
        Ok(resp.experiments
            .into_iter()
            .find(|e| e.name == name)
            .map(|e| e.experiment_id))
    }

    pub async fn recent_runs(&self, experiment_id: &str, limit: i32) -> Result<Vec<RunSummary>, reqwest::Error> {
        let req = SearchRunsReq {
            experiment_ids: vec![experiment_id],
            // We grab the running first, then recent finished, by sorting on
            // start_time desc. The aggregator on the client side splits them.
            filter:         "",
            max_results:    limit,
            order_by:       vec!["attributes.start_time DESC"],
        };
        let resp: RunsResp = self.http
            .post(self.endpoint("runs/search"))
            .json(&req)
            .send().await?
            .error_for_status()?
            .json().await?;

        let now_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);

        Ok(resp.runs.into_iter().map(|r| {
            let end = r.info.end_time.unwrap_or(now_ms);
            RunSummary {
                run_id:        r.info.run_id,
                experiment_id: r.info.experiment_id,
                name:          if r.info.run_name.is_empty() { "(unnamed)".into() }
                               else { r.info.run_name },
                status:        r.info.status,
                start_ms:      r.info.start_time,
                duration_s:    ((end - r.info.start_time).max(0)) / 1000,
            }
        }).collect())
    }
}
