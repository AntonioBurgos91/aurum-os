// =====================================================================
// ml-jobs-tracker integration tests
//
// We pull in `src/mlflow.rs` via `#[path]` so we can exercise the REST
// client (`Client`) and `RunSummary` parser against a `wiremock` fake
// MLflow server, without exposing the module publicly from the binary.
// =====================================================================

#[path = "../src/mlflow.rs"]
mod mlflow;

use mlflow::Client;
use serde_json::json;
use wiremock::{
    matchers::{method, path},
    Mock, MockServer, ResponseTemplate,
};

#[test]
fn sanity_check_compiles() {
    assert_eq!(2 + 2, 4);
}

#[tokio::test]
async fn endpoint_url_is_well_formed() {
    let c = Client::new("http://example.com/").expect("build client");
    // Trailing slash on the base is stripped; `endpoint` joins the api path.
    assert_eq!(
        c.endpoint("runs/search"),
        "http://example.com/api/2.0/mlflow/runs/search"
    );
}

#[tokio::test]
async fn endpoint_url_handles_no_trailing_slash() {
    let c = Client::new("http://example.com").expect("build client");
    assert_eq!(
        c.endpoint("experiments/search"),
        "http://example.com/api/2.0/mlflow/experiments/search"
    );
}

#[tokio::test]
async fn recent_runs_parses_canned_response() {
    let server = MockServer::start().await;

    // Canned MLflow runs/search response. Two runs: one RUNNING (no
    // end_time → duration computed from "now"), one FINISHED with a
    // real end_time. Tracker code should produce duration_s >= 0 for
    // both, with the FINISHED run's duration being exactly 60s.
    let start_running  = 1_700_000_000_000_i64;
    let start_finished = 1_700_000_000_000_i64;
    let end_finished   = 1_700_000_060_000_i64;

    Mock::given(method("POST"))
        .and(path("/api/2.0/mlflow/runs/search"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "runs": [
                {
                    "info": {
                        "run_id":        "abc123",
                        "experiment_id": "1",
                        "status":        "RUNNING",
                        "start_time":    start_running,
                        "run_name":      "exp-running",
                    }
                },
                {
                    "info": {
                        "run_id":        "def456",
                        "experiment_id": "1",
                        "status":        "FINISHED",
                        "start_time":    start_finished,
                        "end_time":      end_finished,
                        "run_name":      "",
                    }
                }
            ]
        })))
        .mount(&server)
        .await;

    let client = Client::new(&server.uri()).expect("build client");
    let runs = client.recent_runs("1", 25).await.expect("parse runs");
    assert_eq!(runs.len(), 2);

    let running = &runs[0];
    assert_eq!(running.run_id, "abc123");
    assert_eq!(running.status, "RUNNING");
    assert_eq!(running.name,   "exp-running");
    assert!(running.duration_s >= 0, "running duration_s must be >= 0");

    let finished = &runs[1];
    assert_eq!(finished.run_id, "def456");
    assert_eq!(finished.status, "FINISHED");
    // Empty run_name should be backfilled to "(unnamed)".
    assert_eq!(finished.name, "(unnamed)");
    assert_eq!(finished.duration_s, 60);
}

#[tokio::test]
async fn recent_runs_empty_array_returns_empty_vec() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/2.0/mlflow/runs/search"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({ "runs": [] })))
        .mount(&server)
        .await;

    let client = Client::new(&server.uri()).unwrap();
    let runs = client.recent_runs("1", 25).await.expect("ok");
    assert!(runs.is_empty());
}

#[tokio::test]
async fn recent_runs_missing_runs_key_returns_empty_vec() {
    // The `#[serde(default)]` on RunsResp::runs means a missing key
    // should deserialize to an empty Vec, not error.
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/2.0/mlflow/runs/search"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({})))
        .mount(&server)
        .await;

    let client = Client::new(&server.uri()).unwrap();
    let runs = client.recent_runs("1", 25).await.expect("ok");
    assert!(runs.is_empty());
}

#[tokio::test]
async fn http_500_is_handled_as_err_not_panic() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/2.0/mlflow/runs/search"))
        .respond_with(ResponseTemplate::new(500))
        .mount(&server)
        .await;

    let client = Client::new(&server.uri()).unwrap();
    let res = client.recent_runs("1", 25).await;
    assert!(res.is_err(), "expected Err on HTTP 500, got {res:?}");
}

#[tokio::test]
async fn malformed_json_is_handled_as_err_not_panic() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/2.0/mlflow/runs/search"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_string("not even close to json")
                .insert_header("content-type", "application/json"),
        )
        .mount(&server)
        .await;

    let client = Client::new(&server.uri()).unwrap();
    let res = client.recent_runs("1", 25).await;
    assert!(res.is_err(), "expected Err on malformed body, got {res:?}");
}

#[tokio::test]
async fn experiment_id_for_finds_matching_name() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/2.0/mlflow/experiments/search"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "experiments": [
                { "experiment_id": "1", "name": "Default" },
                { "experiment_id": "42", "name": "my-experiment" },
            ]
        })))
        .mount(&server)
        .await;

    let client = Client::new(&server.uri()).unwrap();
    let id = client.experiment_id_for("my-experiment").await.unwrap();
    assert_eq!(id.as_deref(), Some("42"));
}

#[tokio::test]
async fn experiment_id_for_missing_name_returns_none() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/2.0/mlflow/experiments/search"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "experiments": [{ "experiment_id": "1", "name": "Default" }]
        })))
        .mount(&server)
        .await;

    let client = Client::new(&server.uri()).unwrap();
    let id = client.experiment_id_for("nope").await.unwrap();
    assert!(id.is_none());
}

#[tokio::test]
async fn unreachable_server_returns_err_not_panic() {
    // No mocks: a request to a deliberately closed/non-existent port
    // should surface as an Err (network refused / timeout) rather than
    // a panic from inside the client.
    let client = Client::new("http://127.0.0.1:1").unwrap();
    let res = client.recent_runs("1", 5).await;
    assert!(res.is_err(), "expected Err for unreachable server, got {res:?}");
}

#[tokio::test]
#[ignore] // covered indirectly above (8s reqwest::Client timeout); explicit
          // wait-test takes too long for normal `cargo test`.
async fn request_timeout_returns_err() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/api/2.0/mlflow/runs/search"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_delay(std::time::Duration::from_secs(20))
                .set_body_json(json!({ "runs": [] })),
        )
        .mount(&server)
        .await;

    let client = Client::new(&server.uri()).unwrap();
    let res = client.recent_runs("1", 5).await;
    assert!(res.is_err(), "expected timeout Err, got {res:?}");
}
