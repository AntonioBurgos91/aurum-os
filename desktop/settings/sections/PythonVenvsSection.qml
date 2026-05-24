import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Aurum.Aqua 1.0

Item {
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        Text { text: "Python virtualenvs"; color: Theme.textPrimary; font.bold: true; font.pixelSize: 20 }
        Text { text: "Managed via uv. /opt/aurum-dl-venv is locked (system venv)."
               color: Theme.textSecondary; font.pixelSize: 12 }

        // --- Create new ----------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            radius: Theme.cornerRadius
            color: Theme.surface
            border.color: Theme.border
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10
                Text { text: "New:"; color: Theme.textSecondary; font.pixelSize: 12 }
                TextField {
                    id: newPath
                    Layout.fillWidth: true
                    placeholderText: "/home/.../venvs/my-venv"
                }
                ComboBox {
                    id: pyVer
                    model: venvManager.availablePythons
                    currentIndex: 0
                    Layout.preferredWidth: 110
                }
                Button {
                    text: "Create"
                    enabled: !venvManager.busy && newPath.text.length > 1
                    onClicked: venvManager.createVenv(newPath.text, pyVer.currentText)
                }
            }
        }

        Text {
            visible: venvManager.lastError.length > 0
            text: " " + venvManager.lastError
            color: Theme.danger
            font.pixelSize: 11
        }

        // --- List ----------------------------------------------------------
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: venvManager.venvs
            spacing: 6
            clip: true
            delegate: Rectangle {
                width: ListView.view.width
                height: 56
                radius: Theme.cornerRadius
                color: Theme.surface
                border.color: Theme.border
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        Text { text: modelData.name; color: Theme.textPrimary; font.bold: true; font.pixelSize: 14 }
                        Text {
                            text: modelData.path + "    " +
                                  "Python " + modelData.pythonVer + "    " +
                                  modelData.sizeMB + " MB"
                            color: Theme.textSecondary
                            font.pixelSize: 11
                        }
                    }
                    Text {
                        text: modelData.locked ? " locked" : ""
                        color: Theme.warning
                        font.pixelSize: 10
                        font.bold: true
                    }
                    Button {
                        text: "Delete"
                        enabled: !modelData.locked && !venvManager.busy
                        onClicked: confirmDelete.openFor(modelData.path)
                    }
                }
            }
        }

        MessageDialog {
            id: confirmDelete
            property string target: ""
            function openFor(p) { target = p; open() }
            text: "Delete venv?"
            informativeText: "This removes the directory and all installed packages.\n" + target
            buttons: MessageDialog.Yes | MessageDialog.No
            onAccepted: venvManager.deleteVenv(target)
        }
    }
}
