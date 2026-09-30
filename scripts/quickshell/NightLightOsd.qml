import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import "./"

// night-light OSD. trigger file: "<icon-glyph> <TEXT>" e.g. "󰌔 AUTO ON"
OsdBase {
    id: osd
    WlrLayershell.namespace: "qs-nl-osd"
    watchFile: "/tmp/qs_nl_osd"
    holdMs: 1400
    accent: osd.cPeach || "#fab387"

    property string osdIcon: "󰌔"
    property string osdText: ""
    onTriggered: (text) => {
        let parts = text.trim().split(" ")
        osd.osdIcon = parts[0]
        osd.osdText = parts.slice(1).join(" ")
    }

    RowLayout {
        spacing: osd.s(10)
        Text {
            font.family: "Iosevka Nerd Font"; font.pixelSize: osd.s(20)
            color: osd.accent
            text: osd.osdIcon
        }
        Text {
            font.family: "JetBrains Mono"; font.weight: Font.Black
            font.pixelSize: osd.s(14); color: osd.cText
            text: osd.osdText
        }
    }
}
