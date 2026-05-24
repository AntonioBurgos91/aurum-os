// GeneralSection — read-only "appearance & behaviour" summary in Settings.
//
// Wave 10E styling refactor: previously a free-floating ColumnLayout with an
// ad-hoc 20px title; now wrapped in shared SectionCard components so the
// panel looks identical to Hardware / CUDA / venvs / MLOps / Model Packs.
// No behaviour change — all bindings and labels are preserved.
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
            title:    "General"
            subtitle: "AurumOS keeps appearance and behaviour tokens centralized in "
                    + "/etc/aurum/hypr/aurum.conf and the Aurum.Aqua QML module. "
                    + "Phase 5 ships a read-only summary here; live tweaks land in a later phase."

            SettingsRow { label: "Theme";      control: Text { text: "Sequoia Dark (Fusion)"; color: Theme.textPrimary; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight } }
            SettingsRow { label: "Font";       control: Text { text: "Inter — 13 px"; color: Theme.textPrimary; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight } }
            SettingsRow { label: "Compositor"; control: Text { text: "Hyprland (AurumOS fork)"; color: Theme.textPrimary; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }; isLast: true }
        }

        Item { Layout.fillHeight: true }
    }
}
