import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import "./"

// adaptive brightness curve toggle OSD. trigger file: "on" | "off"
OsdBase {
    id: osd
    WlrLayershell.namespace: "qs-brightness-curve-osd"
    watchFile: "/tmp/qs_brightness_curve_osd"
    holdMs: 1500
    accent: osd.enabled ? (osd.cPeach || "#fab387") : osd.cText

    property bool enabled: true
    onTriggered: (text) => osd.enabled = text.trim() === "on"

    RowLayout {
        spacing: osd.s(10)
        Text {
            font.family: "Iosevka Nerd Font"; font.pixelSize: osd.s(20)
            color: osd.accent
            text: osd.enabled ? "󰃟" : "󰃠"
        }
        Text {
            font.family: "JetBrains Mono"; font.weight: Font.Black
            font.pixelSize: osd.s(16); color: osd.cText
            text: osd.enabled ? "Brightness Curve On" : "Brightness Curve Off"
        }
    }
}
