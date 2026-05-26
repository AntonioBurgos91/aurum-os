#pragma once

// AurumOS Settings — Model Packs panel backend.
//
// Reads pack manifests from /etc/aurum/model-packs/*.yaml (written by the
// `aurum-model-pack` CLI, owned by Agent I) and exposes them to QML as a
// QAbstractListModel. Install/remove actions shell out to that same CLI via
// QProcess, parsing line-buffered progress on stdout.
//
// The CLI <-> GUI progress protocol (must match Agent I's writer):
//   PROGRESS:<pack_id>:<percent_int_0_100>      e.g. "PROGRESS:coding:42"
//   DONE:<pack_id>                              terminal success
//   ERROR:<pack_id>:<short_message>             terminal failure
//   STAGE:<pack_id>:<free_text>                 (optional) human-readable phase
//
// Lines that don't match any of the above are forwarded to qInfo() for debug
// but otherwise ignored. The CLI is expected to flush its stdout linewise
// (Python: `print(..., flush=True)`; Bash: `stdbuf -oL`).

#include <QAbstractListModel>
#include <QHash>
#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVector>
#include <QtGlobal>

namespace aurum::settings {

// Q_GADGET so QML can read fields of an individual pack via property syntax.
// The list-view itself uses role names (see ModelPacksModel::roleNames), but
// the gadget is handy for the install/remove dialogs and single-pack views.
class ModelPack {
    Q_GADGET
    Q_PROPERTY(QString id MEMBER id)
    Q_PROPERTY(QString title MEMBER title)
    Q_PROPERTY(QString description MEMBER description)
    Q_PROPERTY(qint64 sizeBytes MEMBER sizeBytes)
    Q_PROPERTY(QString minProfile MEMBER minProfile)
    Q_PROPERTY(QString docsUrl MEMBER docsUrl)
    Q_PROPERTY(QString state MEMBER state)
    Q_PROPERTY(int progress MEMBER progress)
    Q_PROPERTY(QString lastError MEMBER lastError)

public:
    QString id;
    QString title;
    QString description;
    qint64 sizeBytes = 0;
    QString minProfile;  // lite | standard | pro | workstation
    QString docsUrl;
    QString state = "not_installed";  // not_installed | installed | installing | error
    int progress = 0;
    QString lastError;
};

class ModelPacksModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(QString currentProfile READ currentProfile NOTIFY currentProfileChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        TitleRole,
        DescriptionRole,
        SizeBytesRole,
        SizeHumanRole,
        MinProfileRole,
        DocsUrlRole,
        StateRole,
        ProgressRole,
        LastErrorRole,
        MeetsProfileRole,
    };
    Q_ENUM(Roles)

    explicit ModelPacksModel(QObject* parent = nullptr);
    ~ModelPacksModel() override;

    // QAbstractListModel API.
    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString currentProfile() const {
        return m_currentProfile;
    }

    // --- QML-callable actions ------------------------------------------------
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void install(const QString& packId);
    Q_INVOKABLE void remove(const QString& packId);

    // Cache management (delegates to the CLI for accurate accounting, but
    // also falls back to a directory walk if the CLI is unavailable).
    Q_INVOKABLE qint64 cacheSize();
    Q_INVOKABLE QString cachePath() const;
    Q_INVOKABLE void clearCache();

    // Utility for QML: pretty-print byte counts ("12.0 GB", "850 MB").
    Q_INVOKABLE QString humanSize(qint64 bytes) const;

    // Is the user's current profile at least `minProfile`? Drives the
    // greyed-out badge in the UI. lite < standard < pro < workstation.
    Q_INVOKABLE bool meetsProfile(const QString& minProfile) const;

signals:
    void currentProfileChanged();
    void countChanged();
    void packStateChanged(const QString& id);
    void installProgress(const QString& id, int percent);
    void installFinished(const QString& id, bool ok, const QString& message);

private slots:
    void onProcReadyRead();
    void onProcFinished(int exitCode, QProcess::ExitStatus exitStatus);

private:
    static constexpr const char* kManifestDir = "/etc/aurum/model-packs";
    static constexpr const char* kCliBinary = "aurum-model-pack";
    static constexpr const char* kProfileConf = "/etc/aurum/profile.conf";

    void scanManifests();
    void detectProfile();
    int indexOf(const QString& packId) const;
    void emitDataChanged(int row);
    void handleProgressLine(const QByteArray& line);
    static int profileRank(const QString& profile);
    static QString defaultCachePath();

    QVector<ModelPack> m_packs;
    QString m_currentProfile = "standard";

    // The set of running install/remove subprocesses, keyed by pack id.
    // Removal is synchronous (fast); only install is tracked here. The
    // QProcess is parented to `this`, deleted on finish.
    struct RunningJob {
        QProcess* proc = nullptr;
        QByteArray buf;  // line-buffer for stdout
        QString op;      // "install" or "remove"
    };
    QHash<QString, RunningJob> m_jobs;
};

}  // namespace aurum::settings
