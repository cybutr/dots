import QtQuick
import Quickshell.Widgets

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

    readonly property real health: Math.max(0, Math.min(100, rc.d.healthPct || 0))
    readonly property color tone: rc.health >= 80 ? "#a6e3a1" : (rc.health >= 60 ? "#f9e2af" : "#f38ba8")
    readonly property color tone2: rc.health >= 80 ? "#94e2d5" : (rc.health >= 60 ? "#fab387" : "#eba0ac")
    property real fill: 0

    implicitHeight: s(156)

    onLiveChanged: if (live) batIn.restart()
    SequentialAnimation {
        id: batIn
        PropertyAction { target: rc; property: "fill"; value: 0 }
        PauseAnimation { duration: 180 }
        NumberAnimation { target: rc; property: "fill"; to: 1; duration: 1300; easing.type: Easing.OutCubic }
    }

    function stat(i) {
        if (i === 0) return { v: rc.d.cycles >= 0 ? String(rc.d.cycles) : "—", l: "cycles" }
        if (i === 1) return { v: (rc.d.full || 0) + "/" + (rc.d.design || 0), l: (rc.d.unit || "Wh") + " full / design" }
        if (i === 2) return { v: (rc.d.wearPct || 0) + "%", l: "wear" }
        let dl = rc.d.deltaPct
        return dl === null || dl === undefined
            ? { v: (rc.d.limitPct || 100) + "%", l: "charge cap" }
            : { v: (dl > 0 ? "+" : "") + dl + "%", l: "since last check" }
    }

    RcShell {
        anchors.fill: parent
        bar: rc.bar; theme: rc.theme
        accent: rc.tone
        accent2: rc.tone2
        radius: rc.s(18)
        live: rc.live
        wash: 0.18
        onCloseClicked: rc.dismissRequested()

        Row {
            anchors.left: parent.left; anchors.leftMargin: rc.s(16)
            anchors.top: parent.top; anchors.topMargin: rc.s(11)
            spacing: rc.s(8)
            Rectangle {
                width: batEyebrow.implicitWidth + rc.s(14)
                height: rc.s(17)
                radius: height / 2
                color: Qt.alpha(rc.tone, 0.22)
                border.width: 1; border.color: Qt.alpha(rc.tone, 0.45)
                Text {
                    id: batEyebrow
                    anchors.centerIn: parent
                    text: "BATTERY HEALTH"
                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(8); font.letterSpacing: rc.s(1)
                    color: rc.tone
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: [rc.d.model || "", rc.d.tech || ""].filter(x => x !== "").join(" · ")
                font.family: "JetBrains Mono"; font.pixelSize: rc.s(9)
                color: rc.theme ? rc.theme.subtext0 : "transparent"
            }
        }

        Item {
            id: cell
            anchors.left: parent.left; anchors.leftMargin: rc.s(16)
            anchors.right: parent.right; anchors.rightMargin: rc.s(16) + nub.width
            y: rc.s(38)
            height: rc.s(52)

            ClippingRectangle {
                id: cellBody
                anchors.fill: parent
                radius: rc.s(12)
                color: rc.theme ? Qt.alpha(rc.theme.text, 0.04) : "transparent"

                Repeater {
                    model: 18
                    delegate: Rectangle {
                        readonly property real lostX: cellBody.width * rc.health / 100
                        x: lostX + index * rc.s(9) - rc.s(4)
                        y: -rc.s(10)
                        width: rc.s(2); height: cellBody.height + rc.s(20)
                        rotation: 28
                        visible: x < cellBody.width
                        color: rc.theme ? Qt.alpha(rc.theme.text, 0.05 * rc.fill) : "transparent"
                    }
                }

                Rectangle {
                    id: juice
                    x: rc.s(4); y: rc.s(4)
                    height: parent.height - rc.s(8)
                    width: Math.max(0, (parent.width - rc.s(8)) * rc.health / 100 * rc.fill)
                    radius: rc.s(9)
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.alpha(rc.tone2, 0.85) }
                        GradientStop { position: 1.0; color: rc.tone }
                    }
                    Rectangle {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: rc.s(3)
                        height: parent.height * 0.32
                        radius: rc.s(6)
                        color: rc.theme ? Qt.alpha(rc.theme.text, 0.18) : "transparent"
                    }
                }

                Repeater {
                    model: 9
                    delegate: Rectangle {
                        x: cellBody.width * (index + 1) / 10
                        y: rc.s(8); width: 1; height: cellBody.height - rc.s(16)
                        color: rc.theme ? Qt.alpha(rc.theme.crust, 0.35) : "transparent"
                    }
                }

            }

            Rectangle {
                anchors.fill: parent
                radius: rc.s(12)
                color: "transparent"
                border.width: rc.s(2)
                border.color: rc.theme ? Qt.alpha(rc.theme.text, 0.28) : "transparent"
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: Math.round(Math.max(rc.s(12), Math.min(juice.width - width - rc.s(10), cellBody.width - width - rc.s(12))))
                text: (rc.health * rc.fill).toFixed(1) + "%"
                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(24)
                font.letterSpacing: -rc.s(0.8)
                color: rc.theme ? rc.theme.crust : "transparent"
            }

            MouseArea {
                anchors.fill: parent
                enabled: rc.actions.length > 0
                cursorShape: Qt.PointingHandCursor
                onClicked: rc.runRequested(rc.actions[0].cmd)
            }

            Rectangle {
                id: nub
                anchors.left: parent.right; anchors.leftMargin: rc.s(2)
                anchors.verticalCenter: parent.verticalCenter
                width: rc.s(6); height: parent.height * 0.4
                radius: rc.s(3)
                color: rc.theme ? Qt.alpha(rc.theme.text, 0.28) : "transparent"
            }
        }

        Row {
            id: batStats
            anchors.left: cell.left; anchors.right: parent.right; anchors.rightMargin: rc.s(16)
            anchors.bottom: parent.bottom; anchors.bottomMargin: rc.s(12)
            Repeater {
                model: 4
                delegate: Column {
                    width: batStats.width / 4
                    spacing: rc.s(1)
                    readonly property var st: rc.stat(index)
                    Text {
                        text: parent.st.v
                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(14)
                        color: index === 3 && (rc.d.deltaPct || 0) < 0 ? rc.tone : (rc.theme ? rc.theme.text : "transparent")
                    }
                    Text {
                        width: parent.width - rc.s(6)
                        text: parent.st.l
                        elide: Text.ElideRight
                        font.family: "JetBrains Mono"; font.pixelSize: rc.s(9)
                        color: rc.theme ? rc.theme.subtext0 : "transparent"
                    }
                }
            }
        }
    }
}
