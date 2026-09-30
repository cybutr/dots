import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window

    property var notifModel: null

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
    readonly property color crust: _theme.crust || "#11111b"

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

    property string insightText: ""
    property bool dndActive: false

    function accentFor(appName) {
        var n = (appName || "").toLowerCase()
        if (n.indexOf("firefox") >= 0 || n.indexOf("vivaldi") >= 0 || n.indexOf("chrome") >= 0) return _theme.blue
        if (n.indexOf("spotify") >= 0 || n.indexOf("music") >= 0) return _theme.green
        if (n.indexOf("discord") >= 0 || n.indexOf("slack") >= 0) return _theme.mauve
        if (n.indexOf("system") >= 0 || n.indexOf("update") >= 0) return _theme.yellow
        if (n.indexOf("error") >= 0 || n.indexOf("fail") >= 0) return _theme.red
        return _theme.peach
    }

    function askAbout(app, summary) {
        var a = (app || "").replace(/'/g, "’")
        var b = (summary || "").replace(/'/g, "’")
        Quickshell.execDetached(["bash", "-c", "echo 'claude:notifications:" + a + " says \"" + b + "\" — what should I do?' > /tmp/qs_widget_state"])
    }

    function sameDay(a, b) {
        var da = new Date(a), db = new Date(b)
        return da.getFullYear() === db.getFullYear() && da.getMonth() === db.getMonth() && da.getDate() === db.getDate()
    }

    function buildGroupsInto(target, arr, hasTs) {
        var i = 0
        while (i < arr.length) {
            var members = [arr[i]]
            var j = i + 1
            while (j < arr.length && arr[j].appName === arr[i].appName) {
                if (hasTs && Math.abs(arr[j - 1].ts - arr[j].ts) > 120000) break
                members.push(arr[j])
                j++
            }
            var rep = members[0]
            target.append({
                appName: rep.appName,
                summary: rep.summary,
                body: rep.body,
                repIdx: rep.idx,
                moreCount: members.length - 1,
                membersJson: JSON.stringify(members),
                expanded: false
            })
            i = j
        }
    }

    function rebuildGrouped() {
        if (!nowModel || !earlierModel || !olderModel) return
        nowModel.clear(); earlierModel.clear(); olderModel.clear()
        if (!notifModel) return

        var now = Date.now()
        var items = []
        for (var i = 0; i < notifModel.count; i++) {
            var it = notifModel.get(i)
            items.push({
                idx: i,
                appName: (it.appName || "System"),
                summary: (it.summary || ""),
                body: (it.body || ""),
                ts: (it.timestamp !== undefined && it.timestamp !== null && it.timestamp !== "") ? Number(it.timestamp) : 0
            })
        }

        var hasTs = false
        for (var k = 0; k < items.length; k++) {
            if (items[k].ts > 0) { hasTs = true; break }
        }
        if (hasTs) items.sort(function(a, b) { return b.ts - a.ts })
        else items.reverse()

        var nowArr = [], earlierArr = [], olderArr = []
        for (var m = 0; m < items.length; m++) {
            var x = items[m]
            if (!hasTs) { nowArr.push(x); continue }
            var age = now - x.ts
            if (age < 600000) nowArr.push(x)
            else if (window.sameDay(now, x.ts)) earlierArr.push(x)
            else olderArr.push(x)
        }

        window.buildGroupsInto(nowModel, nowArr, hasTs)
        window.buildGroupsInto(earlierModel, earlierArr, hasTs)
        window.buildGroupsInto(olderModel, olderArr, hasTs)
    }

    ListModel { id: nowModel }
    ListModel { id: earlierModel }
    ListModel { id: olderModel }

    onNotifModelChanged: window.rebuildGrouped()
    Component.onCompleted: { window.rebuildGrouped(); insightReader.running = true }

    Connections {
        target: window.notifModel
        function onCountChanged() { window.rebuildGrouped() }
    }

    Process {
        id: insightReader
        command: ["bash", "-c", "cat /tmp/qs_notif_insight 2>/dev/null || echo ''"]
        stdout: StdioCollector { onStreamFinished: if (this.text.trim()) window.insightText = this.text.trim() }
    }
    Process {
        id: insightWatcher
        running: true
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "touch /tmp/qs_notif_insight; inotifywait -m -e close_write /tmp/qs_notif_insight 2>/dev/null"]
        stdout: SplitParser { splitMarker: "\n"; onRead: (_) => { insightReader.running = false; insightReader.running = true } }
    }

    Process { id: insightWriter; command: ["bash", "-c", "echo 'claude:notifications:summarize my unread notifications' > /tmp/qs_widget_state"] }

    Process {
        id: dndPoll
        command: ["bash", "-c", "command -v swaync-client >/dev/null && timeout 1 swaync-client -D 2>/dev/null || echo false"]
        stdout: StdioCollector { onStreamFinished: window.dndActive = (this.text.trim() === "true") }
    }
    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: dndPoll.running = true
    }

    component NotifCard: Item {
        id: card
        property string cAppName: "System"
        property string cSummary: ""
        property string cBody: ""
        property int cSourceIndex: -1
        property bool cIsGroup: false

        width: parent ? parent.width : 0
        height: cardRect.height

        HoverHandler { id: cardHov }

        Rectangle {
            anchors.fill: cardRect
            anchors.margins: -window.s(4)
            radius: cardRect.radius + window.s(4)
            color: accentBar.color
            opacity: cardHov.hovered ? 0.16 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }
        }

        Rectangle {
            id: cardRect
            width: parent.width
            height: cardCol.implicitHeight + window.s(20)
            radius: window.s(12)
            color: cardHov.hovered
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
                width: window.s(3)
                height: parent.height - window.s(16)
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                radius: window.s(2)
                color: window.accentFor(card.cAppName)
                opacity: 0.7
            }

            ColumnLayout {
                id: cardCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: window.s(14)
                anchors.rightMargin: window.s(60)
                anchors.topMargin: window.s(10)
                spacing: window.s(3)

                Text {
                    text: card.cAppName || "System"
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(11)
                    font.weight: Font.Medium
                    color: window.overlay1
                    Layout.fillWidth: true
                }

                Text {
                    text: card.cSummary || ""
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(13)
                    font.weight: Font.Bold
                    color: window.text
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    visible: text !== ""
                }

                Text {
                    text: card.cBody || ""
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(12)
                    color: window.subtext0
                    wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    Layout.fillWidth: true
                    visible: text !== ""
                }
            }

            Rectangle {
                id: askDot
                width: window.s(22)
                height: window.s(22)
                radius: window.s(11)
                anchors.right: xBtn.left
                anchors.top: parent.top
                anchors.topMargin: window.s(8)
                anchors.rightMargin: window.s(6)
                visible: cardHov.hovered && !card.cIsGroup
                opacity: (cardHov.hovered && !card.cIsGroup) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
                color: askHov.hovered
                    ? window.mauve
                    : Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.2)
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "?"
                    font.family: "JetBrains Mono"
                    font.weight: Font.Bold
                    font.pixelSize: window.s(11)
                    color: askHov.hovered ? window.crust : window.mauve
                }

                HoverHandler { id: askHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: window.askAbout(card.cAppName, card.cSummary) }
            }

            Rectangle {
                id: xBtn
                width: window.s(22)
                height: window.s(22)
                radius: window.s(11)
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: window.s(8)
                color: xHov.hovered ? window.surface2 : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    font.pixelSize: window.s(10)
                    color: window.subtext0
                }

                HoverHandler { id: xHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: if (window.notifModel && card.cSourceIndex >= 0) window.notifModel.remove(card.cSourceIndex) }
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
                radius: parent.radius
                enabled: false
            }
        }
    }

    component NotifGroup: Item {
        id: grp
        property var ownerModel
        property int rowIndex: 0
        property string gAppName: "System"
        property string gSummary: ""
        property string gBody: ""
        property int gRepIdx: -1
        property int gMoreCount: 0
        property string gMembersJson: "[]"
        property bool gExpanded: false
        property var membersArr: {
            try { return JSON.parse(gMembersJson) } catch (e) { return [] }
        }

        width: parent ? parent.width : 0
        height: grpCol.implicitHeight

        Column {
            id: grpCol
            width: parent.width
            spacing: window.s(8)

            Item {
                id: collapsedWrap
                visible: !grp.gExpanded
                width: parent.width
                height: repCard.height + (grp.gMoreCount > 0 ? window.s(6) : 0)

                Rectangle {
                    visible: grp.gMoreCount > 0
                    z: 0
                    width: repCard.width
                    height: repCard.height
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: window.s(6)
                    scale: 0.94
                    radius: window.s(12)
                    color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.3)
                    border.color: window.surface1
                    border.width: 1
                    opacity: 0.5
                }

                Rectangle {
                    visible: grp.gMoreCount > 0
                    z: 1
                    width: repCard.width
                    height: repCard.height
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: window.s(3)
                    scale: 0.97
                    radius: window.s(12)
                    color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.45)
                    border.color: window.surface1
                    border.width: 1
                    opacity: 0.7
                }

                NotifCard {
                    id: repCard
                    z: 2
                    cAppName: grp.gAppName
                    cSummary: grp.gSummary
                    cBody: grp.gBody
                    cSourceIndex: grp.gRepIdx
                    cIsGroup: grp.gMoreCount > 0
                }

                Rectangle {
                    visible: grp.gMoreCount > 0
                    z: 3
                    anchors.right: repCard.right
                    anchors.bottom: repCard.bottom
                    anchors.margins: window.s(8)
                    height: window.s(20)
                    width: moreTxt.implicitWidth + window.s(16)
                    radius: window.s(10)
                    color: moreMa.containsMouse
                        ? window.mauve
                        : Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.22)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        id: moreTxt
                        anchors.centerIn: parent
                        text: "+" + grp.gMoreCount + " more"
                        font.family: "JetBrains Mono"
                        font.pixelSize: window.s(10)
                        font.weight: Font.Bold
                        color: moreMa.containsMouse ? window.crust : window.mauve
                    }

                    MouseArea {
                        id: moreMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (grp.ownerModel) grp.ownerModel.setProperty(grp.rowIndex, "expanded", true)
                    }
                }
            }

            Column {
                visible: grp.gExpanded
                width: parent.width
                spacing: window.s(8)

                Repeater {
                    model: grp.gExpanded ? grp.membersArr : []
                    delegate: NotifCard {
                        required property var modelData
                        width: parent ? parent.width : 0
                        cAppName: modelData.appName
                        cSummary: modelData.summary
                        cBody: modelData.body
                        cSourceIndex: modelData.idx
                    }
                }

                Rectangle {
                    visible: grp.gMoreCount > 0
                    anchors.right: parent.right
                    height: window.s(20)
                    width: lessTxt.implicitWidth + window.s(16)
                    radius: window.s(10)
                    color: lessMa.containsMouse
                        ? window.surface2
                        : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        id: lessTxt
                        anchors.centerIn: parent
                        text: "Show less"
                        font.family: "JetBrains Mono"
                        font.pixelSize: window.s(10)
                        font.weight: Font.Bold
                        color: window.subtext0
                    }

                    MouseArea {
                        id: lessMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (grp.ownerModel) grp.ownerModel.setProperty(grp.rowIndex, "expanded", false)
                    }
                }
            }
        }
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
                spacing: s(8)

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
                    height: s(28)
                    width: sumTxt.implicitWidth + s(20)
                    radius: s(8)
                    color: sumMa.containsMouse
                        ? Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.28)
                        : Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.16)
                    Behavior on color { ColorAnimation { duration: 150 } }

                    scale: sumMa.pressed ? 0.94 : (sumMa.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                    Text {
                        id: sumTxt
                        anchors.centerIn: parent
                        text: "SUMMARIZE"
                        font.family: "JetBrains Mono"
                        font.pixelSize: s(11)
                        font.weight: Font.Bold
                        color: window.mauve
                    }

                    MouseArea {
                        id: sumMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["bash", "-c", "echo 'claude:notifications:summarize my unread notifications and tell me what needs action' > /tmp/qs_widget_state"])
                    }
                }

                Rectangle {
                    height: s(28)
                    width: dndTxt.implicitWidth + s(20)
                    radius: s(8)
                    color: window.dndActive
                        ? window.mauve
                        : (dndMa.containsMouse ? window.surface2 : window.surface1)
                    Behavior on color { ColorAnimation { duration: 150 } }

                    scale: dndMa.pressed ? 0.94 : (dndMa.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                    Text {
                        id: dndTxt
                        anchors.centerIn: parent
                        text: "DND"
                        font.family: "JetBrains Mono"
                        font.pixelSize: s(11)
                        font.weight: Font.Bold
                        color: window.dndActive ? window.crust : window.subtext0
                    }

                    MouseArea {
                        id: dndMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            window.dndActive = !window.dndActive
                            Quickshell.execDetached(["bash", "-c", "command -v swaync-client >/dev/null && timeout 1 swaync-client -d"])
                            dndPoll.running = true
                        }
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

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: window.insightText ? s(36) : 0
                Layout.leftMargin: s(10)
                Layout.rightMargin: s(10)
                Layout.topMargin: window.insightText ? s(8) : 0
                clip: true
                radius: s(8)
                color: Qt.rgba(_theme.mauve.r, _theme.mauve.g, _theme.mauve.b, 0.09)
                Behavior on Layout.preferredHeight { NumberAnimation { duration: 260; easing.type: Easing.OutExpo } }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: s(3)
                    radius: s(2)
                    color: window.mauve
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: s(14)
                    anchors.rightMargin: s(10)
                    spacing: s(8)

                    Text {
                        text: "✦"
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: s(13)
                        color: window.mauve
                    }

                    Text {
                        text: window.insightText
                        font.family: "JetBrains Mono"
                        font.pixelSize: s(11)
                        color: window.text
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        width: s(24)
                        height: s(24)
                        radius: s(12)
                        color: arrowMa.containsMouse
                            ? window.mauve
                            : Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.2)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "→"
                            font.pixelSize: s(13)
                            font.weight: Font.Bold
                            color: arrowMa.containsMouse ? window.crust : window.mauve
                        }

                        MouseArea {
                            id: arrowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { insightWriter.running = false; insightWriter.running = true }
                        }
                    }
                }
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

            Flickable {
                id: scroller
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: s(10)
                Layout.bottomMargin: s(10)
                Layout.leftMargin: s(10)
                Layout.rightMargin: s(10)
                visible: window.notifModel && window.notifModel.count > 0
                contentWidth: width
                contentHeight: sectionsCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: s(3)
                        radius: s(2)
                        color: window.surface2
                        opacity: 0.6
                    }
                }

                Column {
                    id: sectionsCol
                    width: scroller.width - s(6)
                    spacing: s(14)

                    Column {
                        width: parent.width
                        spacing: s(8)
                        visible: nowModel.count > 0

                        Text {
                            text: "NOW"
                            font.family: "JetBrains Mono"
                            font.pixelSize: s(10)
                            font.weight: Font.Bold
                            color: window.subtext0
                            leftPadding: s(6)
                            bottomPadding: s(4)
                        }

                        Repeater {
                            model: nowModel
                            delegate: NotifGroup {
                                required property int index
                                required property var model
                                ownerModel: nowModel
                                rowIndex: index
                                gAppName: model.appName
                                gSummary: model.summary
                                gBody: model.body
                                gRepIdx: model.repIdx
                                gMoreCount: model.moreCount
                                gMembersJson: model.membersJson
                                gExpanded: model.expanded
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: s(8)
                        visible: earlierModel.count > 0

                        Text {
                            text: "EARLIER TODAY"
                            font.family: "JetBrains Mono"
                            font.pixelSize: s(10)
                            font.weight: Font.Bold
                            color: window.subtext0
                            leftPadding: s(6)
                            bottomPadding: s(4)
                        }

                        Repeater {
                            model: earlierModel
                            delegate: NotifGroup {
                                required property int index
                                required property var model
                                ownerModel: earlierModel
                                rowIndex: index
                                gAppName: model.appName
                                gSummary: model.summary
                                gBody: model.body
                                gRepIdx: model.repIdx
                                gMoreCount: model.moreCount
                                gMembersJson: model.membersJson
                                gExpanded: model.expanded
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: s(8)
                        visible: olderModel.count > 0

                        Text {
                            text: "OLDER"
                            font.family: "JetBrains Mono"
                            font.pixelSize: s(10)
                            font.weight: Font.Bold
                            color: window.subtext0
                            leftPadding: s(6)
                            bottomPadding: s(4)
                        }

                        Repeater {
                            model: olderModel
                            delegate: NotifGroup {
                                required property int index
                                required property var model
                                ownerModel: olderModel
                                rowIndex: index
                                gAppName: model.appName
                                gSummary: model.summary
                                gBody: model.body
                                gRepIdx: model.repIdx
                                gMoreCount: model.moreCount
                                gMembersJson: model.membersJson
                                gExpanded: model.expanded
                            }
                        }
                    }
                }
            }
        }
    }
}
