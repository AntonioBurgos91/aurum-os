// aurum-finder entry point.
//
// Three QML-visible objects:
//   - finderModel   (file browse model for the current directory)
//   - sidebarModel  (Favorites + ML pinned locations)
//   - bridge        (small singleton-ish helper for QML→C++ utilities)

#include <QApplication>
#include <QObject>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QString>
#include <QUrl>

#include "core_services.h"
#include "finder_model.h"
#include "ml_integrations.h"
#include "sidebar_model.h"
#include "style_engine.h"

int main(int argc, char* argv[]) {
    init_core_services();
    init_ml_integrations();

    QApplication app(argc, argv);
    app.setApplicationName("aurum-finder");
    app.setDesktopFileName("aurum-finder");
    init_aqua_style();

    aurum::finder::FinderModel  finderModel;
    aurum::finder::SidebarModel sidebarModel;

    QQmlApplicationEngine engine;
    engine.addImportPath("/usr/lib/qt6/qml");
    engine.addImportPath("/usr/local/lib/qt6/qml");
    const auto dev = qEnvironmentVariable("AURUM_QML_IMPORT_PATH");
    if (!dev.isEmpty()) engine.addImportPath(dev);

    engine.rootContext()->setContextProperty("finderModel",  &finderModel);
    engine.rootContext()->setContextProperty("sidebarModel", &sidebarModel);

    const QString qml = resolve_qml_path("Finder.qml", argv[0]);
    engine.load(QUrl::fromLocalFile(qml));
    if (engine.rootObjects().isEmpty()) return 1;

    return app.exec();
}
