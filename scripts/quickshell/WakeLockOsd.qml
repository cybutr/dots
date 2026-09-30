import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import "./"

// keep-awake (lid-close/sleep inhibit) toggle OSD. trigger file: "on" | "off"
OsdBase {
    id: osd
    WlrLayershell.namespace: "qs-wakelock-osd"
    watchFile: "/tmp/qs_wakelock_osd"
    holdMs: 1500
    accent: osd.awake ? (osd.cGreen || "#a6e3a1") : osd.cText

    property bool awake: false
    onTriggered: (text) => osd.awake = text.trim() === "on"

    RowLayout {
        spacing: osd.s(10)
        Text {
            font.family: "Iosevka Nerd Font"; font.pixelSize: osd.s(20)
            color: osd.accent
            text: osd.awake ? "󰛊" : "󰤄"
        }
        Text {
            font.family: "JetBrains Mono"; font.weight: Font.Black
            font.pixelSize: osd.s(16); color: osd.cText
            text: osd.awake ? "Stay Awake On" : "Stay Awake Off"
        }
    }
}
