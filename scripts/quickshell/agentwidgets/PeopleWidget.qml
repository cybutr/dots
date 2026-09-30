import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

// Agent-only: list saved Discord contact profiles (read from people.py --json).
// Loaded into Main's StackView like every other popup, so it shares the blur
// surface and closes via the standard IPC `close`.
FocusScope {
    id: win
    focus: true

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(v) { return scaler.s(v) }
    MatugenColors { id: th }
    readonly property color accent: th.mauve || "#cba6f7"

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

        Row {
            anchors.fill: parent; anchors.margins: s(20); spacing: s(16)

            Column {
                width: s(300); height: parent.height; spacing: s(10)

                Row {
                    spacing: s(10)
                    Rectangle { width: s(28); height: s(28); radius: s(9); color: Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.18)
                        Text { anchors.centerIn: parent; text: "󰀄"; font.family: "Iosevka Nerd Font"; font.pixelSize: win.s(15); color: win.accent } }
                    Text { text: "People"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: win.s(18); color: th.text; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: listModel.count; font.family: "JetBrains Mono"; font.pixelSize: win.s(12); color: th.subtext0; anchors.verticalCenter: parent.verticalCenter }
                }

                TextField {
                    id: search
                    width: parent.width; height: s(36)
                    placeholderText: "Filter…"; placeholderTextColor: th.subtext0; color: th.text
                    font.family: "JetBrains Mono"; font.pixelSize: win.s(12)
                    background: Rectangle { radius: win.s(9); color: Qt.rgba(th.surface0.r, th.surface0.g, th.surface0.b, 0.6); border.width: 1; border.color: search.activeFocus ? win.accent : Qt.rgba(th.text.r, th.text.g, th.text.b, 0.08) }
                    onTextChanged: win.filter = text
                    Keys.onEscapePressed: win.close()
                    Component.onCompleted: forceActiveFocus()
                }

                ListView {
                    id: lv
                    width: parent.width; height: parent.height - s(94); clip: true; spacing: s(4)
                    model: listModel
                    delegate: Rectangle {
                        width: lv.width; height: s(48); radius: s(10)
                        color: win.selectedIndex === index ? Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.16) : "transparent"
                        border.width: win.selectedIndex === index ? 1 : 0; border.color: Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.4)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Row {
                            anchors.fill: parent; anchors.leftMargin: win.s(12); spacing: win.s(10)
                            Rectangle { width: win.s(30); height: win.s(30); anchors.verticalCenter: parent.verticalCenter; radius: width/2; color: Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.25)
                                Text { anchors.centerIn: parent; text: (model.username||"?").charAt(0).toUpperCase(); font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: win.s(13); color: win.accent } }
                            Column { anchors.verticalCenter: parent.verticalCenter
                                Text { text: model.username; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: win.s(13); color: th.text; elide: Text.ElideRight; width: win.s(220) }
                                Text { text: model.uid; font.family: "JetBrains Mono"; font.pixelSize: win.s(9); color: th.subtext0; elide: Text.ElideRight; width: win.s(220) } }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.selectedIndex = index }
                    }
                }
            }

            Rectangle {
                width: parent.width - s(316); height: parent.height; radius: s(14)
                color: Qt.rgba(th.base.r, th.base.g, th.base.b, 0.7)
                border.width: 1; border.color: Qt.rgba(th.text.r, th.text.g, th.text.b, 0.06); clip: true

                Flickable {
                    anchors.fill: parent; anchors.margins: win.s(20)
                    contentWidth: width; contentHeight: detailCol.height
                    flickableDirection: Flickable.VerticalFlick; boundsBehavior: Flickable.StopAtBounds; clip: true
                    Column {
                        id: detailCol; width: parent.width; spacing: win.s(12)
                        Text { text: win.currentProfile ? win.currentProfile.username : "Select someone"
                            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: win.s(20); color: th.text }
                        Text { visible: win.currentProfile; text: win.currentProfile ? win.currentProfile.uid : ""
                            font.family: "JetBrains Mono"; font.pixelSize: win.s(10); color: th.subtext0 }
                        Rectangle { width: parent.width; height: 1; color: Qt.rgba(th.text.r, th.text.g, th.text.b, 0.08) }
                        Text { width: parent.width; wrapMode: Text.Wrap; textFormat: Text.MarkdownText
                            text: win.currentProfile ? win.currentProfile.body : "Nobody selected. Click a contact on the left, or type to filter."
                            font.family: "JetBrains Mono"; font.pixelSize: win.s(12); color: th.text }
                    }
                }
            }
        }
        Text { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottomMargin: win.s(8)
            text: "esc / click outside to close"; font.family: "JetBrains Mono"; font.pixelSize: win.s(9); color: th.subtext0 }
    }

    property string filter: ""
    property int selectedIndex: -1
    property var currentProfile: (selectedIndex >= 0 && selectedIndex < filtered.length) ? filtered[selectedIndex] : null
    property var raw: []
    property var filtered: []
    onFilterChanged: rebuild()
    function rebuild() {
        let f = filter.toLowerCase()
        filtered = f ? raw.filter(p => (p.username+p.uid+p.body).toLowerCase().indexOf(f) >= 0) : raw
        listModel.clear()
        for (let p of filtered) listModel.append({ username: p.username, uid: p.uid })
        if (selectedIndex >= filtered.length) selectedIndex = filtered.length > 0 ? 0 : -1
    }
    ListModel { id: listModel }

    Process {
        running: true
        command: ["bash", "-c", "python3 ~/.config/hypr/scripts/quickshell/claude/people.py --json 2>/dev/null || echo '[]'"]
        stdout: StdioCollector { onStreamFinished: {
            try { win.raw = JSON.parse(this.text.trim() || "[]"); win.selectedIndex = win.raw.length ? 0 : -1; win.rebuild() } catch (e) {}
        } }
    }
    Keys.onEscapePressed: win.close()
}
