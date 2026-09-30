import QtQuick
import Quickshell.Widgets

Item {
    id: shell

    property var bar
    property var theme
    property color accent: "#cba6f7"
    property color accent2: accent
    property real radius: 18
    property bool live: false
    property real wash: 0.22
    property real breath: 0
    default property alias content: slot.data
    signal closeClicked()

    function s(v) { return shell.bar ? shell.bar.s(v) : v }

    SequentialAnimation on breath {
        running: shell.live
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 2400; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 2400; easing.type: Easing.InOutSine }
    }

    Repeater {
        model: 5
        delegate: Rectangle {
            readonly property real grow: (index + 1) * shell.s(2.5)
            x: -grow; y: -grow * 0.6
            width: shell.width + grow * 2; height: shell.height + grow * 1.9
            radius: shell.radius + grow
            color: Qt.alpha(shell.accent, 0.05 + 0.03 * shell.breath)
        }
    }

    ClippingRectangle {
        anchors.fill: parent
        radius: shell.radius
        color: shell.bar ? shell.bar.cardFill : "transparent"

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.alpha(shell.accent, shell.wash + 0.05 * shell.breath) }
                GradientStop { position: 0.55; color: Qt.alpha(shell.accent2, shell.wash * 0.35) }
                GradientStop { position: 1.0; color: Qt.alpha(shell.accent2, shell.wash * 0.55) }
            }
        }
        Rectangle {
            width: shell.height * 1.6; height: width; radius: width / 2
            x: shell.width - width * 0.55
            y: -height * 0.55
            color: Qt.alpha(shell.accent2, 0.16 + 0.06 * shell.breath)
        }
        Rectangle {
            width: shell.height * 1.2; height: width; radius: width / 2
            x: -width * 0.45
            y: shell.height - height * 0.4
            color: Qt.alpha(shell.accent, 0.12)
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: shell.theme ? Qt.alpha(shell.theme.text, 0.05) : "transparent" }
                GradientStop { position: 0.4; color: "transparent" }
            }
        }
    }

    Item {
        id: slot
        anchors.fill: parent
    }

    Rectangle {
        anchors.fill: parent
        radius: shell.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(shell.accent, 0.35 + 0.2 * shell.breath)
    }

    Text {
        anchors.top: parent.top; anchors.topMargin: shell.s(10)
        anchors.right: parent.right; anchors.rightMargin: shell.s(12)
        text: "󰅖"
        font.family: "Iosevka Nerd Font"; font.pixelSize: shell.s(14)
        color: closeMa.containsMouse ? shell.accent : (shell.theme ? shell.theme.subtext0 : "transparent")
        scale: closeMa.containsMouse ? 1.2 : 1
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
        MouseArea { id: closeMa; anchors.fill: parent; anchors.margins: -shell.s(5); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: shell.closeClicked() }
    }
}
