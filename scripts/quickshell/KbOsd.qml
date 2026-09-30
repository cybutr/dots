import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import "./"

// keyboard-layout OSD. trigger file: bare 2-letter code (e.g. "EN")
OsdBase {
    id: osd
    WlrLayershell.namespace: "qs-kb-osd"
    watchFile: "/tmp/qs_kb_osd"
    holdMs: 1400
    accent: osd.cBlue || "#89b4fa"

    property string layout: ""
    onTriggered: (text) => osd.layout = text.trim()

    RowLayout {
        spacing: osd.s(10)
        Text {
            font.family: "Iosevka Nerd Font"; font.pixelSize: osd.s(20)
            color: osd.accent
            text: "󰌌"
        }
        Text {
            font.family: "JetBrains Mono"; font.weight: Font.Black
            font.pixelSize: osd.s(16); color: osd.cText
            text: osd.layout
        }
    }
}
