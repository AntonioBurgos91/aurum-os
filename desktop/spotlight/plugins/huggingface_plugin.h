#pragma once

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QTimer>

#include "plugin.h"

namespace aurum::spotlight {

// Surfaces HuggingFace models matching the query.
// Trigger: query must start with one of the prefixes `hf:`, `hf `, `model:`.
// Without the prefix we don't hit the network — otherwise every keystroke
// becomes an outbound request.
//
// API:  https://huggingface.co/api/models?search=<q>&limit=8
class HuggingFacePlugin : public SpotlightPlugin {
    Q_OBJECT
public:
    explicit HuggingFacePlugin(QObject* parent = nullptr);

    QString id() const override          { return "huggingface"; }
    QString displayName() const override { return "Hugging Face"; }
    int     priority() const override    { return 3; }
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
