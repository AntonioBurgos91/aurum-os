#pragma once

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVector>

namespace aurum::ml {

// One coarse classification per supported file format. Drives icon choice and
// which preview backend is invoked.
enum class FileKind {
    Unknown,
    Notebook,      // .ipynb
    Safetensors,   // .safetensors
    Parquet,       // .parquet / .arrow / .feather
    Model,         // .pt / .gguf / .onnx / .bin / .ckpt
    Dataset,       // .csv / .tsv / .jsonl
};

FileKind classify(const QString& path);

// --- Preview payloads ----------------------------------------------------
// Each format's preview returns a structured object the QML side renders.
// We keep them as plain QJsonObject blobs so the UI can be swapped without
// reaching back into C++ types.

// notebook: { metadata: {...}, cells: [ {type, source, output_summary} ] }
QJsonObject preview_notebook(const QString& path, int max_cells = 12);

// safetensors: { total_tensors, total_params, dtypes:[...], tensors:[{name,dtype,shape,offset_bytes}] }
QJsonObject preview_safetensors(const QString& path, int max_tensors = 24);

// parquet: { schema:[{name,type}], rows: N, head: [[...]] }  (uses python helper)
QJsonObject preview_parquet(const QString& path, int rows = 20);

// Master entry: classifies and dispatches to the right backend. Returns
// { kind: "...", supported: bool, preview: <see above> | null, error: <str|null> }.
QJsonObject preview(const QString& path);

void init_ml_integrations();

} // namespace aurum::ml

// C-linkage shim kept for legacy main.cpp callers.
extern "C" void init_ml_integrations();
