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

    readonly property color accent: "#89b4fa"
    readonly property color accent2: "#f5c2e7"
    readonly property color moon: "#f9e2af"
    readonly property var tw: rc.d.tomorrow || ({})
    readonly property var te: rc.d.tomorrowEvents || []
    readonly property var screen: rc.d.screen || ({})
    readonly property var apps: rc.screen.apps || []
    readonly property var appColors: ["#89b4fa", "#f5c2e7", "#b4befe"]
    property real glow: 0
    property real fill: 0

    implicitHeight: s(176)

    onLiveChanged: if (live) nightIn.restart()
    SequentialAnimation {
        id: nightIn
        PropertyAction { target: rc; property: "fill"; value: 0 }
        PauseAnimation { duration: 200 }
        NumberAnimation { target: rc; property: "fill"; to: 1; duration: 1400; easing.type: Easing.OutCubic }
    }
    SequentialAnimation on glow {
        running: rc.live
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 3200; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 3200; easing.type: Easing.InOutSine }
    }

    RcShell {
        anchors.fill: parent
        bar: rc.bar; theme: rc.theme
        accent: rc.accent; accent2: rc.accent2
        radius: rc.s(22)
        live: rc.live
        wash: 0.16
        onCloseClicked: rc.dismissRequested()

        Rectangle {
            anchors.fill: parent
            radius: rc.s(22)
            gradient: Gradient {
                GradientStop { position: 0.0; color: rc.theme ? Qt.alpha(rc.theme.crust, 0.55) : "transparent" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        Repeater {
            model: 14
            delegate: Rectangle {
                readonly property real rx: (Math.sin(index * 127.1 + 3.7) * 43758.5453) % 1
                readonly property real ry: (Math.sin(index * 311.7 + 1.3) * 12543.1234) % 1
                x: Math.round(rc.s(120) + Math.abs(rx) * (rc.width - rc.s(160)))
                y: Math.round(rc.s(8) + Math.abs(ry) * rc.s(40))
                width: rc.s(index % 3 === 0 ? 2 : 1.4); height: width; radius: width / 2
                color: "#cdd6f4"
                opacity: 0.25 + 0.4 * Math.abs(Math.sin(rc.glow * 3.14 + index))
            }
        }

        Item {
            id: moonCol
            anchors.left: parent.left; anchors.leftMargin: rc.s(18)
            anchors.top: parent.top; anchors.topMargin: rc.s(18)
            width: rc.s(78); height: width
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * (0.85 + 0.15 * rc.glow); height: width; radius: width / 2
                color: Qt.alpha(rc.moon, 0.08 + 0.06 * rc.glow)
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.62; height: width; radius: width / 2
                color: Qt.alpha(rc.moon, 0.10)
            }
            Text {
                anchors.centerIn: parent
                text: "󰽥"
                font.family: "Iosevka Nerd Font"; font.pixelSize: rc.s(44)
                color: rc.moon
            }
        }

        Column {
            anchors.left: moonCol.right; anchors.leftMargin: rc.s(16)
            anchors.right: parent.right; anchors.rightMargin: rc.s(34)
            anchors.top: parent.top; anchors.topMargin: rc.s(14)
            spacing: rc.s(5)

            Text {
                text: "NIGHT BRIEF"
                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(9); font.letterSpacing: rc.s(3)
                color: rc.accent
            }
            Text {
                width: parent.width
                text: (rc.d.greeting || "Good evening") + "."
                elide: Text.ElideRight
                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(19)
                color: rc.theme ? rc.theme.text : "transparent"
            }
            Row {
                width: parent.width
                spacing: rc.s(6)
                Text { anchors.verticalCenter: parent.verticalCenter; text: "tomorrow"; font.family: "JetBrains Mono"; font.italic: true; font.pixelSize: rc.s(10); color: rc.accent2 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - x - tomW.width - rc.s(6))
                    text: rc.te.length > 0 ? (rc.te[0].time ? rc.te[0].time + " · " : "") + rc.te[0].title : "a clear morning"
                    elide: Text.ElideRight
                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: rc.s(11)
                    color: rc.theme ? rc.theme.text : "transparent"
                }
                Text {
                    id: tomW
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!rc.tw.icon
                    text: (rc.tw.icon || "") + " " + (rc.tw.min !== undefined && rc.tw.min !== "" ? Math.round(rc.tw.min) + "–" + Math.round(rc.tw.max) + "°" : "")
                    font.family: "Iosevka Nerd Font"; font.pixelSize: rc.s(11)
                    color: rc.theme ? rc.theme.subtext1 : "transparent"
                }
            }
        }

        Column {
            anchors.left: parent.left; anchors.leftMargin: rc.s(18)
            anchors.right: parent.right; anchors.rightMargin: rc.s(18)
            anchors.bottom: parent.bottom; anchors.bottomMargin: rc.s(14)
            spacing: rc.s(6)

            Row {
                width: parent.width
                spacing: rc.s(8)
                Text { text: "on screen today"; font.family: "JetBrains Mono"; font.pixelSize: rc.s(9); color: rc.theme ? rc.theme.subtext0 : "transparent"; anchors.baseline: scrTot.baseline }
                Text { id: scrTot; text: rc.screen.total || "0m"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(15); color: rc.theme ? rc.theme.text : "transparent" }
                Text {
                    anchors.baseline: scrTot.baseline
                    text: (rc.d.focus && rc.d.focus.count > 0 ? "· " + rc.d.focus.count + " focus sessions (" + rc.d.focus.total + ") " : "") + "· up " + (rc.d.uptimeDays || 0) + "d"
                    font.family: "JetBrains Mono"; font.pixelSize: rc.s(9)
                    color: rc.theme ? rc.theme.subtext0 : "transparent"
                }
            }

            Rectangle {
                id: screenBar
                width: parent.width
                height: rc.s(8); radius: height / 2
                color: rc.theme ? Qt.alpha(rc.theme.text, 0.07) : "transparent"
                Row {
                    anchors.fill: parent
                    spacing: rc.s(2)
                    Repeater {
                        model: Math.min(3, rc.apps.length)
                        delegate: Rectangle {
                            height: screenBar.height; radius: height / 2
                            width: Math.max(0, screenBar.width * rc.apps[index].pct / 100 * rc.fill - rc.s(2))
                            color: rc.appColors[index]
                        }
                    }
                }
            }

            Row {
                spacing: rc.s(12)
                Repeater {
                    model: Math.min(3, rc.apps.length)
                    delegate: Row {
                        spacing: rc.s(4)
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: rc.s(6); height: width; radius: width / 2; color: rc.appColors[index] }
                        Text {
                            text: rc.apps[index].name + " " + rc.apps[index].pct + "%"
                            font.family: "JetBrains Mono"; font.pixelSize: rc.s(9)
                            color: rc.theme ? rc.theme.subtext1 : "transparent"
                        }
                    }
                }
            }
        }
    }
}
