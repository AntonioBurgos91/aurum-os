// Reusable "glass shelf" background used by the dock and the menubar.
// We deliberately do NOT use real blur — see ADR-0002, blur burns GPU we
// reserve for tensor ops. Instead we approximate with a tinted opaque fill.
import QtQuick
import Aurum.Aqua 1.0

Rectangle {
    id: root
    radius: Theme.cornerRadius
    color: Theme.surface
    opacity: 0.92
    border.color: Theme.border
    border.width: Theme.strokeWidth
}
