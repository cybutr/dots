import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../"
import "fuzzy.js" as Fuzzy

FocusScope {
    id: root
    focus: true
    onActiveFocusChanged: if (activeFocus) input.forceActiveFocus()

    property string widgetArg: ""
    onWidgetArgChanged: if (widgetArg !== "") { input.text = widgetArg; input.cursorPosition = widgetArg.length }

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(v) { return scaler.s(v) }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color subtext1: _theme.subtext1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color seed: _theme.blue
    readonly property color danger: _theme.red

    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: home + "/.config/hypr/scripts/quickshell/palette"
    readonly property string mira: home + "/.config/hypr/scripts/quickshell/claude/mira_mail.py"
    readonly property string mono: "JetBrains Mono"
    readonly property string glyphs: "Iosevka Nerd Font"

    property var actions: []
    property var history: ({})
    property var results: []
    property int sel: 0
    property string confirmId: ""
    property var mailHits: []
    property string mailFor: ""
    property bool mailBusy: false
    property string art: ""
    property color artTone: seed
    property int pop: 0
    readonly property int rowsShown: 6
    readonly property var defaults: ["claude.ask", "media.playpause", "sys.nightlight", "setting.ecoModeEnabled", "timer.25", "wall.random", "mail.search", "capture.region", "power.lock"]

    readonly property var current: results.length > 0 ? results[Math.min(sel, results.length - 1)] : null
    readonly property var act: current ? current.a : null
    readonly property bool confirming: act !== null && confirmId === act.id
    readonly property var paramInfo: resolveParam(current)

    readonly property real hue0: seed.hslHue < 0 ? 0.62 : seed.hslHue
    readonly property var catShift: ({
        media: 0.0, audio: 0.07, timer: 0.13, widget: 0.2, mail: 0.28, app: 0.36, layout: 0.44,
        system: 0.5, wallpaper: 0.57, setting: 0.64, claude: 0.74, capture: 0.84, power: 0.92,
        window: 0.31, workspace: 0.4, device: 0.03
    })
    readonly property var catName: ({
        media: "Media", audio: "Sound", timer: "Timer", widget: "Widget", mail: "Mail", app: "App",
        layout: "Layout", system: "System", wallpaper: "Wallpaper", setting: "Setting", claude: "Claude",
        capture: "Capture", power: "Power", window: "Window", workspace: "Workspace", device: "Device"
    })
    function tint(cat) {
        let h = (root.hue0 + (root.catShift[cat] || 0)) % 1
        return Qt.hsla(h, 0.62, 0.7, 1)
    }
    function hex(c, a) {
        let h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2)
        return "#" + (a === undefined ? "" : h(a)) + h(c.r) + h(c.g) + h(c.b)
    }
    function g(cp) { return String.fromCodePoint(cp) }
    function esc(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    function marked(label, hits, on, off) {
        if (!hits || hits.length === 0) return "<font color='" + off + "'>" + esc(label) + "</font>"
        let set = {}
        for (let i = 0; i < hits.length; i++) set[hits[i]] = true
        let out = "", run = "", runOn = null
        for (let i = 0; i < label.length; i++) {
            let o = !!set[i]
            if (runOn !== null && o !== runOn) { out += "<font color='" + (runOn ? on : off) + "'>" + esc(run) + "</font>"; run = "" }
            run += label[i]; runOn = o
        }
        if (run !== "") out += "<font color='" + (runOn ? on : off) + "'>" + esc(run) + "</font>"
        return out
    }
    function iconSrc(a) {
        if (!a || !a.image) return ""
        return a.image.startsWith("/") ? "file://" + a.image : "image://icon/" + a.image
    }
    function close() { Quickshell.execDetached(["bash", "-c", "echo close > /tmp/qs_widget_state"]) }

    function resolveParam(r) {
        if (!r || !r.a.param) return { ok: true, value: "", show: "" }
        let p = r.a.param
        if (p.kind === "number") {
            let v = parseFloat(r.param)
            if (isNaN(v)) {
                if (p.default !== undefined) return { ok: true, value: String(p.default), show: String(p.default), unit: p.unit || "", implied: true }
                return { ok: !p.required, value: "", show: "", unit: p.unit || "", missing: p.required }
            }
            v = Math.max(p.min !== undefined ? p.min : v, Math.min(p.max !== undefined ? p.max : v, Math.round(v)))
            return { ok: true, value: String(v), show: String(v), unit: p.unit || "" }
        }
        let t = (r.param || "").trim()
        if (t === "") return { ok: !p.required, value: "", show: "", missing: !!p.required, hint: p.hint || "" }
        return { ok: true, value: t, show: t }
    }

    function recompute() {
        let keepId = root.act ? root.act.id : ""
        let q = input.text
        let r = Fuzzy.rank(root.actions, q, root.history, 40)
        if (q.trim() === "") {
            let have = {}
            for (let i = 0; i < r.length; i++) have[r[i].a.id] = true
            for (let i = 0; i < root.defaults.length && r.length < 12; i++) {
                let a = root.byId(root.defaults[i])
                if (a && !have[a.id]) r.push({ a: a, score: 0, hits: [], param: "" })
            }
        } else {
            if (r.length > 0 && r[0].a.live === "mail" && root.mailHits.length > 0 && root.mailFor === r[0].param.trim()) {
                let hits = root.mailHits.map(m => ({ a: m, score: 0, hits: [], param: "" }))
                r = [r[0]].concat(hits, r.slice(1))
            }
            let ask = root.byId("claude.ask")
            if (ask && !r.some(x => x.a.id === "claude.ask")) r.push({ a: ask, score: -99, hits: [], param: q.trim() })
        }
        root.results = r
        let idx = 0
        if (keepId !== "" && q === root.lastQuery) {
            for (let i = 0; i < r.length; i++) if (r[i].a.id === keepId) { idx = i; break }
        }
        root.lastQuery = q
        root.sel = idx
        list.positionViewAtIndex(idx, ListView.Contain)
    }
    property string lastQuery: ""
    function byId(id) {
        for (let i = 0; i < root.actions.length; i++) if (root.actions[i].id === id) return root.actions[i]
        return null
    }

    function move(d) {
        if (root.results.length === 0) return
        root.sel = (root.sel + d + root.results.length) % root.results.length
        root.confirmId = ""
        list.positionViewAtIndex(root.sel, ListView.Contain)
    }

    function run() {
        let r = root.current
        if (!r) return
        let a = r.a
        let p = root.paramInfo
        if (!p.ok) { nudge.restart(); return }
        if (a.danger && root.confirmId !== a.id) { root.confirmId = a.id; confirmReset.restart(); return }
        let args = a.args ? a.args : [p.value !== "" ? p.value : (a.arg || "")]
        if (a.id.indexOf("mailhit.") !== 0 && a.id.indexOf("window.") !== 0) Quickshell.execDetached(["python3", root.dir + "/palette_index.py", "used", a.id])
        fireAnim.restart()
        if (a.close !== false) root.close()
        Quickshell.execDetached(["bash", "-c", a.cmd, "_"].concat(args))
    }

    Timer { id: confirmReset; interval: 3500; onTriggered: root.confirmId = "" }

    function ingest(txt) {
        try {
            let d = JSON.parse(txt)
            if (!d.actions) return
            root.actions = d.actions
            root.history = d.history || {}
            root.recompute()
        } catch (e) { }
    }
    Process {
        id: cacheReader
        running: true
        command: ["bash", "-c", "cat \"$HOME/.cache/quickshell/palette/index.json\" 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { if (root.actions.length === 0) root.ingest(this.text) } }
    }
    Process {
        id: builder
        running: true
        command: ["python3", root.dir + "/palette_index.py"]
        stdout: StdioCollector { onStreamFinished: root.ingest(this.text) }
    }
    Process {
        id: musicReader
        running: true
        command: ["bash", root.home + "/.config/hypr/scripts/quickshell/music/music_info.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let m = JSON.parse(this.text.trim() || "{}")
                    if (m.artUrl && (m.status === "Playing" || m.status === "Paused")) root.art = "file://" + m.artUrl
                    let g = (m.vibrantGrad || "").match(/#[0-9a-fA-F]{6}/)
                    if (g) root.artTone = g[0]
                } catch (e) { }
            }
        }
    }

    readonly property string mailWant: (act && act.live === "mail" && current.param.trim().length >= 2) ? current.param.trim() : ""
    onMailWantChanged: {
        if (mailWant === "") { mailDebounce.stop(); return }
        if (mailWant !== mailFor) mailDebounce.restart()
    }
    Timer {
        id: mailDebounce
        interval: 650
        onTriggered: {
            root.mailBusy = true
            mailProc.q = root.mailWant
            mailProc.command = ["python3", root.mira, "search", root.mailWant, "--limit", "4"]
            mailProc.running = false
            mailProc.running = true
        }
    }
    Process {
        id: mailProc
        property string q: ""
        stdout: StdioCollector {
            onStreamFinished: {
                root.mailBusy = false
                let hits = []
                try {
                    let d = JSON.parse(this.text)
                    let rs = (d.results || []).slice(0, 6)
                    for (let i = 0; i < rs.length; i++) {
                        let m = rs[i]
                        let who = (m.from || "").replace(/<[^>]*>/, "").replace(/"/g, "").trim() || m.from
                        hits.push({
                            id: "mailhit." + m.thread_id, label: m.subject || "(no subject)",
                            hint: who + (m.messages > 1 ? ", " + m.messages + " messages" : ""),
                            cat: "mail", icon: m.unread ? root.g(0xF01EE) : root.g(0xF01EF), unread: !!m.unread,
                            keywords: "", verb: "Open in Mira",
                            cmd: "python3 \"$HOME/.config/hypr/scripts/quickshell/claude/mira_mail.py\" open \"$1\" --account \"$2\" >/dev/null",
                            args: [m.thread_id, m.account]
                        })
                    }
                } catch (e) { }
                root.mailHits = hits
                root.mailFor = mailProc.q
                root.recompute()
            }
        }
    }

    onActChanged: root.pop++

    property color iconTone: seed
    property bool iconToneOk: false
    Canvas {
        id: sampler
        width: 8; height: 8
        opacity: 0
        property string src: root.act && root.act.image ? root.iconSrc(root.act) : ""
        onSrcChanged: {
            root.iconToneOk = false
            if (src === "") return
            if (isImageLoaded(src)) requestPaint()
            else loadImage(src)
        }
        onImageLoaded: requestPaint()
        onPaint: {
            let ctx = getContext("2d")
            ctx.clearRect(0, 0, 8, 8)
            if (src === "" || !isImageLoaded(src)) return
            ctx.drawImage(src, 0, 0, 8, 8)
            let d = ctx.getImageData(0, 0, 8, 8).data
            let r = 0, g = 0, b = 0, w = 0
            for (let i = 0; i < d.length; i += 4) {
                let a = d[i + 3] / 255
                if (a < 0.4) continue
                let mx = Math.max(d[i], d[i + 1], d[i + 2]), mn = Math.min(d[i], d[i + 1], d[i + 2])
                let wt = a * (0.08 + (mx - mn) / 255)
                r += d[i] * wt; g += d[i + 1] * wt; b += d[i + 2] * wt; w += wt
            }
            if (w <= 0) return
            root.iconTone = Qt.rgba(r / w / 255, g / w / 255, b / w / 255, 1)
            root.iconToneOk = true
        }
    }
    readonly property bool appHero: !!act && !!act.image && iconToneOk

    property real intro: 0
    NumberAnimation on intro { from: 0; to: 1; duration: 520; easing.type: Easing.OutCubic; running: true }
    property real fire: 0
    NumberAnimation { id: fireAnim; target: root; property: "fire"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Item {
        id: heroWrap
        width: parent.width
        height: root.s(250)
        y: (1 - root.intro) * -root.s(18)
        opacity: Math.min(1, root.intro * 1.6)
        scale: 1 + 0.018 * Math.sin(Math.PI * root.fire)
        transform: Translate { id: shakeT; x: 0 }
        SequentialAnimation {
            id: nudge
            NumberAnimation { target: shakeT; property: "x"; to: -root.s(10); duration: 50 }
            NumberAnimation { target: shakeT; property: "x"; to: root.s(8); duration: 70 }
            NumberAnimation { target: shakeT; property: "x"; to: -root.s(4); duration: 70 }
            NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 80 }
        }
        MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }

        WrappedBackdrop {
            id: hero
            anchors.fill: parent
            radius: root.s(34)
            bedSpread: root.s(22)
            from1: root.confirming ? root.danger : root.appHero ? root.iconTone : (root.act ? root.tint(root.act.cat) : root.seed)
            from2: root.confirming ? Qt.darker(root.danger, 1.3) : root.appHero ? Qt.hsla((root.iconTone.hslHue + 0.09) % 1, 0.7, 0.5, 1) : root.artTone
            art: root.act && root.act.image ? root.iconSrc(root.act) : root.art
            artStrength: root.act && root.act.image ? 0.5 : 0.2
            wash: 0.5

            Item {
                id: ghost
                anchors.fill: parent
                property real swap: 1
                NumberAnimation { id: ghostSwap; target: ghost; property: "swap"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }
                Connections { target: root; function onPopChanged() { ghostSwap.restart() } }
                property real drift: 0
                SequentialAnimation on drift {
                    running: hero.running; loops: Animation.Infinite
                    NumberAnimation { to: 1; duration: 9000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0; duration: 9000; easing.type: Easing.InOutSine }
                }
                Text {
                    visible: !root.act || !root.act.image || ghostIcon.status === Image.Error
                    x: parent.width - width * 0.62 + root.s(30) * (1 - ghost.swap)
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: root.s(18) - root.s(14) * ghost.drift
                    text: root.act ? (root.act.icon || root.g(0xF003B)) : root.g(0xF0349)
                    font.family: root.glyphs; font.pixelSize: hero.height * 1.45
                    color: hero.ink
                    opacity: 0.13 * ghost.swap
                    rotation: -16 + 7 * ghost.drift
                    scale: 1.12 - 0.12 * ghost.swap
                }
                Image {
                    id: ghostIcon
                    visible: !!root.act && !!root.act.image && status !== Image.Error
                    width: hero.height * 1.2; height: width
                    x: parent.width - width * 0.6 + root.s(30) * (1 - ghost.swap)
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: root.s(18) - root.s(14) * ghost.drift
                    source: root.iconSrc(root.act)
                    sourceSize: Qt.size(256, 256)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true; smooth: true
                    opacity: 0.16 * ghost.swap
                    rotation: -16 + 7 * ghost.drift
                }
            }
        }

        Rectangle {
            anchors.fill: hero
            radius: hero.radius
            color: hero.ink
            opacity: 0.22 * (1 - root.fire) * (root.fire > 0 ? 1 : 0)
        }

        Item {
            id: promptRow
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: root.s(32); anchors.rightMargin: root.s(30); anchors.topMargin: root.s(26)
            height: root.s(26)

            Text {
                id: promptGlyph
                anchors.verticalCenter: parent.verticalCenter
                text: root.g(0xF0349)
                font.family: root.glyphs; font.pixelSize: root.s(18)
                color: Qt.alpha(hero.ink, 0.75)
            }
            TextInput {
                id: input
                anchors.left: promptGlyph.right; anchors.leftMargin: root.s(12)
                anchors.right: countText.left; anchors.rightMargin: root.s(16)
                anchors.verticalCenter: parent.verticalCenter
                focus: true
                color: hero.ink
                selectionColor: Qt.alpha(hero.ink, 0.3)
                selectedTextColor: hero.ink
                font.family: root.mono; font.weight: Font.Bold; font.pixelSize: root.s(18)
                clip: true
                cursorDelegate: Rectangle {
                    width: root.s(3); radius: width / 2
                    color: hero.ink
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite; running: input.activeFocus
                        NumberAnimation { to: 1; duration: 80 }
                        PauseAnimation { duration: 480 }
                        NumberAnimation { to: 0.15; duration: 200 }
                        PauseAnimation { duration: 280 }
                    }
                }
                onTextChanged: { root.confirmId = ""; root.recompute() }
                Keys.onPressed: (e) => {
                    let ctrl = e.modifiers & Qt.ControlModifier
                    if (e.key === Qt.Key_Down || (ctrl && e.key === Qt.Key_N) || (e.key === Qt.Key_Tab && !(e.modifiers & Qt.ShiftModifier))) { root.move(1); e.accepted = true }
                    else if (e.key === Qt.Key_Up || (ctrl && e.key === Qt.Key_P) || e.key === Qt.Key_Backtab) { root.move(-1); e.accepted = true }
                    else if (e.key === Qt.Key_PageDown) { root.move(Math.min(5, root.results.length - 1 - root.sel)); e.accepted = true }
                    else if (e.key === Qt.Key_PageUp) { root.move(-Math.min(5, root.sel)); e.accepted = true }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.run(); e.accepted = true }
                    else if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true }
                }
            }
            Text {
                anchors.left: input.left
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text.length === 0
                text: "Type an action, an app or a setting"
                font: input.font
                color: Qt.alpha(hero.ink, 0.5)
            }
            Text {
                id: countText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: input.text.trim() === "" ? "" : root.results.length + (root.results.length === 1 ? " match" : " matches")
                font.family: root.mono; font.weight: Font.Bold; font.pixelSize: root.s(11)
                color: Qt.alpha(hero.ink, 0.62)
            }
        }

        Item {
            id: tileBox
            anchors.left: parent.left; anchors.leftMargin: root.s(32)
            anchors.bottom: parent.bottom; anchors.bottomMargin: root.s(52)
            width: root.s(104); height: width
            property real popT: 1
            NumberAnimation { id: popAnim; target: tileBox; property: "popT"; from: 0; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
            Connections { target: root; function onPopChanged() { popAnim.restart() } }
            scale: 0.82 + 0.18 * popT
            rotation: -4 - 8 * (1 - popT)

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: root.s(9); anchors.bottomMargin: -root.s(9)
                anchors.leftMargin: root.s(4); anchors.rightMargin: -root.s(4)
                radius: root.s(30)
                color: Qt.alpha(hero.deep, 0.4)
            }
            Rectangle {
                anchors.fill: parent
                radius: root.s(30)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.alpha(hero.ink, 0.30) }
                    GradientStop { position: 1.0; color: Qt.alpha(hero.ink, 0.12) }
                }
                border.width: 1.5; border.color: Qt.alpha(hero.ink, 0.34)
            }
            Text {
                anchors.centerIn: parent
                visible: !root.act || !root.act.image || heroIcon.status === Image.Error
                text: root.act ? (root.act.icon || root.g(0xF003B)) : root.g(0xF0349)
                font.family: root.glyphs; font.pixelSize: root.s(50)
                color: hero.ink
                style: Text.Raised; styleColor: Qt.alpha(hero.deep, 0.35)
            }
            Image {
                id: heroIcon
                anchors.centerIn: parent
                visible: !!root.act && !!root.act.image && status !== Image.Error
                width: root.s(62); height: width
                source: root.iconSrc(root.act)
                sourceSize: Qt.size(128, 128)
                fillMode: Image.PreserveAspectFit
                asynchronous: true; smooth: true; mipmap: true
            }
            Rectangle {
                visible: !!root.act && !!root.act.unread
                anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: -root.s(3)
                width: root.s(18); height: width; radius: width / 2
                color: hero.ink
                border.width: root.s(3); border.color: hero.tone1
            }
        }

        Column {
            id: titleCol
            anchors.left: tileBox.right; anchors.leftMargin: root.s(30)
            anchors.right: parent.right; anchors.rightMargin: root.s(30)
            anchors.verticalCenter: tileBox.verticalCenter
            anchors.verticalCenterOffset: -root.s(4)
            spacing: root.s(2)

            Text {
                width: parent.width
                textFormat: Text.StyledText
                text: root.act ? root.marked(root.act.label, root.current.hits, root.hex(hero.ink), root.hex(hero.ink, root.current.hits.length > 0 ? 0.56 : 1)) : ""
                font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(44); font.letterSpacing: -root.s(1.8)
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: root.s(26)
                style: Text.Raised; styleColor: Qt.alpha(hero.deep, 0.4)
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Text {
                width: parent.width
                text: root.act ? (root.confirming ? "This can't be undone from here" : root.act.hint) : ""
                font.family: root.mono; font.weight: Font.Bold; font.pixelSize: root.s(14)
                color: Qt.alpha(hero.ink, 0.84)
                elide: Text.ElideRight
            }
            Item { width: 1; height: root.s(10) }
            Row {
                id: chipRow
                spacing: root.s(8)
                height: root.s(30)

                component Glass: Rectangle {
                    property string label: ""
                    property bool strong: false
                    property bool ghost: false
                    height: root.s(30)
                    width: glassText.implicitWidth + root.s(24)
                    radius: height / 2
                    color: strong ? hero.ink : Qt.alpha(hero.ink, ghost ? 0.0 : 0.16)
                    border.width: 1
                    border.color: Qt.alpha(hero.ink, ghost ? 0.45 : (strong ? 0 : 0.24))
                    Text {
                        id: glassText
                        anchors.centerIn: parent
                        text: parent.label
                        font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(12)
                        color: parent.strong ? hero.deep : hero.ink
                        opacity: parent.ghost ? 0.8 : 1
                    }
                }

                Glass { label: root.act ? (root.catName[root.act.cat] || root.act.cat) : ""; visible: !!root.act }
                Glass {
                    visible: !!root.act && (root.act.state === "on" || root.act.state === "off")
                    label: root.act && root.act.state === "on" ? "On" : "Off"
                }
                Text {
                    visible: !!root.act && ((root.act.state === "on" || root.act.state === "off") || !!root.act.to)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.g(0xF0054)
                    font.family: root.glyphs; font.pixelSize: root.s(16)
                    color: Qt.alpha(hero.ink, 0.7)
                }
                Glass {
                    visible: !!root.act && (root.act.state === "on" || root.act.state === "off")
                    strong: true
                    label: root.act && root.act.state === "on" ? "Off" : "On"
                }
                Glass { visible: !!root.act && !!root.act.to; strong: true; label: root.act && root.act.to ? root.act.to : "" }
                Glass {
                    visible: root.paramInfo.show !== "" || !!root.paramInfo.missing
                    strong: root.paramInfo.show !== "" && !root.paramInfo.implied
                    ghost: !!root.paramInfo.missing || !!root.paramInfo.implied
                    label: root.paramInfo.show !== ""
                        ? root.paramInfo.show + (root.paramInfo.unit ? (root.paramInfo.unit === "%" ? "%" : " " + root.paramInfo.unit) : "")
                        : (root.act && root.act.param && root.act.param.kind === "number" ? "add a number" : "type " + (root.paramInfo.hint || "something"))
                }
                Glass {
                    visible: root.mailBusy && !!root.act && root.act.live === "mail"
                    ghost: true
                    label: "searching mail"
                    SequentialAnimation on opacity {
                        running: parent.visible; loops: Animation.Infinite
                        NumberAnimation { to: 0.45; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                    }
                }
            }
        }

        Row {
            anchors.right: parent.right; anchors.rightMargin: root.s(30)
            anchors.bottom: parent.bottom; anchors.bottomMargin: root.s(24)
            spacing: root.s(10)
            visible: !!root.act
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: root.s(34); height: root.s(26); radius: root.s(8)
                color: Qt.alpha(hero.ink, root.confirming ? 1 : 0.18)
                border.width: 1; border.color: Qt.alpha(hero.ink, 0.3)
                Text {
                    anchors.centerIn: parent
                    text: root.g(0xF0311)
                    font.family: root.glyphs; font.pixelSize: root.s(15)
                    color: root.confirming ? hero.deep : hero.ink
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: !root.act ? "" : root.confirming ? "again to " + root.act.verb.toLowerCase() : (root.act.verb || "Run")
                font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(15)
                color: hero.ink
            }
        }
    }

    Rectangle {
        id: panel
        anchors.top: heroWrap.bottom; anchors.topMargin: root.s(16)
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - root.s(24)
        height: root.results.length === 0 ? 0 : Math.min(root.results.length, root.rowsShown) * root.s(56) + root.s(20) + footer.height
        visible: height > 0
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        radius: root.s(28)
        clip: true
        opacity: Math.max(0, Math.min(1, root.intro * 2 - 0.4))
        transform: Translate { y: (1 - root.intro) * root.s(22) }
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.alpha(root.surface0, 0.97) }
            GradientStop { position: 1.0; color: Qt.alpha(root.base, 0.98) }
        }
        border.width: 1
        border.color: Qt.alpha(root.text, 0.08)
        MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }

        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 1
            height: root.s(120)
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(hero.tone1, 0.16) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        ListView {
            id: list
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: root.s(10)
            height: Math.min(root.results.length, root.rowsShown) * root.s(56)
            model: root.results
            clip: true
            currentIndex: root.sel
            interactive: true
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: true
            highlightMoveDuration: 170
            highlightResizeDuration: 0
            highlight: Item {
                id: hl
                readonly property color t: root.confirming ? root.danger : root.appHero ? hero.tone1 : (root.act ? root.tint(root.act.cat) : root.seed)
                Rectangle {
                    anchors.fill: parent
                    radius: root.s(18)
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.alpha(hl.t, 0.30) }
                        GradientStop { position: 0.7; color: Qt.alpha(hl.t, 0.08) }
                        GradientStop { position: 1.0; color: Qt.alpha(hl.t, 0.04) }
                    }
                    border.width: 1
                    border.color: Qt.alpha(hl.t, 0.32)
                }
            }

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property var a: modelData.a
                readonly property bool on: index === root.sel
                readonly property color t: on && root.appHero ? Qt.lighter(hero.tone1, 1.3) : root.tint(a.cat)
                width: list.width
                height: root.s(56)

                Rectangle {
                    id: rowTile
                    anchors.left: parent.left; anchors.leftMargin: root.s(10)
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.s(38); height: width
                    radius: root.s(13)
                    color: Qt.alpha(row.t, row.on ? 0.32 : 0.14)
                    border.width: 1; border.color: Qt.alpha(row.t, row.on ? 0.5 : 0.18)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    scale: row.on ? 1.06 : 1
                    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                    Text {
                        anchors.centerIn: parent
                        visible: !row.a.image || rowIcon.status === Image.Error
                        text: row.a.icon || root.g(0xF003B)
                        font.family: root.glyphs; font.pixelSize: root.s(19)
                        color: row.on ? root.text : row.t
                    }
                    Image {
                        id: rowIcon
                        anchors.centerIn: parent
                        visible: !!row.a.image && status !== Image.Error
                        width: root.s(24); height: width
                        source: root.iconSrc(row.a)
                        sourceSize: Qt.size(64, 64)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true; smooth: true; mipmap: true
                    }
                }

                Column {
                    anchors.left: rowTile.right; anchors.leftMargin: root.s(14)
                    anchors.right: rowMeta.left; anchors.rightMargin: root.s(14)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.s(1)
                    Text {
                        width: parent.width
                        textFormat: Text.StyledText
                        text: root.marked(row.a.label, row.modelData.hits, root.hex(row.t), root.hex(root.text))
                            + (row.modelData.param !== "" && row.a.param ? "<font color='" + root.hex(root.subtext1) + "'>  " + root.esc(row.modelData.param) + "</font>" : "")
                        font.family: root.mono; font.weight: row.on ? Font.Black : Font.Bold; font.pixelSize: root.s(14)
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: row.a.hint || ""
                        visible: text !== ""
                        font.family: root.mono; font.weight: Font.Medium; font.pixelSize: root.s(11)
                        color: root.subtext0
                        opacity: row.on ? 0.95 : 0.7
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: rowMeta
                    anchors.right: parent.right; anchors.rightMargin: root.s(14)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.s(5)
                    Repeater {
                        model: row.a.keys ? row.a.keys.split(" ") : []
                        delegate: Rectangle {
                            required property string modelData
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(root.s(22), keyText.implicitWidth + root.s(12)); height: root.s(22)
                            radius: root.s(7)
                            color: Qt.alpha(root.surface2, row.on ? 0.9 : 0.55)
                            Text {
                                id: keyText
                                anchors.centerIn: parent
                                text: modelData
                                font.family: root.mono; font.weight: Font.Bold; font.pixelSize: root.s(10)
                                color: root.subtext0
                            }
                        }
                    }
                    Rectangle {
                        visible: row.a.state === "on" || row.a.state === "off"
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.s(30); height: root.s(18); radius: height / 2
                        color: row.a.state === "on" ? Qt.alpha(row.t, 0.85) : "transparent"
                        border.width: 1.5; border.color: Qt.alpha(row.t, row.a.state === "on" ? 0.85 : 0.4)
                        Rectangle {
                            width: root.s(10); height: width; radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: row.a.state === "on" ? parent.width - width - root.s(4) : root.s(4)
                            color: row.a.state === "on" ? root.base : Qt.alpha(row.t, 0.6)
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: if (root.sel !== row.index) { root.sel = row.index; root.confirmId = "" }
                    onClicked: { root.sel = row.index; input.forceActiveFocus(); root.run() }
                }
            }
        }

        Item {
            id: footer
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.leftMargin: root.s(24); anchors.rightMargin: root.s(24)
            height: root.s(36)
            Rectangle {
                anchors.top: parent.top
                width: parent.width; height: 1
                color: Qt.alpha(root.text, 0.06)
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.s(18)
                Repeater {
                    model: [[root.g(0xF005D) + " " + root.g(0xF0045), "move"], [root.g(0xF0311), "run"], ["esc", "close"]]
                    delegate: Row {
                        required property var modelData
                        spacing: root.s(6)
                        Text {
                            text: modelData[0]
                            font.family: modelData[0] === "esc" ? root.mono : root.glyphs
                            font.weight: Font.Bold; font.pixelSize: root.s(11)
                            color: root.subtext0
                        }
                        Text {
                            text: modelData[1]
                            font.family: root.mono; font.weight: Font.Medium; font.pixelSize: root.s(11)
                            color: root.subtext1
                        }
                    }
                }
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: input.text.trim() === "" ? "Recent and suggested" : ""
                font.family: root.mono; font.weight: Font.Medium; font.pixelSize: root.s(11)
                color: root.subtext1
            }
        }
    }
}
