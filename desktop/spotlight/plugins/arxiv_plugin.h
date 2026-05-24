#pragma once

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QTimer>

#include "plugin.h"

namespace aurum::spotlight {

// Surfaces arXiv papers matching the query.
// Trigger prefix: `arxiv:` or `arxiv ` or `paper:`.
// API: https://export.arxiv.org/api/query?search_query=all:<q>&max_results=8
// The arXiv API returns Atom XML; we parse the small subset we need by hand.
class ArxivPlugin : public SpotlightPlugin {
    Q_OBJECT
public:
    explicit ArxivPlugin(QObject* parent = nullptr);

    QString id() const override          { return "arxiv"; }
    QString displayName() const override { return "arXiv"; }
    int     priority() const override    { return 4; }
    void    search(const QString& query, int generation) override;

private slots:
    void onReplyFinished();

private:
    QNetworkAccessManager m_net;
    QTimer m_debounce;
    QString m_pendingQuery;
    int m_pendingGeneration = -1;
};

} // namespace aurum::spotlight
