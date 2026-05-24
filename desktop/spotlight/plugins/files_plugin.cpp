#include "files_plugin.h"

#include <QDBusArgument>
#include <QDBusMetaType>
#include <QJsonArray>
#include <QJsonObject>
#include <QVariantList>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusPendingCall>
#include <QtDBus/QDBusPendingReply>

namespace aurum::spotlight {

namespace {

// The daemon returns a(ssstd) — array of (kind, name, path, size, score).
// QtDBus surfaces this as QDBusArgument; we marshal it into JSON rows here.
QJsonArray rowsFromReply(const QDBusMessage& msg) {
    QJsonArray rows;
    const auto args = msg.arguments();
    if (args.isEmpty()) return rows;
    const auto v = args.first();

    // The variant wraps a QDBusArgument iterator over the a(ssstd) array.
    const auto arg = v.value<QDBusArgument>();
    if (arg.currentType() != QDBusArgument::ArrayType) return rows;

    arg.beginArray();
    while (!arg.atEnd()) {
        arg.beginStructure();
        QString kind, name, path;
        qulonglong size = 0;
        double score = 0.0;
        arg >> kind >> name >> path >> size >> score;
        arg.endStructure();

        rows.append(QJsonObject{
            {"title",    name},
            {"subtitle", path},
            {"icon",     kind == "notebook" ? "x-office-document"
                       : kind == "model"    ? "applications-science"
                       : kind == "dataset"  ? "x-office-spreadsheet"
                       :                      "text-x-generic"},
            {"score",    score},
            {"action",   QJsonObject{
                {"type", "open_path"},
                {"path", path},
                {"kind", kind},
            }},
        });
    }
    arg.endArray();
    return rows;
}

} // namespace

FilesPlugin::FilesPlugin(QObject* parent) : SpotlightPlugin(parent) {
    m_iface = new QDBusInterface(
        "org.aurumos.SpotlightIndexerService", // bus service name (Service-suffix convention)
        "/org/aurumos/SpotlightIndexer",       // object path
        "org.aurumos.SpotlightIndexer",        // interface name
        QDBusConnection::sessionBus(),
        this);
}

void FilesPlugin::search(const QString& query, int generation) {
    if (!m_iface->isValid() || query.trimmed().size() < 2) {
        emit resultsReady(id(), generation, {});
        return;
    }
    m_active_generation = generation;
    auto pending = m_iface->asyncCall("search", query, quint32{12});
    auto* w = new QDBusPendingCallWatcher(pending, this);
    w->setProperty("generation", generation);
    connect(w, &QDBusPendingCallWatcher::finished,
            this, &FilesPlugin::onPendingFinished);
}

void FilesPlugin::onPendingFinished(QDBusPendingCallWatcher* w) {
    w->deleteLater();
    const int gen = w->property("generation").toInt();
    QDBusPendingReply<> reply = *w;
    if (reply.isError()) {
        emit resultsReady(id(), gen, {});
        return;
    }
    emit resultsReady(id(), gen, rowsFromReply(reply.reply()));
}

} // namespace aurum::spotlight
