import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

FocusScope {
    id: window
    focus: true

    // Main.qml forceActiveFocus()es this on load → forward into the field.
    onActiveFocusChanged: if (activeFocus && !voiceMode && vState !== "listening") input.forceActiveFocus();

    property string widgetArg: ""
    readonly property bool voiceMode: widgetArg === "voice"

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val); }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    // fixed accents — matugen names drift warm (see hypr/CLAUDE.md)
    readonly property color mauve: "#cba6f7"
    readonly property color peach: "#fab387"
    readonly property color accent: voiceMode ? peach : mauve

    // voice: idle → listening → review → sent
    property string vState: voiceMode ? "idle" : "text"
    property string heardLang: ""
    property bool micMuted: false
    property bool warnDismissed: false
    readonly property bool showMicWarn: micMuted && !warnDismissed && voiceMode

    // ---- sizing: card grows from minInner toward the sides, wraps at maxInner ----
    readonly property real innerMin: s(240)
    readonly property real innerMax: s(540)
    readonly property real hPad: s(20)
    readonly property real vPad: s(15)
    readonly property real glyphW: s(20)
    readonly property real gap: s(13)

    TextMetrics {
        id: tm
        font: input.font
        text: input.text.length ? input.text : input.placeholderText
    }
    readonly property real innerW: Math.max(innerMin, Math.min(innerMax, tm.advanceWidth + s(14)))

    function close() {
        Quickshell.execDetached(["bash", "-c", "echo close > /tmp/qs_widget_state"]);
    }

    Process { id: daemonStarter; running: false
        command: ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/claude/claude_daemon.sh"] }
    Process { id: fifoWriter; running: false }

    function submit(msg) {
        let t = (msg || "").trim();
        if (t === "") return;
        daemonStarter.running = false; daemonStarter.running = true;
        fifoWriter.command = ["bash", "-c",
            "printf '%s\\n' \"$1\" > /tmp/qs_claude_in; " +
            "printf '%s' \"$(date +%s)\" > /tmp/qs_quicktell_pending",
            "_", JSON.stringify({ text: t })];
        fifoWriter.running = false; fifoWriter.running = true;
        vState = "sent";
        sentTimer.start();
    }
    Timer { id: sentTimer; interval: 150; onTriggered: window.close() }

    // ---- voice capture via warm STT server (Czech + English auto) ----
    Process {
        id: listenProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(this.text.trim() || "{}"); } catch (e) {}
                let txt = (r.text || "").trim();
                window.heardLang = r.lang || "";
                if (txt === "") {
                    window.vState = "review";
                    input.forceActiveFocus();
                } else if (r.autosend) {
                    window.submit(txt);
                } else {
                    window.vState = "review";
                    input.text = txt;
                    input.forceActiveFocus();
                    input.cursorPosition = txt.length;
                }
            }
        }
    }
    function startListening() {
        vState = "listening";
        input.text = "";
        listenProc.command = ["bash", Quickshell.env("HOME") +
            "/.config/hypr/scripts/quickshell/claude/voice/listen_once.sh"];
        listenProc.running = false; listenProc.running = true;
    }

    Process {
        id: micReader
        running: false
        command: ["bash", "-c", "pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null || echo unknown"]
        stdout: StdioCollector { onStreamFinished: window.micMuted = this.text.indexOf("yes") >= 0; }
    }
    Timer { interval: 1500; repeat: true; running: window.voiceMode; triggeredOnStart: true
        onTriggered: { micReader.running = false; micReader.running = true; } }

    Component.onCompleted: {
        if (voiceMode) startListening();
        else input.forceActiveFocus();
    }

    Keys.onEscapePressed: (e) => { window.close(); e.accepted = true; }

    property real introPhase: 0
    NumberAnimation on introPhase { from: 0; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.15; running: true }

    // ===================== card =====================
    Column {
        anchors.centerIn: parent
        spacing: s(8)
        opacity: window.introPhase
        transform: Translate { y: (1 - window.introPhase) * s(14) }

        Item {
            id: cardWrap
            anchors.horizontalCenter: parent.horizontalCenter
            width: window.innerW + window.hPad * 2
            height: Math.max(s(56), input.contentHeight + window.vPad * 2)
            Behavior on width  { NumberAnimation { duration: 220; easing.type: Easing.OutExpo } }
            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutExpo } }

            scale: input.activeFocus ? 1.0 : 0.985
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutExpo } }

            // soft accent halo — breathes behind the card, brighter on focus/listen
            Rectangle {
                anchors.fill: parent
                anchors.margins: -s(10)
                radius: s(24)
                color: "transparent"
                border.width: s(10)
                border.color: window.accent
                opacity: (input.activeFocus || window.vState === "listening") ? haloOp : 0.0
                property real haloOp: 0.10
                Behavior on opacity { NumberAnimation { duration: 280 } }
                SequentialAnimation on haloOp {
                    running: window.vState === "listening"; loops: Animation.Infinite
                    NumberAnimation { to: 0.22; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.08; duration: 900; easing.type: Easing.InOutSine }
                }
            }

            // layered drop shadow — three offset rects fake a soft blurred shadow
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    anchors.fill: card
                    anchors.topMargin: s(2 + index * 3)
                    anchors.leftMargin: index
                    anchors.rightMargin: index
                    radius: card.radius + index * 2
                    color: "#000000"
                    opacity: 0.22 - index * 0.05
                }
            }

            // send-success pulse — expanding accent ring when a message fires.
            // targets sendRing by id: `target: parent` is null inside an animation.
            Rectangle {
                id: sendRing
                anchors.centerIn: card
                width: card.width; height: card.height
                radius: card.radius
                color: "transparent"
                border.width: s(2)
                border.color: window.accent
                opacity: 0
                property int trig: window.vState === "sent" ? 1 : 0
                onTrigChanged: if (trig) sendPulse.restart()
                ParallelAnimation {
                    id: sendPulse
                    NumberAnimation { target: sendRing; property: "scale"; from: 1.0; to: 1.15; duration: 420; easing.type: Easing.OutQuad }
                    SequentialAnimation {
                        NumberAnimation { target: sendRing; property: "opacity"; from: 0.0; to: 0.7; duration: 120 }
                        NumberAnimation { target: sendRing; property: "opacity"; to: 0.0; duration: 320 }
                    }
                }
            }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: s(16)
            border.width: 1
            border.color: input.activeFocus
                ? Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.55)
                : Qt.rgba(window.text.r, window.text.g, window.text.b, 0.10)
            Behavior on border.color { ColorAnimation { duration: 160 } }

            // vertical gradient — slightly lighter top, deeper bottom = depth
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.97) }
                GradientStop { position: 1.0; color: Qt.rgba(window.base.r, window.base.g, window.base.b, 0.98) }
            }

            // top sheen — bright gradient catching "light" along the upper edge
            Rectangle {
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                anchors.margins: 1
                height: parent.height * 0.5
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.05) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // diagonal specular sweep — a soft highlight that drifts across on focus
            Item {
                anchors.fill: parent
                clip: true
                visible: input.activeFocus
                Rectangle {
                    width: parent.width * 0.3; height: parent.height * 2.4
                    rotation: 22
                    y: -parent.height * 0.7
                    x: sweepX
                    property real sweepX: -width
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.06) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                    SequentialAnimation on sweepX {
                        running: input.activeFocus; loops: Animation.Infinite
                        NumberAnimation { from: -window.width * 0.4; to: window.width * 1.4; duration: 2600; easing.type: Easing.InOutSine }
                        PauseAnimation { duration: 2400 }
                    }
                }
            }

            // subtle accent glow underline
            Rectangle {
                anchors.bottom: parent.bottom; anchors.bottomMargin: s(1)
                anchors.horizontalCenter: parent.horizontalCenter
                width: input.activeFocus || window.vState === "listening" ? parent.width * 0.62 : parent.width * 0.3
                height: s(2); radius: height / 2
                color: window.accent
                opacity: input.activeFocus || window.vState === "listening" ? 0.6 : 0.0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
            }

            // live waveform — shown only while listening, replaces the placeholder
            Row {
                anchors.centerIn: parent
                spacing: s(4)
                visible: window.vState === "listening"
                Repeater {
                    model: 9
                    Rectangle {
                        required property int index
                        width: s(3); radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: window.accent
                        property real lvl: 0.4
                        height: s(8) + lvl * s(20)
                        opacity: 0.85
                        SequentialAnimation on lvl {
                            running: window.vState === "listening"; loops: Animation.Infinite
                            PauseAnimation { duration: index * 70 }
                            NumberAnimation { to: 1.0; duration: 320 + (index % 3) * 90; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0.25; duration: 300 + (index % 4) * 80; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }

            // input / transcript field — fixed width, centered in card so HCenter
            // lands on screen-center. height drives card height (no fill = no loop).
            TextArea {
                id: input
                width: window.innerW
                visible: window.vState !== "listening"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: TextEdit.AlignHCenter
                verticalAlignment: TextEdit.AlignVCenter
                leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                cursorDelegate: Component { Item {} }
                background: Item {}
                color: window.text
                selectionColor: Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.35)
                wrapMode: TextEdit.Wrap
                font.family: "JetBrains Mono"; font.pixelSize: s(15)
                enabled: window.vState !== "listening" && window.vState !== "sent"
                placeholderText: window.vState === "listening" ? "Listening…"
                    : window.voiceMode ? "Speak, or type…" : "Message Claude…"
                placeholderTextColor: window.vState === "listening"
                    ? window.accent : window.subtext0
                Keys.onReturnPressed: (e) => {
                    if (e.modifiers & Qt.ShiftModifier) { e.accepted = false; return; }
                    window.submit(text); e.accepted = true;
                }
                Keys.onPressed: (e) => {
                    if (window.voiceMode && e.key === Qt.Key_R && (e.modifiers & Qt.ControlModifier)) {
                        window.startListening(); e.accepted = true;
                    }
                }
                Keys.onEscapePressed: (e) => { window.close(); e.accepted = true; }
            }
        }
        }

        // ---- mic-off warning (slim, dismissable, voice only) ----
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: warnRow.implicitWidth + s(24)
            height: window.showMicWarn ? s(30) : 0
            visible: height > 0
            radius: s(9)
            color: Qt.rgba(window.peach.r, window.peach.g, window.peach.b, 0.13)
            border.width: 1; border.color: Qt.rgba(window.peach.r, window.peach.g, window.peach.b, 0.35)
            clip: true
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutExpo } }

            Row {
                id: warnRow
                anchors.centerIn: parent
                spacing: s(8)
                Text { anchors.verticalCenter: parent.verticalCenter
                    text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: s(12); color: window.peach }
                Text { anchors.verticalCenter: parent.verticalCenter
                    text: "Mic muted — unmute for voice"
                    font.family: "JetBrains Mono"; font.pixelSize: s(11); color: window.text }
                Text { anchors.verticalCenter: parent.verticalCenter
                    text: "✕"; font.pixelSize: s(10); color: window.peach
                    MouseArea { anchors.fill: parent; anchors.margins: -s(6)
                        cursorShape: Qt.PointingHandCursor; onClicked: window.warnDismissed = true } }
            }
        }
    }
}
