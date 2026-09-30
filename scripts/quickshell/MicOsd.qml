import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import "./"

// mic mute OSD. trigger file: "muted" | "live"
OsdBase {
    id: osd
    WlrLayershell.namespace: "qs-mic-osd"
    watchFile: "/tmp/qs_mic_osd"
    holdMs: 1200
    accent: osd.muted ? (osd.cRed || "#f38ba8") : (osd.cGreen || "#a6e3a1")

    property bool muted: false
    onTriggered: (text) => osd.muted = text.trim() === "muted"

    RowLayout {
        spacing: osd.s(10)
        Text {
            font.family: "Iosevka Nerd Font"; font.pixelSize: osd.s(20)
            color: osd.accent
            text: osd.muted ? "󰍭" : "󰍬"
        }
        Text {
            font.family: "JetBrains Mono"; font.weight: Font.Black
            font.pixelSize: osd.s(16); color: osd.cText
            text: osd.muted ? "Mic Muted" : "Mic Live"
        }
    }
}
