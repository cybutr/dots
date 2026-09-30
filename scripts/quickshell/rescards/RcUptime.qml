import QtQuick
import "../claude"

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

    readonly property color accent: "#b4befe"
    readonly property color accent2: "#89b4fa"
    readonly property int starTarget: Math.min(40, ((rc.d.days || 0) + 3) * 3)
    property int stars: 0

    implicitHeight: s(138)

    onLiveChanged: if (live) upIn.restart()
    SequentialAnimation {
        id: upIn
        PropertyAction { target: rc; property: "stars"; value: 0 }
        PauseAnimation { duration: 150 }
        NumberAnimation { target: rc; property: "stars"; to: rc.starTarget; duration: 1600; easing.type: Easing.OutQuad }
    }

    RcShell {
        anchors.fill: parent
        bar: rc.bar; theme: rc.theme
        accent: rc.accent
        accent2: rc.accent2
        radius: rc.s(18)
        live: rc.live
        wash: 0.2
        onCloseClicked: rc.dismissRequested()

        Rectangle {
            anchors.fill: parent
            radius: rc.s(18)
            gradient: Gradient {
                GradientStop { position: 0.0; color: rc.theme ? Qt.alpha(rc.theme.crust, 0.45) : "transparent" }
                GradientStop { position: 1.0; color: rc.theme ? Qt.alpha(rc.theme.mantle, 0.1) : "transparent" }
            }
        }

        Item {
            anchors.fill: parent
            anchors.margins: rc.s(4)
            PillBg {
                kind: "stars"
                shown: rc.live
                radius: rc.s(14)
                px: rc.s(1.6)
                count: rc.stars
            }
        }

        Column {
            anchors.left: parent.left; anchors.leftMargin: rc.s(18)
            anchors.right: parent.right; anchors.rightMargin: rc.s(40)
            anchors.top: parent.top; anchors.topMargin: rc.s(11)
            spacing: rc.s(3)

            Rectangle {
                width: upEyebrow.implicitWidth + rc.s(14)
                height: rc.s(17)
                radius: height / 2
                color: Qt.alpha(rc.accent, 0.22)
                border.width: 1; border.color: Qt.alpha(rc.accent, 0.45)
                Text {
                    id: upEyebrow
                    anchors.centerIn: parent
                    text: "UPTIME · SINCE " + String(rc.d.bootStr || "").toUpperCase()
                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(8); font.letterSpacing: rc.s(1)
                    color: rc.accent
                }
            }

            Row {
                spacing: rc.s(8)
                Text {
                    id: upBig
                    text: (rc.d.days || 0) + "d " + String(rc.d.hours || 0).padStart(2, "0") + "h"
                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(30)
                    font.letterSpacing: -rc.s(1)
                    color: rc.theme ? rc.theme.text : "transparent"
                    style: Text.Raised; styleColor: rc.theme ? Qt.alpha(rc.theme.crust, 0.6) : "transparent"
                }
                Text {
                    anchors.baseline: upBig.baseline
                    text: "no sleep"
                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: rc.s(11)
                    color: rc.accent
                }
            }

            Text {
                width: parent.width
                text: rc.d.quip || ""
                elide: Text.ElideRight
                font.family: "JetBrains Mono"; font.italic: true; font.pixelSize: rc.s(11)
                color: rc.theme ? rc.theme.subtext1 : "transparent"
            }
        }

        Rectangle {
            anchors.left: parent.left; anchors.leftMargin: rc.s(18)
            anchors.verticalCenter: upBtns.verticalCenter
            visible: !!rc.d.kernelStale
            width: kText.implicitWidth + rc.s(14); height: rc.s(20); radius: height / 2
            color: Qt.alpha("#fab387", 0.2)
            border.width: 1; border.color: Qt.alpha("#fab387", 0.5)
            Text {
                id: kText
                anchors.centerIn: parent
                text: "󰏗 new kernel waiting"
                font.family: "Iosevka Nerd Font"; font.pixelSize: rc.s(10)
                color: rc.theme ? rc.theme.text : "transparent"
            }
        }

        RcButton {
            id: upBtns
            anchors.right: parent.right; anchors.rightMargin: rc.s(16)
            anchors.bottom: parent.bottom; anchors.bottomMargin: rc.s(11)
            bar: rc.bar; theme: rc.theme; accent: rc.accent
            label: rc.actions.length > 0 ? rc.actions[0].label : ""
            onPrimary: rc.runRequested(rc.actions[0].cmd)
            onLater: rc.dismissRequested()
        }
    }
}
