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

    readonly property bool urgent: (rc.d.daysLeft || 0) <= 3
    readonly property color accent: urgent ? "#f38ba8" : "#89b4fa"
    readonly property color accent2: urgent ? "#fab387" : "#74c7ec"

    // Fully content-driven — no guessed magic-number offsets, so it can
    // never overlap regardless of scale, device-list length or text wrap.
    implicitHeight: mainCol.implicitHeight + s(13) + s(12) + btnRow.implicitHeight + s(14)

    RcShell {
        anchors.fill: parent
        bar: rc.bar; theme: rc.theme
        accent: rc.accent
        accent2: rc.accent2
        radius: rc.s(18)
        live: rc.live
        wash: 0.22
        onCloseClicked: rc.dismissRequested()

        Rectangle {
            anchors.fill: parent
            radius: rc.s(18)
            gradient: Gradient {
                GradientStop { position: 0.0; color: rc.theme ? Qt.alpha(rc.theme.crust, 0.45) : "transparent" }
                GradientStop { position: 1.0; color: rc.theme ? Qt.alpha(rc.theme.mantle, 0.1) : "transparent" }
            }
        }

        // Small mesh/node motif — a few dots, echoing a VPN mesh, purely
        // decorative. Pinned to the corner so it never competes with content.
        Row {
            anchors.right: parent.right; anchors.rightMargin: rc.s(16)
            anchors.top: parent.top; anchors.topMargin: rc.s(16)
            spacing: rc.s(6)
            opacity: 0.4
            Repeater {
                model: 3
                delegate: Rectangle {
                    width: rc.s(6); height: rc.s(6); radius: rc.s(3)
                    color: rc.accent2
                }
            }
        }

        Column {
            id: mainCol
            anchors.left: parent.left; anchors.leftMargin: rc.s(18)
            anchors.right: parent.right; anchors.rightMargin: rc.s(18)
            anchors.top: parent.top; anchors.topMargin: rc.s(13)
            spacing: rc.s(8)

            Rectangle {
                width: tsEyebrow.implicitWidth + rc.s(14)
                height: rc.s(17)
                radius: height / 2
                color: Qt.alpha(rc.accent, 0.22)
                border.width: 1; border.color: Qt.alpha(rc.accent, 0.45)
                Text {
                    id: tsEyebrow
                    anchors.centerIn: parent
                    text: "TAILSCALE · AUTH KEY"
                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(8); font.letterSpacing: rc.s(1)
                    color: rc.accent
                }
            }

            Column {
                spacing: rc.s(2)
                Row {
                    spacing: rc.s(8)
                    Text {
                        id: bigDays
                        text: (rc.d.daysLeft !== undefined ? rc.d.daysLeft : "?") + "d"
                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(28)
                        font.letterSpacing: -rc.s(1)
                        color: rc.theme ? rc.theme.text : "transparent"
                        style: Text.Raised; styleColor: rc.theme ? Qt.alpha(rc.theme.crust, 0.6) : "transparent"
                    }
                    Text {
                        anchors.baseline: bigDays.baseline
                        text: "until expiry · " + String(rc.d.expiry || "")
                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: rc.s(11)
                        color: rc.accent
                    }
                }
                Text {
                    width: mainCol.width
                    text: rc.urgent ? "re-auth now — devices drop off the tailnet after this" : "re-auth soon to keep every device connected"
                    elide: Text.ElideRight
                    font.family: "JetBrains Mono"; font.italic: true; font.pixelSize: rc.s(11)
                    color: rc.theme ? rc.theme.subtext1 : "transparent"
                }
            }

            Flow {
                width: mainCol.width
                visible: !!rc.d.devices
                spacing: rc.s(6)
                Repeater {
                    model: rc.d.devices || []
                    delegate: Rectangle {
                        height: rc.s(19)
                        width: devTxt.implicitWidth + rc.s(18)
                        radius: height / 2
                        color: modelData.online ? Qt.alpha("#a6e3a1", 0.18) : Qt.alpha(rc.theme ? rc.theme.overlay0 : "#888", 0.18)
                        border.width: 1
                        border.color: modelData.online ? Qt.alpha("#a6e3a1", 0.5) : Qt.alpha(rc.theme ? rc.theme.overlay0 : "#888", 0.4)
                        Text {
                            id: devTxt
                            anchors.centerIn: parent
                            text: (modelData.online ? "● " : "○ ") + modelData.name
                            font.family: "JetBrains Mono"; font.pixelSize: rc.s(9)
                            color: modelData.online ? "#a6e3a1" : (rc.theme ? rc.theme.subtext0 : "#aaa")
                        }
                    }
                }
            }
        }

        Row {
            id: btnRow
            anchors.right: parent.right; anchors.rightMargin: rc.s(16)
            anchors.top: mainCol.bottom; anchors.topMargin: rc.s(12)

            RcButton {
                bar: rc.bar; theme: rc.theme; accent: rc.accent
                label: rc.actions.length > 0 ? rc.actions[0].label : "Open admin console"
                onPrimary: rc.runRequested(rc.actions.length > 0 ? rc.actions[0].cmd : "xdg-open https://login.tailscale.com/admin/machines")
                onLater: rc.dismissRequested()
            }
        }
    }
}
