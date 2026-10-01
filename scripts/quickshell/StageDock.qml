import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./"

PanelWindow {
    id: root
    color: "transparent"
    WlrLayershell.namespace: "qs-stage"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    anchors { right: true; bottom: true }
    implicitWidth: s(460)
    implicitHeight: s(720)
    mask: Region { item: dock }

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(v) { return scaler.s(v) }

    MatugenColors { id: _theme }
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color subtext1: _theme.subtext1
    readonly property color surface0: _theme.surface0
    readonly property color overlay0: _theme.overlay0

    readonly property string sayPy: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/claude/stage_say.py"
    readonly property string mono: "JetBrains Mono"
    readonly property string glyphs: "Iosevka Nerd Font"

    readonly property color seed: rgb("#fab387")
    readonly property color gateTone: rgb("#f9e2af")
    readonly property color okTone: rgb("#a6e3a1")
    readonly property var kindHex: ({
        info: "#89b4fa", step: "#cba6f7", tip: "#94e2d5", done: "#a6e3a1",
        warn: "#eba0ac", error: "#f38ba8", wait: "#f9e2af"
    })
    readonly property var kindGlyph: ({
        info: 0xF02FC, step: 0xF0142, tip: 0xF0335, done: 0xF05E0,
        warn: 0xF0026, error: 0xF0028, wait: 0xF03E4
    })
    function rgb(h) {
        let n = parseInt(h.slice(1), 16)
        return Qt.rgba((n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255, 1)
    }
    function tone(k) { return rgb(kindHex[k] || kindHex.info) }
    function g(cp) { return String.fromCodePoint(cp) }
    function hm(ts) {
        let d = new Date(ts * 1000)
        return ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
    }

    readonly property int cap: 30
    property real lastRev: 0
    property bool booted: false
    property var acks: ({})
    property real lastActivity: 0
    property real now: Date.now()
    property int holdMs: 9000
    property bool expanded: false
    property int logRev: 0

    ListModel { id: log }

    readonly property string gateId: {
        let c = log.count, a = acks, r = logRev
        for (let i = c - 1; i >= 0; i--) {
            let e = log.get(i)
            if (e.wait && !a[e.eid]) return e.eid
        }
        return ""
    }
    readonly property var gateEntry: {
        let id = gateId, c = log.count, r = logRev
        for (let i = 0; i < c; i++) if (log.get(i).eid === id) return log.get(i)
        return null
    }
    readonly property bool gated: gateId !== ""
    readonly property bool live: now - lastActivity < 15000
    readonly property string mood: gated ? "waiting" : live ? "live" : "quiet"
    readonly property color moodTone: gated ? gateTone : live ? okTone : overlay0

    function autoHold(e) {
        if (e.hold !== undefined && e.hold !== null) return e.hold * 1000
        let n = (e.title || "").length + (e.body || "").length
        return Math.max(7000, Math.min(45000, 5000 + n * 60))
    }

    function ingest(lines) {
        let list = []
        for (let i = 0; i < lines.length; i++) {
            try {
                let e = JSON.parse(lines[i])
                if (e && e.id && e.via !== "resident") list.push(e)
            } catch (err) {}
        }
        list = list.slice(-cap)
        let ids = {}
        for (let i = 0; i < list.length; i++) ids[list[i].id] = true
        for (let i = log.count - 1; i >= 0; i--) if (!ids[log.get(i).eid]) log.remove(i)
        let top = 0, newest = null
        for (let i = 0; i < list.length; i++) {
            let e = list[i]
            let rev = Number(e.rev) || 0
            let row = {
                eid: e.id, title: e.title || "", body: e.body || "", icon: e.icon || "",
                kind: kindHex[e.kind] ? e.kind : (e.wait ? "wait" : "info"),
                stamp: hm(e.ts || Date.now() / 1000), wait: !!e.wait,
                fresh: booted && rev > lastRev, rev: rev
            }
            let j = -1
            for (let k = 0; k < log.count; k++) if (log.get(k).eid === e.id) { j = k; break }
            if (j < 0) log.insert(i, row)
            else {
                if (j !== i) log.move(j, i, 1)
                if (log.get(i).rev !== rev) log.set(i, row)
            }
            if (rev > top) { top = rev; newest = e }
        }
        if (newest && booted && top > lastRev) activity(newest)
        else if (newest && !booted && (Date.now() / 1000 - (newest.ts || 0) < 30 || gated)) activity(newest)
        lastRev = Math.max(lastRev, top)
        logRev++
        booted = true
    }

    function ingestAcks(lines) {
        let out = {}
        for (let i = 0; i < lines.length; i++) {
            let p = lines[i].trim().split(/\s+/)
            if (p.length >= 2) out[p[0]] = p[1]
        }
        acks = out
    }

    function control(lines) {
        try {
            let c = JSON.parse(lines.join(""))
            if (c.op === "collapse") expanded = false
            else if (c.op === "expand") { expanded = true; holdMs = 9000; collapseTimer.restart() }
        } catch (err) {}
    }

    function activity(e) {
        lastActivity = Date.now()
        now = lastActivity
        holdMs = autoHold(e)
        expanded = true
        collapseTimer.restart()
    }

    function proceed() {
        let id = gateId
        if (id === "") return
        let a = Object.assign({}, acks)
        a[id] = "ok"
        acks = a
        Quickshell.execDetached(["python3", sayPy, "ack", id])
        flash.restart()
    }

    Timer {
        id: collapseTimer
        interval: root.holdMs
        running: root.expanded && root.holdMs > 0 && !root.gated && !dockHover.hovered
        onTriggered: root.expanded = false
    }
    Timer {
        interval: 1000; repeat: true
        running: root.expanded || root.live
        onTriggered: root.now = Date.now()
    }

    property var chunk: []
    property string section: ""
    Process {
        running: true
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
            "cd /tmp; touch qs_stage.jsonl qs_stage_ack; " +
            "dump() { echo \"@@$1\"; cat \"$1\" 2>/dev/null; echo; echo '@@end'; }; " +
            "exec 3< <(inotifywait -m -q -e close_write,moved_to --include '/qs_stage(\\.jsonl|_ack|_ctl)$' --format '%f' /tmp); " +
            "sleep 0.3; dump qs_stage_ack; dump qs_stage.jsonl; " +
            "while read -r f <&3; do dump \"$f\"; done"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (line === "@@end") {
                    let lines = root.chunk.filter(l => l.trim() !== "")
                    if (root.section === "qs_stage.jsonl") root.ingest(lines)
                    else if (root.section === "qs_stage_ack") root.ingestAcks(lines)
                    else if (root.section === "qs_stage_ctl") root.control(lines)
                    root.chunk = []
                    root.section = ""
                } else if (line.startsWith("@@")) {
                    root.section = line.slice(2)
                    root.chunk = []
                } else root.chunk.push(line)
            }
        }
    }

    readonly property real dotSize: s(40)
    readonly property real fullW: s(400)
    readonly property real pad: s(14)
    readonly property real headH: s(58)
    readonly property real logCap: s(380)
    readonly property real logH: log.count > 0 ? Math.min(logCol.implicitHeight, logCap) : s(46)
    readonly property real gateH: gated ? gateCard.implicitHeight + s(10) : 0
    readonly property real fullH: headH + logH + gateH + pad
    property real fullHs: fullH
    Behavior on fullHs { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    property real morph: expanded ? 1 : 0
    Behavior on morph { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
    property real breath: 0
    SequentialAnimation on breath {
        running: root.gated && !root.expanded
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 700; easing.type: Easing.InOutSine }
    }
    property real flashV: 0
    NumberAnimation { id: flash; target: root; property: "flashV"; from: 1; to: 0; duration: 520; easing.type: Easing.OutCubic }

    component Caps: Text {
        font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(9); font.letterSpacing: root.s(1.5)
        font.capitalization: Font.AllUppercase
        color: Qt.alpha(root.subtext0, 0.8)
    }
    component Tag: Rectangle {
        property string label: ""
        property color tone: root.subtext0
        property bool strong: false
        height: root.s(18)
        width: tagText.implicitWidth + root.s(12)
        radius: root.s(5)
        color: strong ? Qt.alpha(tone, 0.9) : "transparent"
        border.width: 1; border.color: Qt.alpha(tone, strong ? 0 : 0.45)
        Caps {
            id: tagText
            anchors.centerIn: parent
            text: parent.label
            font.pixelSize: root.s(8)
            color: parent.strong ? root.crust : parent.tone
        }
    }

    Rectangle {
        id: dock
        anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.rightMargin: root.s(18); anchors.bottomMargin: root.s(18)
        width: root.dotSize + (root.fullW - root.dotSize) * root.morph
        height: root.dotSize + (root.fullHs - root.dotSize) * root.morph
        radius: root.dotSize / 2 + (root.s(16) - root.dotSize / 2) * root.morph
        color: root.mantle
        border.width: 1
        border.color: root.gated ? Qt.alpha(root.gateTone, 0.35 + 0.35 * root.breath) : Qt.alpha(root.seed, 0.16 + 0.14 * root.morph)
        Behavior on border.color { ColorAnimation { duration: 220 } }
        clip: true

        HoverHandler { id: dockHover }

        Item {
            id: idle
            anchors.fill: parent
            opacity: Math.max(0, 1 - root.morph * 2.5)
            visible: opacity > 0
            readonly property color t: root.gated ? root.gateTone : root.seed
            Rectangle {
                anchors.centerIn: parent
                width: root.s(30); height: width; radius: width / 2
                color: Qt.alpha(idle.t, 0.07 + 0.08 * root.breath)
            }
            Rectangle {
                anchors.centerIn: parent
                width: root.s(20); height: width; radius: width / 2
                color: Qt.alpha(idle.t, 0.16 + 0.14 * root.breath)
            }
            Rectangle {
                anchors.centerIn: parent
                width: root.s(9); height: width; radius: width / 2
                color: idle.t
            }
            MouseArea {
                anchors.fill: parent
                enabled: root.morph < 0.5
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.expanded = true; root.holdMs = 9000; collapseTimer.restart() }
            }
        }

        Item {
            id: panel
            anchors.right: parent.right; anchors.bottom: parent.bottom
            width: root.fullW; height: root.fullHs
            opacity: Math.max(0, (root.morph - 0.35) / 0.65)
            visible: opacity > 0

            Row {
                id: strip
                anchors.top: parent.top
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: root.s(16); anchors.rightMargin: root.s(16)
                height: root.s(3)
                spacing: root.s(2)
                readonly property int n: Math.max(1, log.count)
                readonly property real unit: (width - spacing * (n - 1)) / (n + (log.count > 0 ? 5 : 0))
                Rectangle {
                    visible: log.count === 0
                    width: strip.width; height: strip.height; radius: height / 2
                    color: Qt.alpha(root.seed, 0.35)
                }
                Repeater {
                    model: log
                    delegate: Rectangle {
                        required property int index
                        required property string kind
                        readonly property bool hot: index === log.count - 1
                        height: strip.height
                        width: strip.unit * (hot ? 6 : 1)
                        radius: height / 2
                        color: Qt.alpha(root.tone(kind), hot ? 1 : 0.5)
                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Rectangle {
                            anchors.top: parent.top
                            width: parent.width; height: root.s(14)
                            visible: parent.hot
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.alpha(root.tone(kind), 0.28) }
                                GradientStop { position: 1.0; color: Qt.alpha(root.tone(kind), 0) }
                            }
                        }
                    }
                }
            }

            Item {
                id: head
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: root.pad; anchors.rightMargin: root.s(12); anchors.topMargin: root.s(14)
                height: root.s(32)

                Rectangle {
                    id: mark
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    width: root.s(32); height: width; radius: root.s(9)
                    color: Qt.alpha(root.seed, 0.14)
                    border.width: 1; border.color: Qt.alpha(root.seed, 0.4)
                    Text {
                        anchors.centerIn: parent
                        text: root.g(0xF0674)
                        font.family: root.glyphs; font.pixelSize: root.s(17)
                        color: root.seed
                    }
                }
                Column {
                    anchors.left: mark.right; anchors.leftMargin: root.s(10)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.s(2)
                    Text {
                        text: "STAGE"
                        font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(13); font.letterSpacing: root.s(2.4)
                        color: root.text
                    }
                    Caps {
                        text: root.gated ? "paused for you" : root.live ? "claude is narrating" : log.count > 0 && root.logRev >= 0 ? "last at " + log.get(log.count - 1).stamp : "nothing yet"
                        color: Qt.alpha(root.moodTone, 0.85)
                    }
                }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: root.s(8)
                    Tag {
                        anchors.verticalCenter: parent.verticalCenter
                        label: root.mood
                        tone: root.moodTone
                        strong: root.mood !== "quiet"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ("0" + log.count).slice(-2)
                        font.family: root.mono; font.weight: Font.Bold; font.pixelSize: root.s(10)
                        color: Qt.alpha(root.subtext0, 0.7)
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.s(24); height: width; radius: root.s(7)
                        color: closeArea.containsMouse ? Qt.alpha(root.text, 0.1) : "transparent"
                        border.width: 1; border.color: Qt.alpha(root.text, 0.12)
                        Text {
                            anchors.centerIn: parent
                            text: root.g(0xF0140)
                            font.family: root.glyphs; font.pixelSize: root.s(14)
                            color: root.subtext0
                        }
                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.expanded = false
                        }
                    }
                }
            }

            Caps {
                visible: log.count === 0
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.headH + root.s(14)
                text: "waiting for narration"
                color: Qt.alpha(root.subtext0, 0.5)
            }

            Flickable {
                id: flick
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: root.s(8); anchors.rightMargin: root.s(8)
                y: root.headH
                height: root.logH
                contentWidth: width
                contentHeight: logCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                property bool stick: true
                onMovementEnded: stick = contentY >= contentHeight - height - root.s(6)
                onContentHeightChanged: if (stick) contentY = Math.max(0, contentHeight - height)
                onHeightChanged: if (stick) contentY = Math.max(0, contentHeight - height)

                Column {
                    id: logCol
                    width: flick.width
                    spacing: root.s(2)
                    Repeater {
                        model: log
                        delegate: Item {
                            id: row
                            required property int index
                            required property string eid
                            required property string title
                            required property string body
                            required property string icon
                            required property string kind
                            required property string stamp
                            required property bool wait
                            required property bool fresh
                            readonly property color t: root.tone(kind)
                            readonly property bool newest: index === log.count - 1
                            readonly property string ackState: wait ? (root.acks[eid] || "") : ""
                            property int typed: 0
                            readonly property bool typing: typed < body.length
                            width: logCol.width
                            height: rowCol.implicitHeight + root.s(16)
                            opacity: newest ? 1 : 0.5 + 0.4 * Math.pow((index + 1) / log.count, 1.6)
                            Component.onCompleted: typed = fresh ? 0 : body.length

                            Timer {
                                interval: 16; repeat: true
                                running: row.typing
                                onTriggered: row.typed = Math.min(row.body.length, row.typed + Math.max(1, Math.ceil((row.body.length - row.typed) / 40)))
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: root.s(10)
                                color: Qt.alpha(row.t, row.newest ? 0.07 : 0)
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top; anchors.topMargin: root.s(9)
                                width: root.s(3); height: Math.min(parent.height - root.s(18), root.s(28))
                                radius: width / 2
                                color: row.t
                                opacity: row.newest ? 1 : 0.45
                            }
                            Text {
                                id: rowNum
                                anchors.left: parent.left; anchors.leftMargin: root.s(10)
                                anchors.top: parent.top; anchors.topMargin: root.s(15)
                                width: root.s(18)
                                text: ("0" + (row.index + 1)).slice(-2)
                                font.family: root.mono; font.weight: Font.Bold; font.pixelSize: root.s(9)
                                color: Qt.alpha(row.t, row.newest ? 0.85 : 0.5)
                            }
                            Rectangle {
                                id: tile
                                anchors.left: rowNum.right; anchors.leftMargin: root.s(2)
                                anchors.top: parent.top; anchors.topMargin: root.s(8)
                                width: root.s(26); height: width; radius: root.s(7)
                                color: Qt.alpha(row.t, row.newest ? 0.2 : 0.1)
                                border.width: 1; border.color: Qt.alpha(row.t, row.newest ? 0.4 : 0.15)
                                Text {
                                    anchors.centerIn: parent
                                    text: row.icon !== "" ? row.icon : root.g(root.kindGlyph[row.kind] || root.kindGlyph.info)
                                    font.family: root.glyphs; font.pixelSize: root.s(14)
                                    color: row.t
                                }
                            }
                            Column {
                                id: rowCol
                                anchors.left: tile.right; anchors.leftMargin: root.s(10)
                                anchors.right: parent.right; anchors.rightMargin: root.s(10)
                                anchors.top: parent.top; anchors.topMargin: root.s(8)
                                spacing: root.s(3)
                                Item {
                                    width: parent.width
                                    height: Math.max(titleText.implicitHeight, meta.height)
                                    Text {
                                        id: titleText
                                        anchors.left: parent.left; anchors.right: meta.left; anchors.rightMargin: root.s(8)
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: row.title !== "" ? row.title : row.kind
                                        font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(12)
                                        font.capitalization: row.title !== "" ? Font.MixedCase : Font.AllUppercase
                                        font.letterSpacing: row.title !== "" ? 0 : root.s(1.4)
                                        color: row.title !== "" ? root.text : Qt.alpha(row.t, 0.85)
                                        elide: Text.ElideRight
                                    }
                                    Row {
                                        id: meta
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        spacing: root.s(6)
                                        Tag {
                                            visible: row.wait
                                            anchors.verticalCenter: parent.verticalCenter
                                            label: row.ackState === "ok" ? "continued" : row.ackState === "expired" ? "timed out" : row.ackState === "cancel" ? "skipped" : "waiting"
                                            tone: row.ackState === "ok" ? root.okTone : row.ackState === "" ? root.gateTone : root.overlay0
                                            strong: row.ackState === ""
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: row.stamp
                                            font.family: root.mono; font.weight: Font.Bold; font.pixelSize: root.s(9)
                                            color: Qt.alpha(root.subtext0, 0.6)
                                        }
                                    }
                                }
                                Text {
                                    width: parent.width
                                    visible: row.body !== ""
                                    textFormat: Text.PlainText
                                    text: row.body.substring(0, row.typed) + (row.typing ? "▌" : "")
                                    wrapMode: Text.Wrap
                                    lineHeight: 1.15
                                    font.family: root.mono; font.weight: Font.Medium; font.pixelSize: root.s(11)
                                    color: row.newest ? root.subtext1 : root.subtext0
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: gateCard
                visible: root.gated
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.leftMargin: root.s(10); anchors.rightMargin: root.s(10); anchors.bottomMargin: root.s(10)
                implicitHeight: gateCol.implicitHeight + root.s(26)
                height: implicitHeight
                radius: root.s(12)
                color: Qt.alpha(root.gateTone, 0.06)
                border.width: 1
                border.color: Qt.alpha(root.gateTone, 0.5)
                clip: true

                Canvas {
                    anchors.fill: parent
                    property color tint: root.gateTone
                    onTintChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        let c = getContext("2d")
                        c.reset()
                        let step = root.s(12), r = Math.max(0.6, root.s(0.9))
                        c.fillStyle = tint
                        for (let x = step / 2; x < width; x += step)
                            for (let y = step / 2; y < height; y += step) {
                                c.globalAlpha = 0.06 + 0.12 * Math.pow(1 - y / height, 2)
                                c.fillRect(x - r, y - r, r * 2, r * 2)
                            }
                    }
                }
                Rectangle {
                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    anchors.topMargin: root.s(12); anchors.bottomMargin: root.s(12)
                    width: root.s(4); radius: width / 2
                    color: root.gateTone
                }
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: root.okTone
                    opacity: 0.35 * root.flashV
                }

                Column {
                    id: gateCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.leftMargin: root.s(18); anchors.rightMargin: root.s(14); anchors.topMargin: root.s(13)
                    spacing: root.s(8)
                    Row {
                        spacing: root.s(6)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.g(0xF03E4)
                            font.family: root.glyphs; font.pixelSize: root.s(13)
                            color: root.gateTone
                        }
                        Caps {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "paused  ·  your move"
                            color: root.gateTone
                        }
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: root.gateEntry ? (root.gateEntry.title || root.gateEntry.body || "") : ""
                        font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(13)
                        color: root.text
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        id: goBtn
                        width: parent.width; height: root.s(36)
                        radius: root.s(9)
                        color: goArea.pressed ? Qt.darker(root.gateTone, 1.15) : goArea.containsMouse ? Qt.lighter(root.gateTone, 1.06) : Qt.alpha(root.gateTone, 0.9)
                        scale: goArea.pressed ? 0.97 : 1
                        Behavior on scale { NumberAnimation { duration: 90 } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row {
                            anchors.centerIn: parent
                            spacing: root.s(8)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "CONTINUE"
                                font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(12); font.letterSpacing: root.s(2.2)
                                color: root.crust
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.g(0xF0311)
                                font.family: root.glyphs; font.pixelSize: root.s(15)
                                color: root.crust
                            }
                        }
                        MouseArea {
                            id: goArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.proceed()
                        }
                    }
                }
            }
        }
    }
}
