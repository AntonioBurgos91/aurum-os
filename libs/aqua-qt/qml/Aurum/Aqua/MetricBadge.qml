// Compact circular/rounded metric badge for menubar + dock applets.
// Caller supplies the label, value text, and a threshold trio for coloring.
import QtQuick
import Aurum.Aqua 1.0

Rectangle {
    id: root

    property string label: ""
    property string valueText: ""
    property int    valueNumeric: 0
    property int    warnAt: 70
    property int    critAt: 90
    property color  valueColor: valueNumeric >= critAt ? Theme.danger
                              : valueNumeric >= warnAt ? Theme.warning
                              :                          Theme.success

    implicitWidth: 48
    implicitHeight: 48
    radius: Theme.cornerRadiusSm
    color: Theme.surfaceRaised
    border.color: Theme.border
    border.width: Theme.strokeWidth

    Column {
        anchors.centerIn: parent
        spacing: 2

        Text {
            text: root.label
            font.bold: true
            font.pixelSize: 8
            color: Theme.textSecondary
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: root.valueText
            font.bold: true
            font.pixelSize: 11
            color: root.valueColor
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
