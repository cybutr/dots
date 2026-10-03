import QtQuick
import Quickshell
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
    readonly property color addCol: "#a6e3a1"
    readonly property color delCol: "#f38ba8"
    readonly property color forceCol: "#fab387"

    readonly property var commits: rc.d.commits || []
    readonly property int shown: Math.min(4, commits.length)
    readonly property int count: rc.d.count !== undefined ? rc.d.count : commits.length
    readonly property int more: Math.max(0, count - shown)
    readonly property int ins: rc.d.ins || 0
    readonly property int dels: rc.d.del || 0
    readonly property int files: rc.d.files || 0
    readonly property bool hasStat: ins + dels > 0
    readonly property string badge: rc.d.deleted ? "DELETED" : rc.d.forced ? "FORCE" : rc.d.newBranch ? "NEW BRANCH" : ""
    readonly property color badgeCol: rc.d.deleted ? delCol : rc.d.forced ? forceCol : accent2
    readonly property string remoteLabel: String(rc.d.remote || "origin") + (rc.d.remoteBranch && rc.d.remoteBranch !== rc.d.branch ? "/" + rc.d.remoteBranch : "")
    property real grow: 0
    property string copied: ""

    implicitHeight: s(14) + mainCol.implicitHeight + (footer.height > 0 ? s(12) + footer.height : 0) + s(14)

    onLiveChanged: if (live) growIn.restart()
    SequentialAnimation {
        id: growIn
        PropertyAction { target: rc; property: "grow"; value: 0 }
        PauseAnimation { duration: 120 }
        NumberAnimation { target: rc; property: "grow"; to: 1; duration: 260 + 170 * rc.shown; easing.type: Easing.OutCubic }
    }

    function rowT(i) {
        const n = rc.shown
        return Math.max(0, Math.min(1, rc.grow * (n + 0.6) - (n - 1 - i)))
    }

    Timer { id: copiedReset; interval: 1400; onTriggered: rc.copied = "" }

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

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top; anchors.topMargin: rc.s(16)
            anchors.bottom: parent.bottom; anchors.bottomMargin: rc.s(16)
            width: rc.s(3); radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: rc.accent }
                GradientStop { position: 1.0; color: Qt.alpha(rc.accent2, 0.2) }
            }
        }

        Column {
            id: mainCol
            anchors.left: parent.left; anchors.leftMargin: rc.s(18)
            anchors.right: parent.right; anchors.rightMargin: rc.s(18)
            anchors.top: parent.top; anchors.topMargin: rc.s(14)
            spacing: rc.s(9)

            Row {
                spacing: rc.s(6)
                Rectangle {
                    width: gEyebrow.implicitWidth + rc.s(14)
                    height: rc.s(17)
                    radius: height / 2
                    color: Qt.alpha(rc.accent, 0.22)
                    border.width: 1; border.color: Qt.alpha(rc.accent, 0.45)
                    Text {
                        id: gEyebrow
                        anchors.centerIn: parent
                        text: "󰊢  PUSHED · " + String(rc.d.repo || "?").toUpperCase()
                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(8); font.letterSpacing: rc.s(1)
                        color: rc.accent
                    }
                }
                Rectangle {
                    visible: rc.badge !== ""
                    width: gBadge.implicitWidth + rc.s(14)
                    height: rc.s(17)
                    radius: height / 2
                    color: Qt.alpha(rc.badgeCol, 0.22)
                    border.width: 1; border.color: Qt.alpha(rc.badgeCol, 0.5)
                    Text {
                        id: gBadge
                        anchors.centerIn: parent
                        text: rc.badge
                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(8); font.letterSpacing: rc.s(1)
                        color: rc.badgeCol
                    }
                }
            }

            Item {
                width: mainCol.width
                height: Math.max(branchRow.implicitHeight, countCol.implicitHeight)

                Row {
                    id: branchRow
                    anchors.left: parent.left
                    anchors.right: countCol.left; anchors.rightMargin: rc.s(12)
                    spacing: rc.s(8)
                    Text {
                        id: branchTxt
                        width: Math.min(implicitWidth, branchRow.width * 0.55)
                        text: String(rc.d.branch || "?")
                        elide: Text.ElideRight
                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(22)
                        font.letterSpacing: -rc.s(0.6)
                        font.strikeout: !!rc.d.deleted
                        color: rc.theme ? rc.theme.text : "transparent"
                        style: Text.Raised; styleColor: rc.theme ? Qt.alpha(rc.theme.crust, 0.6) : "transparent"
                    }
                    Text {
                        anchors.baseline: branchTxt.baseline
                        text: "󰁔"
                        font.family: "Iosevka Nerd Font"; font.pixelSize: rc.s(15)
                        color: rc.accent
                    }
                    Text {
                        anchors.baseline: branchTxt.baseline
                        width: Math.max(0, branchRow.width - branchTxt.width - rc.s(40))
                        text: rc.remoteLabel
                        elide: Text.ElideRight
                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: rc.s(13)
                        color: rc.accent2
                    }
                }

                Column {
                    id: countCol
                    visible: rc.count > 0
                    width: visible ? implicitWidth : 0
                    anchors.right: parent.right; anchors.rightMargin: rc.s(10)
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        anchors.right: parent.right
                        text: String(rc.count)
                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(20)
                        font.letterSpacing: -rc.s(0.6)
                        color: rc.accent
                    }
                    Text {
                        anchors.right: parent.right
                        text: rc.count === 1 ? "COMMIT" : "COMMITS"
                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(7); font.letterSpacing: rc.s(1)
                        color: rc.theme ? rc.theme.subtext0 : "transparent"
                    }
                }
            }

            Item {
                id: graph
                visible: rc.shown > 0
                width: mainCol.width
                height: visible ? graphCol.implicitHeight : 0
                readonly property real lane: rc.s(9)

                Rectangle {
                    readonly property real top0: rc.s(11)
                    readonly property real span: Math.max(0, (rc.shown - 1) * (rc.s(22) + rc.s(3)) + (rc.more > 0 ? rc.s(22) : 0))
                    x: graph.lane - width / 2
                    width: rc.s(2); radius: width / 2
                    height: span * rc.grow
                    y: top0 + span - height
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: rc.accent }
                        GradientStop { position: 1.0; color: Qt.alpha(rc.accent2, 0.25) }
                    }
                }

                Column {
                    id: graphCol
                    width: parent.width
                    spacing: rc.s(3)

                    Repeater {
                        model: rc.shown
                        delegate: Item {
                            id: cRow
                            required property int index
                            readonly property var c: rc.commits[index]
                            readonly property bool head: index === 0
                            readonly property real t: rc.rowT(index)
                            width: graphCol.width
                            height: rc.s(22)

                            Rectangle {
                                visible: cRow.head && rc.live
                                x: graph.lane - width / 2; y: cRow.height / 2 - height / 2
                                width: rc.s(12); height: width; radius: width / 2
                                color: "transparent"
                                border.width: rc.s(1.5); border.color: rc.accent
                                SequentialAnimation on scale {
                                    running: cRow.head && rc.live
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1; to: 2.3; duration: 1700; easing.type: Easing.OutCubic }
                                    PauseAnimation { duration: 500 }
                                }
                                opacity: Math.max(0, (2.3 - scale) / 1.3) * 0.7 * cRow.t
                            }

                            Rectangle {
                                x: graph.lane - width / 2; y: cRow.height / 2 - height / 2
                                width: cRow.head ? rc.s(12) : rc.s(9); height: width
                                radius: cRow.c.m ? rc.s(2) : width / 2
                                rotation: cRow.c.m ? 45 : 0
                                scale: cRow.t
                                color: cRow.head ? rc.accent : (rc.bar ? rc.bar.cardFill : "transparent")
                                border.width: cRow.head ? 0 : rc.s(2)
                                border.color: cRow.c.m ? rc.accent2 : rc.accent
                            }

                            Item {
                                anchors.left: parent.left; anchors.leftMargin: graph.lane * 2 + rc.s(8)
                                anchors.right: parent.right
                                height: parent.height
                                opacity: cRow.t
                                transform: Translate { x: rc.s(10) * (1 - cRow.t) }

                                Rectangle {
                                    id: hashChip
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: hashTxt.implicitWidth + rc.s(10)
                                    height: rc.s(16); radius: rc.s(5)
                                    color: hashMa.containsMouse ? Qt.alpha(rc.accent, 0.3) : Qt.alpha(cRow.head ? rc.accent : rc.accent2, cRow.head ? 0.18 : 0.08)
                                    border.width: 1; border.color: Qt.alpha(cRow.head ? rc.accent : rc.accent2, cRow.head ? 0.4 : 0.2)
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Text {
                                        id: hashTxt
                                        anchors.centerIn: parent
                                        text: rc.copied === cRow.c.h ? "copied" : cRow.c.h
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: rc.s(9)
                                        color: cRow.head ? rc.accent : rc.accent2
                                    }
                                    MouseArea {
                                        id: hashMa
                                        anchors.fill: parent
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Quickshell.execDetached(["wl-copy", cRow.c.h])
                                            rc.copied = cRow.c.h
                                            copiedReset.restart()
                                        }
                                    }
                                }

                                Text {
                                    anchors.left: hashChip.right; anchors.leftMargin: rc.s(8)
                                    anchors.right: ageTxt.left; anchors.rightMargin: rc.s(8)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: cRow.c.s || ""
                                    elide: Text.ElideRight
                                    font.family: "JetBrains Mono"; font.weight: cRow.head ? Font.Bold : Font.Normal; font.pixelSize: rc.s(11)
                                    color: rc.theme ? (cRow.head ? rc.theme.text : rc.theme.subtext1) : "transparent"
                                }

                                Text {
                                    id: ageTxt
                                    anchors.right: parent.right; anchors.rightMargin: rc.s(2)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: cRow.c.t || ""
                                    font.family: "JetBrains Mono"; font.pixelSize: rc.s(9)
                                    color: rc.theme ? rc.theme.subtext0 : "transparent"
                                }
                            }
                        }
                    }

                    Item {
                        visible: rc.more > 0
                        width: graphCol.width
                        height: visible ? rc.s(16) : 0
                        opacity: rc.grow
                        Rectangle {
                            x: graph.lane - width / 2; anchors.verticalCenter: parent.verticalCenter
                            width: rc.s(5); height: width; radius: width / 2
                            color: Qt.alpha(rc.accent2, 0.5)
                        }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: graph.lane * 2 + rc.s(8)
                            anchors.verticalCenter: parent.verticalCenter
                            text: "+" + rc.more + " more"
                            font.family: "JetBrains Mono"; font.italic: true; font.pixelSize: rc.s(10)
                            color: rc.theme ? rc.theme.subtext0 : "transparent"
                        }
                    }
                }
            }
        }

        Item {
            id: footer
            anchors.left: parent.left; anchors.leftMargin: rc.s(18)
            anchors.right: parent.right; anchors.rightMargin: rc.s(16)
            anchors.top: mainCol.bottom; anchors.topMargin: rc.s(12)
            height: statRow.visible || btn.visible ? Math.max(statRow.implicitHeight, btn.implicitHeight) : 0

            Row {
                id: statRow
                visible: rc.hasStat || rc.files > 0
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: rc.s(8)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: rc.files + (rc.files === 1 ? " file" : " files")
                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: rc.s(10)
                    color: rc.theme ? rc.theme.subtext1 : "transparent"
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "+" + rc.ins
                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(10)
                    color: rc.addCol
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "−" + rc.dels
                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(10)
                    color: rc.delCol
                }
                Row {
                    id: statBlocks
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: rc.s(2)
                    readonly property int adds: !rc.hasStat ? 0 : Math.max(rc.ins > 0 ? 1 : 0, Math.min(rc.dels > 0 ? 4 : 5, Math.round(5 * rc.ins / (rc.ins + rc.dels))))
                    Repeater {
                        model: 5
                        delegate: Rectangle {
                            required property int index
                            width: rc.s(8); height: rc.s(8); radius: rc.s(2)
                            readonly property bool lit: rc.grow * 5 > index
                            color: !rc.hasStat ? Qt.alpha(rc.theme ? rc.theme.overlay0 : "#888", 0.4)
                                : index < statBlocks.adds ? rc.addCol : rc.delCol
                            opacity: lit ? 1 : 0.15
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                        }
                    }
                }
            }

            RcButton {
                id: btn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: rc.actions.length > 0
                bar: rc.bar; theme: rc.theme; accent: rc.accent
                label: rc.actions.length > 0 ? rc.actions[0].label : ""
                onPrimary: rc.runRequested(rc.actions[0].cmd)
                onLater: rc.dismissRequested()
            }
        }
    }
}
