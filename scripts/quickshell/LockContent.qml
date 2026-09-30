import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io

Item {
    id: screenRoot
    property bool lockReady: false
    property var root: ({
        preview: false, cfgMusic: false, cfgWeather: false, cfgNotifs: "off", cfgBrief: false, cfgBlur: 0.8,
        cfgParallax: false, cfgAmbient: "never", cfgClock: "big", cfgQuickActions: true,
        base: Qt.color("#11111b"), crust: Qt.color("#11111b"), mantle: Qt.color("#181825"), text: Qt.color("#cdd6f4"),
        subtext0: Qt.color("#a6adc8"), overlay0: Qt.color("#6c7086"), overlay2: Qt.color("#9399b2"),
        surface0: Qt.color("#313244"), surface1: Qt.color("#45475a"), surface2: Qt.color("#585b70"),
        mauve: Qt.color("#cba6f7"), pink: Qt.color("#f5c2e7"), red: Qt.color("#f38ba8"), peach: Qt.color("#fab387"),
        blue: Qt.color("#89b4fa"), green: Qt.color("#a6e3a1")
    })
    property var lockUI: ({ failed: false, authenticating: false, unlocking: false, statusText: "Locked", content: null })
    property var lockSettings: ({ hidePassword: false, revealDuration: 300 })
    readonly property bool preview: root ? root.preview : false

    Scaler {
        id: scaler
        currentWidth: screenRoot.width > 0 ? screenRoot.width : Screen.width
    }
    readonly property real sc: scaler.baseScale

    property real accentT: 0
    readonly property color accentA: root.mauve
    readonly property color accentB: root.pink
    readonly property color accentC: root.blue
    function mixC(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }
    readonly property color accent: {
        let t = accentT % 3
        if (t < 1) return mixC(accentA, accentB, t)
        if (t < 2) return mixC(accentB, accentC, t - 1)
        return mixC(accentC, accentA, t - 2)
    }

    readonly property bool ambientOn: root.cfgAmbient === "always" || (root.cfgAmbient === "occasional" && !inputActive)
    readonly property bool bigClock: root.cfgClock !== "compact"
    property string wallpaperSrc: ""
    property string clockH: "00"
    property string clockM: "00"
    property string dateStr: ""
    property string greeting: ""
    property string weatherDesc: ""
    property bool capsOn: false
    property string wifiName: ""
    property var musicInfo: ({ status: "Stopped" })
    property var notifList: []
    property var briefInfo: ({})
    property var timerInfo: ({ state: "idle", durationSecs: 1500, endTs: 0, remainingSecs: 0 })
    property int timerTick: 0
    readonly property int timerRemainingNow: {
        let _t = screenRoot.timerTick
        if (screenRoot.timerInfo.state === "running") return Math.max(0, Math.ceil((screenRoot.timerInfo.endTs - Date.now()) / 1000))
        if (screenRoot.timerInfo.state === "paused") return screenRoot.timerInfo.remainingSecs || 0
        return 0
    }
    function timerFmt(s) {
        let h = Math.floor(s / 3600)
        let m = Math.floor((s % 3600) / 60)
        let sec = s % 60
        let mmss = (m < 10 ? "0" : "") + m + ":" + (sec < 10 ? "0" : "") + sec
        return h > 0 ? (h + ":" + mmss) : mmss
    }

    Timer {
        interval: 100
        running: screenRoot.ambientOn || screenRoot.inputActive
        repeat: true
        onTriggered: screenRoot.accentT = (screenRoot.accentT + 0.0055) % 3
    }

    function refreshClock() {
        let d = new Date()
        clockH = Qt.formatDateTime(d, "hh")
        clockM = Qt.formatDateTime(d, "mm")
        dateStr = Qt.formatDateTime(d, "dddd, MMMM d")
        let h = d.getHours()
        greeting = h < 5 ? "Still up" : (h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : (h < 22 ? "Good evening" : "Good night")))
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: screenRoot.refreshClock() }

    function clearInput() {
        inputField.text = ""
        inputField.oldText = ""
        passModel.clear()
    }
    function focusInput() { inputField.forceActiveFocus() }

    Process { id: suspendProcess; command: ["systemctl", "suspend"] }
    Process { id: poweroffProcess; command: ["systemctl", "poweroff"] }
    Process { id: reloadProcess; command: ["systemctl", "reboot"] }

    Process {
        id: wpFinder
        running: true
        command: ["bash", "-c", "f=/tmp/lock_bg.png; if [ -s \"$f\" ]; then echo \"$f\"; else awww query 2>/dev/null | grep -o 'image: .*' | head -1 | sed 's/^image: //'; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = this.text.trim()
                if (p !== "") screenRoot.wallpaperSrc = "file://" + p
            }
        }
    }

    Process {
        id: weatherDescReader
        command: ["bash", "-c", "cat ~/.cache/quickshell/weather/weather.json 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(this.text)
                    screenRoot.weatherDesc = (d.forecast && d.forecast[0] && d.forecast[0].desc) ? d.forecast[0].desc : ""
                } catch (e) {}
            }
        }
    }
    Timer { interval: 600000; running: root.cfgWeather; repeat: true; triggeredOnStart: true; onTriggered: weatherDescReader.running = true }

    Process {
        id: musicReader
        command: ["bash", "-c", "cat /tmp/music_info.json 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { screenRoot.musicInfo = JSON.parse(this.text) } catch (e) {}
            }
        }
    }
    Timer { interval: 1000; running: root.cfgMusic; repeat: true; triggeredOnStart: true; onTriggered: musicReader.running = true }

    // ---------------------------------------------------------
    // Quick actions — mute / DND / brightness, usable without
    // unlocking. Same commands the top bar pills already use so
    // behavior matches exactly (volume_step.sh / brightness_step.sh /
    // swaync-client), no auth path touched.
    // ---------------------------------------------------------
    property bool qaMuted: false
    property bool qaDnd: false
    property int qaBrightness: 50

    Process {
        id: qaMuteReader
        command: ["bash", "-c", "pamixer --get-mute 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: screenRoot.qaMuted = this.text.trim() === "true" }
    }
    Process {
        id: qaDndReader
        command: ["bash", "-c", "command -v swaync-client >/dev/null && timeout 1 swaync-client -D 2>/dev/null || echo false"]
        stdout: StdioCollector { onStreamFinished: screenRoot.qaDnd = this.text.trim() === "true" }
    }
    Process {
        id: qaBrightnessReader
        command: ["bash", "-c", "brightnessctl -m 2>/dev/null | awk -F, '{gsub(\"%\",\"\",$4); print $4}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let v = parseInt(this.text.trim())
                if (!isNaN(v)) screenRoot.qaBrightness = v
            }
        }
    }
    Timer {
        interval: 2000; running: root.cfgQuickActions && !screenRoot.qaBrightnessDragging; repeat: true; triggeredOnStart: true
        onTriggered: { qaMuteReader.running = true; qaDndReader.running = true; qaBrightnessReader.running = true }
    }

    property bool qaBrightnessDragging: false

    function qaToggleMute() {
        Quickshell.execDetached(["bash", "-c", "bash ~/.config/hypr/scripts/volume_step.sh mute-toggle"])
        qaMuted = !qaMuted
    }
    function qaToggleDnd() {
        Quickshell.execDetached(["bash", "-c", "command -v swaync-client >/dev/null && swaync-client -d"])
        qaDnd = !qaDnd
    }
    function qaSetBrightness(pct) {
        qaBrightness = pct
        Quickshell.execDetached(["bash", "-c", "bash ~/.config/hypr/scripts/brightness_step.sh set " + pct])
    }

    Process {
        id: notifReader
        command: ["bash", "-c", "cat /tmp/qs_notifications.json 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let a = JSON.parse(this.text)
                    screenRoot.notifList = Array.isArray(a) ? a : []
                } catch (e) { screenRoot.notifList = [] }
            }
        }
    }
    Timer { interval: 4000; running: root.cfgNotifs !== "off"; repeat: true; triggeredOnStart: true; onTriggered: notifReader.running = true }

    Process {
        id: briefReader
        command: ["bash", "-c", "cat /tmp/qs_lock_brief.json 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { screenRoot.briefInfo = JSON.parse(this.text) } catch (e) { screenRoot.briefInfo = ({}) }
            }
        }
    }
    Timer { interval: 3000; running: root.cfgBrief; repeat: true; triggeredOnStart: true; onTriggered: briefReader.running = true }

    Process {
        id: timerReader
        command: ["bash", "-c", "cat /tmp/qs_timer.json 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { screenRoot.timerInfo = JSON.parse(this.text) } catch (e) {}
            }
        }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: timerReader.running = true }
    Timer { interval: 1000; running: screenRoot.timerInfo.state === "running"; repeat: true; onTriggered: screenRoot.timerTick = (screenRoot.timerTick + 1) % 100000 }

    Process {
        id: wifiPoller
        command: ["bash", "-c", "nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | grep '^yes' | head -1 | cut -d: -f2-"]
        stdout: StdioCollector { onStreamFinished: screenRoot.wifiName = this.text.trim() }
    }
    Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: wifiPoller.running = true }

    Process {
        id: capsPoller
        command: ["bash", "-c", "cat /sys/class/leds/*capslock/brightness 2>/dev/null | head -1"]
        stdout: StdioCollector { onStreamFinished: screenRoot.capsOn = this.text.trim() === "1" }
    }
    Timer { interval: 600; running: screenRoot.inputActive; repeat: true; triggeredOnStart: true; onTriggered: capsPoller.running = true }


                property string batPct: "100"
                property string batStatus: "AC"
                property string currentUser: "User"
                property string faceIconPath: ""
                property string kbLayout: "US"
                property string weatherIcon: ""
                property string weatherTemp: "--°C"

                // UI States
                property real introState: 0.0
                property bool powerMenuOpen: false
                property bool inputActive: false 
                property bool isPlayingIntro: true
                property bool isDesktop: false
                
                Component.onCompleted: {
                    lockUI.content = screenRoot;
                    lockReady = true;
                    introSequence.start();
                }

                property real globalOrbitAngle: 0
                NumberAnimation on globalOrbitAngle {
                    from: 0; to: Math.PI * 2; duration: 90000; loops: Animation.Infinite; running: screenRoot.ambientOn
                }

                // Auto-hide input field if empty and idle for 15 seconds
                Timer {
                    id: idleTimer
                    interval: 15000
                    running: screenRoot.inputActive && inputField.text.length === 0
                    repeat: false
                    onTriggered: screenRoot.inputActive = false
                }

                // ---------------------------------------------------------
                // BACKGROUND DATA POLLING 
                // ---------------------------------------------------------

                Process {
                    id: chassisDetector
                    running: true
                    command: ["bash", "-c", "if ls /sys/class/power_supply/BAT* 1> /dev/null 2>&1; then echo 'laptop'; else echo 'desktop'; fi"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            screenRoot.isDesktop = (this.text.trim() === "desktop");
                        }
                    }
                }

                Process {
                    id: userPoller
                    command: [
                        "bash", 
                        "-c", 
                        "USER_VAR=$(whoami); ICON_PATH=\"\"; if [ -f ~/.face.icon ]; then ICON_PATH=$(readlink -f ~/.face.icon); elif [ -f ~/.face ]; then ICON_PATH=$(readlink -f ~/.face); fi; echo -n \"$USER_VAR|$ICON_PATH\""
                    ]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            let parts = this.text.trim().split("|");
                            if (parts.length > 0 && parts[0] !== "") screenRoot.currentUser = parts[0];
                            if (parts.length > 1 && parts[1].trim() !== "") {
                                let path = parts[1].trim();
                                screenRoot.faceIconPath = path.startsWith("file://") ? path : "file://" + path;
                            }
                        }
                    }
                    Component.onCompleted: running = true
                }
                
                Process {
                    id: kbPoller
                    command: ["bash", "-c", "hyprctl devices -j | jq -r '.keyboards[] | select(.main == true) | .active_keymap' | head -n1 | cut -c1-2 | tr '[:lower:]' '[:upper:]'"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            let layout = this.text.trim();
                            if (layout !== "" && layout !== "null") {
                                screenRoot.kbLayout = layout;
                            }
                        }
                    }
                }
                Timer { interval: 1500; running: true; repeat: true; triggeredOnStart: true; onTriggered: kbPoller.running = true }

                Process {
                    id: batPoller
                    running: !screenRoot.isDesktop
                    command: ["bash", "-c", "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1 || echo '100'; cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1 || echo 'AC'"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            let lines = this.text.trim().split("\n");
                            if (lines.length >= 2) {
                                screenRoot.batPct = lines[0] || "100";
                                screenRoot.batStatus = lines[1] || "Unknown";
                            }
                        }
                    }
                }
                Timer { interval: 5000; running: !screenRoot.isDesktop; repeat: true; triggeredOnStart: true; onTriggered: batPoller.running = true }

                Process {
                    id: weatherPoller
                    property string scriptPath: Qt.resolvedUrl("calendar/weather.sh").toString().replace(/^file:\/\//, "")
                    command: ["bash", "-c", '"' + scriptPath + '" --current-icon; "' + scriptPath + '" --current-temp']
                    stdout: StdioCollector {
                        onStreamFinished: {
                            let lines = this.text.trim().split("\n");
                            if (lines.length >= 2) {
                                screenRoot.weatherIcon = lines[0] || "";
                                screenRoot.weatherTemp = lines[1] || "--°C";
                            }
                        }
                    }
                }
                Timer { interval: 900000; running: true; repeat: true; triggeredOnStart: true; onTriggered: weatherPoller.running = true }


    // ---------------------------------------------------------
    // 1. BACKGROUND
    // ---------------------------------------------------------
    Rectangle { anchors.fill: parent; color: root.base }

    Item {
        id: bgHolder
        anchors.fill: parent
        clip: true

        property real drift: 0
        SequentialAnimation on drift {
            running: root.cfgParallax && screenRoot.visible
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: 32000; easing.type: Easing.InOutSine }
            NumberAnimation { to: -1; duration: 32000; easing.type: Easing.InOutSine }
        }

        Image {
            id: bgWallpaper
            anchors.fill: parent
            source: screenRoot.wallpaperSrc
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
            cache: false
        }

        MultiEffect {
            source: bgWallpaper
            width: parent.width * 1.1
            height: parent.height * 1.1
            x: -parent.width * 0.05 + bgHolder.drift * parent.width * 0.03
            y: -parent.height * 0.05 + Math.sin(bgHolder.drift * 1.6) * parent.height * 0.02
            blurEnabled: true
            blurMax: 64
            blur: root.cfgBlur
            brightness: -0.08
            saturation: 0.1
            visible: bgWallpaper.status === Image.Ready
            opacity: screenRoot.introState
        }
    }

    Rectangle { anchors.fill: parent; color: "black"; opacity: 0.32 }
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: parent.height * 0.4
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.45) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: parent.height * 0.45
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
        }
    }

    // ---------------------------------------------------------
    // 2. AMBIENT LAYER (aurora + drifting motes)
    // ---------------------------------------------------------
    Item {
        id: ambientLayer
        anchors.fill: parent
        opacity: screenRoot.ambientOn ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }

        component SoftGlow: Item {
            id: glowItem
            property color glowColor: "white"
            property real glowSize: 400
            property real glowAlpha: 0.05
            width: glowSize; height: glowSize
            Repeater {
                model: 16
                Rectangle {
                    anchors.centerIn: parent
                    width: glowItem.glowSize * (1 - index * 0.055)
                    height: width
                    radius: width / 2
                    color: glowItem.glowColor
                    opacity: glowItem.glowAlpha / 9
                }
            }
        }
        SoftGlow {
            glowSize: parent.width * 0.7
            glowColor: screenRoot.accent
            glowAlpha: 0.10
            x: (parent.width - width) / 2 + Math.cos(screenRoot.globalOrbitAngle * 2) * (220 * screenRoot.sc)
            y: (parent.height - height) / 2 + Math.sin(screenRoot.globalOrbitAngle * 2) * (140 * screenRoot.sc)
            scale: 1.0 + Math.sin(screenRoot.globalOrbitAngle * 6) * 0.06
        }
        SoftGlow {
            glowSize: parent.width * 0.55
            glowColor: screenRoot.mixC(screenRoot.accentC, screenRoot.accentB, 0.5 + 0.5 * Math.sin(screenRoot.accentT * 2))
            glowAlpha: 0.09
            x: (parent.width - width) / 2 - Math.sin(screenRoot.globalOrbitAngle * 3) * (260 * screenRoot.sc)
            y: (parent.height - height) / 2 - Math.cos(screenRoot.globalOrbitAngle * 3) * (160 * screenRoot.sc)
        }

        Repeater {
            model: 16
            Rectangle {
                id: mote
                property real p: 0
                property real baseX: ((index * 137) % 100) / 100
                property real sz: (2 + (index % 4)) * screenRoot.sc
                width: sz; height: sz; radius: sz / 2
                color: screenRoot.accent
                x: baseX * ambientLayer.width + Math.sin(p * 6.283 + index) * 24 * screenRoot.sc
                y: ambientLayer.height * (1.05 - p * 1.1)
                opacity: Math.sin(p * Math.PI) * 0.4
                NumberAnimation on p {
                    from: 0; to: 1
                    duration: 14000 + (index % 5) * 2600
                    loops: Animation.Infinite
                    running: ambientLayer.visible
                }
            }
        }
    }

    // ---------------------------------------------------------
    // 3. MAIN CONTENT
    // ---------------------------------------------------------
    MouseArea {
        anchors.fill: parent
        enabled: !screenRoot.isPlayingIntro
        onClicked: {
            if (screenRoot.powerMenuOpen) screenRoot.powerMenuOpen = false;
            if (!screenRoot.inputActive) screenRoot.inputActive = true;
            inputField.forceActiveFocus();
        }
    }

    Item {
        id: contentLayer
        anchors.fill: parent
        opacity: screenRoot.introState * (lockUI.unlocking ? 0.0 : 1.0)
        scale: lockUI.unlocking ? 1.05 : 1.0
        transform: Translate { y: (30 * screenRoot.sc) * (1.0 - screenRoot.introState) }
        Behavior on opacity { NumberAnimation { duration: lockUI.unlocking ? 420 : 0; easing.type: Easing.InCubic } }
        Behavior on scale { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }

        // --- CLOCK MODULE (idle) ---
        ColumnLayout {
            id: clockModule
            anchors.centerIn: parent
            anchors.verticalCenterOffset: screenRoot.inputActive ? (-140 * screenRoot.sc) : (-50 * screenRoot.sc)
            spacing: 4 * screenRoot.sc
            opacity: screenRoot.inputActive ? 0.0 : 1.0
            scale: screenRoot.inputActive ? 0.92 : 1.0
            visible: opacity > 0.01
            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: screenRoot.greeting + ", " + screenRoot.currentUser
                font.family: "JetBrains Mono"
                font.pixelSize: 18 * screenRoot.sc
                font.weight: Font.Medium
                font.letterSpacing: 3
                color: screenRoot.accent
                opacity: 0.9
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 0
                RollText {
                    val: screenRoot.clockH
                    pixelSize: (screenRoot.bigClock ? 150 : 76) * screenRoot.sc
                    rollH: pixelSize * 1.2
                    weight: Font.Bold
                    color: root.text
                }
                Text {
                    text: ":"
                    font.family: "JetBrains Mono"
                    font.pixelSize: (screenRoot.bigClock ? 150 : 76) * screenRoot.sc
                    font.weight: Font.Bold
                    color: screenRoot.accent
                    SequentialAnimation on opacity {
                        running: clockModule.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 1400; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.9; duration: 1400; easing.type: Easing.InOutSine }
                    }
                }
                RollText {
                    val: screenRoot.clockM
                    pixelSize: (screenRoot.bigClock ? 150 : 76) * screenRoot.sc
                    rollH: pixelSize * 1.2
                    weight: Font.Bold
                    color: root.text
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: screenRoot.dateStr
                font.family: "JetBrains Mono"
                font.pixelSize: (screenRoot.bigClock ? 22 : 16) * screenRoot.sc
                font.weight: Font.Bold
                color: root.text
                opacity: 0.85
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 10 * screenRoot.sc
                visible: root.cfgWeather && screenRoot.weatherIcon !== ""
                Layout.preferredHeight: 40 * screenRoot.sc
                Layout.preferredWidth: weatherChipRow.implicitWidth + 32 * screenRoot.sc
                radius: height / 2
                color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.42)
                border.width: 1
                border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1)
                Row {
                    id: weatherChipRow
                    anchors.centerIn: parent
                    spacing: 10 * screenRoot.sc
                    Text { anchors.verticalCenter: parent.verticalCenter; text: screenRoot.weatherIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: 20 * screenRoot.sc; color: root.blue }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: screenRoot.weatherTemp; font.family: "JetBrains Mono"; font.pixelSize: 15 * screenRoot.sc; font.weight: Font.Black; color: root.text }
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: text !== ""; text: screenRoot.weatherDesc; font.family: "JetBrains Mono"; font.pixelSize: 13 * screenRoot.sc; color: root.subtext0 }
                }
            }
        }

        // --- AUTH MODULE (input) ---
        RowLayout {
            id: authModule
            anchors.centerIn: parent
            anchors.verticalCenterOffset: screenRoot.inputActive ? (-40 * screenRoot.sc) : (40 * screenRoot.sc)
            spacing: 34 * screenRoot.sc
            opacity: screenRoot.inputActive ? 1.0 : 0.0
            scale: screenRoot.inputActive ? 1.0 : 0.92
            visible: opacity > 0.01
            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }

            // Avatar with a live progress ring
            Item {
                id: avatarBox
                Layout.alignment: Qt.AlignVCenter
                width: 190 * screenRoot.sc
                height: width

                Canvas {
                    id: authRing
                    anchors.fill: parent
                    property real spin: 0
                    property real fillFrac: Math.min(1, inputField.text.length / 12)
                    property color ringColor: lockUI.unlocking ? root.green : (lockUI.failed ? root.red : (lockUI.authenticating ? root.peach : screenRoot.accent))
                    onFillFracChanged: requestPaint()
                    onSpinChanged: if (lockUI.authenticating) requestPaint()
                    onRingColorChanged: requestPaint()
                    NumberAnimation on spin { from: 0; to: 6.283; duration: 1100; loops: Animation.Infinite; running: lockUI.authenticating && authModule.visible }
                    onPaint: {
                        let ctx = getContext("2d")
                        ctx.reset()
                        let cx = width / 2, cy = height / 2
                        let r = width / 2 - 4 * screenRoot.sc
                        ctx.lineWidth = Math.max(2, 4 * screenRoot.sc)
                        ctx.lineCap = "round"
                        ctx.strokeStyle = Qt.rgba(root.text.r, root.text.g, root.text.b, 0.14)
                        ctx.beginPath(); ctx.arc(cx, cy, r, 0, 6.283); ctx.stroke()
                        ctx.strokeStyle = ringColor
                        ctx.beginPath()
                        if (lockUI.unlocking || lockUI.failed) ctx.arc(cx, cy, r, 0, 6.283)
                        else if (lockUI.authenticating) ctx.arc(cx, cy, r, spin, spin + 2.1)
                        else if (fillFrac > 0) ctx.arc(cx, cy, r, -1.5708, -1.5708 + 6.283 * fillFrac)
                        ctx.stroke()
                    }
                }

                Item {
                    anchors.fill: parent
                    anchors.margins: 16 * screenRoot.sc

                    Rectangle {
                        id: avatarMask
                        anchors.fill: parent
                        radius: height / 2
                        color: "black"
                        visible: false
                        layer.enabled: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.55)
                        visible: avatarImg.status !== Image.Ready
                        Text { anchors.centerIn: parent; text: "󰀄"; font.family: "Iosevka Nerd Font"; font.pixelSize: 68 * screenRoot.sc; color: root.subtext0 }
                    }
                    Image {
                        id: avatarImg
                        anchors.fill: parent
                        source: screenRoot.faceIconPath !== "" ? screenRoot.faceIconPath : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: false
                        cache: false
                        asynchronous: true
                    }
                    MultiEffect {
                        source: avatarImg
                        anchors.fill: avatarImg
                        maskEnabled: true
                        maskSource: avatarMask
                        visible: avatarImg.status === Image.Ready
                    }
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 16 * screenRoot.sc

                Text {
                    text: screenRoot.currentUser
                    font.family: "JetBrains Mono"
                    font.pixelSize: 30 * screenRoot.sc
                    font.weight: Font.Bold
                    color: root.text
                }

                RowLayout {
                    spacing: 12 * screenRoot.sc
                    Rectangle {
                        width: 36 * screenRoot.sc
                        height: width
                        radius: height / 2
                        color: lockUI.failed ? Qt.rgba(root.red.r, root.red.g, root.red.b, 0.2) : (lockUI.authenticating ? Qt.rgba(root.peach.r, root.peach.g, root.peach.b, 0.2) : Qt.rgba(screenRoot.accent.r, screenRoot.accent.g, screenRoot.accent.b, 0.18))
                        border.color: lockUI.failed ? root.red : (lockUI.authenticating ? root.peach : screenRoot.accent)
                        border.width: Math.max(1, 1 * screenRoot.sc)
                        Behavior on color { ColorAnimation { duration: 300 } }
                        Text {
                            anchors.centerIn: parent
                            text: lockUI.unlocking ? "󰌿" : "󰌾"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: 18 * screenRoot.sc
                            color: lockUI.failed ? root.red : (lockUI.authenticating ? root.peach : screenRoot.accent)
                        }
                    }
                    Text {
                        font.family: "JetBrains Mono"
                        font.pixelSize: 14 * screenRoot.sc
                        font.weight: Font.Medium
                        font.letterSpacing: 2.0
                        color: lockUI.failed ? root.red : (lockUI.authenticating ? root.peach : root.text)
                        text: (lockUI.unlocking ? "Welcome back" : lockUI.statusText).toUpperCase()
                    }
                    Rectangle {
                        visible: screenRoot.capsOn
                        height: 24 * screenRoot.sc
                        width: capsText.implicitWidth + 18 * screenRoot.sc
                        radius: height / 2
                        color: Qt.rgba(root.peach.r, root.peach.g, root.peach.b, 0.18)
                        border.color: root.peach
                        border.width: 1
                        Text { id: capsText; anchors.centerIn: parent; text: "CAPS"; font.family: "JetBrains Mono"; font.pixelSize: 11 * screenRoot.sc; font.weight: Font.Black; font.letterSpacing: 1.5; color: root.peach }
                        SequentialAnimation on opacity {
                            running: screenRoot.capsOn
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.5; duration: 700 }
                            NumberAnimation { to: 1.0; duration: 700 }
                        }
                    }
                }

                Item {
                    Layout.preferredWidth: 300 * screenRoot.sc
                    Layout.preferredHeight: 64 * screenRoot.sc

                    Rectangle {
                        id: keyPulse
                        anchors.fill: pinPill
                        radius: height / 2
                        color: "transparent"
                        border.width: Math.max(1, 2 * screenRoot.sc)
                        border.color: screenRoot.accent
                        opacity: 0
                        transformOrigin: Item.Center
                        ParallelAnimation {
                            id: keyPulseAnim
                            NumberAnimation { target: keyPulse; property: "scale"; from: 1.0; to: 1.14; duration: 320; easing.type: Easing.OutCubic }
                            NumberAnimation { target: keyPulse; property: "opacity"; from: 0.7; to: 0.0; duration: 320; easing.type: Easing.OutCubic }
                        }
                    }

                    Rectangle {
                        id: pinPill
                        anchors.centerIn: parent
                        width: 280 * screenRoot.sc
                        height: 60 * screenRoot.sc
                        radius: height / 2
                        clip: true
                        color: lockUI.failed ? Qt.rgba(root.red.r, root.red.g, root.red.b, 0.12) : Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.55)
                        border.width: Math.max(1, 2 * screenRoot.sc)
                        border.color: {
                            if (lockUI.unlocking) return root.green;
                            if (lockUI.failed) return root.red;
                            if (lockUI.authenticating) return root.peach;
                            if (inputField.text.length > 0) return screenRoot.accent;
                            return Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1);
                        }
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutExpo } }
                        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutExpo } }
                        scale: lockUI.failed ? 1.04 : (lockUI.authenticating ? 0.98 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                        transform: Translate { id: shakeTranslate; x: 0 }

                        SequentialAnimation {
                            id: shakeAnim
                            NumberAnimation { target: shakeTranslate; property: "x"; to: -12 * screenRoot.sc; duration: 70; easing.type: Easing.InOutSine }
                            NumberAnimation { target: shakeTranslate; property: "x"; to: 12 * screenRoot.sc; duration: 110; easing.type: Easing.InOutSine }
                            NumberAnimation { target: shakeTranslate; property: "x"; to: -8 * screenRoot.sc; duration: 100; easing.type: Easing.InOutSine }
                            NumberAnimation { target: shakeTranslate; property: "x"; to: 5 * screenRoot.sc; duration: 90; easing.type: Easing.InOutSine }
                            NumberAnimation { target: shakeTranslate; property: "x"; to: 0; duration: 80; easing.type: Easing.InOutSine }
                        }

                        Connections {
                            target: screenRoot.lockReady ? screenRoot.lockUI : null
                            function onFailedChanged() {
                                if (lockUI.failed) { shakeAnim.restart(); redFlash.restart(); }
                            }
                        }

                        TextInput {
                            id: inputField
                            anchors.fill: parent
                            opacity: 0
                            echoMode: TextInput.Password
                            enabled: !screenRoot.isPlayingIntro && !lockUI.unlocking

                            property string oldText: ""

                            Component.onCompleted: forceActiveFocus()

                            onActiveFocusChanged: {
                                if (!activeFocus && !screenRoot.powerMenuOpen && !screenRoot.isPlayingIntro) {
                                    forceActiveFocus();
                                }
                            }

                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Escape) {
                                    if (screenRoot.preview && !screenRoot.inputActive) Qt.quit();
                                    screenRoot.inputActive = false;
                                    text = "";
                                    passModel.clear();
                                    event.accepted = true;
                                }
                                else if (!screenRoot.inputActive) {
                                    screenRoot.inputActive = true;
                                }
                            }

                            onAccepted: {
                                if (text.length > 0 && !lockUI.authenticating) {
                                    let pwd = text;
                                    text = "";
                                    oldText = "";
                                    passModel.clear();
                                    lockUI.submit(pwd);
                                }
                            }

                            onTextChanged: {
                                if (lockUI.authenticating) return;

                                if (text.length > 0 && !screenRoot.inputActive) {
                                    screenRoot.inputActive = true;
                                }

                                idleTimer.restart();

                                if (text !== oldText) {
                                    if (text.length > oldText.length) {
                                        keyPulseAnim.restart();
                                        for (let i = oldText.length; i < text.length; i++) {
                                            passModel.append({ "charStr": text.charAt(i), "isDot": lockSettings.hidePassword });
                                        }
                                    } else if (text.length < oldText.length) {
                                        let diff = oldText.length - text.length;
                                        for (let i = 0; i < diff; i++) {
                                            passModel.remove(passModel.count - 1);
                                        }
                                    } else {
                                        passModel.clear();
                                        for (let i = 0; i < text.length; i++) {
                                            passModel.append({ "charStr": text.charAt(i), "isDot": lockSettings.hidePassword });
                                        }
                                    }
                                    oldText = text;
                                }

                                if (text.length > 0) {
                                    lockUI.failed = false;
                                    lockUI.statusText = "Enter PIN";
                                } else {
                                    if (!lockUI.failed) lockUI.statusText = "Locked";
                                }
                            }
                        }

                        ListModel { id: passModel }

                        Item {
                            anchors.fill: parent
                            anchors.leftMargin: 20 * screenRoot.sc
                            anchors.rightMargin: 20 * screenRoot.sc
                            clip: true

                            Row {
                                id: dotRow
                                anchors.verticalCenter: parent.verticalCenter
                                x: width > parent.width ? parent.width - width : (parent.width - width) / 2
                                spacing: 4 * screenRoot.sc
                                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                                Repeater {
                                    model: passModel
                                    delegate: Text {
                                        text: model.isDot ? "•" : model.charStr
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: model.isDot ? (32 * screenRoot.sc) : (24 * screenRoot.sc)
                                        font.weight: Font.Bold
                                        color: lockUI.failed ? root.red : (lockUI.authenticating ? root.peach : root.text)
                                        verticalAlignment: Text.AlignVCenter
                                        height: pinPill.height
                                        NumberAnimation on opacity { from: 0; to: 1; duration: 150 }
                                        Timer {
                                            interval: lockSettings.revealDuration
                                            running: !model.isDot && !lockSettings.hidePassword
                                            onTriggered: {
                                                if (index >= 0 && index < passModel.count) {
                                                    passModel.setProperty(index, "isDot", true);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: screenRoot.preview
                    text: "preview mode - password: test  (Esc twice to close)"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 11 * screenRoot.sc
                    color: root.subtext0
                }
            }
        }
    }

    // wrong-password red flash
    Rectangle {
        id: redFlashRect
        anchors.fill: parent
        color: root.red
        opacity: 0
        z: 50
        SequentialAnimation {
            id: redFlash
            NumberAnimation { target: redFlashRect; property: "opacity"; to: 0.22; duration: 90 }
            NumberAnimation { target: redFlashRect; property: "opacity"; to: 0.0; duration: 420; easing.type: Easing.OutCubic }
        }
    }

    // success burst
    Rectangle {
        id: successBurst
        anchors.centerIn: parent
        width: 260 * screenRoot.sc
        height: width
        radius: width / 2
        color: "transparent"
        border.color: root.green
        border.width: Math.max(2, 3 * screenRoot.sc)
        opacity: 0
        z: 40
        ParallelAnimation {
            id: successAnim
            NumberAnimation { target: successBurst; property: "scale"; from: 0.6; to: 3.2; duration: 560; easing.type: Easing.OutCubic }
            NumberAnimation { target: successBurst; property: "opacity"; from: 0.8; to: 0.0; duration: 560; easing.type: Easing.OutCubic }
        }
    }
    Connections {
        target: screenRoot.lockReady ? screenRoot.lockUI : null
        function onUnlockingChanged() { if (lockUI.unlocking) { successAnim.restart(); authRing.requestPaint(); } }
    }

    // ---------------------------------------------------------
    // 4. SIDE CARDS
    // ---------------------------------------------------------
    // left: Claude brief + notifications
    ColumnLayout {
        id: leftCards
        anchors.left: parent.left
        anchors.leftMargin: 48 * screenRoot.sc
        anchors.verticalCenter: parent.verticalCenter
        width: 340 * screenRoot.sc
        spacing: 14 * screenRoot.sc
        opacity: screenRoot.introState * (screenRoot.inputActive ? 0.55 : 1.0) * (lockUI.unlocking ? 0 : 1)
        Behavior on opacity { NumberAnimation { duration: 400 } }

        Rectangle {
            id: briefCard
            readonly property var briefItems: Array.isArray(screenRoot.briefInfo.items) ? screenRoot.briefInfo.items : []
            readonly property int shownItems: Math.min(5, briefItems.length)
            Layout.fillWidth: true
            visible: root.cfgBrief && ((screenRoot.briefInfo.headline || "") !== "")
            Layout.preferredHeight: visible ? briefCol.implicitHeight + 28 * screenRoot.sc : 0
            radius: 20 * screenRoot.sc
            color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.48)
            border.width: 1
            border.color: Qt.rgba(screenRoot.accent.r, screenRoot.accent.g, screenRoot.accent.b, 0.4)
            ColumnLayout {
                id: briefCol
                anchors.fill: parent
                anchors.margins: 14 * screenRoot.sc
                spacing: 8 * screenRoot.sc
                RowLayout {
                    spacing: 8 * screenRoot.sc
                    Text { text: "󰚩"; font.family: "Iosevka Nerd Font"; font.pixelSize: 18 * screenRoot.sc; color: screenRoot.accent }
                    Text { text: "WHILE YOU WERE AWAY"; font.family: "JetBrains Mono"; font.pixelSize: 11 * screenRoot.sc; font.weight: Font.Black; font.letterSpacing: 1.5; color: screenRoot.accent }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        visible: briefCard.briefItems.length > 0
                        width: briefCountText.implicitWidth + 14 * screenRoot.sc; height: 20 * screenRoot.sc; radius: height / 2
                        color: Qt.rgba(screenRoot.accent.r, screenRoot.accent.g, screenRoot.accent.b, 0.2)
                        Text { id: briefCountText; anchors.centerIn: parent; text: briefCard.briefItems.length; font.family: "JetBrains Mono"; font.pixelSize: 11 * screenRoot.sc; font.weight: Font.Black; color: screenRoot.accent }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: screenRoot.briefInfo.headline || ""
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    font.family: "JetBrains Mono"
                    font.weight: Font.Bold
                    font.pixelSize: 13 * screenRoot.sc
                    color: root.text
                }
                Rectangle {
                    Layout.fillWidth: true
                    visible: briefCard.briefItems.length > 0
                    Layout.preferredHeight: 1 * screenRoot.sc
                    color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1)
                }
                Repeater {
                    model: briefCard.shownItems
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: 8 * screenRoot.sc
                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 6 * screenRoot.sc
                            width: 5 * screenRoot.sc; height: width; radius: width / 2
                            color: screenRoot.accent
                            opacity: 0.7
                        }
                        Text {
                            Layout.fillWidth: true
                            text: briefCard.briefItems[index] || ""
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.family: "JetBrains Mono"
                            font.pixelSize: 12 * screenRoot.sc
                            color: root.subtext0
                        }
                    }
                }
                Text {
                    visible: briefCard.briefItems.length > briefCard.shownItems
                    text: "+" + (briefCard.briefItems.length - briefCard.shownItems) + " more"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 11 * screenRoot.sc
                    color: root.subtext0
                }
            }
        }

        Rectangle {
            id: notifCard
            Layout.fillWidth: true
            visible: root.cfgNotifs !== "off" && screenRoot.notifList.length > 0
            Layout.preferredHeight: visible ? notifCol.implicitHeight + 28 * screenRoot.sc : 0
            radius: 20 * screenRoot.sc
            color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.48)
            border.width: 1
            border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1)
            ColumnLayout {
                id: notifCol
                anchors.fill: parent
                anchors.margins: 14 * screenRoot.sc
                spacing: 8 * screenRoot.sc
                RowLayout {
                    spacing: 8 * screenRoot.sc
                    Text { text: "󰂚"; font.family: "Iosevka Nerd Font"; font.pixelSize: 18 * screenRoot.sc; color: root.peach }
                    Text {
                        text: root.cfgNotifs === "count" ? (screenRoot.notifList.length + (screenRoot.notifList.length === 1 ? " notification" : " notifications")) : "NOTIFICATIONS"
                        font.family: "JetBrains Mono"; font.pixelSize: 12 * screenRoot.sc; font.weight: Font.Black; font.letterSpacing: 1.5; color: root.text
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        visible: root.cfgNotifs === "full"
                        width: countText.implicitWidth + 14 * screenRoot.sc; height: 20 * screenRoot.sc; radius: height / 2
                        color: Qt.rgba(root.peach.r, root.peach.g, root.peach.b, 0.2)
                        Text { id: countText; anchors.centerIn: parent; text: screenRoot.notifList.length; font.family: "JetBrains Mono"; font.pixelSize: 11 * screenRoot.sc; font.weight: Font.Black; color: root.peach }
                    }
                }
                Repeater {
                    model: root.cfgNotifs === "full" ? Math.min(4, screenRoot.notifList.length) : 0
                    delegate: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1 * screenRoot.sc
                        Text {
                            Layout.fillWidth: true
                            text: (screenRoot.notifList[index].appName || "") + "  ·  " + (screenRoot.notifList[index].summary || "")
                            elide: Text.ElideRight
                            font.family: "JetBrains Mono"; font.pixelSize: 12 * screenRoot.sc; font.weight: Font.Bold; color: root.text
                        }
                        Text {
                            Layout.fillWidth: true
                            text: screenRoot.notifList[index].body || ""
                            elide: Text.ElideRight
                            font.family: "JetBrains Mono"; font.pixelSize: 11 * screenRoot.sc; color: root.subtext0
                        }
                    }
                }
            }
        }
    }

    // right: now playing
    Rectangle {
        id: musicCard
        anchors.right: parent.right
        anchors.rightMargin: 48 * screenRoot.sc
        anchors.verticalCenter: parent.verticalCenter
        width: 320 * screenRoot.sc
        height: musicCol.implicitHeight + 32 * screenRoot.sc
        radius: 22 * screenRoot.sc
        readonly property bool active: root.cfgMusic && (screenRoot.musicInfo.status === "Playing" || screenRoot.musicInfo.status === "Paused")
        visible: opacity > 0.01
        opacity: active ? screenRoot.introState * (screenRoot.inputActive ? 0.55 : 1.0) * (lockUI.unlocking ? 0 : 1) : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }
        color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.5)
        border.width: 1
        border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1)

        ColumnLayout {
            id: musicCol
            anchors.fill: parent
            anchors.margins: 16 * screenRoot.sc
            spacing: 12 * screenRoot.sc

            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 200 * screenRoot.sc
                Layout.preferredHeight: 200 * screenRoot.sc
                Rectangle { id: artMask; anchors.fill: parent; radius: 18 * screenRoot.sc; color: "black"; visible: false; layer.enabled: true }
                Rectangle { anchors.fill: parent; radius: 18 * screenRoot.sc; color: Qt.rgba(root.surface1.r, root.surface1.g, root.surface1.b, 0.7); visible: artImg.status !== Image.Ready
                    Text { anchors.centerIn: parent; text: "󰎆"; font.family: "Iosevka Nerd Font"; font.pixelSize: 56 * screenRoot.sc; color: root.subtext0 } }
                Image {
                    id: artImg
                    anchors.fill: parent
                    source: screenRoot.musicInfo.artUrl ? "file://" + screenRoot.musicInfo.artUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: false
                }
                MultiEffect { source: artImg; anchors.fill: artImg; maskEnabled: true; maskSource: artMask; visible: artImg.status === Image.Ready }
            }

            Text {
                Layout.fillWidth: true
                text: screenRoot.musicInfo.title || ""
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                font.family: "JetBrains Mono"; font.pixelSize: 16 * screenRoot.sc; font.weight: Font.Bold; color: root.text
            }
            Text {
                Layout.fillWidth: true
                text: screenRoot.musicInfo.artist || ""
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                font.family: "JetBrains Mono"; font.pixelSize: 12 * screenRoot.sc; color: root.subtext0
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 5 * screenRoot.sc
                radius: height / 2
                color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.14)
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, (screenRoot.musicInfo.percent || 0) / 100))
                    height: parent.height
                    radius: height / 2
                    color: screenRoot.accent
                    Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: screenRoot.musicInfo.positionStr || ""; font.family: "JetBrains Mono"; font.pixelSize: 10 * screenRoot.sc; color: root.subtext0 }
                Item { Layout.fillWidth: true }
                Text { text: screenRoot.musicInfo.lengthStr || ""; font.family: "JetBrains Mono"; font.pixelSize: 10 * screenRoot.sc; color: root.subtext0 }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 26 * screenRoot.sc
                Repeater {
                    model: [
                        { g: "󰒮", a: "previous" },
                        { g: (screenRoot.musicInfo.status === "Playing" ? "󰏤" : "󰐊"), a: "play-pause" },
                        { g: "󰒭", a: "next" }
                    ]
                    delegate: Text {
                        text: modelData.g
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: (index === 1 ? 34 : 24) * screenRoot.sc
                        color: btnMa.containsMouse ? screenRoot.accent : root.text
                        scale: btnMa.pressed ? 0.85 : (btnMa.containsMouse ? 1.12 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        MouseArea {
                            id: btnMa
                            anchors.fill: parent
                            anchors.margins: -8 * screenRoot.sc
                            hoverEnabled: true
                            onClicked: {
                                Quickshell.execDetached(["playerctl", "--player=spotify", modelData.a]);
                                musicReader.running = true;
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------
    // 4b. QUICK ACTIONS — mute / DND / brightness, no unlock needed
    // ---------------------------------------------------------
    RowLayout {
        id: quickActionsRow
        visible: root.cfgQuickActions
        anchors.bottom: statusPillsRow.top
        anchors.bottomMargin: 14 * screenRoot.sc
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 12 * screenRoot.sc
        opacity: screenRoot.introState * (lockUI.unlocking ? 0 : 1)
        transform: Translate { y: (20 * screenRoot.sc) * (1.0 - screenRoot.introState) }

        Rectangle {
            id: qaMuteBtn
            Layout.preferredWidth: 44 * screenRoot.sc
            Layout.preferredHeight: 44 * screenRoot.sc
            radius: height / 2
            color: screenRoot.qaMuted
                ? Qt.rgba(root.red.r, root.red.g, root.red.b, 0.3)
                : Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.42)
            border.color: screenRoot.qaMuted ? root.red : Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1)
            border.width: Math.max(1, 1 * screenRoot.sc)
            Behavior on color { ColorAnimation { duration: 150 } }
            Text {
                anchors.centerIn: parent
                text: screenRoot.qaMuted ? "󰝟" : "󰕾"
                font.family: "Iosevka Nerd Font"; font.pixelSize: 18 * screenRoot.sc
                color: screenRoot.qaMuted ? root.red : root.text
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: screenRoot.qaToggleMute() }
        }

        Rectangle {
            id: qaDndBtn
            Layout.preferredWidth: 44 * screenRoot.sc
            Layout.preferredHeight: 44 * screenRoot.sc
            radius: height / 2
            color: screenRoot.qaDnd
                ? Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.3)
                : Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.42)
            border.color: screenRoot.qaDnd ? root.mauve : Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1)
            border.width: Math.max(1, 1 * screenRoot.sc)
            Behavior on color { ColorAnimation { duration: 150 } }
            Text {
                anchors.centerIn: parent
                text: screenRoot.qaDnd ? "󰂛" : "󰂚"
                font.family: "Iosevka Nerd Font"; font.pixelSize: 18 * screenRoot.sc
                color: screenRoot.qaDnd ? root.mauve : root.text
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: screenRoot.qaToggleDnd() }
        }

        Rectangle {
            id: qaBrightPill
            Layout.preferredHeight: 44 * screenRoot.sc
            Layout.preferredWidth: 160 * screenRoot.sc
            radius: height / 2
            color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.42)
            border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1)
            border.width: Math.max(1, 1 * screenRoot.sc)

            Text {
                anchors.left: parent.left; anchors.leftMargin: 14 * screenRoot.sc
                anchors.verticalCenter: parent.verticalCenter
                text: "󰃟"
                font.family: "Iosevka Nerd Font"; font.pixelSize: 16 * screenRoot.sc; color: root.peach
            }

            Item {
                id: qaBrightTrack
                anchors.left: parent.left; anchors.leftMargin: 40 * screenRoot.sc
                anchors.right: parent.right; anchors.rightMargin: 16 * screenRoot.sc
                anchors.verticalCenter: parent.verticalCenter
                height: 6 * screenRoot.sc

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: root.surface2
                }
                Rectangle {
                    width: parent.width * (screenRoot.qaBrightness / 100)
                    height: parent.height
                    radius: height / 2
                    color: root.peach
                    Behavior on width { enabled: !screenRoot.qaBrightnessDragging; NumberAnimation { duration: 150 } }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10 * screenRoot.sc
                    cursorShape: Qt.PointingHandCursor
                    function pctFromX(mx) {
                        let p = Math.max(0, Math.min(1, mx / qaBrightTrack.width))
                        return Math.round(p * 100)
                    }
                    onPressed: (mouse) => { screenRoot.qaBrightnessDragging = true; screenRoot.qaSetBrightness(pctFromX(mouse.x)) }
                    onPositionChanged: (mouse) => { if (pressed) screenRoot.qaSetBrightness(pctFromX(mouse.x)) }
                    onReleased: screenRoot.qaBrightnessDragging = false
                }
            }
        }
    }

    // ---------------------------------------------------------
    // 5. BOTTOM STATUS PILLS
    // ---------------------------------------------------------
    RowLayout {
        id: statusPillsRow
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40 * screenRoot.sc
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 16 * screenRoot.sc
        opacity: screenRoot.introState * (lockUI.unlocking ? 0 : 1)
        transform: Translate { y: (20 * screenRoot.sc) * (1.0 - screenRoot.introState) }

        Rectangle {
            Layout.preferredHeight: 48 * screenRoot.sc
            Layout.preferredWidth: kbLayoutRow.implicitWidth + (36 * screenRoot.sc)
            radius: height / 2
            color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.42)
            border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1)
            border.width: Math.max(1, 1 * screenRoot.sc)
            RowLayout {
                id: kbLayoutRow; anchors.centerIn: parent; spacing: 8 * screenRoot.sc
                Text { text: "󰌌"; font.family: "Iosevka Nerd Font"; font.pixelSize: 18 * screenRoot.sc; color: root.overlay2 }
                Text { text: screenRoot.kbLayout; font.family: "JetBrains Mono"; font.pixelSize: 14 * screenRoot.sc; font.weight: Font.Black; color: root.text }
            }
        }

        Rectangle {
            visible: screenRoot.wifiName !== ""
            Layout.preferredHeight: 48 * screenRoot.sc
            Layout.preferredWidth: wifiRow.implicitWidth + (36 * screenRoot.sc)
            radius: height / 2
            color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.42)
            border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1)
            border.width: Math.max(1, 1 * screenRoot.sc)
            RowLayout {
                id: wifiRow; anchors.centerIn: parent; spacing: 8 * screenRoot.sc
                Text { text: "󰤨"; font.family: "Iosevka Nerd Font"; font.pixelSize: 18 * screenRoot.sc; color: root.blue }
                Text { text: screenRoot.wifiName; font.family: "JetBrains Mono"; font.pixelSize: 13 * screenRoot.sc; font.weight: Font.Bold; color: root.text; elide: Text.ElideRight; Layout.maximumWidth: 180 * screenRoot.sc }
            }
        }

        Rectangle {
            visible: !screenRoot.isDesktop
            Layout.preferredHeight: 48 * screenRoot.sc
            Layout.preferredWidth: batLayoutRow.implicitWidth + (36 * screenRoot.sc)
            radius: height / 2
            color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.42)
            border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1)
            border.width: Math.max(1, 1 * screenRoot.sc)
            RowLayout {
                id: batLayoutRow; anchors.centerIn: parent; spacing: 8 * screenRoot.sc
                property color dynamicBatColor: {
                    if (screenRoot.batStatus === "Charging") return root.green;
                    let pct = parseInt(screenRoot.batPct);
                    if (pct >= 60) return root.green;
                    if (pct >= 25) return root.peach;
                    return root.red;
                }
                Text {
                    text: screenRoot.batStatus === "Charging" ? "󰂄" : (parseInt(screenRoot.batPct) < 20 ? "󰂃" : "󰁹")
                    font.family: "Iosevka Nerd Font"; font.pixelSize: 20 * screenRoot.sc; color: batLayoutRow.dynamicBatColor
                }
                Text { text: screenRoot.batPct + "%"; font.family: "JetBrains Mono"; font.pixelSize: 14 * screenRoot.sc; font.weight: Font.Black; color: batLayoutRow.dynamicBatColor }
            }
        }

        Rectangle {
            visible: screenRoot.timerInfo.state === "running" || screenRoot.timerInfo.state === "paused"
            Layout.preferredHeight: 48 * screenRoot.sc
            Layout.preferredWidth: timerLayoutRow.implicitWidth + (36 * screenRoot.sc)
            radius: height / 2
            color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.42)
            border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.1)
            border.width: Math.max(1, 1 * screenRoot.sc)
            RowLayout {
                id: timerLayoutRow; anchors.centerIn: parent; spacing: 8 * screenRoot.sc
                Text {
                    text: screenRoot.timerInfo.state === "paused" ? "󰏤" : "󰄉"
                    font.family: "Iosevka Nerd Font"; font.pixelSize: 18 * screenRoot.sc
                    color: screenRoot.timerInfo.state === "paused" ? root.overlay2 : root.peach
                }
                Text {
                    text: screenRoot.timerFmt(screenRoot.timerRemainingNow)
                    font.family: "JetBrains Mono"; font.pixelSize: 14 * screenRoot.sc; font.weight: Font.Black
                    color: screenRoot.timerInfo.state === "paused" ? root.overlay2 : root.text
                }
            }
        }
    }

                // ---------------------------------------------------------
                // 4. POWER MENU
                // ---------------------------------------------------------
                Rectangle {
                    id: powerMenu
                    anchors.bottom: powerBtn.top
                    anchors.right: parent.right
                    anchors.bottomMargin: 15 * screenRoot.sc
                    anchors.rightMargin: 40 * screenRoot.sc
                    width: 280 * screenRoot.sc
                    height: screenRoot.powerMenuOpen ? (menuLayout.implicitHeight + (20 * screenRoot.sc)) : 0
                    radius: 18 * screenRoot.sc
                    clip: true
                    opacity: screenRoot.powerMenuOpen ? 1 : 0
                    
                    color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.95)
                    border.color: Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.25)
                    border.width: Math.max(1, 1 * screenRoot.sc)

                    Behavior on height { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
                    Behavior on opacity { NumberAnimation { duration: 250 } }

                    ColumnLayout {
                        id: menuLayout
                        anchors.top: parent.top
                        anchors.topMargin: 10 * screenRoot.sc
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 6 * screenRoot.sc

                        // --- SETTINGS SECTION ---
                        Text { 
                            text: "SETTINGS"
                            font.family: "JetBrains Mono"
                            font.weight: Font.Black
                            font.pixelSize: 12 * screenRoot.sc
                            font.letterSpacing: 1.5
                            color: root.mauve
                            Layout.leftMargin: 18 * screenRoot.sc; Layout.topMargin: 4 * screenRoot.sc; Layout.bottomMargin: 4 * screenRoot.sc 
                        }

                        // Hide Password Toggle
                        RowLayout {
                            Layout.fillWidth: true; Layout.leftMargin: 18 * screenRoot.sc; Layout.rightMargin: 18 * screenRoot.sc; Layout.topMargin: 4 * screenRoot.sc
                            Text {
                                text: "Hide password"
                                font.family: "JetBrains Mono"
                                font.pixelSize: 14 * screenRoot.sc
                                font.weight: Font.Medium
                                color: root.text
                                Layout.fillWidth: true
                            }
                            
                            Rectangle {
                                width: 40 * screenRoot.sc; height: 22 * screenRoot.sc; radius: height / 2
                                color: lockSettings.hidePassword ? root.mauve : root.surface2
                                Behavior on color { ColorAnimation { duration: 250 } }
                                
                                Rectangle {
                                    width: height; height: 18 * screenRoot.sc; radius: height / 2
                                    x: lockSettings.hidePassword ? parent.width - width - (2 * screenRoot.sc) : (2 * screenRoot.sc)
                                    y: (parent.height - height) / 2
                                    color: root.base
                                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                }
                                MouseArea { 
                                    anchors.fill: parent; 
                                    onClicked: {
                                        lockSettings.hidePassword = !lockSettings.hidePassword;
                                        if (lockSettings.hidePassword) {
                                            for(let i = 0; i < passModel.count; i++) passModel.setProperty(i, "isDot", true);
                                        }
                                    }
                                }
                            }
                        }

                        // Reveal Delay Slider
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.leftMargin: 18 * screenRoot.sc; Layout.rightMargin: 18 * screenRoot.sc; Layout.topMargin: 8 * screenRoot.sc; Layout.bottomMargin: 8 * screenRoot.sc; spacing: 8 * screenRoot.sc
                            opacity: lockSettings.hidePassword ? 0.3 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Reveal delay"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 14 * screenRoot.sc
                                    font.weight: Font.Medium
                                    color: root.blue
                                    Layout.fillWidth: true
                                }
                                Text { 
                                    text: lockSettings.revealDuration >= 1000 ? (lockSettings.revealDuration / 1000).toFixed(1) + " s" : lockSettings.revealDuration + " ms"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 13 * screenRoot.sc
                                    font.weight: Font.Bold
                                    color: root.peach
                                }
                            }
                            
                            Item {
                                Layout.fillWidth: true; Layout.preferredHeight: 28 * screenRoot.sc
                                
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width; height: 8 * screenRoot.sc; radius: height / 2; color: root.surface2
                                    Rectangle {
                                        width: ((lockSettings.revealDuration - 100) / 2900) * parent.width
                                        height: parent.height; radius: height / 2; color: root.mauve
                                    }
                                }
                                
                                Rectangle {
                                    id: sliderThumb
                                    width: 20 * screenRoot.sc
                                    height: width
                                    radius: height / 2
                                    color: root.peach
                                    border.color: root.crust; border.width: Math.max(1, 2 * screenRoot.sc)
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: Math.max(0, Math.min(((lockSettings.revealDuration - 100) / 2900) * parent.width - (width / 2), parent.width - width))
                                    
                                    scale: sliderMouse.pressed ? 1.3 : (sliderMouse.containsMouse ? 1.15 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                }
                                
                                MultiEffect {
                                    source: sliderThumb
                                    anchors.fill: sliderThumb
                                    shadowEnabled: true
                                    shadowBlur: 0.5
                                    shadowColor: "#000000"
                                    shadowOpacity: 0.4
                                    shadowVerticalOffset: 2 * screenRoot.sc
                                }

                                MouseArea {
                                    id: sliderMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !lockSettings.hidePassword
                                    preventStealing: true
                                    
                                    function updateVal(mouseX) {
                                        let pct = Math.max(0, Math.min(1, mouseX / width));
                                        let ms = Math.round(100 + (pct * 2900));
                                        if (ms % 100 < 10) ms -= (ms % 100);
                                        else if (ms % 100 > 90) ms += (100 - (ms % 100));
                                        lockSettings.revealDuration = ms;
                                    }

                                    onPositionChanged: (mouse) => {
                                        if (pressed) {
                                            updateVal(mouse.x);
                                        }
                                    }
                                    onPressed: (mouse) => updateVal(mouse.x)
                                }
                            }
                        }

                        // Separator
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: Math.max(1, 1 * screenRoot.sc)
                            color: Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.2)
                            Layout.leftMargin: 18 * screenRoot.sc; Layout.rightMargin: 18 * screenRoot.sc; Layout.topMargin: 4 * screenRoot.sc; Layout.bottomMargin: 4 * screenRoot.sc
                        }

                        // --- SYSTEM ACTIONS SECTION ---
                        Text {
                            text: "SYSTEM"
                            font.family: "JetBrains Mono"
                            font.weight: Font.Black
                            font.pixelSize: 12 * screenRoot.sc
                            font.letterSpacing: 1.5
                            color: root.mauve
                            Layout.leftMargin: 18 * screenRoot.sc; Layout.bottomMargin: 4 * screenRoot.sc
                        }

                        // Manual escape hatch: if the PAM conversation ever wedges
                        // (auth stuck after a failed attempt, input dead), this
                        // re-arms it in place - no process restart, no reboot needed.
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 48 * screenRoot.sc; Layout.leftMargin: 10 * screenRoot.sc; Layout.rightMargin: 10 * screenRoot.sc; radius: 12 * screenRoot.sc
                            color: ma0.containsMouse ? Qt.rgba(root.green.r, root.green.g, root.green.b, 0.1) : "transparent"
                            scale: ma0.pressed ? 0.95 : (ma0.containsMouse ? 1.02 : 1.0)
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 16 * screenRoot.sc; anchors.rightMargin: 16 * screenRoot.sc; spacing: 0
                                Text { text: "󰑓"; font.family: "Iosevka Nerd Font"; font.pixelSize: 18 * screenRoot.sc; color: ma0.containsMouse ? root.green : Qt.rgba(root.green.r, root.green.g, root.green.b, 0.6); Behavior on color { ColorAnimation { duration: 200 } } }
                                Item { Layout.fillWidth: true }
                                Text { text: "Reset Login"; font.family: "JetBrains Mono"; font.pixelSize: 15 * screenRoot.sc; font.weight: Font.Medium; color: ma0.containsMouse ? root.green : Qt.rgba(root.green.r, root.green.g, root.green.b, 0.6); Behavior on color { ColorAnimation { duration: 200 } } }
                            }
                            MouseArea {
                                id: ma0; anchors.fill: parent; hoverEnabled: true;
                                onClicked: {
                                    screenRoot.powerMenuOpen = false;
                                    lockUI.reset(false);
                                    inputField.forceActiveFocus();
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 48 * screenRoot.sc; Layout.leftMargin: 10 * screenRoot.sc; Layout.rightMargin: 10 * screenRoot.sc; radius: 12 * screenRoot.sc
                            color: ma1.containsMouse ? Qt.rgba(root.blue.r, root.blue.g, root.blue.b, 0.1) : "transparent"
                            scale: ma1.pressed ? 0.95 : (ma1.containsMouse ? 1.02 : 1.0)
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 16 * screenRoot.sc; anchors.rightMargin: 16 * screenRoot.sc; spacing: 0
                                Text { text: "󰜉"; font.family: "Iosevka Nerd Font"; font.pixelSize: 18 * screenRoot.sc; color: ma1.containsMouse ? root.blue : Qt.rgba(root.blue.r, root.blue.g, root.blue.b, 0.6); Behavior on color { ColorAnimation { duration: 200 } } }
                                Item { Layout.fillWidth: true }
                                Text { text: "Reboot"; font.family: "JetBrains Mono"; font.pixelSize: 15 * screenRoot.sc; font.weight: Font.Medium; color: ma1.containsMouse ? root.blue : Qt.rgba(root.blue.r, root.blue.g, root.blue.b, 0.6); Behavior on color { ColorAnimation { duration: 200 } } }
                            }
                            MouseArea {
                                id: ma1; anchors.fill: parent; hoverEnabled: true;
                                onClicked: {
                                    screenRoot.powerMenuOpen = false;
                                    reloadProcess.running = true;
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 48 * screenRoot.sc; Layout.leftMargin: 10 * screenRoot.sc; Layout.rightMargin: 10 * screenRoot.sc; radius: 12 * screenRoot.sc
                            color: ma2.containsMouse ? Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.1) : "transparent"
                            scale: ma2.pressed ? 0.95 : (ma2.containsMouse ? 1.02 : 1.0)
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 16 * screenRoot.sc; anchors.rightMargin: 16 * screenRoot.sc; spacing: 0
                                Text { text: "󰒲"; font.family: "Iosevka Nerd Font"; font.pixelSize: 18 * screenRoot.sc; color: ma2.containsMouse ? root.mauve : Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.6); Behavior on color { ColorAnimation { duration: 200 } } }
                                Item { Layout.fillWidth: true }
                                Text { text: "Suspend"; font.family: "JetBrains Mono"; font.pixelSize: 15 * screenRoot.sc; font.weight: Font.Medium; color: ma2.containsMouse ? root.mauve : Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.6); Behavior on color { ColorAnimation { duration: 200 } } }
                            }
                            MouseArea { 
                                id: ma2; anchors.fill: parent; hoverEnabled: true;
                                onClicked: {
                                    screenRoot.powerMenuOpen = false;
                                    suspendProcess.running = true;
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 48 * screenRoot.sc; Layout.leftMargin: 10 * screenRoot.sc; Layout.rightMargin: 10 * screenRoot.sc; Layout.bottomMargin: 8 * screenRoot.sc; radius: 12 * screenRoot.sc
                            color: ma3.containsMouse ? Qt.rgba(root.red.r, root.red.g, root.red.b, 0.1) : "transparent"
                            scale: ma3.pressed ? 0.95 : (ma3.containsMouse ? 1.02 : 1.0)
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 16 * screenRoot.sc; anchors.rightMargin: 16 * screenRoot.sc; spacing: 0
                                Text { text: "󰐥"; font.family: "Iosevka Nerd Font"; font.pixelSize: 18 * screenRoot.sc; color: ma3.containsMouse ? root.red : Qt.rgba(root.red.r, root.red.g, root.red.b, 0.6); Behavior on color { ColorAnimation { duration: 200 } } }
                                Item { Layout.fillWidth: true }
                                Text { text: "Power Off"; font.family: "JetBrains Mono"; font.pixelSize: 15 * screenRoot.sc; font.weight: Font.Medium; color: ma3.containsMouse ? root.red : Qt.rgba(root.red.r, root.red.g, root.red.b, 0.6); Behavior on color { ColorAnimation { duration: 200 } } }
                            }
                            MouseArea { 
                                id: ma3; anchors.fill: parent; hoverEnabled: true;
                                onClicked: {
                                    screenRoot.powerMenuOpen = false;
                                    poweroffProcess.running = true;
                                }
                            }
                        }
                    }
                }

                // Enlarged Power Button
                Rectangle {
                    id: powerBtn
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.margins: 40 * screenRoot.sc
                    width: 52 * screenRoot.sc
                    height: width
                    radius: height / 2
                    
                    color: screenRoot.powerMenuOpen 
                            ? root.surface2 
                            : (powerBtnMa.containsMouse ? Qt.rgba(root.surface1.r, root.surface1.g, root.surface1.b, 0.8) : Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.4))
                    border.color: screenRoot.powerMenuOpen ? root.text : Qt.rgba(root.text.r, root.text.g, root.text.b, 0.15)
                    border.width: Math.max(1, 1 * screenRoot.sc)

                    opacity: screenRoot.introState
                    transform: Translate { y: (20 * screenRoot.sc) * (1.0 - screenRoot.introState) }
                    
                    scale: powerBtnMa.pressed ? 0.9 : (powerBtnMa.containsMouse ? 1.08 : 1.0)

                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }
                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰐥"
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: 22 * screenRoot.sc
                        color: screenRoot.powerMenuOpen ? root.red : (powerBtnMa.containsMouse ? root.text : root.subtext0)
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    MouseArea {
                        id: powerBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !screenRoot.isPlayingIntro
                        onClicked: {
                            screenRoot.powerMenuOpen = !screenRoot.powerMenuOpen;
                            if (!screenRoot.powerMenuOpen) inputField.forceActiveFocus();
                        }
                    }
                }

                // ---------------------------------------------------------
                // 5. INTRO ANIMATION OVERLAY
                // ---------------------------------------------------------
                Item {
                    id: introOverlay
                    anchors.fill: parent
                    z: 999
                    visible: screenRoot.isPlayingIntro || opacity > 0

                    Rectangle {
                        id: ring3
                        width: 360 * screenRoot.sc
                        height: width
                        radius: height / 2 
                        anchors.centerIn: parent
                        color: "transparent"
                        border.color: root.mauve
                        border.width: Math.max(1, 1 * screenRoot.sc)
                        scale: 0.5
                        opacity: 0.0
                    }
                    Rectangle {
                        id: ring2
                        width: 300 * screenRoot.sc
                        height: width
                        radius: height / 2 
                        anchors.centerIn: parent
                        color: "transparent"
                        border.color: root.text
                        border.width: Math.max(1, 1 * screenRoot.sc)
                        scale: 0.8
                        opacity: 0.0
                    }
                    Rectangle {
                        id: ring1
                        width: 240 * screenRoot.sc
                        height: width
                        radius: height / 2 
                        anchors.centerIn: parent
                        color: "transparent"
                        border.color: root.text
                        border.width: Math.max(1, 2 * screenRoot.sc)
                        scale: 0.8
                        opacity: 0.0
                    }

                    Item {
                        id: introLockOrb
                        width: 170 * screenRoot.sc
                        height: width
                        anchors.centerIn: parent
                        scale: 0.0
                        opacity: 0.0
                        
                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.9)
                            border.color: root.text
                            border.width: Math.max(1, 2 * screenRoot.sc)
                        }

                        Text {
                            id: introIconUnlocked
                            anchors.centerIn: parent
                            text: "󰌿"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: 64 * screenRoot.sc 
                            color: root.text
                            opacity: 1.0
                            scale: 1.0
                            transformOrigin: Item.Center
                        }

                        Text {
                            id: introIconLocked
                            anchors.centerIn: parent
                            text: "󰌾"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: 64 * screenRoot.sc 
                            color: root.text
                            opacity: 0.0
                            scale: 1.6
                            transformOrigin: Item.Center
                        }
                    }

                    SequentialAnimation {
                        id: introSequence
                        
                        ParallelAnimation {
                            NumberAnimation { target: introLockOrb; property: "scale"; from: 0.0; to: 1.0; duration: 300; easing.type: Easing.OutCubic }
                            NumberAnimation { target: introLockOrb; property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                            
                            NumberAnimation { target: ring1; property: "scale"; from: 0.8; to: 1.25; duration: 250; easing.type: Easing.OutCubic }
                            NumberAnimation { target: ring1; property: "opacity"; from: 0.6; to: 0.0; duration: 250; easing.type: Easing.OutCubic }
                            
                            NumberAnimation { target: ring2; property: "scale"; from: 0.8; to: 1.4; duration: 300; easing.type: Easing.OutCubic }
                            NumberAnimation { target: ring2; property: "opacity"; from: 0.4; to: 0.0; duration: 300; easing.type: Easing.OutCubic }

                            NumberAnimation { target: ring3; property: "scale"; from: 0.5; to: 1.5; duration: 350; easing.type: Easing.OutCubic }
                            NumberAnimation { target: ring3; property: "opacity"; from: 0.3; to: 0.0; duration: 350; easing.type: Easing.OutCubic }
                            
                            SequentialAnimation {
                                PauseAnimation { duration: 300 } 
                                ParallelAnimation {
                                    NumberAnimation { target: introIconUnlocked; property: "scale"; from: 1.0; to: 0.5; duration: 100; easing.type: Easing.InCubic }
                                    NumberAnimation { target: introIconUnlocked; property: "opacity"; from: 1.0; to: 0.0; duration: 50 }
                                    
                                    NumberAnimation { target: introIconLocked; property: "scale"; from: 1.6; to: 1.0; duration: 200; easing.type: Easing.OutBack }
                                    NumberAnimation { target: introIconLocked; property: "opacity"; from: 0.0; to: 1.0; duration: 100 }
                                    
                                    SequentialAnimation {
                                        NumberAnimation { target: introLockOrb; property: "anchors.verticalCenterOffset"; from: 0; to: 3 * screenRoot.sc; duration: 40; easing.type: Easing.OutQuad }
                                        NumberAnimation { target: introLockOrb; property: "anchors.verticalCenterOffset"; from: 3 * screenRoot.sc; to: 0; duration: 120; easing.type: Easing.OutBack }
                                    }
                                }
                            }
                        }
                        
                        PauseAnimation { duration: 50 }

                        SequentialAnimation {
                            ParallelAnimation {
                                NumberAnimation { target: introLockOrb; property: "scale"; to: 1.8; duration: 100; easing.type: Easing.InCubic }
                                NumberAnimation { target: introOverlay; property: "opacity"; to: 0.0; duration: 100; easing.type: Easing.InCubic }
                            }
                            
                            NumberAnimation { target: screenRoot; property: "introState"; from: 0.0; to: 1.0; duration: 100; easing.type: Easing.OutCubic }
                        }

                        PropertyAction { target: screenRoot; property: "isPlayingIntro"; value: false }
                        ScriptAction { script: { inputField.text = ""; inputField.forceActiveFocus(); } }
                    }
                }

}
