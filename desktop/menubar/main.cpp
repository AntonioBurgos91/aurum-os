// aurum-menubar entry point.
//
// SystemClient exposes the values the top strip reads at ~1 Hz:
//   - systemTime / focusedApp                 (host-local state)
//   - gpuUtilization / vramUsedGb / vramTotalGb / gpuTemp (D-Bus → gpu-monitor)
//   - netThroughput                           (RX delta from /proc/net/dev)

#include <QApplication>
#include <QDateTime>
#include <QDebug>
#include <QFile>
#include <QObject>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QRegularExpression>
#include <QString>
#include <QTextStream>
#include <QTimer>
#include <QUrl>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusReply>

#include "core_services.h"
#include "ml_integrations.h"
#include "style_engine.h"

class SystemClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString systemTime READ systemTime NOTIFY changed)
    Q_PROPERTY(QString focusedApp READ focusedApp NOTIFY changed)
    Q_PROPERTY(int gpuUtilization READ gpuUtilization NOTIFY changed)
    Q_PROPERTY(double vramUsedGb READ vramUsedGb NOTIFY changed)
    Q_PROPERTY(double vramTotalGb READ vramTotalGb NOTIFY changed)
    Q_PROPERTY(int gpuTemp READ gpuTemp NOTIFY changed)
    Q_PROPERTY(QString gpuName READ gpuName NOTIFY changed)
    Q_PROPERTY(QString netThroughput READ netThroughput NOTIFY changed)

public:
    explicit SystemClient(QObject* parent = nullptr) : QObject(parent) {
        m_iface = new QDBusInterface("org.aurumos.GpuMonitorService", "/org/aurumos/GpuMonitor",
                                     "org.aurumos.GpuMonitor", QDBusConnection::sessionBus(), this);
        m_lastRx = readTotalRxBytes();
        auto* t = new QTimer(this);
        connect(t, &QTimer::timeout, this, &SystemClient::tick);
        t->start(1000);
        tick();
    }

    QString systemTime() const {
        return m_time;
    }
    QString focusedApp() const {
        return m_focusedApp;
    }
    int gpuUtilization() const {
        return m_util;
    }
    double vramUsedGb() const {
        return m_used / 1073741824.0;
    }
    double vramTotalGb() const {
        return m_total / 1073741824.0;
    }
    int gpuTemp() const {
        return m_temp;
    }
    QString gpuName() const {
        return m_name;
    }
    QString netThroughput() const {
        return m_net;
    }

signals:
    void changed();

private slots:
    void tick() {
        m_time = QDateTime::currentDateTime().toString("ddd d MMM  h:mm AP");
        pollGpu();
        pollNet();
        pollFocusedApp();
        emit changed();
    }

private:
    void pollGpu() {
        if (!m_iface->isValid()) {
            m_name = "—";
            m_util = 0;
            m_temp = 0;
            m_used = 0;
            m_total = 0;
            return;
        }
        if (auto r = QDBusReply<QString>(m_iface->call("gpu_name")); r.isValid())
            m_name = r.value();
        else
            qWarning() << "[gpu-client] D-Bus call failed:" << r.error().message();
        if (auto r = QDBusReply<uint>(m_iface->call("gpu_utilization")); r.isValid())
            m_util = static_cast<int>(r.value());
        else
            qWarning() << "[gpu-client] D-Bus call failed:" << r.error().message();
        if (auto r = QDBusReply<qulonglong>(m_iface->call("vram_used")); r.isValid())
            m_used = r.value();
        else
            qWarning() << "[gpu-client] D-Bus call failed:" << r.error().message();
        if (auto r = QDBusReply<qulonglong>(m_iface->call("vram_total")); r.isValid())
            m_total = r.value();
        else
            qWarning() << "[gpu-client] D-Bus call failed:" << r.error().message();
        if (auto r = QDBusReply<uint>(m_iface->call("temperature")); r.isValid())
            m_temp = static_cast<int>(r.value());
        else
            qWarning() << "[gpu-client] D-Bus call failed:" << r.error().message();
    }

    void pollNet() {
        const qulonglong now = readTotalRxBytes();
        const qulonglong delta = now >= m_lastRx ? now - m_lastRx : 0;
        const double mbps = static_cast<double>(delta) / (1024.0 * 1024.0);
        m_net = mbps < 0.1 ? QString::number(mbps * 1024.0, 'f', 1) + " KB/s"
                           : QString::number(mbps, 'f', 1) + " MB/s";
        m_lastRx = now;
    }

    // Best-effort: ask hyprctl for the active window's class. Falls back to
    // empty string if hyprctl is unavailable (e.g. running outside Hyprland).
    // Reads at 1 Hz so this is cheap.
    void pollFocusedApp() {
        QProcess p;
        p.start("hyprctl", {"activewindow", "-j"});
        if (!p.waitForFinished(120)) {
            m_focusedApp.clear();
            return;
        }
        const auto out = p.readAllStandardOutput();
        // Avoid pulling QJsonDocument for one field — regex is fine.
        static const QRegularExpression re("\"class\"\\s*:\\s*\"([^\"]*)\"");
        const auto m = re.match(QString::fromUtf8(out));
        m_focusedApp = m.hasMatch() ? m.captured(1) : QString{};
    }

    qulonglong readTotalRxBytes() const {
        QFile f("/proc/net/dev");
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return 0;
        QTextStream in(&f);
        qulonglong total = 0;
        int line = 0;
        while (!in.atEnd()) {
            const auto raw = in.readLine();
            if (++line <= 2) continue;
            const auto parts = raw.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
            // Skip the loopback so we measure real network throughput.
            if (parts.size() > 1 && !parts.first().startsWith("lo:"))
                total += parts.at(1).toULongLong();
        }
        return total;
    }

    QDBusInterface* m_iface = nullptr;
    QString m_time;
    QString m_focusedApp;
    QString m_name = "—";
    QString m_net = "0.0 KB/s";
    int m_util = 0;
    int m_temp = 0;
    qulonglong m_used = 0;
    qulonglong m_total = 0;
    qulonglong m_lastRx = 0;
};

int main(int argc, char* argv[]) {
    init_core_services();
    init_ml_integrations();

    QApplication app(argc, argv);
    app.setApplicationName("aurum-menubar");
    app.setDesktopFileName("aurum-menubar");
    init_aqua_style();

    SystemClient systemClient;

    QQmlApplicationEngine engine;
    engine.addImportPath("/usr/lib/qt6/qml");
    engine.addImportPath("/usr/local/lib/qt6/qml");
    const auto dev = qEnvironmentVariable("AURUM_QML_IMPORT_PATH");
    if (!dev.isEmpty()) engine.addImportPath(dev);

    engine.rootContext()->setContextProperty("systemClient", &systemClient);
    // Some applets read from gpuClient (legacy QML); alias to systemClient so
    // either name works in the menubar QML during the transition.
    engine.rootContext()->setContextProperty("gpuClient", &systemClient);

    const QString qml = resolve_qml_path("MenuBar.qml", argv[0]);
    engine.load(QUrl::fromLocalFile(qml));
    if (engine.rootObjects().isEmpty()) return 1;

    return app.exec();
}

#include "main.moc"
