import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./"

// Full-screen, always-click-through ambient edge glow — one instance per
// monitor. Purely decorative: a soft bezel of color bleeding in from each
// screen edge, cycling through the mauve/pink/blue trio (or a fixed color,
// or the current track's album art color) and pulsing gently to the
// current track's BPM. Runs as an independent process (can't read other
// QML processes' internal properties) but reads the exact same underlying
// data — /tmp/music_info.json (bpm/status/grad) and settings.json's
// ambientGlow* keys — so it stays visually consistent without any
// cross-process synchronization.
//
// NOTE on ambientGlowEnabled vs topBarAccentLine: this is a dedicated
// master toggle, deliberately separate from the bar's own accent-line
// setting. They're visually related (same palette, same "ambient lighting"
// idea) but materially different features — one's a full-screen bezel,
// the other's a slim line under the bar — so a user may want one without
// the other. Falls back to topBarAccentLine if ambientGlowEnabled is
// missing from settings.json (older config), so nothing silently breaks
// on upgrade.
Variants {
    model: Quickshell.screens

    delegate: Component {
        PanelWindow {
            id: glowWindow

            required property var modelData
            screen: modelData

            color: "transparent"
            WlrLayershell.namespace: "qs-ambient-glow"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            focusable: false

            anchors { top: true; bottom: true; left: true; right: true }

            // Zero-size hit item — this window is NEVER clickable anywhere,
            // same "hole" idiom BatteryAlarm.qml uses for its own full-screen
            // click-through surface, just with no exceptions carved out.
            mask: Region { item: noHit }
            Item { id: noHit; width: 0; height: 0 }

            visible: glowWindow.glowActive

            Scaler { id: scaler; currentWidth: Screen.width }
            function s(val) { return scaler.s(val); }

            MatugenColors { id: _theme }
            readonly property color mauve: _theme.mauve
            readonly property color pink: _theme.pink
            readonly property color blue: _theme.blue

            // -----------------------------------------------------------
            // Config — read from settings.json, hot-reloaded via the same
            // cat + inotifywait pattern used everywhere else in this repo.
            // -----------------------------------------------------------
            property bool enabled: true
            property real cfgIntensity: 1.0
            property int cfgSpread: 140
            property bool cfgEdgeTop: true
            property bool cfgEdgeBottom: true
            property bool cfgEdgeLeft: true
            property bool cfgEdgeRight: true
            property string cfgColorMode: "cycle"       // "cycle" | "fixed" | "album"
            property color cfgFixedColor: "#cba6f7"
            property bool cfgBeatReactive: true
            property int cfgCycleSpeedMs: 5200
            property string cfgIdleBehavior: "dim"      // "dim" | "fadeOut"

            function applySettings(parsed) {
                if (parsed.ambientGlowEnabled !== undefined) glowWindow.enabled = parsed.ambientGlowEnabled;
                else if (parsed.topBarAccentLine !== undefined) glowWindow.enabled = parsed.topBarAccentLine;

                if (parsed.ambientGlowIntensity !== undefined) glowWindow.cfgIntensity = parsed.ambientGlowIntensity;
                if (parsed.ambientGlowSpread !== undefined) glowWindow.cfgSpread = parsed.ambientGlowSpread;
                if (parsed.ambientGlowEdgeTop !== undefined) glowWindow.cfgEdgeTop = parsed.ambientGlowEdgeTop;
                if (parsed.ambientGlowEdgeBottom !== undefined) glowWindow.cfgEdgeBottom = parsed.ambientGlowEdgeBottom;
                if (parsed.ambientGlowEdgeLeft !== undefined) glowWindow.cfgEdgeLeft = parsed.ambientGlowEdgeLeft;
                if (parsed.ambientGlowEdgeRight !== undefined) glowWindow.cfgEdgeRight = parsed.ambientGlowEdgeRight;
                if (parsed.ambientGlowColorMode !== undefined) glowWindow.cfgColorMode = parsed.ambientGlowColorMode;
                if (parsed.ambientGlowFixedColor !== undefined) glowWindow.cfgFixedColor = parsed.ambientGlowFixedColor;
                if (parsed.ambientGlowBeatReactive !== undefined) glowWindow.cfgBeatReactive = parsed.ambientGlowBeatReactive;
                if (parsed.ambientGlowCycleSpeedMs !== undefined) glowWindow.cfgCycleSpeedMs = parsed.ambientGlowCycleSpeedMs;
                if (parsed.ambientGlowIdleBehavior !== undefined) glowWindow.cfgIdleBehavior = parsed.ambientGlowIdleBehavior;
            }

            Process {
                id: settingsReader
                command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            glowWindow.applySettings(JSON.parse(this.text.trim() || "{}"));
                        } catch (e) {}
                    }
                }
            }
            Process {
                id: settingsWatcher
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "while [ ! -f ~/.config/hypr/settings.json ]; do sleep 1; done; exec inotifywait -qq -e modify,close_write ~/.config/hypr/settings.json"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        settingsReader.running = false; settingsReader.running = true;
                        settingsWatcher.running = false; settingsWatcher.running = true;
                    }
                }
            }

            // -----------------------------------------------------------
            // Beat/color source — same file TopBar.qml's media box already
            // reads (music_info.sh output), polled cheaply on its own
            // timer rather than synchronized cross-process. `grad` is the
            // same quantized-album-art gradient string the media pill's
            // background uses — its first stop is the track's dominant
            // color, reused here for "album" color mode.
            // -----------------------------------------------------------
            property real bpm: 0
            property bool playing: false
            property color albumColor: glowWindow.mauve
            Process {
                id: musicPoller
                command: ["bash", "-c", "cat /tmp/music_info.json 2>/dev/null || echo '{}'"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            let d = JSON.parse(this.text.trim() || "{}");
                            glowWindow.bpm = d.bpm || 0;
                            glowWindow.playing = d.status === "Playing";
                            if (d.grad) {
                                let m = /#([0-9A-Fa-f]{6})/.exec(d.grad);
                                if (m) glowWindow.albumColor = "#" + m[1];
                            }
                        } catch (e) {}
                    }
                }
            }
            Timer { interval: 2000; running: true; repeat: true; onTriggered: musicPoller.running = true }

            readonly property real beatIntervalMs: (glowWindow.playing && glowWindow.bpm >= 40 && glowWindow.bpm <= 220) ? (60000.0 / glowWindow.bpm) : 5200

            property real beatPulse: 0
            SequentialAnimation {
                loops: Animation.Infinite
                running: glowWindow.glowActive && glowWindow.cfgBeatReactive
                NumberAnimation { target: glowWindow; property: "beatPulse"; to: 1.0; duration: Math.max(120, glowWindow.beatIntervalMs * (glowWindow.playing ? 0.32 : 0.5)); easing.type: glowWindow.playing ? Easing.OutCubic : Easing.InOutSine }
                NumberAnimation { target: glowWindow; property: "beatPulse"; to: 0.0; duration: Math.max(180, glowWindow.beatIntervalMs * (glowWindow.playing ? 0.68 : 0.5)); easing.type: glowWindow.playing ? Easing.InCubic : Easing.InOutSine }
            }
            // when beat-reactivity is switched off mid-pulse, relax back to zero
            // instead of freezing wherever the animation last left it
            Behavior on beatPulse { enabled: !glowWindow.cfgBeatReactive; NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }
            readonly property real effectiveBeatPulse: glowWindow.cfgBeatReactive ? glowWindow.beatPulse : 0.0

            // Base mauve → pink → blue → mauve cycle, used directly in "cycle"
            // mode and as the idle fallback in "album" mode when nothing is
            // playing (no album art color to pull from).
            property color cycleColor: glowWindow.mauve
            SequentialAnimation on cycleColor {
                loops: Animation.Infinite
                running: glowWindow.glowActive && (glowWindow.cfgColorMode === "cycle" || (glowWindow.cfgColorMode === "album" && !glowWindow.playing))
                ColorAnimation { to: glowWindow.pink; duration: glowWindow.cfgCycleSpeedMs; easing.type: Easing.InOutSine }
                ColorAnimation { to: glowWindow.blue; duration: glowWindow.cfgCycleSpeedMs; easing.type: Easing.InOutSine }
                ColorAnimation { to: glowWindow.mauve; duration: glowWindow.cfgCycleSpeedMs; easing.type: Easing.InOutSine }
            }

            property color renderColor: {
                if (glowWindow.cfgColorMode === "fixed") return glowWindow.cfgFixedColor;
                if (glowWindow.cfgColorMode === "album") return glowWindow.playing ? glowWindow.albumColor : glowWindow.cycleColor;
                return glowWindow.cycleColor;
            }
            Behavior on renderColor { ColorAnimation { duration: 900; easing.type: Easing.InOutSine } }

            // Idle behavior — "dim" keeps the ambient cycle running at all
            // times (original behavior); "fadeOut" smoothly hides the glow
            // entirely whenever nothing is playing.
            property real idleFade: (glowWindow.cfgIdleBehavior === "fadeOut" && !glowWindow.playing) ? 0.0 : 1.0
            readonly property bool glowActive: glowWindow.enabled && (glowWindow.cfgIdleBehavior !== "fadeOut" || glowWindow.playing || glowWindow.idleFade > 0.01)
            Behavior on idleFade { NumberAnimation { duration: 1200; easing.type: Easing.InOutSine } }

            // Base + pulse opacity — deliberately very subtle, a bezel, not
            // a border. Scaled by user intensity and idle fade; never rises
            // above ~0.10 * intensity even at full beat pulse.
            readonly property real edgeOpacity: (0.035 + glowWindow.effectiveBeatPulse * 0.045) * glowWindow.cfgIntensity * glowWindow.idleFade

            // Four soft edge bleeds — plain colored Rectangles with a
            // gradient fade inward, not MultiEffect blur (unreliable in
            // quickshell-git per repo convention). Each independently
            // toggleable via cfgEdge*.
            Rectangle {
                visible: glowWindow.cfgEdgeTop
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                height: glowWindow.s(glowWindow.cfgSpread)
                opacity: glowWindow.edgeOpacity
                gradient: Gradient {
                    GradientStop { position: 0.0; color: glowWindow.renderColor }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Rectangle {
                visible: glowWindow.cfgEdgeBottom
                anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                height: glowWindow.s(glowWindow.cfgSpread)
                opacity: glowWindow.edgeOpacity
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: glowWindow.renderColor }
                }
            }
            Rectangle {
                visible: glowWindow.cfgEdgeLeft
                anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
                width: glowWindow.s(glowWindow.cfgSpread)
                opacity: glowWindow.edgeOpacity
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: glowWindow.renderColor }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Rectangle {
                visible: glowWindow.cfgEdgeRight
                anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right
                width: glowWindow.s(glowWindow.cfgSpread)
                opacity: glowWindow.edgeOpacity
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: glowWindow.renderColor }
                }
            }
        }
    }
}
