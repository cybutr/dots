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

    readonly property color accent: "#f9e2af"
    readonly property color accent2: "#fab387"
    readonly property var w: rc.d.weather || ({})
    readonly property var events: rc.d.events || []
    property real rise: 0

    implicitHeight: s(172)

    onLiveChanged: if (live) riseIn.restart()
    SequentialAnimation {
        id: riseIn
        PropertyAction { target: rc; property: "rise"; value: 0 }
        PauseAnimation { duration: 140 }
        NumberAnimation { target: rc; property: "rise"; to: 1; duration: 1100; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
    }

    RcShell {
        anchors.fill: parent
        bar: rc.bar; theme: rc.theme
        accent: rc.accent; accent2: rc.accent2
        radius: rc.s(20)
        live: rc.live
        wash: 0.26
        onCloseClicked: rc.dismissRequested()

        Item {
            id: sunCol
            anchors.left: parent.left; anchors.leftMargin: rc.s(16)
            anchors.top: parent.top; anchors.bottom: parent.bottom
            width: rc.s(112)

            Rectangle {
                anchors.horizontalCenter: sunGlyph.horizontalCenter
                anchors.verticalCenter: sunGlyph.verticalCenter
                width: rc.s(74) * rc.rise; height: width; radius: width / 2
                color: Qt.alpha(rc.accent, 0.18)
            }
            Text {
                id: sunGlyph
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(rc.s(20) + rc.s(24) * (1 - rc.rise))
                opacity: rc.rise
                text: rc.w.icon || "󰖙"
                font.family: "Iosevka Nerd Font"; font.pixelSize: rc.s(46)
                color: rc.accent
            }
            Text {
                id: tempRange
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: sunGlyph.bottom; anchors.topMargin: rc.s(2)
                text: rc.w.min !== undefined && rc.w.min !== "" ? Math.round(rc.w.min) + "–" + Math.round(rc.w.max) + "°" : "—"
                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(20)
                font.letterSpacing: -rc.s(0.6)
                color: rc.theme ? rc.theme.text : "transparent"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: tempRange.bottom
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: rc.w.desc || ""
                elide: Text.ElideRight
                font.family: "JetBrains Mono"; font.pixelSize: rc.s(9)
                color: rc.theme ? rc.theme.subtext0 : "transparent"
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: rc.s(12)
                spacing: rc.s(8)
                visible: !!rc.w.sunrise
                Text { text: "󰖜 " + (rc.w.sunrise || ""); font.family: "Iosevka Nerd Font"; font.pixelSize: rc.s(10); color: rc.accent }
                Text { text: "󰖛 " + (rc.w.sunset || ""); font.family: "Iosevka Nerd Font"; font.pixelSize: rc.s(10); color: rc.accent2 }
            }
        }

        Rectangle {
            anchors.left: sunCol.right; anchors.leftMargin: rc.s(4)
            anchors.top: parent.top; anchors.topMargin: rc.s(18)
            anchors.bottom: parent.bottom; anchors.bottomMargin: rc.s(18)
            width: 1
            color: Qt.alpha(rc.accent, 0.25)
        }

        Column {
            anchors.left: sunCol.right; anchors.leftMargin: rc.s(20)
            anchors.right: parent.right; anchors.rightMargin: rc.s(34)
            anchors.top: parent.top; anchors.topMargin: rc.s(12)
            spacing: rc.s(6)

            Rectangle {
                width: mbEyebrow.implicitWidth + rc.s(14)
                height: rc.s(17)
                radius: height / 2
                color: Qt.alpha(rc.accent, 0.22)
                border.width: 1; border.color: Qt.alpha(rc.accent, 0.45)
                Text {
                    id: mbEyebrow
                    anchors.centerIn: parent
                    text: "MORNING BRIEF · " + String(rc.d.dateStr || "").toUpperCase()
                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(8); font.letterSpacing: rc.s(1)
                    color: rc.accent
                }
            }

            Text {
                width: parent.width
                text: (rc.d.greeting || "Good morning") + "."
                elide: Text.ElideRight
                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(20)
                font.letterSpacing: -rc.s(0.5)
                color: rc.theme ? rc.theme.text : "transparent"
            }

            Flow {
                width: parent.width
                spacing: rc.s(6)
                Repeater {
                    model: rc.events.length
                    delegate: Rectangle {
                        width: evRow.implicitWidth + rc.s(14)
                        height: rc.s(22)
                        radius: rc.s(7)
                        color: Qt.alpha(index === 0 ? rc.accent2 : rc.accent, index === 0 ? 0.26 : 0.12)
                        border.width: 1; border.color: Qt.alpha(index === 0 ? rc.accent2 : rc.accent, 0.4)
                        Row {
                            id: evRow
                            anchors.centerIn: parent
                            spacing: rc.s(6)
                            Text { text: rc.events[index].time; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rc.s(10); color: index === 0 ? rc.accent2 : rc.accent }
                            Text { text: rc.events[index].title; font.family: "JetBrains Mono"; font.pixelSize: rc.s(10); color: rc.theme ? rc.theme.text : "transparent" }
                        }
                    }
                }
                Text {
                    visible: rc.events.length === 0
                    text: "Calendar's clear — the day is yours."
                    font.family: "JetBrains Mono"; font.italic: true; font.pixelSize: rc.s(11)
                    color: rc.theme ? rc.theme.subtext1 : "transparent"
                }
            }
        }

        Row {
            anchors.left: sunCol.right; anchors.leftMargin: rc.s(20)
            anchors.bottom: parent.bottom; anchors.bottomMargin: rc.s(12)
            spacing: rc.s(14)
            Repeater {
                model: [
                    { g: "󰂄", v: (rc.d.battery && rc.d.battery.pct !== "" ? rc.d.battery.pct + "%" : "—") },
                    { g: "󰂚", v: String(rc.d.notifs || 0) },
                    { g: "󰄲", v: String((rc.d.tasks || []).length) + " tasks" }
                ]
                delegate: Row {
                    spacing: rc.s(4)
                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.g; font.family: "Iosevka Nerd Font"; font.pixelSize: rc.s(12); color: rc.accent2 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.v; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: rc.s(10); color: rc.theme ? rc.theme.subtext1 : "transparent" }
                }
            }
        }
    }
}
