import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    property bool valid: usernameField.text.length >= 1
                      && passwordField.text.length >= 8
                      && confirmField.text === passwordField.text
                      && hostnameField.text.length >= 1

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 48
        spacing: 14

        Text { text: "Create your user"; color: Theme.textPrimary
               font.bold: true; font.pixelSize: 22 }

        GridLayout {
            columns: 2
            columnSpacing: 16
            rowSpacing: 8
            Layout.fillWidth: true

            Text { text: "Full name"; color: Theme.textSecondary; font.pixelSize: 12 }
            TextField {
                id: fullNameField
                Layout.fillWidth: true
                placeholderText: "Alex Researcher"
                onTextChanged: backend.fullName = text
            }

            Text { text: "Username"; color: Theme.textSecondary; font.pixelSize: 12 }
            TextField {
                id: usernameField
                Layout.fillWidth: true
                placeholderText: "alex"
                validator: RegularExpressionValidator { regularExpression: /^[a-z_][a-z0-9_-]{0,31}$/ }
                onTextChanged: backend.username = text
            }

            Text { text: "Password"; color: Theme.textSecondary; font.pixelSize: 12 }
            TextField {
                id: passwordField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                onTextChanged: backend.password = text
            }

            Text { text: "Confirm password"; color: Theme.textSecondary; font.pixelSize: 12 }
            TextField {
                id: confirmField
                Layout.fillWidth: true
                echoMode: TextInput.Password
            }

            Text { text: "Hostname"; color: Theme.textSecondary; font.pixelSize: 12 }
            TextField {
                id: hostnameField
                Layout.fillWidth: true
                text: "aurumos"
                onTextChanged: backend.hostname = text
            }
        }

        Text {
            visible: !valid && passwordField.text.length > 0
            text: confirmField.text !== passwordField.text
                ? "Passwords do not match"
                : passwordField.text.length < 8
                  ? "Password must be at least 8 characters"
                  : ""
            color: Theme.danger
            font.pixelSize: 11
        }

        Item { Layout.fillHeight: true }
    }
}
