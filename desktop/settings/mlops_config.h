#pragma once

#include <QObject>
#include <QString>

namespace aurum::settings {

// Reads / writes ~/.config/aurum/mlops.toml. We keep a hand-rolled mini TOML
// reader instead of pulling tomlplusplus into aurum-settings — the file has
// at most 4 keys, hand-coding is clearer than introducing another dep just
// for the Settings panel.
//
// File schema:
//   [mlflow]
//   tracking_uri = "http://localhost:5000"
//   experiment   = "Default"
//
//   [wandb]
//   api_key = ""
//   entity  = ""
class MlopsConfig : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString mlflowTrackingUri READ mlflowTrackingUri WRITE setMlflowTrackingUri NOTIFY changed)
    Q_PROPERTY(QString mlflowExperiment  READ mlflowExperiment  WRITE setMlflowExperiment  NOTIFY changed)
    Q_PROPERTY(QString wandbApiKey       READ wandbApiKey       WRITE setWandbApiKey       NOTIFY changed)
    Q_PROPERTY(QString wandbEntity       READ wandbEntity       WRITE setWandbEntity       NOTIFY changed)

public:
    explicit MlopsConfig(QObject* parent = nullptr);

    QString mlflowTrackingUri() const { return m_mlflowTrackingUri; }
    QString mlflowExperiment()  const { return m_mlflowExperiment; }
    QString wandbApiKey()       const { return m_wandbApiKey; }
    QString wandbEntity()       const { return m_wandbEntity; }

    void setMlflowTrackingUri(const QString& v);
    void setMlflowExperiment(const QString& v);
    void setWandbApiKey(const QString& v);
    void setWandbEntity(const QString& v);

    Q_INVOKABLE bool save();
    Q_INVOKABLE bool reload();

signals:
    void changed();

private:
    void load();

    QString m_mlflowTrackingUri;
    QString m_mlflowExperiment;
    QString m_wandbApiKey;
    QString m_wandbEntity;
};

} // namespace aurum::settings
