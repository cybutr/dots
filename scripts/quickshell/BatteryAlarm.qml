import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./"

PanelWindow {
    id: root
    color: "transparent"
    WlrLayershell.namespace: "qs-battery-alarm"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    width: Screen.width
    height: Screen.height
    visible: alarmVisible

    // Only the card's own rect (plus a small margin) is hit-testable — everything
    // else on screen stays fully clickable while the alarm is up. Without this a
    // full-screen PanelWindow eats all pointer input by default under wlr-layer-shell,
    // even though only the small card is actually painted. Same idea as the
    // activeWidgetHole pattern in Main.qml.
    mask: Region {
        item: hitArea
    }

    Item {
        id: hitArea
        x: alertCard.x - root.s(10)
        y: alertCard.y - root.s(10)
        width: root.alarmVisible ? alertCard.width + root.s(20) : 0
        height: root.alarmVisible ? alertCard.height + root.s(20) : 0
    }

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val) }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1

    property int batCapacity: 100
    property string batStatus: "Unknown"
    property bool isCharging: batStatus === "Charging"
    property bool alarmVisible: false
    property int activeAlarmLevel: 0

    property bool notified30: false
    property bool notified20: false
    property bool notified10: false

    // "integrated" (default) — the topbar battery pill itself flashes via
    // the resident pill-takeover mechanism instead of this full-screen card.
    // "popup" — old behavior, this card shows exactly as before.
    property string alertStyle: "integrated"
    Process {
        id: alertStyleReader
        command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let parsed = JSON.parse(this.text || "{}")
                    if (parsed.batteryAlertStyle !== undefined) root.alertStyle = parsed.batteryAlertStyle
                } catch (e) {}
            }
        }
    }
    Process {
        id: alertStyleWatcher
        running: true
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "while [ ! -f ~/.config/hypr/settings.json ]; do sleep 1; done; exec inotifywait -qq -e modify,close_write ~/.config/hypr/settings.json"]
        onExited: { alertStyleReader.running = true; running = true }
    }

    // Fires the topbar pill takeover instead of the full-screen card — same
    // fixed-hex accents/icons as levelAccent/levelIcon above, so the color
    // language stays identical between popup and integrated styles.
    function fireIntegrated(lvl) {
        let urgency = lvl === 2 ? "high" : (lvl === 1 ? "normal" : "low")
        let style = lvl === 2 ? "border" : "wash"
        let ttl = lvl === 2 ? 900 : (lvl === 1 ? 600 : 360)
        Quickshell.execDetached(["python3", "/home/czeddaru/.config/hypr/scripts/quickshell/claude/resident_card.py",
            "--pill", "battery", "--tint", root.levelAccent(lvl), "--urgency", urgency,
            "--style", style, "--ttl", String(ttl)])
    }

    // Fixed semantic accents — never matugen, urgency must read the same on any wallpaper
    function levelAccent(lvl) { return lvl === 3 ? "#f9a825" : lvl === 1 ? "#fb8500" : lvl === 2 ? "#f38ba8" : "#89b4fa" }
    function levelIcon(lvl) { return lvl === 3 ? "󰂁" : lvl === 1 ? "󰂃" : lvl === 2 ? "󰂃" : "󰂀" }
    function levelLabel(lvl) { return lvl === 3 ? "BATTERY" : lvl === 1 ? "BATTERY LOW" : lvl === 2 ? "BATTERY CRITICAL" : "" }
    function levelSub(lvl) { return lvl === 3 ? "Consider plugging in" : lvl === 1 ? "Plug in soon" : lvl === 2 ? "Plug in now" : "" }
    function levelPulseMax(lvl) { return lvl === 3 ? 0.30 : lvl === 1 ? 0.45 : lvl === 2 ? 0.65 : 0.25 }

    readonly property color accent: levelAccent(activeAlarmLevel)

    property real pulse: 0.0
    SequentialAnimation on pulse {
        loops: Animation.Infinite
        running: root.alarmVisible
        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.0; duration: 700; easing.type: Easing.InOutSine }
    }

    property real drainPhase: 0.0
    SequentialAnimation on drainPhase {
        loops: Animation.Infinite
        running: root.alarmVisible
        NumberAnimation { to: 1.0; duration: 1400; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0.0; duration: 0 }
    }

    onIsChargingChanged: {
        if (!isCharging) return
        notified30 = false
        notified20 = false
        notified10 = false
        if (batCapacity > 20) {
            alarmVisible = false
            activeAlarmLevel = 0
        }
    }

    Process {
        id: batPoller
        running: true
        command: ["bash", "-c",
            "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1 || echo '100'; " +
            "cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1 || echo 'Unknown'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n")
                if (lines.length >= 2) {
                    root.batCapacity = parseInt(lines[0]) || 100
                    root.batStatus = lines[1].trim()
                }
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: batPoller.running = true
    }

    Process {
        id: testWatcher
        running: true
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "touch /tmp/qs_alarm_test; exec inotifywait -qq -e close_write /tmp/qs_alarm_test"]
        onExited: {
            testPoller.running = true
            running = true
        }
    }

    Process {
        id: testPoller
        command: ["bash", "-c", "cat /tmp/qs_alarm_test 2>/dev/null && echo '' > /tmp/qs_alarm_test"]
        stdout: StdioCollector {
            onStreamFinished: {
                let cmd = this.text.trim()
                if (cmd === "3" || cmd === "1" || cmd === "2") {
                    let lvl = parseInt(cmd)
                    if (root.alertStyle === "popup") {
                        root.activeAlarmLevel = lvl
                        root.alarmVisible = true
                    } else {
                        root.fireIntegrated(lvl)
                    }
                } else if (cmd === "0") {
                    root.alarmVisible = false
                    root.activeAlarmLevel = 0
                }
            }
        }
    }

    onBatCapacityChanged: checkThresholds()
    onBatStatusChanged: checkThresholds()

    function checkThresholds() {
        if (isCharging) return
        if (batCapacity <= 30 && batCapacity > 20 && !notified30) {
            notified30 = true
            if (alertStyle === "popup") { activeAlarmLevel = 3; alarmVisible = true }
            else fireIntegrated(3)
        }
        if (batCapacity <= 20 && batCapacity > 10 && !notified20) {
            notified20 = true
            if (alertStyle === "popup") { activeAlarmLevel = 1; alarmVisible = true }
            else fireIntegrated(1)
        }
        if (batCapacity <= 10 && !notified10) {
            notified10 = true
            if (alertStyle === "popup") { activeAlarmLevel = 2; alarmVisible = true }
            else fireIntegrated(2)
        }
    }

    // Soft glow ring behind the card — decorative only, deliberately NOT in the
    // hit-test mask, so it never eats clicks even though it visually bleeds outward
    Rectangle {
        anchors.centerIn: alertCard
        width: alertCard.width + root.s(28) + root.pulse * root.s(20)
        height: alertCard.height + root.s(28) + root.pulse * root.s(20)
        radius: alertCard.radius + root.s(14)
        color: "transparent"
        border.width: root.s(1)
        border.color: root.accent
        opacity: root.alarmVisible ? (0.10 + root.pulse * root.levelPulseMax(root.activeAlarmLevel) * 0.4) : 0.0
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }
    Rectangle {
        anchors.centerIn: alertCard
        width: alertCard.width + root.s(10)
        height: alertCard.height + root.s(10)
        radius: alertCard.radius + root.s(6)
        color: root.accent
        opacity: root.alarmVisible ? (0.05 + root.pulse * root.levelPulseMax(root.activeAlarmLevel) * 0.25) : 0.0
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    // === THE CARD — same footprint for every level, only content/accent changes ===
    Rectangle {
        id: alertCard
        anchors.top: parent.top
        anchors.topMargin: s(28)
        anchors.horizontalCenter: parent.horizontalCenter
        width: s(400)
        height: s(72)
        radius: s(20)
        color: Qt.rgba(root.crust.r, root.crust.g, root.crust.b, 0.92)
        border.width: s(1.5)
        border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35 + root.pulse * root.levelPulseMax(root.activeAlarmLevel))
        visible: root.alarmVisible
        scale: root.alarmVisible ? 1.0 : 0.9
        opacity: root.alarmVisible ? 1.0 : 0.0
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
        Behavior on border.color { ColorAnimation { duration: 200 } }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: root.accent
            opacity: 0.05 + root.pulse * 0.05
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: s(16)
            spacing: s(14)

            // Icon well — subtle drain pulse
            Item {
                width: s(38); height: s(38)
                Rectangle {
                    anchors.fill: parent
                    radius: s(11)
                    color: root.accent
                    opacity: 0.14
                }
                Text {
                    anchors.centerIn: parent
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: s(20)
                    color: root.accent
                    text: root.levelIcon(root.activeAlarmLevel)
                    opacity: 0.75 + root.pulse * 0.25
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: s(6)

                RowLayout {
                    spacing: s(8)
                    Text {
                        font.family: "JetBrains Mono"
                        font.weight: Font.Bold
                        font.pixelSize: s(13)
                        color: root.text
                        font.letterSpacing: s(1)
                        text: root.levelLabel(root.activeAlarmLevel)
                    }
                    Text {
                        font.family: "JetBrains Mono"
                        font.weight: Font.Black
                        font.pixelSize: s(13)
                        color: root.accent
                        text: root.batCapacity + "%"
                    }
                    Item { Layout.fillWidth: true }
                }

                Text {
                    font.family: "JetBrains Mono"
                    font.pixelSize: s(10.5)
                    color: root.subtext0
                    text: root.levelSub(root.activeAlarmLevel)
                }

                // Drain bar — segmented, sweeps toward empty
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: s(2)
                    height: s(4)
                    radius: s(2)
                    color: Qt.rgba(1, 1, 1, 0.08)

                    Rectangle {
                        width: parent.width * Math.max(root.batCapacity / 100.0, 0.02)
                        height: parent.height
                        radius: parent.radius
                        color: root.accent
                        opacity: 0.55 + root.pulse * 0.35
                    }
                }
            }

            Rectangle {
                width: s(26); height: s(26); radius: s(8)
                color: dismissMa.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                border.color: Qt.rgba(1, 1, 1, 0.12); border.width: s(1)
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    font.family: "JetBrains Mono"
                    font.pixelSize: s(13)
                    color: root.subtext0
                    text: "×"
                }
                MouseArea {
                    id: dismissMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.alarmVisible = false
                        root.activeAlarmLevel = 0
                    }
                }
            }
        }
    }
}
