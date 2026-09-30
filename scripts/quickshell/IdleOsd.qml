import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import "./"

// idle-lock toggle OSD. trigger file: "paused" | "resumed"
OsdBase {
    id: osd
    WlrLayershell.namespace: "qs-idle-osd"
    watchFile: "/tmp/qs_idle_osd"
    holdMs: 1500
    accent: osd.paused ? (osd.cRed || "#f38ba8") : (osd.cGreen || "#a6e3a1")

    property bool paused: false
    onTriggered: (text) => osd.paused = text.trim() === "paused"

    RowLayout {
        spacing: osd.s(10)
        Text {
            font.family: "Iosevka Nerd Font"; font.pixelSize: osd.s(20)
            color: osd.accent
            text: osd.paused ? "󰒲" : "󰒳"
        }
        Text {
            font.family: "JetBrains Mono"; font.weight: Font.Black
            font.pixelSize: osd.s(16); color: osd.cText
            text: osd.paused ? "Idle Lock Paused" : "Idle Lock Resumed"
        }
    }
}
