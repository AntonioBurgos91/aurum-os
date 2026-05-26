// aurum-coming-soon — visual feedback for dock icons whose real app isn't
// installed yet.
//
// We use this instead of `notify-send` because:
//   * the demo container has no notification daemon (mako/dunst) so notify
//     events go to /dev/null,
//   * the user reasonably expects a click on a dock icon to produce a
//     visible UI response.
//
// Single-window Qt6 app, ~250 lines. Reads two arguments:
//   $1  app id          (used to set wmclass — so each placeholder is its
//                        own window from Hyprland's point of view, which
//                        lets the dock dedup focus the SAME placeholder
//                        instead of spawning a new one each click)
//   $2  display name    (heading text in the window)
//   $3  install hint    (optional — second paragraph, e.g. "pip install foo")
//
// Spawned from the .desktop file as e.g.:
//   Exec=aurum-coming-soon aurum-browser "Browser" "Install firefox or chromium"

#include <QApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <iostream>

#include "core_services.h"
#include "style_engine.h"

extern "C" void init_aqua_style();

int main(int argc, char* argv[]) {
    QApplication app(argc, argv);

    // CRITICAL: set the wmclass before any window is shown. This is what
    // Hyprland matches against `class:` in windowrules and what our dock's
    // dedup logic queries via `hyprctl clients`. Without this each placeholder
    // would inherit "aurum-coming-soon" → clicking ANY placeholder would focus
    // the FIRST one open, regardless of which app the user wanted. Setting it
    // per-invocation gives each placeholder its own identity.
    const QString app_id = argc > 1 ? QString::fromUtf8(argv[1]) : "aurum-placeholder";
    const QString display = argc > 2 ? QString::fromUtf8(argv[2]) : app_id;
    const QString install_to = argc > 3 ? QString::fromUtf8(argv[3]) : QString();

    QGuiApplication::setApplicationName(app_id);
    QGuiApplication::setDesktopFileName(app_id);

    init_aqua_style();

    QQmlApplicationEngine engine;
    engine.addImportPath("/usr/lib/qt6/qml");
    engine.addImportPath("/usr/local/lib/qt6/qml");
    const auto dev = qEnvironmentVariable("AURUM_QML_IMPORT_PATH");
    if (!dev.isEmpty()) engine.addImportPath(dev);

    // Expose the three strings to QML as context properties — cheap and
    // avoids registering a typed model for three immutable values.
    engine.rootContext()->setContextProperty("appId", app_id);
    engine.rootContext()->setContextProperty("displayName", display);
    engine.rootContext()->setContextProperty("installHint", install_to);

    const QString qml = resolve_qml_path("ComingSoon.qml", argv[0]);
    if (qml.isEmpty()) return 2;
    engine.load(QUrl::fromLocalFile(qml));
    if (engine.rootObjects().isEmpty()) return 1;

    std::cerr << "[coming-soon] " << app_id.toStdString() << " — \"" << display.toStdString()
              << "\"\n";
    return app.exec();
}
