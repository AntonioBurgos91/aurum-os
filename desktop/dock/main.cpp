// aurum-dock entry point.
//
// Bridges three things into QML:
//   - DockModel: pinned launchers parsed from XDG .desktop files
//   - GpuClient: live NVML metrics over the session bus
//   - aqua-qt:   palette + Fusion base style
//
// The QML file is loaded from /usr/share/aurum-os/qml/Dock.qml in production
// and overridable via $AURUM_QML_DIR during development.

#include <QApplication>
#include <QDebug>
#include <QIcon>
#include <QObject>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QString>
#include <QTimer>
#include <QUrl>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusReply>

#include "core_services.h"
#include "dock_model.h"
#include "style_engine.h"

// --- GPU bridge -----------------------------------------------------------
class GpuClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(int     gpuUtilization READ gpuUtilization NOTIFY changed)
    Q_PROPERTY(double  vramUsedGb     READ vramUsedGb     NOTIFY changed)
    Q_PROPERTY(double  vramTotalGb    READ vramTotalGb    NOTIFY changed)
    Q_PROPERTY(int     gpuTemp        READ gpuTemp        NOTIFY changed)
    Q_PROPERTY(QString gpuName        READ gpuName        NOTIFY changed)

public:
    explicit GpuClient(QObject* parent = nullptr) : QObject(parent) {
        m_iface = new QDBusInterface(
            "org.aurumos.GpuMonitorService",
            "/org/aurumos/GpuMonitor",
            "org.aurumos.GpuMonitor",
            QDBusConnection::sessionBus(),
            this);

        auto* t = new QTimer(this);
        connect(t, &QTimer::timeout, this, &GpuClient::tick);
        t->start(1000);
        tick();
    }

    int     gpuUtilization() const { return m_util; }
    double  vramUsedGb()     const { return m_used / 1073741824.0; }
    double  vramTotalGb()    const { return m_total / 1073741824.0; }
    int     gpuTemp()        const { return m_temp; }
    QString gpuName()        const { return m_name; }

signals:
    void changed();

private slots:
    void tick() {
        if (!m_iface->isValid()) {
            m_name  = "GPU monitor offline";
            m_util  = 0;
            m_used  = 0;
            m_total = 0;
            m_temp  = 0;
            emit changed();
            return;
        }
        // Each call is independent; if one fails we keep the previous value
        // but log via qWarning so daemon outages are diagnosable in the log.
        if (auto r = QDBusReply<QString>    (m_iface->call("gpu_name"));         r.isValid()) m_name  = r.value();
        else qWarning() << "[gpu-client] D-Bus call failed:" << r.error().message();
        if (auto r = QDBusReply<uint>       (m_iface->call("gpu_utilization"));  r.isValid()) m_util  = static_cast<int>(r.value());
        else qWarning() << "[gpu-client] D-Bus call failed:" << r.error().message();
        if (auto r = QDBusReply<qulonglong> (m_iface->call("vram_total"));       r.isValid()) m_total = r.value();
        else qWarning() << "[gpu-client] D-Bus call failed:" << r.error().message();
        if (auto r = QDBusReply<qulonglong> (m_iface->call("vram_used"));        r.isValid()) m_used  = r.value();
        else qWarning() << "[gpu-client] D-Bus call failed:" << r.error().message();
        if (auto r = QDBusReply<uint>       (m_iface->call("temperature"));      r.isValid()) m_temp  = static_cast<int>(r.value());
        else qWarning() << "[gpu-client] D-Bus call failed:" << r.error().message();
        emit changed();
    }

private:
    QDBusInterface*   m_iface = nullptr;
    int               m_util  = 0;
    int               m_temp  = 0;
    qulonglong        m_used  = 0;
    qulonglong        m_total = 0;
    QString           m_name  = "—";
};

int main(int argc, char* argv[]) {
    // Defensive PATH bootstrap. Hyprland on some installs strips PATH from the
    // env it passes to children; without /usr/bin, our `hyprctl` dedup lookup
    // in libcore-services would fail and clicks would spawn duplicate windows.
    // Use setenv with overwrite=0 so a user-set PATH wins.
    if (!qEnvironmentVariableIsSet("PATH")) {
        qputenv("PATH", "/usr/local/bin:/usr/bin:/bin");
    }

    init_core_services();
    QApplication app(argc, argv);
    app.setApplicationName("aurum-dock");
    app.setDesktopFileName("aurum-dock");
    init_aqua_style();

    aurum::dock::DockModel dockModel;
    GpuClient gpuClient;

    QQmlApplicationEngine engine;

    // Ensure the installed Aurum.Aqua QML module is importable. CMAKE_INSTALL_PREFIX
    // is baked in below; we also pick up XDG_DATA_DIRS so a sideload works.
    engine.addImportPath("/usr/lib/qt6/qml");
    engine.addImportPath("/usr/local/lib/qt6/qml");
    const auto dev = qEnvironmentVariable("AURUM_QML_IMPORT_PATH");
    if (!dev.isEmpty()) engine.addImportPath(dev);

    auto* ctx = engine.rootContext();
    ctx->setContextProperty("dockModel",  &dockModel);
    ctx->setContextProperty("gpuClient",  &gpuClient);

    const QString qml = resolve_qml_path("Dock.qml", argv[0]);
    engine.load(QUrl::fromLocalFile(qml));
    if (engine.rootObjects().isEmpty()) return 1;

    return app.exec();
}

#include "main.moc"
