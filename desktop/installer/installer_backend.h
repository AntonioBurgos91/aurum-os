#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>

namespace aurum::installer {

// Drives the actual install by shelling out to `distinst` (the Pop!_OS install
// backend; MIT, written in Rust). We keep the C++ side responsible only for
// (a) collecting user choices, (b) producing the distinst CLI invocation,
// (c) streaming progress + log lines back into QML.
//
// Why distinst instead of a hand-rolled bcachefs/zfs installer for Phase 6:
//   - distinst already handles GRUB / systemd-boot installation, locale,
//     keyboard, user creation, and squashfs unpacking against a wide range
//     of disk layouts.
//   - The deviating bit on AurumOS is bcachefs as the rootfs, which distinst
//     supports via --filesystem bcachefs in recent releases (>= 0.7).
class InstallerBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString device      MEMBER m_device      NOTIFY paramsChanged)
    Q_PROPERTY(QString filesystem  MEMBER m_filesystem  NOTIFY paramsChanged)
    Q_PROPERTY(QString hostname    MEMBER m_hostname    NOTIFY paramsChanged)
    Q_PROPERTY(QString fullName    MEMBER m_fullName    NOTIFY paramsChanged)
    Q_PROPERTY(QString username    MEMBER m_username    NOTIFY paramsChanged)
    Q_PROPERTY(QString password    MEMBER m_password    NOTIFY paramsChanged)
    Q_PROPERTY(QString locale      MEMBER m_locale      NOTIFY paramsChanged)
    Q_PROPERTY(QString keyboard    MEMBER m_keyboard    NOTIFY paramsChanged)
    Q_PROPERTY(QString timezone    MEMBER m_timezone    NOTIFY paramsChanged)
    Q_PROPERTY(bool encryptDisk    MEMBER m_encryptDisk NOTIFY paramsChanged)

    Q_PROPERTY(int progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString status READ status NOTIFY progressChanged)
    Q_PROPERTY(QString lastLog READ lastLog NOTIFY logAppended)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(bool succeeded READ succeeded NOTIFY runningChanged)

public:
    explicit InstallerBackend(QObject* parent = nullptr);

    int progress() const     { return m_progress; }
    QString status() const   { return m_status; }
    QString lastLog() const  { return m_log; }
    bool running() const     { return m_running; }
    bool succeeded() const   { return m_succeeded; }

    // Validate the collected parameters; returns empty string if OK,
    // otherwise a human-readable reason. QML calls this before "Install".
    Q_INVOKABLE QString validate() const;

    // Kick off the install. Returns false synchronously if validation fails.
    Q_INVOKABLE bool start();

    // Abort an in-flight install (best-effort). distinst cleans up its mounts.
    Q_INVOKABLE void cancel();

    // The fully-assembled distinst command line, for the "Summary" page.
    Q_INVOKABLE QStringList commandPreview() const;

signals:
    void paramsChanged();
    void progressChanged();
    void logAppended();
    void runningChanged();

private slots:
    void onReadyReadStdout();
    void onReadyReadStderr();
    void onFinished(int exitCode, QProcess::ExitStatus status);

private:
    void appendLog(const QString& line);
    void parseProgressLine(const QString& line);

    QString m_device      = "/dev/nvme0n1";
    QString m_filesystem  = "bcachefs";   // AurumOS default; ADR-0004
    QString m_hostname    = "aurumos";
    QString m_fullName;
    QString m_username;
    QString m_password;
    QString m_locale      = "en_US.UTF-8";
    QString m_keyboard    = "us";
    QString m_timezone    = "Etc/UTC";
    bool    m_encryptDisk = false;

    QProcess m_proc;
    int      m_progress = 0;
    QString  m_status   = "Idle";
    QString  m_log;
    bool     m_running   = false;
    bool     m_succeeded = false;
};

} // namespace aurum::installer
