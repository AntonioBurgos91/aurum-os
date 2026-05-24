// aurum-mission-control entry point.
//
// Fullscreen Wayland overlay that snapshots Hyprland's workspaces + clients at
// open time and lets the user click any window to focus it. Closes itself on
// ESC, click-outside-a-window-card, or when a focus action fires.

#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>

#include "core_services.h"
#include "hypr_client.h"
#include "style_engine.h"

int main(int argc, char* argv[]) {
    init_core_services();
    QApplication app(argc, argv);
    app.setApplicationName("aurum-mission-control");
    app.setDesktopFileName("aurum-mission-control");
    init_aqua_style();

    aurum::mc::HyprClient hyprClient;

    QQmlApplicationEngine engine;
    engine.addImportPath("/usr/lib/qt6/qml");
    engine.addImportPath("/usr/local/lib/qt6/qml");
    const auto dev = qEnvironmentVariable("AURUM_QML_IMPORT_PATH");
    if (!dev.isEmpty()) engine.addImportPath(dev);

    engine.rootContext()->setContextProperty("hypr", &hyprClient);

    const QString qml = resolve_qml_path("MissionControl.qml", argv[0]);
    engine.load(QUrl::fromLocalFile(qml));
    if (engine.rootObjects().isEmpty()) return 1;
    return app.exec();
}
