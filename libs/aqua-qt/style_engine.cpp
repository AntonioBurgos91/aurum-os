#include "style_engine.h"

#include <QApplication>
#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QIcon>
#include <QPalette>
#include <QStringList>
#include <QStyleFactory>

#include <mutex>

namespace aurum::aqua {

const Tokens& tokens() {
    static const Tokens t{};
    return t;
}

QPalette aqua_dark_palette() {
    const auto& t = tokens();
    QPalette p;

    p.setColor(QPalette::Window,          t.windowBg);
    p.setColor(QPalette::WindowText,      t.textPrimary);
    p.setColor(QPalette::Base,            t.windowBg);
    p.setColor(QPalette::AlternateBase,   t.surface);
    p.setColor(QPalette::ToolTipBase,     t.surfaceRaised);
    p.setColor(QPalette::ToolTipText,     t.textPrimary);
    p.setColor(QPalette::Text,            t.textPrimary);
    p.setColor(QPalette::Button,          t.surface);
    p.setColor(QPalette::ButtonText,      t.textPrimary);
    p.setColor(QPalette::BrightText,      t.danger);
    p.setColor(QPalette::Link,            t.accent);
    p.setColor(QPalette::LinkVisited,     t.accent.darker(120));
    p.setColor(QPalette::Highlight,       t.accent);
    p.setColor(QPalette::HighlightedText, t.accentText);
    p.setColor(QPalette::PlaceholderText, t.textSecondary);

    // Disabled-state colors. Without these, Fusion paints disabled text in
    // black on dark surfaces.
    p.setColor(QPalette::Disabled, QPalette::WindowText,      t.textSecondary);
    p.setColor(QPalette::Disabled, QPalette::ButtonText,      t.textSecondary);
    p.setColor(QPalette::Disabled, QPalette::Text,            t.textSecondary);
    p.setColor(QPalette::Disabled, QPalette::HighlightedText, t.textSecondary);

    return p;
}

QFont aqua_default_font() {
    // Try in order: Inter (shipped by themes/install_themes.sh), then the
    // SF-family fallbacks. Letting QFont's substitution chain do the work
    // means we don't have to pre-check QFontDatabase.
    QFont f("Inter");
    f.setStyleHint(QFont::SansSerif, QFont::PreferAntialias);
    f.setPixelSize(13);
    f.setWeight(QFont::Normal);
    QFont::insertSubstitutions("Inter", {"Inter Display", "SF Pro Text",
                                         "Helvetica Neue", "Sans Serif"});
    return f;
}

QFont aqua_mono_font() {
    QFont f("FiraCode");
    f.setStyleHint(QFont::Monospace);
    f.setPixelSize(12);
    QFont::insertSubstitutions("FiraCode", {"Fira Code", "SF Mono",
                                            "JetBrains Mono", "Monospace"});
    return f;
}

} // namespace aurum::aqua

extern "C" void init_aqua_style() {
    static std::once_flag init_flag;
    std::call_once(init_flag, [](){
        if (!QCoreApplication::instance()) {
            qWarning() << "[aqua-qt] init_aqua_style called before QApplication;"
                          " palette will not stick.";
            return;
        }

        // Force Fusion: the per-platform default style (e.g. Adwaita, Breeze)
        // tends to ignore palette overrides on some distros.
        if (auto* fusion = QStyleFactory::create("Fusion"))
            QApplication::setStyle(fusion);

        QGuiApplication::setFont(aurum::aqua::aqua_default_font());
        QGuiApplication::setPalette(aurum::aqua::aqua_dark_palette());

        // Icon theme setup — Qt6 ships QIcon::themeName()=="" on minimal headless
        // installs (no GTK settings, no $XDG_CURRENT_DESKTOP). That makes
        // QIcon::fromTheme(name) return null even when our PNGs are perfectly
        // present under /usr/local/share/icons/hicolor/256x256/apps/. Forcing the
        // canonical "hicolor" theme + adding the standard XDG search paths fixes
        // the dock-icon lookup without per-app code, and lets users drop their
        // own theme in by overriding QT_ICON_THEME later.
        QStringList themePaths = QIcon::themeSearchPaths();
        for (const auto& p : {QStringLiteral("/usr/local/share/icons"),
                              QStringLiteral("/usr/share/icons"),
                              QStringLiteral("/var/lib/flatpak/exports/share/icons"),
                              QDir::homePath() + QStringLiteral("/.local/share/icons")}) {
            if (!themePaths.contains(p) && QFileInfo::exists(p))
                themePaths << p;
        }
        QIcon::setThemeSearchPaths(themePaths);
        if (QIcon::themeName().isEmpty()) {
            QIcon::setThemeName(qEnvironmentVariable("QT_ICON_THEME", "hicolor"));
        }

        qInfo().noquote() << "[aqua-qt] Fusion + Sequoia Dark palette applied. "
                             "Icon theme:" << QIcon::themeName()
                          << "(search paths:" << QIcon::themeSearchPaths().size() << ")";
    });
}

// Legacy shims.
QPalette get_aqua_dark_palette() { return aurum::aqua::aqua_dark_palette(); }
QFont    get_aqua_default_font() { return aurum::aqua::aqua_default_font(); }
