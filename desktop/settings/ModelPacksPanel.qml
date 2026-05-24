// ModelPacksPanel — Steam-Workshop-style downloader for ML model bundles
// tuned to the user's detected hardware profile.
//
// Backend: `modelPacksModel` (a ModelPacksModel C++ object, wired in main.cpp).
// It scans /etc/aurum/model-packs/*.yaml (manifests written by Agent I's
// `aurum-model-pack` CLI) and shells out to that same CLI for install/remove.
//
// Layout, top to bottom:
//   1. Header: title + "current profile: <tier>" subtitle
//   2. ListView of pack rows (icon, title/desc, size, profile badge, action)
//   3. Footer: cache path + total size + Clear cache button
//
// Empty-state message kicks in when the manifests directory doesn't exist yet
// (Agent I hasn't run) so the panel never shows as broken in that window.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Aurum.Aqua 1.0

Item {
    id: panel

    // --- Helpers ------------------------------------------------------------

    // Title-case the profile string for display ("pro" -> "Pro").
    function profileLabel(p) {
        if (!p) return "—"
        return p.charAt(0).toUpperCase() + p.slice(1)
    }

    // Suffix the min-profile badge with "+" so a "standard" pack reads
    // "Standard+" (i.e. "standard or better"), matching how the spec talks
    // about it.
    function minProfileBadge(p) {
        return profileLabel(p) + "+"
    }

    function badgeColor(tier) {
        switch (tier) {
            case "workstation": return Theme.accent
            case "pro":         return "#4a9eff"
            case "standard":    return Theme.success
            case "lite":        return Theme.warning
            default:            return Theme.surfaceRaised
        }
    }

    // Cached cache size: we re-query on demand because directory walks can
    // be slow on first install. The footer triggers a refresh when the
    // model emits installFinished.
    property string cacheSizeHuman: modelPacksModel.humanSize(modelPacksModel.cacheSize())
    function refreshCacheSize() {
        cacheSizeHuman = modelPacksModel.humanSize(modelPacksModel.cacheSize())
    }

    Connections {
        target: modelPacksModel
        function onInstallFinished(id, ok, message) { panel.refreshCacheSize() }
    }

    // --- Layout -------------------------------------------------------------

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        // ---- Header --------------------------------------------------------
        Text {
            text: "Model Packs"
            color: Theme.textPrimary
            font.bold: true
            font.pixelSize: 20
        }
        Text {
            text: "Download AI models tuned for your hardware (current profile: "
                  + panel.profileLabel(modelPacksModel.currentProfile) + ")"
            color: Theme.textSecondary
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // ---- Pack list (wrapped in an Item so the empty-state placeholder
        //      can be a sibling overlay, not a contentItem child of ListView).
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

        ListView {
            id: packList
            anchors.fill: parent
            model: modelPacksModel
            spacing: 8
            clip: true

            delegate: Rectangle {
                id: row
                // The QAbstractListModel role names land as context properties.
                // We mostly use them by name (packId, title, ...) but pull a
                // couple onto explicit locals for the action-button bindings
                // so each row's button reflects ITS state, not the last row's.
                required property string packId
                required property string title
                required property string description
                required property string sizeHuman
                required property string minProfile
                required property string state
                required property int    progress
                required property string lastError
                required property string docsUrl
                required property bool   meetsProfile

                width: ListView.view.width
                height: 88
                radius: Theme.cornerRadiusSm
                color: hoverArea.containsMouse ? Theme.surfaceRaised : Theme.surface
                border.color: Theme.border
                border.width: Theme.strokeWidth

                MouseArea {
                    id: hoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    // Don't intercept clicks — the action button owns those.
                    acceptedButtons: Qt.NoButton
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    spacing: 14

                    // --- Squircle icon (generic placeholder) ---------------
                    Rectangle {
                        Layout.preferredWidth: 56
                        Layout.preferredHeight: 56
                        radius: 14
                        color: row.meetsProfile ? Theme.accent : Theme.surfaceRaised
                        border.color: Theme.border
                        Text {
                            anchors.centerIn: parent
                            // First letter of the title as a stand-in glyph.
                            text: row.title.length > 0
                                  ? row.title.charAt(0).toUpperCase()
                                  : "?"
                            color: row.meetsProfile
                                   ? Theme.accentText : Theme.textSecondary
                            font.pixelSize: 24
                            font.bold: true
                        }
                    }

                    // --- Title + description + size ------------------------
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            spacing: 8
                            Layout.fillWidth: true
                            Text {
                                text: row.title
                                color: Theme.textPrimary
                                font.bold: true
                                font.pixelSize: 14
                            }
                            // Min-profile badge
                            Rectangle {
                                Layout.preferredHeight: 18
                                Layout.preferredWidth: badgeText.implicitWidth + 12
                                radius: 9
                                color: row.meetsProfile
                                       ? Qt.darker(panel.badgeColor(row.minProfile), 1.3)
                                       : Theme.surfaceRaised
                                border.color: row.meetsProfile
                                              ? panel.badgeColor(row.minProfile)
                                              : Theme.border
                                Text {
                                    id: badgeText
                                    anchors.centerIn: parent
                                    text: panel.minProfileBadge(row.minProfile)
                                    color: row.meetsProfile
                                           ? Theme.textPrimary : Theme.textSecondary
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }
                            Item { Layout.fillWidth: true }
                            // Size estimate, right-aligned.
                            Text {
                                text: row.sizeHuman
                                color: Theme.textSecondary
                                font.pixelSize: 11
                            }
                        }
                        Text {
                            text: row.description
                            color: Theme.textSecondary
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            Layout.fillWidth: true
                        }

                        // State / progress line.
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: row.state === "installing" ? 8 : 14
                            sourceComponent: row.state === "installing"
                                             ? progressInline
                                             : stateInline
                        }
                        // Inline "Installed" / "Not installed" / "Error: ..."
                        Component {
                            id: stateInline
                            Text {
                                text: {
                                    if (row.state === "installed")     return "Installed"
                                    if (row.state === "error")         return "Error: " + row.lastError
                                    return "Not installed"
                                }
                                color: row.state === "installed" ? Theme.success
                                     : row.state === "error"     ? Theme.danger
                                                                  : Theme.textSecondary
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                        Component {
                            id: progressInline
                            // Thin 4px accent-coloured progress bar.
                            Rectangle {
                                radius: 2
                                color: Theme.surfaceRaised
                                Rectangle {
                                    width: parent.width * (row.progress / 100.0)
                                    height: parent.height
                                    radius: parent.radius
                                    color: Theme.accent
                                    Behavior on width { NumberAnimation { duration: 120 } }
                                }
                            }
                        }
                    }

                    // --- Action button ------------------------------------
                    ColumnLayout {
                        Layout.preferredWidth: 110
                        spacing: 4
                        Button {
                            Layout.fillWidth: true
                            text: {
                                if (row.state === "installing") return "Installing..."
                                if (row.state === "installed")  return "Remove"
                                if (row.state === "error")      return "Retry"
                                if (!row.meetsProfile)          return "Open Docs"
                                return "Install"
                            }
                            enabled: row.state !== "installing"
                            highlighted: row.state !== "installed" && row.meetsProfile
                            onClicked: {
                                if (row.state === "installed") {
                                    modelPacksModel.remove(row.packId)
                                } else if (!row.meetsProfile && row.state !== "error") {
                                    // Profile too low: link out to docs rather
                                    // than letting the install fail server-side.
                                    if (row.docsUrl.length > 0)
                                        Qt.openUrlExternally(row.docsUrl)
                                } else {
                                    modelPacksModel.install(row.packId)
                                }
                            }
                        }
                        Text {
                            visible: row.state === "installing"
                            text: row.progress + "%"
                            color: Theme.textSecondary
                            font.pixelSize: 10
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }

        }

        // ---- Empty state (sibling of the ListView, not a child) -----------
        Rectangle {
            anchors.centerIn: parent
            visible: packList.count === 0
            width: Math.min(parent.width - 40, 420)
            height: 130
            radius: Theme.cornerRadius
            color: Theme.surface
            border.color: Theme.border
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 6
                Text {
                    text: "No model packs found"
                    color: Theme.textPrimary
                    font.bold: true
                    font.pixelSize: 14
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "Pack manifests live in /etc/aurum/model-packs. "
                          + "Install the `aurum-model-pack` CLI to populate this list."
                    color: Theme.textSecondary
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }
                Button {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Open docs"
                    onClicked: Qt.openUrlExternally("https://docs.aurumos.dev/model-packs")
                }
            }
        }
        } // outer Item wrapping ListView + empty state

        // ---- Footer (cache controls) --------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: Theme.cornerRadiusSm
            color: Theme.surface
            border.color: Theme.border
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 12
                Text {
                    text: "Cache: " + modelPacksModel.cachePath()
                    color: Theme.textSecondary
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
                Text {
                    text: panel.cacheSizeHuman + " used"
                    color: Theme.textPrimary
                    font.pixelSize: 11
                    font.bold: true
                }
                Button {
                    text: "Clear cache"
                    onClicked: clearCacheDialog.open()
                }
                Button {
                    text: "Refresh"
                    onClicked: { modelPacksModel.refresh(); panel.refreshCacheSize() }
                }
            }
        }
    }

    // --- Dialogs ------------------------------------------------------------
    MessageDialog {
        id: clearCacheDialog
        text: "Clear model cache?"
        informativeText: "This deletes every downloaded model from "
                        + modelPacksModel.cachePath()
                        + ". Installed packs will need to be re-downloaded."
        buttons: MessageDialog.Yes | MessageDialog.No
        onAccepted: { modelPacksModel.clearCache(); panel.refreshCacheSize() }
    }
}
