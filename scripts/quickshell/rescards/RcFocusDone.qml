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

    readonly property color accent: "#cba6f7"
    readonly property color accent2: "#f5c2e7"
    readonly property var apps: rc.d.apps || []
    readonly property var appColors: ["#cba6f7", "#f5c2e7", "#89dceb", "#fab387"]
    property real sweep: 0

    implicitHeight: s(150)

    onLiveChanged: if (live) fdIn.restart()
    onSweepChanged: ring.requestPaint()
    onAppsChanged: ring.requestPaint()
    SequentialAnimation {
        id: fdIn
        PropertyAction { target: rc; property: "sweep"; value: 0 }
        PauseAnimation { duration: 160 }
        NumberAnimation { target: rc; property: "sweep"; to: 1; duration: 1400; easing.type: Easing.OutCubic }
    }

    RcShell {
        anchors.fill: parent
        bar: rc.bar; theme: rc.theme
        accent: rc.accent
        accent2: rc.accent2
        radius: rc.s(18)
        live: rc.live
        onCloseClicked: rc.dismissRequested()

        Canvas {
            id: ring
            anchors.left: parent.left; anchors.leftMargin: rc.s(18)
            anchors.verticalCenter: parent.verticalCenter
            width: rc.s(104); height: width
            onPaint: {
                let ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                if (!rc.theme) return
                let cx = width / 2, cy = height / 2
                let lw = rc.s(9)
                let r = width / 2 - lw / 2 - rc.s(2)
                let start = -Math.PI / 2
                let full = Math.PI * 2 * rc.sweep
                let tr = rc.theme.text
                ctx.lineCap = "round"
                ctx.lineWidth = lw
                ctx.strokeStyle = Qt.rgba(tr.r, tr.g, tr.b, 0.08)
                ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke()
                let total = rc.d.trackedSecs || 0
                let a = start
                let gap = 0.06
                if (total <= 0 || rc.apps.length === 0) {
                    let c = rc.accent
                    ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.9)
                    ctx.beginPath(); ctx.arc(cx, cy, r, start, start + full); ctx.stroke()
                    return
                }
                for (let i = 0; i < rc.apps.length && i < 4; i++) {
                    let span = Math.PI * 2 * rc.apps[i].secs / total
                    let end = Math.min(start + full, a + span)
                    if (end - a > gap) {
                        let c = Qt.lighter(rc.appColors[i], 1.0)
                        ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.92)
                        ctx.beginPath(); ctx.arc(cx, cy, r, a + gap / 2, end - gap / 2); ctx.stroke()
                    }
                    a += span
                    if (a >= start + full) break
                }
                if (a < start + full) {
                    let c = rc.theme.overlay0
                    ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.5)
                    ctx.beginPath(); ctx.arc(cx, cy, r, a + gap / 2, start + full); ctx.stroke()
                }
            }
            Column {
                anchors.centerIn: parent
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: rc.d.label || ""
                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(18)
                    font.letterSpacing: -rc.s(0.6)
                    color: rc.theme ? rc.theme.text : "transparent"
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "focused"
                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: rc.s(8)
                    color: rc.theme ? rc.theme.subtext0 : "transparent"
                }
            }
        }

        Column {
            anchors.left: ring.right; anchors.leftMargin: rc.s(20)
            anchors.right: parent.right; anchors.rightMargin: rc.s(36)
            anchors.top: parent.top; anchors.topMargin: rc.s(11)
            spacing: rc.s(5)

            Rectangle {
                width: fdEyebrow.implicitWidth + rc.s(14)
                height: rc.s(17)
                radius: height / 2
                color: Qt.alpha(rc.accent, 0.22)
                border.width: 1; border.color: Qt.alpha(rc.accent, 0.45)
                Text {
                    id: fdEyebrow
                    anchors.centerIn: parent
                    text: "SESSION DONE · #" + (rc.d.sessionsToday || 1) + " TODAY"
                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(8); font.letterSpacing: rc.s(1)
                    color: rc.accent
                }
            }

            Text {
                width: parent.width
                text: rc.apps.length > 0 ? "Mostly " + rc.apps[0].name : "Nice work."
                elide: Text.ElideRight
                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(17)
                color: rc.theme ? rc.theme.text : "transparent"
            }

            Flow {
                width: parent.width
                spacing: rc.s(10)
                Repeater {
                    model: Math.min(3, rc.apps.length)
                    delegate: Row {
                        spacing: rc.s(4)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: rc.s(7); height: width; radius: width / 2
                            color: rc.appColors[index]
                        }
                        Text {
                            text: rc.apps[index].name + " " + Math.round(rc.apps[index].pct) + "%"
                            font.family: "JetBrains Mono"; font.pixelSize: rc.s(10)
                            color: rc.theme ? rc.theme.subtext1 : "transparent"
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: "focus today " + (rc.d.focusToday || "0m") + " · screen " + (rc.d.screenToday || "0m")
                elide: Text.ElideRight
                font.family: "JetBrains Mono"; font.pixelSize: rc.s(10)
                color: rc.theme ? rc.theme.subtext0 : "transparent"
            }
        }

        RcButton {
            anchors.right: parent.right; anchors.rightMargin: rc.s(16)
            anchors.bottom: parent.bottom; anchors.bottomMargin: rc.s(11)
            bar: rc.bar; theme: rc.theme; accent: rc.accent
            label: rc.actions.length > 0 ? rc.actions[0].label : ""
            onPrimary: rc.runRequested(rc.actions[0].cmd)
            onLater: rc.dismissRequested()
        }
    }
}
