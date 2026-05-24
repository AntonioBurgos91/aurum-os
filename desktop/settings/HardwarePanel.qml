// HardwarePanel — Settings tab that surfaces the detected AurumOS profile.
//
// Read-only summary plus a power-user override that re-runs the detection
// script with AURUM_PROFILE pinned. The "what this profile installs" table is
// the same source of truth as 00-detect-profile.sh — keep them in sync when
// adding new keys.
//
// Data source: `profileClient` context property (libs/core-services
// ProfileClient singleton wired in desktop/settings/main.cpp).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Aurum.Aqua 1.0

Item {
    id: panel

    // Colour the badge by tier so users get a single visual cue for "what
    // class of machine does AurumOS think I have". Hex literals match the
    // existing Theme accent / warning / danger palette.
    function badgeColor(p) {
        switch (p) {
            case "workstation": return Theme.accent
            case "pro":         return "#4a9eff"
            case "standard":    return Theme.success
            case "lite":        return Theme.warning
            default:            return Theme.surfaceRaised
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 18

        Text {
            text: "Hardware Profile"
            color: Theme.textPrimary
            font.bold: true
            font.pixelSize: 20
        }

        // --- Big tier badge --------------------------------------------------
        Rectangle {
            Layout.preferredWidth: 240
            Layout.preferredHeight: 80
            radius: Theme.cornerRadius
            color: panel.badgeColor(profileClient.profile)
            border.color: Theme.border
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 2
                Text {
                    text: profileClient.profile.toUpperCase()
                    color: "#FFFFFF"
                    font.pixelSize: 28
                    font.bold: true
                }
                Text {
                    text: "Detected profile (auto)"
                    color: "#E0E0E0"
                    font.pixelSize: 11
                }
            }
        }

        // --- Detected hardware grid -----------------------------------------
        GridLayout {
            columns: 2
            columnSpacing: 24
            rowSpacing: 8
            Layout.fillWidth: true

            Text { text: "GPU";  color: Theme.textSecondary; font.pixelSize: 12 }
            Text { text: profileClient.gpuName; color: Theme.textPrimary;
                   font.pixelSize: 13; font.bold: true }

            Text { text: "VRAM"; color: Theme.textSecondary; font.pixelSize: 12 }
            Text {
                text: profileClient.vramMb > 0
                      ? (profileClient.vramMb + " MB ("
                         + (profileClient.vramMb / 1024).toFixed(1) + " GB)")
                      : "—  (CPU-only)"
                color: Theme.textPrimary; font.pixelSize: 13
            }

            Text { text: "RAM";  color: Theme.textSecondary; font.pixelSize: 12 }
            Text { text: profileClient.ramGb + " GB"; color: Theme.textPrimary;
                   font.pixelSize: 13 }

            Text { text: "CUDA"; color: Theme.textSecondary; font.pixelSize: 12 }
            Text {
                text: profileClient.hasCuda ? "available" : "not available"
                color: profileClient.hasCuda ? Theme.success : Theme.warning
                font.pixelSize: 13; font.bold: true
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        // --- Override row ----------------------------------------------------
        RowLayout {
            spacing: 12
            Layout.fillWidth: true

            Text {
                text: "Override:"
                color: Theme.textSecondary
                font.pixelSize: 12
                Layout.alignment: Qt.AlignVCenter
            }
            Repeater {
                model: ["lite", "standard", "pro", "workstation"]
                Button {
                    text: modelData
                    enabled: modelData !== profileClient.profile
                    // Power-user knob. The exec hook is wired in main.cpp via
                    // a small QProcess slot on profileClient.requestOverride —
                    // we just emit the signal here. The button stays subtle
                    // (no accent color) so users aren't tempted to click it.
                    onClicked: profileClient.requestOverride
                               ? profileClient.requestOverride(modelData)
                               : console.log("override:", modelData)
                }
            }
        }

        Text {
            text: "⚠  Overriding the auto-detected profile is not recommended. "
                + "Wave 8 launchers (vLLM, Unsloth, ComfyUI) pick model sizes "
                + "and VRAM flags from this value — forcing a profile higher "
                + "than your hardware will cause OOM crashes; forcing one "
                + "lower wastes capacity."
            color: Theme.textSecondary
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        // --- Per-profile defaults table -------------------------------------
        Text {
            text: "What each profile installs"
            color: Theme.textPrimary
            font.bold: true
            font.pixelSize: 14
        }

        // Pure-QML mini-table. We avoid TableView here because the row count
        // is fixed (4 tiers × ~8 keys) and TableView's lazy-realisation buys
        // us nothing while breaking the macOS-Sequoia surface styling.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: contentCol.implicitHeight + 16
            radius: Theme.cornerRadius
            color: Theme.surface
            border.color: Theme.border

            ColumnLayout {
                id: contentCol
                anchors.fill: parent
                anchors.margins: 8
                spacing: 0

                // Header row
                RowLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    Repeater {
                        model: ["Setting", "lite", "standard", "pro", "workstation"]
                        Text {
                            text: modelData
                            color: Theme.textSecondary
                            font.bold: true
                            font.pixelSize: 11
                            Layout.fillWidth: true
                            Layout.preferredWidth: 100
                            padding: 6
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                Repeater {
                    // Each row: [label, lite_val, standard_val, pro_val, ws_val].
                    // Mirrors emit_profile_keys() in 00-detect-profile.sh.
                    model: [
                        ["Ollama default",  "qwen2.5-coder:1.5b", "qwen2.5-coder:7b", "qwen2.5-coder:14b", "qwen2.5-coder:32b"],
                        ["Ollama chat",     "qwen2.5:1.5b",       "qwen2.5:7b",       "qwen2.5:14b",       "qwen2.5:32b"],
                        ["ComfyUI flags",   "--cpu",              "--medvram",        "--highvram",        "--highvram --bf16-vae"],
                        ["vLLM args",       "--device cpu",       "awq, 8k ctx",      "awq, 16k ctx",      "fp16, 32k ctx"],
                        ["Unsloth recipe",  "qlora-4bit-1b",      "qlora-4bit-7b",    "qlora-4bit-14b",    "qlora-4bit-32b"],
                        ["SD model",        "sd15-int8",          "sdxl-turbo-int8",  "sdxl-fp16",         "sdxl-fp16"],
                        ["Whisper",         "tiny",               "small",            "medium",            "large-v3"],
                        ["YOLO",            "yolov11n",           "yolov11s",         "yolov11m",          "yolov11x"],
                        ["SAM",             "sam2-tiny",          "sam2-base",        "sam2-large",        "sam2-large"],
                        ["LLaVA",           "llava-phi-int4",     "llava-7b-int4",    "llava-13b-int4",    "llava-34b-int4"]
                    ]
                    RowLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        Repeater {
                            model: modelData
                            Text {
                                text: modelData
                                color: index === 0 ? Theme.textSecondary
                                                    : (profileColIsActive(index) ? Theme.accent : Theme.textPrimary)
                                font.pixelSize: 11
                                font.bold: index === 0 || profileColIsActive(index)
                                Layout.fillWidth: true
                                Layout.preferredWidth: 100
                                padding: 6
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    // Map column index (1..4) → profile name; highlight the active one.
    function profileColIsActive(col) {
        const map = { 1: "lite", 2: "standard", 3: "pro", 4: "workstation" }
        return map[col] === profileClient.profile
    }
}
