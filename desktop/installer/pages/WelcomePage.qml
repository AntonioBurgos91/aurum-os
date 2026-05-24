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

        Text { text: "Welcome to AurumOS"; color: Theme.textPrimary
               font.bold: true; font.pixelSize: 28 }
        Text {
            text: "A Linux distribution built for deep-learning workstations.\n" +
                  "Bring your own model; the OS gets out of your way."
            color: Theme.textSecondary
            font.pixelSize: 14
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        ColumnLayout {
            spacing: 6
            Text { text: "What you'll get:"; color: Theme.textPrimary
                   font.bold: true; font.pixelSize: 14 }
            Text { text: "• Hyprland-based macOS-like desktop"
                   color: Theme.textSecondary; font.pixelSize: 12 }
            Text { text: "• PyTorch + JAX + TensorFlow + vLLM, pre-installed and verified"
                   color: Theme.textSecondary; font.pixelSize: 12 }
            Text { text: "• Spotlight search across files, Hugging Face models, arXiv papers"
                   color: Theme.textSecondary; font.pixelSize: 12 }
            Text { text: "• bcachefs root with snapshot support for dataset versioning"
                   color: Theme.textSecondary; font.pixelSize: 12 }
        }

        Item { Layout.fillHeight: true }
    }
}
