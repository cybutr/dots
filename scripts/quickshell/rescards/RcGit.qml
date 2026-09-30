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

    readonly property color accent: "#a6e3a1"
    readonly property color accent2: "#94e2d5"

    implicitHeight: s(96)

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

        // Tiny commit-graph motif — a short line of dots/dashes, purely
        // decorative, echoes the shape of `git log --oneline --graph`.
        Row {
            anchors.left: parent.left; anchors.leftMargin: rc.s(18)
            anchors.top: parent.top; anchors.topMargin: rc.s(13)
            spacing: rc.s(5)
            Repeater {
                model: 5
                delegate: Rectangle {
                    width: index === 4 ? rc.s(14) : rc.s(6)
                    height: rc.s(6); radius: rc.s(3)
                    anchors.verticalCenter: parent.verticalCenter
                    color: index === 4 ? rc.accent : Qt.alpha(rc.accent, 0.35)
                }
            }
        }

        Column {
            anchors.left: parent.left; anchors.leftMargin: rc.s(18)
            anchors.right: parent.right; anchors.rightMargin: rc.s(40)
            anchors.top: parent.top; anchors.topMargin: rc.s(30)
            spacing: rc.s(3)

            Text {
                text: "PUSHED · " + String(rc.d.repo || "?")
                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(9); font.letterSpacing: rc.s(1)
                color: rc.accent
            }

            Row {
                spacing: rc.s(6)
                Text {
                    text: String(rc.d.branch || "?")
                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(20)
                    color: rc.theme ? rc.theme.text : "transparent"
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "→ " + String(rc.d.remote || "origin")
                    font.family: "JetBrains Mono"; font.pixelSize: rc.s(12)
                    color: rc.accent2
                }
            }
        }
    }
}
