// =====================================================================
// spotlight-indexer integration tests
//
// We pull in `src/index.rs` via `#[path]` so we can exercise the
// `Indexer` API without exposing it publicly from the binary crate.
// The watcher module is OS-dependent (inotify) and is not tested here.
// =====================================================================

#[path = "../src/index.rs"]
mod index;

use std::fs;
use std::path::PathBuf;

use index::Indexer;
use tempfile::TempDir;

fn make_fake_file(root: &std::path::Path, rel: &str, content: &[u8]) -> PathBuf {
    let p = root.join(rel);
    if let Some(parent) = p.parent() {
        fs::create_dir_all(parent).unwrap();
    }
    fs::write(&p, content).unwrap();
    p
}

/// Tantivy's default `ReloadPolicy::OnCommitWithDelay` runs the
/// reader-refresh on a background thread with a small debounce, which
/// races with assertions in single-threaded unit tests. The reader has
/// an explicit `reload()` we call after every commit in tests to force
/// the searcher to see freshly committed segments.
fn commit_and_reload(idx: &mut Indexer) {
    idx.commit().expect("commit");
    idx.reader.reload().expect("reload");
}

#[test]
fn sanity_check_compiles() {
    assert_eq!(1 + 1, 2);
}

#[test]
fn empty_index_search_returns_nothing() {
    let tmp = TempDir::new().unwrap();
    let mut idx = Indexer::open(tmp.path()).expect("open empty index");
    commit_and_reload(&mut idx);
    let hits = idx.search("anything", 10).expect("search ok");
    assert!(hits.is_empty(), "got hits from empty index: {hits:?}");
    assert_eq!(idx.doc_count(), 0);
}

#[test]
fn index_three_docs_and_search_finds_one() {
    let tmp_idx = TempDir::new().unwrap();
    let tmp_files = TempDir::new().unwrap();

    let notebook = make_fake_file(tmp_files.path(), "notebooks/explore.ipynb", b"{}");
    let model    = make_fake_file(tmp_files.path(), "models/llama.safetensors", b"\0\0\0\0");
    let parquet  = make_fake_file(tmp_files.path(), "datasets/train.parquet",  b"PAR1");

    let mut idx = Indexer::open(tmp_idx.path()).expect("open");
    idx.upsert(&notebook);
    idx.upsert(&model);
    idx.upsert(&parquet);
    commit_and_reload(&mut idx);

    assert_eq!(idx.doc_count(), 3);

    // The default tokenizer splits on punctuation, so "explore" should
    // match the notebook file.
    let hits = idx.search("explore", 10).expect("search ok");
    assert_eq!(hits.len(), 1, "expected exactly one hit, got: {hits:?}");
    assert_eq!(hits[0].kind, "notebook");
    assert!(hits[0].path.ends_with("explore.ipynb"));
}

#[test]
fn search_with_no_matches_is_empty() {
    let tmp_idx = TempDir::new().unwrap();
    let tmp_files = TempDir::new().unwrap();
    let f = make_fake_file(tmp_files.path(), "notebooks/foo.ipynb", b"{}");

    let mut idx = Indexer::open(tmp_idx.path()).unwrap();
    idx.upsert(&f);
    commit_and_reload(&mut idx);

    let hits = idx.search("zxcvbnm_no_such_token", 10).unwrap();
    assert!(hits.is_empty());
}

#[test]
fn index_persists_across_reopen() {
    let tmp_idx = TempDir::new().unwrap();
    let tmp_files = TempDir::new().unwrap();
    let f = make_fake_file(tmp_files.path(), "models/checkpoint.gguf", b"GGUF");

    {
        let mut idx = Indexer::open(tmp_idx.path()).unwrap();
        idx.upsert(&f);
        commit_and_reload(&mut idx);
        assert_eq!(idx.doc_count(), 1);
    }

    // Re-open the same directory; the document survives.
    let idx2 = Indexer::open(tmp_idx.path()).unwrap();
    idx2.reader.reload().unwrap();
    let hits = idx2.search("checkpoint", 10).unwrap();
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].kind, "model");
}

#[test]
fn classify_kinds_via_extension_and_dir() {
    // Indirectly verifies `classify()`: parquet → dataset, .gguf → model,
    // .ipynb → notebook, .md (no special dir) → file.
    let tmp_idx = TempDir::new().unwrap();
    let tmp_files = TempDir::new().unwrap();

    let nb  = make_fake_file(tmp_files.path(), "notebooks/a.ipynb", b"{}");
    let md  = make_fake_file(tmp_files.path(), "other/readme.md",   b"# hi");
    let ds  = make_fake_file(tmp_files.path(), "datasets/x.parquet", b"PAR1");
    let mdl = make_fake_file(tmp_files.path(), "models/y.safetensors", b"\0");

    let mut idx = Indexer::open(tmp_idx.path()).unwrap();
    for p in [&nb, &md, &ds, &mdl] { idx.upsert(p); }
    commit_and_reload(&mut idx);

    let by_token = |q: &str| -> String {
        let h = idx.search(q, 5).unwrap();
        assert!(!h.is_empty(), "no hits for {q}");
        h[0].kind.clone()
    };
    assert_eq!(by_token("a"),      "notebook");
    assert_eq!(by_token("readme"), "file");
    assert_eq!(by_token("x"),      "dataset");
    assert_eq!(by_token("y"),      "model");
}

#[test]
fn schema_fields_are_retrievable() {
    // Index a single doc and confirm the path/name/size fields come
    // back through Hit (i.e. the schema's STORED bits are set
    // correctly). This guards against accidental "INDEXED but not
    // STORED" mistakes in the schema builder.
    let tmp_idx = TempDir::new().unwrap();
    let tmp_files = TempDir::new().unwrap();
    let body = b"hello world contents";
    let f = make_fake_file(tmp_files.path(), "datasets/payload.jsonl", body);

    let mut idx = Indexer::open(tmp_idx.path()).unwrap();
    idx.upsert(&f);
    commit_and_reload(&mut idx);

    let hits = idx.search("payload", 5).unwrap();
    assert_eq!(hits.len(), 1);
    let h = &hits[0];
    assert_eq!(h.name, "payload.jsonl");
    assert_eq!(h.size_bytes, body.len() as u64);
    assert!(h.path.ends_with("payload.jsonl"));
    assert!(h.score > 0.0);
}

#[test]
fn delete_then_commit_removes_doc() {
    let tmp_idx = TempDir::new().unwrap();
    let tmp_files = TempDir::new().unwrap();
    let f = make_fake_file(tmp_files.path(), "datasets/transient.csv", b"a,b\n1,2\n");

    let mut idx = Indexer::open(tmp_idx.path()).unwrap();
    idx.upsert(&f);
    commit_and_reload(&mut idx);
    assert_eq!(idx.search("transient", 5).unwrap().len(), 1);

    idx.delete(&f);
    commit_and_reload(&mut idx);
    assert!(idx.search("transient", 5).unwrap().is_empty());
}

#[test]
#[ignore] // inotify is OS-dependent; run with `cargo test -- --ignored` on Linux.
fn inotify_watcher_emits_touched_on_create() {
    // Documentation test for watch::watch — needs a real inotify
    // backend and a debounce window to fire events into an mpsc.
}
