#include "arxiv_plugin.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QNetworkRequest>
#include <QString>
#include <QUrl>
#include <QUrlQuery>
#include <QXmlStreamReader>

namespace aurum::spotlight {

namespace {

QString stripTrigger(QString q) {
    q = q.trimmed();
    for (const auto& prefix :
         {QStringLiteral("arxiv:"), QStringLiteral("arxiv "), QStringLiteral("paper:")}) {
        if (q.startsWith(prefix, Qt::CaseInsensitive)) return q.mid(prefix.size()).trimmed();
    }
    return {};
}

// arXiv returns Atom XML. Pull out enough to build a row per <entry>:
//   <id>     → absolute paper URL (also yields the arXiv id)
//   <title>  → paper title
//   <author><name>... → first author
QJsonArray parseAtom(const QByteArray& body) {
    QJsonArray rows;
    QXmlStreamReader r(body);
    QString id, title, firstAuthor;
    bool inEntry = false, inAuthor = false;
    while (!r.atEnd() && !r.hasError()) {
        const auto tok = r.readNext();
        if (tok == QXmlStreamReader::StartElement) {
            const auto name = r.name().toString();
            if (name == "entry") {
                inEntry = true;
                id.clear();
                title.clear();
                firstAuthor.clear();
            } else if (name == "author") {
                inAuthor = true;
            } else if (inEntry && name == "id")
                id = r.readElementText();
            else if (inEntry && name == "title")
                title = r.readElementText().simplified();
            else if (inAuthor && name == "name" && firstAuthor.isEmpty())
                firstAuthor = r.readElementText();
        } else if (tok == QXmlStreamReader::EndElement) {
            const auto name = r.name().toString();
            if (name == "author")
                inAuthor = false;
            else if (name == "entry") {
                inEntry = false;
                if (!id.isEmpty() && !title.isEmpty()) {
                    rows.append(QJsonObject{
                        {"title", title},
                        {"subtitle", firstAuthor.isEmpty() ? id : firstAuthor + "  ·  " + id},
                        {"icon", "accessories-document-viewer"},
                        {"score", 1.0},
                        {"action",
                         QJsonObject{
                             {"type", "open_url"},
                             {"url", id},
                         }},
                    });
                }
            }
        }
    }
    return rows;
}

}  // namespace

ArxivPlugin::ArxivPlugin(QObject* parent) : SpotlightPlugin(parent) {
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(350);
    connect(&m_debounce, &QTimer::timeout, this, [this] {
        const QString q = m_pendingQuery;
        const int gen = m_pendingGeneration;
        if (q.isEmpty()) {
            emit resultsReady(id(), gen, {});
            return;
        }

        QUrl url("https://export.arxiv.org/api/query");
        QUrlQuery qs;
        qs.addQueryItem("search_query", "all:" + q);
        qs.addQueryItem("max_results", "8");
        qs.addQueryItem("sortBy", "relevance");
        url.setQuery(qs);

        QNetworkRequest req(url);
        req.setHeader(QNetworkRequest::UserAgentHeader, "AurumOS-Spotlight/0.1");

        auto* reply = m_net.get(req);
        reply->setProperty("generation", gen);
        connect(reply, &QNetworkReply::finished, this, &ArxivPlugin::onReplyFinished);
    });
}

void ArxivPlugin::search(const QString& query, int generation) {
    const auto bare = stripTrigger(query);
    if (bare.size() < 2) {
        emit resultsReady(id(), generation, {});
        return;
    }
    m_pendingQuery = bare;
    m_pendingGeneration = generation;
    m_debounce.start();
}

void ArxivPlugin::onReplyFinished() {
    auto* reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    reply->deleteLater();
    const int gen = reply->property("generation").toInt();
    if (reply->error() != QNetworkReply::NoError) {
        emit resultsReady(id(), gen, {});
        return;
    }
    emit resultsReady(id(), gen, parseAtom(reply->readAll()));
}

}  // namespace aurum::spotlight
