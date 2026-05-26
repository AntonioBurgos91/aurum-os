//! Tantivy index of the user's ML workspace.
//!
//! The schema is intentionally tiny — we don't try to index file *contents* for
//! Phase 3 (a full code-search index belongs in its own daemon). What we DO
//! index is enough to make the Spotlight overlay feel snappy:
//!   * path        — STORED + STRING (exact-match retrieval)
//!   * filename    — STORED + TEXT  (tokenized; the actual ranked field)
//!   * extension   — STRING         (filter, e.g. only .ipynb hits)
//!   * kind        — STRING         (file / notebook / model / dataset)
//!   * mtime       — STORED I64
//!   * size_bytes  — STORED U64

use std::path::{Path, PathBuf};

use serde::Serialize;
use tantivy::{
    collector::TopDocs,
    doc,
    query::QueryParser,
    schema::{
        Field, IndexRecordOption, Schema, SchemaBuilder, TextFieldIndexing, TextOptions, FAST,
        INDEXED, STORED, STRING,
    },
    Index, IndexReader, IndexWriter, ReloadPolicy, TantivyDocument,
};
use walkdir::WalkDir;

#[derive(Debug, Clone, Serialize)]
pub struct Hit {
    pub kind: String,
    pub name: String,
    pub path: String,
    pub size_bytes: u64,
    pub score: f32,
}

pub struct Schemas {
    pub schema: Schema,
    pub path: Field,
    pub filename: Field,
    pub extension: Field,
    pub kind: Field,
    pub mtime: Field,
    pub size_bytes: Field,
}

impl Schemas {
    pub fn build() -> Self {
        let mut sb: SchemaBuilder = Schema::builder();

        // Tokenized field for ranked search. "default" tokenizer is reasonable
        // for filenames (splits on punctuation, lowercases).
        let text_opts = TextOptions::default()
            .set_indexing_options(
                TextFieldIndexing::default()
                    .set_tokenizer("default")
                    .set_index_option(IndexRecordOption::WithFreqsAndPositions),
            )
            .set_stored();

        let path = sb.add_text_field("path", STRING | STORED);
        let filename = sb.add_text_field("filename", text_opts);
        let extension = sb.add_text_field("extension", STRING | STORED);
        let kind = sb.add_text_field("kind", STRING | STORED);
        let mtime = sb.add_i64_field("mtime", STORED | INDEXED);
        let size_bytes = sb.add_u64_field("size_bytes", STORED | FAST);
        let schema = sb.build();
        Self {
            schema,
            path,
            filename,
            extension,
            kind,
            mtime,
            size_bytes,
        }
    }
}

pub struct Indexer {
    pub schemas: Schemas,
    pub index: Index,
    pub reader: IndexReader,
    pub writer: IndexWriter,
}

impl Indexer {
    /// Open (or create) the index at `dir`. We use a generous 200 MB heap budget
    /// for the writer: this index lives on a single workstation, not a cluster.
    pub fn open(dir: &Path) -> tantivy::Result<Self> {
        std::fs::create_dir_all(dir).map_err(tantivy::TantivyError::from)?;
        let schemas = Schemas::build();
        let index = Index::open_or_create(
            tantivy::directory::MmapDirectory::open(dir)?,
            schemas.schema.clone(),
        )?;
        let writer = index.writer(200_000_000)?;
        let reader = index
            .reader_builder()
            .reload_policy(ReloadPolicy::OnCommitWithDelay)
            .try_into()?;
        Ok(Self {
            schemas,
            index,
            reader,
            writer,
        })
    }

