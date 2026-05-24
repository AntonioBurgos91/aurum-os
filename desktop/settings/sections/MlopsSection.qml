import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        Text { text: "MLOps"; color: Theme.textPrimary; font.bold: true; font.pixelSize: 20 }
        Text {
            text: "Saved to ~/.config/aurum/mlops.toml. The aurum-ml-jobs-tracker\n" +
                  "daemon picks the values up at next start (or systemctl --user reload)."
            color: Theme.textSecondary
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Rectangle {
            Layout.fillWidth: true
            radius: Theme.cornerRadius
            color: Theme.surface
            border.color: Theme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                Text { text: "MLflow"; color: Theme.textPrimary; font.bold: true; font.pixelSize: 14 }

                GridLayout {
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 6
                    Layout.fillWidth: true

                    Text { text: "Tracking URI"; color: Theme.textSecondary; font.pixelSize: 12 }
                    TextField {
                        text: mlopsConfig.mlflowTrackingUri
                        Layout.fillWidth: true
                        onTextChanged: mlopsConfig.mlflowTrackingUri = text
                    }
                    Text { text: "Experiment"; color: Theme.textSecondary; font.pixelSize: 12 }
                    TextField {
                        text: mlopsConfig.mlflowExperiment
                        Layout.fillWidth: true
                        onTextChanged: mlopsConfig.mlflowExperiment = text
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            radius: Theme.cornerRadius
            color: Theme.surface
            border.color: Theme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                Text { text: "Weights & Biases"; color: Theme.textPrimary; font.bold: true; font.pixelSize: 14 }

                GridLayout {
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 6
                    Layout.fillWidth: true

                    Text { text: "API key"; color: Theme.textSecondary; font.pixelSize: 12 }
                    TextField {
                        text: mlopsConfig.wandbApiKey
                        Layout.fillWidth: true
                        echoMode: TextInput.Password
                        onTextChanged: mlopsConfig.wandbApiKey = text
                    }
                    Text { text: "Entity"; color: Theme.textSecondary; font.pixelSize: 12 }
                    TextField {
                        text: mlopsConfig.wandbEntity
                        Layout.fillWidth: true
                        onTextChanged: mlopsConfig.wandbEntity = text
                    }
                }
            }
        }

        RowLayout {
            Item { Layout.fillWidth: true }
            Button {
                text: "Reload"
                onClicked: mlopsConfig.reload()
            }
            Button {
                text: "Save"
                highlighted: true
                onClicked: mlopsConfig.save()
            }
        }

        Item { Layout.fillHeight: true }
    }
}
