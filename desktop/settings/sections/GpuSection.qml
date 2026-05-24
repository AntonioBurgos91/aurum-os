// GpuSection — live GPU utilisation / VRAM / temperature dashboard in Settings.
//
// Wave 10E styling refactor: the three coloured "stat tiles" used to be free
// Rectangles styled inline; they now live inside one shared SectionCard so the
// section matches the rest of the Settings app. The tiles themselves keep
// their custom layout because they're gauges, not label/control rows — a
// SettingsRow would lose the big numeric readout.
// Bindings to `gpuLive` and all colour-by-threshold logic preserved verbatim.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 12

        SectionCard {
            Layout.fillWidth: true
            title:    "GPU"
            subtitle: gpuLive.gpuName

            // Three stat tiles: utilization, VRAM, temperature.
            // Kept as a RowLayout of Rectangles (not SettingsRow) because
            // these are dashboard tiles with big numeric readouts.
            RowLayout {
                Layout.fillWidth: true
                spacing: 24

                // Utilization
                Rectangle {
                    Layout.preferredWidth: 220
                    Layout.preferredHeight: 120
                    radius: Theme.cornerRadius
                    color: Theme.surface
                    border.color: Theme.border
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 4
                        Text { text: "Utilization"; color: Theme.textSecondary; font.pixelSize: 11 }
                        Text {
                            text: gpuLive.gpuUtilization + " %"
                            color: gpuLive.gpuUtilization >= 90 ? Theme.danger
                                 : gpuLive.gpuUtilization >= 70 ? Theme.warning
                                 :                                 Theme.success
                            font.pixelSize: 32
                            font.bold: true
                        }
                        ProgressBar {
                            Layout.fillWidth: true
                            from: 0; to: 100; value: gpuLive.gpuUtilization
                        }
                    }
                }

                // VRAM
                Rectangle {
                    Layout.preferredWidth: 280
                    Layout.preferredHeight: 120
                    radius: Theme.cornerRadius
                    color: Theme.surface
                    border.color: Theme.border
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 4
                        Text { text: "VRAM"; color: Theme.textSecondary; font.pixelSize: 11 }
                        Text {
                            text: gpuLive.vramUsedGb.toFixed(1) + " / " +
                                  gpuLive.vramTotalGb.toFixed(0) + " GB"
                            color: Theme.textPrimary
                            font.pixelSize: 24
                            font.bold: true
                        }
                        ProgressBar {
                            Layout.fillWidth: true
                            from: 0
                            to: Math.max(1, gpuLive.vramTotalGb)
                            value: gpuLive.vramUsedGb
                        }
                    }
                }

                // Temperature
                Rectangle {
                    Layout.preferredWidth: 160
                    Layout.preferredHeight: 120
                    radius: Theme.cornerRadius
                    color: Theme.surface
                    border.color: Theme.border
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 4
                        Text { text: "Temperature"; color: Theme.textSecondary; font.pixelSize: 11 }
                        Text {
                            text: gpuLive.gpuTemp + " °C"
                            color: gpuLive.gpuTemp >= 85 ? Theme.danger
                                 : gpuLive.gpuTemp >= 75 ? Theme.warning
                                 :                          Theme.textPrimary
                            font.pixelSize: 32
                            font.bold: true
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
