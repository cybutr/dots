import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import "./"

// Lightweight transient OSD for the resident's shortest-lived single facts
// (e.g. "freed 2.1GB" after a proactive fix resolves) — a lighter channel
// than the resident card queue, not a replacement for it. Trigger file
// takes a JSON payload: {"text": "...", "icon": "", "tint": "#a6e3a1"}.
// A plain non-JSON string is also accepted and shown as-is.
OsdBase {
    id: osd
    WlrLayershell.namespace: "qs-resident-osd"
    watchFile: "/tmp/qs_resident_osd"
    holdMs: 3200
    accent: osd.tint !== "" ? osd.tint : osd.cGreen
    springEntrance: true
    breathingBorder: true

    property string msgText: ""
    property string msgIcon: "󰚩"
    property string tint: ""

    onTriggered: (text) => {
        let t = "", i = "󰚩", tn = ""
        try {
            let p = JSON.parse(text)
            t = p.text || ""
            i = p.icon || "󰚩"
            tn = p.tint || ""
        } catch (e) {
            t = text
        }
        osd.msgText = t
        osd.msgIcon = i
        osd.tint = tn
    }

    RowLayout {
        spacing: osd.s(11)
        // Rounded tinted backing behind the glyph, matching the hover-card
        // icon treatment elsewhere in the bar rather than a bare glyph.
        Rectangle {
            Layout.preferredWidth: osd.s(30)
            Layout.preferredHeight: osd.s(30)
            radius: osd.s(15)
            color: Qt.rgba(osd.accent.r, osd.accent.g, osd.accent.b, 0.16)
            border.width: 1
            border.color: Qt.rgba(osd.accent.r, osd.accent.g, osd.accent.b, 0.40)
            Text {
                anchors.centerIn: parent
                font.family: "Iosevka Nerd Font"; font.pixelSize: osd.s(15)
                color: osd.accent
                text: osd.msgIcon
            }
        }
        Text {
            id: osdBodyText
            font.family: "JetBrains Mono"; font.weight: Font.Black
            font.pixelSize: osd.s(15); color: osd.cText
            text: osd.msgText
            elide: Text.ElideRight
            // Two things were needed, not one: Layout.maximumWidth alone
            // never engages because this RowLayout isn't being squeezed by
            // anything (it just sizes to natural content), so "maximum"
            // never kicks in. And a plain `width:` binding doesn't work
            // either — RowLayout overwrites a direct child's width every
            // relayout pass regardless of what you bind it to (same gotcha
            // documented in this project's CLAUDE.md for MouseArea sizing).
            // Layout.preferredWidth is the one property RowLayout actually
            // respects for sizing a child, so that's what has to carry the cap.
            Layout.preferredWidth: Math.min(implicitWidth, osd.s(420))
        }
    }
}
