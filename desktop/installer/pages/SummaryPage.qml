import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    property bool valid: backend.validate() === ""

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 48
        spacing: 12

        Text { text: "Ready to install"; color: Theme.textPrimary
               font.bold: true; font.pixelSize: 22 }
        Text {
            text: "Review your choices. Clicking Install will erase the selected disk."
            color: Theme.warning
            font.pixelSize: 12
        }

        GridLayout {
            columns: 2
            columnSpacing: 24
            rowSpacing: 6
            Layout.fillWidth: true

            Text { text: "Disk:";        color: Theme.textSecondary; font.pixelSize: 12 }
            Text { text: backend.device; color: Theme.textPrimary;  font.pixelSize: 12 }
            Text { text: "Filesystem:";  color: Theme.textSecondary; font.pixelSize: 12 }
            Text { text: backend.filesystem + (backend.encryptDisk ? " (encrypted)" : "")
                   color: Theme.textPrimary; font.pixelSize: 12 }
            Text { text: "Hostname:";    color: Theme.textSecondary; font.pixelSize: 12 }
            Text { text: backend.hostname; color: Theme.textPrimary; font.pixelSize: 12 }
            Text { text: "User:";        color: Theme.textSecondary; font.pixelSize: 12 }
            Text { text: backend.username + "  (" + (backend.fullName || "unset") + ")"
                   color: Theme.textPrimary; font.pixelSize: 12 }
            Text { text: "Locale:";      color: Theme.textSecondary; font.pixelSize: 12 }
            Text { text: backend.locale + "    " + backend.keyboard + "    " + backend.timezone
                   color: Theme.textPrimary; font.pixelSize: 12 }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        Text { text: "Command preview"; color: Theme.textSecondary
               font.bold: true; font.pixelSize: 11 }
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            TextArea {
                readOnly: true
                wrapMode: TextArea.Wrap
                font.family: "FiraCode"
                font.pixelSize: 11
                color: Theme.textPrimary
                background: Rectangle { color: Theme.surface; border.color: Theme.border; radius: 6 }
                // distinst hides the password from the displayed command;
                // we mirror the same redaction here.
                text: {
                    const args = backend.commandPreview()
                    let out = "distinst"
                    for (let i = 0; i < args.length; ++i) {
                        const v = args[i]
                        if (args[i-1] === "--password" || args[i-1] === "--encrypt-disk") {
                            out += " " + (v ? "*****" : "")
                        } else {
                            out += " " + v
                        }
                    }
                    return out
                }
            }
        }

        Text {
            visible: !valid
            text: "" + (backend.validate())
            color: Theme.danger
            font.pixelSize: 11
        }
    }
}
