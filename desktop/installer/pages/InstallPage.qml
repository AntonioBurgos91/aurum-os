import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    property bool valid: !backend.running && backend.succeeded

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 48
        spacing: 14

        Text { text: "Installing AurumOS"; color: Theme.textPrimary
               font.bold: true; font.pixelSize: 22 }
        Text { text: backend.status; color: Theme.textSecondary; font.pixelSize: 14 }

        ProgressBar {
            Layout.fillWidth: true
            from: 0; to: 100
            value: backend.progress
            indeterminate: backend.progress === 0 && backend.running
        }

        // Live distinst log; tail to stay scrolled at the bottom so the user
        // can watch progress without manually chasing it.
        ScrollView {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            TextArea {
                id: logArea
                readOnly: true
                wrapMode: TextArea.NoWrap
                font.family: "FiraCode"
                font.pixelSize: 11
                color: Theme.textPrimary
                background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: 6 }
                text: backend.lastLog
                onTextChanged: cursorPosition = length
            }
        }
    }
}
