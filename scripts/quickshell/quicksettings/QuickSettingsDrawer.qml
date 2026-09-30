import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window

    // -------------------------------------------------------------------------
    // Inline components — this directory is only reached via a Loader/StackView
    // URL, never a static `import`, so quickshell never scans it and never
    // synthesizes a qmldir for it. Sibling .qml components are therefore
    // invisible here ("X is not a type"). Declaring everything inline in this
    // one file sidesteps that entirely.
    // -------------------------------------------------------------------------

    component DeckKnob: Item {
        id: knob
        property real val: 50
        property string label: ""
        property color colA: "#f5c2e7"
        property color colB: "#cba6f7"
        property var theme: null
        signal dragged(real v)

        readonly property real minDeg: -130
        readonly property real maxDeg: 130
        readonly property real sweep: maxDeg - minDeg

        width: theme ? theme.s(76) : 76
        height: theme ? theme.s(76) : 76

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            text: knob.label
            font.family: "JetBrains Mono"
            font.pixelSize: theme ? theme.s(9) : 9
            font.capitalization: Font.AllUppercase
            color: theme ? theme.overlay1 : "#7f849c"
        }

        Item {
            id: wrap
            anchors.centerIn: parent
            anchors.verticalCenterOffset: theme ? theme.s(4) : 4
            width: theme ? theme.s(56) : 56
            height: theme ? theme.s(56) : 56

            Canvas {
                id: ring
                anchors.fill: parent
                onPaint: {
                    let ctx = getContext("2d");
                    ctx.reset();
                    let cx = width / 2, cy = height / 2;
                    let r = width / 2 - (theme ? theme.s(3) : 3);
                    let start = (knob.minDeg - 90) * Math.PI / 180;
                    let full = (knob.maxDeg - 90) * Math.PI / 180;
                    let cur = start + (knob.sweep * Math.PI / 180) * (knob.val / 100);
                    ctx.lineWidth = theme ? theme.s(4) : 4;
                    ctx.lineCap = "round";
                    ctx.strokeStyle = theme ? theme.surface1 : "#45475a";
                    ctx.beginPath(); ctx.arc(cx, cy, r, start, full); ctx.stroke();
                    ctx.strokeStyle = knob.colA;
                    ctx.beginPath(); ctx.arc(cx, cy, r, start, cur); ctx.stroke();
                }
                Connections { target: knob; function onValChanged() { ring.requestPaint(); } }
                Component.onCompleted: requestPaint()
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: theme ? theme.s(8) : 8
                radius: width / 2
                color: theme ? theme.mantle : "#16151f"
                border.width: 1
                border.color: theme ? theme.surface2 : "#37354a"
                Text {
                    anchors.centerIn: parent
                    text: Math.round(knob.val)
                    font.family: "JetBrains Mono"
                    font.weight: Font.Black
                    font.pixelSize: theme ? theme.s(15) : 15
                    color: theme ? theme.text : "#eae8f5"
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: (mouse) => updateFromPos(mouse.x, mouse.y)
                onPositionChanged: (mouse) => { if (pressed) updateFromPos(mouse.x, mouse.y); }
                function updateFromPos(mx, my) {
                    let cx = width / 2, cy = height / 2;
                    let deg = Math.atan2(mx - cx, -(my - cy)) * (180 / Math.PI);
                    deg = Math.min(knob.maxDeg, Math.max(knob.minDeg, deg));
                    let v = ((deg - knob.minDeg) / knob.sweep) * 100;
                    knob.val = v;
                    knob.dragged(v);
                }
            }
        }
    }

    component DeckFader: Item {
        id: fader
        property real val: 50
        property color colTop: "#fab387"
        property color colBottom: "#ffcf9e"
        property var theme: null
        signal dragged(real v)

        Rectangle {
            anchors.fill: parent
            radius: theme ? theme.s(5) : 5
            color: theme ? theme.surface1 : "#37354a"
            clip: true
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * (fader.val / 100)
                radius: theme ? theme.s(5) : 5
                gradient: Gradient {
                    GradientStop { position: 0.0; color: fader.colTop }
                    GradientStop { position: 1.0; color: fader.colBottom }
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: (mouse) => updateFromY(mouse.y)
            onPositionChanged: (mouse) => { if (pressed) updateFromY(mouse.y); }
            function updateFromY(my) {
                let pct = Math.max(0, Math.min(100, Math.round(100 - (my / height) * 100)));
                fader.val = pct;
                fader.dragged(pct);
            }
        }
    }

    component DeckSwitchRow: RowLayout {
        id: srow
        property string label: ""
        property bool active: false
        property color accent: "#a6e3a1"
        property var theme: null
        signal toggled()

        Layout.fillWidth: true
        spacing: theme ? theme.s(6) : 6

        Text {
            text: srow.label
            font.family: "JetBrains Mono"
            font.pixelSize: theme ? theme.s(10) : 10
            color: theme ? theme.text : "#eae8f5"
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
        Rectangle {
            Layout.preferredWidth: theme ? theme.s(30) : 30
            Layout.preferredHeight: theme ? theme.s(16) : 16
            radius: height / 2
            color: srow.active ? srow.accent : (theme ? theme.surface2 : "#37354a")
            Behavior on color { ColorAnimation { duration: 180 } }
            Rectangle {
                width: parent.height - 4; height: parent.height - 4
                radius: height / 2
                anchors.verticalCenter: parent.verticalCenter
                x: srow.active ? parent.width - width - 2 : 2
                color: "#0f0e15"
                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: srow.toggled() }
        }
    }

    component DeckQaIcon: Rectangle {
        id: qa
        property string glyph: ""
        property string title: ""
        property var theme: null
        signal activated()

        radius: theme ? theme.s(8) : 8
        color: qaMa.containsMouse ? (theme ? theme.surface2 : "#37354a") : (theme ? theme.surface1 : "#2a2836")
        border.width: 1
        border.color: theme ? theme.surface2 : "#37354a"
        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: qa.glyph
            font.family: "Iosevka Nerd Font"
            font.pixelSize: theme ? theme.s(17) : 17
            color: qaMa.containsMouse ? (theme ? theme.pink : "#f5c2e7") : (theme ? theme.subtext0 : "#a8a5bd")
        }
        MouseArea {
            id: qaMa
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: qa.activated()
        }
    }

    component DeckKeycap: Rectangle {
        id: cap
        property string glyph: "★"
        property bool active: false
        property var theme: null
        signal activated()

        radius: theme ? theme.s(5) : 5
        color: cap.active ? (theme ? theme.mauve : "#cba6f7") : (capMa.containsMouse ? (theme ? theme.surface2 : "#37354a") : (theme ? theme.surface1 : "#2a2836"))
        border.width: 1
        border.color: theme ? theme.surface2 : "#37354a"
        Behavior on color { ColorAnimation { duration: 150 } }
        Text {
            anchors.centerIn: parent
            text: cap.glyph
            font.pixelSize: theme ? theme.s(11) : 11
            color: cap.active ? "#22101d" : (theme ? theme.text : "#eae8f5")
        }
        MouseArea { id: capMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cap.activated() }
    }

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val); }
    readonly property int cellSize: 16
    function gx(n) { return window.s(n * cellSize); }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color overlay1: _theme.overlay1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color red: _theme.red
    readonly property color peach: _theme.peach
    readonly property color yellow: _theme.yellow
    readonly property color green: _theme.green
    readonly property color teal: _theme.teal
    readonly property color sapphire: _theme.sapphire
    readonly property color blue: _theme.blue

    // -------------------------------------------------------------------------
    // STATE — same underlying sources/scripts as TopBar's tray pills and
    // BatteryPopup's own sliders. This drawer is purely a bigger touch surface
    // over the exact same state, not a parallel control path.
    // -------------------------------------------------------------------------
    property real sysVolume: 0
    property bool sysMuted: false
    property real sysBrightness: 0
    property real micGain: 0
    property bool micMuted: false
    property bool isDraggingVol: false
    property bool isDraggingBri: false
    property bool isDraggingMic: false

    property string wifiPower: "off"
    property string wifiSsid: ""
    property bool wifiPending: false

    property string btPower: "off"
    property int btConnectedCount: 0
    property bool btPending: false

    property bool dndOn: false
    property string nlMode: "auto" // auto | on | off

    property int cpuPct: 0
    property string batteryPercent: "100"
    property string batteryStatus: "Full"
    property bool kandorEnabled: true
    property string powerProfile: "balanced"

    property string weatherTemp: "--"
    property string weatherIcon: ""
    property string weatherDesc: ""

    property string musicTitle: "Not Playing"
    property string musicArtist: ""
    property string musicStatus: "Stopped"
    property int musicBpm: 0
    property real musicPercent: 0
    property bool isMediaActive: musicStatus !== "Stopped" && musicTitle !== "Not Playing" && musicTitle !== ""
    property real mediaAudioLevel: 0
    Behavior on mediaAudioLevel { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }

    Timer { id: volSyncDelay; interval: 800; onTriggered: window.isDraggingVol = false }
    Timer { id: briSyncDelay; interval: 800; onTriggered: window.isDraggingBri = false }
    Timer { id: micSyncDelay; interval: 800; onTriggered: window.isDraggingMic = false }

    readonly property string scriptsDir: Quickshell.env("HOME") + "/.config/hypr/scripts"
    readonly property string networkScriptsDir: scriptsDir + "/quickshell/network"

    // -------------------------------------------------------------------------
    // POLLING — volume/brightness/mic mirrors BatteryPopup.qml's slider poll,
    // extended with battery/kandor/power-profile in the same combined call so
    // it stays one spawn per tick instead of five. wifi/bt reuse the exact
    // panel-logic scripts NetworkPopup.qml already drives. DND reuses
    // swaync-client, the same backend toggle_dnd (holdaction registry) already
    // calls. Night light reuses the qs_nightlight_override file toggle_night_
    // light.sh already owns. CPU reuses cpu_usage.sh's long-lived /proc/stat
    // delta loop exactly like TopBar's own sparkline. Music reads the same
    // /tmp/music_info.json music_info.sh already maintains.
    // -------------------------------------------------------------------------
    Process {
        id: sysPoller
        command: ["bash", "-c",
            "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print int($2*100), ($3==\"[MUTED]\"?\"off\":\"on\")}' || echo '0 on'; " +
            "brightnessctl -m 2>/dev/null | awk -F, '{print substr($4, 1, length($4)-1)}' || echo '0'; " +
            "timeout 2 swaync-client -D 2>/dev/null || echo false; " +
            "cat /tmp/qs_nightlight_override 2>/dev/null || echo auto; " +
            "wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | awk '{print int($2*100), ($3==\"[MUTED]\"?\"off\":\"on\")}' || echo '0 on'; " +
            "echo \"$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1 || echo 100) $(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1 || echo Full)\"; " +
            "cat /tmp/qs_kandor_enabled 2>/dev/null || echo 1; " +
            "powerprofilesctl get 2>/dev/null || echo balanced"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                if (lines.length >= 8) {
                    if (!window.isDraggingVol) {
                        let volParts = (lines[0] || "0 on").trim().split(" ");
                        window.sysVolume = parseInt(volParts[0]) || 0;
                        window.sysMuted = (volParts[1] === "off");
                    }
                    if (!window.isDraggingBri) window.sysBrightness = parseInt(lines[1]) || 0;
                    window.dndOn = lines[2].trim() === "true";
                    window.nlMode = lines[3].trim() || "auto";
                    if (!window.isDraggingMic) {
                        let micParts = (lines[4] || "0 on").trim().split(" ");
                        window.micGain = parseInt(micParts[0]) || 0;
                        window.micMuted = (micParts[1] === "off");
                    }
                    let batParts = (lines[5] || "100 Full").trim().split(" ");
                    window.batteryPercent = batParts[0] || "100";
                    window.batteryStatus = batParts[1] || "Full";
                    window.kandorEnabled = lines[6].trim() === "1" || lines[6].trim() === "true";
                    window.powerProfile = lines[7].trim() || "balanced";
                }
            }
        }
    }
    Timer { interval: 1500; running: true; repeat: true; triggeredOnStart: true; onTriggered: sysPoller.running = true }

    Process {
        id: wifiPoller
        command: ["bash", window.networkScriptsDir + "/wifi_panel_logic.sh"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(this.text.trim());
                    if (!window.wifiPending) window.wifiPower = d.power || "off";
                    window.wifiSsid = (d.connected && d.connected.ssid) ? d.connected.ssid : "";
                } catch (e) {}
            }
        }
    }

    Process {
        id: btPoller
        command: ["bash", window.networkScriptsDir + "/bluetooth_panel_logic.sh", "--status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(this.text.trim());
                    if (!window.btPending) window.btPower = d.power || "off";
                    window.btConnectedCount = (d.connected || []).length;
                } catch (e) {}
            }
        }
    }
    Timer { interval: 3000; running: true; repeat: true; onTriggered: { wifiPoller.running = true; btPoller.running = true; } }
    Timer { id: wifiPendingReset; interval: 4000; onTriggered: window.wifiPending = false }
    Timer { id: btPendingReset; interval: 4000; onTriggered: window.btPending = false }

    Process {
        id: cpuPoller
        running: true
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "~/.config/hypr/scripts/quickshell/cpu_usage.sh"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => { let v = parseInt(line); if (!isNaN(v)) window.cpuPct = v; }
        }
    }

    Process {
        id: weatherPoller
        command: ["bash", "-c",
            "bash ~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-temp 2>/dev/null; " +
            "bash ~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-icon 2>/dev/null; " +
            "jq -r '.forecast[0].desc // \"Cloudy\"' ~/.cache/quickshell/weather/weather.json 2>/dev/null || echo Cloudy"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                if (lines.length >= 3) {
                    window.weatherTemp = lines[0].trim() || "--";
                    window.weatherIcon = lines[1].trim();
                    window.weatherDesc = lines[2].trim() || "Cloudy";
                }
            }
        }
    }
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: weatherPoller.running = true }

    Process {
        id: musicPoller
        command: ["bash", "-c", "cat /tmp/music_info.json 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(this.text.trim());
                    window.musicTitle = d.title || "Not Playing";
                    window.musicArtist = d.artist || "";
                    window.musicStatus = d.status || "Stopped";
                    window.musicBpm = d.bpm || 0;
                    window.musicPercent = d.percent || 0;
                } catch (e) {}
            }
        }
    }
    Timer { interval: 1200; running: true; repeat: true; triggeredOnStart: true; onTriggered: musicPoller.running = true }

    // Real-time visualizer level — same fixed pattern TopBar's media pill
    // uses: a single RMS scalar sampled on a slow timer, animated purely via
    // the phase NumberAnimation below. No Behavior on the bar heights
    // themselves — that fights a value recomputed every frame and collapses
    // to near-static (learned the hard way in TopBar.qml).
    Timer {
        interval: 900
        running: window.isMediaActive && window.musicStatus === "Playing"
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!mediaAudioLevelProc.running) mediaAudioLevelProc.running = true
    }
    Process {
        id: mediaAudioLevelProc
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "$HOME/.config/hypr/scripts/quickshell/music/audio_level.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                let v = parseFloat(this.text.trim());
                if (!isNaN(v)) window.mediaAudioLevel = Math.max(0, Math.min(1, v));
            }
        }
    }
    onIsMediaActiveChanged: if (!window.isMediaActive) window.mediaAudioLevel = 0

    // -------------------------------------------------------------------------
    // AMBIENT ACCENT — same mauve→pink→blue cycle TopBar uses for its own
    // "alive" border echoes, so this drawer reads as part of the same lighting
    // system rather than a bolted-on screen.
    // -------------------------------------------------------------------------
    property color accentCycle: window.mauve
    SequentialAnimation on accentCycle {
        loops: Animation.Infinite
        ColorAnimation { to: window.pink; duration: 5200; easing.type: Easing.InOutSine }
        ColorAnimation { to: window.blue; duration: 5200; easing.type: Easing.InOutSine }
        ColorAnimation { to: window.mauve; duration: 5200; easing.type: Easing.InOutSine }
    }

    // -------------------------------------------------------------------------
    // LIQUID GROWTH — the panel is anchored flush to the true bottom/left/
    // right screen edges (set by WindowRegistry: rx:0, w:mw) with only the
    // top corners rounded. Instead of translating a fixed-size rectangle
    // (which reads as a floating card sliding up), its HEIGHT grows from 0
    // up out of the bottom edge with an elastic overshoot, so it reads as
    // the screen border itself bulging/melting outward. A thin highlight
    // line ripples into place along the new top edge shortly after, like a
    // liquid surface settling.
    // -------------------------------------------------------------------------
    Item {
        id: content
        anchors.fill: parent

        property real panelHeight: 0
        Component.onCompleted: growAnim.start()
        NumberAnimation {
            id: growAnim
            target: content; property: "panelHeight"
            from: 0; to: window.height
            duration: 620
            easing.type: Easing.OutBack
            easing.overshoot: 1.6
        }

        Rectangle {
            id: panel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: content.panelHeight
            topLeftRadius: window.s(28)
            topRightRadius: window.s(28)
            bottomLeftRadius: 0
            bottomRightRadius: 0
            color: window.base
            border.width: 1
            border.color: window.surface0
            clip: true

            // soft ambient glow bleeding from the bottom inner edge — the side
            // that faces into the screen, reinforcing the "grown out of the
            // bottom" read
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: window.s(120)
                opacity: 0.10
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: window.accentCycle }
                }
            }

            // liquid ripple — a row of soft highlight segments along the top
            // edge that rise into place with a staggered delay after the
            // sheet has mostly grown in, mimicking a liquid surface settling
            Row {
                id: ripple
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: window.s(3)
                spacing: 0

                Repeater {
                    model: 14
                    delegate: Rectangle {
                        width: ripple.width / 14
                        height: window.s(3)
                        radius: height / 2
                        color: window.accentCycle
                        opacity: 0
                        transform: Translate { id: segT; y: window.s(16) }

                        SequentialAnimation {
                            running: true
                            PauseAnimation { duration: 260 + index * 22 }
                            ParallelAnimation {
                                NumberAnimation { target: segT; property: "y"; to: 0; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                                SequentialAnimation {
                                    NumberAnimation { target: parent; property: "opacity"; to: 0.55; duration: 180 }
                                    NumberAnimation { target: parent; property: "opacity"; to: 0.0; duration: 900; easing.type: Easing.InQuad }
                                }
                            }
                        }
                    }
                }
            }

            // Header
            RowLayout {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: window.s(22)
                anchors.topMargin: window.s(16)

                Text {
                    text: "Quick Settings"
                    font.family: "JetBrains Mono"
                    font.weight: Font.Black
                    font.pixelSize: window.s(18)
                    color: window.text
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                }
                Item { Layout.fillWidth: true; Layout.minimumWidth: window.s(8) }
                Rectangle {
                    width: window.s(32); height: window.s(32); radius: window.s(16)
                    color: closeMa.containsMouse ? window.surface1 : "transparent"
                    border.color: window.surface1; border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text { anchors.centerIn: parent; text: "×"; font.pixelSize: window.s(16); color: window.subtext0 }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["bash", "-c", "echo close > /tmp/qs_widget_state"])
                    }
                }
            }

            // -----------------------------------------------------------------
            // DECK — every piece placed on a fixed 16px grid (window.gx(n)),
            // straight, snapped, non-overlapping — the exact coordinates from
            // the approved Control Deck layout, just wired to real state
            // instead of mock data.
            // -----------------------------------------------------------------
            Item {
                id: deck
                anchors.top: header.bottom
                anchors.topMargin: window.s(14)
                anchors.horizontalCenter: parent.horizontalCenter
                width: window.gx(52)
                height: window.gx(14)

                // ---- Volume knob ----
                DeckKnob {
                    x: window.gx(32); y: window.gx(0)
                    label: "Volume"
                    val: window.sysVolume
                    colA: window.blue
                    theme: window
                    onDragged: (v) => {
                        window.isDraggingVol = true;
                        volSyncDelay.restart();
                        window.sysVolume = v;
                        volCmdThrottle.targetPct = Math.round(v);
                        if (!volCmdThrottle.running) volCmdThrottle.start();
                    }
                }
                Timer {
                    id: volCmdThrottle
                    interval: 50
                    property int targetPct: -1
                    onTriggered: {
                        if (targetPct >= 0) {
                            if (targetPct > 0 && window.sysMuted) {
                                window.sysMuted = false;
                                Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"]);
                            }
                            Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", targetPct + "%"]);
                            targetPct = -1;
                        }
                    }
                }

                // ---- Mic gain knob ----
                DeckKnob {
                    x: window.gx(32); y: window.gx(5)
                    label: "Mic"
                    val: window.micGain
                    colA: window.green
                    theme: window
                    onDragged: (v) => {
                        window.isDraggingMic = true;
                        micSyncDelay.restart();
                        window.micGain = v;
                        micCmdThrottle.targetPct = Math.round(v);
                        if (!micCmdThrottle.running) micCmdThrottle.start();
                    }
                }
                Timer {
                    id: micCmdThrottle
                    interval: 50
                    property int targetPct: -1
                    onTriggered: {
                        if (targetPct >= 0) {
                            if (targetPct > 0 && window.micMuted) {
                                window.micMuted = false;
                                Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "0"]);
                            }
                            Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", targetPct + "%"]);
                            targetPct = -1;
                        }
                    }
                }

                // ---- Brightness knob ----
                DeckKnob {
                    x: window.gx(17); y: window.gx(0)
                    label: "Brightness"
                    val: window.sysBrightness
                    colA: window.yellow
                    theme: window
                    onDragged: (v) => {
                        window.isDraggingBri = true;
                        briSyncDelay.restart();
                        window.sysBrightness = v;
                        briCmdThrottle.targetPct = Math.max(1, Math.round(v));
                        if (!briCmdThrottle.running) briCmdThrottle.start();
                    }
                }
                Timer {
                    id: briCmdThrottle
                    interval: 50
                    property int targetPct: -1
                    onTriggered: { if (targetPct >= 0) { Quickshell.execDetached(["brightnessctl", "set", targetPct + "%"]); targetPct = -1; } }
                }

                // ---- Faders — same three real values, vertical duplicate ----
                Rectangle {
                    x: window.gx(12); y: window.gx(1)
                    width: window.gx(4) - window.s(4); height: window.gx(6) - window.s(4)
                    radius: window.s(8)
                    color: window.surface0
                    border.width: 1; border.color: window.surface1
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: window.s(7)
                        spacing: window.s(6)
                        DeckFader { Layout.fillWidth: true; Layout.fillHeight: true; val: window.sysBrightness; colTop: window.peach; colBottom: window.yellow; theme: window
                            onDragged: (v) => { window.isDraggingBri = true; briSyncDelay.restart(); window.sysBrightness = v; briCmdThrottle.targetPct = Math.max(1, Math.round(v)); if (!briCmdThrottle.running) briCmdThrottle.start(); } }
                        DeckFader { Layout.fillWidth: true; Layout.fillHeight: true; val: window.micGain; colTop: window.green; colBottom: window.teal; theme: window
                            onDragged: (v) => { window.isDraggingMic = true; micSyncDelay.restart(); window.micGain = v; micCmdThrottle.targetPct = Math.round(v); if (!micCmdThrottle.running) micCmdThrottle.start(); } }
                        DeckFader { Layout.fillWidth: true; Layout.fillHeight: true; val: window.sysVolume; colTop: window.blue; colBottom: window.sapphire; theme: window
                            onDragged: (v) => { window.isDraggingVol = true; volSyncDelay.restart(); window.sysVolume = v; volCmdThrottle.targetPct = Math.round(v); if (!volCmdThrottle.running) volCmdThrottle.start(); } }
                    }
                }

                // ---- Player ----
                Rectangle {
                    id: playerCard
                    x: window.gx(22); y: window.gx(1)
                    width: window.gx(10) - window.s(4); height: window.gx(7) - window.s(4)
                    radius: window.s(9)
                    color: window.surface0
                    border.width: 1; border.color: window.surface1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: window.s(10)
                        spacing: window.s(6)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: window.s(7)
                            Rectangle {
                                Layout.preferredWidth: window.s(26); Layout.preferredHeight: window.s(26)
                                radius: window.s(5)
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: window.mauve }
                                    GradientStop { position: 0.5; color: window.blue }
                                    GradientStop { position: 1.0; color: window.peach }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 0
                                Text { text: window.musicTitle; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11); color: window.text; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: window.musicArtist + (window.musicBpm > 0 ? (" · " + window.musicBpm + "bpm") : ""); font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                        }

                        Row {
                            id: vizRow
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: window.s(2)
                            opacity: window.musicStatus === "Playing" ? 0.85 : 0.25
                            Behavior on opacity { NumberAnimation { duration: 400 } }

                            property real phase: 0
                            NumberAnimation on phase { from: 0; to: Math.PI * 2; duration: 3200; loops: Animation.Infinite; running: vizRow.parent !== null }

                            Repeater {
                                model: 14
                                delegate: Rectangle {
                                    width: (vizRow.width - window.s(2) * 13) / 14
                                    anchors.bottom: parent.bottom
                                    radius: width / 2
                                    height: window.s(3) + ((vizRow.height - window.s(3)) * Math.sqrt(window.mediaAudioLevel) *
                                        (0.35 + 0.65 * Math.abs(Math.sin(vizRow.phase * (1.0 + (index % 4) * 0.35) + index * 0.9))))
                                    gradient: Gradient {
                                        orientation: Gradient.Vertical
                                        GradientStop { position: 0.0; color: window.mauve }
                                        GradientStop { position: 1.0; color: window.blue }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            spacing: window.s(10)
                            Text { text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.subtext0
                                MouseArea { anchors.fill: parent; anchors.margins: -window.s(6); cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["playerctl", "previous"]) } }
                            Rectangle {
                                width: window.s(24); height: window.s(24); radius: width / 2
                                color: window.pink
                                Text { anchors.centerIn: parent; text: window.musicStatus === "Playing" ? "" : ""; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(11); color: "#22101d" }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["playerctl", "play-pause"]) }
                            }
                            Text { text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.subtext0
                                MouseArea { anchors.fill: parent; anchors.margins: -window.s(6); cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["playerctl", "next"]) } }
                        }
                    }
                }

                // ---- Console — cpu / battery / kandor ----
                Rectangle {
                    x: window.gx(38); y: window.gx(1)
                    width: window.gx(8) - window.s(4); height: window.gx(6) - window.s(4)
                    radius: window.s(8)
                    color: "#050805"
                    border.width: 1; border.color: "#123018"
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: window.s(8)
                        spacing: window.s(4)
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "LOG"; font.family: "Share Tech Mono"; font.pixelSize: window.s(9); color: "#4fdc7a" }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                width: window.s(4); height: window.s(4); radius: width/2; color: "#4fdc7a"
                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.15; duration: 600 }
                                    NumberAnimation { to: 1.0; duration: 600 }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                        RowLayout { Layout.fillWidth: true
                            Text { text: "cpu"; font.family: "Share Tech Mono"; font.pixelSize: window.s(10); color: "#3f8a5c"; Layout.fillWidth: true }
                            Text { text: window.cpuPct + "%"; font.family: "Share Tech Mono"; font.pixelSize: window.s(10); color: "#baffce" }
                        }
                        RowLayout { Layout.fillWidth: true
                            Text { text: "batt"; font.family: "Share Tech Mono"; font.pixelSize: window.s(10); color: "#3f8a5c"; Layout.fillWidth: true }
                            Text { text: window.batteryPercent + "%"; font.family: "Share Tech Mono"; font.pixelSize: window.s(10); color: "#baffce" }
                        }
                        RowLayout { Layout.fillWidth: true
                            Text { text: "kandor"; font.family: "Share Tech Mono"; font.pixelSize: window.s(10); color: "#3f8a5c"; Layout.fillWidth: true }
                            Text { text: window.kandorEnabled ? "on" : "off"; font.family: "Share Tech Mono"; font.pixelSize: window.s(10); color: "#baffce" }
                        }
                    }
                }

                // ---- Switch bank — Wi-Fi / Bluetooth / DND / Night Light ----
                Rectangle {
                    x: window.gx(38); y: window.gx(7)
                    width: window.gx(7) - window.s(4); height: window.gx(7) - window.s(4)
                    radius: window.s(8)
                    color: window.surface0
                    border.width: 1; border.color: window.surface1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: window.s(9)
                        DeckSwitchRow { label: "Wi-Fi"; active: window.wifiPower === "on"; accent: window.blue; theme: window
                            onToggled: { window.wifiPending = true; window.wifiPower = window.wifiPower === "on" ? "off" : "on"; Quickshell.execDetached(["nmcli", "radio", "wifi", window.wifiPower]); wifiPendingReset.restart(); } }
                        DeckSwitchRow { label: "Bluetooth"; active: window.btPower === "on"; accent: window.sapphire; theme: window
                            onToggled: { window.btPending = true; window.btPower = window.btPower === "on" ? "off" : "on"; Quickshell.execDetached(["bash", window.networkScriptsDir + "/bluetooth_panel_logic.sh", "--toggle"]); btPendingReset.restart(); } }
                        DeckSwitchRow { label: "DND"; active: window.dndOn; accent: window.mauve; theme: window
                            onToggled: { window.dndOn = !window.dndOn; Quickshell.execDetached(["swaync-client", "-d"]); } }
                        DeckSwitchRow { label: "Night Light"; active: window.nlMode === "on"; accent: window.peach; theme: window
                            onToggled: Quickshell.execDetached(["bash", window.scriptsDir + "/toggle_night_light.sh"]) }
                    }
                }

                // ---- Weather ----
                Rectangle {
                    x: window.gx(23); y: window.gx(8)
                    width: window.gx(7) - window.s(4); height: window.gx(4) - window.s(4)
                    radius: window.s(8)
                    color: window.surface0
                    border.width: 1; border.color: window.surface1
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: window.s(9)
                        spacing: window.s(6)
                        Text { text: window.weatherIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(20); color: window.accentCycle }
                        ColumnLayout { spacing: 0
                            Text { text: window.weatherTemp + "°"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(15); color: window.text }
                            Text { text: window.weatherDesc; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.subtext0; elide: Text.ElideRight }
                        }
                    }
                }

                // ---- Spinner — decorative flourish, no backend, physically fun ----
                Item {
                    id: spinnerItem
                    x: window.gx(18); y: window.gx(5)
                    width: window.gx(3) - window.s(4); height: window.gx(3) - window.s(4)
                    property real angle: 0
                    property real velocity: 0
                    property real lastAngle: 0
                    property real lastTime: 0
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: window.surface0
                        border.width: 1; border.color: window.surface1
                    }
                    Item {
                        anchors.centerIn: parent
                        width: parent.width * 0.72; height: parent.height * 0.72
                        rotation: spinnerItem.angle
                        Repeater {
                            model: [
                                { deg: 90, col: window.mauve },
                                { deg: 210, col: window.blue },
                                { deg: 330, col: window.pink }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: parent.width * 0.36; height: width; radius: width / 2
                                color: modelData.col
                                x: parent.width / 2 - width / 2 + (parent.width / 2 - width / 2) * Math.cos(modelData.deg * Math.PI / 180)
                                y: parent.height / 2 - height / 2 + (parent.height / 2 - height / 2) * Math.sin(modelData.deg * Math.PI / 180)
                            }
                        }
                        Rectangle { anchors.centerIn: parent; width: parent.width * 0.22; height: width; radius: width / 2; color: window.text }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onPressed: (mouse) => { spinnerItem.lastAngle = Math.atan2(mouse.y - height/2, mouse.x - width/2) * 180 / Math.PI; spinnerItem.lastTime = Date.now(); }
                        onPositionChanged: (mouse) => {
                            if (!pressed) return;
                            let a = Math.atan2(mouse.y - height/2, mouse.x - width/2) * 180 / Math.PI;
                            let now = Date.now();
                            let diff = a - spinnerItem.lastAngle;
                            if (diff > 180) diff -= 360; if (diff < -180) diff += 360;
                            spinnerItem.angle += diff;
                            spinnerItem.velocity = diff / Math.max(1, now - spinnerItem.lastTime) * 16;
                            spinnerItem.lastAngle = a; spinnerItem.lastTime = now;
                        }
                    }
                    Timer {
                        interval: 16; running: true; repeat: true
                        onTriggered: {
                            if (Math.abs(spinnerItem.velocity) > 0.02) {
                                spinnerItem.angle += spinnerItem.velocity;
                                spinnerItem.velocity *= 0.97;
                            }
                        }
                    }
                }

                // ---- Levers — power profile select ----
                Repeater {
                    model: [
                        { key: "power-saver", gxv: 32, glyph: "" },
                        { key: "balanced", gxv: 34, glyph: "" },
                        { key: "performance", gxv: 36, glyph: "" }
                    ]
                    delegate: Item {
                        required property var modelData
                        x: window.gx(modelData.gxv); y: window.gx(10)
                        width: window.gx(2) - window.s(4); height: window.gx(3) - window.s(4)
                        property bool engaged: window.powerProfile === modelData.key
                        Rectangle {
                            anchors.fill: parent
                            radius: window.s(4)
                            color: window.surface1
                            border.width: 1; border.color: window.surface2
                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.leftMargin: parent.width * 0.5 - window.s(1)
                                anchors.rightMargin: parent.width * 0.5 - window.s(1)
                                anchors.top: parent.top; anchors.bottom: parent.bottom
                                anchors.topMargin: window.s(3); anchors.bottomMargin: window.s(3)
                                color: window.surface2
                            }
                            Rectangle {
                                width: parent.width - window.s(4); height: window.s(9)
                                radius: window.s(3)
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: engaged ? parent.height - height - window.s(3) : window.s(3)
                                Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                                gradient: Gradient {
                                    orientation: Gradient.Vertical
                                    GradientStop { position: 0.0; color: window.surface2 }
                                    GradientStop { position: 1.0; color: window.mantle }
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!engaged) {
                                    window.powerProfile = modelData.key;
                                    Quickshell.execDetached(["powerprofilesctl", "set", modelData.key]);
                                }
                            }
                        }
                    }
                }

                // ---- Quick actions ----
                DeckQaIcon {
                    x: window.gx(16); y: window.gx(8)
                    width: window.gx(3) - window.s(4); height: window.gx(3) - window.s(4)
                    glyph: String.fromCharCode(0xf030); title: "Screenshot"; theme: window
                    onActivated: Quickshell.execDetached(["bash", window.scriptsDir + "/screenshot.sh"])
                }
                DeckQaIcon {
                    x: window.gx(19); y: window.gx(8)
                    width: window.gx(3) - window.s(4); height: window.gx(3) - window.s(4)
                    glyph: "󰌾"; title: "Lock"; theme: window
                    onActivated: Quickshell.execDetached(["bash", window.scriptsDir + "/lock.sh"])
                }
                DeckQaIcon {
                    x: window.gx(19); y: window.gx(11)
                    width: window.gx(3) - window.s(4); height: window.gx(3) - window.s(4)
                    glyph: window.micMuted ? "󰍭" : "󰍬"; title: "Mute Mic"; theme: window
                    onActivated: Quickshell.execDetached(["bash", "-c", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"])
                }
                DeckQaIcon {
                    x: window.gx(16); y: window.gx(11)
                    width: window.gx(3) - window.s(4); height: window.gx(3) - window.s(4)
                    glyph: "󰒲"; title: "Toggle Idle Lock"; theme: window
                    onActivated: Quickshell.execDetached(["bash", window.scriptsDir + "/toggle_hypridle.sh"])
                }

                // ---- Panic button — flip cover, then confirm: locks the screen ----
                Item {
                    id: panicItem
                    x: window.gx(12); y: window.gx(8)
                    width: window.gx(3) - window.s(4); height: window.gx(3) - window.s(4)
                    property bool open: false
                    Timer { id: panicCloseTimer; interval: 5000; onTriggered: panicItem.open = false }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#ff9fb0" }
                            GradientStop { position: 1.0; color: window.red }
                        }
                        border.width: 2; border.color: "#7a1f34"
                    }
                    Rectangle {
                        id: panicCover
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: width / 2
                        color: window.surface1
                        border.width: 1; border.color: window.surface2
                        transform: Rotation {
                            id: coverRot
                            origin.x: panicCover.width / 2
                            origin.y: panicCover.height
                            axis: Qt.vector3d(1, 0, 0)
                            angle: panicItem.open ? -125 : 0
                            Behavior on angle { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                        }
                        Text { anchors.centerIn: parent; text: "⚠"; color: window.overlay1; font.pixelSize: window.s(13) }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!panicItem.open) { panicItem.open = true; panicCloseTimer.restart(); }
                                else { panicItem.open = false; panicCloseTimer.stop(); Quickshell.execDetached(["bash", window.scriptsDir + "/lock.sh"]); }
                            }
                        }
                    }
                }

                // ---- Keycaps — workspace 1 / 2 / 3 ----
                Repeater {
                    model: [1, 2, 3]
                    delegate: DeckKeycap {
                        required property int modelData
                        required property int index
                        x: window.gx(23 + index * 3); y: window.gx(12)
                        width: window.gx(2) - window.s(4); height: window.gx(2) - window.s(4)
                        glyph: String(modelData)
                        theme: window
                        onActivated: Quickshell.execDetached(["hyprctl", "dispatch", "workspace", String(modelData)])
                    }
                }
            }
        }
    }
}
