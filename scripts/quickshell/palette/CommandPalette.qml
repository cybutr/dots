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
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color subtext1: _theme.subtext1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color seed: _theme.blue
    readonly property color danger: rgb("#f38ba8")

    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: home + "/.config/hypr/scripts/quickshell/palette"
    readonly property string mira: home + "/.config/hypr/scripts/quickshell/claude/mira_mail.py"
    readonly property string pinFile: home + "/.cache/quickshell/palette/pinned.json"
    readonly property string mono: "JetBrains Mono"
    readonly property string glyphs: "Iosevka Nerd Font"

    property var actions: []
    property var history: ({})
    property var pinned: []
    property var results: []
    property int sel: 0
    property var peek: null
    property string confirmId: ""
    property var mailHits: []
    property string mailFor: ""
    property bool mailBusy: false
    property string art: ""
    property var music: ({})
    property var ctx: ({})
    property var perf: ({})
    property var cpuHist: []
    property var batPts: []
    property string wall: ""
    property string wallDir: ""
    property var wallFiles: []
    property int bright: -1
    property var timerState: ({})
    property var liveState: ({})
    property int liveVol: -1
    property var batLive: ({})
    property int cpuNow: -1
    property real musicAt: 0
    property var peekData: ({})
    property string suggestSig: ""
    property real now: Date.now() / 1000
    property int pop: 0
    readonly property var defaults: ["claude.ask", "media.playpause", "sys.nightlight", "setting.ecoModeEnabled", "timer.25", "wall.random", "mail.search", "capture.region", "power.lock"]

    readonly property var current: results.length > 0 ? results[Math.min(sel, results.length - 1)] : null
    readonly property var act: current ? current.a : null
    readonly property var shown: peek !== null ? peek : act
    readonly property bool confirming: shown !== null && confirmId === shown.id
    readonly property var paramInfo: resolveParam(current)
    readonly property string kind: previewKind(shown)
    readonly property color accent: confirming ? danger : shown ? tint(shown.cat) : seed

    readonly property var catOrder: ["media", "audio", "timer", "widget", "mail", "app", "layout", "system", "wallpaper", "setting", "claude", "capture", "power"]
    readonly property var catHex: ({
        media: "#f5c2e7", audio: "#cba6f7", timer: "#f9e2af", widget: "#89b4fa", mail: "#f5e0dc", app: "#94e2d5",
        layout: "#74c7ec", system: "#89dceb", wallpaper: "#a6e3a1", setting: "#b4befe", claude: "#fab387",
        capture: "#eba0ac", power: "#f38ba8", window: "#f2cdcd", workspace: "#74c7ec", device: "#f2cdcd",
        tab: "#89b4fa", web: "#89b4fa", code: "#74c7ec", spotify: "#a6e3a1", project: "#f9e2af"
    })
    readonly property var catName: ({
        media: "Media", audio: "Sound", timer: "Timer", widget: "Widget", mail: "Mail", app: "App",
        layout: "Layout", system: "System", wallpaper: "Wallpaper", setting: "Setting", claude: "Claude",
        capture: "Capture", power: "Power", window: "Window", workspace: "Workspace", device: "Device",
        tab: "Tab", web: "Web", code: "Code", spotify: "Spotify", project: "Project"
    })
    function rgb(h) {
        let n = parseInt(h.slice(1), 16)
        return Qt.rgba((n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255, 1)
    }
    function tint(cat) { return root.catHex[cat] ? root.rgb(root.catHex[cat]) : root.seed }
    function hex(c, a) {
        let h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2)
        return "#" + (a === undefined ? "" : h(a)) + h(c.r) + h(c.g) + h(c.b)
    }
    function g(cp) { return String.fromCodePoint(cp) }
    function esc(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    function num(v, d) { let n = parseFloat(v); return isNaN(n) ? d : n }
    function clock(secs) {
        secs = Math.max(0, Math.round(secs))
        let h = Math.floor(secs / 3600), m = Math.floor(secs % 3600 / 60), sc = secs % 60
        let p = v => ("0" + v).slice(-2)
        return (h > 0 ? h + ":" + p(m) : p(m)) + ":" + p(sc)
    }
    function ago(t) {
        let d = Math.max(0, root.now - t)
        return d < 3600 ? Math.max(1, Math.floor(d / 60)) + "m ago" : d < 86400 ? Math.floor(d / 3600) + "h ago" : Math.floor(d / 86400) + "d ago"
    }
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
            v = Math.max(p.min !== undefined ? p.min : v, Math.min(p.max !== undefined ? p.max : v, p.float ? Math.round(v * 100) / 100 : Math.round(v)))
            return { ok: true, value: String(v), show: String(v), unit: p.unit || "" }
        }
        let t = (r.param || "").trim()
        if (t === "") return { ok: !p.required, value: "", show: "", missing: !!p.required, hint: p.hint || "" }
        return { ok: true, value: t, show: t }
    }

    function previewKind(a) {
        if (!a) return "none"
        let id = a.id
        if (a.cat === "wallpaper" || id === "widget.wallpaper") return "wall"
        if (a.cat === "media" || id === "widget.music") return "media"
        if (id === "audio.volume" || id === "audio.mute" || id === "audio.muteall" || id === "widget.volume") return "volume"
        if (id === "sys.brightness" || id === "sys.brightcurve") return "bright"
        if (id.indexOf("sys.pp.") === 0 || id === "sys.powersave" || id === "sys.powerrestore" || id === "widget.battery" || /batt/i.test(id)) return "battery"
        if (/(^|\.)eco/i.test(id) || id === "sys.orphans" || id === "sys.restartbar" || id === "sys.restartshell") return "stats"
        if (a.cat === "timer" || id === "widget.focustime") return "timer"
        if (id.indexOf("spotifyhit.") === 0) return "art"
        if (a.cat === "project" && a.project) return "project"
        if (a.image) return "app"
        return "glyph"
    }

    readonly property var sysx: ctx.system || ({})
    readonly property int vol: liveVol >= 0 ? liveVol : num((sysx.audio || {}).volume, -1)
    readonly property bool muted: liveState.mute !== undefined ? liveState.mute === "on" : (sysx.audio || {}).is_muted === "true"
    readonly property int bat: batLive.pct !== undefined ? batLive.pct : num((sysx.battery || {}).percent, -1)
    readonly property string batStatus: batLive.status !== undefined ? batLive.status : (sysx.battery || {}).status || ""
    readonly property var proc: ctx.proc || ({})
    readonly property bool playing: music.status === "Playing"
    readonly property real musicLen: num(music.length, 0)
    readonly property real musicPos: {
        let p = num(music.position, 0)
        if (playing) p += Math.max(0, now - musicAt)
        return musicLen > 0 ? Math.min(musicLen, p) : p
    }
    readonly property string musicTime: musicLen > 0 ? clock(musicPos) + " / " + (music.lengthStr || clock(musicLen)) : (music.timeStr || "")
    readonly property var mediaPeek: {
        if (!shown || (shown.id !== "media.next" && shown.id !== "media.prev")) return null
        let p = peekData[shown.id === "media.next" ? "next" : "prev"]
        return p && p.title && peekData.now === music.title ? p : null
    }
    function stateOf(a) {
        if (!a) return undefined
        return a.stateKey && root.liveState[a.stateKey] !== undefined ? root.liveState[a.stateKey] : a.state
    }

    function suggest() {
        let out = []
        let title = root.music.title || ""
        if (root.music.status === "Playing") { out.push(["media.playpause", "pause " + title]); out.push(["media.next", "skip " + title]) }
        else if (root.music.status === "Paused" && title !== "") out.push(["media.playpause", "resume " + title])
        let ts = root.timerState.state || "idle"
        if (ts === "running") out.push(["timer.pause", root.timerView.label + " left on the timer"])
        else if (ts === "paused") out.push(["timer.resume", "timer paused at " + root.timerView.label])
        if (root.bat >= 0 && root.bat <= 25 && root.batStatus === "Discharging") {
            out.push(["sys.pp.saver", "battery at " + root.bat + "%"])
            if (root.bat <= 12) out.push(["sys.powersave", "battery at " + root.bat + "%"])
        }
        if (root.muted) out.push(["audio.mute", "audio is muted"])
        if ((root.perf.orphans || 0) > 10) out.push(["sys.orphans", root.perf.orphans + " orphaned watchers"])
        out = out.concat(root.projectPicks())
        let h = new Date().getHours()
        let night = root.byId("sys.nightlight")
        if ((h >= 20 || h < 6) && night && root.stateOf(night) !== "on") out.push(["sys.nightlight", h < 6 ? "late night" : "evening"])
        if (h >= 0 && h < 5) out.push(["power.suspend", "it's past midnight"])
        if (ts === "idle" && h >= 8 && h < 18) out.push(["timer.25", "focus block"])
        return out
    }

    function projectPicks() {
        let last = null, top = null
        for (let i = 0; i < root.actions.length; i++) {
            let a = root.actions[i], p = a.project
            if (!p || !p.last || p.latest) continue
            if (!last || p.last > last.project.last) last = a
            if (!top || p.frecency > top.project.frecency) top = a
        }
        let out = []
        if (last && root.now - last.project.last < 4 * 86400) out.push([last.id, "where you left off, " + root.ago(last.project.last)])
        if (top && top !== last && top.project.frecency >= 2) out.push([top.id, "your most-opened project lately"])
        return out
    }

    readonly property var rail: {
        let out = [], seen = {}
        for (let i = 0; i < root.pinned.length; i++) {
            let a = root.byId(root.pinned[i])
            if (a && !seen[a.id]) { seen[a.id] = true; out.push({ a: a, pin: true }) }
        }
        let h = root.history
        let rec = Object.keys(h).filter(id => !seen[id]).sort((x, y) => (h[y].t || 0) - (h[x].t || 0))
        for (let i = 0; i < rec.length && out.length < 10; i++) {
            let a = root.byId(rec[i])
            if (a) { seen[a.id] = true; out.push({ a: a, pin: false }) }
        }
        return out
    }

    function recompute() {
        let keepId = root.act ? root.act.id : ""
        let q = input.text
        let r = Fuzzy.rank(root.actions, q, root.history, 40)
        if (q.trim() === "") {
            let skip = {}, have = {}, out = []
            for (let i = 0; i < root.rail.length; i++) skip[root.rail[i].a.id] = true
            let add = (a, why) => {
                if (!a || have[a.id] || skip[a.id]) return
                have[a.id] = true
                out.push({ a: a, score: 0, hits: [], param: "", why: why })
            }
            let sg = root.suggest()
            for (let i = 0; i < sg.length; i++) add(root.byId(sg[i][0]), sg[i][1])
            for (let i = 0; i < r.length; i++) add(r[i].a, "")
            for (let i = 0; i < root.defaults.length; i++) add(root.byId(root.defaults[i]), "")
            r = out.slice(0, 14)
        } else {
            let qt = q.trim()
            root.maybeRoute(qt, r)
            if (r.length > 0 && r[0].a.live === "mail" && root.mailHits.length > 0 && root.mailFor === r[0].param.trim()) {
                let hits = root.mailHits.map(m => ({ a: m, score: 0, hits: [], param: "" }))
                r = [r[0]].concat(hits, r.slice(1))
            } else if (r.length > 0 && r[0].a.live === "spotify" && root.spotHits.length > 0 && root.spotFor === r[0].param.trim()) {
                let hits = root.spotHits.map(m => ({ a: m, score: 0, hits: [], param: "" }))
                r = [r[0]].concat(hits, r.slice(1))
            }
            let lead = root.leadRow(qt)
            if (lead) r = [lead].concat(r.filter(x => x.a.id !== lead.a.id))
            if (/^run\s+\S/i.test(qt)) r = r.map(x => x.a.alt ? Object.assign({}, x, { altRun: true }) : x)
            let ask = root.byId("claude.ask")
            if (ask && !r.some(x => x.a.id === "claude.ask")) r.push({ a: ask, score: -99, hits: [], param: q.trim() })
        }
        root.results = r
        root.suggestSig = JSON.stringify(root.suggest())
        let idx = 0
        if (keepId !== "" && q === root.lastQuery) {
            for (let i = 0; i < r.length; i++) if (r[i].a.id === keepId) { idx = i; break }
        }
        root.lastQuery = q
        root.sel = idx
        // a model swap resets ListView.currentIndex internally without re-evaluating its binding
        list.currentIndex = Qt.binding(() => root.sel)
        list.positionViewAtIndex(idx, ListView.Contain)
    }
    property string lastQuery: ""
    function wsIntent(q) {
        let t = q.toLowerCase()
        if (/,| and | then /.test(t)) return false
        return /^(open|launch|start|run|spawn|put|fire up)\s+\S.*\s(on|in|to|onto|into)\s+(a |an |the )?(new|empty|fresh|free|blank|next|another|clean|workspace|ws|desktop|\d+)\b/.test(t)
            || /\S\s+(on|in|to)\s+(workspace|ws|desktop)\s*\d+$/.test(t)
    }
    function urlish(q) {
        if (/^[a-z][a-z0-9+.-]*:\/\/\S+$/i.test(q)) return true
        if (/\s/.test(q) || /\.(json|py|qml|js|md|txt|sh|conf|log|png|jpe?g|webp|gif|mp4|pdf)$/i.test(q)) return false
        return /^([\w-]+\.)+[a-z]{2,}(:\d+)?([\/?#]\S*)?$/i.test(q) || /^localhost(:\d+)?(\/\S*)?$/i.test(q)
    }
    function leadRow(q) {
        if (root.routeRes && root.routeRes.query === q) return { a: root.routeRes.action, score: 99, hits: [], param: "" }
        let id = root.wsIntent(q) ? "ws.openapp" : root.urlish(q) ? "web.open" : ""
        let a = id !== "" ? root.byId(id) : null
        return a ? { a: a, score: 99, hits: [], param: q } : null
    }
    function maybeRoute(q, r) {
        if (root.routeRes && root.routeRes.query === q) return
        let ws = root.wsIntent(q)
        let multi = / and |,| then /.test(q)
        let top = r.length > 0 ? r[0] : null
        let weak = !top || top.score < 12 || top.a.id === "claude.ask"
        if (ws || (!root.urlish(q) && !(top && top.a.live) && (multi || (weak && q.split(/\s+/).length >= 3)))) {
            routeDebounce.q = q
            routeDebounce.interval = ws ? 120 : 600
            routeDebounce.restart()
        } else routeDebounce.stop()
    }
    function byId(id) {
        for (let i = 0; i < root.actions.length; i++) if (root.actions[i].id === id) return root.actions[i]
        return null
    }
    function idle() { if (input.text.trim() === "") root.recompute() }
    function resuggest() { if (input.text.trim() === "" && JSON.stringify(root.suggest()) !== root.suggestSig) root.recompute() }

    function move(d) {
        if (root.results.length === 0) return
        root.peek = null
        root.sel = (root.sel + d + root.results.length) % root.results.length
        root.confirmId = ""
        list.positionViewAtIndex(root.sel, ListView.Contain)
    }

    function run() {
        if (!root.current) return
        if (root.current.altRun) { root.runAlt(); return }
        root.peek = null
        root.execute(root.current.a, root.paramInfo)
    }
    function runAlt() {
        if (!root.current) return
        let a = root.current.a
        if (!a.alt) { root.execute(a, root.paramInfo); return }
        root.peek = null
        root.execute(Object.assign({}, a, { cmd: a.alt.cmd, args: a.alt.args, verb: a.alt.verb }), root.paramInfo)
    }
    readonly property bool altNow: !!current && !!current.altRun && !!act && !!act.alt && shown === act
    readonly property string verbNow: !shown ? "" : altNow ? shown.alt.verb : (shown.verb || "Run")
    readonly property string altHint: !shown || !shown.alt || shown !== act ? "" : altNow ? (shown.verb || "Open") : shown.alt.verb
    function runRail(a) {
        root.peek = a
        let p = root.resolveParam({ a: a, param: "" })
        if (!p.ok) {
            root.peek = null
            input.text = a.label + " "
            input.cursorPosition = input.text.length
            input.forceActiveFocus()
            return
        }
        root.execute(a, p)
    }
    function execute(a, p) {
        if (!p.ok) { nudge.restart(); return }
        if (a.danger && root.confirmId !== a.id) { root.confirmId = a.id; confirmReset.restart(); return }
        let args = a.args ? a.args : [p.value !== "" ? p.value : (a.arg || "")]
        if (!root.transient(a)) Quickshell.execDetached(["python3", root.dir + "/palette_index.py", "used", a.id])
        fireAnim.restart()
        if (a.close !== false) root.close()
        Quickshell.execDetached(["bash", "-c", a.cmd, "_"].concat(args))
    }

    function transient(a) { return /^(mailhit|window|tab|spotifyhit|route)\./.test(a.id) }
    function pinnable(a) { return !!a && !root.transient(a) }
    function togglePin(a) {
        if (!root.pinnable(a)) return
        let p = root.pinned.slice()
        let i = p.indexOf(a.id)
        if (i >= 0) p.splice(i, 1)
        else p.unshift(a.id)
        root.pinned = p.slice(0, 8)
        Quickshell.execDetached(["python3", "-c",
            "import json,os,sys;p=sys.argv[1];os.makedirs(os.path.dirname(p),exist_ok=True);json.dump(json.loads(sys.argv[2]),open(p+'.tmp','w'));os.replace(p+'.tmp',p)",
            root.pinFile, JSON.stringify(root.pinned)])
        root.idle()
    }

    Timer { id: confirmReset; interval: 3500; onTriggered: root.confirmId = "" }
    Timer { interval: 1000; repeat: true; running: true; onTriggered: root.now = Date.now() / 1000 }

    component Pull: Process {
        property bool again: false
        function pull() { if (running) again = true; else running = true }
        onExited: if (again) { again = false; Qt.callLater(pull) }
    }
    function jsonOr(txt, d) {
        try { return JSON.parse(txt) } catch (e) { return d }
    }
    function patchState(o) {
        let s = Object.assign({}, root.liveState), changed = false
        for (let k in o) if (s[k] !== o[k]) { s[k] = o[k]; changed = true }
        if (changed) { root.liveState = s; root.resuggest() }
    }
    function onLive(line) {
        let sp = line.indexOf(" ")
        let t = sp < 0 ? line : line.slice(0, sp)
        switch (t) {
        case "audio": audioPull.pull(); break
        case "music": musicReader.pull(); break
        case "bat": batPull.pull(); break
        case "perf": perfPull.pull(); break
        case "timer": timerPull.pull(); break
        case "ctx": ctxPull.pull(); break
        case "state": statePull.pull(); break
        case "bright": brightPull.pull(); break
        case "wall": wallPull.pull(); break
        case "settings": builder.pull(); break
        case "cpu": {
            let v = parseInt(line.slice(sp + 1))
            if (isNaN(v)) break
            root.cpuNow = v
            let h = root.cpuHist.concat([v])
            root.cpuHist = h.length > 40 ? h.slice(h.length - 40) : h
            break
        }
        }
    }
    Process {
        id: liveWatch
        running: true
        command: [root.home + "/.config/hypr/scripts/quickshell/lifeline.sh", "exec bash \"$HOME/.config/hypr/scripts/quickshell/palette/live_watch.sh\""]
        stdout: SplitParser { splitMarker: "\n"; onRead: (line) => root.onLive(line.trim()) }
    }
    Pull {
        id: audioPull
        running: true
        command: ["bash", "-c", "echo \"$(pamixer --get-volume) $(pamixer --get-mute) $(pamixer --default-source --get-mute)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = this.text.trim().split(" ")
                if (p.length < 3) return
                let v = parseInt(p[0])
                if (!isNaN(v)) root.liveVol = v
                root.patchState({ mute: p[1] === "true" ? "on" : "off", mic: p[2] === "true" ? "on" : "off" })
            }
        }
    }
    readonly property string stateSrc: [
        "import sys,json,subprocess",
        "sys.path.insert(0,sys.argv[1])",
        "import palette_index as p",
        "s=p.live_states()",
        "try: s['bt']='on' if 'Powered: yes' in subprocess.run(['bluetoothctl','show'],capture_output=True,text=True,timeout=1).stdout else 'off'",
        "except Exception: pass",
        "print(json.dumps(s))"
    ].join("\n")
    Pull {
        id: statePull
        command: ["python3", "-c", root.stateSrc, root.dir]
        stdout: StdioCollector { onStreamFinished: { let s = root.jsonOr(this.text, null); if (s) root.patchState(s) } }
    }
    readonly property string batSrc: [
        "import json,os,glob,time",
        "def rd(p):",
        "    try: return open(p).read().strip()",
        "    except Exception: return ''",
        "b=sorted(glob.glob('/sys/class/power_supply/BAT*'))",
        "o={}",
        "if b:",
        "    c=rd(b[0]+'/capacity')",
        "    if c.isdigit(): o['pct']=int(c)",
        "    o['status']=rd(b[0]+'/status')",
        "fs=[f for f in glob.glob('/var/lib/upower/history-charge-*.dat') if ':' not in f and 'generic' not in f]",
        "o['pts']=[]",
        "if fs:",
        "    cut=time.time()-21600",
        "    for ln in open(max(fs,key=os.path.getmtime)).read().splitlines()[-600:]:",
        "        p=ln.split('\\t')",
        "        try: t=int(p[0]);v=float(p[1].replace(',','.'))",
        "        except Exception: continue",
        "        if t>=cut: o['pts'].append([t,v])",
        "print(json.dumps(o))"
    ].join("\n")
    Pull {
        id: batPull
        running: true
        command: ["python3", "-c", root.batSrc]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = root.jsonOr(this.text, null)
                if (!d) return
                if (d.pts.length > 1) root.batPts = d.pts
                delete d.pts
                root.batLive = d
                root.resuggest()
            }
        }
    }
    Pull {
        id: perfPull
        command: ["cat", "/tmp/qs_perf.json"]
        stdout: StdioCollector { onStreamFinished: { let d = root.jsonOr(this.text, null); if (d) { root.perf = d; root.resuggest() } } }
    }
    Pull {
        id: timerPull
        command: ["cat", "/tmp/qs_timer.json"]
        stdout: StdioCollector { onStreamFinished: { let d = root.jsonOr(this.text, null); if (d) { root.timerState = d; root.resuggest() } } }
    }
    Pull {
        id: ctxPull
        command: ["cat", "/tmp/qs_context.json"]
        stdout: StdioCollector { onStreamFinished: { let d = root.jsonOr(this.text, null); if (d) root.ctx = d } }
    }
    Pull {
        id: brightPull
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                let b = this.text.trim().split(",")
                let v = b.length > 3 ? parseInt(b[3]) : NaN
                if (!isNaN(v)) root.bright = v
            }
        }
    }
    Pull {
        id: wallPull
        command: ["awww", "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                let i = this.text.indexOf("image: ")
                if (i >= 0) root.wall = this.text.slice(i + 7).split("\n")[0].trim()
            }
        }
    }
    Pull {
        id: peekPull
        command: ["python3", root.dir + "/spotify_peek.py"]
        stdout: StdioCollector { onStreamFinished: root.peekData = root.jsonOr(this.text, {}) || {} }
    }

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
    Pull {
        id: builder
        running: true
        command: ["python3", root.dir + "/palette_index.py"]
        stdout: StdioCollector { onStreamFinished: root.ingest(this.text) }
    }
    Process {
        id: pinReader
        running: true
        command: ["cat", root.pinFile]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let p = JSON.parse(this.text)
                    if (Array.isArray(p)) { root.pinned = p; root.idle() }
                } catch (e) { }
            }
        }
    }
    Pull {
        id: musicReader
        running: true
        command: ["bash", root.home + "/.config/hypr/scripts/quickshell/music/music_info.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let m = JSON.parse(this.text.trim() || "{}")
                    if (m.artUrl && (m.status === "Playing" || m.status === "Paused")) root.art = "file://" + m.artUrl
                    else if (!m.title) root.art = ""
                    let moved = m.title !== root.music.title || m.artist !== root.music.artist
                    root.now = Date.now() / 1000
                    root.musicAt = root.now
                    root.music = m
                    if (moved) peekPull.pull()
                    root.resuggest()
                } catch (e) { }
            }
        }
    }
    readonly property string probeSrc: [
        "import json,os,glob,subprocess,time",
        "def rd(p,d):",
        "    try: return json.load(open(p))",
        "    except Exception: return d",
        "def sh(c):",
        "    try: return subprocess.run(c,capture_output=True,text=True,timeout=2).stdout",
        "    except Exception: return ''",
        "o={'ctx':rd('/tmp/qs_context.json',{}),'perf':rd('/tmp/qs_perf.json',{}),'timer':rd('/tmp/qs_timer.json',{})}",
        "sp='/tmp/qs_sparkline_card_CPU.json'",
        "o['cpu']=rd(sp,[]) if os.path.exists(sp) and time.time()-os.path.getmtime(sp)<900 else []",
        "fs=[f for f in glob.glob('/var/lib/upower/history-charge-*.dat') if ':' not in f and 'generic' not in f]",
        "o['bat']=[]",
        "if fs:",
        "    cut=time.time()-21600",
        "    for ln in open(max(fs,key=os.path.getmtime)).read().splitlines()[-600:]:",
        "        p=ln.split('\\t')",
        "        try: t=int(p[0]);v=float(p[1].replace(',','.'))",
        "        except Exception: continue",
        "        if t>=cut: o['bat'].append([t,v])",
        "q=sh(['awww','query'])",
        "o['wall']=q.split('image: ')[1].splitlines()[0].strip() if 'image: ' in q else ''",
        "wd=os.path.expanduser(rd(os.path.expanduser('~/.config/hypr/settings.json'),{}).get('wallpaperDir','~/Wallpapers'))",
        "o['wallDir']=wd",
        "try: o['walls']=sorted(f for f in os.listdir(wd) if f.lower().endswith(('.jpg','.jpeg','.png','.webp','.gif')))[:3000]",
        "except Exception: o['walls']=[]",
        "b=sh(['brightnessctl','-m']).split(',')",
        "o['bright']=int(b[3].rstrip('%')) if len(b)>3 and b[3].rstrip('%').isdigit() else -1",
        "print(json.dumps(o))"
    ].join("\n")
    Process {
        id: probe
        running: true
        command: ["python3", "-c", root.probeSrc]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(this.text)
                    root.ctx = d.ctx || {}
                    root.perf = d.perf || {}
                    if (Array.isArray(d.cpu)) root.cpuHist = d.cpu.concat(root.cpuHist).slice(-40)
                    if (root.batPts.length < 2) root.batPts = d.bat || []
                    root.wall = d.wall || ""
                    root.wallDir = d.wallDir || ""
                    root.wallFiles = d.walls || []
                    root.bright = d.bright
                    root.timerState = d.timer || {}
                    root.idle()
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

    property var spotHits: []
    property string spotFor: ""
    property bool spotBusy: false
    readonly property string spotWant: (act && act.live === "spotify" && current.param.trim().length >= 2) ? current.param.trim() : ""
    onSpotWantChanged: {
        if (spotWant === "") { spotDebounce.stop(); return }
        if (spotWant !== spotFor) spotDebounce.restart()
    }
    Timer {
        id: spotDebounce
        interval: 450
        onTriggered: {
            root.spotBusy = true
            spotProc.q = root.spotWant
            spotProc.command = ["python3", root.dir + "/sources.py", "spotify", root.spotWant]
            spotProc.running = false
            spotProc.running = true
        }
    }
    Process {
        id: spotProc
        property string q: ""
        stdout: StdioCollector {
            onStreamFinished: {
                root.spotBusy = false
                let d = root.jsonOr(this.text, null) || {}
                root.spotHits = d.results || []
                root.spotFor = spotProc.q
                root.recompute()
            }
        }
    }

    property var routeRes: null
    property bool routeBusy: false
    Timer {
        id: routeDebounce
        property string q: ""
        onTriggered: {
            root.routeBusy = !root.wsIntent(q)
            routeProc.command = ["python3", root.dir + "/palette_index.py", "route", q]
            routeProc.running = false
            routeProc.running = true
        }
    }
    Process {
        id: routeProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.routeBusy = false
                let d = root.jsonOr(this.text, null)
                if (!d || !d.ok || !d.action || d.query !== input.text.trim()) return
                let top = root.sel === 0
                root.routeRes = d
                root.recompute()
                if (top) root.sel = 0
            }
        }
    }

    property var projPeek: ({})
    readonly property string projWant: shown && shown.project && shown.project.path ? shown.project.path : ""
    onProjWantChanged: if (projWant !== "" && !projPeek[projWant]) projDebounce.restart()
    Timer {
        id: projDebounce
        interval: 90
        onTriggered: {
            if (root.projWant === "" || root.projPeek[root.projWant]) return
            projProc.p = root.projWant
            projProc.command = ["python3", root.dir + "/sources.py", "project", "peek", root.projWant]
            projProc.running = false
            projProc.running = true
        }
    }
    Process {
        id: projProc
        property string p: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let d = root.jsonOr(this.text, null)
                if (d) {
                    let m = Object.assign({}, root.projPeek)
                    m[projProc.p] = d
                    root.projPeek = m
                }
                if (root.projWant !== "" && !root.projPeek[root.projWant]) projDebounce.restart()
            }
        }
    }

    onShownChanged: root.pop++
    readonly property bool wantsPeek: !!shown && (shown.id === "media.next" || shown.id === "media.prev")
    onWantsPeekChanged: if (wantsPeek) peekPull.pull()

    property color iconTone: seed
    property bool iconToneOk: false
    Canvas {
        id: sampler
        width: 8; height: 8
        opacity: 0
        property string src: root.shown && root.shown.image ? root.iconSrc(root.shown) : ""
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

    readonly property string wallShown: {
        if (!shown || shown.id !== "wall.set" || shown !== act || paramInfo.value === "") return wall
        let q = paramInfo.value.toLowerCase()
        for (let i = 0; i < wallFiles.length; i++) if (wallFiles[i].toLowerCase().indexOf(q) >= 0) return wallDir + "/" + wallFiles[i]
        return ""
    }
    function timerMins(a) {
        if (!a) return -1
        if (a.id === "timer.start") return a === root.act ? root.num(root.paramInfo.value, 25) : 25
        let m = a.id.match(/^timer\.(\d+)$/)
        return m ? parseInt(m[1]) : -1
    }
    readonly property var timerView: {
        let t = timerState || {}, st = t.state || "idle"
        let want = timerMins(shown)
        if (st === "running" || st === "paused") {
            let end = num(t.endTs, 0)
            if (end > 1e12) end /= 1000
            let rem = st === "running" ? Math.max(0, end - now) : num(t.remainingSecs, 0)
            return { secs: rem, frac: rem / Math.max(1, num(t.durationSecs, 1)), label: clock(rem), caption: want > 0 ? st + " · restarts at " + want + "m" : st }
        }
        if (want > 0) return { secs: want * 60, frac: 1, label: clock(want * 60), caption: "ready" }
        return { secs: 0, frac: 0, label: "00:00", caption: "idle" }
    }
    readonly property var meter: {
        let a = shown
        if (!a || (kind !== "volume" && kind !== "bright")) return null
        let target = (a === act && a.param && a.param.kind === "number" && paramInfo.value !== "") ? num(paramInfo.value, -1) : -1
        if (kind === "volume") return {
            value: vol, max: 150, target: target, dim: muted, tone: tint("audio"),
            glyph: muted ? 0xF0581 : 0xF057E,
            caption: vol < 0 ? "volume unknown" : muted ? "output muted" : "output volume"
        }
        return { value: bright, max: 100, target: target, dim: false, tone: tint("system"), glyph: 0xF00DF, caption: bright < 0 ? "brightness unknown" : "screen brightness" }
    }
    readonly property var graph: {
        if (kind === "battery") {
            let pts = []
            if (batPts.length > 1) {
                let t0 = batPts[0][0], t1 = Math.max(t0 + 1, batPts[batPts.length - 1][0])
                for (let i = 0; i < batPts.length; i++) pts.push([(batPts[i][0] - t0) / (t1 - t0), batPts[i][1]])
            }
            return {
                big: bat >= 0 ? bat + "%" : "--", caption: bat < 0 ? "no battery" : batStatus.toLowerCase(),
                foot: pts.length > 1 ? "charge, last 6h" : "no charge history yet",
                pts: pts, lo: 0, hi: 100, tone: bat >= 0 && bat <= 20 ? danger : tint("wallpaper"), glyph: batStatus === "Charging" ? 0xF0084 : 0xF0079
            }
        }
        if (kind === "stats") {
            let h = cpuHist.length > 1 ? cpuHist : (perf.hist || [])
            let pts = h.map((v, i) => [i / Math.max(1, h.length - 1), v])
            let hi = Math.max(25, ...h.map(v => v * 1.15))
            let m = proc.mem || {}
            let parts = []
            if (m.used_pct !== undefined) parts.push("mem " + Math.round(m.used_pct) + "%")
            if (proc.temp_c !== undefined) parts.push(Math.round(proc.temp_c) + "°C")
            if (proc.load) parts.push("load " + proc.load[0])
            if ((perf.orphans || 0) > 0) parts.push(perf.orphans + " orphans")
            return {
                big: cpuNow >= 0 ? cpuNow + "%" : proc.cpu_pct !== undefined ? Math.round(proc.cpu_pct) + "%" : "--",
                caption: cpuHist.length > 1 ? "cpu" : "quickshell cpu", foot: parts.join("  ·  "),
                pts: pts, lo: 0, hi: Math.min(100, hi), tone: tint("system"), glyph: 0xF035B
            }
        }
        return null
    }
    readonly property string hhmm: {
        let d = new Date(now * 1000)
        return ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
    }
    readonly property color batTone: batStatus === "Charging" || batStatus === "Full" ? rgb("#a6e3a1") : bat <= 20 ? rgb("#f38ba8") : bat < 30 ? rgb("#f9e2af") : rgb("#89b4fa")
    readonly property var readout: {
        let out = [[g(0xF0150), hhmm, tint("timer")]]
        if (bat >= 0) out.push([g(batStatus === "Charging" ? 0xF0084 : 0xF0079), bat + "%", batTone])
        if (vol >= 0) out.push([g(muted ? 0xF0581 : 0xF057E), muted ? "muted" : String(vol), muted ? danger : tint("audio")])
        if (playing) out.push([g(0xF0387), "playing", tint("media")])
        return out
    }

    component Caps: Text {
        font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(10); font.letterSpacing: root.s(1.6)
        font.capitalization: Font.AllUppercase
        color: Qt.alpha(root.subtext0, 0.8)
    }
    component Tag: Rectangle {
        property string label: ""
        property color tone: root.subtext0
        property bool strong: false
        height: root.s(22)
        width: tagText.implicitWidth + root.s(16)
        radius: root.s(6)
        color: strong ? Qt.alpha(tone, 0.9) : "transparent"
        border.width: 1; border.color: Qt.alpha(tone, strong ? 0 : 0.45)
        Caps {
            id: tagText
            anchors.centerIn: parent
            text: parent.label
            font.letterSpacing: root.s(1.1)
            color: parent.strong ? root.crust : parent.tone
        }
    }
    component Gauge: Item {
        property real value: 0
        property real target: -1
        property real max: 100
        property color tone: root.seed
        property bool dim: false
        height: root.s(10)
        Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.alpha(root.text, 0.08) }
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, parent.value / parent.max)); height: parent.height
            radius: height / 2
            color: Qt.alpha(parent.tone, parent.dim ? 0.3 : 0.9)
            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            visible: parent.max > 100
            x: parent.width * 100 / parent.max - width / 2; y: -root.s(4)
            width: root.s(2); height: parent.height + root.s(8)
            color: Qt.alpha(root.text, 0.22)
        }
        Rectangle {
            visible: parent.target >= 0
            x: parent.width * Math.min(1, parent.target / parent.max) - width / 2; y: -root.s(5)
            width: root.s(4); height: parent.height + root.s(10); radius: width / 2
            color: root.text
            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }
    }
    component Spark: Canvas {
        property var pts: []
        property real lo: 0
        property real hi: 100
        property color tone: root.seed
        onPtsChanged: requestPaint()
        onToneChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            let c = getContext("2d")
            c.reset()
            if (!pts || pts.length < 2) return
            let w = width, h = height, span = Math.max(1e-6, hi - lo)
            let Y = v => h - 1 - (Math.max(lo, Math.min(hi, v)) - lo) / span * (h - 2)
            c.beginPath()
            c.moveTo(0, h)
            for (let i = 0; i < pts.length; i++) c.lineTo(pts[i][0] * w, Y(pts[i][1]))
            c.lineTo(w, h)
            c.closePath()
            c.globalAlpha = 0.16
            c.fillStyle = tone
            c.fill()
            c.globalAlpha = 1
            c.beginPath()
            for (let i = 0; i < pts.length; i++) {
                if (i === 0) c.moveTo(0, Y(pts[0][1]))
                else c.lineTo(pts[i][0] * w, Y(pts[i][1]))
            }
            c.lineWidth = root.s(2)
            c.lineJoin = "round"
            c.strokeStyle = tone
            c.stroke()
        }
    }

    property real intro: 0
    NumberAnimation on intro { from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic; running: true }
    property real fire: 0
    NumberAnimation { id: fireAnim; target: root; property: "fire"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: root.s(22)
        color: Qt.alpha(root.mantle, 0.97)
        border.width: 1
        border.color: root.confirming ? Qt.alpha(root.danger, 0.6) : Qt.alpha(wash, 0.24)
        Behavior on border.color { ColorAnimation { duration: 180 } }
        opacity: root.intro
        transform: Translate { y: (1 - root.intro) * -root.s(14) }
        property color wash: root.accent
        Behavior on wash { ColorAnimation { duration: 260 } }
        MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: card.radius - 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(card.wash, 0.13) }
                GradientStop { position: 0.45; color: Qt.alpha(card.wash, 0.035) }
                GradientStop { position: 1.0; color: Qt.alpha(card.wash, 0.07) }
            }
        }

        Row {
            id: spectrum
            anchors.top: parent.top
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: card.radius; anchors.rightMargin: card.radius
            height: root.s(3)
            spacing: root.s(3)
            readonly property string on: root.shown ? root.shown.cat : ""
            readonly property real sum: root.catOrder.length + (root.catOrder.indexOf(on) >= 0 ? 8 : 0)
            Repeater {
                model: root.catOrder
                delegate: Rectangle {
                    required property string modelData
                    readonly property bool hot: modelData === spectrum.on
                    height: spectrum.height
                    width: (spectrum.width - spectrum.spacing * (root.catOrder.length - 1)) * (hot ? 9 : 1) / spectrum.sum
                    radius: height / 2
                    color: root.confirming && hot ? root.danger : Qt.alpha(root.tint(modelData), hot ? 1 : 0.55)
                    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Rectangle {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width; height: root.s(16)
                        opacity: parent.hot ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.alpha(root.confirming ? root.danger : root.tint(modelData), 0.32) }
                            GradientStop { position: 1.0; color: Qt.alpha(root.confirming ? root.danger : root.tint(modelData), 0) }
                        }
                    }
                }
            }
        }

        Item {
            id: promptRow
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.leftMargin: root.s(26); anchors.rightMargin: root.s(22); anchors.topMargin: root.s(20)
            height: root.s(40)
            transform: Translate { id: shakeT; x: 0 }
            SequentialAnimation {
                id: nudge
                NumberAnimation { target: shakeT; property: "x"; to: -root.s(10); duration: 50 }
                NumberAnimation { target: shakeT; property: "x"; to: root.s(8); duration: 70 }
                NumberAnimation { target: shakeT; property: "x"; to: -root.s(4); duration: 70 }
                NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 80 }
            }

            Text {
                id: promptGlyph
                anchors.verticalCenter: parent.verticalCenter
                text: root.g(0xF0142)
                font.family: root.glyphs; font.pixelSize: root.s(24)
                color: root.accent
                Behavior on color { ColorAnimation { duration: 200 } }
            }
            TextInput {
                id: input
                anchors.left: promptGlyph.right; anchors.leftMargin: root.s(8)
                anchors.right: catTag.left; anchors.rightMargin: root.s(16)
                anchors.verticalCenter: parent.verticalCenter
                focus: true
                color: root.text
                selectionColor: Qt.alpha(root.accent, 0.35)
                selectedTextColor: root.text
                font.family: root.mono; font.weight: Font.Bold; font.pixelSize: root.s(20)
                clip: true
                cursorDelegate: Rectangle {
                    width: root.s(10); radius: root.s(2)
                    color: Qt.alpha(root.accent, 0.85)
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite; running: input.activeFocus
                        NumberAnimation { to: 1; duration: 60 }
                        PauseAnimation { duration: 520 }
                        NumberAnimation { to: 0.1; duration: 60 }
                        PauseAnimation { duration: 400 }
                    }
                }
                onTextChanged: { root.confirmId = ""; root.peek = null; root.recompute() }
                Keys.onPressed: (e) => {
                    let ctrl = e.modifiers & Qt.ControlModifier
                    if (ctrl && e.key === Qt.Key_S) { root.togglePin(root.act); e.accepted = true }
                    else if (ctrl && e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
                        let i = e.key - Qt.Key_1
                        if (i < root.rail.length) root.runRail(root.rail[i].a)
                        e.accepted = true
                    }
                    else if (e.key === Qt.Key_Down || (ctrl && e.key === Qt.Key_N) || (e.key === Qt.Key_Tab && !(e.modifiers & Qt.ShiftModifier))) { root.move(1); e.accepted = true }
                    else if (e.key === Qt.Key_Up || (ctrl && e.key === Qt.Key_P) || e.key === Qt.Key_Backtab) { root.move(-1); e.accepted = true }
                    else if (e.key === Qt.Key_PageDown) { root.move(Math.min(5, root.results.length - 1 - root.sel)); e.accepted = true }
                    else if (e.key === Qt.Key_PageUp) { root.move(-Math.min(5, root.sel)); e.accepted = true }
                    else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ShiftModifier)) { root.runAlt(); e.accepted = true }
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
                color: Qt.alpha(root.subtext0, 0.45)
            }
            Tag {
                id: catTag
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: !!root.shown
                tone: root.accent
                label: root.confirming ? "confirm" : root.shown ? (root.catName[root.shown.cat] || root.shown.cat) : ""
            }
        }

        Rectangle {
            id: rule
            anchors.top: promptRow.bottom; anchors.topMargin: root.s(12)
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: root.s(18); anchors.rightMargin: root.s(18)
            height: 1
            color: Qt.alpha(root.text, 0.07)
        }

        Item {
            id: railBox
            readonly property bool open: input.text.trim() === "" && root.rail.length > 0
            anchors.top: rule.bottom
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: root.s(18); anchors.rightMargin: root.s(18)
            height: open ? root.s(92) : 0
            opacity: open ? 1 : 0
            clip: true
            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160 } }

            Caps {
                id: railHead
                anchors.left: parent.left; anchors.top: parent.top; anchors.topMargin: root.s(12)
                text: root.pinned.length > 0 ? "Pinned  ·  Recent" : "Recent"
            }
            Caps {
                anchors.right: parent.right; anchors.verticalCenter: railHead.verticalCenter
                anchors.left: railHead.right; anchors.leftMargin: root.s(16)
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                font.capitalization: Font.MixedCase
                font.letterSpacing: 0
                font.weight: Font.Bold
                text: root.peek ? root.peek.label : "ctrl 1-9 to run  ·  ctrl s to pin"
                color: root.peek ? root.tint(root.peek.cat) : Qt.alpha(root.subtext0, 0.55)
            }
            Row {
                anchors.left: parent.left
                anchors.top: railHead.bottom; anchors.topMargin: root.s(10)
                spacing: root.s(8)
                Repeater {
                    model: root.rail
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        required property int index
                        readonly property var a: modelData.a
                        readonly property color t: root.tint(a.cat)
                        readonly property bool hot: root.peek === a
                        width: root.s(46); height: width
                        radius: root.s(12)
                        color: Qt.alpha(t, hot ? 0.26 : 0.12)
                        border.width: 1
                        border.color: Qt.alpha(t, hot ? 0.85 : modelData.pin ? 0.55 : 0.3)
                        scale: hot ? 1.06 : 1
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text {
                            anchors.centerIn: parent
                            visible: !chip.a.image || chipIcon.status === Image.Error
                            text: chip.a.icon || root.g(0xF003B)
                            font.family: root.glyphs; font.pixelSize: root.s(19)
                            color: chip.t
                        }
                        Image {
                            id: chipIcon
                            anchors.centerIn: parent
                            visible: !!chip.a.image && status !== Image.Error
                            width: root.s(24); height: width
                            source: root.iconSrc(chip.a)
                            sourceSize: Qt.size(64, 64)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true; smooth: true; mipmap: true
                        }
                        Rectangle {
                            visible: chip.modelData.pin
                            anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: root.s(5)
                            width: root.s(6); height: width; radius: width / 2
                            color: chip.t
                        }
                        Text {
                            visible: chip.index < 9
                            anchors.right: parent.right; anchors.bottom: parent.bottom
                            anchors.rightMargin: root.s(5); anchors.bottomMargin: root.s(2)
                            text: chip.index + 1
                            font.family: root.mono; font.weight: Font.Bold; font.pixelSize: root.s(8)
                            color: Qt.alpha(chip.t, 0.7)
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onEntered: { root.peek = chip.a; if (root.confirmId !== chip.a.id) root.confirmId = "" }
                            onExited: if (root.peek === chip.a) root.peek = null
                            onClicked: (m) => {
                                input.forceActiveFocus()
                                if (m.button === Qt.RightButton) root.togglePin(chip.a)
                                else root.runRail(chip.a)
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: body
            anchors.top: railBox.bottom; anchors.topMargin: root.s(12)
            anchors.bottom: footer.top; anchors.bottomMargin: root.s(6)
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: root.s(18); anchors.rightMargin: root.s(18)

            Item {
                id: listCol
                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                width: Math.round((body.width - root.s(16)) * 0.55)

                Caps {
                    id: listHead
                    anchors.left: parent.left; anchors.leftMargin: root.s(8)
                    anchors.top: parent.top
                    text: input.text.trim() === "" ? "Suggested" : "Results"
                }
                Caps {
                    anchors.right: parent.right; anchors.rightMargin: root.s(8)
                    anchors.verticalCenter: listHead.verticalCenter
                    text: root.mailBusy ? "searching mail" : root.spotBusy ? "searching spotify" : root.routeBusy ? "asking claude" : input.text.trim() === "" ? "" : root.results.length + (root.results.length === 1 ? " match" : " matches")
                    color: Qt.alpha(root.subtext0, 0.55)
                }

                ListView {
                    id: list
                    anchors.top: listHead.bottom; anchors.topMargin: root.s(8)
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    model: root.results
                    clip: true
                    currentIndex: root.sel
                    interactive: true
                    boundsBehavior: Flickable.StopAtBounds
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: 140
                    highlightResizeDuration: 0
                    highlight: Item {
                        Rectangle {
                            anchors.fill: parent
                            radius: root.s(10)
                            color: Qt.alpha(root.surface0, root.peek ? 0.35 : 0.8)
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: root.s(10)
                            opacity: root.peek ? 0.4 : 1
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.alpha(card.wash, 0.2) }
                                GradientStop { position: 1.0; color: Qt.alpha(card.wash, 0.04) }
                            }
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.s(3); height: parent.height - root.s(18)
                            radius: width / 2
                            color: root.confirming && !root.peek ? root.danger : (root.act ? root.tint(root.act.cat) : root.seed)
                            opacity: root.peek ? 0.4 : 1
                        }
                    }

                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property var a: modelData.a
                        readonly property string st: root.stateOf(a) || ""
                        readonly property bool on: index === root.sel
                        readonly property color t: root.tint(a.cat)
                        readonly property string why: modelData.why || ""
                        width: list.width
                        height: root.s(50)

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.s(3); height: root.s(14)
                            radius: width / 2
                            color: row.t
                            opacity: row.on ? 0 : 0.4
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                        }
                        Text {
                            id: rowNum
                            anchors.left: parent.left; anchors.leftMargin: root.s(12)
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.s(18)
                            text: ("0" + (row.index + 1)).slice(-2)
                            font.family: root.mono; font.weight: Font.Bold; font.pixelSize: root.s(9)
                            color: Qt.alpha(row.t, row.on ? 0.85 : 0.45)
                        }
                        Item {
                            id: rowTile
                            anchors.left: rowNum.right; anchors.leftMargin: root.s(4)
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.s(30); height: width
                            Rectangle {
                                anchors.fill: parent
                                radius: root.s(8)
                                color: Qt.alpha(row.t, row.on ? 0.22 : 0.1)
                                border.width: 1; border.color: Qt.alpha(row.t, row.on ? 0.4 : 0.14)
                                Behavior on color { ColorAnimation { duration: 140 } }
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !row.a.image || rowIcon.status === Image.Error
                                text: row.a.icon || root.g(0xF003B)
                                font.family: root.glyphs; font.pixelSize: root.s(18)
                                color: row.t
                                opacity: row.on ? 1 : 0.9
                            }
                            Image {
                                id: rowIcon
                                anchors.centerIn: parent
                                visible: !!row.a.image && status !== Image.Error
                                width: root.s(22); height: width
                                source: root.iconSrc(row.a)
                                sourceSize: Qt.size(64, 64)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true; smooth: true; mipmap: true
                            }
                        }

                        Column {
                            anchors.left: rowTile.right; anchors.leftMargin: root.s(10)
                            anchors.right: rowMeta.left; anchors.rightMargin: root.s(10)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.s(1)
                            Text {
                                width: parent.width
                                textFormat: Text.StyledText
                                text: root.marked(row.a.label, row.modelData.hits, root.hex(row.t), root.hex(row.on ? root.text : root.subtext1))
                                    + (row.modelData.param !== "" && row.a.param ? "<font color='" + root.hex(root.subtext0) + "'>  " + root.esc(row.modelData.param) + "</font>" : "")
                                font.family: root.mono; font.weight: row.on ? Font.Black : Font.Bold; font.pixelSize: root.s(13)
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: row.why !== "" ? row.why : (row.a.hint || "")
                                visible: text !== ""
                                font.family: root.mono; font.weight: row.why !== "" ? Font.Bold : Font.Medium; font.pixelSize: root.s(10)
                                color: row.why !== "" ? row.t : root.subtext0
                                opacity: row.on ? 0.95 : 0.65
                                elide: Text.ElideRight
                            }
                        }

                        Row {
                            id: rowMeta
                            anchors.right: parent.right; anchors.rightMargin: root.s(12)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.s(5)
                            Text {
                                visible: root.pinned.indexOf(row.a.id) >= 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.g(0xF0403)
                                font.family: root.glyphs; font.pixelSize: root.s(12)
                                color: Qt.alpha(row.t, 0.8)
                            }
                            Repeater {
                                model: row.on && row.a.keys ? row.a.keys.split(" ") : []
                                delegate: Rectangle {
                                    required property string modelData
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(root.s(20), keyText.implicitWidth + root.s(10)); height: root.s(20)
                                    radius: root.s(5)
                                    color: "transparent"
                                    border.width: 1; border.color: Qt.alpha(row.t, 0.45)
                                    Text {
                                        id: keyText
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.family: root.mono; font.weight: Font.Bold; font.pixelSize: root.s(9)
                                        color: row.t
                                    }
                                }
                            }
                            Rectangle {
                                visible: row.st === "on" || row.st === "off"
                                anchors.verticalCenter: parent.verticalCenter
                                width: root.s(26); height: root.s(14); radius: root.s(4)
                                color: row.st === "on" ? Qt.alpha(row.t, 0.85) : "transparent"
                                border.width: 1; border.color: Qt.alpha(row.t, row.st === "on" ? 0.85 : 0.4)
                                Rectangle {
                                    width: root.s(8); height: width; radius: root.s(2)
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: row.st === "on" ? parent.width - width - root.s(3) : root.s(3)
                                    color: row.st === "on" ? root.crust : Qt.alpha(row.t, 0.6)
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: {
                                root.peek = null
                                if (root.sel !== row.index) { root.sel = row.index; root.confirmId = "" }
                            }
                            onClicked: (m) => {
                                root.sel = row.index
                                input.forceActiveFocus()
                                if (m.button === Qt.RightButton) root.togglePin(row.a)
                                else root.run()
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: inspector
                anchors.left: listCol.right; anchors.leftMargin: root.s(16)
                anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                radius: root.s(16)
                color: Qt.alpha(root.surface0, 0.4)
                border.width: 1
                border.color: root.confirming ? Qt.alpha(root.danger, 0.55) : Qt.alpha(root.accent, 0.3)
                Behavior on border.color { ColorAnimation { duration: 200 } }
                clip: true

                Canvas {
                    id: dots
                    anchors.fill: parent
                    property color tone: root.accent
                    onToneChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        let c = getContext("2d")
                        c.reset()
                        let step = root.s(14), r = Math.max(0.6, root.s(0.9))
                        c.fillStyle = tone
                        for (let x = step / 2; x < width; x += step)
                            for (let y = step / 2; y < height; y += step) {
                                c.globalAlpha = 0.07 + 0.13 * Math.pow(1 - y / height, 2)
                                c.fillRect(x - r, y - r, r * 2, r * 2)
                            }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.alpha(card.wash, 0.1) }
                        GradientStop { position: 0.6; color: Qt.alpha(card.wash, 0) }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: root.accent
                    opacity: 0.18 * (1 - root.fire) * (root.fire > 0 ? 1 : 0)
                }

                Item {
                    id: stage
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    anchors.margins: root.s(14)
                    height: Math.min(root.s(176), parent.height * 0.48)
                    property real popT: 1
                    NumberAnimation { id: stagePop; target: stage; property: "popT"; from: 0; to: 1; duration: 340; easing.type: Easing.OutCubic }
                    Connections { target: root; function onPopChanged() { stagePop.restart() } }
                    opacity: stage.popT
                    transform: Translate { y: (1 - stage.popT) * root.s(8) }

                    Loader {
                        anchors.fill: parent
                        sourceComponent: {
                            switch (root.kind) {
                            case "wall": return wallStage
                            case "media": return mediaStage
                            case "volume": case "bright": return meterStage
                            case "battery": case "stats": return graphStage
                            case "timer": return timerStage
                            case "app": return appStage
                            case "art": return artStage
                            case "project": return projectStage
                            case "glyph": return glyphStage
                            default: return null
                            }
                        }
                    }
                }

                Column {
                    id: info
                    anchors.top: stage.bottom; anchors.topMargin: root.s(14)
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: root.s(16); anchors.rightMargin: root.s(16)
                    spacing: root.s(4)
                    visible: !!root.shown

                    Text {
                        width: parent.width
                        textFormat: Text.StyledText
                        text: !root.shown ? "" : root.shown === root.act && root.current
                            ? root.marked(root.shown.label, root.current.hits, root.hex(root.accent), root.hex(root.text))
                            : "<font color='" + root.hex(root.text) + "'>" + root.esc(root.shown.label) + "</font>"
                        font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(21); font.letterSpacing: -root.s(0.6)
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: root.s(14)
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    Text {
                        width: parent.width
                        text: !root.shown ? "" : root.confirming ? "This can't be undone from here" : (root.shown.hint || "")
                        font.family: root.mono; font.weight: Font.Medium; font.pixelSize: root.s(11)
                        color: root.confirming ? root.danger : root.subtext0
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Item { width: 1; height: root.s(6) }
                    Flow {
                        width: parent.width
                        spacing: root.s(6)
                        readonly property var a: root.shown
                        readonly property string st: root.stateOf(a) || ""
                        readonly property bool toggle: !!a && (st === "on" || st === "off")
                        readonly property bool mine: !!a && a === root.act
                        Tag { visible: parent.toggle; tone: root.subtext0; label: parent.toggle && parent.st === "on" ? "on" : "off" }
                        Tag { visible: parent.toggle; tone: root.accent; strong: true; label: parent.toggle && parent.st === "on" ? "→ off" : "→ on" }
                        Tag { visible: !!parent.a && !!parent.a.to; tone: root.accent; strong: true; label: parent.a && parent.a.to ? "→ " + parent.a.to : "" }
                        Tag {
                            visible: parent.mine && (root.paramInfo.show !== "" || !!root.paramInfo.missing)
                            tone: root.accent
                            strong: root.paramInfo.show !== "" && !root.paramInfo.implied
                            label: root.paramInfo.show !== ""
                                ? root.paramInfo.show + (root.paramInfo.unit ? (root.paramInfo.unit === "%" ? "%" : " " + root.paramInfo.unit) : "")
                                : (root.act && root.act.param && root.act.param.kind === "number" ? "add a number" : "type " + (root.paramInfo.hint || "something"))
                        }
                        Tag { visible: !!parent.a && root.pinned.indexOf(parent.a.id) >= 0; tone: root.subtext0; label: "pinned" }
                    }
                }

                Item {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.leftMargin: root.s(16); anchors.rightMargin: root.s(16); anchors.bottomMargin: root.s(14)
                    height: root.s(28)
                    visible: !!root.shown
                    Rectangle {
                        id: runKey
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        width: root.s(32); height: root.s(24); radius: root.s(6)
                        color: root.confirming ? root.danger : Qt.alpha(root.accent, 0.16)
                        border.width: 1; border.color: Qt.alpha(root.accent, 0.5)
                        Text {
                            anchors.centerIn: parent
                            text: root.peek ? root.g(0xF037D) : root.g(0xF0311)
                            font.family: root.glyphs; font.pixelSize: root.s(14)
                            color: root.confirming ? root.crust : root.accent
                        }
                    }
                    Text {
                        anchors.left: runKey.right; anchors.leftMargin: root.s(10)
                        anchors.right: pinHint.left; anchors.rightMargin: root.s(8)
                        anchors.verticalCenter: parent.verticalCenter
                        text: !root.shown ? "" : root.confirming ? "again to " + root.verbNow.toLowerCase() : root.verbNow
                        font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(14)
                        color: root.confirming ? root.danger : root.text
                        elide: Text.ElideRight
                    }
                    Caps {
                        anchors.right: pinHint.left; anchors.rightMargin: root.s(14)
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.altHint !== "" && !root.confirming
                        text: "shift ↵ " + root.altHint
                        font.capitalization: Font.MixedCase
                        font.letterSpacing: 0
                        font.weight: Font.Bold
                        color: Qt.alpha(root.tint("project"), 0.8)
                    }
                    Caps {
                        id: pinHint
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        visible: root.pinnable(root.shown)
                        text: root.shown && root.pinned.indexOf(root.shown.id) >= 0 ? "unpin" : "pin"
                        color: Qt.alpha(root.subtext0, 0.5)
                    }
                }
            }
        }

        Item {
            id: footer
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.leftMargin: root.s(26); anchors.rightMargin: root.s(26)
            height: root.s(34)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.s(16)
                Repeater {
                    model: [[root.g(0xF005D) + root.g(0xF0045), "move"], [root.g(0xF0311), "run"], ["ctrl s", "pin"], ["esc", "close"]]
                    delegate: Row {
                        required property var modelData
                        spacing: root.s(5)
                        Text {
                            text: modelData[0]
                            font.family: modelData[0].length > 2 ? root.mono : root.glyphs
                            font.weight: Font.Bold; font.pixelSize: root.s(10)
                            color: Qt.alpha(card.wash, 0.85)
                        }
                        Text {
                            text: modelData[1]
                            font.family: root.mono; font.weight: Font.Medium; font.pixelSize: root.s(10)
                            color: Qt.alpha(root.subtext1, 0.7)
                        }
                    }
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.s(14)
                Repeater {
                    model: root.readout
                    delegate: Row {
                        required property var modelData
                        spacing: root.s(5)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[0]
                            font.family: root.glyphs; font.pixelSize: root.s(11)
                            color: modelData[2]
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]
                            font.family: root.mono; font.weight: Font.Bold; font.pixelSize: root.s(10)
                            color: Qt.alpha(modelData[2], 0.8)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: wallStage
        ClippingRectangle {
            radius: root.s(12)
            color: Qt.alpha(root.text, 0.05)
            Image {
                id: wallImg
                anchors.fill: parent
                source: root.wallShown !== "" ? "file://" + root.wallShown : ""
                sourceSize.width: 720
                fillMode: Image.PreserveAspectCrop
                asynchronous: true; smooth: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220 } }
            }
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: root.s(46)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Qt.alpha(root.crust, 0.88) }
                }
            }
            Text {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.margins: root.s(10)
                text: root.wallShown === "" ? (root.shown && root.shown.id === "wall.set" ? "no wallpaper matches that" : "current wallpaper unknown") : root.wallShown.split("/").pop()
                font.family: root.mono; font.weight: Font.Bold; font.pixelSize: root.s(10)
                color: root.text
                elide: Text.ElideMiddle
            }
            Tag {
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: root.s(8)
                tone: root.tint("wallpaper")
                strong: true
                label: root.shown && root.shown.id === "wall.set" && root.wallShown !== root.wall ? "match" : root.shown && root.shown.id === "wall.random" ? "now → random" : "now"
            }
        }
    }

    Component {
        id: mediaStage
        Item {
            id: mediaRoot
            readonly property var pk: root.mediaPeek
            readonly property string artSrc: pk ? (pk.art || "") : root.art
            ClippingRectangle {
                id: artBox
                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                width: height
                radius: root.s(12)
                color: Qt.alpha(root.tint("media"), 0.1)
                Image {
                    anchors.fill: parent
                    source: mediaRoot.artSrc
                    sourceSize: Qt.size(320, 320)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true; smooth: true
                }
                Text {
                    anchors.centerIn: parent
                    visible: mediaRoot.artSrc === ""
                    text: root.g(0xF0387)
                    font.family: root.glyphs; font.pixelSize: root.s(48)
                    color: Qt.alpha(root.tint("media"), 0.6)
                }
            }
            Column {
                anchors.left: artBox.right; anchors.leftMargin: root.s(14)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.s(4)
                Caps {
                    text: mediaRoot.pk ? (root.shown.id === "media.next" ? root.g(0xF04AD) + " up next" : root.g(0xF04AE) + " previous")
                        : root.music.status === "Playing" ? root.g(0xF040A) + " playing" : root.music.status === "Paused" ? root.g(0xF03E4) + " paused" : "nothing playing"
                    font.family: root.glyphs
                    color: root.tint("media")
                }
                Text {
                    width: parent.width
                    text: mediaRoot.pk ? mediaRoot.pk.title : root.music.title || ""
                    visible: text !== ""
                    font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(15)
                    color: root.text
                    wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: mediaRoot.pk ? mediaRoot.pk.artist || "" : root.music.artist || ""
                    visible: text !== ""
                    font.family: root.mono; font.weight: Font.Medium; font.pixelSize: root.s(11)
                    color: root.subtext0
                    elide: Text.ElideRight
                }
                Item { width: 1; height: root.s(8) }
                Gauge {
                    width: parent.width
                    height: root.s(4)
                    visible: !mediaRoot.pk && !!root.music.title
                    value: root.musicLen > 0 ? root.musicPos / root.musicLen * 100 : root.num(root.music.percent, 0)
                    tone: root.tint("media")
                }
                Text {
                    text: root.musicTime
                    visible: !mediaRoot.pk && text !== ""
                    font.family: root.mono; font.weight: Font.Bold; font.pixelSize: root.s(9)
                    color: Qt.alpha(root.subtext0, 0.7)
                }
            }
        }
    }

    Component {
        id: meterStage
        Item {
            id: meterRoot
            readonly property var m: root.meter || ({ value: -1, max: 100, target: -1, dim: false, tone: root.seed, glyph: 0xF057E, caption: "" })
            Text {
                id: meterGlyph
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: root.s(4)
                text: root.g(parent.m.glyph)
                font.family: root.glyphs; font.pixelSize: root.s(30)
                color: Qt.alpha(parent.m.tone, 0.5)
            }
            Row {
                id: meterBig
                anchors.left: parent.left; anchors.leftMargin: root.s(4)
                anchors.bottom: meterCap.top
                spacing: root.s(8)
                Text {
                    id: meterNum
                    text: meterRoot.m.value >= 0 ? Math.round(meterRoot.m.value) : "--"
                    font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(56); font.letterSpacing: -root.s(2)
                    color: meterRoot.m.dim ? root.subtext0 : root.text
                }
                Text {
                    anchors.baseline: meterNum.baseline
                    visible: meterRoot.m.target >= 0
                    text: "→ " + Math.round(meterRoot.m.target)
                    font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(22)
                    color: meterRoot.m.tone
                }
            }
            Caps {
                id: meterCap
                anchors.left: parent.left; anchors.leftMargin: root.s(4)
                anchors.bottom: meterBar.top; anchors.bottomMargin: root.s(14)
                text: parent.m.caption
            }
            Gauge {
                id: meterBar
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: root.s(4); anchors.rightMargin: root.s(4)
                anchors.bottom: parent.bottom; anchors.bottomMargin: root.s(10)
                value: Math.max(0, parent.m.value)
                max: parent.m.max
                target: parent.m.target
                tone: parent.m.tone
                dim: parent.m.dim
            }
        }
    }

    Component {
        id: graphStage
        Item {
            id: graphRoot
            readonly property var gr: root.graph || ({ big: "--", caption: "", foot: "", pts: [], lo: 0, hi: 100, tone: root.seed, glyph: 0xF035B })
            Row {
                id: graphHead
                anchors.left: parent.left; anchors.top: parent.top; anchors.leftMargin: root.s(4)
                spacing: root.s(10)
                Text {
                    text: graphRoot.gr.big
                    font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(40); font.letterSpacing: -root.s(1.5)
                    color: root.text
                }
                Caps {
                    anchors.bottom: parent.bottom; anchors.bottomMargin: root.s(8)
                    text: graphRoot.gr.caption
                    color: graphRoot.gr.tone
                }
            }
            Text {
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: root.s(4)
                text: root.g(parent.gr.glyph)
                font.family: root.glyphs; font.pixelSize: root.s(26)
                color: Qt.alpha(parent.gr.tone, 0.5)
            }
            Spark {
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: graphHead.bottom; anchors.topMargin: root.s(6)
                anchors.bottom: graphFoot.top; anchors.bottomMargin: root.s(6)
                pts: parent.gr.pts
                lo: parent.gr.lo
                hi: parent.gr.hi
                tone: parent.gr.tone
            }
            Caps {
                id: graphFoot
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.leftMargin: root.s(4)
                text: parent.gr.foot
                font.capitalization: Font.MixedCase
                font.letterSpacing: 0
                font.weight: Font.Bold
                color: Qt.alpha(root.subtext0, 0.65)
                elide: Text.ElideRight
            }
        }
    }

    Component {
        id: timerStage
        Item {
            Canvas {
                id: ring
                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                width: height
                property real frac: root.timerView.frac
                property color tone: root.tint("timer")
                property bool live: (root.timerState.state || "idle") !== "idle"
                onFracChanged: requestPaint()
                onToneChanged: requestPaint()
                onLiveChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    let c = getContext("2d")
                    c.reset()
                    let lw = root.s(9), r = width / 2 - lw
                    c.lineWidth = lw
                    c.lineCap = "round"
                    c.strokeStyle = root.text
                    c.globalAlpha = 0.08
                    c.beginPath(); c.arc(width / 2, height / 2, r, 0, Math.PI * 2); c.stroke()
                    if (frac <= 0) return
                    c.strokeStyle = tone
                    c.globalAlpha = live ? 1 : 0.45
                    c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.min(1, frac)); c.stroke()
                }
                Text {
                    anchors.centerIn: parent
                    text: root.g(0xF051B)
                    font.family: root.glyphs; font.pixelSize: root.s(30)
                    color: Qt.alpha(ring.tone, 0.7)
                }
            }
            Column {
                anchors.left: ring.right; anchors.leftMargin: root.s(16)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.s(4)
                Text {
                    text: root.timerView.label
                    font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(34); font.letterSpacing: -root.s(1)
                    color: root.text
                }
                Caps { width: parent.width; text: root.timerView.caption; color: root.tint("timer"); elide: Text.ElideRight }
            }
        }
    }

    Component {
        id: artStage
        Item {
            id: artRoot
            readonly property var a: root.shown || ({})
            readonly property color tone: root.tint("spotify")
            ClippingRectangle {
                id: coverBox
                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                width: height
                radius: artRoot.a.kind === "artist" ? width / 2 : root.s(12)
                color: Qt.alpha(artRoot.tone, 0.1)
                Image {
                    id: coverImg
                    anchors.fill: parent
                    source: root.iconSrc(artRoot.a)
                    sourceSize: Qt.size(320, 320)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true; smooth: true
                }
                Text {
                    anchors.centerIn: parent
                    visible: coverImg.status !== Image.Ready
                    text: artRoot.a.icon || root.g(0xF04C7)
                    font.family: root.glyphs; font.pixelSize: root.s(48)
                    color: Qt.alpha(artRoot.tone, 0.6)
                }
            }
            Column {
                anchors.left: coverBox.right; anchors.leftMargin: root.s(14)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.s(4)
                Caps {
                    text: (artRoot.a.kind || "") + (artRoot.a.mine ? "  ·  yours" : "")
                    color: artRoot.tone
                }
                Text {
                    width: parent.width
                    text: artRoot.a.label || ""
                    font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(15)
                    color: root.text
                    wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: artRoot.a.sub || ""
                    visible: text !== ""
                    font.family: root.mono; font.weight: Font.Medium; font.pixelSize: root.s(11)
                    color: root.subtext0
                    wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                }
            }
        }
    }

    Component {
        id: projectStage
        Item {
            id: projRoot
            readonly property var a: root.shown || ({})
            readonly property var p: a.project || ({})
            readonly property var pk: root.projPeek[p.path] || ({})
            readonly property bool fresh: !!p.new
            readonly property string typed: a === root.act ? root.paramInfo.value : ""
            readonly property color tone: root.tint("project")
            readonly property string newName: p.next ? p.next : typed === "" ? "" : /\s/.test(typed) ? "" : typed
            readonly property var lines: {
                let out = []
                if (fresh) {
                    if (p.next) out.push([0xF0770, p.root + "/" + p.next])
                    else if (typed !== "" && /\s/.test(typed)) out.push([0xF06A9, "Claude names it from your idea"])
                    else if (typed !== "") out.push([0xF0770, p.root + "/" + typed])
                    else out.push([0xF0770, "type a name, or describe the idea"])
                    return out
                }
                if (pk.gone) return [[0xF0026, "this folder is gone"]]
                if (pk.git) out.push([0xF062C, (pk.branch || "detached") + (pk.dirty ? "  ·  " + pk.dirty + " changed" : "  ·  clean") + (pk.repoRoot ? "  ·  in " + pk.repoRoot : "")])
                if (pk.commit) out.push([0xF0718, pk.commit + (pk.commitAgo ? "  ·  " + pk.commitAgo : "")])
                let blurb = p.desc || pk.readme || ""
                if (blurb !== "") out.push([0xF0219, blurb])
                let st = []
                if (p.opens) st.push("opened " + p.opens + (p.opens === 1 ? " time" : " times"))
                if (p.last) st.push("last " + root.ago(p.last))
                else if (!p.latest) st.push("never opened with do")
                if (pk.files !== undefined) st.push(pk.files + (pk.files === 1 ? " item" : " items"))
                if (st.length) out.push([0xF02DA, st.join("  ·  ")])
                return out
            }
            Rectangle {
                id: projTile
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                width: Math.min(parent.height, root.s(118)); height: width
                radius: root.s(14)
                color: Qt.alpha(projRoot.tone, 0.1)
                border.width: 1; border.color: Qt.alpha(projRoot.tone, 0.3)
                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: projRoot.fresh ? 0 : -root.s(6)
                    text: projRoot.a.icon || root.g(0xF0770)
                    font.family: root.glyphs; font.pixelSize: root.s(50)
                    color: projRoot.tone
                }
                Gauge {
                    visible: !projRoot.fresh
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.margins: root.s(14)
                    height: root.s(4)
                    value: Math.max(0.03, projRoot.p.heat || 0) * 100
                    tone: projRoot.tone
                    dim: !projRoot.p.heat
                }
            }
            Column {
                anchors.left: projTile.right; anchors.leftMargin: root.s(14)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.s(5)
                Caps {
                    width: parent.width
                    text: (projRoot.fresh ? "new " : "") + [projRoot.p.shortcut ? "shortcut" : projRoot.p.type, projRoot.p.lang].filter(x => !!x).join("  ·  ")
                    color: projRoot.tone
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: projRoot.fresh && projRoot.newName !== ""
                    text: projRoot.newName
                    font.family: root.mono; font.weight: Font.Black; font.pixelSize: root.s(24); font.letterSpacing: -root.s(0.8)
                    color: root.text
                    elide: Text.ElideRight
                }
                Repeater {
                    model: projRoot.lines
                    delegate: Row {
                        required property var modelData
                        width: parent.width
                        spacing: root.s(7)
                        Text {
                            id: lineGlyph
                            text: root.g(modelData[0])
                            font.family: root.glyphs; font.pixelSize: root.s(12)
                            color: Qt.alpha(projRoot.tone, 0.85)
                        }
                        Text {
                            width: parent.width - lineGlyph.width - parent.spacing
                            text: modelData[1]
                            font.family: root.mono; font.weight: Font.Medium; font.pixelSize: root.s(11)
                            color: root.subtext1
                            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                        }
                    }
                }
                Caps {
                    visible: !!projRoot.a.alt && projRoot.a === root.act
                    text: projRoot.a.alt ? (root.altNow ? "↵ " : "shift ↵ ") + projRoot.a.alt.verb.toLowerCase() + "  ·  " + projRoot.a.alt.how : ""
                    font.capitalization: Font.MixedCase
                    font.letterSpacing: 0
                    font.weight: Font.Bold
                    color: Qt.alpha(projRoot.tone, 0.75)
                }
            }
        }
    }

    Component {
        id: appStage
        Item {
            Rectangle {
                anchors.centerIn: parent
                width: root.s(150); height: width; radius: width / 2
                color: Qt.alpha(root.iconToneOk ? root.iconTone : root.tint("app"), 0.14)
            }
            Rectangle {
                anchors.centerIn: parent
                width: root.s(112); height: width; radius: width / 2
                color: Qt.alpha(root.iconToneOk ? root.iconTone : root.tint("app"), 0.14)
            }
            Image {
                anchors.centerIn: parent
                width: root.s(76); height: width
                source: root.iconSrc(root.shown)
                sourceSize: Qt.size(160, 160)
                fillMode: Image.PreserveAspectFit
                asynchronous: true; smooth: true; mipmap: true
            }
        }
    }

    Component {
        id: glyphStage
        Item {
            readonly property var a: root.shown
            readonly property string st: root.stateOf(a) || ""
            readonly property bool toggle: !!a && (st === "on" || st === "off")
            Rectangle {
                anchors.centerIn: glyphBig
                width: root.s(118); height: width; radius: width / 2
                color: "transparent"
                border.width: root.s(2); border.color: Qt.alpha(root.accent, 0.22)
            }
            Rectangle {
                anchors.centerIn: glyphBig
                width: root.s(150); height: width; radius: width / 2
                color: "transparent"
                border.width: 1; border.color: Qt.alpha(root.accent, 0.1)
            }
            Text {
                id: glyphBig
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: parent.toggle ? -root.s(48) : 0
                text: parent.a ? (parent.a.icon || root.g(0xF003B)) : ""
                font.family: root.glyphs; font.pixelSize: root.s(62)
                color: root.accent
            }
            Item {
                visible: parent.toggle
                anchors.left: glyphBig.right; anchors.leftMargin: root.s(58)
                anchors.verticalCenter: glyphBig.verticalCenter
                width: root.s(60); height: root.s(30)
                readonly property bool isOn: !!parent.a && parent.st === "on"
                Rectangle {
                    anchors.fill: parent
                    radius: root.s(8)
                    color: parent.isOn ? Qt.alpha(root.accent, 0.85) : "transparent"
                    border.width: root.s(2); border.color: Qt.alpha(root.accent, parent.isOn ? 0.85 : 0.45)
                }
                Rectangle {
                    width: root.s(18); height: width; radius: root.s(4)
                    anchors.verticalCenter: parent.verticalCenter
                    x: parent.isOn ? parent.width - width - root.s(6) : root.s(6)
                    color: parent.isOn ? root.crust : Qt.alpha(root.accent, 0.6)
                }
            }
        }
    }
}