    pub fn upsert(&mut self, p: &Path) {
        let meta = match std::fs::metadata(p) {
            Ok(m) => m,
            Err(_) => return,
        };
        if !meta.is_file() {
            return;
        }
        let name = p
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_string();
        let path = p.to_string_lossy().to_string();
        let ext = p
            .extension()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_lowercase();
        let kind = classify(p, &ext);
        let mtime = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        let size_bytes = meta.len();

        // Tantivy doesn't have native "update": delete by primary key (path),
        // then add a fresh document.
        let term = tantivy::Term::from_field_text(self.schemas.path, &path);
        self.writer.delete_term(term);

        let _ = self.writer.add_document(doc!(
            self.schemas.path       => path,
            self.schemas.filename   => name,
            self.schemas.extension  => ext,
            self.schemas.kind       => kind,
            self.schemas.mtime      => mtime,
            self.schemas.size_bytes => size_bytes,
        ));
    }

    pub fn delete(&mut self, p: &Path) {
        let term = tantivy::Term::from_field_text(self.schemas.path, &p.to_string_lossy());
        self.writer.delete_term(term);
    }

    pub fn commit(&mut self) -> tantivy::Result<()> {
        self.writer.commit().map(|_| ())
    }

    /// Crawl the supplied roots and upsert every file. Caller commits.
    pub fn crawl<I: IntoIterator<Item = PathBuf>>(&mut self, roots: I) {
        for root in roots {
            for entry in WalkDir::new(&root)
                .follow_links(false)
                .into_iter()
                .filter_map(Result::ok)
            {
                if entry.file_type().is_file() {
                    self.upsert(entry.path());
                }
            }
        }
    }

    pub fn doc_count(&self) -> u64 {
        self.reader.searcher().num_docs()
    }

    pub fn search(&self, query: &str, limit: usize) -> tantivy::Result<Vec<Hit>> {
        let searcher = self.reader.searcher();
        let parser = QueryParser::for_index(&self.index, vec![self.schemas.filename]);
        let q = parser.parse_query(query)?;
        let top = searcher.search(&q, &TopDocs::with_limit(limit))?;

        let mut hits = Vec::with_capacity(top.len());
        for (score, addr) in top {
            let doc: TantivyDocument = searcher.doc(addr)?;
            let path = first_text(&doc, self.schemas.path).unwrap_or_default();
            let kind = first_text(&doc, self.schemas.kind).unwrap_or_else(|| "file".into());
            let name = first_text(&doc, self.schemas.filename).unwrap_or_default();
            let size = first_u64(&doc, self.schemas.size_bytes).unwrap_or(0);
            hits.push(Hit {
                kind,
                name,
                path,
                size_bytes: size,
                score,
            });
        }
        Ok(hits)
    }
}

fn first_text(doc: &TantivyDocument, field: Field) -> Option<String> {
    // tantivy 0.22 changed Value into a trait; OwnedValue is the concrete
    // variant we get back from get_first(). Pattern-match instead of relying
    // on the (removed) inherent .as_str() helper.
    match doc.get_first(field)? {
        tantivy::schema::OwnedValue::Str(s) => Some(s.clone()),
        _ => None,
    }
}

fn first_u64(doc: &TantivyDocument, field: Field) -> Option<u64> {
    match doc.get_first(field)? {
        tantivy::schema::OwnedValue::U64(v) => Some(*v),
        _ => None,
    }
}

// Map a file to a coarse "kind" so the UI can group results.
fn classify(path: &Path, ext: &str) -> String {
    let in_dir = |d: &str| {
        path.components().any(|c| {
            c.as_os_str()
                .to_str()
                .map(|s| s.eq_ignore_ascii_case(d))
                .unwrap_or(false)
        })
    };

    match ext {
        "ipynb" => "notebook".into(),
        "safetensors" | "gguf" | "pt" | "bin" | "onnx" | "ckpt" => "model".into(),
        "parquet" | "arrow" | "feather" | "csv" | "tsv" | "jsonl" => "dataset".into(),
        _ if in_dir("datasets") => "dataset".into(),
        _ if in_dir("models") => "model".into(),
        _ if in_dir("notebooks") => "notebook".into(),
        _ => "file".into(),
    }
}
