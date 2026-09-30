import QtQuick

Item {
    id: rc

    property var bar
    property var theme
    property var d: ({})
    property var actions: []
    property bool live: false
    signal dismissRequested()
    signal runRequested(string cmd)

    function s(v) { return rc.bar ? rc.bar.s(v) : v }

    readonly property color accent: "#fab387"
    readonly property color accent2: "#f9e2af"
    property real nowSec: Date.now() / 1000
    readonly property real secsLeft: Math.max(0, (rc.d.start || 0) - rc.nowSec)
    readonly property int minsLeft: Math.ceil(rc.secsLeft / 60)
    readonly property bool started: rc.secsLeft <= 0
    property real intro: 0

    implicitHeight: s(132)

    onLiveChanged: if (live) { nowSec = Date.now() / 1000; intro = 0; calIn.restart() }
    NumberAnimation { id: calIn; target: rc; property: "intro"; from: 0; to: 1; duration: 700; easing.type: Easing.OutCubic }
    Timer { interval: 1000; repeat: true; running: rc.live; onTriggered: rc.nowSec = Date.now() / 1000 }

    RcShell {
        id: shell
        anchors.fill: parent
        bar: rc.bar; theme: rc.theme
        accent: rc.accent
        accent2: rc.accent2
        radius: rc.s(18)
        live: rc.live
        onCloseClicked: rc.dismissRequested()

        Rectangle {
            x: rc.s(10); y: rc.s(12)
            width: rc.s(4); height: (parent.height - rc.s(24)) * rc.intro
            radius: width / 2
            color: rc.accent
        }

        Column {
            id: calLeft
            anchors.left: parent.left; anchors.leftMargin: rc.s(24)
            anchors.right: calCount.left; anchors.rightMargin: rc.s(12)
            anchors.top: parent.top; anchors.topMargin: rc.s(11)
            spacing: rc.s(4)

            Rectangle {
                width: calEyebrow.implicitWidth + rc.s(14)
                height: rc.s(17)
                radius: height / 2
                color: Qt.alpha(rc.accent, 0.22)
                border.width: 1; border.color: Qt.alpha(rc.accent, 0.45)
                Text {
                    id: calEyebrow
                    anchors.centerIn: parent
                    text: (rc.started ? "HAPPENING NOW" : "UP NEXT") + (rc.d.calendar && String(rc.d.calendar).indexOf("@") < 0 ? " · " + String(rc.d.calendar).toUpperCase() : "")
                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(8); font.letterSpacing: rc.s(1)
                    color: rc.accent
                }
            }

            Text {
                width: parent.width
                text: rc.d.title || ""
                elide: Text.ElideRight
                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(19)
                font.letterSpacing: -rc.s(0.4)
                color: rc.theme ? rc.theme.text : "transparent"
            }

            Row {
                width: parent.width
                spacing: rc.s(6)
                Text { anchors.verticalCenter: parent.verticalCenter; text: "󰥔"; font.family: "Iosevka Nerd Font"; font.pixelSize: rc.s(12); color: rc.accent }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(rc.d.time || "").replace(" - ", " – ")
                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: rc.s(11)
                    color: rc.theme ? rc.theme.subtext1 : "transparent"
                }
                Text { visible: !!rc.d.room; anchors.verticalCenter: parent.verticalCenter; text: "󰍎"; font.family: "Iosevka Nerd Font"; font.pixelSize: rc.s(12); color: rc.accent }
                Text {
                    visible: !!rc.d.room
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - x)
                    text: rc.d.room || ""
                    elide: Text.ElideRight
                    font.family: "JetBrains Mono"; font.pixelSize: rc.s(11)
                    color: rc.theme ? rc.theme.subtext1 : "transparent"
                }
            }
        }

        Column {
            id: calCount
            anchors.right: parent.right; anchors.rightMargin: rc.s(36)
            anchors.top: parent.top; anchors.topMargin: rc.s(14)
            width: rc.s(64)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: rc.started ? "now" : (rc.minsLeft > 99 ? String(Math.round(rc.minsLeft / 60)) : String(rc.minsLeft))
                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(rc.started ? 22 : 32)
                font.letterSpacing: -rc.s(1)
                color: rc.accent
            }
            Text {
                visible: !rc.started
                anchors.horizontalCenter: parent.horizontalCenter
                text: rc.minsLeft > 99 ? "hours" : (rc.minsLeft === 1 ? "minute" : "minutes")
                font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: rc.s(9)
                color: rc.theme ? rc.theme.subtext0 : "transparent"
            }
        }

        Rectangle {
            id: calTrack
            anchors.left: calLeft.left; anchors.right: parent.right; anchors.rightMargin: rc.s(16)
            y: rc.s(88)
            height: rc.s(3); radius: height / 2
            color: rc.theme ? Qt.alpha(rc.theme.text, 0.08) : "transparent"
            Rectangle {
                height: parent.height; radius: parent.radius
                width: parent.width * rc.intro * Math.max(0, Math.min(1, 1 - rc.secsLeft / 900))
                color: rc.accent
                Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
            }
        }

        Text {
            anchors.left: calLeft.left
            anchors.right: calBtns.left; anchors.rightMargin: rc.s(10)
            anchors.verticalCenter: calBtns.verticalCenter
            visible: !!rc.d.next
            text: "then " + (rc.d.next || "") + (rc.d.nextTime ? " · " + rc.d.nextTime : "")
            elide: Text.ElideRight
            font.family: "JetBrains Mono"; font.pixelSize: rc.s(10)
            color: rc.theme ? rc.theme.subtext0 : "transparent"
        }

        RcButton {
            id: calBtns
            anchors.right: parent.right; anchors.rightMargin: rc.s(16)
            anchors.bottom: parent.bottom; anchors.bottomMargin: rc.s(11)
            bar: rc.bar; theme: rc.theme; accent: rc.accent
            label: rc.actions.length > 0 ? rc.actions[0].label : ""
            onPrimary: rc.runRequested(rc.actions[0].cmd)
            onLater: rc.dismissRequested()
        }
    }
}
