import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        Text { text: "CUDA"; color: Theme.textPrimary; font.bold: true; font.pixelSize: 20 }
        Text {
            text: "Driver: " + (cudaManager.driverVersion || "unknown") +
                  "    Active (system): " + (cudaManager.systemActive || "—") +
                  "    Active (user): " + (cudaManager.userActive || "—")
            color: Theme.textSecondary
            font.pixelSize: 12
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        Repeater {
            model: cudaManager.toolkits
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                radius: Theme.cornerRadius
                color: Theme.surface
                border.color: Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 16

                    ColumnLayout {
                        Layout.fillWidth: true
                        Text { text: "CUDA " + modelData.version
                               color: Theme.textPrimary; font.bold: true; font.pixelSize: 14 }
                        Text { text: modelData.path
                               color: Theme.textSecondary; font.pixelSize: 11 }
                    }

                    Text {
                        text: (modelData.isSystemActive ? " system  " : "") +
                              (modelData.isUserActive   ? " user "   : "")
                        color: Theme.accent
                        font.pixelSize: 10
                        font.bold: true
                    }

                    Button {
                        text: "Use for me"
                        enabled: !modelData.isUserActive
                        onClicked: cudaManager.setUserActive(modelData.version)
                    }
                    Button {
                        text: "Set system default"
                        enabled: !modelData.isSystemActive
                        onClicked: cudaManager.setSystemActive(modelData.version)
                    }
                }
            }
        }

        Text {
            visible: cudaManager.toolkits.length === 0
            text: "No /usr/local/cuda-* toolkits found. Install one via apt:\n" +
                  "    sudo apt install cuda-toolkit-12-6"
            color: Theme.warning
            font.pixelSize: 12
        }

        Item { Layout.fillHeight: true }
    }
}
