// CudaSection — list & switch between installed CUDA toolkits.
//
// Wave 10E styling refactor: the previous free-floating title + repeater is
// now wrapped in two shared SectionCards so the page rhythm matches the rest
// of Settings. Bindings on `cudaManager.*` are preserved verbatim; only the
// outer structure changed.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    ScrollView {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: parent.parent.width - 40
            x: 20
            y: 20
            spacing: Theme.cardSpacing

            // ---- Overview ------------------------------------------------------
            SectionCard {
                Layout.fillWidth: true
                title:    "CUDA"
                subtitle: "Driver: " + (cudaManager.driverVersion || "unknown")
                        + "    Active (system): " + (cudaManager.systemActive || "—")
                        + "    Active (user): "   + (cudaManager.userActive   || "—")
            }

            // ---- Installed toolkits -------------------------------------------
            SectionCard {
                Layout.fillWidth: true
                title:    "Installed toolkits"
                subtitle: "Detected under /usr/local/cuda-*. Use one for your shell "
                        + "or set the system-wide default."

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
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
