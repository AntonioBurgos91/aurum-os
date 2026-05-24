// ==============================================================================
// AurumOS Spotlight Indexer
//
// Crawls a configurable set of roots (defaults: ~/datasets, ~/models,
// ~/notebooks, ~/Documents, ~/Downloads) into a tantivy index, watches them
// with inotify for live updates, and exposes a session-bus D-Bus interface
// the aurum-spotlight overlay queries:
//
//     bus name    org.aurumos.SpotlightIndexerService
//     object      /org/aurumos/SpotlightIndexer
//     interface   org.aurumos.SpotlightIndexer
//     methods     search(q: s, limit: u) -> a(ssstd)   // kind, name, path, size, score
//                 reindex()
//                 stats() -> (doc_count: t, last_indexed: x)
// ==============================================================================

mod index;
mod watch;

use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};

use tokio::sync::Mutex;
use zbus::{connection::Builder, interface};

use crate::index::{Hit, Indexer};
use crate::watch::FsChange;

fn default_roots() -> Vec<PathBuf> {
    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"));
    // Order matters only for cosmetic logs.
    ["datasets", "models", "notebooks", "Documents", "Downloads", "Desktop"]
        .iter()
        .map(|d| home.join(d))
        .collect()
}

fn index_dir() -> PathBuf {
    dirs::cache_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join("aurum/spotlight/index")
}

/// State shared between the watcher loop, the periodic commit loop, and the
/// D-Bus interface object.
struct State {
    indexer: Indexer,
    last_indexed: i64,
}

struct SpotlightService {
    state: Arc<Mutex<State>>,
    roots: Vec<PathBuf>,
}

// Keep wire names snake_case to match the docs + C++ FilesPlugin caller.
#[interface(name = "org.aurumos.SpotlightIndexer")]
impl SpotlightService {
    /// Returns up to `limit` hits ranked by tantivy. Tuple layout is fixed so
    /// the C++ client side stays simple: (kind, name, path, size_bytes, score).
    #[zbus(name = "search")]
    async fn search(&self, query: String, limit: u32) -> Vec<(String, String, String, u64, f64)> {
        let lim = limit.clamp(1, 200) as usize;
        let state = self.state.lock().await;
        match state.indexer.search(&query, lim) {
            Ok(hits) => hits.into_iter().map(hit_to_tuple).collect(),
            Err(e) => {
                log::warn!("search('{}') failed: {e}", query);
                vec![]
            }
        }
    }

    /// Triggers a full re-crawl. Idempotent; safe to call from the UI.
    #[zbus(name = "reindex")]
    async fn reindex(&self) {
        let mut state = self.state.lock().await;
        log::info!("reindex requested via D-Bus");
        state.indexer.crawl(self.roots.clone());
        if let Err(e) = state.indexer.commit() {
            log::warn!("commit after reindex failed: {e}");
        }
        state.last_indexed = now_secs();
    }

    /// (doc_count, last_indexed_unix_seconds)
    #[zbus(name = "stats")]
    async fn stats(&self) -> (u64, i64) {
        let state = self.state.lock().await;
        (state.indexer.doc_count(), state.last_indexed)
    }
}

fn hit_to_tuple(h: Hit) -> (String, String, String, u64, f64) {
    (h.kind, h.name, h.path, h.size_bytes, h.score as f64)
}

fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    log::info!("starting aurum-spotlight-indexer");

    let roots = default_roots();
    let dir   = index_dir();
    log::info!("index dir: {}", dir.display());
    for r in &roots { log::info!("watching: {}", r.display()); }

    // --- Open the tantivy index FIRST. If it can't open we abort the daemon
    // rather than binding a bus name that maps to a non-functional service.
    // (Previously the bus name was bound first and the indexer opened after,
    // which let other apps connect to a dead D-Bus surface on tantivy failure.)
    let indexer = Indexer::open(&dir)?;
    let state = Arc::new(Mutex::new(State {
        indexer,
        last_indexed: 0,   // becomes >0 once the initial crawl commits
    }));

    // --- D-Bus interface (bound AFTER the index is open so the bus name only
    // appears when we can actually serve queries). stats() will report 0 docs
    // until the initial crawl commits — honest "we're indexing".
    let _conn = Builder::session()?
        .name("org.aurumos.SpotlightIndexerService")?
        .serve_at(
            "/org/aurumos/SpotlightIndexer",
            SpotlightService { state: state.clone(), roots: roots.clone() },
        )?
        .build()
        .await?;
    log::info!("D-Bus ready at org.aurumos.SpotlightIndexerService /org/aurumos/SpotlightIndexer");

    // --- Initial crawl on the blocking pool -------------------------------
    // tantivy's writer is synchronous, so we hand the work to
    // tokio::task::spawn_blocking. blocking_lock() is safe here because the
    // task runs *outside* the async runtime workers.
    let crawl_state = state.clone();
    let crawl_roots = roots.clone();
    tokio::task::spawn_blocking(move || {
        let t0 = Instant::now();
        log::info!("starting initial crawl across {} root(s)", crawl_roots.len());
        let mut s = crawl_state.blocking_lock();
        s.indexer.crawl(crawl_roots);
        if let Err(e) = s.indexer.commit() {
            log::warn!("initial commit failed: {e}");
        }
        s.last_indexed = now_secs();
        log::info!("initial crawl done: {} docs in {:?}",
                   s.indexer.doc_count(), t0.elapsed());
    });

    // --- Watcher → debounced batch upserter -------------------------------
    // inotify can fire dozens of events per "single user save" (e.g. editors
    // doing atomic rename via tmp file). Coalesce changes by buffering for
    // 500 ms after the last event before committing the writer.
    let watch = watch::watch(&roots)?;
    let watch_state = state.clone();
    tokio::spawn(async move {
        let mut rx = watch.rx;
        let mut pending = false;
        let mut last_event = Instant::now();
        loop {
            let timeout = if pending {
                Duration::from_millis(500)
            } else {
                Duration::from_secs(60)
            };
            match tokio::time::timeout(timeout, rx.recv()).await {
                Ok(Some(change)) => {
                    let mut s = watch_state.lock().await;
                    match change {
                        FsChange::Touched(p) => s.indexer.upsert(&p),
                        FsChange::Removed(p) => s.indexer.delete(&p),
                    }
                    pending = true;
                    last_event = Instant::now();
                }
                Ok(None) => break, // watcher dropped
                Err(_) => {
                    // Debounce window elapsed; commit if we have pending writes.
                    if pending && last_event.elapsed() >= Duration::from_millis(500) {
                        let mut s = watch_state.lock().await;
                        if let Err(e) = s.indexer.commit() {
                            log::warn!("debounced commit failed: {e}");
                        } else {
                            s.last_indexed = now_secs();
                        }
                        pending = false;
                    }
                }
            }
        }
    });

    tokio::signal::ctrl_c().await?;
    log::info!("shutdown requested");
    Ok(())
}
