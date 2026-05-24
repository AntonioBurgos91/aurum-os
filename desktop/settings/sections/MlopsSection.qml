// MlopsSection — MLflow + Weights & Biases credentials in Settings.
//
// Wave 10E styling refactor: the two custom "Rectangle with Grid inside"
// blocks for MLflow and W&B used to define their own surface/border/padding
// inline; they're now SectionCards with SettingsRows. Functionally identical:
// every TextField still two-way-binds to the same `mlopsConfig` property
// (which writes ~/.config/aurum/mlops.toml on save()), and the Save / Reload
// buttons retain their highlights and click handlers.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 12

        // ---- MLflow card --------------------------------------------------
        SectionCard {
            Layout.fillWidth: true
            title:    "MLflow"
            subtitle: "Saved to ~/.config/aurum/mlops.toml — the aurum-ml-jobs-tracker "
                    + "daemon picks the values up at next start (systemctl --user reload)."

            SettingsRow {
                label: "Tracking URI"
                control: TextField {
                    text: mlopsConfig.mlflowTrackingUri
                    onTextChanged: mlopsConfig.mlflowTrackingUri = text
                }
            }
            SettingsRow {
                label: "Experiment"
                control: TextField {
                    text: mlopsConfig.mlflowExperiment
                    onTextChanged: mlopsConfig.mlflowExperiment = text
                }
                isLast: true
            }
        }

        // ---- Weights & Biases card ---------------------------------------
        SectionCard {
            Layout.fillWidth: true
            title: "Weights & Biases"

            SettingsRow {
                label: "API key"
                control: TextField {
                    text: mlopsConfig.wandbApiKey
                    echoMode: TextInput.Password
                    onTextChanged: mlopsConfig.wandbApiKey = text
                }
            }
            SettingsRow {
                label: "Entity"
                control: TextField {
                    text: mlopsConfig.wandbEntity
                    onTextChanged: mlopsConfig.wandbEntity = text
                }
                isLast: true
            }
        }

        // ---- Save / Reload action row (outside the cards, like macOS
        //      footer buttons in System Settings detail panes).
        RowLayout {
            Layout.fillWidth: true
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
