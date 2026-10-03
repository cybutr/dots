import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root
    color: "transparent"
    WlrLayershell.namespace: "qs-presenter-fx"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    width: Screen.width
    height: Screen.height
    visible: presenterOn

    // Fully click-through — nothing here is ever hit-testable, the whole
    // point of this window is to paint over everything without stealing
    // any pointer/keyboard input from whatever's underneath.
    mask: Region {
        item: noHit
    }

    Item {
        id: noHit
        x: 0
        y: 0
        width: 0
        height: 0
    }

    readonly property color accent: "#89dceb"

    property bool presenterOn: false
    property string presenterMode: "border"
    readonly property bool showBorder: presenterOn && (presenterMode === "border" || presenterMode === "both")
    readonly property bool showSpotlight: presenterOn && (presenterMode === "spotlight" || presenterMode === "both")

    property real cursorX: width / 2
    property real cursorY: height / 2

    property real slowT: 0
    Timer {
        interval: 16
        running: root.showBorder
        repeat: true
        onTriggered: root.slowT += 16
    }
    readonly property real breathWave: (slowT % 4000) / 4000
    function ambientBreath(phase) {
        return 0.5 + 0.5 * Math.sin((breathWave + phase) * Math.PI * 2)
    }

    Item {
        id: borderFx
        anchors.fill: parent
        visible: root.showBorder
        opacity: visible ? 1 : 0

        readonly property real glow: root.ambientBreath(0)
        readonly property real th: 3 + glow * 3

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: borderFx.th
            color: root.accent
            opacity: 0.35 + borderFx.glow * 0.45
        }
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: borderFx.th
            color: root.accent
            opacity: 0.35 + borderFx.glow * 0.45
        }
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: borderFx.th
            color: root.accent
            opacity: 0.35 + borderFx.glow * 0.45
        }
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: borderFx.th
            color: root.accent
            opacity: 0.35 + borderFx.glow * 0.45
        }
    }

    Item {
        id: spotlightFx
        anchors.fill: parent
        visible: root.showSpotlight

        Rectangle {
            id: glowCircle
            width: 180
            height: 180
            radius: width / 2
            color: "transparent"
            border.width: 10
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
            x: root.cursorX - width / 2
            y: root.cursorY - height / 2

            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.6
                height: width
                radius: width / 2
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)
            }
        }
    }

    Process {
        id: cursorPoller
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let p = JSON.parse(this.text.trim());
                    if (typeof p.x === "number" && typeof p.y === "number") {
                        root.cursorX = p.x;
                        root.cursorY = p.y;
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 120
        running: root.showSpotlight
        repeat: true
        onTriggered: {
            if (!cursorPoller.running) cursorPoller.running = true;
        }
    }

    function applyState(obj) {
        if (!obj) return;
        presenterOn = !!obj.on;
        let m = obj.mode || "border";
        if (m === "border" || m === "spotlight" || m === "both") presenterMode = m;
    }

    Process {
        id: stateWatcher
        running: true
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "touch /tmp/qs_presenter_mode; exec inotifywait -qq -e close_write /tmp/qs_presenter_mode"]
        onExited: {
            statePoller.running = true;
            running = true;
        }
    }

    Process {
        id: statePoller
        command: ["bash", "-c", "cat /tmp/qs_presenter_mode 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let text = this.text.trim();
                if (text === "") return;
                try {
                    root.applyState(JSON.parse(text));
                } catch (e) {}
            }
        }
    }

    Component.onCompleted: {
        statePoller.running = true;
    }
}
