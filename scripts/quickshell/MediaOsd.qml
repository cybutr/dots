import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Wayland
import "./"

// Spotify transport OSD. trigger file payload:
//   "<icon-key>\t<line1>\t<line2>"                     - transport, no progress bar
//   "<icon-key>\t<line1>\t<line2>\t<pos-sec>\t<len-sec>" - transport + progress bar
// icon-key: play | pause | next | prev | seek-back | seek-fwd
OsdBase {
    id: osd
    WlrLayershell.namespace: "qs-media-osd"
    watchFile: "/tmp/qs_media_osd"
    holdMs: 1600
    // Dark album-art colors (near-black) would be unreadable against this
    // dark pill — floor lightness/saturation so the accent always reads clearly.
    // Gated by the same "Hyprland Border Pulse" settings toggle the border-pulse
    // effect uses — off reverts this OSD to its original plain green look too.
    accent: {
        if (!osd.dynamicColorsEnabled || osd.songAccent === "") return osd.cGreen || "#a6e3a1"
        let raw = Qt.color(osd.songAccent)
        let l = Math.max(raw.hslLightness, 0.55)
        let s = Math.max(raw.hslSaturation, 0.4)
        return Qt.hsla(raw.hslHue, s, l, 1.0)
    }

    property bool dynamicColorsEnabled: true
    Process {
        id: settingsReader
        command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let parsed = JSON.parse(this.text || "{}");
                    if (parsed.hyprlandBorderPulseEnabled !== undefined) osd.dynamicColorsEnabled = parsed.hyprlandBorderPulseEnabled;
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

    property string iconKey: "play"
    property string line1: ""
    property string line2: ""
    property bool showProgress: false
    property real position: 0
    property real length: 0
    readonly property bool playing: osd.iconKey === "play" || osd.iconKey === "seek-back" || osd.iconKey === "seek-fwd"

    // song-derived accent/tempo (music_info.sh: grad = album art quantized colors,
    // bpm = locally analyzed, cached per track). Both default to "unavailable" so the
    // bar degrades to the plain green/static look until they're ready.
    property string songAccent: ""
    property real bpm: 0
    readonly property real beatMs: osd.bpm > 0 ? 60000 / osd.bpm : 500

    onTriggered: (text) => {
        let p = text.split("\t")
        osd.iconKey = p[0] || "play"
        osd.line1 = p[1] || ""
        osd.line2 = p[2] || ""
        osd.showProgress = p.length >= 5 && p[4] !== ""
        osd.position = osd.showProgress ? (parseFloat(p[3]) || 0) : 0
        osd.length = osd.showProgress ? (parseFloat(p[4]) || 0) : 0
        if (!songInfoProc.running) songInfoProc.running = true
    }

    // fetched once per trigger (matches the OSD's own transient lifecycle) rather
    // than polled continuously — bpm/grad are cached per track anyway.
    Process {
        id: songInfoProc
        command: ["bash", "-c", "$HOME/.config/hypr/scripts/quickshell/music/music_info.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!this.text) return
                try {
                    let d = JSON.parse(this.text.trim())
                    osd.bpm = (d.bpm && d.bpm > 0) ? d.bpm : 0
                    let matches = String(d.grad || "").match(/#[0-9a-fA-F]{6}/g)
                    osd.songAccent = (matches && matches.length > 0) ? matches[0] : ""
                } catch (e) {
                    osd.bpm = 0
                    osd.songAccent = ""
                }
            }
        }
    }

    // ticks the bar forward between triggers so it reads as "live" instead
    // of frozen at the moment of the last seek/pause/resume
    Timer {
        interval: 100
        repeat: true
        running: osd.shown && osd.showProgress && osd.playing
        onTriggered: osd.position = Math.min(osd.length, osd.position + interval / 1000)
    }

    readonly property string glyph: {
        if (osd.iconKey === "pause") return "󰏤"
        if (osd.iconKey === "next") return "󰒭"
        if (osd.iconKey === "prev") return "󰒮"
        if (osd.iconKey === "seek-back") return "󰒮"
        if (osd.iconKey === "seek-fwd") return "󰒭"
        return "󰐊"
    }

    ColumnLayout {
        spacing: osd.s(6)

        RowLayout {
            spacing: osd.s(12)
            Text {
                font.family: "Iosevka Nerd Font"; font.pixelSize: osd.s(22)
                color: osd.accent
                text: osd.glyph
            }
            ColumnLayout {
                spacing: 0
                Text {
                    font.family: "JetBrains Mono"; font.weight: Font.Black
                    font.pixelSize: osd.s(15); color: osd.cText
                    elide: Text.ElideRight
                    Layout.maximumWidth: osd.s(220)
                    text: osd.line1
                }
                Text {
                    visible: osd.line2 !== ""
                    font.family: "JetBrains Mono"; font.pixelSize: osd.s(11)
                    color: osd.cSubtext0
                    elide: Text.ElideRight
                    Layout.maximumWidth: osd.s(220)
                    text: osd.line2
                }
            }
        }

        Rectangle {
            id: track
            visible: osd.showProgress
            Layout.fillWidth: true
            Layout.preferredHeight: osd.s(3)
            Layout.topMargin: osd.s(2)
            radius: height / 2
            color: Qt.rgba(osd.cText.r, osd.cText.g, osd.cText.b, 0.12)
            clip: true

            Rectangle {
                id: fill
                height: parent.height
                width: parent.width * (osd.length > 0 ? Math.min(1, osd.position / osd.length) : 0)
                radius: parent.height / 2
                color: osd.accent
                clip: true

                // beat-synced breathing — only when a real bpm was analyzed, otherwise
                // stays a flat fill (graceful degrade, no fake tempo)
                SequentialAnimation on opacity {
                    running: osd.dynamicColorsEnabled && osd.shown && osd.showProgress && osd.playing && osd.bpm > 0
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.72; duration: osd.beatMs * 0.5; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: osd.beatMs * 0.5; easing.type: Easing.InOutSine }
                }

                // slow shimmer sweeping across the filled portion — pure motion, no
                // data dependency, so it always runs while a song is actually playing
                Rectangle {
                    id: shimmer
                    width: track.height * 6
                    height: parent.height
                    x: -width
                    visible: osd.dynamicColorsEnabled && fill.width > 0
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.55) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }

                    NumberAnimation on x {
                        running: osd.dynamicColorsEnabled && osd.shown && osd.showProgress && osd.playing
                        loops: Animation.Infinite
                        from: -shimmer.width
                        to: fill.width + shimmer.width
                        duration: 1800
                    }
                }
            }
        }
    }
}
