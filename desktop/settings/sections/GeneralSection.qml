import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        Text { text: "General"; color: Theme.textPrimary; font.bold: true; font.pixelSize: 20 }
        Text {
            text: "AurumOS keeps the appearance and behavior tokens centralized\n" +
                  "in /etc/aurum/hypr/aurum.conf and the Aurum.Aqua QML module.\n" +
                  "Phase 5 ships a read-only summary here; live tweaks land in a later phase."
            color: Theme.textSecondary
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        GridLayout {
            columns: 2
            columnSpacing: 24
            rowSpacing: 8
            Text { text: "Theme:";   color: Theme.textSecondary; font.pixelSize: 12 }
            Text { text: "Sequoia Dark (Fusion)"; color: Theme.textPrimary; font.pixelSize: 12 }
            Text { text: "Font:";    color: Theme.textSecondary; font.pixelSize: 12 }
            Text { text: "Inter — 13 px"; color: Theme.textPrimary; font.pixelSize: 12 }
            Text { text: "Compositor:"; color: Theme.textSecondary; font.pixelSize: 12 }
            Text { text: "Hyprland (AurumOS fork)"; color: Theme.textPrimary; font.pixelSize: 12 }
        }
        Item { Layout.fillHeight: true }
    }
}
