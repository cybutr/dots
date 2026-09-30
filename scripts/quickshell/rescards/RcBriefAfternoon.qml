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

    readonly property color accent: "#89dceb"
    readonly property color accent2: "#94e2d5"
    readonly property var remaining: rc.d.left || []
    readonly property var screen: rc.d.screen || ({})
    readonly property var w: rc.d.weather || ({})
    readonly property real dayStartH: 7
    readonly property real dayEndH: 23
    property real nowSec: Date.now() / 1000
    property real grow: 0
    property real pulse: 0

    function frac(ts) {
        let t = new Date(ts * 1000)
        let h = t.getHours() + t.getMinutes() / 60
        return Math.max(0, Math.min(1, (h - rc.dayStartH) / (rc.dayEndH - rc.dayStartH)))
    }
    function until(ts) {
        let m = Math.max(0, Math.round((ts - rc.nowSec) / 60))
        return m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m" : m + "m"
    }

    implicitHeight: s(164)

    onLiveChanged: if (live) { nowSec = Date.now() / 1000; aftIn.restart() }
    NumberAnimation { id: aftIn; target: rc; property: "grow"; from: 0; to: 1; duration: 1200; easing.type: Easing.OutCubic }
    Timer { interval: 30000; repeat: true; running: rc.live; onTriggered: rc.nowSec = Date.now() / 1000 }
    SequentialAnimation on pulse {
        running: rc.live
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 1100; easing.type: Easing.OutCubic }
        NumberAnimation { to: 0; duration: 900; easing.type: Easing.InCubic }
    }

    RcShell {
        anchors.fill: parent
        bar: rc.bar; theme: rc.theme
        accent: rc.accent; accent2: rc.accent2
        radius: rc.s(16)
        live: rc.live
        wash: 0.2
        onCloseClicked: rc.dismissRequested()

        Item {
            id: aftHeadWrap
            anchors.left: parent.left; anchors.leftMargin: rc.s(16)
            anchors.right: parent.right; anchors.rightMargin: rc.s(36)
            anchors.top: parent.top; anchors.topMargin: rc.s(12)
            height: rc.s(20)
        }
        Row {
            id: aftHead
            anchors.left: aftHeadWrap.left
            anchors.verticalCenter: aftHeadWrap.verticalCenter
            spacing: rc.s(10)
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: abEyebrow.implicitWidth + rc.s(14)
                height: rc.s(17)
                radius: rc.s(4)
                color: Qt.alpha(rc.accent, 0.22)
                border.width: 1; border.color: Qt.alpha(rc.accent, 0.45)
                Text {
                    id: abEyebrow
                    anchors.centerIn: parent
                    text: "AFTERNOON · " + Qt.formatTime(new Date(rc.nowSec * 1000), "HH:mm")
                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(8); font.letterSpacing: rc.s(1)
                    color: rc.accent
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, aftHeadWrap.width - x)
                elide: Text.ElideRight
                text: (rc.d.greeting || "Good afternoon") + " · what's left"
                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(14)
                color: rc.theme ? rc.theme.text : "transparent"
            }
        }

        Item {
            id: track
            anchors.left: parent.left; anchors.leftMargin: rc.s(22)
            anchors.right: parent.right; anchors.rightMargin: rc.s(22)
            y: rc.s(58)
            height: rc.s(44)

            Rectangle {
                id: rail
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: rc.s(6); radius: height / 2
                color: rc.theme ? Qt.alpha(rc.theme.text, 0.08) : "transparent"
                Rectangle {
                    height: parent.height; radius: parent.radius
                    width: parent.width * rc.frac(rc.nowSec) * rc.grow
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.alpha(rc.accent2, 0.35) }
                        GradientStop { position: 1.0; color: rc.accent }
                    }
                }
            }

            Repeater {
                model: rc.remaining.length
                delegate: Item {
                    readonly property var ev: rc.remaining[index]
                    x: Math.round(rail.width * rc.frac(ev.start))
                    width: 1; height: track.height
                    opacity: rc.grow
                    Rectangle {
                        anchors.centerIn: parent
                        width: rc.s(10); height: width
                        rotation: 45
                        color: index === 0 ? "#fab387" : rc.accent2
                        border.width: 1; border.color: rc.theme ? rc.theme.crust : "transparent"
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom; anchors.bottomMargin: index % 2 === 0 ? -rc.s(4) : track.height - rc.s(10)
                        text: ev.time + " " + ev.title
                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: rc.s(9)
                        color: index === 0 ? "#fab387" : (rc.theme ? rc.theme.subtext1 : "transparent")
                    }
                }
            }

            Item {
                x: Math.round(rail.width * rc.frac(rc.nowSec) * rc.grow)
                width: 1; height: track.height
                Rectangle {
                    anchors.centerIn: parent
                    width: rc.s(12) + rc.s(10) * rc.pulse; height: width; radius: width / 2
                    color: Qt.alpha(rc.accent, 0.35 * (1 - rc.pulse))
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: rc.s(10); height: width; radius: width / 2
                    color: rc.accent
                    border.width: rc.s(2); border.color: rc.theme ? rc.theme.crust : "transparent"
                }
            }

            Text {
                anchors.left: parent.left; anchors.top: parent.top; anchors.topMargin: -rc.s(4)
                visible: rc.remaining.length === 0
                text: "Nothing else on the calendar. Clear runway."
                font.family: "JetBrains Mono"; font.italic: true; font.pixelSize: rc.s(10)
                color: rc.theme ? rc.theme.subtext1 : "transparent"
            }
        }

        Row {
            id: aftStats
            anchors.left: parent.left; anchors.leftMargin: rc.s(16)
            anchors.right: parent.right; anchors.rightMargin: rc.s(16)
            anchors.bottom: parent.bottom; anchors.bottomMargin: rc.s(12)
            spacing: rc.s(8)
            Repeater {
                model: [
                    { g: "󰔟", l: rc.remaining.length > 0 ? (rc.remaining[0].start > rc.nowSec ? "next · in " + rc.until(rc.remaining[0].start) : "happening now") : "next", v: rc.remaining.length > 0 ? rc.remaining[0].title : "free", c: "#fab387" },
                    { g: "󰍹", l: "screen" + ((rc.screen.apps || []).length > 0 ? " · mostly " + rc.screen.apps[0].name : " so far"), v: rc.screen.total || "0m", c: rc.accent },
                    { g: rc.w.icon || "󰖐", l: "outside" + (rc.w.sunset ? " · sunset " + rc.w.sunset : ""), v: rc.w.temp ? Math.round(rc.w.temp) + "° " + (rc.w.desc || "") : (rc.w.desc || "—"), c: rc.accent2 }
                ]
                delegate: Rectangle {
                    width: (aftStats.width - aftStats.spacing * 2) / 3
                    height: rc.s(38)
                    radius: rc.s(8)
                    color: Qt.alpha(modelData.c, 0.10)
                    border.width: 1; border.color: Qt.alpha(modelData.c, 0.28)
                    Text {
                        id: stG
                        anchors.left: parent.left; anchors.leftMargin: rc.s(8)
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.g
                        font.family: "Iosevka Nerd Font"; font.pixelSize: rc.s(16)
                        color: modelData.c
                    }
                    Column {
                        anchors.left: stG.right; anchors.leftMargin: rc.s(8)
                        anchors.right: parent.right; anchors.rightMargin: rc.s(6)
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            width: parent.width
                            text: modelData.l
                            font.family: "JetBrains Mono"; font.pixelSize: rc.s(8)
                            color: rc.theme ? rc.theme.subtext0 : "transparent"
                        }
                        Text {
                            width: parent.width
                            text: modelData.v
                            elide: Text.ElideRight
                            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(11)
                            color: rc.theme ? rc.theme.text : "transparent"
                        }
                    }
                }
            }
        }
    }
}
