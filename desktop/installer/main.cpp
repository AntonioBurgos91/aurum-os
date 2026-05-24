// aurum-installer entry point.
//
// Loaded by the Live ISO session as the welcome wizard. Once the user clicks
// "Install", the backend invokes distinst via pkexec — the installer process
// itself stays unprivileged.

#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QString>
#include <QUrl>

#include "core_services.h"
#include "disk_lister.h"
#include "installer_backend.h"
#include "style_engine.h"

int main(int argc, char* argv[]) {
    init_core_services();
    QApplication app(argc, argv);
    app.setApplicationName("aurum-installer");
    app.setDesktopFileName("aurum-installer");
    init_aqua_style();

    aurum::installer::DiskLister     diskLister;
    aurum::installer::InstallerBackend backend;

    QQmlApplicationEngine engine;
    engine.addImportPath("/usr/lib/qt6/qml");
    engine.addImportPath("/usr/local/lib/qt6/qml");
    const auto dev = qEnvironmentVariable("AURUM_QML_IMPORT_PATH");
    if (!dev.isEmpty()) engine.addImportPath(dev);

    auto* ctx = engine.rootContext();
    ctx->setContextProperty("diskLister", &diskLister);
    ctx->setContextProperty("backend",    &backend);

    const QString qml = resolve_qml_path("Installer.qml", argv[0]);
    engine.load(QUrl::fromLocalFile(qml));
    if (engine.rootObjects().isEmpty()) return 1;
    return app.exec();
}
