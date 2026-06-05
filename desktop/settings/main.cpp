// aurum-settings entry point.
//
// Five sections (General, GPU, CUDA, Venvs, MLOps), each backed by a thin
// C++ manager exposed as a QML context property. Wayland-native; Fusion
// palette via aqua-qt.

#include <QApplication>
#include <QDebug>
#include <QObject>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QString>
#include <QUrl>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>

#include "core_services.h"
#include "cuda_manager.h"
#include "display_manager.h"
#include "mlops_config.h"
#include "model_packs_model.h"
#include "profile_client.h"
#include "style_engine.h"
#include "venv_manager.h"

// --- Shared GPU live values (same shape as the dock's GpuClient) ----------
// Kept here as a local class so we don't pull a dependency on the dock target.
#include <QTimer>
#include <QtDBus/QDBusReply>

class GpuLiveBridge : public QObject {
    Q_OBJECT
    Q_PROPERTY(int gpuUtilization READ gpuUtilization NOTIFY changed)
    Q_PROPERTY(int gpuTemp READ gpuTemp NOTIFY changed)
    Q_PROPERTY(double vramUsedGb READ vramUsedGb NOTIFY changed)
    Q_PROPERTY(double vramTotalGb READ vramTotalGb NOTIFY changed)
    Q_PROPERTY(QString gpuName READ gpuName NOTIFY changed)
public:
    explicit GpuLiveBridge(QObject* parent = nullptr) : QObject(parent) {
        m_iface = new QDBusInterface("org.aurumos.GpuMonitorService", "/org/aurumos/GpuMonitor",
                                     "org.aurumos.GpuMonitor", QDBusConnection::sessionBus(), this);
        auto* t = new QTimer(this);
        connect(t, &QTimer::timeout, this, &GpuLiveBridge::tick);
        t->start(1500);
        tick();
    }
    int gpuUtilization() const {
        return m_util;
    }
    int gpuTemp() const {
        return m_temp;
    }
    double vramUsedGb() const {
        return m_used / 1073741824.0;
    }
    double vramTotalGb() const {
        return m_total / 1073741824.0;
    }
    QString gpuName() const {
        return m_name;
    }
signals:
    void changed();
private slots:
    void tick() {
        if (!m_iface->isValid()) {
            emit changed();
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
        emit changed();
    }

private:
    QDBusInterface* m_iface = nullptr;
    int m_util = 0, m_temp = 0;
    qulonglong m_used = 0, m_total = 0;
    QString m_name = "—";
};

int main(int argc, char* argv[]) {
    init_core_services();

    QApplication app(argc, argv);
    app.setApplicationName("aurum-settings");
    app.setDesktopFileName("aurum-settings");
    init_aqua_style();

    aurum::settings::CudaManager cudaManager;
    aurum::settings::DisplayManager displayManager;
    aurum::settings::VenvManager venvManager;
    aurum::settings::MlopsConfig mlopsConfig;
    aurum::settings::ModelPacksModel modelPacksModel;
    GpuLiveBridge gpuLive;

    QQmlApplicationEngine engine;
    engine.addImportPath("/usr/lib/qt6/qml");
    engine.addImportPath("/usr/local/lib/qt6/qml");
    const auto dev = qEnvironmentVariable("AURUM_QML_IMPORT_PATH");
    if (!dev.isEmpty()) engine.addImportPath(dev);

    auto* ctx = engine.rootContext();
    ctx->setContextProperty("cudaManager", &cudaManager);
    ctx->setContextProperty("displayMgr", &displayManager);
    ctx->setContextProperty("venvManager", &venvManager);
    ctx->setContextProperty("mlopsConfig", &mlopsConfig);
    ctx->setContextProperty("modelPacksModel", &modelPacksModel);
    ctx->setContextProperty("gpuLive", &gpuLive);
    // ProfileClient is a process-wide singleton (libs/core-services). HardwarePanel.qml
    // binds to its CONSTANT properties; no signals needed unless the user
    // re-runs detection at runtime via the override button.
    ctx->setContextProperty("profileClient", &aurum::ProfileClient::instance());

    const QString qml = resolve_qml_path("Settings.qml", argv[0]);
    engine.load(QUrl::fromLocalFile(qml));
    if (engine.rootObjects().isEmpty()) return 1;
    return app.exec();
}

#include "main.moc"
