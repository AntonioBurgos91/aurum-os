#include "ml_integrations.h"

#include <QByteArray>
#include <QDataStream>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QProcess>
#include <QString>
#include <QStringList>

#include <mutex>

namespace aurum::ml {

FileKind classify(const QString& path) {
    const auto ext = QFileInfo(path).suffix().toLower();
    if (ext == "ipynb")                        return FileKind::Notebook;
    if (ext == "safetensors")                  return FileKind::Safetensors;
    if (ext == "parquet" || ext == "arrow" || ext == "feather")
                                               return FileKind::Parquet;
    if (ext == "pt" || ext == "gguf" || ext == "onnx" ||
        ext == "bin" || ext == "ckpt")         return FileKind::Model;
    if (ext == "csv" || ext == "tsv" || ext == "jsonl")
                                               return FileKind::Dataset;
    return FileKind::Unknown;
}

namespace {

// Max characters of cell source text included in a preview. Anything beyond
// is truncated — Finder's preview pane is a thumbnail, not a full editor.
constexpr int kCellPreviewMaxChars = 800;

// Read up to `n` bytes from `path` starting at `offset`. Returns empty array
// on any I/O failure so callers can short-circuit cleanly.
QByteArray read_range(const QString& path, qint64 offset, qint64 n) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return {};
    if (!f.seek(offset)) return {};
    return f.read(n);
}

// Single line of human-readable text approximating cell output. We avoid
// rendering anything beyond the first few characters — Finder's preview pane
// is a thumbnail, not a full notebook renderer.
QString summarize_outputs(const QJsonArray& outputs) {
    if (outputs.isEmpty()) return {};
    const auto first = outputs.first().toObject();
    const auto type  = first.value("output_type").toString();
    if (type == "stream") {
        // Stream output text is either a string or a string list.
        const auto v = first.value("text");
        if (v.isString())  return QString("stdout: %1").arg(v.toString().left(120));
        if (v.isArray())   return QString("stdout: %1").arg(v.toArray().first().toString().left(120));
        return "stdout: …";
    }
    if (type == "error") {
        return "error: " + first.value("ename").toString();
    }
    if (type == "display_data" || type == "execute_result") {
        const auto data = first.value("data").toObject();
        if (data.contains("image/png"))   return "image/png";
        if (data.contains("text/html"))   return "text/html";
        if (data.contains("text/plain"))  return "text: " + data.value("text/plain").toString().left(120);
    }
    return "(" + type + ")";
}

QString dtype_byte_size(const QString& dtype) {
    // safetensors dtypes are conventionally lowercase strings: f16, f32, f64,
    // bf16, i8 ... Normalize the input to lowercase and compare against
    // lowercase constants. The previous version's comment said lowercase but
    // it actually compared against UPPERCASE constants, so every dtype hit
    // the fallback "?" and the safetensors preview byte math was wrong.
    const QString d = dtype.toLower();
    if (d == "f32" || d == "i32" || d == "u32") return "4";
    if (d == "f16" || d == "bf16"|| d == "i16" || d == "u16") return "2";
    if (d == "f64" || d == "i64" || d == "u64") return "8";
    if (d == "i8"  || d == "u8"  || d == "bool") return "1";
    return "?";
}

QJsonObject error_obj(const QString& msg) {
    return QJsonObject{{"error", msg}};
}

} // namespace

QJsonObject preview_notebook(const QString& path, int max_cells) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return error_obj("cannot open file");
    const auto bytes = f.readAll();
    QJsonParseError err;
    const auto doc = QJsonDocument::fromJson(bytes, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return error_obj("invalid notebook json");

    const auto root = doc.object();
    QJsonObject out;
    out["metadata"] = root.value("metadata").toObject();

    QJsonArray summarized;
    const auto cells = root.value("cells").toArray();
    int kept = 0;
    for (const auto& v : cells) {
        if (kept >= max_cells) break;
        const auto cell = v.toObject();
        const auto type = cell.value("cell_type").toString();
        if (type != "code" && type != "markdown") continue;

        // `source` can be a single string or a list of lines.
        QString source;
        const auto sv = cell.value("source");
        if (sv.isString())  source = sv.toString();
        else if (sv.isArray()) {
            for (const auto& line : sv.toArray()) source += line.toString();
        }

        QJsonObject c;
        c["type"]   = type;
        c["source"] = source.left(kCellPreviewMaxChars);
        if (type == "code") {
            c["execution_count"]  = cell.value("execution_count");
            c["output_summary"]   = summarize_outputs(cell.value("outputs").toArray());
        }
        summarized.append(c);
        ++kept;
    }
    out["cells"] = summarized;
    out["total_cells"] = cells.size();
    return out;
}

