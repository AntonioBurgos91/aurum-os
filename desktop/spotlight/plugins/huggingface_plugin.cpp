#include "huggingface_plugin.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkRequest>
#include <QUrl>
#include <QUrlQuery>

namespace aurum::spotlight {

namespace {

// Strip the trigger prefix and return the bare model search term.
// Returns an empty string when the query does not opt into the HF plugin.
QString stripTrigger(QString q) {
    q = q.trimmed();
    for (const auto& prefix :
         {QStringLiteral("hf:"), QStringLiteral("hf "), QStringLiteral("model:")}) {
        if (q.startsWith(prefix, Qt::CaseInsensitive)) return q.mid(prefix.size()).trimmed();
    }
    return {};
}

QJsonArray parseModels(const QByteArray& body) {
    QJsonArray rows;
    const auto doc = QJsonDocument::fromJson(body);
    if (!doc.isArray()) return rows;
    const auto arr = doc.array();
    for (const auto& v : arr) {
        const auto m = v.toObject();
        const auto id_full = m.value("id").toString();
        const auto downloads = m.value("downloads").toInt();
        const auto likes = m.value("likes").toInt();
        const auto pipeline = m.value("pipeline_tag").toString();

        rows.append(QJsonObject{
            {"title", id_full},
            {"subtitle", QString("%1  ·  ⬇ %2  ·  ♡ %3")
                             .arg(pipeline.isEmpty() ? QStringLiteral("model") : pipeline)
                             .arg(downloads)
                             .arg(likes)},
            {"icon", "applications-science"},
            {"score", 1.0},
            {"action",
             QJsonObject{
                 {"type", "open_url"},
                 {"url", "https://huggingface.co/" + id_full},
             }},
        });
    }
    return rows;
}

}  // namespace

HuggingFacePlugin::HuggingFacePlugin(QObject* parent) : SpotlightPlugin(parent) {
    // 250 ms debounce: typing "hf bert-base" shouldn't fire one request per
    // character. Network results land 1-2 round trips later anyway, so the
    // delay is invisible to the user.
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(250);
    connect(&m_debounce, &QTimer::timeout, this, [this] {
        const QString q = m_pendingQuery;
        const int gen = m_pendingGeneration;
        if (q.isEmpty()) {
            emit resultsReady(id(), gen, {});
            return;
        }

        QUrl url("https://huggingface.co/api/models");
        QUrlQuery qs;
        qs.addQueryItem("search", q);
        qs.addQueryItem("limit", "8");
        url.setQuery(qs);

        QNetworkRequest req(url);
        req.setHeader(QNetworkRequest::UserAgentHeader, "AurumOS-Spotlight/0.1");
        req.setRawHeader("Accept", "application/json");

        auto* reply = m_net.get(req);
        reply->setProperty("generation", gen);
        connect(reply, &QNetworkReply::finished, this, &HuggingFacePlugin::onReplyFinished);
    });
}

void HuggingFacePlugin::search(const QString& query, int generation) {
    const auto bare = stripTrigger(query);
    if (bare.size() < 2) {
        emit resultsReady(id(), generation, {});
        return;
    }
    m_pendingQuery = bare;
    m_pendingGeneration = generation;
    m_debounce.start();
}

void HuggingFacePlugin::onReplyFinished() {
    auto* reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    reply->deleteLater();
    const int gen = reply->property("generation").toInt();
    if (reply->error() != QNetworkReply::NoError) {
        emit resultsReady(id(), gen, {});
        return;
    }
    emit resultsReady(id(), gen, parseModels(reply->readAll()));
}

}  // namespace aurum::spotlight
