import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var bar       // barWindow, for s() scaling + barHeight
    property var theme      // MatugenColors instance
    property bool compact: false   // center-embed mode: just a status dot

    // live state pulled from the daemon + resident watcher
    property string daemonStatus: "idle"   // "idle" | "busy"
    property string sugMsg: ""
    property string sugLabel: "needs you"   // dot tag, resident-set, max 10 chars
    property string sugActionCmd: ""        // empty = passive comment, no action to confirm
    property string sugActionLabel: ""      // button text for sugActionCmd, eg "kill it"
    property double sugTs: 0
    property double seenTs: 0
    property var history: []   // last few resident nudges, [{ts, msg}, ...]
    property int replyFlash: 0  // bumped when a quick-tell reply lands → triggers a one-shot dot flash
    property int _clockTick: 0  // ticks every 1s alongside the poll, just to keep "Xm ago" fresh

    function agoText(ts) {
        let d = Math.max(0, Math.floor(Date.now() / 1000 - ts))
        if (d < 5) return "now"
        if (d < 60) return d + "s ago"
        if (d < 3600) return Math.floor(d / 60) + "m ago"
        return Math.floor(d / 3600) + "h ago"
    }

    function s(v) { return bar ? bar.s(v) : v }

    readonly property bool hasSuggestion: root.sugTs > root.seenTs && root.sugMsg !== ""
    readonly property bool hovered: hoverArea.containsMouse

    // working = a turn is running (even with the widget closed),
    // waiting = a proactive nudge is unseen, idle = ready / launcher.
    readonly property string status: {
        if (root.hasSuggestion) return "waiting"
        if (root.daemonStatus === "busy") return "working"
        return "idle"
    }

    // Fixed hex — matugen names pull warm tones on warm wallpapers and would
    // collapse the status distinction. See hypr/CLAUDE.md. Listening (the
    // SUPER+ALT+Z inline question field) gets its own fixed teal, distinct
    // from working/waiting/idle here and from topBarClaudeAuroraMode's
    // aurora pill background (a gradient effect, not a solid glow).
    readonly property color accent: {
        if (root.listening) return "#94e2d5"   // teal — listening
        switch (status) {
            case "working": return "#cba6f7"   // mauve
            case "waiting": return "#fab387"   // peach — attention
            case "idle":    return "#89b4fa"   // blue
            default:        return "#9399b2"
        }
    }
    readonly property string glyph: {
        switch (status) {
            case "working": return ""   // cog
            case "waiting": return ""   // bell
            default:        return ""   // sparkle / idle
        }
    }
    readonly property string label: {
        switch (status) {
            case "working": return "Claude · working"
            case "waiting": return "Claude · needs you"
            default:        return "Claude"
        }
    }
    readonly property bool pulsing: status === "working" || status === "waiting" || root.listening

    // ---- SUPER+ALT+Z listening state ----
    property bool listening: false
    property string listenText: ""

    Layout.alignment: Qt.AlignVCenter
    Layout.preferredWidth: compact ? compactBox.width : pill.width
    Layout.preferredHeight: bar ? bar.barHeight : 48
    implicitHeight: bar ? bar.barHeight : 48
    clip: true

    Behavior on Layout.preferredWidth { NumberAnimation { duration: 450; easing.type: Easing.OutExpo } }

    // ---- actions ----
    Process { id: opener; running: false }
    Process { id: seenWriter; running: false }
    function openWidget() {
        // passive nudge (no action attached, eg. wallpaper/song comments) — just
        // dismiss the dot, don't drag the user into a chat session for it
        if (root.hasSuggestion && root.sugActionCmd === "") {
            root.seenTs = root.sugTs
            seenWriter.command = ["bash", "-c",
                "printf '%s' \"$1\" > /tmp/qs_resident_seen", "_", String(Math.floor(root.sugTs))]
            seenWriter.running = false; seenWriter.running = true
            return
        }
        // acknowledge any pending nudge, hand its text to the widget as a prefill
        if (root.hasSuggestion) {
            root.seenTs = root.sugTs
            seenWriter.command = ["bash", "-c",
                "printf '%s' \"$1\" > /tmp/qs_resident_seen; printf '%s' \"$2\" > /tmp/qs_claude_prefill",
                "_", String(Math.floor(root.sugTs)), root.sugMsg]
            seenWriter.running = false; seenWriter.running = true
        }
        opener.command = ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "open", "claudeask"]
        opener.running = false; opener.running = true
    }

    // silent dismiss — mark seen without opening the chat, for the tooltip's × button
    function dismissSuggestion() {
        if (!root.hasSuggestion) return
        root.seenTs = root.sugTs
        seenWriter.command = ["bash", "-c",
            "printf '%s' \"$1\" > /tmp/qs_resident_seen", "_", String(Math.floor(root.sugTs))]
        seenWriter.running = false; seenWriter.running = true
    }

    // run the resident's one-click action (eg cpu-hog's "kill it") directly
    // from the tooltip, then dismiss — no chat detour needed for something
    // this quick and this reversible-by-choice (the user is the one clicking it).
    Process { id: actionRunner; running: false }
    function runSuggestedAction() {
        if (!root.hasSuggestion || root.sugActionCmd === "") return
        actionRunner.command = ["bash", "-c", root.sugActionCmd]
        actionRunner.running = false; actionRunner.running = true
        root.dismissSuggestion()
    }

    onSugTsChanged: pillBg.fire()

    // ---- SUPER+ALT+Z listening pipeline ----
    // shot_ask.sh (region-screenshot) writes the image path to the trigger
    // file below; this watches it via the standard inotify+cat idiom (same
    // one used for /tmp/qs_timer.json etc) and flips into the listening
    // state. The actual key capture happens out-of-process in
    // shot_listen.py, started via `sg input -c` same as ctrl_watch.py —
    // the bar window never gets real keyboard focus, so an inline
    // TextField here could never receive typed input directly.
    Process {
        id: listenTriggerWatcher
        running: true
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
            "touch /tmp/qs_shot_listen_trigger; exec inotifywait -m -q -e close_write /tmp/qs_shot_listen_trigger"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => { listenTriggerReader.running = false; listenTriggerReader.running = true }
        }
    }
    Process {
        id: listenTriggerReader
        command: ["bash", "-c", "cat /tmp/qs_shot_listen_trigger 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = (this.text || "").trim()
                if (p === "") return
                root.listenText = ""
                root.listening = true
            }
        }
    }
    // wrapped via lifeline.sh so it dies with Main/TopBar's restart rather
    // than leaking — leak_reaper is a backstop only, not a substitute
    Process {
        id: shotListenProc
        running: root.listening
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
            "exec sg input -c 'exec python3 /home/czeddaru/.config/hypr/scripts/quickshell/claude/shot_listen.py'"]
        onExited: root.listening = false
    }
    Process {
        id: listenTextWatcher
        running: root.listening
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
            "touch /tmp/qs_shot_listen.json; exec inotifywait -m -q -e close_write /tmp/qs_shot_listen.json"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => { listenTextReader.running = false; listenTextReader.running = true }
        }
    }
    Process {
        id: listenTextReader
        command: ["bash", "-c", "cat /tmp/qs_shot_listen.json 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse((this.text || "").trim())
                    root.listenText = d.text || ""
                } catch (e) {}
            }
        }
    }

    // ---- compact mode: status dot ----
    Item {
        id: compactBox
        visible: root.compact
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        height: parent.height
        width: compactRow.implicitWidth + root.s(8)

        Row {
            id: compactRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: root.s(4)
            spacing: root.s(6)

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: root.s(14); height: root.s(14)

                // soft halo when active — stronger/faster for "waiting" than "working"
                Rectangle {
                    anchors.centerIn: parent
                    width: root.s(14); height: root.s(14); radius: width / 2
                    color: root.accent
                    opacity: root.pulsing ? (root.status === "waiting" ? 0.38 : 0.25) : 0.0
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                    SequentialAnimation on scale {
                        running: root.pulsing
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 0.7; to: 1.5
                            duration: root.status === "waiting" ? 800 : 1100; easing.type: Easing.OutQuad
                        }
                        NumberAnimation { from: 1.5; to: 0.7; duration: 0 }
                    }
                }
                // one-shot reply flash — expanding peach ring when a quick-tell reply lands.
                // NB: the animations target `flashRing` by id — `target: parent` inside a
                // SequentialAnimation does NOT resolve to the Rectangle (animations have no
                // visual parent), it was null and broke the ClaudeStatus render on every
                // reply, collapsing the topbar centre box.
                Rectangle {
                    id: flashRing
                    anchors.centerIn: parent
                    width: root.s(14); height: width; radius: width / 2
                    color: "transparent"
                    border.width: root.s(2)
                    border.color: "#fab387"
                    opacity: 0
                    property int trig: root.replyFlash
                    onTrigChanged: flashAnim.restart()
                    SequentialAnimation {
                        id: flashAnim
                        loops: 3
                        ParallelAnimation {
                            NumberAnimation { target: flashRing; property: "scale"; from: 0.6; to: 1.8; duration: 380; easing.type: Easing.OutQuad }
                            SequentialAnimation {
                                NumberAnimation { target: flashRing; property: "opacity"; from: 0.0; to: 0.9; duration: 120 }
                                NumberAnimation { target: flashRing; property: "opacity"; to: 0.0; duration: 260 }
                            }
                        }
                    }
                }
                Rectangle {
                    id: dot
                    anchors.centerIn: parent
                    width: root.s(9); height: root.s(9); radius: width / 2
                    color: root.accent
                    Behavior on color { ColorAnimation { duration: 300 } }
                    // idle: faint breathing so the dot reads as "alive" even with nothing pending
                    Timer {
                        interval: 100; repeat: true
                        running: !root.pulsing && root.visible
                        onTriggered: dot.opacity = 1 - 0.35 * (0.5 - 0.5 * Math.cos(2 * Math.PI * ((Date.now() % 4400) / 4400)))
                    }
                    SequentialAnimation on opacity {
                        running: root.pulsing
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.45; duration: root.status === "waiting" ? 450 : 650; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0;  duration: root.status === "waiting" ? 450 : 650; easing.type: Easing.InOutQuad }
                    }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.status === "waiting"
                text: root.sugLabel.slice(0, 10)
                font.family: "JetBrains Mono"; font.pixelSize: root.s(11); font.weight: Font.Bold
                color: root.accent
            }
            // Elapsed time — without this the compact pill gives no signal that
            // a nudge is aging normally toward its own expiry vs. actually
            // stuck; "shot" (and anything else) now visibly counts up.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.status === "waiting"
                text: { root._clockTick; return root.agoText(root.sugTs) }
                font.family: "JetBrains Mono"; font.pixelSize: root.s(9)
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.65)
            }
            // Inline growing question field — not a real TextField (the bar
            // window never gets keyboard focus), just a live mirror of the
            // buffer shot_listen.py is streaming to /tmp/qs_shot_listen.json.
            // Anchored to the right inside a clipped, width-animated box so
            // it visually grows as you type and always shows the tail end
            // (cursor position) once it hits the width cap.
            Item {
                id: listenBox
                visible: root.listening
                anchors.verticalCenter: parent.verticalCenter
                height: root.s(14)
                width: visible ? Math.min(root.s(260), listenTextItem.implicitWidth + root.s(6)) : 0
                clip: true
                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                Text {
                    id: listenTextItem
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    text: root.listenText.length > 0 ? root.listenText : "type…"
                    font.family: "JetBrains Mono"; font.pixelSize: root.s(11)
                    color: root.listenText.length > 0 ? root.accent : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
                }
            }
        }
    }

    // ---- pill mode (non-compact) ----
    Rectangle {
        id: pill
        visible: !root.compact
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        width: pillRow.width + root.s(20)
        height: bar ? bar.barHeight : 48
        radius: root.s(14)
        color: theme ? Qt.rgba(theme.base.r, theme.base.g, theme.base.b, 0.75) : "#222"
        border.width: 1
        border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.8)

        Behavior on border.color { ColorAnimation { duration: 300 } }
        SequentialAnimation on opacity {
            running: root.status === "waiting"
            loops: Animation.Infinite
            NumberAnimation { to: 0.4; duration: 550; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 550; easing.type: Easing.InOutQuad }
        }
        SequentialAnimation on opacity {
            running: root.status === "idle"
            loops: Animation.Infinite
            NumberAnimation { to: 0.85; duration: 2400; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0;  duration: 2400; easing.type: Easing.InOutQuad }
        }

        PillBg {
            id: pillBg
            kind: "aurora"
            radius: pill.radius
            px: root.s(1)
            shown: root.bar !== null && root.bar !== undefined && root.bar.pillFxOn(root.bar.topBarClaudeAuroraMode, root.daemonStatus === "busy" || root.bar.fxFlash("claude"))
        }

        // Resident pill takeover — same generic mechanism as the rest of the bar's
        // pills (resident_card.pill_flag("claude", ...)). Lives inside `pill`
        // (not `compactBox`), so it's naturally excluded in compact/dot mode too.
        PillBg {
            id: residentClaudeBg
            kind: root.bar && root.bar.residentPillFlag.style === "border" ? "border" : "pulse"
            radius: pill.radius
            px: root.s(1)
            tint: (root.bar && root.bar.residentPillFlag.tint) ? root.bar.residentPillFlag.tint : "#cba6f7"
            shown: !!root.bar && root.bar.residentPillActive("claude")
        }
        Connections {
            target: root.bar
            ignoreUnknownSignals: true
            function onResidentPillBurstChanged() { if (root.bar && root.bar.residentPillFlag.pill === "claude") residentClaudeBg.fire() }
        }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: root.s(7)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.glyph
                font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(14)
                color: root.accent
                RotationAnimation on rotation {
                    running: root.status === "working"
                    from: 0; to: 360; duration: 1600; loops: Animation.Infinite
                }
                onTextChanged: rotation = 0
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                font.family: "JetBrains Mono"; font.pixelSize: root.s(12); font.weight: Font.Bold
                color: theme ? theme.text : "#eee"
            }
        }
    }

    // ---- click target: open the Claude widget ----
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: root.openWidget()
    }

    // tooltip: current nudge (if pending) plus recent resident history, on hover any time
    Rectangle {
        id: tip
        visible: !root.compact && (hoverArea.containsMouse || tipHover.containsMouse) && (root.hasSuggestion || root.history.length > 0)
        anchors.top: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: root.s(6)
        width: tipCol.implicitWidth + root.s(20)
        height: tipCol.implicitHeight + root.s(12)
        radius: root.s(10)
        color: theme ? theme.mantle : "#181825"
        border.width: 1; border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
        z: 100

        // keeps the tooltip alive while the mouse moves down off the pill and
        // into the tooltip itself — without this, hovering toward the ×/run
        // buttons below the pill instantly loses hoverArea.containsMouse and
        // the tooltip vanishes before a click can land. acceptedButtons:
        // NoButton so it never steals a press from the real buttons drawn
        // after it (QtQuick offers press events to those first regardless of
        // this MouseArea also seeing the hover).
        MouseArea { id: tipHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

        Column {
            id: tipCol
            anchors.centerIn: parent
            spacing: root.s(5)

            RowLayout {
                visible: root.hasSuggestion
                width: parent.width
                spacing: root.s(8)
                Rectangle {
                    Layout.preferredWidth: sugLabelText.implicitWidth + root.s(10)
                    Layout.preferredHeight: root.s(16)
                    radius: height / 2
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                    Text {
                        id: sugLabelText
                        anchors.centerIn: parent
                        text: root.sugLabel
                        font.family: "JetBrains Mono"; font.pixelSize: root.s(9); font.weight: Font.Bold
                        color: root.accent
                    }
                }
                Text {
                    text: { root._clockTick; return root.agoText(root.sugTs) }
                    font.family: "JetBrains Mono"; font.pixelSize: root.s(9)
                    color: theme ? theme.overlay0 : "#666"
                    Layout.fillWidth: true
                }
                Text {
                    text: "×"
                    font.pixelSize: root.s(13); font.weight: Font.Bold
                    color: dismissMa.containsMouse ? (theme ? theme.text : "#eee") : (theme ? theme.overlay0 : "#777")
                    MouseArea {
                        id: dismissMa
                        anchors.fill: parent; anchors.margins: -root.s(4)
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.dismissSuggestion()
                    }
                }
            }
            Text {
                visible: root.hasSuggestion
                text: root.sugMsg
                font.family: "JetBrains Mono"; font.pixelSize: root.s(11); font.weight: Font.Bold
                color: theme ? theme.text : "#eee"
                wrapMode: Text.NoWrap
            }
            Rectangle {
                visible: root.hasSuggestion && root.sugActionCmd !== ""
                width: runRow.implicitWidth + root.s(16)
                height: root.s(20)
                radius: root.s(6)
                color: runMa.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.3) : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                border.width: 1; border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)
                Behavior on color { ColorAnimation { duration: 120 } }
                Row {
                    id: runRow
                    anchors.centerIn: parent
                    spacing: root.s(5)
                    Text { text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(10); color: root.accent }
                    Text {
                        text: root.sugActionLabel !== "" ? root.sugActionLabel : "run"
                        font.family: "JetBrains Mono"; font.pixelSize: root.s(10); font.weight: Font.Bold
                        color: root.accent
                    }
                }
                MouseArea {
                    id: runMa
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.runSuggestedAction()
                }
            }
            Repeater {
                model: {
                    let h = root.history.slice().reverse()
                    if (root.hasSuggestion && h.length > 0 && h[0].msg === root.sugMsg) h = h.slice(1)
                    return h.slice(0, 4)
                }
                Text {
                    text: "· " + modelData.msg
                    font.family: "JetBrains Mono"; font.pixelSize: root.s(10)
                    color: theme ? theme.subtext0 : "#888"
                    opacity: 0.7
                    wrapMode: Text.NoWrap
                }
            }
        }
    }
    MouseArea { id: hoverArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

    // ---- poll daemon status + resident suggestion ----
    Process {
        id: reader
        command: ["bash", "-c",
            "s=$(cat /tmp/qs_claude_status 2>/dev/null); seen=$(cat /tmp/qs_resident_seen 2>/dev/null || echo 0); sug=$(cat /tmp/qs_resident_suggestion 2>/dev/null || echo '{}'); hist=$(cat /tmp/qs_resident_history.json 2>/dev/null || echo '[]'); qtp=$(cat /tmp/qs_quicktell_pending 2>/dev/null || echo 0); qta=$(cat /tmp/qs_quicktell_ack 2>/dev/null || echo 0); printf '{\"daemon\":\"%s\",\"seen\":%s,\"sug\":%s,\"history\":%s,\"qtp\":%s,\"qta\":%s}' \"$s\" \"$seen\" \"$sug\" \"$hist\" \"${qtp:-0}\" \"${qta:-0}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text.trim()
                if (txt === "") return
                try {
                    let d = JSON.parse(txt)
                    let prev = root.daemonStatus
                    root.daemonStatus = d.daemon || "idle"
                    root.seenTs = d.seen || 0
                    let sug = d.sug || {}
                    root.sugMsg = sug.msg || ""
                    root.sugLabel = sug.label || "needs you"
                    root.sugActionCmd = sug.action_cmd || ""
                    root.sugActionLabel = sug.action_label || ""
                    root.sugTs = sug.ts || 0
                    root.history = d.history || []
                    // a quick-tell reply just landed (daemon went busy→idle with an
                    // un-acked pending send) → flash the dot, then ack so it fires once
                    let qtp = d.qtp || 0, qta = d.qta || 0
                    if (prev === "busy" && root.daemonStatus !== "busy" && qtp > qta) {
                        root.replyFlash++
                        // Body = the reply that JUST finished. chat.json is only written
                        // by the ClaudeAsk widget (stale when sending via QuickTell), so
                        // read /tmp/qs_claude_stream instead — the daemon appends every
                        // {"t":"text","d":...} chunk there live. Concatenate the text
                        // chunks of the LAST turn (after the final 'turn' marker's prior turn).
                        notifier.command = ["bash", "-c",
                            "b=$(python3 - <<'PY'\n" +
                            "import json\n" +
                            "try:\n" +
                            "  lines=[l for l in open('/tmp/qs_claude_stream') if l.strip()]\n" +
                            "  ev=[json.loads(l) for l in lines]\n" +
                            "  # find the last completed turn: collect text chunks after the\n" +
                            "  # second-to-last 'turn' marker up to the last one\n" +
                            "  turns=[i for i,e in enumerate(ev) if e.get('t')=='turn']\n" +
                            "  lo=turns[-2] if len(turns)>=2 else -1\n" +
                            "  hi=turns[-1] if turns else len(ev)\n" +
                            "  txt=''.join(e.get('d','') for e in ev[lo+1:hi] if e.get('t')=='text')\n" +
                            "  print(txt.strip()[:180])\n" +
                            "except Exception: print('')\n" +
                            "PY\n" +
                            ")\n" +
                            "notify-send -a Claude -u normal -i dialog-information " +
                            "-h string:x-canonical-private-synchronous:claude-quicktell " +
                            "'Claude replied' \"${b:-Tap to open the chat.}\""]
                        notifier.running = false; notifier.running = true
                        ackWriter.command = ["bash", "-c", "printf '%s' \"$1\" > /tmp/qs_quicktell_ack", "_", String(qtp)]
                        ackWriter.running = false; ackWriter.running = true
                    }
                } catch (e) {}
            }
        }
    }
    Process { id: ackWriter; running: false }
    Process { id: notifier; running: false }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { root._clockTick++; reader.running = true } }
}