QJsonObject preview_safetensors(const QString& path, int max_tensors) {
    // safetensors layout: [u64 header_len LE][header JSON][raw tensor bytes]
    // The header is small enough (a few hundred KB at most) that we can read
    // it whole and parse with QJsonDocument.
    const auto header_len_bytes = read_range(path, 0, 8);
    if (header_len_bytes.size() != 8)
        return error_obj("safetensors: cannot read header length");

    quint64 header_len = 0;
    QDataStream ds(header_len_bytes);
    ds.setByteOrder(QDataStream::LittleEndian);
    ds >> header_len;
    if (header_len == 0 || header_len > (256ull * 1024ull * 1024ull))
        return error_obj("safetensors: implausible header length");

    const auto header = read_range(path, 8, static_cast<qint64>(header_len));
    if (static_cast<quint64>(header.size()) != header_len)
        return error_obj("safetensors: short header read");

    QJsonParseError err;
    const auto doc = QJsonDocument::fromJson(header, &err);
    if (err.error != QJsonParseError::NoError)
        return error_obj("safetensors header: " + err.errorString());
    const auto root = doc.object();

    QJsonArray tensors;
    QStringList dtypes;
    qulonglong total_params = 0;
    int kept = 0;
    const auto keys = root.keys();
    for (const auto& k : keys) {
        if (k == "__metadata__") continue;
        const auto t = root.value(k).toObject();
        const auto dtype = t.value("dtype").toString();
        if (!dtypes.contains(dtype)) dtypes << dtype;

        // shape product → param count (works for any-dim tensor).
        const auto shape_v = t.value("shape").toArray();
        qulonglong n = 1;
        for (const auto& d : shape_v) n *= static_cast<qulonglong>(d.toDouble());
        total_params += n;

        if (kept < max_tensors) {
            QJsonObject row;
            row["name"]         = k;
            row["dtype"]        = dtype;
            row["shape"]        = shape_v;
            row["param_count"]  = static_cast<qint64>(n);
            row["dtype_bytes"]  = dtype_byte_size(dtype);
            tensors.append(row);
            ++kept;
        }
    }

    QJsonObject out;
    out["total_tensors"] = root.size() - (root.contains("__metadata__") ? 1 : 0);
    out["total_params"]  = static_cast<qint64>(total_params);
    out["dtypes"]        = QJsonArray::fromStringList(dtypes);
    out["tensors"]       = tensors;
    if (root.contains("__metadata__"))
        out["metadata"] = root.value("__metadata__");
    return out;
}

QJsonObject preview_parquet(const QString& path, int rows) {
    // We shell out to a tiny Python helper rather than linking Arrow C++ into
    // every Aurum binary. The helper lives in /usr/local/share/aurum-os/scripts.
    const QStringList candidates = {
        qEnvironmentVariable("AURUM_PARQUET_PEEK"),
        "/usr/local/share/aurum-os/scripts/parquet_peek.py",
        "/usr/share/aurum-os/scripts/parquet_peek.py",
    };
    QString script;
    for (const auto& c : candidates)
        if (!c.isEmpty() && QFile::exists(c)) { script = c; break; }
    if (script.isEmpty()) return error_obj("parquet_peek.py not installed");

    QProcess p;
    p.start("python3", {script, path, QString::number(rows)});
    if (!p.waitForFinished(4000))
        return error_obj("parquet_peek timed out");
    if (p.exitCode() != 0)
        return error_obj("parquet_peek: " + QString::fromUtf8(p.readAllStandardError()).trimmed());

    QJsonParseError err;
    const auto doc = QJsonDocument::fromJson(p.readAllStandardOutput(), &err);
    if (err.error != QJsonParseError::NoError)
        return error_obj("parquet_peek bad JSON: " + err.errorString());
    return doc.object();
}

QJsonObject preview(const QString& path) {
    QJsonObject out{
        {"path",      path},
        {"size",      QFileInfo(path).size()},
        {"mtime",     QFileInfo(path).lastModified().toString(Qt::ISODate)},
        {"supported", true},
        {"preview",   QJsonValue::Null},
        {"error",     QJsonValue::Null},
    };

    const auto kind = classify(path);
    QString kind_str = "unknown";
    QJsonObject inner;
    switch (kind) {
        case FileKind::Notebook:    kind_str = "notebook";    inner = preview_notebook(path);   break;
        case FileKind::Safetensors: kind_str = "safetensors"; inner = preview_safetensors(path); break;
        case FileKind::Parquet:     kind_str = "parquet";     inner = preview_parquet(path);    break;
        case FileKind::Model:       kind_str = "model";       break;
        case FileKind::Dataset:     kind_str = "dataset";     break;
        case FileKind::Unknown:     out["supported"] = false; break;
    }
    out["kind"] = kind_str;
    if (inner.contains("error")) {
        out["error"] = inner.value("error");
    } else if (!inner.isEmpty()) {
        out["preview"] = inner;
    }
    return out;
}

void init_ml_integrations() {
    static std::once_flag init_flag;
    std::call_once(init_flag, [](){
        // Informational message goes through Qt logging; stdout is reserved
        // for tools that pipe the library's preview() JSON output (see
        // tests/test_preview.cpp). Filter via QT_LOGGING_RULES in production.
        qInfo().noquote() << "[ml-integrations] initialized (ipynb/safetensors/parquet preview)";
    });
}

} // namespace aurum::ml

extern "C" void init_ml_integrations() {
    aurum::ml::init_ml_integrations();
}
