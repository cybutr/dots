import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Screen-recording indicator. Hidden unless a recording is active.
// Watches /tmp/qs_recording.json (written by screenrec-toggle.sh).
// Red pulsing dot + live elapsed timer; click to stop.
Item {
    id: root

    property var bar        // barWindow, for s() scaling + barHeight
    property var theme       // MatugenColors instance

    property bool recording: false
    property double since: 0
    property int now: Math.floor(Date.now() / 1000)

    function s(v) { return bar ? bar.s(v) : v }

    readonly property color recColor: "#f38ba8"   // red — fixed, see hypr/CLAUDE.md
    readonly property int elapsed: recording ? Math.max(0, now - since) : 0
    readonly property string elapsedStr: {
        var m = Math.floor(elapsed / 60)
        var s2 = elapsed % 60
        return (m < 10 ? "0" : "") + m + ":" + (s2 < 10 ? "0" : "") + s2
    }

    Layout.alignment: Qt.AlignVCenter
    Layout.preferredWidth: recording ? (pillRow.width + s(6)) : 0
    Layout.preferredHeight: bar ? bar.barHeight : 48
    implicitHeight: bar ? bar.barHeight : 48
    visible: recording
    clip: true

    Behavior on Layout.preferredWidth { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

    Row {
        id: pillRow
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: root.s(2)
        spacing: root.s(6)

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: root.s(12); height: root.s(12)

            // soft halo
            Rectangle {
                anchors.centerIn: parent
                width: root.s(12); height: root.s(12); radius: width / 2
                color: root.recColor
                opacity: 0.22
                SequentialAnimation on scale {
                    running: root.recording
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.6; to: 1.5; duration: 1100; easing.type: Easing.OutQuad }
                    NumberAnimation { from: 1.5; to: 0.6; duration: 0 }
                }
            }
            // solid dot, breathing
            Rectangle {
                anchors.centerIn: parent
                width: root.s(8); height: root.s(8); radius: width / 2
                color: root.recColor
                SequentialAnimation on opacity {
                    running: root.recording
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.45; duration: 750; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 750; easing.type: Easing.InOutQuad }
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.elapsedStr
            font.family: "JetBrains Mono"; font.pixelSize: root.s(13); font.weight: Font.Bold
            color: root.recColor
        }
    }

    // click to stop
    Process { id: stopper; running: false }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: {
            stopper.command = ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/screenrec-toggle.sh"]
            stopper.running = false; stopper.running = true
        }
    }

    // tooltip
    Rectangle {
        visible: tipArea.containsMouse && root.recording
        anchors.top: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: root.s(6)
        width: tipText.implicitWidth + root.s(18)
        height: tipText.implicitHeight + root.s(10)
        radius: root.s(8)
        color: theme ? theme.mantle : "#181825"
        border.width: 1; border.color: Qt.rgba(root.recColor.r, root.recColor.g, root.recColor.b, 0.6)
        z: 100
        Text {
            id: tipText
            anchors.centerIn: parent
            text: "Recording · click to stop"
            font.family: "JetBrains Mono"; font.pixelSize: root.s(11); font.weight: Font.Bold
            color: theme ? theme.text : "#eee"
        }
    }
    MouseArea { id: tipArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

    // poll state file
    Process {
        id: reader
        command: ["bash", "-c", "cat /tmp/qs_recording.json 2>/dev/null || echo '{}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var txt = this.text.trim()
                if (txt === "") return
                try {
                    var d = JSON.parse(txt)
                    root.recording = d.recording === true
                    root.since = d.since || 0
                } catch (e) { root.recording = false }
            }
        }
    }
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { root.now = Math.floor(Date.now() / 1000); reader.running = true }
    }
}
