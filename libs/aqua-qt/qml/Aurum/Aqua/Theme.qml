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

    // ─── Typography (Wave 10 Agent C) ────────────────────────────────────
    // Apple uses SF Pro Display (headlines) + SF Pro Text (body) + SF Mono.
    // We ship Inter / Inter Display / JetBrains Mono as the libre equivalents.
    // `fontFamily` resolves at runtime via fontconfig substitution if Inter is
    // missing — fonts-inter is apt-installable, see themes/install-fonts.sh.
    readonly property string fontFamily:         "Inter"
    readonly property string fontFamilyDisplay:  "Inter Display"   // 17px+ headlines
    readonly property string fontFamilyMono:     "JetBrains Mono"
    readonly property string fontFamilyFallback: "Sans Serif"      // qt fallback

    // Sizes (matches macOS Sequoia at 1× density)
    readonly property int    fontSizeTiny:    10   // hairline labels (menubar applet badges)
    readonly property int    fontSizeSmall:   11   // secondary text (dock tooltips, captions)
    readonly property int    fontSizeBody:    13   // default body
    readonly property int    fontSizeMedium:  15   // emphasized body / sidebar items
    readonly property int    fontSizeLarge:   17   // sub-headings
    readonly property int    fontSizeTitle:   22   // window titles in Settings/Finder big-mode
    readonly property int    fontSizeHero:    34   // splash / installer welcome

    // Weights (matches Apple's named weights)
    readonly property int    fontWeightRegular:  Font.Normal       // 400
    readonly property int    fontWeightMedium:   Font.Medium       // 500
    readonly property int    fontWeightSemibold: Font.DemiBold     // 600
    readonly property int    fontWeightBold:     Font.Bold         // 700

    // Line heights (Qt expects lineHeightMode: Text.FixedHeight + lineHeight: N)
    readonly property real   lineHeightBody:    1.32
    readonly property real   lineHeightDisplay: 1.18
    readonly property real   lineHeightMono:    1.45

    // Letter-spacing (Qt: font.letterSpacing in px, NOT em)
    readonly property real   letterSpacingTight:  -0.2
    readonly property real   letterSpacingNormal:  0.0
    readonly property real   letterSpacingCaps:    0.5     // for ALL-CAPS labels (menubar applet "GPU", "VRAM" etc.)

    // --- Window chrome (Wave 10A) ---
    // Tokens consumed by WindowChrome.qml + TrafficLight.qml so the title bar
    // matches macOS Sequoia exactly across every AurumOS app.
    readonly property int   windowChromeHeight: 28
    readonly property color windowChromeBg:     "#FF1c1c1e"  // matches macOS sequoia dark bar
    readonly property color trafficClose:       "#FF5F57"
    readonly property color trafficMin:         "#FEBC2E"
    readonly property color trafficMax:         "#28C840"
    readonly property color trafficDisabled:    "#555555"

    // --- Typography (Wave 10C, HIG-aligned superset) ----------------------
    // Extends the typography block above with macOS Sequoia HIG semantic
    // names so call-sites can read like the Apple docs (Title1, Headline,
    // Callout, Caption1…).  The shorter `fontSize{Tiny,Small,Body,…}` set
    // above is kept for backwards compatibility — the values are aligned so
    // either family resolves to the same px.  Inter is the OFL-licensed
    // stand-in for SF Pro (Apple's SF Pro is non-redistributable); Inter is
    // what GitHub, Figma and Linear ship for the same reason.
    //
    // Multi-family fallback strings let fontconfig pick the best match per
    // host: on AurumOS Inter resolves natively; on a fresh install before
    // `themes/install_fonts.sh` runs, system-ui → DejaVu Sans is acceptable.
    readonly property string fontFamilyText:      "Inter, SF Pro Text, system-ui, sans-serif"
    readonly property string fontFamilyDisplayCSS:"Inter Display, Inter, SF Pro Display, system-ui, sans-serif"
    readonly property string fontFamilyMonoCSS:   "JetBrains Mono, Menlo, Monaco, monospace"

    // HIG semantic sizes — pixel-perfect mapping to macOS Sequoia @1x.
    readonly property int  fontSizeLargeTitle:    34
    readonly property int  fontSizeTitle1:        28
    readonly property int  fontSizeTitle2:        22
    readonly property int  fontSizeTitle3:        20
    readonly property int  fontSizeHeadline:      17   // body bold
    // fontSizeBody (13) already defined above — HIG body == our body.
    readonly property int  fontSizeCallout:       12
    readonly property int  fontSizeSubheadline:   11
    readonly property int  fontSizeFootnote:      10
    readonly property int  fontSizeCaption1:       9
    readonly property int  fontSizeCaption2:       8

    // Extra letter-spacing token — `Wide` complements the Tight/Normal/Caps
    // trio above for the occasional spaced-out label (e.g. Quick Look chips).
    readonly property real letterSpacingWide:      0.2

    // --- Settings cards (Wave 10E) ---
    // Tokens consumed by SectionCard.qml + every desktop/settings panel so the
    // seven Settings pages share one coherent macOS-Sequoia card rhythm. Keep
    // these aligned with docs/guides/settings-style.md when tweaking.
    readonly property color cardBg:       "#FF2c2c2e"   // settings card surface (slightly lighter than window bg)
    readonly property color cardBorder:   "#33FFFFFF"   // 20% white over dark = subtle 1px line
    readonly property int   cardRadius:   12
    readonly property int   cardPadding:  16
    readonly property int   cardSpacing:  16            // between sibling cards in a scroll list

    // Hover background used by SettingsRow (10% white tint, premultiplied).
    readonly property color hoverBg:      "#1affffff"
}
