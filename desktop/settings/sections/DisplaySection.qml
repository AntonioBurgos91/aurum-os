// DisplaySection — monitors, brightness and warm/night light.
//
// Binds to the C++ `displayMgr` (aurum::settings::DisplayManager) exposed as a
// context property in main.cpp. Reading is live via `displayMgr.monitors`;
// actions are Q_INVOKABLE calls that shell out to hyprctl / sysfs / ddcutil /
// hyprsunset. Styling follows GpuSection (SectionCard + Theme).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 12

        // ── Monitors ──────────────────────────────────────────────────────
        SectionCard {
            Layout.fillWidth: true
            title:    "Displays"
            subtitle: displayMgr.monitors.length + " connected"

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                Repeater {
                    model: displayMgr.monitors
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 96
                        radius: Theme.cornerRadius
                        color: Theme.surface
                        border.color: modelData.focused ? Theme.accent : Theme.border

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 16

                            ColumnLayout {
                                spacing: 2
                                Text {
                                    text: modelData.name
                                    color: Theme.textPrimary
                                    font.pixelSize: 16; font.bold: true
                                }
                                Text {
                                    text: modelData.description
                                    color: Theme.textSecondary; font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 240
                                }
                                Text {
                                    text: modelData.width + "×" + modelData.height +
                                          " @ " + Math.round(modelData.refresh) + "Hz" +
                                          "   ·   scale " + modelData.scale.toFixed(2) +
                                          "   ·   (" + modelData.x + "," + modelData.y + ")"
                                    color: Theme.textSecondary; font.pixelSize: 11
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Switch {
                                text: modelData.active ? "On" : "Off"
                                checked: modelData.active
                                onToggled: displayMgr.setEnabled(modelData.name, checked)
                            }
                        }
                    }
                }

                // Two-monitor quick arrangements (shown when ≥2 connected).
                RowLayout {
                    Layout.fillWidth: true
                    visible: displayMgr.monitors.length >= 2
                    spacing: 12

                    Button {
                        text: "Extend ⇆"
                        onClicked: displayMgr.arrangeExtend(
                            displayMgr.monitors[0].name, displayMgr.monitors[1].name)
                    }
                    Button {
                        text: "Mirror ⧉"
                        onClicked: displayMgr.arrangeMirror(
                            displayMgr.monitors[0].name, displayMgr.monitors[1].name)
                    }
                    Item { Layout.fillWidth: true }
                    Button {
                        text: "Refresh"
                        onClicked: displayMgr.refresh()
                    }
                }
            }
        }

        // ── Brightness ────────────────────────────────────────────────────
        SectionCard {
            Layout.fillWidth: true
            title:    "Brightness"
            subtitle: "Laptop panel via backlight; external monitors via DDC/CI"

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: displayMgr.monitors
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            text: modelData.name
                            color: Theme.textPrimary; font.pixelSize: 13
                            Layout.preferredWidth: 90
                        }
                        Slider {
                            id: brightnessSlider
                            Layout.fillWidth: true
                            from: 0; to: 100; stepSize: 1
                            value: modelData.brightness !== undefined ? modelData.brightness : 100
                            onPressedChanged: if (!pressed)
                                displayMgr.setBrightness(modelData.name, Math.round(value))
                        }
                        Text {
                            text: Math.round(brightnessSlider.value) + "%"
                            color: Theme.textSecondary; font.pixelSize: 12
                            Layout.preferredWidth: 40
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }

        // ── Night light / warm light ────────────────────────────────────────
        SectionCard {
            Layout.fillWidth: true
            title:    "Night Light"
            subtitle: "Warm the display colour temperature to reduce blue light"

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Switch {
                        text: "Enabled"
                        checked: displayMgr.nightLightEnabled
                        onToggled: displayMgr.setNightLight(checked, kelvinSlider.value)
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: Math.round(kelvinSlider.value) + " K · " +
                              displayMgr.kelvinLabel(Math.round(kelvinSlider.value))
                        color: Theme.textSecondary; font.pixelSize: 12
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Text { text: "Warm"; color: Theme.textSecondary; font.pixelSize: 11 }
                    Slider {
                        id: kelvinSlider
                        Layout.fillWidth: true
                        from: 1000; to: 6500; stepSize: 100
                        value: displayMgr.nightLightKelvin
                        onPressedChanged: if (!pressed && displayMgr.nightLightEnabled)
                            displayMgr.setNightLight(true, Math.round(value))
                    }
                    Text { text: "Cool"; color: Theme.textSecondary; font.pixelSize: 11 }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
