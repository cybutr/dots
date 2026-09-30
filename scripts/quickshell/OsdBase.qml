import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./"

// Shared on-screen-display shell. One file watch, one hide timer, and an
// opacity that is a *pure function* of a single `shown` bool — so it can never
// wedge "stuck on": the only thing that sets shown=true is a fresh trigger,
// the only thing that sets it false is the hide timer (or a hot-reload reset).
PanelWindow {
    id: root
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    mask: Region { }
    width: Screen.width
    height: Screen.height
    visible: osdOpacity > 0.001

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val) }

    MatugenColors { id: _theme }
    // re-export so subclasses (which can't see the child id) can read colors
    readonly property color cText: _theme.text
    readonly property color cSubtext0: _theme.subtext0
    readonly property color cMantle: _theme.mantle
    readonly property color cMauve: _theme.mauve || "#cba6f7"
    readonly property color cBlue: _theme.blue || "#89b4fa"
    readonly property color cGreen: _theme.green || "#a6e3a1"
    readonly property color cRed: _theme.red || "#f38ba8"
    readonly property color cPeach: _theme.peach || "#fab387"

    // --- config supplied by each concrete OSD ---
    property string watchFile: ""
    property int holdMs: 1400
    property color accent: _theme.text
    default property alias body: bodyHolder.data

    // Opt-in chrome upgrades — default false so every existing OSD (volume,
    // brightness, mic, etc.) stays pixel-identical unless it opts in.
    property bool springEntrance: false
    property bool breathingBorder: false

    // payload of the last trigger (raw file contents, trimmed) for the OSD to parse
    property string payload: ""
    signal triggered(string text)

    // --- the one source of truth ---
    property bool shown: false
    property real osdOpacity: shown ? 1.0 : 0.0
    Behavior on osdOpacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

    Timer {
        id: hideTimer
        interval: root.holdMs
        repeat: false
        onTriggered: root.shown = false
    }

    function flash(text) {
        root.payload = text
        root.triggered(text)
        root.shown = true
        hideTimer.restart()
    }

    // --- IPC: one persistent monitor emits the file's contents on each write ---
    // A single long-lived `inotifywait -m` (no re-arm) + `cat` per event. The old
    // re-arm-on-exit pattern busy-looped (watcher's own touch re-triggered itself),
    // which is exactly why the OSD got stuck on until another widget opened.
    Process {
        id: watcher
        running: root.watchFile !== ""
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
            "f='" + root.watchFile + "'; [ -e \"$f\" ] || touch \"$f\"; " +
            "inotifywait -m -q -e close_write --format '%w' \"$f\" | " +
            "while read -r _; do cat \"$f\"; echo; done"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                let t = (line || "").trim()
                if (t.length) root.flash(t)
            }
        }
    }

    // Spring-in scale — only animated when springEntrance is set, otherwise
    // pinned at 1.0 so non-opted-in OSDs never see a scale transform.
    property real osdScale: springEntrance ? (shown ? 1.0 : 0.82) : 1.0
    Behavior on osdScale {
        enabled: root.springEntrance
        NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.35 }
    }

    // Ambient breathing phase for breathingBorder — only ticks while a
    // breathingBorder-opted OSD is actually visible, otherwise idle.
    property real borderPhase: 0
    Timer {
        interval: 50; repeat: true
        running: root.breathingBorder && root.shown
        onTriggered: root.borderPhase += 0.05
    }
    readonly property real borderBreathe: 0.5 + 0.5 * Math.sin(borderPhase * 2.1)

    // --- chrome: centered pill near the bottom ---
    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.s(80)
        width: bodyHolder.childrenRect.width + root.s(36)
        height: Math.max(root.s(54), bodyHolder.childrenRect.height + root.s(24))
        radius: root.s(14)
        color: root.cMantle
        opacity: root.osdOpacity
        scale: root.osdScale
        transformOrigin: Item.Center
        border.width: root.breathingBorder ? root.s(1.2 + 0.9 * root.borderBreathe) : 1
        border.color: root.breathingBorder
            ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.30 + 0.35 * root.borderBreathe)
            : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: root.accent
            opacity: 0.07
        }

        // Faint top highlight line — matches the hover-card flush-top
        // vocabulary used elsewhere in the bar (TopBar.qml's HoverCard).
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            height: 1
            radius: parent.radius
            color: Qt.rgba(1, 1, 1, 0.10)
        }

        Item {
            id: bodyHolder
            anchors.centerIn: parent
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }
}
