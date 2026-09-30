import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import "./"

// Spotify-only MPRIS volume OSD (SUPER+volume keys). trigger file: "<0-100 int>"
OsdBase {
    id: osd
    WlrLayershell.namespace: "qs-spotify-volume-osd"
    watchFile: "/tmp/qs_spotify_volume_osd"
    holdMs: 1000
    accent: osd.cGreen || "#a6e3a1"

    property int level: 0
    onTriggered: (text) => osd.level = Math.max(0, Math.min(100, parseInt(text.trim()) || 0))

    RowLayout {
        spacing: osd.s(14)

        Text {
            font.family: "Iosevka Nerd Font"; font.pixelSize: osd.s(20)
            color: osd.accent
            text: "󰓇"
        }

        Rectangle {
            Layout.preferredWidth: osd.s(130)
            Layout.preferredHeight: osd.s(10)
            radius: height / 2
            color: osd.cMantle
            border.width: 1
            border.color: Qt.rgba(osd.cText.r, osd.cText.g, osd.cText.b, 0.08)
            clip: true

            Rectangle {
                height: parent.height
                width: parent.width * (osd.level / 100)
                radius: parent.height / 2
                color: osd.accent
            }
        }

        Text {
            Layout.preferredWidth: osd.s(38)
            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: osd.s(14)
            color: osd.cText
            text: osd.level + "%"
            horizontalAlignment: Text.AlignRight
        }
    }
}
