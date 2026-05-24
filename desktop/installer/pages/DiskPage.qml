import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    property bool valid: backend.device !== ""
    property int selected: -1

    Component.onCompleted: diskLister.refresh()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 48
        spacing: 14

        Text { text: "Choose a disk"; color: Theme.textPrimary
               font.bold: true; font.pixelSize: 22 }
        Text {
            text: "AurumOS will use the entire disk you select. Existing data will be erased."
            color: Theme.warning
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: diskLister.disks
            spacing: 8
            clip: true
            delegate: Rectangle {
                width: ListView.view.width
                height: 62
                radius: Theme.cornerRadius
                color: index === selected ? Theme.accent
                      : hov.containsMouse  ? Theme.surfaceRaised
                      :                       Theme.surface
                border.color: index === selected ? Theme.accent : Theme.border
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    spacing: 16

                    ColumnLayout {
                        Layout.fillWidth: true
                        Text {
                            text: modelData.model + "    " + modelData.sizeHuman
                            color: index === selected ? Theme.accentText : Theme.textPrimary
                            font.bold: true
                            font.pixelSize: 14
                        }
                        Text {
                            text: modelData.device + "    " + modelData.transport.toUpperCase() +
                                  (modelData.rotational ? "  (HDD)" : "  (SSD)")
                            color: Theme.textSecondary
                            font.pixelSize: 11
                        }
                    }
                    Text {
                        visible: modelData.warning.length > 0
                        text: " " + modelData.warning
                        color: Theme.warning
                        font.pixelSize: 11
                    }
                }

                MouseArea {
                    id: hov
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        selected = index
                        backend.device = modelData.device
                    }
                }
            }
        }

        // Filesystem + encryption picker.
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            Text { text: "Filesystem"; color: Theme.textSecondary; font.pixelSize: 12 }
            ComboBox {
                model: ["bcachefs", "ext4", "btrfs"]
                onCurrentTextChanged: backend.filesystem = currentText
                Component.onCompleted: backend.filesystem = currentText
            }
            CheckBox {
                text: "Encrypt disk (LUKS)"
                onCheckedChanged: backend.encryptDisk = checked
            }
            Item { Layout.fillWidth: true }
            Button { text: "Rescan"; onClicked: diskLister.refresh() }
        }
    }
}
