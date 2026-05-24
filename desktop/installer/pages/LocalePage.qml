import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    property bool valid: localeCombo.currentText.length > 0
                      && keyboardCombo.currentText.length > 0
                      && tzCombo.currentText.length > 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 48
        spacing: 16

        Text { text: "Language & region"; color: Theme.textPrimary
               font.bold: true; font.pixelSize: 22 }

        GridLayout {
            columns: 2
            columnSpacing: 16
            rowSpacing: 8
            Layout.fillWidth: true

            Text { text: "System language"; color: Theme.textSecondary; font.pixelSize: 12 }
            ComboBox {
                id: localeCombo
                Layout.fillWidth: true
                model: ["en_US.UTF-8", "es_ES.UTF-8", "es_AR.UTF-8", "fr_FR.UTF-8",
                        "de_DE.UTF-8", "ja_JP.UTF-8", "zh_CN.UTF-8"]
                currentIndex: 0
                onCurrentTextChanged: backend.locale = currentText
                Component.onCompleted: backend.locale = currentText
            }

            Text { text: "Keyboard layout"; color: Theme.textSecondary; font.pixelSize: 12 }
            ComboBox {
                id: keyboardCombo
                Layout.fillWidth: true
                model: ["us", "us-intl", "es", "latam", "fr", "de", "jp"]
                currentIndex: 0
                onCurrentTextChanged: backend.keyboard = currentText
                Component.onCompleted: backend.keyboard = currentText
            }

            Text { text: "Timezone"; color: Theme.textSecondary; font.pixelSize: 12 }
            ComboBox {
                id: tzCombo
                Layout.fillWidth: true
                model: ["Etc/UTC", "America/Argentina/Buenos_Aires",
                        "America/Los_Angeles", "America/New_York",
                        "Europe/Madrid", "Europe/Berlin", "Europe/London",
                        "Asia/Tokyo", "Asia/Shanghai"]
                currentIndex: 0
                onCurrentTextChanged: backend.timezone = currentText
                Component.onCompleted: backend.timezone = currentText
            }
        }

        Item { Layout.fillHeight: true }
    }
}
