// Single source of truth for the Sequoia-dark color tokens used by every
// AurumOS QML component. Mirrors libs/aqua-qt/style_engine.cpp::Tokens.
pragma Singleton
import QtQuick

QtObject {
    readonly property color windowBg      : "#1c1c1e"
    readonly property color surface       : "#262628"
    readonly property color surfaceRaised : "#323236"
    readonly property color textPrimary   : "#ffffff"
    readonly property color textSecondary : "#8e8e93"
    readonly property color border        : "#3c3c40"
    readonly property color accent        : "#0a84ff"
    readonly property color accentText    : "#ffffff"   // text rendered on accent backgrounds
    readonly property color success       : "#30d158"
    readonly property color warning       : "#ff9f0a"
    readonly property color danger        : "#ff453a"

    readonly property int   cornerRadius   : 12
    readonly property int   cornerRadiusSm : 8
    readonly property int   strokeWidth    : 1

    // Strip / shelf geometry constants shared by dock + menubar.
    readonly property int   menubarHeight  : 28
    readonly property int   dockHeight     : 80
    readonly property int   dockIconSize   : 48
}
