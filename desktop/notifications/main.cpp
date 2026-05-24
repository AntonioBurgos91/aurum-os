// aurum-notifications — top-right notification panel.
//
// Today this is a static "Welcome to AurumOS" card; the real notification
// dispatch will arrive via D-Bus org.freedesktop.Notifications. The window
// itself is frameless, on-top, transparent-background, and lives on the
// right edge of the screen — same visual language as the dock + menubar.

#include <QApplication>
#include <QQmlApplicationEngine>
#include <QString>
#include <QUrl>

#include "core_services.h"
#include "style_engine.h"

int main(int argc, char* argv[]) {
    init_core_services();

    QApplication app(argc, argv);
    app.setApplicationName("aurum-notifications");
    app.setDesktopFileName("aurum-notifications");
    init_aqua_style();

    QQmlApplicationEngine engine;
    engine.addImportPath("/usr/lib/qt6/qml");
    engine.addImportPath("/usr/local/lib/qt6/qml");
    const auto dev = qEnvironmentVariable("AURUM_QML_IMPORT_PATH");
    if (!dev.isEmpty()) engine.addImportPath(dev);

    const QString qml = resolve_qml_path("Notifications.qml", argv[0]);
    engine.load(QUrl::fromLocalFile(qml));
    if (engine.rootObjects().isEmpty()) return 1;

    return app.exec();
}
