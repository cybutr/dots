import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./"

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string lifeline: home + "/.config/hypr/scripts/quickshell/lifeline.sh"
    readonly property string triggerFile: "/tmp/qs_idle_ambient"
    readonly property string lockCheck: "pgrep -a -x quickshell | grep -qE '/Lock(Legacy)?[.]qml'"

    MatugenColors { id: _theme }

    property bool enabled: true
    property bool shown: false
    property bool testMode: false
    property string forcedMode: ""
    property bool musicPlaying: false
    property string musicTitle: ""
    property string musicArtist: ""
    property string musicBlur: ""
    property real bpm: 0
    property color albumColor: _theme.mauve
    property real audioLevel: 0
    Behavior on audioLevel { NumberAnimation { duration: 700; easing.type: Easing.OutQuad } }

    readonly property bool musicMode: root.forcedMode === "music" || (root.forcedMode === "" && root.musicPlaying)
    property var wallpapers: ({})
    property string cursorBaseline: ""

    function show(test, mode) {
        root.testMode = test
        root.forcedMode = mode
        root.cursorBaseline = ""
        wallReader.running = false; wallReader.running = true
        musicReader.running = false; musicReader.running = true
        root.shown = true
        lifeCap.restart()
    }
    function hide() {
        root.shown = false
        root.testMode = false
        root.forcedMode = ""
        root.audioLevel = 0
        lifeCap.stop()
    }

    function handle(cmd) {
        cmd = cmd.trim()
        if (cmd === "off") { root.hide(); return }
        if (cmd === "on") { if (root.enabled && !root.shown) { gateCheck.running = false; gateCheck.running = true } return }
        if (cmd === "test") root.show(true, "")
        else if (cmd === "test-music") root.show(true, "music")
        else if (cmd === "test-wall") root.show(true, "wall")
    }

    Process {
        id: trigger
        command: [root.lifeline, "f=/tmp/qs_idle_ambient; [ -f \"$f\" ] || echo off > \"$f\"; while inotifywait -qq -e close_write \"$f\"; do cat \"$f\"; echo; done"]
        running: true
        stdout: SplitParser { onRead: (line) => { if (line.trim() !== "") root.handle(line) } }
        onExited: respawn.restart()
    }
    Timer { id: respawn; interval: 1000; onTriggered: trigger.running = true }

    Process {
        id: gateCheck
        command: ["bash", "-c", root.lockCheck + " && echo locked || echo free"]
        stdout: StdioCollector { onStreamFinished: if (this.text.trim() === "free" && root.enabled) root.show(false, "") }
    }

    Process {
        id: settingsReader
        command: ["bash", "-c", "jq -r 'if has(\"idleAmbientEnabled\") then .idleAmbientEnabled else true end' ~/.config/hypr/settings.json 2>/dev/null || echo true"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.enabled = this.text.trim() !== "false"
                if (!root.enabled && !root.testMode) root.hide()
            }
        }
    }
    Process {
        id: settingsWatcher
        command: [root.lifeline, "while [ ! -f ~/.config/hypr/settings.json ]; do sleep 1; done; exec inotifywait -qq -e modify,close_write ~/.config/hypr/settings.json"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                settingsReader.running = false; settingsReader.running = true
                settingsWatcher.running = false; settingsWatcher.running = true
            }
        }
    }

    Process {
        id: wallReader
        command: ["bash", "-c", "awww query 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let map = {}
                for (let l of this.text.split("\n")) {
                    let m = /^:?\s*([^:]+):.*image:\s*(.+)$/.exec(l.trim())
                    if (m) map[m[1].trim()] = "file://" + m[2].trim()
                }
                root.wallpapers = map
            }
        }
    }

    Process {
        id: musicReader
        command: ["bash", "-c", "cat /tmp/music_info.json 2>/dev/null || echo '{}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(this.text.trim() || "{}")
                    root.musicPlaying = d.status === "Playing"
                    root.bpm = d.bpm || 0
                    root.musicTitle = d.title || ""
                    root.musicArtist = d.artist || ""
                    root.musicBlur = d.blur ? "file://" + d.blur : ""
                    let m = /#([0-9A-Fa-f]{6})/.exec(d.vibrantGrad || d.grad || "")
                    if (m) {
                        let c = Qt.color("#" + m[1])
                        root.albumColor = (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.18 ? _theme.mauve : c
                    }
                } catch (e) {}
            }
        }
    }
    Timer { interval: 2000; repeat: true; running: root.shown; onTriggered: if (!musicReader.running) musicReader.running = true }

    Timer {
        interval: 900; repeat: true; triggeredOnStart: true
        running: root.shown && root.musicMode
        onTriggered: if (!audioProc.running) audioProc.running = true
    }
    Process {
        id: audioProc
        command: [root.lifeline, "$HOME/.config/hypr/scripts/quickshell/music/audio_level.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                let v = parseFloat(this.text.trim())
                if (!isNaN(v) && root.shown) root.audioLevel = Math.max(0, Math.min(1, v))
            }
        }
    }

    Timer {
        interval: 400; repeat: true; running: root.shown
        onTriggered: if (!guardProc.running) guardProc.running = true
    }
    Process {
        id: guardProc
        command: [root.lifeline, "hyprctl cursorpos 2>/dev/null; " + root.lockCheck + " && echo LOCKED; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.shown) return
                let out = this.text.trim()
                if (out.indexOf("LOCKED") !== -1) { root.hide(); return }
                let pos = out.split("\n")[0].trim()
                if (pos === "") return
                if (root.cursorBaseline === "") root.cursorBaseline = pos
                else if (pos !== root.cursorBaseline) root.hide()
            }
        }
    }

    Timer { id: lifeCap; interval: root.testMode ? 60000 : 300000; onTriggered: root.hide() }

    readonly property real beatIntervalMs: (root.bpm >= 40 && root.bpm <= 220) ? (60000.0 / root.bpm) * 2 : 4200
    property real beatPulse: 0
    SequentialAnimation {
        loops: Animation.Infinite
        running: root.shown && root.musicMode
        NumberAnimation { target: root; property: "beatPulse"; to: 1.0; duration: root.beatIntervalMs * 0.4; easing.type: Easing.OutSine }
        NumberAnimation { target: root; property: "beatPulse"; to: 0.0; duration: root.beatIntervalMs * 0.6; easing.type: Easing.InOutSine }
    }

    property real orbit: 0
    NumberAnimation on orbit { from: 0; to: 1; duration: 90000; loops: Animation.Infinite; running: root.shown }

    property real drift: 0
    SequentialAnimation on drift {
        running: root.shown
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 40000; easing.type: Easing.InOutSine }
        NumberAnimation { to: -1; duration: 40000; easing.type: Easing.InOutSine }
    }

    property real moteT: 0
    NumberAnimation on moteT { from: 0; to: 1; duration: 60000; loops: Animation.Infinite; running: root.shown && root.musicMode }

    component Glow: Canvas {
        id: glow
        property color tint: "transparent"
        onTintChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            let ctx = getContext("2d")
            ctx.reset()
            let r = width / 2
            let c = (a) => "rgba(" + Math.round(tint.r * 255) + "," + Math.round(tint.g * 255) + "," + Math.round(tint.b * 255) + "," + a + ")"
            let g = ctx.createRadialGradient(r, r, 0, r, r, r)
            g.addColorStop(0.0, c(0.55))
            g.addColorStop(0.35, c(0.28))
            g.addColorStop(0.7, c(0.08))
            g.addColorStop(1.0, c(0))
            ctx.fillStyle = g
            ctx.fillRect(0, 0, width, height)
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: win
                required property var modelData
                screen: modelData

                color: "transparent"
                WlrLayershell.namespace: "qs-idle-ambient"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                exclusionMode: ExclusionMode.Ignore
                focusable: false
                anchors { top: true; bottom: true; left: true; right: true }

                mask: Region { item: noHit }
                Item { id: noHit; width: 0; height: 0 }

                visible: root.shown

                Scaler { id: scaler; currentWidth: win.width }
                function s(v) { return scaler.s(v) }

                readonly property string wallSrc: root.wallpapers[win.modelData.name] || Object.values(root.wallpapers)[0] || ""

                Item {
                    id: stage
                    anchors.fill: parent
                    opacity: 0
                    clip: true

                    Connections {
                        target: root
                        function onShownChanged() {
                            fadeIn.stop()
                            stage.opacity = 0
                            if (root.shown) fadeIn.start()
                        }
                    }
                    NumberAnimation { id: fadeIn; target: stage; property: "opacity"; from: 0; to: 1; duration: 2800; easing.type: Easing.InOutSine }

                    Rectangle { anchors.fill: parent; color: _theme.crust }

                    Item {
                        id: wallLayer
                        anchors.fill: parent
                        opacity: root.musicMode ? 0 : 1
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 1400; easing.type: Easing.InOutSine } }

                        Image {
                            source: win.wallSrc
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            sourceSize.width: win.width * 1.2
                            width: parent.width * 1.12
                            height: parent.height * 1.12
                            x: -parent.width * 0.06 + root.drift * parent.width * 0.035
                            y: -parent.height * 0.06 + Math.sin(root.drift * 1.6) * parent.height * 0.025
                            scale: 1.0 + (Math.sin(root.orbit * Math.PI * 2) + 1) * 0.025
                            smooth: true
                        }
                        Rectangle { anchors.fill: parent; color: "black"; opacity: 0.12 }
                    }

                    Item {
                        id: musicLayer
                        anchors.fill: parent
                        opacity: root.musicMode ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 1400; easing.type: Easing.InOutSine } }

                        Image {
                            source: root.musicBlur !== "" ? root.musicBlur : win.wallSrc
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            width: parent.width * 1.12
                            height: parent.height * 1.12
                            x: -parent.width * 0.06 + root.drift * parent.width * 0.025
                            y: -parent.height * 0.06 + Math.cos(root.drift * 1.3) * parent.height * 0.02
                            smooth: true
                        }
                        Rectangle { anchors.fill: parent; color: _theme.crust; opacity: 0.42 }

                        readonly property real amp: 0.45 + root.audioLevel * 0.9

                        Glow {
                            tint: root.albumColor
                            width: Math.max(parent.width, parent.height) * 0.95
                            height: width
                            x: parent.width * 0.5 - width / 2 + Math.cos(root.orbit * Math.PI * 2) * parent.width * 0.06
                            y: parent.height * 0.5 - height / 2 + Math.sin(root.orbit * Math.PI * 2) * parent.height * 0.05
                            scale: 1.0 + root.beatPulse * 0.07 * musicLayer.amp
                            opacity: 0.7 + root.beatPulse * 0.25 * musicLayer.amp
                        }
                        Glow {
                            tint: _theme.mauve
                            width: Math.max(parent.width, parent.height) * 0.6
                            height: width
                            x: parent.width * 0.22 - width / 2 + Math.sin(root.orbit * Math.PI * 4) * parent.width * 0.08
                            y: parent.height * 0.7 - height / 2 + Math.cos(root.orbit * Math.PI * 2) * parent.height * 0.08
                            scale: 1.0 + root.beatPulse * 0.05 * musicLayer.amp
                            opacity: 0.45 + root.beatPulse * 0.2 * musicLayer.amp
                        }
                        Glow {
                            tint: _theme.blue
                            width: Math.max(parent.width, parent.height) * 0.55
                            height: width
                            x: parent.width * 0.8 - width / 2 + Math.cos(root.orbit * Math.PI * 4) * parent.width * 0.07
                            y: parent.height * 0.3 - height / 2 + Math.sin(root.orbit * Math.PI * 2) * parent.height * 0.08
                            scale: 1.0 + (1 - root.beatPulse) * 0.04 * musicLayer.amp
                            opacity: 0.38 + (1 - root.beatPulse) * 0.18 * musicLayer.amp
                        }

                        Repeater {
                            model: 26
                            delegate: Rectangle {
                                required property int index
                                readonly property real seed: (index * 0.6180339) % 1
                                readonly property int speed: index % 3 === 0 ? 2 : 1
                                readonly property real prog: (root.moteT * speed + seed) % 1
                                width: win.s(2 + (index % 4))
                                height: width
                                radius: width / 2
                                color: index % 2 === 0 ? root.albumColor : _theme.text
                                x: musicLayer.width * ((seed * 7.31) % 1) + Math.sin(prog * Math.PI * 4 + index) * win.s(24)
                                y: musicLayer.height + win.s(10) - prog * (musicLayer.height + win.s(20))
                                opacity: Math.sin(prog * Math.PI) * (0.18 + root.beatPulse * 0.22 * musicLayer.amp)
                            }
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: win.s(64)
                            anchors.bottomMargin: win.s(56)
                            spacing: win.s(4)
                            opacity: 0.55 + root.beatPulse * 0.1
                            Text {
                                text: root.musicTitle
                                width: Math.min(implicitWidth, win.width * 0.5)
                                elide: Text.ElideRight
                                font.family: "JetBrains Mono"; font.weight: Font.Black
                                font.pixelSize: win.s(22)
                                color: _theme.text
                            }
                            Text {
                                text: root.musicArtist
                                width: Math.min(implicitWidth, win.width * 0.5)
                                elide: Text.ElideRight
                                font.family: "JetBrains Mono"
                                font.pixelSize: win.s(14)
                                color: _theme.subtext0
                            }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        height: parent.height * 0.35
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.35) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }
                    Rectangle {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                        height: parent.height * 0.4
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
                        }
                    }
                }
            }
        }
    }
}
