import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import "./"

// caps lock OSD. trigger file: "on" | "off"
OsdBase {
    id: osd
    WlrLayershell.namespace: "qs-caps-osd"
    watchFile: "/tmp/qs_caps_osd"
    holdMs: 1200
    accent: osd.capsOn ? (osd.cPeach || "#fab387") : osd.cSubtext0

    property bool capsOn: false
    onTriggered: (text) => osd.capsOn = text.trim() === "on"

    RowLayout {
        spacing: osd.s(10)
        Text {
            font.family: "Iosevka Nerd Font"; font.pixelSize: osd.s(20)
            color: osd.accent
            text: "󰪛"
        }
        Text {
            font.family: "JetBrains Mono"; font.weight: Font.Black
            font.pixelSize: osd.s(16); color: osd.cText
            text: osd.capsOn ? "Caps Lock On" : "Caps Lock Off"
        }
    }
}
