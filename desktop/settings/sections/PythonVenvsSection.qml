// PythonVenvsSection — manage user-owned uv virtualenvs.
//
// Wave 10E styling refactor: the "create new" form and the venv list now sit
// inside two shared SectionCards so the layout rhythm matches the rest of
// Settings. Bindings on `venvManager.*` and the delete-confirmation dialog
// are preserved verbatim.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
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

            // ---- Create new ---------------------------------------------------
            SectionCard {
                Layout.fillWidth: true
                title:    "Python virtualenvs"
                subtitle: "Managed via uv. /opt/aurum-dl-venv is locked (system venv)."

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
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }

            // ---- List ---------------------------------------------------------
            SectionCard {
                Layout.fillWidth: true
                Layout.preferredHeight: 360
                title:    "Existing venvs"
                subtitle: venvManager.venvs.length + " environment"
                        + (venvManager.venvs.length === 1 ? "" : "s")
                        + " under management"

                ListView {
                    id: venvList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 260
                    model: venvManager.venvs
                    spacing: 6
                    clip: true
                    delegate: Rectangle {
                        width: venvList.width
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
            }

            Item { Layout.fillHeight: true }
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
