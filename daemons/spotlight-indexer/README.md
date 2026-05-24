# spotlight-indexer

Rust daemon: tantivy-backed file index over the AurumOS workspace
(`~/datasets`, `~/models`, `~/notebooks`, `~/Documents`, `~/Downloads`,
`~/Desktop`). Watches with inotify, debounces 500 ms after the last event
before committing.

| Bus name   | `org.aurumos.SpotlightIndexerService`                       |
| Object     | `/org/aurumos/SpotlightIndexer`                             |
| Interface  | `org.aurumos.SpotlightIndexer`                              |
| Methods    | `search(q, limit) → a(ssstd)`, `reindex()`, `stats() → (xt)`|

The index lives at `$XDG_CACHE_HOME/aurum/spotlight/index/` (~50–200 MB
typical). Schema in [`src/index.rs`](src/index.rs); content indexing is
deliberately out of scope for v0.1 — filename + path + extension only.
