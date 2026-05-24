// aurum-spotlight entry point.
//
// Builds the in-process plugin set and bridges them into QML through a single
// SearchAggregator instance. The QML side renders a center-of-screen overlay,
// debounces typing into setQuery(), and calls activate() on Enter.

#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QString>
#include <QUrl>

#include "core_services.h"
#include "ml_integrations.h"
#include "search_aggregator.h"
#include "style_engine.h"

#include "plugins/apps_plugin.h"
#include "plugins/arxiv_plugin.h"
#include "plugins/calculator_plugin.h"
#include "plugins/files_plugin.h"
#include "plugins/huggingface_plugin.h"

int main(int argc, char* argv[]) {
    init_core_services();
    init_ml_integrations();

    QApplication app(argc, argv);
    app.setApplicationName("aurum-spotlight");
    app.setDesktopFileName("aurum-spotlight");
    init_aqua_style();

    aurum::spotlight::SearchAggregator aggregator;
    // Order added does not affect display order — plugin priority() does.
    aggregator.addPlugin(new aurum::spotlight::AppsPlugin);
    aggregator.addPlugin(new aurum::spotlight::FilesPlugin);
    aggregator.addPlugin(new aurum::spotlight::CalculatorPlugin);
    aggregator.addPlugin(new aurum::spotlight::HuggingFacePlugin);
    aggregator.addPlugin(new aurum::spotlight::ArxivPlugin);

    QQmlApplicationEngine engine;
    engine.addImportPath("/usr/lib/qt6/qml");
    engine.addImportPath("/usr/local/lib/qt6/qml");
    const auto dev = qEnvironmentVariable("AURUM_QML_IMPORT_PATH");
    if (!dev.isEmpty()) engine.addImportPath(dev);

    engine.rootContext()->setContextProperty("aggregator", &aggregator);

    const QString qml = resolve_qml_path("Spotlight.qml", argv[0]);
    engine.load(QUrl::fromLocalFile(qml));
    if (engine.rootObjects().isEmpty()) return 1;

    return app.exec();
}
