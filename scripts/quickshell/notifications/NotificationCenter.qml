import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../"

Item {
    id: window

    property var notifModel: null
    property var liveNotifs: ({})

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val) }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0 || "#6c7086"
    readonly property color overlay1: _theme.overlay1 || "#7f849c"
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color mauve: _theme.mauve || "#cba6f7"

    property bool noNotifs: !notifModel || notifModel.count === 0

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: 360; duration: 18000; loops: Animation.Infinite; running: true
    }

    property real introPhase: 0
    NumberAnimation on introPhase {
        id: introAnim
        from: 0; to: 1; duration: 450; easing.type: Easing.OutExpo; running: true
    }

    Rectangle {
        anchors.fill: parent
        radius: s(16)
        color: window.base
        border.color: window.surface1
        border.width: 1
        clip: true
        opacity: window.introPhase
        transform: Translate { y: (1 - window.introPhase) * s(24) }

        Rectangle {
            width: window.s(280); height: window.s(280); radius: width / 2
            color: Qt.rgba(_theme.mauve.r, _theme.mauve.g, _theme.mauve.b, 0.06)
            x: parent.width * 0.12 + Math.cos(window.globalOrbitAngle * Math.PI / 180) * window.s(40)
            y: parent.height * 0.18 + Math.sin(window.globalOrbitAngle * Math.PI / 180) * window.s(40)
        }

        Rectangle {
            width: window.s(280); height: window.s(280); radius: width / 2
            color: Qt.rgba(_theme.peach.r, _theme.peach.g, _theme.peach.b, 0.04)
            x: parent.width * 0.6 + Math.sin(window.globalOrbitAngle * Math.PI / 180) * window.s(40)
            y: parent.height * 0.55 + Math.cos(window.globalOrbitAngle * Math.PI / 180) * window.s(40)
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: s(56)
                Layout.leftMargin: s(20)
                Layout.rightMargin: s(14)
                spacing: s(10)

                Text {
                    text: "Notifications"
                    font.family: "JetBrains Mono"
                    font.pixelSize: s(15)
                    font.weight: Font.Bold
                    color: window.text
                    Layout.fillWidth: true
                }

                Rectangle {
                    visible: window.notifModel && window.notifModel.count > 0
                    width: badge.implicitWidth + s(14)
                    height: s(22)
                    radius: s(11)
                    color: window.surface1

                    Text {
                        id: badge
                        anchors.centerIn: parent
                        text: window.notifModel ? window.notifModel.count : "0"
                        font.family: "JetBrains Mono"
                        font.pixelSize: s(11)
                        font.weight: Font.Bold
                        color: window.subtext0
                    }
                }

                Rectangle {
                    visible: window.notifModel && window.notifModel.count > 0
                    width: s(72)
                    height: s(28)
                    radius: s(8)
                    color: clearMa.containsMouse ? window.surface1 : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }

                    scale: clearMa.pressed ? 0.94 : (clearMa.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -s(4)
                        radius: parent.radius + s(4)
                        z: -1
                        color: window.mauve
                        opacity: clearMa.containsMouse ? 0.16 : 0
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "Clear all"
                        font.family: "JetBrains Mono"
                        font.pixelSize: s(12)
                        color: window.subtext0
                    }

                    MouseArea {
                        id: clearMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (window.notifModel) window.notifModel.clear()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: window.surface0
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !window.notifModel || window.notifModel.count === 0

                Column {
                    anchors.centerIn: parent
                    spacing: s(14)

                    Text {
                        id: emptyIcon
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ""
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: s(36)
                        color: window.surface2
                    }

                    SequentialAnimation {
                        running: window.noNotifs
                        loops: Animation.Infinite
                        NumberAnimation { target: emptyIcon; property: "scale"; to: 1.08; duration: 1800; easing.type: Easing.InOutSine }
                        NumberAnimation { target: emptyIcon; property: "scale"; to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No notifications"
                        font.family: "JetBrains Mono"
                        font.pixelSize: s(13)
                        color: window.overlay0
                    }
                }
            }

            ListView {
                id: notifList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: s(10)
                Layout.bottomMargin: s(10)
                Layout.leftMargin: s(10)
                Layout.rightMargin: s(10)
                visible: window.notifModel && window.notifModel.count > 0
                model: window.notifModel
                spacing: s(8)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                add: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 350; easing.type: Easing.OutExpo }
                        NumberAnimation { property: "x"; from: -s(30); to: 0; duration: 350; easing.type: Easing.OutExpo }
                    }
                }
                remove: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; to: 0; duration: 220; easing.type: Easing.OutExpo }
                        NumberAnimation { property: "x"; to: s(30); duration: 220; easing.type: Easing.OutExpo }
                    }
                }
                displaced: Transition {
                    NumberAnimation { properties: "x,y"; duration: 300; easing.type: Easing.OutExpo }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: s(3)
                        radius: s(2)
                        color: window.surface2
                        opacity: 0.6
                    }
                }

                delegate: Item {
                    width: ListView.view.width
                    height: cardRect.height

                    HoverHandler { id: cardHov }

                    Rectangle {
                        anchors.fill: cardRect
                        anchors.margins: -s(4)
                        radius: cardRect.radius + s(4)
                        color: accentBar.color
                        opacity: cardHov.hovered ? 0.16 : 0
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                    }

                    Rectangle {
                        id: cardRect
                        width: parent.width
                        height: cardCol.implicitHeight + s(20)
                        radius: s(12)
                        color: cardMa.containsMouse
                            ? Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.9)
                            : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.55)
                        border.color: window.surface1
                        border.width: 1
                        clip: true
                        Behavior on color { ColorAnimation { duration: 150 } }

                        scale: cardHov.hovered ? 1.012 : 1.0
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

                        Rectangle {
                            anchors { top: parent.top; left: parent.left; right: parent.right }
                            height: parent.height * 0.4
                            radius: parent.radius
                            color: Qt.rgba(1, 1, 1, 0.055)
                        }

                        Rectangle {
                            id: accentBar
                            width: s(3)
                            height: parent.height - s(16)
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            radius: s(2)
                            color: {
                                var n = (model.appName || "").toLowerCase()
                                if (n.indexOf("firefox") >= 0 || n.indexOf("vivaldi") >= 0 || n.indexOf("chrome") >= 0) return _theme.blue
                                if (n.indexOf("spotify") >= 0 || n.indexOf("music") >= 0) return _theme.green
                                if (n.indexOf("discord") >= 0 || n.indexOf("slack") >= 0) return _theme.mauve
                                if (n.indexOf("system") >= 0 || n.indexOf("update") >= 0) return _theme.yellow
                                if (n.indexOf("error") >= 0 || n.indexOf("fail") >= 0) return _theme.red
                                return _theme.peach
                            }
                            opacity: 0.7
                        }

                        ColumnLayout {
                            id: cardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: s(14)
                            anchors.rightMargin: s(36)
                            anchors.topMargin: s(10)
                            spacing: s(3)

                            Text {
                                text: model.appName || "System"
                                font.family: "JetBrains Mono"
                                font.pixelSize: s(11)
                                font.weight: Font.Medium
                                color: window.overlay1
                                Layout.fillWidth: true
                            }

                            Text {
                                text: model.summary || ""
                                font.family: "JetBrains Mono"
                                font.pixelSize: s(13)
                                font.weight: Font.Bold
                                color: window.text
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                                visible: text !== ""
                            }

                            Text {
                                text: model.body || ""
                                font.family: "JetBrains Mono"
                                font.pixelSize: s(12)
                                color: window.subtext0
                                wrapMode: Text.Wrap
                                textFormat: Text.StyledText
                                Layout.fillWidth: true
                                visible: text !== ""
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: s(4)
                                spacing: s(6)
                                visible: {
                                    try { return JSON.parse(model.actionsJson || "[]").length > 0 } catch(e) { return false }
                                }

                                property int delegateIndex: index
                                property int delegateUid: model.uid
                                property var actions: {
                                    try { return JSON.parse(model.actionsJson || "[]") } catch(e) { return [] }
                                }

                                Repeater {
                                    model: parent.actions
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: s(26)
                                        radius: s(6)
                                        property bool isPrimary: index === 0
                                        color: actMa.containsMouse
                                            ? (isPrimary ? window.mauve : window.surface2)
                                            : (isPrimary ? Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.22) : window.surface1)
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.text || "Action"
                                            font.family: "JetBrains Mono"
                                            font.weight: Font.Bold
                                            font.pixelSize: s(11)
                                            color: isPrimary ? (actMa.containsMouse ? window.base : window.mauve) : window.text
                                            elide: Text.ElideRight
                                        }

                                        MouseArea {
                                            id: actMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var uid = parent.parent.delegateUid
                                                var rowIdx = parent.parent.delegateIndex
                                                var live = window.liveNotifs[uid]
                                                if (live && live.actions) {
                                                    for (var i = 0; i < live.actions.length; i++) {
                                                        if (live.actions[i].identifier === modelData.id) {
                                                            live.actions[i].invoke()
                                                            break
                                                        }
                                                    }
                                                }
                                                if (window.notifModel) window.notifModel.remove(rowIdx)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: s(22)
                            height: s(22)
                            radius: s(11)
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: s(8)
                            color: xMa.containsMouse ? window.surface2 : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                font.pixelSize: s(10)
                                color: window.subtext0
                            }

                            MouseArea {
                                id: xMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (window.notifModel) window.notifModel.remove(index)
                            }
                        }

                        MouseArea { id: cardMa; anchors.fill: parent; hoverEnabled: true; z: -1 }

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            radius: parent.radius
                        }
                    }
                }
            }
        }
    }
}
