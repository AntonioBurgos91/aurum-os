import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    property bool valid: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 48
        spacing: 18

        Text { text: "AurumOS is installed"; color: Theme.textPrimary
               font.bold: true; font.pixelSize: 28 }
        Text {
            text: "Remove the install medium and reboot. Your DL stack is\n" +
                  "already at /opt/aurum-dl-venv — `aurum-dl-verify` confirms\n" +
                  "GPU + framework health from the menu or a terminal."
            color: Theme.textSecondary
            font.pixelSize: 14
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        ColumnLayout {
            spacing: 6
            Text { text: "First steps after reboot:"; color: Theme.textPrimary
                   font.bold: true; font.pixelSize: 14 }
            Text { text: "•  Cmd+Space  →  Spotlight (try: hf llama, arxiv attention)"
                   color: Theme.textSecondary; font.pixelSize: 12 }
            Text { text: "•  Cmd+,      →  Settings (CUDA, Python venvs, MLOps)"
                   color: Theme.textSecondary; font.pixelSize: 12 }
            Text { text: "•  Cmd+E      →  Finder with Quick Look for .ipynb / .safetensors / .parquet"
                   color: Theme.textSecondary; font.pixelSize: 12 }
            Text { text: "•  aurum-dl-verify   →  Smoke + benchmark report"
                   color: Theme.textSecondary; font.pixelSize: 12 }
        }

        Item { Layout.fillHeight: true }
    }
}
