import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import "./"

// account / key switch OSD. trigger file: label \t type \t email
OsdBase {
    id: osd
    WlrLayershell.namespace: "qs-acct-osd"
    watchFile: "/tmp/qs_acct_osd"
    holdMs: 1500
    accent: osd.cMauve || "#cba6f7"

    property string label: ""
    property string type: "account"
    property string email: ""

    onTriggered: (text) => {
        let p = text.split("\t")
        osd.label = p[0] || ""
        osd.type  = p[1] || "account"
        osd.email = p[2] || ""
    }

    RowLayout {
        spacing: osd.s(10)
        Text {
            font.family: "Iosevka Nerd Font"; font.pixelSize: osd.s(20)
            color: osd.accent
            text: osd.type === "key" ? "󰌆" : "󰀄"
        }
        ColumnLayout {
            spacing: 0
            Text {
                font.family: "JetBrains Mono"; font.weight: Font.Black
                font.pixelSize: osd.s(16); color: osd.cText
                text: osd.label
            }
            Text {
                visible: osd.email !== ""
                font.family: "JetBrains Mono"; font.pixelSize: osd.s(9)
                color: osd.cSubtext0
                text: osd.email
            }
        }
    }
}
