#include "installer_backend.h"

#include <QFileInfo>
#include <QRegularExpression>

namespace aurum::installer {

namespace {

// Source squashfs shipped on the Live ISO. Pop!_OS's casper layout places it
// here; AurumOS inherits that path via the ISO builder.
constexpr auto kSquashfs = "/cdrom/casper/filesystem.squashfs";

}  // namespace

InstallerBackend::InstallerBackend(QObject* parent) : QObject(parent) {
    m_proc.setProcessChannelMode(QProcess::SeparateChannels);
    connect(&m_proc, &QProcess::readyReadStandardOutput, this,
            &InstallerBackend::onReadyReadStdout);
    connect(&m_proc, &QProcess::readyReadStandardError, this, &InstallerBackend::onReadyReadStderr);
    connect(&m_proc, &QProcess::finished, this, &InstallerBackend::onFinished);
}

QString InstallerBackend::validate() const {
    if (m_device.isEmpty() || !m_device.startsWith("/dev/")) return "No target disk selected";
    if (m_username.isEmpty()) return "Username is required";
    static const QRegularExpression userRe(R"(^[a-z_][a-z0-9_-]{0,31}$)");
    if (!userRe.match(m_username).hasMatch())
        return "Username must be lowercase, start with a letter, ≤32 chars";
    if (m_password.size() < 8) return "Password must be at least 8 characters";
    if (m_hostname.isEmpty()) return "Hostname is required";
    return {};
}

QStringList InstallerBackend::commandPreview() const {
    // distinst CLI surface (see distinst --help). We deliberately call the
    // simple all-in-one mode rather than the "blocks" sub-command, so the
    // installer is constrained to whole-disk installs for Phase 6. Custom
    // partition layouts come in a later release.
    QStringList args = {
        "--block",      m_device,
        "--bootloader", QFileInfo::exists("/sys/firmware/efi/efivars") ? "efi" : "bios",
        "--filesystem", m_filesystem,
        "--squashfs",   kSquashfs,
        "--hostname",   m_hostname,
        "--keyboard",   m_keyboard,
        "--lang",       m_locale,
        "--remove",     "/cdrom/casper/filesystem.manifest-remove",
        "--username",   m_username,
        "--realname",   m_fullName.isEmpty() ? m_username : m_fullName,
        "--password",   m_password,
        "--timezone",   m_timezone,
    };
    if (m_encryptDisk) args << "--encrypt-disk" << m_password;
    return args;
}

bool InstallerBackend::start() {
    if (!validate().isEmpty()) return false;
    if (m_running) return false;

    m_progress = 0;
    m_succeeded = false;
    m_status = "Starting…";
    m_log.clear();
    emit progressChanged();
    emit logAppended();

    m_running = true;
    emit runningChanged();

    // distinst MUST run as root. From the live session we always launch
    // via pkexec; the polkit action `org.aurumos.installer.run` allows it.
    QStringList full;
    full << "distinst";
    full << commandPreview();
    m_proc.start("pkexec", full);
    return true;
}

void InstallerBackend::cancel() {
    if (!m_running) return;
    m_proc.terminate();
    if (!m_proc.waitForFinished(2000)) m_proc.kill();
}

void InstallerBackend::onReadyReadStdout() {
    const auto data = QString::fromUtf8(m_proc.readAllStandardOutput());
    for (const auto& line : data.split('\n', Qt::SkipEmptyParts)) {
        appendLog(line);
        parseProgressLine(line);
    }
}

void InstallerBackend::onReadyReadStderr() {
    const auto data = QString::fromUtf8(m_proc.readAllStandardError());
    for (const auto& line : data.split('\n', Qt::SkipEmptyParts)) appendLog(line);
}

void InstallerBackend::onFinished(int exitCode, QProcess::ExitStatus status) {
    m_running = false;
    m_succeeded = (status == QProcess::NormalExit && exitCode == 0);
    m_status = m_succeeded ? "Done" : QString("Failed (exit %1)").arg(exitCode);
    m_progress = m_succeeded ? 100 : m_progress;
    emit runningChanged();
    emit progressChanged();
}

void InstallerBackend::appendLog(const QString& line) {
    // Keep the log buffer bounded: a full install emits a few thousand lines
    // and we don't want the UI to lock up rendering all of them.
    m_log += line + '\n';
    if (m_log.size() > 200'000) m_log = m_log.right(150'000);
    emit logAppended();
}

void InstallerBackend::parseProgressLine(const QString& line) {
    // distinst progress format on stdout: "STEP <NAME> <PERCENT>"
    // Plus textual phase markers we surface as the visible status.
    static const QRegularExpression step(R"(^STEP\s+(\S+)\s+(\d+))");
    const auto m = step.match(line);
    if (m.hasMatch()) {
        m_status = m.captured(1);
        m_progress = m.captured(2).toInt();
        emit progressChanged();
    }
}

}  // namespace aurum::installer
