import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

// Agent-only: everything the agent has remembered (qs_claude_memory.md).
// Item-based so it loads into Main's StackView like other popups.
FocusScope {
    id: win
    focus: true

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(v) { return scaler.s(v) }
    MatugenColors { id: th }
    readonly property color accent: th.teal || "#94e2d5"

    function close() { Quickshell.execDetached(["bash", "-c", "echo close > /tmp/qs_widget_state"]) }

    property real intro: 0
    NumberAnimation on intro { from: 0; to: 1; duration: 360; easing.type: Easing.OutBack; easing.overshoot: 1.05; running: true }
    Timer { interval: 900; running: true; onTriggered: win.intro = 1 }

    Rectangle {
        anchors.fill: parent; radius: s(22)
        color: Qt.rgba(th.crust.r, th.crust.g, th.crust.b, 0.98)
        border.width: 1; border.color: Qt.rgba(th.text.r, th.text.g, th.text.b, 0.08)
        opacity: win.intro
        transform: Scale { origin.x: width/2; origin.y: height/2; xScale: win.intro; yScale: win.intro }
        Rectangle { anchors.fill: parent; radius: parent.radius; gradient: Gradient { GradientStop { position: 0.0; color: Qt.rgba(th.surface0.r, th.surface0.g, th.surface0.b, 0.4) } GradientStop { position: 1.0; color: "transparent" } } }

        Column {
            anchors.fill: parent; anchors.margins: s(24); spacing: s(16)

            Row {
                spacing: s(10)
                Rectangle { width: s(28); height: s(28); radius: s(9); color: Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.18)
                    Text { anchors.centerIn: parent; text: "󰍛"; font.family: "Iosevka Nerd Font"; font.pixelSize: win.s(15); color: win.accent } }
                Text { text: "Memory"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: win.s(18); color: th.text; anchors.verticalCenter: parent.verticalCenter }
                Text { text: notes.count + " notes"; font.family: "JetBrains Mono"; font.pixelSize: win.s(11); color: th.subtext0; anchors.verticalCenter: parent.verticalCenter }
            }

            TextField {
                id: search
                width: parent.width; height: s(34)
                placeholderText: "Search what I remember…"; placeholderTextColor: th.subtext0; color: th.text
                font.family: "JetBrains Mono"; font.pixelSize: win.s(12)
                background: Rectangle { radius: win.s(9); color: Qt.rgba(th.surface0.r, th.surface0.g, th.surface0.b, 0.6); border.width: 1; border.color: search.activeFocus ? win.accent : Qt.rgba(th.text.r, th.text.g, th.text.b, 0.08) }
                onTextChanged: win.filter = text
                Keys.onEscapePressed: win.close()
                Component.onCompleted: forceActiveFocus()
            }

            ListView {
                id: lv
                width: parent.width; height: parent.height - s(110); clip: true; spacing: s(8)
                model: notes
                delegate: Rectangle {
                    width: lv.width
                    height: Math.max(win.s(48), noteText.implicitHeight + win.s(24))
                    radius: s(12)
                    color: Qt.rgba(th.mantle.r, th.mantle.g, th.mantle.b, 0.6)
                    border.width: 1; border.color: Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.12)
                    Text {
                        id: noteText
                        anchors.fill: parent; anchors.margins: win.s(12)
                        wrapMode: Text.Wrap; textFormat: Text.MarkdownText
                        font.family: "JetBrains Mono"; font.pixelSize: win.s(12); color: th.text
                        text: model.note
                    }
                }
            }
        }
        Text { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottomMargin: win.s(8)
            text: "esc / click outside to close"; font.family: "JetBrains Mono"; font.pixelSize: win.s(9); color: th.subtext0 }
    }

    property string filter: ""
    property var raw: []
    onFilterChanged: rebuild()
    function rebuild() {
        let f = filter.toLowerCase()
        let list = f ? raw.filter(n => n.toLowerCase().indexOf(f) >= 0) : raw
        notes.clear()
        for (let n of list) notes.append({ note: n })
    }
    ListModel { id: notes }

    Process {
        running: true
        // memory file is bullets — split into notes, strip leading "- "
        command: ["bash", "-c", "f=~/.local/share/qs_claude_memory.md; [ -f \"$f\" ] && jq -Rsc 'split(\"\\n\") | map(select(length>0))' \"$f\" || echo '[]'"]
        stdout: StdioCollector { onStreamFinished: {
            try {
                let d = JSON.parse(this.text.trim() || "[]")
                d = d.map(x => x.replace(/^- /, "")).filter(x => x.trim().length)
                win.raw = d.reverse()
                win.rebuild()
            } catch (e) {}
        } }
    }
    Keys.onEscapePressed: win.close()
}
