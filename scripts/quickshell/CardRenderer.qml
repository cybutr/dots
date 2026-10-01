import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// Standalone, reusable card renderer — shared by the inline chat card (ClaudeAsk.qml) and
// the persistent pinned-card panel (PinnedCards.qml). Self-contained: owns its own
// Scaler/MatugenColors, so it doesn't depend on an enclosing window id.
        Item {
            id: cr
            Scaler { id: scaler; currentWidth: Screen.width }
            function s(val) { return scaler.s(val); }
            MatugenColors { id: _theme }
            readonly property color base: _theme.base
            readonly property color mantle: _theme.mantle
            readonly property color crust: _theme.crust
            readonly property color text: _theme.text
            readonly property color subtext0: _theme.subtext0
            readonly property color overlay0: _theme.overlay0 || "#6c7086"
            readonly property color surface0: _theme.surface0
            readonly property color surface1: _theme.surface1
            readonly property color surface2: _theme.surface2
            readonly property color mauve: _theme.mauve || "#cba6f7"
            readonly property color blue: _theme.blue
            readonly property color green: _theme.green
            readonly property color peach: _theme.peach
            readonly property color red: _theme.red
            property var spec: ({})
            property bool cOpen: true
            property bool standalone: false
            // one-shot cards (approval / reauth) collapse themselves after the choice
            property bool dismissed: false
            signal dismissRequested(string cardId)
            opacity: dismissed ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            // live guide settings — let the user dial polish up/down and pick a card accent
            property bool cardAnimations: true
            property bool cardDepth: true
            property string cardAccentName: "blue"
            property string agendaDefaultFilter: "all"
            readonly property color accent: cardAccentName === "mauve" ? mauve
                : cardAccentName === "green" ? green
                : cardAccentName === "peach" ? peach
                : cardAccentName === "red" ? red
                : cardAccentName === "teal" ? (_theme.teal || "#94e2d5")
                : blue
            Process {
                id: crSettingsReader
                running: true
                command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
                stdout: StdioCollector { onStreamFinished: { try { let p = JSON.parse(this.text.trim() || "{}"); if (p.cardAnimations !== undefined) cr.cardAnimations = p.cardAnimations; if (p.cardDepth !== undefined) cr.cardDepth = p.cardDepth; if (p.cardAccent !== undefined) cr.cardAccentName = p.cardAccent; if (p.agendaDefaultFilter !== undefined) cr.agendaDefaultFilter = p.agendaDefaultFilter; } catch (e) {} } }
            }
            Process {
                id: crSettingsWatcher
                running: true
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "while [ ! -f ~/.config/hypr/settings.json ]; do sleep 1; done; exec inotifywait -m -e close_write,modify ~/.config/hypr/settings.json 2>/dev/null"]
                stdout: SplitParser { splitMarker: "\n"; onRead: (data) => { crSettingsReader.running = false; crSettingsReader.running = true; } }
            }
            // compact "chip" mode (standalone panel only) — collapses the full card down to
            // an icon+title strip, default driven by the guide's "Pinned Card Compact Default"
            // setting at pin time, toggled per-card by clicking the chip/shrink button. Grabbing
            // the card's first row/gauge/bar value as a fake "glance stat" was arbitrary noise
            // (whichever block happened to be first, not necessarily the headline number) — the
            // chip only shows spec.glance now, an explicit one-liner the agent can opt into.
            property bool compact: false
            signal compactToggled(bool v)
            // extra height added by an open dropdown in expand mode (not overlay mode).
            // updated synchronously in onExpandedChanged so PinnedCards can resize
            // cardWrap in the same frame — avoids Qt.callLater one-frame hit-test gap.
            property real dropdownExpandH: 0
            // a card holding a one-shot credential field can't be pinned/unpinned at all —
            // hides the pin toggle entirely instead of letting it pin a card that locks
            // itself the moment the field is used
            readonly property bool hasSecret: {
                let blk = cr.spec.blocks;
                if (!blk) return false;
                for (let i = 0; i < blk.length; i++)
                    if (blk[i] && blk[i].kind === "secret") return true;
                return false;
            }
            // one-shot auth/approval cards (autopilot_decide, or open_url to Google
            // consent) can't be pinned either — reauth/approval is meaningless once
            // detached from the chat row that triggered it. Mirrors qs_mcp.py's
            // _has_approval_block so client and server agree.
            readonly property bool hasApproval: {
                let blk = cr.spec.blocks;
                if (!blk) return false;
                for (let i = 0; i < blk.length; i++) {
                    let b = blk[i];
                    if (!b || (b.kind !== "buttons" && b.kind !== "pills")) continue;
                    let items = b.items || [];
                    for (let j = 0; j < items.length; j++) {
                        let it = items[j];
                        if (!it) continue;
                        let act = (it.action) || {};
                        if (act.fn === "autopilot_decide") return true;
                        if (act.fn === "open_url" &&
                            String((act.args || {}).url || "").indexOf("accounts.google.com") >= 0) return true;
                    }
                }
                return false;
            }
            // one mode covers both: composer visible at the bottom, AND blocks become
            // clickable to select — see editModeBtn in the header (icon-swap toggle)
            property bool editMode: false
            // single shared selection — selecting a different block (or the same one again,
            // to deselect) replaces whichever was selected before; nothing renders until
            // something is selected, no permanent per-block chrome
            property int selectedBlockIndex: -1

            // ---- debug-only UI probe manifest (off by default, zero overhead unless
            // QS_PROBE_DEBUG=1 in the launching environment) — self-reports exact click
            // targets + live state to a JSON file, so qs_probe.py (Claude's own click tool)
            // can target elements by stable name and verify state without ever taking a
            // screenshot. Same idea as Qt's Accessible/QML test tooling (Spix, Squish):
            // object-level access beats pixel-guessing, it just doesn't exist for this
            // hand-rolled widget stack, so this is the minimal local equivalent.
            readonly property bool probeDebug: Quickshell.env("QS_PROBE_DEBUG") === "1"
            readonly property string probeFile: Quickshell.env("HOME") + "/.cache/quickshell/claude/ui_manifest.json"
            readonly property string probeCardKey: cr.spec.card_id || cr.spec.title || "unknown"
            Process { id: probeWriter; running: false }
            function reportAll() {
                if (!cr.probeDebug) return;
                let entries = {};
                function add(name, item, state) {
                    if (!item || !item.width || !item.height) return;
                    let g = item.mapToGlobal(0, 0);
                    entries[name] = { x: g.x, y: g.y, w: item.width, h: item.height, state: state || {} };
                }
                add("pin", pinBtn, { pinned: cr.pinned, standalone: cr.standalone });
                add("shrink", shrinkBtn, { compact: cr.compact });
                add("revert", revertBtn, { hasHistory: cr.hasHistory });
                add("chip", chipRect, { compact: cr.compact });
                add("edit_mode_toggle", editModeBtn, { editMode: cr.editMode });
                add("quicksend_send", sendBtn, { editMode: cr.editMode });
                for (let i = 0; i < blocksRepeater.count; i++) {
                    let bw = blocksRepeater.itemAt(i);
                    if (!bw) continue;
                    add("block" + i + "_select", bw.loaderRef, { selected: bw.selected, kind: bw.modelData.kind });
                    add("block" + i + "_edit_pill", bw.pillRef, { visible: bw.pillRef ? bw.pillRef.visible : false });
                }
                probeWriter.command = ["python3", "-c",
                    "import sys,json,os\n" +
                    "p=sys.argv[1]; key=sys.argv[2]; data=json.loads(sys.argv[3])\n" +
                    "try:\n    m=json.load(open(p))\nexcept Exception:\n    m={}\n" +
                    "m[key]=data\n" +
                    "os.makedirs(os.path.dirname(p), exist_ok=True)\n" +
                    "json.dump(m, open(p,'w'))\n",
                    cr.probeFile, cr.probeCardKey, JSON.stringify(entries)];
                probeWriter.running = false; probeWriter.running = true;
            }
            Timer { interval: 400; running: cr.probeDebug; repeat: true; onTriggered: cr.reportAll() }

            property var sendPlain: function(text) {
                sendPlainProc.command = ["bash", "-c", "printf '%s\\n' \"$1\" > /tmp/qs_claude_in", "_",
                    JSON.stringify({ text: text, context: "" })];
                sendPlainProc.running = false; sendPlainProc.running = true;
            }
            signal pinRequested()
            signal unpinRequested()
            // emits the already-popped prior spec (as JSON text) so the parent — PinnedCards.qml
            // for a pinned card, ClaudeAsk.qml for an inline chat row — can write it back to
            // wherever this card actually lives, without either side needing its own copy of
            // the pop logic (only one history file, popped exactly once per click)
            signal revertRequested(string poppedSpecJson)
            Process { id: sendPlainProc; running: false }

            readonly property string historyFile: Quickshell.env("HOME") + "/.cache/quickshell/claude/card_history.json"
            property bool hasHistory: false
            Process {
                id: historyChecker
                running: false
                command: ["python3", "-c",
                    "import sys,json,os\n" +
                    "p=sys.argv[1]; cid=sys.argv[2]\n" +
                    "try:\n    m=json.load(open(p))\nexcept Exception:\n    m={}\n" +
                    "print('1' if m.get(cid) else '0')\n",
                    cr.historyFile, cr.spec.card_id || ""]
                stdout: StdioCollector { onStreamFinished: cr.hasHistory = this.text.trim() === "1" }
            }
            function checkHistory() {
                if (!(cr.spec.card_id || "")) { cr.hasHistory = false; return; }
                historyChecker.running = false; historyChecker.running = true;
            }
            Process {
                id: revertPopper
                running: false
                command: ["python3", "-c",
                    "import sys,json,os\n" +
                    "p=sys.argv[1]; cid=sys.argv[2]\n" +
                    "try:\n    m=json.load(open(p))\nexcept Exception:\n    m={}\n" +
                    "lst=m.get(cid) or []\n" +
                    "popped=lst.pop() if lst else None\n" +
                    "m[cid]=lst\n" +
                    "os.makedirs(os.path.dirname(p), exist_ok=True)\n" +
                    "json.dump(m, open(p,'w'))\n" +
                    "print(json.dumps(popped) if popped is not None else '')\n",
                    cr.historyFile, cr.spec.card_id || ""]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let t = this.text.trim();
                        if (t !== "") { cr.revertRequested(t); cr.checkHistory(); }
                    }
                }
            }
            function requestRevert() { revertPopper.running = false; revertPopper.running = true; }

            // Pinned state is never trusted from the replayed chat stream (spec._pin_id
            // there is whatever id was true the moment it was *originally* pinned — stale
            // forever after, since qs_mcp.py's dedup-by-title can later reassign that title
            // to a different id, or it can get unpinned from the side panel entirely). The
            // file is the only ground truth; this re-reads it by title whenever spec changes
            // or shortly after a click, so reopening the chat or a dedup reassignment can't
            // leave the icon out of sync with what's actually pinned.
            property var pinId: -1
            readonly property bool pinned: pinId >= 0
            Process {
                id: pinStateChecker
                running: false
                command: ["python3", "-c",
                    "import sys,json,os\n" +
                    "p=os.path.expanduser('~/.cache/quickshell/claude/pinned_cards.json')\n" +
                    "title=sys.argv[1].strip().lower()\n" +
                    "try:\n    m=json.load(open(p))\nexcept Exception:\n    m=[]\n" +
                    "match=next((e for e in m if title and (e.get('spec',{}).get('title') or '').strip().lower()==title), None)\n" +
                    "print(match['id'] if match else -1)\n",
                    cr.spec.title || ""]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let v = parseInt(this.text.trim());
                        cr.pinId = (!isNaN(v) && v >= 0) ? v : -1;
                    }
                }
            }
            function checkPinnedState() {
                if (cr.standalone || !(cr.spec.title || "")) return;
                pinStateChecker.running = false; pinStateChecker.running = true;
            }
            Timer { id: recheckTimer; interval: 200; repeat: false; onTriggered: cr.checkPinnedState() }
            function recheckSoon() { recheckTimer.restart(); }
            Component.onCompleted: { cr.checkPinnedState(); cr.checkHistory(); }
            onSpecChanged: { cr.checkPinnedState(); cr.checkHistory(); }
            // Live watch on the pin file itself — covers unpinning from the standalone
            // panel's own X button (PinnedCards.qml's unpin()), which never touches this
            // chat-side card directly, so without this the icon stayed stuck filled.
            Process {
                running: !cr.standalone
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
                    "f=~/.cache/quickshell/claude/pinned_cards.json; mkdir -p \"$(dirname \"$f\")\"; touch \"$f\"; " +
                    "inotifywait -m -e close_write,create \"$f\" 2>/dev/null"]
                stdout: SplitParser { splitMarker: "\n"; onRead: (data) => cr.checkPinnedState() }
            }
            // ---- shared live-metrics bus: cpu/mem/temp/battery/volume polled once by a
            // background script instead of every gauge/bar spawning its own shell command.
            readonly property string metricsBusFile: Quickshell.env("HOME") + "/.cache/quickshell/claude/live_metrics.json"
            readonly property string metricsBusPidFile: Quickshell.env("HOME") + "/.cache/quickshell/claude/metrics_bus.pid"
            readonly property string metricsBusScript: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/claude/metrics_bus.py"
            readonly property string metricsBusSpawnScript:
                "import subprocess,os\n" +
                "pidf = '" + cr.metricsBusPidFile + "'\n" +
                "alive = False\n" +
                "try:\n" +
                "    pid = int(open(pidf).read().strip())\n" +
                "    os.kill(pid, 0)\n" +
                "    alive = True\n" +
                "except Exception:\n" +
                "    pass\n" +
                "if not alive:\n" +
                "    subprocess.Popen(['python3', '" + cr.metricsBusScript + "'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)\n"
            function extractMetric(jsonText, key) {
                try {
                    let v = JSON.parse(jsonText)[key];
                    return v === undefined || v === null ? "" : ("" + v);
                } catch (e) {
                    return "";
                }
            }
            function progFrac(v) {
                if (typeof v === "number") return Math.max(0, Math.min(1, v));
                let s = ("" + v).trim();
                if (s.endsWith("%")) return Math.max(0, Math.min(1, parseFloat(s) / 100));
                let f = parseFloat(s);
                if (isNaN(f)) return 0;
                return Math.max(0, Math.min(1, f > 1 ? f / 100 : f));
            }
            // numeric prefix of a value string ("73%" -> 73, "1.2 GB" -> 1.2), NaN if none
            function parseNum(v) {
                let m = ("" + v).match(/^-?\d*\.?\d+/);
                return m ? parseFloat(m[0]) : NaN;
            }
            // render an animated count-up value back with the original suffix + decimal places
            function formatNum(animVal, orig) {
                let s = "" + orig;
                let m = s.match(/^-?\d*\.?\d+/);
                if (!m) return s;
                let dec = m[0].indexOf(".") >= 0 ? m[0].split(".")[1].length : 0;
                return animVal.toFixed(dec) + s.slice(m[0].length);
            }
            // labels where a HIGH reading is good and a LOW one is the problem — invert the
            // threshold direction so a full battery reads green, not critical-red
            function autoInvert(label) {
                return /bat|charg|free|avail|signal|wifi|uptime|fps|score|health/.test(("" + label).toLowerCase());
            }
            // Normal state keeps the per-tile matugen color (base). Only escalate to fixed
            // amber/red at the warn/crit thresholds — those two stay hardcoded so a real
            // warning reads warning even on a warm wallpaper. opt out with semantic:false.
            function semanticColor(value, md, base) {
                md = md || {};
                base = base || cr.accent;
                if (md.semantic === false) return base;
                let p = cr.progFrac(value);
                let invert = md.invert === true || (md.invert === undefined && cr.autoInvert(md.label || md.id || ""));
                let warn = md.warn !== undefined ? (md.warn > 1 ? md.warn / 100 : md.warn) : (invert ? 0.30 : 0.75);
                let crit = md.crit !== undefined ? (md.crit > 1 ? md.crit / 100 : md.crit) : (invert ? 0.15 : 0.90);
                let level = invert ? (p <= crit ? 2 : p <= warn ? 1 : 0)
                                   : (p >= crit ? 2 : p >= warn ? 1 : 0);
                return level === 2 ? "#f38ba8" : level === 1 ? "#f9e2af" : base;
            }
            // Fallback when no icon resolves: first letter of each *word* (punctuation
            // stripped, so a label like "Disk /" badges as "DI" not "D/"), max 2 chars.
            function iconFor(label) {
                let words = ("" + label).replace(/[^A-Za-z ]/g, "").trim().split(/\s+/).filter(w => w.length > 0);
                if (words.length === 0) return "?";
                if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
                return (words[0][0] + words[1][0]).toUpperCase();
            }
            // Flatten the card's numeric blocks (display/gauges/bars) into a short list of
            // glanceable stats so the COLLAPSED chip can show real live data instead of a
            // static one-liner — a collapsed card with no info is useless. Capped so the chip
            // stays a chip; the full card is one click away for the rest.
            readonly property var glanceStats: {
                let out = [];
                let blk = cr.spec.blocks || [];
                for (let i = 0; i < blk.length && out.length < 3; i++) {
                    let b = blk[i];
                    if (!b || (b.kind !== "display" && b.kind !== "gauges" && b.kind !== "bars")) continue;
                    let items = b.items || [];
                    for (let j = 0; j < items.length && out.length < 3; j++) {
                        let it = items[j];
                        if (!it || it.separator === true) continue;
                        out.push({
                            label: it.label || "", value: it.value !== undefined ? ("" + it.value) : "",
                            unit: it.unit || "", icon: it.icon || "",
                            metric: it.metric || "", source: it.source || "", watch: it.watch || "",
                            interval_ms: it.interval_ms || 0
                        });
                    }
                }
                return out;
            }
            // a card_start placeholder ({_sid} only) has no blocks yet — render a skeleton
            // shimmer instead of a bare empty housing until card_update fills it in.
            readonly property bool isBuilding: !cr.spec.blocks || cr.spec.blocks.length === 0
            // Name -> real Nerd Font glyph, via \uXXXX JS escapes (plain ASCII in this file,
            // turned into the actual PUA codepoint at runtime) — hand-typing the raw glyph
            // byte was the old bug (silently vanished). Claude sends a semantic name like
            // icon:"cpu"; unknown names fall back to the letter badge instead of printing junk.
            readonly property var iconMap: ({
                "os": String.fromCharCode(0xf108), "desktop": String.fromCharCode(0xf108),
                "kernel": String.fromCharCode(0xf17c), "linux": String.fromCharCode(0xf17c),
                "cpu": String.fromCharCode(0xf2db), "chip": String.fromCharCode(0xf2db), "processor": String.fromCharCode(0xf2db),
                "gpu": String.fromCharCode(0xf26c), "graphics": String.fromCharCode(0xf26c), "display": String.fromCharCode(0xf26c),
                "memory": String.fromCharCode(0xf1b2), "ram": String.fromCharCode(0xf1b2), "mem": String.fromCharCode(0xf1b2),
                "disk": String.fromCharCode(0xf0a0), "storage": String.fromCharCode(0xf0a0), "drive": String.fromCharCode(0xf0a0),
                "volume": String.fromCharCode(0xf028), "audio": String.fromCharCode(0xf028), "sound": String.fromCharCode(0xf028),
                "wifi": String.fromCharCode(0xf1eb), "network": String.fromCharCode(0xf1eb),
                "bluetooth": String.fromCharCode(0xf293),
                "battery": String.fromCharCode(0xf240),
                "power": String.fromCharCode(0xf011),
                "bolt": String.fromCharCode(0xf0e7), "performance": String.fromCharCode(0xf0e7), "lightning": String.fromCharCode(0xf0e7),
                "gear": String.fromCharCode(0xf013), "settings": String.fromCharCode(0xf013), "config": String.fromCharCode(0xf013),
                "temp": String.fromCharCode(0xf2c9), "temperature": String.fromCharCode(0xf2c9), "thermometer": String.fromCharCode(0xf2c9),
                "clock": String.fromCharCode(0xf017), "time": String.fromCharCode(0xf017),
                "calendar": String.fromCharCode(0xf133), "date": String.fromCharCode(0xf133),
                "task": String.fromCharCode(0xf0ae), "tasks": String.fromCharCode(0xf0ae), "check": String.fromCharCode(0xf00c), "close": String.fromCharCode(0xf00d),
                "user": String.fromCharCode(0xf007), "person": String.fromCharCode(0xf007),
                "folder": String.fromCharCode(0xf07b), "file": String.fromCharCode(0xf15b),
                "terminal": String.fromCharCode(0xf120), "code": String.fromCharCode(0xf121),
                "warning": String.fromCharCode(0xf071), "info": String.fromCharCode(0xf05a), "question": String.fromCharCode(0xf059),
                "chart": String.fromCharCode(0xf080), "dashboard": String.fromCharCode(0xf0e4),
                "workspace": String.fromCharCode(0xf009), "workspaces": String.fromCharCode(0xf009), "grid": String.fromCharCode(0xf009),
                "widget": String.fromCharCode(0xf2d0), "window": String.fromCharCode(0xf2d0), "panel": String.fromCharCode(0xf2d0),
                "mail": String.fromCharCode(0xf0e0), "mailbox": String.fromCharCode(0xf0e0), "inbox": String.fromCharCode(0xf01c), "message": String.fromCharCode(0xf0e0),
                "lock": String.fromCharCode(0xf023), "locked": String.fromCharCode(0xf023), "unlock": String.fromCharCode(0xf09c),
                "sleep": String.fromCharCode(0xf186), "moon": String.fromCharCode(0xf186), "suspend": String.fromCharCode(0xf186), "night": String.fromCharCode(0xf186),
                "reboot": String.fromCharCode(0xf01e), "restart": String.fromCharCode(0xf01e), "refresh": String.fromCharCode(0xf01e),
                "shutdown": String.fromCharCode(0xf011), "off": String.fromCharCode(0xf011),
                "play": String.fromCharCode(0xf04b), "pause": String.fromCharCode(0xf04c), "stop": String.fromCharCode(0xf04d),
                "next": String.fromCharCode(0xf051), "prev": String.fromCharCode(0xf048), "previous": String.fromCharCode(0xf048),
                "shuffle": String.fromCharCode(0xf074), "random": String.fromCharCode(0xf074),
                "skip": String.fromCharCode(0xf050), "skip-forward": String.fromCharCode(0xf050), "forward": String.fromCharCode(0xf050), "fast-forward": String.fromCharCode(0xf050),
                "skip-back": String.fromCharCode(0xf049), "rewind": String.fromCharCode(0xf049),
                "refresh-cw": String.fromCharCode(0xf01e), "reload": String.fromCharCode(0xf01e), "sync": String.fromCharCode(0xf021), "rotate": String.fromCharCode(0xf01e),
                "layers": String.fromCharCode(0xf5fd), "layer": String.fromCharCode(0xf5fd), "stack": String.fromCharCode(0xf5fd),
                "music": String.fromCharCode(0xf001), "speaker": String.fromCharCode(0xf028),
                "home": String.fromCharCode(0xf015), "star": String.fromCharCode(0xf005), "heart": String.fromCharCode(0xf004),
                "search": String.fromCharCode(0xf002), "edit": String.fromCharCode(0xf044), "trash": String.fromCharCode(0xf1f8),
                "download": String.fromCharCode(0xf019), "upload": String.fromCharCode(0xf093), "share": String.fromCharCode(0xf064),
                "copy": String.fromCharCode(0xf0c5), "paste": String.fromCharCode(0xf0ea), "cut": String.fromCharCode(0xf0c4),
                "link": String.fromCharCode(0xf0c1), "external": String.fromCharCode(0xf08e),
                "arrow-up": String.fromCharCode(0xf062), "arrow-down": String.fromCharCode(0xf063),
                "arrow-left": String.fromCharCode(0xf060), "arrow-right": String.fromCharCode(0xf061),
                "plus": String.fromCharCode(0xf067), "minus": String.fromCharCode(0xf068), "times": String.fromCharCode(0xf00d),
                "eye": String.fromCharCode(0xf06e), "hide": String.fromCharCode(0xf070),
                "mic": String.fromCharCode(0xf130), "mic-off": String.fromCharCode(0xf131),
                "camera": String.fromCharCode(0xf030), "image": String.fromCharCode(0xf03e), "photo": String.fromCharCode(0xf03e),
                "map": String.fromCharCode(0xf279), "location": String.fromCharCode(0xf041),
                "tag": String.fromCharCode(0xf02b), "flag": String.fromCharCode(0xf024),
                "key": String.fromCharCode(0xf084), "shield": String.fromCharCode(0xf132), "bug": String.fromCharCode(0xf188),
                "vpn": String.fromCharCode(0xf132), "ethernet": String.fromCharCode(0xf6ff), "lan": String.fromCharCode(0xf6ff)
            })
            function resolveIcon(name, label) {
                let key = ("" + (name || "")).trim().toLowerCase();
                if (key === "") return cr.iconFor(label);
                if (cr.iconMap[key] !== undefined) return cr.iconMap[key];
                if (key.length <= 2) return name;      // looks like an actual glyph already
                return cr.iconFor(label);
            }

            // ---- local action registry: lets buttons/pills run a known system action
            // directly (zero chat tokens) instead of always round-tripping the click as
            // a new message. Only a fixed allowlist of fn names is honored.
            function buildActionCmd(fnName, args) {
                args = args || {};
                function pick(v, allowed) { return allowed.indexOf(v) >= 0 ? v : null; }
                switch (fnName) {
                    case "power_profile": {
                        let p = pick(args.profile, ["performance", "balanced", "power-saver"]);
                        return p ? ("powerprofilesctl set " + p) : null;
                    }
                    case "toggle_wifi":
                        return args.state ? ("nmcli radio wifi " + (args.state === "off" ? "off" : "on"))
                                          : "nmcli radio wifi toggle";
                    case "toggle_bluetooth":
                        return "bash " + Quickshell.env("HOME") +
                               "/.config/hypr/scripts/quickshell/network/bluetooth_panel_logic.sh --toggle";
                    case "bluetooth_connect": {
                        let mac = ("" + (args.mac || "")).match(/^[0-9A-Fa-f:]{17}$/) ? args.mac : null;
                        return mac ? ("bash " + Quickshell.env("HOME") +
                               "/.config/hypr/scripts/quickshell/network/bluetooth_panel_logic.sh --connect '" + mac + "'") : null;
                    }
                    case "bluetooth_disconnect": {
                        let mac2 = ("" + (args.mac || "")).match(/^[0-9A-Fa-f:]{17}$/) ? args.mac : null;
                        return mac2 ? ("bash " + Quickshell.env("HOME") +
                               "/.config/hypr/scripts/quickshell/network/bluetooth_panel_logic.sh --disconnect '" + mac2 + "'") : null;
                    }
                    case "toggle_mute":
                        return "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
                    case "mic_mute":
                        return "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ " + (args.muted === false ? "0" : "1");
                    case "set_volume": {
                        let pct = Math.max(0, Math.min(100, parseInt(args.percent) || 0));
                        return "wpctl set-volume @DEFAULT_AUDIO_SINK@ " + pct + "%";
                    }
                    case "media_control": {
                        let a = pick(args.action, ["play-pause", "next", "previous", "pause", "play", "stop"]);
                        return a ? ("playerctl " + a) : null;
                    }
                    case "open_widget": {
                        let name = ("" + (args.name || "")).replace(/[^a-z]/g, "");
                        if (!name) return null;
                        return "bash " + Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh " +
                               (args.toggle ? "toggle" : "open") + " " + name;
                    }
                    case "open_url": {
                        let u = "" + (args.url || "");
                        if (!/^https:\/\/[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]+$/.test(u)) return null;
                        return "xdg-open '" + u.replace(/'/g, "") + "'";
                    }
                    case "open_mail": {
                        let tid = ("" + (args.thread_id || "")).match(/^[0-9A-Fa-f]{8,32}$/) ? args.thread_id : null;
                        let acct = ("" + (args.account || "")).match(/^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+$/) ? args.account : "";
                        return tid ? ("bash " + Quickshell.env("HOME") + "/.config/hypr/scripts/mira_toggle.sh open " +
                               tid + (acct ? " '" + acct + "'" : "")) : null;
                    }
                    case "autopilot_decide": {
                        let id = ("" + (args.id || "")).replace(/[^A-Za-z0-9_\-]/g, "");
                        let choice = pick(args.choice, ["send", "skip", "trust_send", "trust", "edit", "approve", "deny"]);
                        if (!id || !choice) return null;
                        let uid = ("" + (args.user_id || "")).replace(/[^0-9]/g, "");
                        let uname = ("" + (args.username || "")).replace(/[^A-Za-z0-9_.\-]/g, "");
                        return "bash " + Quickshell.env("HOME") +
                               "/.config/hypr/scripts/quickshell/claude/autopilot_decide.sh " +
                               id + " " + choice + " '" + uid + "' '" + uname + "'";
                    }
                    case "process_kill": {
                        let pid = ("" + (args.pid || "")).match(/^[0-9]+$/) ? args.pid : null;
                        if (pid) return "kill " + pid;
                        let pname = ("" + (args.name || "")).match(/^[A-Za-z0-9_.\-]+$/) ? args.name : null;
                        return pname ? ("pkill -f '" + pname + "'") : null;
                    }
                    default: return null;
                }
            }
            Process { id: actionExecProc; running: false }
            function runAction(cmd) {
                actionExecProc.command = ["bash", "-c", cmd];
                actionExecProc.running = false; actionExecProc.running = true;
            }

            // ---- raw-text local actions: copy_text/open_chat carry free-form text (an
            // OTP code, a drafted reply, a stacktrace) that must never be interpolated
            // into a shell string (see buildActionCmd's comment above) — passed as its
            // own argv element instead, same idiom as buildSecretCmdArgv.
            Process { id: copyTextProc; running: false }
            function copyText(text) {
                copyTextProc.command = ["wl-copy", "" + (text || "")];
                copyTextProc.running = false; copyTextProc.running = true;
            }
            Process { id: openChatProc; running: false }
            function openChat(text) {
                openChatProc.command = ["bash", "-c",
                    "printf 'claude:%s' \"$1\" > /tmp/qs_widget_state", "_", "" + (text || "")];
                openChatProc.running = false; openChatProc.running = true;
            }

            // ---- secret-block credential allowlist: deliberately separate from
            // buildActionCmd above. The typed value is passed as its own argv element
            // (never string-interpolated into the script) so it can't end up in a
            // process list, a log, or get mangled by shell metacharacters — and this
            // function only ever returns a fixed script template, never one built from
            // arbitrary input, so a card can't smuggle in an attacker-controlled command.
            function buildSecretCmdArgv(fnName, args) {
                args = args || {};
                switch (fnName) {
                    case "wifi_connect": {
                        let ssid = ("" + (args.ssid || "")).trim();
                        if (!ssid) return null;
                        return { script: "exec nmcli device wifi connect \"$1\" password \"$2\"", nonSecretArgs: [ssid] };
                    }
                    case "vpn_connect": {
                        let name = ("" + (args.name || "")).trim();
                        if (!name) return null;
                        return { script: "nmcli connection modify \"$1\" vpn.secrets.password \"$2\" >/dev/null 2>&1 && exec nmcli connection up \"$1\"", nonSecretArgs: [name] };
                    }
                    case "bluetooth_pair": {
                        let mac = ("" + (args.mac || "")).match(/^[0-9A-Fa-f:]{17}$/) ? args.mac : "";
                        if (!mac) return null;
                        return { script: "bluetoothctl <<BTEOF\nagent on\ndefault-agent\npair \"$1\"\n$2\nBTEOF", nonSecretArgs: [mac] };
                    }
                    default: return null;
                }
            }
            Process { id: secretExecProc; running: false }
            function runSecretAction(fnName, args, secretValue, onDone) {
                let built = cr.buildSecretCmdArgv(fnName, args);
                if (!built) { onDone(false, "unsupported action"); return; }
                let argv = ["bash", "-c", built.script, "_"].concat(built.nonSecretArgs).concat([secretValue]);
                secretExecProc.command = argv;
                secretExecProc.exited.connect(function handler(code) {
                    secretExecProc.exited.disconnect(handler);
                    onDone(code === 0, code === 0 ? "" : ("exit " + code));
                });
                secretExecProc.running = false; secretExecProc.running = true;
            }
            Process { id: mailboxProc; running: false }
            function mailboxNote(msg) {
                mailboxProc.command = ["python3", "-c",
                    "import sys,json,time,os\n" +
                    "p='/tmp/qs_claude_mailbox.json'\n" +
                    "m=json.load(open(p)) if os.path.exists(p) else []\n" +
                    "m.append({'id':int(time.time()*1000),'from':'card','to':'me','msg':sys.argv[1],'ts':int(time.time()),'read':False})\n" +
                    "json.dump(m[-100:], open(p,'w'))\n",
                    msg];
                mailboxProc.running = false; mailboxProc.running = true;
            }
            // item is either a plain string (old behaviour: click sends it as the next chat
            // message) or {label, icon?, action:{fn,args}} bound to a local action — those run
            // instantly client-side and only leave a passive mailbox note, no chat round-trip.
            function send(item) {
                let isObj = typeof item === "object" && item !== null;
                let label = isObj ? (item.label || "") : ("" + item);
                let act = isObj ? item.action : null;
                if (act && act.fn === "copy_text") {
                    cr.copyText((act.args || {}).text || "");
                    return;
                }
                if (act && act.fn === "open_chat") {
                    cr.openChat((act.args || {}).text || "");
                    return;
                }
                if (act && act.fn) {
                    let cmd = cr.buildActionCmd(act.fn, act.args || {});
                    if (cmd) {
                        cr.runAction(cmd);
                        cr.mailboxNote("Card \"" + (cr.spec.title || "") + "\": user clicked \"" + label +
                            "\" → ran " + act.fn + "(" + JSON.stringify(act.args || {}) + ")");
                        // approval / reauth cards are one-shot — collapse after the choice,
                        // then ask the host to drop the row so it never comes back on reopen.
                        // Approval cards almost never carry an explicit card_id (the model's
                        // show_card call for them typically omits it) — fall back to the
                        // card's own _sid, which is always present and stable across a
                        // daemon-stream replay, so suppression isn't silently skipped.
                        if (act.fn === "autopilot_decide") {
                            cr.dismissed = true;
                            cr.dismissRequested(cr.spec.card_id || cr.spec._sid || "");
                        }
                        return;
                    }
                }
                if (isObj && item.silent === true) { cr.sendSilent(item); return; }
                cr.sendPlain("Card \"" + (cr.spec.title || "") + "\": user chose \"" + label + "\"");
            }

            // ---- silent card interactions: a control flagged silent:true routes its click to
            // the chat agent as a HIDDEN turn — no user bubble, no agent prose. The agent acts
            // via tools (command / update_card / notify). The control shows a pending state
            // until the daemon writes an ack to /tmp/qs_card_acks, which we watch like a bus.
            property var pending: ({})
            property int pendingRev: 0
            property int _iidCtr: 0
            function ackStatus(iid) { return cr.pending[iid] || ""; }
            Process { id: silentWriter; running: false }
            function sendSilent(item) {
                let isObj = typeof item === "object" && item !== null;
                let label = isObj ? (item.label || "") : ("" + item);
                let val = (isObj && item.value !== undefined) ? (" (value: " + item.value + ")") : "";
                let id = "c" + Date.now() + "_" + (cr._iidCtr++);
                cr.pending[id] = "pending"; cr.pendingRev++;
                let payload = JSON.stringify({
                    text: "Card \"" + (cr.spec.title || "") + "\": user clicked \"" + label + "\"" + val,
                    silent: true, iid: id
                });
                silentWriter.command = ["bash", "-c", "printf '%s\\n' \"$1\" > /tmp/qs_claude_in", "_", payload];
                silentWriter.running = false; silentWriter.running = true;
                silentTimeout.restart();
                return id;
            }
            // safety net: if no ack arrives, fail any still-pending interaction so a control
            // never hangs in a spinner forever.
            Timer {
                id: silentTimeout; interval: 15000; repeat: false
                onTriggered: {
                    let changed = false;
                    for (let k in cr.pending) if (cr.pending[k] === "pending") { cr.pending[k] = "fail"; changed = true; }
                    if (changed) { cr.pendingRev++; ackClear.restart(); }
                }
            }
            function applyAcks(text) {
                let lines = ("" + text).trim().split("\n");
                let changed = false;
                for (let i = 0; i < lines.length; i++) {
                    let ln = lines[i].trim(); if (ln === "") continue;
                    let o; try { o = JSON.parse(ln); } catch (e) { continue; }
                    if (o && o.iid && cr.pending[o.iid] === "pending") {
                        cr.pending[o.iid] = (o.status === "fail") ? "fail" : "ok";
                        changed = true;
                    }
                }
                if (changed) { cr.pendingRev++; ackClear.restart(); }
            }
            // resolved badges (✓/✗) linger briefly, then the key is dropped so the control
            // returns to its normal look (update_card may already have changed it).
            Timer {
                id: ackClear; interval: 1400; repeat: false
                onTriggered: {
                    for (let k in cr.pending) if (cr.pending[k] !== "pending") delete cr.pending[k];
                    cr.pendingRev++;
                }
            }
            Process {
                id: ackReader; running: false
                command: ["bash", "-c", "tail -n 60 /tmp/qs_card_acks 2>/dev/null"]
                stdout: StdioCollector { onStreamFinished: cr.applyAcks(this.text) }
            }
            Process {
                id: ackWatcher; running: true
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "f=/tmp/qs_card_acks; touch \"$f\"; exec inotifywait -m -e close_write,modify,moved_to \"$f\" 2>/dev/null"]
                stdout: SplitParser { splitMarker: "\n"; onRead: (data) => { ackReader.running = false; ackReader.running = true; } }
            }
            Component {
                id: statusBadge
                Item {
                    property string st: "pending"
                    implicitWidth: cr.s(16); implicitHeight: cr.s(16)
                    Row {
                        anchors.centerIn: parent; spacing: cr.s(2); visible: parent.st === "pending"
                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                id: pendingDot
                                required property int index
                                width: cr.s(3); height: cr.s(3); radius: width / 2; color: cr.accent
                                SequentialAnimation on opacity {
                                    running: pendingDot.visible; loops: Animation.Infinite
                                    PauseAnimation { duration: index * 150 }
                                    NumberAnimation { to: 1.0; duration: 200 }
                                    NumberAnimation { to: 0.25; duration: 400 }
                                    PauseAnimation { duration: (2 - index) * 150 }
                                }
                            }
                        }
                    }
                    Text { anchors.centerIn: parent; visible: parent.st === "ok"; text: String.fromCharCode(0xf00c); font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(11); color: cr.green }
                    Text { anchors.centerIn: parent; visible: parent.st === "fail"; text: String.fromCharCode(0xf00d); font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(11); color: cr.red }
                }
            }
            readonly property var tileColors: [cr.mauve, cr.peach, cr.blue, cr.green, cr.red]
            property real _totalBlocksH: 0
            function updateTotalHeight() {
                var h = 0, n = 0;
                for (var i = 0; i < blocksRepeater.count; i++) {
                    var it = blocksRepeater.itemAt(i);
                    if (it) { h += it.height; n++; }
                }
                _totalBlocksH = h + s(12) * Math.max(0, n - 1);
            }
            // In the chat view the Loader sets cr.width AFTER blockWraps are created,
            // so the first Qt.callLater(updateTotalHeight) runs with width=0 (all heights
            // = s(10)). This timer fires once after layout settles and corrects the total.
            Timer { interval: 80; running: true; repeat: false; onTriggered: cr.updateTotalHeight() }
            implicitHeight: cr.dismissed ? 0 : (cr.compact ? chipRect.height : ccard.height)
            Behavior on implicitHeight { enabled: cr.dismissed; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            clip: cr.dismissed
            // expanded footprint regardless of compact state — pinned layout clamps with
            // this so a collapsed chip parked above/below the chat still reserves the room
            // its expanded form will need.
            readonly property real expandedH: ccard.height
            // smooth the compact<->expanded morph — standalone-only so this never fights
            // the live-streaming chat card's own growth, which needs to track each delta
            // immediately rather than ease toward a perpetually-moving target
            Behavior on implicitHeight { enabled: cr.standalone; NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

            // ---- block renderers: each reads modelData via parent.dBlock, same idiom as the
            // outer chat delegate's parent.dText/dLang/etc — keeps every block in cr's id scope.
            Component {
                id: rowsBlock
                Grid {
                    id: rg
                    property var bData: parent ? parent.dBlock : {}
                    width: cardCol.width
                    columns: 2
                    columnSpacing: cr.s(12); rowSpacing: cr.s(10)
                    Repeater {
                        model: rg.bData.items || []
                        delegate: Row {
                            id: rowItem
                            required property var modelData
                            required property int index
                            width: (cardCol.width - cr.s(12)) / 2
                            spacing: cr.s(8)
                            property string liveVal: modelData.value || ""
                            property color accentC: cr.tileColors[index % cr.tileColors.length]

                            // same live-binding idiom bars/gauges already use, generalized: a
                            // 'watch'-ed file refetches on inotify (event-driven, topbar-caliber)
                            // instead of a blind timer; 'metric'/'source' keep the timer fallback
                            // for stats with nothing to watch.
                            Process { id: rowBusStarter; running: false; command: ["python3", "-c", cr.metricsBusSpawnScript] }
                            Process {
                                id: rowLiveProc
                                command: rowItem.modelData.metric
                                    ? ["bash", "-c", "cat " + cr.metricsBusFile]
                                    : ["bash", "-c", rowItem.modelData.source || (rowItem.modelData.watch ? ("cat '" + rowItem.modelData.watch + "'") : "true")]
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        rowItem.liveVal = rowItem.modelData.metric
                                            ? cr.extractMetric(this.text, rowItem.modelData.metric)
                                            : this.text.trim();
                                    }
                                }
                            }
                            Timer {
                                interval: rowItem.modelData.interval_ms || 4000
                                running: !!(rowItem.modelData.source || rowItem.modelData.metric) && !rowItem.modelData.watch
                                repeat: true
                                triggeredOnStart: true
                                onTriggered: {
                                    if (rowItem.modelData.metric) { rowBusStarter.running = false; rowBusStarter.running = true; }
                                    rowLiveProc.running = false; rowLiveProc.running = true;
                                }
                            }
                            Process {
                                id: rowWatcher
                                running: !!rowItem.modelData.watch
                                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
                                    "f='" + (rowItem.modelData.watch || "") + "'; mkdir -p \"$(dirname \"$f\")\"; touch \"$f\"; " +
                                    "inotifywait -m -e close_write,create \"$f\" 2>/dev/null"]
                                stdout: SplitParser { splitMarker: "\n"; onRead: (data) => { rowLiveProc.running = false; rowLiveProc.running = true; } }
                            }
                            Component.onCompleted: if (rowItem.modelData.watch) { rowLiveProc.running = true; }

                            HoverHandler { id: rowHov }
                            Rectangle {
                                width: cr.s(30); height: cr.s(30); radius: cr.s(8)
                                anchors.verticalCenter: parent.verticalCenter
                                // matugen per-item tint instead of flat surface — the icon chip
                                // carries the row's identity color, brightens on hover.
                                color: Qt.rgba(rowItem.accentC.r, rowItem.accentC.g, rowItem.accentC.b, rowHov.hovered ? 0.26 : 0.15)
                                border.width: 1
                                border.color: Qt.rgba(rowItem.accentC.r, rowItem.accentC.g, rowItem.accentC.b, rowHov.hovered ? 0.5 : 0.25)
                                scale: cr.cardAnimations && rowHov.hovered ? 1.08 : 1.0
                                Behavior on color { ColorAnimation { duration: 130 } }
                                Behavior on border.color { ColorAnimation { duration: 130 } }
                                Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
                                Text { anchors.centerIn: parent; text: cr.resolveIcon(modelData.icon, modelData.label); font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(14); color: rowItem.accentC }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: cr.s(1)
                                Text { text: (modelData.label || "").toUpperCase(); font.family: "JetBrains Mono"; font.pixelSize: cr.s(9); font.weight: Font.Medium; font.letterSpacing: cr.s(0.5); color: cr.subtext0 }
                                Text { text: rowItem.liveVal; font.family: "JetBrains Mono"; font.pixelSize: cr.s(12); font.weight: Font.Bold; color: cr.text; elide: Text.ElideRight; width: cardCol.width / 2 - cr.s(46) }
                            }
                        }
                    }
                }
            }

            Component {
                id: gaugesBlock
                Row {
                    id: gr
                    property var bData: parent ? parent.dBlock : {}
                    width: cardCol.width
                    spacing: cr.s(10)
                    property int n: Math.max(1, (gr.bData.items || []).length)
                    property real tw: (cardCol.width - gr.spacing * (gr.n - 1)) / gr.n
                    Repeater {
                        model: gr.bData.items || []
                        delegate: Rectangle {
                            id: tile
                            required property var modelData
                            required property int index
                            property string liveVal: modelData.value || ""
                            property color tileColor: cr.semanticColor(tile.liveVal, tile.modelData, cr.tileColors[tile.index % cr.tileColors.length])
                            // a tile is "alerting" when its semantic color escalated to amber/red —
                            // that's what drives the breathing heartbeat glow
                            property bool alert: cr.cardAnimations && (Qt.colorEqual(tile.tileColor, "#f9e2af") || Qt.colorEqual(tile.tileColor, "#f38ba8"))
                            // chat shows dense ring-left + big-number bento (kills dead space);
                            // a pinned/standalone card keeps the airy centered ring it has room for
                            property bool bento: !cr.standalone
                            width: gr.tw
                            height: bento ? cr.s(62) : Math.min(gr.tw + cr.s(28), cr.s(130))
                            radius: cr.s(12)
                            clip: true
                            color: Qt.alpha(cr.surface0, 0.55)
                            border.width: 1; border.color: Qt.rgba(cr.surface1.r, cr.surface1.g, cr.surface1.b, 0.7)
                            Behavior on color { ColorAnimation { duration: 200 } }
                            // glass: a soft top-down sheen + a crisp 1px specular top edge so the
                            // tile reads as a lit surface, not a flat black hole
                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.05) }
                                    GradientStop { position: 0.5; color: "transparent" }
                                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.10) }
                                }
                            }
                            Rectangle {
                                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                anchors.leftMargin: cr.s(10); anchors.rightMargin: cr.s(10)
                                height: 1
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "transparent" }
                                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.12) }
                                    GradientStop { position: 1.0; color: "transparent" }
                                }
                            }

                            // heartbeat: a soft border glow that breathes in/out while the metric
                            // is in warn/crit — draws the eye to the tile that needs attention
                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                color: "transparent"
                                border.width: cr.s(1.5); border.color: tile.tileColor
                                visible: tile.alert
                                opacity: 0.0
                                SequentialAnimation on opacity {
                                    running: tile.alert; loops: Animation.Infinite
                                    NumberAnimation { to: 0.55; duration: 750; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 0.12; duration: 750; easing.type: Easing.InOutSine }
                                }
                            }
                            HoverHandler { id: tileHover }
                            // sheen sweep: a faint diagonal streak crosses the tile on hover
                            Rectangle {
                                visible: cr.cardAnimations
                                width: cr.s(40); height: parent.height * 2.2
                                y: -parent.height * 0.6
                                rotation: 18
                                x: tileHover.hovered ? parent.width + cr.s(40) : -cr.s(90)
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "transparent" }
                                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.10) }
                                    GradientStop { position: 1.0; color: "transparent" }
                                }
                                Behavior on x { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                            }

                            Process {
                                id: busStarter
                                running: false
                                command: ["python3", "-c", cr.metricsBusSpawnScript]
                            }
                            Process {
                                id: liveProc
                                command: tile.modelData.metric
                                    ? ["bash", "-c", "cat " + cr.metricsBusFile]
                                    : ["bash", "-c", tile.modelData.source || (tile.modelData.watch ? ("cat '" + tile.modelData.watch + "'") : "true")]
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        if (tile.modelData.metric) {
                                            tile.liveVal = cr.extractMetric(this.text, tile.modelData.metric);
                                        } else {
                                            tile.liveVal = this.text.trim();
                                        }
                                    }
                                }
                            }
                            Timer {
                                interval: tile.modelData.interval_ms || 4000
                                running: !!(tile.modelData.source || tile.modelData.metric) && !tile.modelData.watch
                                repeat: true
                                triggeredOnStart: true
                                onTriggered: {
                                    if (tile.modelData.metric) { busStarter.running = false; busStarter.running = true; }
                                    liveProc.running = false; liveProc.running = true;
                                }
                            }
                            Process {
                                id: gaugeWatcher
                                running: !!tile.modelData.watch
                                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
                                    "f='" + (tile.modelData.watch || "") + "'; mkdir -p \"$(dirname \"$f\")\"; touch \"$f\"; " +
                                    "inotifywait -m -e close_write,create,moved_to \"$f\" 2>/dev/null"]
                                stdout: SplitParser { splitMarker: "\n"; onRead: (data) => { liveProc.running = false; liveProc.running = true; } }
                            }
                            Component.onCompleted: if (tile.modelData.watch) liveProc.running = true;

                            // ===== CENTERED (pinned/standalone): airy ring with value inside =====
                            Item {
                                visible: !tile.bento
                                anchors.fill: parent
                                Item {
                                    id: ringSlot
                                    anchors.top: parent.top; anchors.topMargin: cr.s(10)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(gr.tw - cr.s(20), cr.s(64)); height: width
                                    Canvas {
                                        anchors.fill: parent
                                        property real frac: cr.progFrac(tile.liveVal)
                                        property color rc: tile.tileColor
                                        Behavior on frac { NumberAnimation { duration: cr.cardAnimations ? 750 : 0; easing.type: Easing.OutCubic } }
                                        Behavior on rc { ColorAnimation { duration: 200 } }
                                        onFracChanged: requestPaint()
                                        onRcChanged: requestPaint()
                                        onWidthChanged: requestPaint()
                                        onPaint: {
                                            var ctx = getContext("2d");
                                            ctx.reset();
                                            var cx = width / 2, cy = height / 2, r = Math.min(width, height) / 2 - cr.s(5);
                                            ctx.lineWidth = cr.s(6); ctx.lineCap = "round";
                                            ctx.strokeStyle = Qt.rgba(rc.r, rc.g, rc.b, 0.16);
                                            ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.stroke();
                                            ctx.strokeStyle = rc;
                                            ctx.beginPath();
                                            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + frac * 2 * Math.PI);
                                            ctx.stroke();
                                        }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        property real animVal: { let n = cr.parseNum(tile.liveVal); return isNaN(n) ? 0 : n }
                                        Behavior on animVal { NumberAnimation { duration: cr.cardAnimations ? 900 : 0; easing.type: Easing.OutCubic } }
                                        text: (cr.cardAnimations && !isNaN(cr.parseNum(tile.liveVal))) ? cr.formatNum(animVal, tile.liveVal) : tile.liveVal
                                        font.family: "JetBrains Mono"; font.pixelSize: cr.s(14); font.weight: Font.Bold
                                        color: cr.text
                                    }
                                }
                                Text {
                                    anchors.bottom: parent.bottom; anchors.bottomMargin: cr.s(10)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: ("" + (tile.modelData.label || "")).toUpperCase()
                                    font.family: "JetBrains Mono"; font.pixelSize: cr.s(9); font.weight: Font.Bold; font.letterSpacing: cr.s(1)
                                    color: cr.subtext0
                                }
                            }

                            // ===== BENTO (chat): small ring left, dominant KPI + label right =====
                            Row {
                                visible: tile.bento
                                anchors.fill: parent
                                anchors.leftMargin: cr.s(12); anchors.rightMargin: cr.s(12)
                                spacing: cr.s(12)
                                Item {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: cr.s(38); height: cr.s(38)
                                    Canvas {
                                        anchors.fill: parent
                                        property real frac: cr.progFrac(tile.liveVal)
                                        property color rc: tile.tileColor
                                        Behavior on frac { NumberAnimation { duration: cr.cardAnimations ? 750 : 0; easing.type: Easing.OutCubic } }
                                        Behavior on rc { ColorAnimation { duration: 200 } }
                                        onFracChanged: requestPaint()
                                        onRcChanged: requestPaint()
                                        onWidthChanged: requestPaint()
                                        onPaint: {
                                            var ctx = getContext("2d");
                                            ctx.reset();
                                            var cx = width / 2, cy = height / 2, r = Math.min(width, height) / 2 - cr.s(3);
                                            ctx.lineWidth = cr.s(4); ctx.lineCap = "round";
                                            ctx.strokeStyle = Qt.rgba(rc.r, rc.g, rc.b, 0.16);
                                            ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.stroke();
                                            ctx.strokeStyle = rc;
                                            ctx.beginPath();
                                            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + frac * 2 * Math.PI);
                                            ctx.stroke();
                                        }
                                    }
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: cr.s(1)
                                    Text {
                                        property real animVal: { let n = cr.parseNum(tile.liveVal); return isNaN(n) ? 0 : n }
                                        Behavior on animVal { NumberAnimation { duration: cr.cardAnimations ? 900 : 0; easing.type: Easing.OutCubic } }
                                        text: (cr.cardAnimations && !isNaN(cr.parseNum(tile.liveVal))) ? cr.formatNum(animVal, tile.liveVal) : tile.liveVal
                                        font.family: "JetBrains Mono"; font.pixelSize: cr.s(20); font.weight: Font.Bold
                                        color: cr.text
                                    }
                                    Text {
                                        text: ("" + (tile.modelData.label || "")).toUpperCase()
                                        font.family: "JetBrains Mono"; font.pixelSize: cr.s(9); font.weight: Font.Bold; font.letterSpacing: cr.s(1)
                                        color: cr.subtext0
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: barsBlock
                Column {
                    id: bb
                    property var bData: parent ? parent.dBlock : {}
                    width: cardCol.width
                    spacing: cr.s(10)
                    Repeater {
                        model: bb.bData.items || []
                        delegate: Row {
                            id: barRow
                            required property var modelData
                            required property int index
                            property string liveVal: modelData.value || ""
                            width: cardCol.width
                            spacing: cr.s(10)

                            Process {
                                id: barBusStarter
                                running: false
                                command: ["python3", "-c", cr.metricsBusSpawnScript]
                            }
                            Process {
                                id: barLiveProc
                                command: barRow.modelData.metric
                                    ? ["bash", "-c", "cat " + cr.metricsBusFile]
                                    : ["bash", "-c", barRow.modelData.source || (barRow.modelData.watch ? ("cat '" + barRow.modelData.watch + "'") : "true")]
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        if (barRow.modelData.metric) {
                                            barRow.liveVal = cr.extractMetric(this.text, barRow.modelData.metric);
                                        } else {
                                            barRow.liveVal = this.text.trim();
                                        }
                                    }
                                }
                            }
                            Timer {
                                interval: barRow.modelData.interval_ms || 4000
                                running: !!(barRow.modelData.source || barRow.modelData.metric) && !barRow.modelData.watch
                                repeat: true
                                triggeredOnStart: true
                                onTriggered: {
                                    if (barRow.modelData.metric) { barBusStarter.running = false; barBusStarter.running = true; }
                                    barLiveProc.running = false; barLiveProc.running = true;
                                }
                            }
                            Process {
                                id: barWatcher
                                running: !!barRow.modelData.watch
                                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
                                    "f='" + (barRow.modelData.watch || "") + "'; mkdir -p \"$(dirname \"$f\")\"; touch \"$f\"; " +
                                    "inotifywait -m -e close_write,create,moved_to \"$f\" 2>/dev/null"]
                                stdout: SplitParser { splitMarker: "\n"; onRead: (data) => { barLiveProc.running = false; barLiveProc.running = true; } }
                            }
                            Component.onCompleted: if (barRow.modelData.watch) barLiveProc.running = true;

                            property color barColor: cr.semanticColor(barRow.liveVal, barRow.modelData, cr.tileColors[index % cr.tileColors.length])
                            property int _gaps: (2 + (barLbl.visible ? 1 : 0) + (valPill.visible ? 1 : 0)) - 1
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: cr.resolveIcon(modelData.icon, modelData.label)
                                font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(15)
                                color: barRow.barColor
                                Behavior on color { ColorAnimation { duration: 200 } }
                                width: cr.s(18)
                            }
                            Text {
                                id: barLbl
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !!modelData.label
                                text: ("" + (modelData.label || "")).toUpperCase()
                                font.family: "JetBrains Mono"; font.pixelSize: cr.s(10); font.weight: Font.Bold; font.letterSpacing: cr.s(0.5)
                                color: cr.subtext0
                                elide: Text.ElideRight
                                width: visible ? cr.s(70) : 0
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: cardCol.width - cr.s(18)
                                    - (barLbl.visible ? barLbl.width : 0)
                                    - (valPill.visible ? valPill.width : 0)
                                    - barRow.spacing * barRow._gaps
                                height: cr.s(10); radius: cr.s(5)
                                color: Qt.rgba(cr.surface1.r, cr.surface1.g, cr.surface1.b, 0.7)
                                Rectangle {
                                    width: parent.width * cr.progFrac(barRow.liveVal)
                                    height: parent.height; radius: cr.s(5)
                                    color: barRow.barColor
                                    Behavior on width { NumberAnimation { duration: cr.cardAnimations ? 650 : 0; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                            }
                            Rectangle {
                                id: valPill
                                visible: barRow.liveVal !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                width: valTxt.implicitWidth + cr.s(14); height: cr.s(20); radius: cr.s(6)
                                color: Qt.rgba(barRow.barColor.r, barRow.barColor.g, barRow.barColor.b, 0.14)
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Text {
                                    id: valTxt
                                    anchors.centerIn: parent
                                    text: barRow.liveVal
                                    font.family: "JetBrains Mono"; font.pixelSize: cr.s(11); font.weight: Font.Bold
                                    color: barRow.barColor
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: pillsBlock
                Row {
                    id: pr
                    property var bData: parent ? parent.dBlock : {}
                    width: cardCol.width
                    spacing: cr.s(8)
                    property int n: Math.max(1, (pr.bData.items || []).length)
                    property real pw: (cardCol.width - pr.spacing * (pr.n - 1)) / pr.n
                    // optimistic local selection so action-bound pills (e.g. power profile)
                    // flip highlight instantly on click instead of waiting on a chat round-trip
                    property string localSel: pr.bData.selected || ""
                    Repeater {
                        model: pr.bData.items || []
                        delegate: Rectangle {
                            id: pillItem
                            required property var modelData
                            property bool isObj: typeof modelData === "object" && modelData !== null
                            property string mLabel: isObj ? (modelData.label || "") : ("" + modelData)
                            property bool sel: mLabel === pr.localSel
                            property string iid: ""
                            property string ackSt: iid === "" ? "" : (cr.pendingRev, cr.ackStatus(iid))
                            property bool isPending: ackSt === "pending"
                            width: pr.pw; height: cr.s(32)
                            radius: cr.s(8)
                            opacity: !cr.cOpen ? 0.5 : (isPending ? 0.7 : 1)
                            color: sel ? cr.accent
                                : (pMa.containsMouse ? Qt.alpha(cr.surface2, 0.9) : Qt.alpha(cr.surface1, 0.7))
                            border.width: 1
                            border.color: sel ? Qt.rgba(cr.accent.r, cr.accent.g, cr.accent.b, 0.0)
                                : (pMa.containsMouse ? Qt.rgba(cr.accent.r, cr.accent.g, cr.accent.b, 0.4) : Qt.alpha(cr.surface2, 0.0))
                            scale: !cr.cardAnimations ? 1.0 : (pMa.pressed ? 0.95 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }
                            // selected glow halo — the active pill lifts off the row
                            Rectangle {
                                anchors.fill: parent; anchors.margins: -cr.s(2); z: -1
                                radius: cr.s(10); color: "transparent"
                                visible: parent.sel && cr.cardDepth
                                border.width: cr.s(2)
                                border.color: Qt.rgba(cr.accent.r, cr.accent.g, cr.accent.b, 0.22)
                            }
                            Text {
                                anchors.centerIn: parent
                                text: mLabel
                                visible: pillItem.ackSt === ""
                                font.family: "JetBrains Mono"; font.pixelSize: cr.s(11); font.weight: Font.Bold
                                color: parent.sel ? cr.crust : (pMa.containsMouse ? cr.text : cr.subtext0)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            Loader {
                                anchors.centerIn: parent
                                active: pillItem.ackSt !== ""
                                sourceComponent: statusBadge
                                onLoaded: item.st = Qt.binding(() => pillItem.ackSt)
                            }
                            MouseArea {
                                id: pMa; anchors.fill: parent; hoverEnabled: true
                                enabled: cr.cOpen && !pillItem.isPending
                                onClicked: {
                                    pr.localSel = mLabel;
                                    if (pillItem.isObj && modelData.silent === true) pillItem.iid = cr.sendSilent(modelData);
                                    else cr.send(modelData);
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: buttonsBlock
                Flow {
                    id: btb
                    property var bData: parent ? parent.dBlock : {}
                    width: cardCol.width
                    spacing: cr.s(8)
                    Repeater {
                        model: btb.bData.items || []
                        delegate: Rectangle {
                            id: btnItem
                            required property var modelData
                            property bool isObj: typeof modelData === "object" && modelData !== null
                            // 'live' on an item replaces a frozen label like "Resume music" with
                            // one that tracks real state (e.g. playerctl status) — the same
                            // metric/source/watch idiom as everywhere else, applied to the label
                            // itself instead of a stat value.
                            property var liveSpec: isObj ? (modelData.live || null) : null
                            property string liveLabel: ""
                            property string mLabel: liveSpec && liveLabel !== "" ? liveLabel : (isObj ? (modelData.label || "") : ("" + modelData))
                            property string mIcon: isObj && modelData.icon ? cr.resolveIcon(modelData.icon, mLabel) : ""
                            property string iid: ""
                            property string ackSt: iid === "" ? "" : (cr.pendingRev, cr.ackStatus(iid))
                            property bool isPending: ackSt === "pending"

                            Process { id: btnBusStarter; running: false; command: ["python3", "-c", cr.metricsBusSpawnScript] }
                            Process {
                                id: btnLiveProc
                                command: btnItem.liveSpec && btnItem.liveSpec.metric
                                    ? ["bash", "-c", "cat " + cr.metricsBusFile]
                                    : ["bash", "-c", (btnItem.liveSpec && btnItem.liveSpec.source) || (btnItem.liveSpec && btnItem.liveSpec.watch ? ("cat '" + btnItem.liveSpec.watch + "'") : "true")]
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        btnItem.liveLabel = (btnItem.liveSpec && btnItem.liveSpec.metric)
                                            ? cr.extractMetric(this.text, btnItem.liveSpec.metric)
                                            : this.text.trim();
                                    }
                                }
                            }
                            Timer {
                                interval: (btnItem.liveSpec && btnItem.liveSpec.interval_ms) || 4000
                                running: !!btnItem.liveSpec && !btnItem.liveSpec.watch
                                repeat: true; triggeredOnStart: true
                                onTriggered: {
                                    if (btnItem.liveSpec && btnItem.liveSpec.metric) { btnBusStarter.running = false; btnBusStarter.running = true; }
                                    btnLiveProc.running = false; btnLiveProc.running = true;
                                }
                            }
                            Process {
                                id: btnWatcher
                                running: !!(btnItem.liveSpec && btnItem.liveSpec.watch)
                                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
                                    "f='" + ((btnItem.liveSpec && btnItem.liveSpec.watch) || "") + "'; mkdir -p \"$(dirname \"$f\")\"; touch \"$f\"; " +
                                    "inotifywait -m -e close_write,create \"$f\" 2>/dev/null"]
                                stdout: SplitParser { splitMarker: "\n"; onRead: (data) => { btnLiveProc.running = false; btnLiveProc.running = true; } }
                            }
                            Component.onCompleted: if (btnItem.liveSpec) btnLiveProc.running = true;

                            height: cr.s(30)
                            width: actRow.implicitWidth + cr.s(24)
                            radius: cr.s(8)
                            opacity: !cr.cOpen ? 0.4 : (btnItem.isPending ? 0.65 : 1)
                            color: actMa.containsMouse ? cr.accent : Qt.rgba(cr.accent.r, cr.accent.g, cr.accent.b, 0.16)
                            border.width: 1; border.color: Qt.rgba(cr.accent.r, cr.accent.g, cr.accent.b, 0.35)
                            scale: !cr.cardAnimations ? 1.0 : (actMa.pressed ? 0.94 : 1.0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }
                            // specular top edge — reads as glass, brightest while filled on hover
                            Rectangle {
                                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                anchors.topMargin: 1; anchors.leftMargin: cr.s(6); anchors.rightMargin: cr.s(6)
                                height: 1; visible: cr.cardAnimations
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "transparent" }
                                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, actMa.containsMouse ? 0.22 : 0.10) }
                                    GradientStop { position: 1.0; color: "transparent" }
                                }
                            }
                            Row {
                                id: actRow
                                anchors.centerIn: parent
                                spacing: cr.s(6)
                                opacity: btnItem.ackSt === "" ? 1 : 0
                                Text {
                                    visible: mIcon !== ""
                                    text: mIcon
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(12)
                                    color: actMa.containsMouse ? cr.crust : cr.accent
                                }
                                Text {
                                    text: mLabel
                                    font.family: "JetBrains Mono"; font.pixelSize: cr.s(12); font.weight: Font.Bold
                                    color: actMa.containsMouse ? cr.crust : cr.accent
                                }
                            }
                            Loader {
                                anchors.centerIn: parent
                                active: btnItem.ackSt !== ""
                                sourceComponent: statusBadge
                                onLoaded: item.st = Qt.binding(() => btnItem.ackSt)
                            }
                            MouseArea {
                                id: actMa; anchors.fill: parent; hoverEnabled: true
                                enabled: cr.cOpen && !btnItem.isPending
                                onClicked: {
                                    if (btnItem.isObj && modelData.silent === true) btnItem.iid = cr.sendSilent(modelData);
                                    else cr.send(modelData);
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: listBlock
                Column {
                    id: lb
                    property var bData: parent ? parent.dBlock : {}
                    width: cardCol.width
                    spacing: cr.s(6)
                    // block-level live source: a 'source'/'watch' on the list itself (not per
                    // item) re-derives the whole bullet set from one command's stdout, split on
                    // newlines — for things like a workspace/window list that change as a unit.
                    property var liveItems: lb.bData.items || []
                    Process { id: lbBusStarter; running: false; command: ["python3", "-c", cr.metricsBusSpawnScript] }
                    Process {
                        id: lbLiveProc
                        command: ["bash", "-c", lb.bData.source || (lb.bData.watch ? ("cat '" + lb.bData.watch + "'") : "true")]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                let t = this.text.trim();
                                lb.liveItems = t === "" ? [] : t.split("\n");
                            }
                        }
                    }
                    Timer {
                        interval: lb.bData.interval_ms || 4000
                        running: !!lb.bData.source && !lb.bData.watch
                        repeat: true; triggeredOnStart: true
                        onTriggered: { lbLiveProc.running = false; lbLiveProc.running = true; }
                    }
                    Process {
                        id: lbWatcher
                        running: !!lb.bData.watch
                        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
                            "f='" + (lb.bData.watch || "") + "'; mkdir -p \"$(dirname \"$f\")\"; touch \"$f\"; " +
                            "inotifywait -m -e close_write,create \"$f\" 2>/dev/null"]
                        stdout: SplitParser { splitMarker: "\n"; onRead: (data) => { lbLiveProc.running = false; lbLiveProc.running = true; } }
                    }
                    Component.onCompleted: if (lb.bData.watch || lb.bData.source) lbLiveProc.running = true;
                    Repeater {
                        model: lb.liveItems
                        delegate: Row {
                            required property var modelData
                            required property int index
                            width: lb.width
                            spacing: cr.s(8)
                            Rectangle {
                                width: cr.s(5); height: cr.s(5); radius: width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: cr.tileColors[index % cr.tileColors.length]
                            }
                            Text {
                                text: "" + modelData
                                font.family: "JetBrains Mono"; font.pixelSize: cr.s(12)
                                color: cr.text; wrapMode: Text.Wrap
                                width: lb.width - cr.s(20)
                            }
                        }
                    }
                }
            }

            // live agenda from the Google Calendar/Tasks schedule cache the calendar widget
            // already populates — events + tasks for today. Tasks are tickable inline.
            // spec: { kind:"agenda", filter:"all"|"tasks"|"events", max:N, header:true|false }
            Component {
                id: agendaBlock
                Column {
                    id: ag
                    property var bData: parent ? parent.dBlock : {}
                    width: cardCol.width
                    spacing: cr.s(6)
                    property string schedDir: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/calendar/schedule"
                    property string cacheFile: Quickshell.env("HOME") + "/.local/share/qs_schedule_cache.json"
                    property var sched: ({ "header": "Loading…", "lessons": [] })
                    property string filterMode: ag.bData.filter || cr.agendaDefaultFilter || "all"
                    property int maxItems: ag.bData.max || 0
                    property var items: {
                        let ls = (ag.sched && ag.sched.lessons) ? ag.sched.lessons : [];
                        let out = [];
                        for (let i = 0; i < ls.length; i++) {
                            let isT = (ls[i].time || "") === "Task";
                            if (ag.filterMode === "tasks" && !isT) continue;
                            if (ag.filterMode === "events" && isT) continue;
                            out.push(ls[i]);
                            if (ag.maxItems > 0 && out.length >= ag.maxItems) break;
                        }
                        return out;
                    }
                    onImplicitHeightChanged: Qt.callLater(cr.updateTotalHeight)

                    Process {
                        id: agProc
                        command: ["bash", ag.schedDir + "/schedule_manager.sh"]
                        stdout: StdioCollector { onStreamFinished: { try { ag.sched = JSON.parse(this.text.trim() || "{}"); } catch (e) {} } }
                    }
                    Process {
                        id: agWatcher
                        running: true
                        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "f='" + ag.cacheFile + "'; touch \"$f\"; exec inotifywait -m -e close_write,create,delete \"$f\" 2>/dev/null"]
                        stdout: SplitParser { splitMarker: "\n"; onRead: (data) => { agProc.running = false; agProc.running = true; } }
                    }
                    Timer { interval: 300000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { agProc.running = false; agProc.running = true; } }

                    Text {
                        visible: ag.bData.header !== false && (ag.sched && ag.sched.header || "") !== ""
                        text: (ag.sched && ag.sched.header) ? ag.sched.header : ""
                        font.family: "JetBrains Mono"; font.pixelSize: cr.s(11); font.weight: Font.Bold
                        color: cr.subtext0
                    }
                    Text {
                        visible: ag.items.length === 0
                        text: "Nothing scheduled"
                        font.family: "JetBrains Mono"; font.pixelSize: cr.s(12); color: cr.overlay0
                    }
                    Repeater {
                        model: ag.items
                        delegate: Rectangle {
                            id: agItem
                            required property var modelData
                            required property int index
                            property bool isTask: (modelData.time || "") === "Task"
                            width: ag.width
                            height: agRow.implicitHeight + cr.s(14)
                            radius: cr.s(8)
                            color: agItemMa.containsMouse
                                ? Qt.rgba(cr.surface1.r, cr.surface1.g, cr.surface1.b, 0.55)
                                : Qt.rgba(cr.surface0.r, cr.surface0.g, cr.surface0.b, 0.5)
                            border.width: 1
                            border.color: Qt.rgba(cr.surface1.r, cr.surface1.g, cr.surface1.b, 0.6)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            // staggered entrance
                            opacity: 0
                            transform: Translate { id: agTr; y: cr.s(6) }
                            Component.onCompleted: agIn.start()
                            ParallelAnimation {
                                id: agIn
                                NumberAnimation { target: agItem; property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutQuad }
                                NumberAnimation { target: agTr; property: "y"; from: cr.s(6); to: 0; duration: 320; easing.type: Easing.OutExpo }
                                PauseAnimation { duration: Math.min(agItem.index * 45, 270) }
                            }
                            HoverHandler { }
                            MouseArea { id: agItemMa; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

                            Row {
                                id: agRow
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: cr.s(10); anchors.rightMargin: cr.s(10)
                                spacing: cr.s(10)
                                Item {
                                    width: cr.s(18); height: cr.s(18)
                                    anchors.verticalCenter: parent.verticalCenter
                                    Rectangle {
                                        visible: agItem.isTask
                                        anchors.fill: parent; radius: cr.s(5)
                                        color: "transparent"; border.width: Math.max(1, cr.s(2)); border.color: cr.green
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (!agItem.modelData.taskId) return;
                                                Quickshell.execDetached(["bash", ag.schedDir + "/toggle_task.sh", agItem.modelData.taskId, agItem.modelData.tasklistId]);
                                            }
                                        }
                                    }
                                    Rectangle {
                                        visible: !agItem.isTask
                                        width: cr.s(8); height: cr.s(8); radius: width / 2
                                        anchors.centerIn: parent
                                        color: cr.blue
                                    }
                                }
                                Column {
                                    width: agRow.width - cr.s(28)
                                    spacing: cr.s(2)
                                    Text {
                                        text: agItem.modelData.subject || ""
                                        font.family: "JetBrains Mono"; font.pixelSize: cr.s(12); font.weight: Font.Bold
                                        color: cr.text; elide: Text.ElideRight; width: parent.width
                                        maximumLineCount: 2; wrapMode: Text.Wrap
                                    }
                                    Text {
                                        visible: (agItem.modelData.time || "") !== ""
                                        text: (agItem.modelData.time || "") + (agItem.modelData.room ? ("  ·  " + agItem.modelData.room) : "")
                                        font.family: "JetBrains Mono"; font.pixelSize: cr.s(10)
                                        color: cr.subtext0
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: textBlock
                Text {
                    id: tb
                    property var bData: parent ? parent.dBlock : {}
                    property string liveText: tb.bData.text || ""
                    width: cardCol.width
                    text: tb.liveText
                    Process { id: tbBusStarter; running: false; command: ["python3", "-c", cr.metricsBusSpawnScript] }
                    Process {
                        id: tbLiveProc
                        command: ["bash", "-c", tb.bData.source || (tb.bData.watch ? ("cat '" + tb.bData.watch + "'") : "true")]
                        stdout: StdioCollector { onStreamFinished: tb.liveText = this.text.trim() }
                    }
                    Timer {
                        interval: tb.bData.interval_ms || 4000
                        running: !!tb.bData.source && !tb.bData.watch
                        repeat: true; triggeredOnStart: true
                        onTriggered: { tbLiveProc.running = false; tbLiveProc.running = true; }
                    }
                    Process {
                        id: tbWatcher
                        running: !!tb.bData.watch
                        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
                            "f='" + (tb.bData.watch || "") + "'; mkdir -p \"$(dirname \"$f\")\"; touch \"$f\"; " +
                            "inotifywait -m -e close_write,create \"$f\" 2>/dev/null"]
                        stdout: SplitParser { splitMarker: "\n"; onRead: (data) => { tbLiveProc.running = false; tbLiveProc.running = true; } }
                    }
                    Component.onCompleted: if (tb.bData.watch || tb.bData.source) tbLiveProc.running = true;
                    font.family: "JetBrains Mono"; font.pixelSize: cr.s(12)
                    color: cr.text; wrapMode: Text.Wrap
                }
            }

            // table — static: {kind:'table', headers:['A','B'], rows:[['1','2']]}
            //         live:   {kind:'table', source:'<cmd>', interval_ms?} where the cmd
            //                 prints JSON {"headers":[...],"rows":[[...]]} or just [[...]]
            Component {
                id: tableBlock
                Column {
                    id: tbl
                    property var bData: parent ? parent.dBlock : {}
                    property var liveHdrs: []
                    property var liveRws: []
                    property var hdrs: (tbl.liveHdrs && tbl.liveHdrs.length) ? tbl.liveHdrs : (tbl.bData.headers || [])
                    property var rws: (tbl.liveRws && tbl.liveRws.length) ? tbl.liveRws : (tbl.bData.rows || [])
                    // single source of truth for column count → every cell uses the same width
                    property int ncols: Math.max(tbl.hdrs.length,
                                                 (tbl.rws.length && Array.isArray(tbl.rws[0])) ? tbl.rws[0].length : 1, 1)
                    property real colW: tbl.width / tbl.ncols
                    width: cardCol.width
                    spacing: cr.s(1)
                    // watch a file, OR poll a source command; default to live when either is set
                    Process {
                        id: tblProc
                        command: ["bash", "-c", tbl.bData.source || (tbl.bData.watch ? ("cat '" + tbl.bData.watch + "'") : "true")]
                        stdout: StdioCollector { onStreamFinished: {
                            try {
                                let d = JSON.parse(this.text.trim());
                                if (Array.isArray(d)) { tbl.liveRws = d; }
                                else { if (d.headers) tbl.liveHdrs = d.headers; if (d.rows) tbl.liveRws = d.rows; }
                            } catch (e) { /* keep last good */ }
                        } }
                    }
                    Timer {
                        interval: tbl.bData.interval_ms || 3000
                        running: !!tbl.bData.source && !tbl.bData.watch
                        repeat: true; triggeredOnStart: true
                        onTriggered: { tblProc.running = false; tblProc.running = true; }
                    }
                    Process {
                        id: tblWatcher
                        running: !!tbl.bData.watch
                        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
                            "f='" + (tbl.bData.watch || "") + "'; mkdir -p \"$(dirname \"$f\")\"; touch \"$f\"; " +
                            "inotifywait -m -e close_write,create \"$f\" 2>/dev/null"]
                        stdout: SplitParser { splitMarker: "\n"; onRead: (data) => { tblProc.running = false; tblProc.running = true; } }
                    }
                    Row {
                        visible: tbl.hdrs.length > 0
                        width: parent.width
                        Repeater {
                            model: tbl.hdrs
                            delegate: Text {
                                required property var modelData
                                width: tbl.colW
                                text: modelData
                                font.family: "JetBrains Mono"; font.pixelSize: cr.s(11); font.weight: Font.Bold
                                color: cr.subtext0; elide: Text.ElideRight
                            }
                        }
                    }
                    Rectangle { visible: tbl.hdrs.length > 0; width: parent.width; height: 1; color: Qt.alpha(cr.surface2, 0.6) }
                    // keyed model so rows that change position animate (move/displaced)
                    // instead of snapping. Key = first cell (e.g. PID).
                    ListModel { id: rowModel }
                    onRwsChanged: tbl.syncRows()
                    Component.onCompleted: {
    if (tbl.bData.source || tbl.bData.watch) tblProc.running = true;
    tbl.syncRows();
}
                    function syncRows() {
                        let rows = tbl.rws || [];
                        // remove rows no longer present (by key)
                        let keys = rows.map(function(r) { return Array.isArray(r) ? ("" + r[0]) : ("" + r); });
                        for (let i = rowModel.count - 1; i >= 0; i--) {
                            if (keys.indexOf(rowModel.get(i).key) < 0) rowModel.remove(i);
                        }
                        // place each row at its target index, moving existing or inserting new
                        for (let t = 0; t < rows.length; t++) {
                            let r = rows[t];
                            let key = Array.isArray(r) ? ("" + r[0]) : ("" + r);
                            let cells = JSON.stringify(Array.isArray(r) ? r : [r]);
                            let cur = -1;
                            for (let j = 0; j < rowModel.count; j++) { if (rowModel.get(j).key === key) { cur = j; break; } }
                            if (cur < 0) {
                                rowModel.insert(t, { key: key, cells: cells });
                            } else {
                                if (cur !== t) rowModel.move(cur, t, 1);
                                if (rowModel.get(t).cells !== cells) rowModel.setProperty(t, "cells", cells);
                            }
                        }
                    }
                    ListView {
                        id: rowView
                        width: parent.width
                        height: rowModel.count * cr.s(22)
                        interactive: false
                        model: rowModel
                        move: Transition { NumberAnimation { properties: "y"; duration: 350; easing.type: Easing.OutCubic } }
                        displaced: Transition { NumberAnimation { properties: "y"; duration: 350; easing.type: Easing.OutCubic } }
                        delegate: Item {
                            id: rowItem
                            required property string cells
                            required property int index
                            width: rowView.width
                            height: cr.s(22)
                            property var cellArr: { try { return JSON.parse(cells); } catch (e) { return []; } }
                            // brief accent flash when this row's values change
                            property real flash: 0
                            onCellsChanged: { flash = 1; flashAnim.restart(); }
                            NumberAnimation { id: flashAnim; target: rowItem; property: "flash"; from: 1; to: 0; duration: 600; easing.type: Easing.OutCubic }
                            Rectangle {
                                anchors.fill: parent
                                color: (index % 2 === 1) ? Qt.alpha(cr.surface1, 0.35) : "transparent"
                                radius: cr.s(3)
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: cr.s(3)
                                color: Qt.alpha(cr.blue, 0.06 * rowItem.flash)
                            }
                            Row {
                                anchors.fill: parent
                                Repeater {
                                    model: rowItem.cellArr
                                    delegate: Text {
                                        required property var modelData
                                        width: tbl.colW
                                        height: cr.s(22)
                                        verticalAlignment: Text.AlignVCenter
                                        text: modelData === undefined || modelData === null ? "" : ("" + modelData)
                                        font.family: "JetBrains Mono"; font.pixelSize: cr.s(11)
                                        color: cr.text; elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // sparkline — {kind:'sparkline', label, values:[..], source?, watch?, interval_ms?}
            Component {
                id: sparklineBlock
                Column {
                    id: spk
                    property var bData: parent ? parent.dBlock : {}
                    property var vals: spk.bData.values || []
                    width: cardCol.width
                    spacing: cr.s(4)
                    property int maxPoints: spk.bData.max_points || 40
                    // persistence: rolling trend survives reopening the widget
                    property string persistKey: ("" + (cr.spec.card_id || "card") + "_" + (spk.bData.label || "spk")).replace(/[^A-Za-z0-9_]/g, "_")
                    property string persistFile: "/tmp/qs_sparkline_" + persistKey + ".json"
                    // animation: each new point scrolls in from the right
                    property real animOffset: 0
                    NumberAnimation { id: spkAnim; target: spk; property: "animOffset"; from: 1; to: 0; duration: 450; easing.type: Easing.OutCubic; onStopped: spkCanvas.requestPaint() }
                    onAnimOffsetChanged: spkCanvas.requestPaint()
                    // eased vertical range — snapping min/max to the data every tick makes the
                    // whole line jump as each new point lands. Glide the displayed range toward
                    // the target instead so the curve breathes instead of bumping.
                    property real dispMn: 0
                    property real dispMx: 1
                    property bool rangeInit: false
                    Behavior on dispMn { enabled: spk.rangeInit; NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }
                    Behavior on dispMx { enabled: spk.rangeInit; NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }
                    function updateRange() {
                        let v = spk.vals;
                        if (!v || !v.length) return;
                        let mn = Math.min.apply(null, v), mx = Math.max.apply(null, v);
                        if (mx - mn < 5) { let c = (mx + mn) / 2; mn = c - 3; mx = c + 3; }
                        if (!spk.rangeInit) { spk.dispMn = mn; spk.dispMx = mx; spk.rangeInit = true; }
                        else { spk.dispMn = mn; spk.dispMx = mx; }
                    }
                    onDispMnChanged: spkCanvas.requestPaint()
                    onDispMxChanged: spkCanvas.requestPaint()
                    function parseVals(s) {
                        let out = [];
                        let parts = ("" + s).replace(/[^0-9.\s,+-]/g, " ").split(/[\s,]+/);
                        for (let i = 0; i < parts.length; i++) { let n = parseFloat(parts[i]); if (!isNaN(n)) out.push(n); }
                        return out;
                    }
                    function persist() {
                        let b64 = Qt.btoa(JSON.stringify(spk.vals));
                        spkSaver.command = ["bash", "-c", "echo '" + b64 + "' | base64 -d > '" + spk.persistFile + "'"];
                        spkSaver.running = false; spkSaver.running = true;
                    }
                    Process { id: spkSaver; running: false }
                    // metric:'cpu'|'mem'|'temp'|'battery'|'volume' auto-reads the shared
                    // metrics bus, so 'a cpu sparkline' needs no hand-written source.
                    property string effSource: spk.bData.source
                        || (spk.bData.metric ? ("jq -r '." + spk.bData.metric + "' '" + cr.metricsBusFile + "' 2>/dev/null") : "")
                    Process { id: spkBusStarter; running: false; command: ["python3", "-c", cr.metricsBusSpawnScript] }
                    Process {
                        id: spkLoader
                        command: ["bash", "-c", "cat '" + spk.persistFile + "' 2>/dev/null || echo '[]'"]
                        stdout: StdioCollector { onStreamFinished: {
                            try { let saved = JSON.parse(this.text.trim() || "[]");
                                  if (Array.isArray(saved) && saved.length && !(spk.bData.values && spk.bData.values.length)) {
                                      spk.vals = saved; spkCanvas.requestPaint();
                                  } } catch (e) {}
                        } }
                    }
                    Process {
                        id: spkProc
                        command: ["bash", "-c", spk.effSource || (spk.bData.watch ? ("cat '" + spk.bData.watch + "'") : "true")]
                        stdout: StdioCollector { onStreamFinished: {
                            let v = spk.parseVals(this.text.trim());
                            if (!v.length) return;
                            if (v.length === 1) {
                                // single live reading → accumulate into a rolling trend
                                let arr = spk.vals.slice();
                                arr.push(v[0]);
                                if (arr.length > spk.maxPoints) arr = arr.slice(arr.length - spk.maxPoints);
                                spk.vals = arr;
                                spkAnim.restart();   // scroll the new point in
                            } else {
                                spk.vals = v; // full series each poll
                            }
                            spk.updateRange();
                            spk.persist();
                            spkCanvas.requestPaint();
                        } }
                    }
                    Timer {
                        interval: spk.bData.interval_ms || (spk.bData.metric ? 2000 : 4000)
                        running: !!spk.effSource && !spk.bData.watch
                        repeat: true; triggeredOnStart: true
                        onTriggered: { spkProc.running = false; spkProc.running = true; }
                    }
                    Component.onCompleted: {
                        spkLoader.running = true;
                        if (spk.bData.metric) spkBusStarter.running = true;
                    }
                    Row {
                        visible: !!spk.bData.label
                        width: parent.width
                        Text {
                            text: spk.bData.label || ""
                            font.family: "JetBrains Mono"; font.pixelSize: cr.s(11); color: cr.subtext0
                            width: parent.width - latestTxt.width; elide: Text.ElideRight
                        }
                        Text {
                            id: latestTxt
                            text: spk.vals.length ? ("" + spk.vals[spk.vals.length - 1]) : ""
                            font.family: "JetBrains Mono"; font.pixelSize: cr.s(11); font.weight: Font.Bold; color: cr.blue
                        }
                    }
                    Canvas {
                        id: spkCanvas
                        width: parent.width; height: cr.s(34)
                        onPaint: {
                            let ctx = getContext("2d");
                            ctx.reset();
                            let v = spk.vals;
                            if (!v || !v.length) return;
                            if (v.length === 1) v = [v[0], v[0]]; // single point → flat line
                            // eased range (dispMn/dispMx glide toward the data range) — no snap
                            let mn = spk.dispMn, mx = spk.dispMx;
                            let rng = (mx - mn) || 1;
                            let pad = cr.s(2);
                            let w = width - pad * 2, h = height - pad * 2;
                            let seg = w / (v.length - 1);
                            // animOffset (1→0) shifts the whole line right by one segment as the
                            // newest point scrolls in, giving a smooth ticker feel.
                            let dx = spk.animOffset * seg;
                            // precompute points, then stroke as a smoothed quadratic curve so the
                            // line glides between samples instead of zig-zagging on noisy data
                            let pts = [];
                            for (let i = 0; i < v.length; i++) {
                                pts.push({ x: pad + i * seg - dx,
                                           y: pad + h - ((v[i] - mn) / rng) * h });
                            }
                            ctx.save();
                            ctx.beginPath();
                            ctx.rect(pad, 0, w, height);
                            ctx.clip();
                            ctx.beginPath();
                            ctx.moveTo(pts[0].x, pts[0].y);
                            for (let i = 1; i < pts.length; i++) {
                                let xc = (pts[i - 1].x + pts[i].x) / 2;
                                let yc = (pts[i - 1].y + pts[i].y) / 2;
                                ctx.quadraticCurveTo(pts[i - 1].x, pts[i - 1].y, xc, yc);
                            }
                            ctx.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y);
                            ctx.strokeStyle = cr.blue;
                            ctx.lineWidth = cr.s(1.5);
                            ctx.lineJoin = "round";
                            ctx.lineCap = "round";
                            ctx.stroke();
                            // soft fill under the line
                            ctx.lineTo(pts[pts.length - 1].x, pad + h);
                            ctx.lineTo(pts[0].x, pad + h);
                            ctx.closePath();
                            ctx.fillStyle = Qt.alpha(cr.blue, 0.12);
                            ctx.fill();
                            ctx.restore();
                        }
                        Component.onCompleted: requestPaint()
                        onWidthChanged: requestPaint()
                    }
                }
            }

            Component {
                id: secretBlock
                Column {
                    id: sb
                    property var bData: parent ? parent.dBlock : {}
                    // locks only on success — failed submissions keep the input live for retry
                    property bool done: false
                    property bool ok: false
                    property string resultMsg: ""
                    property bool pending: false
                    width: cardCol.width
                    spacing: cr.s(8)

                    Text {
                        text: sb.bData.prompt || "Enter password"
                        font.family: "JetBrains Mono"; font.pixelSize: cr.s(12); font.weight: Font.Bold
                        color: cr.text
                    }

                    Rectangle {
                        visible: !sb.done
                        width: parent.width; height: cr.s(34)
                        radius: cr.s(8)
                        color: Qt.alpha(cr.surface0, 0.6)
                        border.width: 1; border.color: cr.surface1
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: cr.s(10); anchors.rightMargin: cr.s(6)
                            spacing: cr.s(6)
                            TextField {
                                id: secretInput
                                width: parent.width - secretSubmitBtn.width - cr.s(6)
                                height: parent.height
                                background: Item {}
                                echoMode: TextInput.Password
                                color: cr.text
                                font.family: "JetBrains Mono"; font.pixelSize: cr.s(12)
                                placeholderText: "Password…"
                                placeholderTextColor: cr.subtext0
                                verticalAlignment: TextInput.AlignVCenter
                                Keys.onReturnPressed: sb.submit()
                            }
                            Rectangle {
                                id: secretSubmitBtn
                                width: cr.s(22); height: cr.s(22); radius: cr.s(6)
                                anchors.verticalCenter: parent.verticalCenter
                                color: secretSubmitMa.containsMouse ? cr.surface2 : "transparent"
                                Text {
                                    anchors.centerIn: parent; text: String.fromCharCode(0xf00c)
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(10); color: cr.green
                                }
                                MouseArea { id: secretSubmitMa; anchors.fill: parent; hoverEnabled: true; onClicked: sb.submit() }
                            }
                        }
                    }

                    Rectangle {
                        visible: sb.done
                        width: parent.width; height: cr.s(34)
                        radius: cr.s(8)
                        color: Qt.alpha(cr.green, 0.12)
                        border.width: 1; border.color: Qt.alpha(cr.green, 0.4)
                        Row {
                            anchors.centerIn: parent
                            spacing: cr.s(6)
                            Text {
                                text: String.fromCharCode(0xf00c)
                                font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(11)
                                color: cr.green
                            }
                            Text {
                                text: sb.bData.success_label || "Connected"
                                font.family: "JetBrains Mono"; font.pixelSize: cr.s(11); font.weight: Font.Bold
                                color: cr.text
                            }
                        }
                    }

                    Rectangle {
                        visible: !sb.done && !sb.pending && sb.resultMsg !== ""
                        width: parent.width; height: cr.s(28)
                        radius: cr.s(6)
                        color: Qt.alpha(cr.red, 0.10)
                        border.width: 1; border.color: Qt.alpha(cr.red, 0.35)
                        Row {
                            anchors.centerIn: parent
                            spacing: cr.s(6)
                            Text {
                                text: String.fromCharCode(0xf00d)
                                font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(10)
                                color: cr.red
                            }
                            Text {
                                text: "Failed" + (sb.resultMsg ? " (" + sb.resultMsg + ")" : "") + " — try again"
                                font.family: "JetBrains Mono"; font.pixelSize: cr.s(10)
                                color: cr.subtext0
                            }
                        }
                    }

                    function submit() {
                        if (sb.done || sb.pending || secretInput.text === "") return;
                        sb.pending = true; sb.resultMsg = "";
                        let act = sb.bData.action || {};
                        let val = secretInput.text;
                        secretInput.text = "";
                        // never logged, never put back on cr.spec, never sent anywhere but the
                        // local command itself — see runSecretAction's argv-isolation comment
                        cr.runSecretAction(act.fn, act.args || {}, val, function(success, msg) {
                            sb.pending = false;
                            if (success) { sb.ok = true; sb.done = true; }
                            else { sb.resultMsg = msg; }
                        });
                    }
                }
            }

            Component {
                id: dropdownBlock
                Item {
                    id: dd
                    property var bData: parent ? parent.dBlock : {}
                    property string selected: bData.selected || ""
                    property bool expanded: false
                    property string iid: ""
                    property string ackSt: iid === "" ? "" : (cr.pendingRev, cr.ackStatus(iid))
                    property bool isPending: ackSt === "pending"
                    property real listH: Math.min(ddCol.implicitHeight + cr.s(4), cr.s(190))
                    property bool fitsInCard: false
                    width: cardCol.width
                    // overlay mode (fitsInCard): keep header height only so card doesn't grow;
                    // ddList renders over sibling blocks via z-index instead.
                    implicitHeight: cr.s(34) + (expanded && !fitsInCard ? cr.s(4) + listH : 0)
                    height: implicitHeight
                    onImplicitHeightChanged: Qt.callLater(cr.updateTotalHeight)
                    onExpandedChanged: {
                        if (expanded) {
                            var pt = dd.mapToItem(ccard, 0, cr.s(38) + listH)
                            fitsInCard = pt.y <= ccard.height - cr.s(4)
                            if (!fitsInCard) cr.dropdownExpandH = listH + cr.s(4)
                        } else {
                            fitsInCard = false
                            cr.dropdownExpandH = 0
                        }
                    }

                    Rectangle {
                        id: ddHeader
                        width: parent.width; height: cr.s(34)
                        radius: cr.s(8)
                        color: ddHdrMa.containsMouse ? Qt.alpha(cr.surface1, 0.7) : Qt.alpha(cr.surface0, 0.6)
                        border.width: 1
                        border.color: dd.expanded ? Qt.rgba(cr.accent.r, cr.accent.g, cr.accent.b, 0.45) : cr.surface1
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }
                        Rectangle {
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                            anchors.topMargin: 1; anchors.leftMargin: cr.s(8); anchors.rightMargin: cr.s(8)
                            height: 1; visible: cr.cardAnimations
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.08) }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: cr.s(10); anchors.rightMargin: cr.s(8)
                            Text {
                                width: parent.width - cr.s(20); height: parent.height
                                text: dd.selected !== "" ? dd.selected : (dd.bData.placeholder || "Select…")
                                font.family: "JetBrains Mono"; font.pixelSize: cr.s(12)
                                color: dd.selected !== "" ? cr.text : cr.subtext0
                                verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                            }
                            Text {
                                visible: dd.ackSt === ""
                                height: parent.height; width: cr.s(18)
                                text: String.fromCharCode(dd.expanded ? 0xf077 : 0xf078)
                                font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(9)
                                color: cr.subtext0; verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Loader {
                                width: cr.s(18); height: parent.height
                                active: dd.ackSt !== ""
                                sourceComponent: statusBadge
                                onLoaded: item.st = Qt.binding(() => dd.ackSt)
                            }
                        }
                        MouseArea { id: ddHdrMa; anchors.fill: parent; hoverEnabled: true; enabled: !dd.isPending; onClicked: dd.expanded = !dd.expanded }
                    }

                    Rectangle {
                        id: ddList
                        visible: dd.expanded
                        y: cr.s(38)
                        z: dd.fitsInCard ? 200 : 0
                        width: parent.width
                        height: dd.listH
                        clip: true
                        radius: cr.s(8)
                        color: Qt.alpha(cr.surface0, 0.95)
                        border.width: 1; border.color: Qt.rgba(cr.accent.r, cr.accent.g, cr.accent.b, 0.25)

                        Flickable {
                            anchors.fill: parent; anchors.margins: cr.s(2)
                            contentHeight: ddCol.implicitHeight; clip: true

                            Column {
                                id: ddCol
                                width: parent.width
                                Repeater {
                                    model: dd.bData.items || []
                                    delegate: Rectangle {
                                        required property var modelData
                                        property bool isObj: typeof modelData === "object" && modelData !== null
                                        property string itemLabel: isObj ? (modelData.label || "") : ("" + modelData)
                                        property bool isSel: dd.selected === itemLabel
                                        width: ddCol.width; height: cr.s(32)
                                        color: ddOptMa.containsMouse ? Qt.alpha(cr.surface1, 0.7) : (isSel ? Qt.rgba(cr.accent.r, cr.accent.g, cr.accent.b, 0.13) : "transparent")
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                        Row {
                                            anchors.fill: parent; anchors.leftMargin: cr.s(10); spacing: cr.s(6)
                                            Text {
                                                visible: isSel; height: parent.height; width: cr.s(12)
                                                text: String.fromCharCode(0xf00c)
                                                font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(9)
                                                color: cr.accent; verticalAlignment: Text.AlignVCenter
                                            }
                                            Text {
                                                height: parent.height; text: itemLabel
                                                font.family: "JetBrains Mono"; font.pixelSize: cr.s(12)
                                                font.weight: isSel ? Font.Bold : Font.Normal
                                                color: isSel ? cr.accent : cr.text; verticalAlignment: Text.AlignVCenter
                                            }
                                        }
                                        MouseArea {
                                            id: ddOptMa; anchors.fill: parent; hoverEnabled: true
                                            onClicked: {
                                                dd.selected = itemLabel; dd.expanded = false;
                                                if (isObj && modelData.silent === true) dd.iid = cr.sendSilent(modelData);
                                                else cr.send(modelData);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: iconbuttonsBlock
                Item {
                    id: ib
                    property var bData: parent ? parent.dBlock : {}
                    property int ibCols: bData.columns || 4
                    property int ibCount: (bData.items || []).length
                    property int ibRows: ibCols > 0 ? Math.ceil(ibCount / ibCols) : 1
                    property real btnW: ibCols > 0 && width > 0 ? Math.max(0, (width - cr.s(8) * (ibCols - 1)) / ibCols) : cr.s(72)
                    property real btnH: Math.min(btnW > 0 ? btnW : cr.s(72), cr.s(72))
                    width: cardCol.width
                    implicitHeight: ibRows > 0 ? ibRows * btnH + (ibRows - 1) * cr.s(8) : 0
                    height: implicitHeight
                    Flow {
                        anchors.fill: parent
                        spacing: cr.s(8)
                        Repeater {
                            model: ib.bData.items || []
                            delegate: Rectangle {
                                id: ibBtn
                                required property var modelData
                                required property int index
                                property bool isObj: typeof modelData === "object" && modelData !== null
                                property string mIcon: isObj ? cr.resolveIcon(modelData.icon || "", modelData.label || "") : cr.resolveIcon("", "" + modelData)
                                property string mLabel: isObj ? (modelData.label || "") : ("" + modelData)
                                // per-button matugen identity (overridable via item.color name) so a
                                // row of actions reads as distinct buttons, not one grey grid.
                                property color accentC: (isObj && modelData.color && cr[modelData.color]) ? cr[modelData.color]
                                    : cr.tileColors[index % cr.tileColors.length]
                                property string iid: ""
                                property string ackSt: iid === "" ? "" : (cr.pendingRev, cr.ackStatus(iid))
                                property bool isPending: ackSt === "pending"
                                width: ib.btnW
                                height: ib.btnH
                                radius: cr.s(14)
                                opacity: isPending ? 0.7 : 1
                                color: ibMa.containsMouse ? Qt.rgba(accentC.r, accentC.g, accentC.b, 0.16) : Qt.alpha(cr.surface0, 0.7)
                                border.width: 1; border.color: ibMa.containsMouse ? Qt.rgba(accentC.r, accentC.g, accentC.b, 0.55) : cr.surface1
                                scale: !cr.cardAnimations ? 1.0 : (ibMa.pressed ? 0.93 : 1.0)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }
                                // hover glow halo in the button's own color
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: -cr.s(2); z: -1
                                    radius: parent.radius + cr.s(2); color: "transparent"
                                    visible: cr.cardDepth
                                    border.width: cr.s(3)
                                    border.color: Qt.rgba(ibBtn.accentC.r, ibBtn.accentC.g, ibBtn.accentC.b, ibMa.containsMouse ? 0.22 : 0.0)
                                    Behavior on border.color { ColorAnimation { duration: 160 } }
                                }
                                Column {
                                    anchors.centerIn: parent; spacing: cr.s(6)
                                    visible: ibBtn.ackSt === ""
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: mIcon; font.family: "Iosevka Nerd Font"
                                        font.pixelSize: cr.s(22)
                                        color: ibMa.containsMouse ? Qt.lighter(ibBtn.accentC, 1.15) : ibBtn.accentC
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                    Text {
                                        visible: mLabel !== ""; anchors.horizontalCenter: parent.horizontalCenter
                                        text: mLabel.toUpperCase(); font.family: "JetBrains Mono"
                                        font.pixelSize: cr.s(9); font.weight: Font.Bold; font.letterSpacing: cr.s(0.5)
                                        color: ibMa.containsMouse ? cr.subtext1 : cr.subtext0
                                    }
                                }
                                Loader {
                                    anchors.centerIn: parent
                                    active: ibBtn.ackSt !== ""
                                    sourceComponent: statusBadge
                                    onLoaded: item.st = Qt.binding(() => ibBtn.ackSt)
                                }
                                MouseArea {
                                    id: ibMa; anchors.fill: parent; hoverEnabled: true
                                    enabled: !ibBtn.isPending
                                    onClicked: {
                                        if (ibBtn.isObj && modelData.silent === true) ibBtn.iid = cr.sendSilent(modelData);
                                        else cr.send(modelData);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: displayBlock
                Row {
                    id: disp
                    property var bData: parent ? parent.dBlock : {}
                    width: cardCol.width
                    spacing: cr.s(8)
                    Repeater {
                        model: disp.bData.items || []
                        delegate: Column {
                            id: dispItem
                            required property var modelData
                            required property int index
                            property string liveVal: modelData.value || ""
                            property bool isSep: modelData.separator === true
                            // semantic-aware per-metric color: matugen tile color normally,
                            // amber/red at warn/crit — same rule the gauges + bars use.
                            property color tileColor: cr.semanticColor(dispItem.liveVal, dispItem.modelData, cr.tileColors[index % cr.tileColors.length])
                            spacing: cr.s(6)

                            Process { id: dispBusStarter; running: false; command: ["python3", "-c", cr.metricsBusSpawnScript] }
                            Process {
                                id: dispLiveProc
                                command: dispItem.modelData.metric
                                    ? ["bash", "-c", "cat " + cr.metricsBusFile]
                                    : ["bash", "-c", dispItem.modelData.source || (dispItem.modelData.watch ? ("cat '" + dispItem.modelData.watch + "'") : "true")]
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        dispItem.liveVal = dispItem.modelData.metric
                                            ? cr.extractMetric(this.text, dispItem.modelData.metric)
                                            : this.text.trim();
                                    }
                                }
                            }
                            Timer {
                                interval: dispItem.modelData.interval_ms || 4000
                                running: !!(dispItem.modelData.source || dispItem.modelData.metric) && !dispItem.modelData.watch
                                repeat: true; triggeredOnStart: true
                                onTriggered: {
                                    if (dispItem.modelData.metric) { dispBusStarter.running = false; dispBusStarter.running = true; }
                                    dispLiveProc.running = false; dispLiveProc.running = true;
                                }
                            }
                            Process {
                                id: dispWatcher
                                running: !!dispItem.modelData.watch
                                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
                                    "f='" + (dispItem.modelData.watch || "") + "'; mkdir -p \"$(dirname \"$f\")\"; touch \"$f\"; " +
                                    "inotifywait -m -e close_write,create,moved_to \"$f\" 2>/dev/null"]
                                stdout: SplitParser { splitMarker: "\n"; onRead: (data) => { dispLiveProc.running = false; dispLiveProc.running = true; } }
                            }
                            Component.onCompleted: if (dispItem.modelData.watch) dispLiveProc.running = true;

                            Rectangle {
                                id: dispTile
                                visible: !isSep
                                width: (cardCol.width - cr.s(8) * Math.max(1, (disp.bData.items || []).length - 1)) / Math.max(1, (disp.bData.items || []).length)
                                height: width * 0.72
                                radius: cr.s(12)
                                clip: true
                                // accent-tinted glass: subtle top→bottom fall-off + colored border
                                // so each metric reads as its own lit panel, not a grey box.
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(dispItem.tileColor.r, dispItem.tileColor.g, dispItem.tileColor.b, dispMa.hovered ? 0.16 : 0.09) }
                                    GradientStop { position: 1.0; color: Qt.alpha(cr.surface0, 0.75) }
                                }
                                border.width: 1
                                border.color: Qt.rgba(dispItem.tileColor.r, dispItem.tileColor.g, dispItem.tileColor.b, dispMa.hovered ? 0.5 : 0.28)
                                scale: !cr.cardAnimations ? 1.0 : (dispMa.hovered ? 1.03 : 1.0)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                HoverHandler { id: dispMa }
                                // hover glow halo
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: -cr.s(2); z: -1
                                    radius: parent.radius + cr.s(2); color: "transparent"
                                    visible: cr.cardDepth
                                    border.width: cr.s(3)
                                    border.color: Qt.rgba(dispItem.tileColor.r, dispItem.tileColor.g, dispItem.tileColor.b, dispMa.hovered ? 0.20 : 0.0)
                                    Behavior on border.color { ColorAnimation { duration: 160 } }
                                }
                                // top specular sheen
                                Rectangle {
                                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                    anchors.topMargin: 1; anchors.leftMargin: cr.s(10); anchors.rightMargin: cr.s(10)
                                    height: 1; visible: cr.cardAnimations
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.14) }
                                        GradientStop { position: 1.0; color: "transparent" }
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: dispItem.liveVal || "--"
                                    font.family: "JetBrains Mono"; font.pixelSize: cr.s(28); font.weight: Font.Bold
                                    color: dispItem.tileColor; horizontalAlignment: Text.AlignHCenter
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                // bottom identity bar in the metric's color
                                Rectangle {
                                    anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottomMargin: cr.s(7)
                                    width: parent.width * 0.32; height: cr.s(2.5); radius: height / 2
                                    color: Qt.rgba(dispItem.tileColor.r, dispItem.tileColor.g, dispItem.tileColor.b, 0.55)
                                }
                            }

                            Text {
                                visible: isSep
                                text: modelData.text || ":"
                                font.family: "JetBrains Mono"; font.pixelSize: cr.s(28); font.weight: Font.Bold
                                color: cr.subtext0
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                visible: !isSep && (modelData.label || "") !== ""
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: (modelData.label || "").toUpperCase()
                                font.family: "JetBrains Mono"; font.pixelSize: cr.s(9); font.weight: Font.Bold; font.letterSpacing: cr.s(0.5)
                                color: cr.subtext0
                            }
                        }
                    }
                }
            }

            Component {
                id: inputBlock
                Column {
                    id: inp
                    property var bData: parent ? parent.dBlock : {}
                    width: cardCol.width
                    spacing: cr.s(8)

                    Text {
                        visible: (inp.bData.label || "") !== ""
                        text: inp.bData.label || ""
                        font.family: "JetBrains Mono"; font.pixelSize: cr.s(12); font.weight: Font.Bold
                        color: cr.text
                    }

                    Rectangle {
                        width: inp.width; height: cr.s(34)
                        radius: cr.s(8)
                        color: inpField.activeFocus ? Qt.alpha(cr.surface0, 0.85) : Qt.alpha(cr.surface0, 0.6)
                        border.width: 1; border.color: inpField.activeFocus ? Qt.rgba(cr.accent.r, cr.accent.g, cr.accent.b, 0.5) : cr.surface1
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                        // focus glow halo + top specular edge — parity with the chat composer
                        Rectangle {
                            anchors.fill: parent; anchors.margins: -cr.s(2); z: -1
                            radius: parent.radius + cr.s(2); color: "transparent"
                            visible: cr.cardDepth
                            border.width: cr.s(2)
                            border.color: Qt.rgba(cr.accent.r, cr.accent.g, cr.accent.b, 0.16)
                            opacity: inpField.activeFocus ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                        }
                        Rectangle {
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                            anchors.topMargin: 1; anchors.leftMargin: cr.s(8); anchors.rightMargin: cr.s(8)
                            height: 1; visible: cr.cardAnimations
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.08) }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }
                        Row {
                            anchors.fill: parent; anchors.leftMargin: cr.s(10); anchors.rightMargin: cr.s(6); spacing: cr.s(6)
                            TextField {
                                id: inpField
                                width: parent.width - inpSubmitBtn.width - cr.s(6)
                                height: parent.height
                                background: Item {}
                                color: cr.text
                                font.family: "JetBrains Mono"; font.pixelSize: cr.s(12)
                                placeholderText: inp.bData.placeholder || "Type here…"
                                placeholderTextColor: cr.subtext0
                                verticalAlignment: TextInput.AlignVCenter
                                Keys.onReturnPressed: inp.submit()
                            }
                            Rectangle {
                                id: inpSubmitBtn
                                width: cr.s(22); height: cr.s(22); radius: cr.s(6)
                                anchors.verticalCenter: parent.verticalCenter
                                color: inpSbMa.containsMouse ? cr.blue : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: String.fromCharCode(0xf00c)
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(10)
                                    color: inpSbMa.containsMouse ? cr.crust : cr.green
                                }
                                MouseArea { id: inpSbMa; anchors.fill: parent; hoverEnabled: true; onClicked: inp.submit() }
                            }
                        }
                    }

                    function submit() {
                        let val = inpField.text.trim();
                        if (val === "") return;
                        inpField.text = "";
                        cr.sendPlain("Card \"" + (cr.spec.title || "") + "\": input=\"" + val + "\"");
                    }
                }
            }

            Rectangle {
                id: chipRect
                readonly property bool hasStats: cr.glanceStats.length > 0
                width: parent.width
                height: hasStats ? cr.s(52) : cr.s(40)
                visible: cr.compact
                radius: cr.s(10)
                // accent-tinted fill + glow instead of flat base — the collapsed card reads
                // as a live tile, not dead chrome. Brightens on hover.
                color: Qt.rgba(cr.base.r, cr.base.g, cr.base.b, 0.94)
                border.width: 1
                border.color: chipBgMa.containsMouse
                    ? Qt.rgba(cr.accent.r, cr.accent.g, cr.accent.b, 0.65)
                    : Qt.rgba(cr.accent.r, cr.accent.g, cr.accent.b, 0.32)
                // tap feedback: brief shrink on press, gentle lift on hover — "luxury is
                // calm", a controlled acknowledgment, not a bounce.
                scale: !cr.cardAnimations ? 1.0 : (chipBgMa.pressed ? 0.985 : (chipBgMa.containsMouse ? 1.025 : 1.0))
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                Behavior on border.color { ColorAnimation { duration: 140 } }

                // soft accent glow behind the chip
                Rectangle {
                    anchors.fill: parent; anchors.margins: -cr.s(2)
                    z: -1; radius: cr.s(12)
                    visible: cr.cardDepth
                    color: "transparent"
                    border.width: cr.s(3)
                    border.color: Qt.rgba(cr.accent.r, cr.accent.g, cr.accent.b, chipBgMa.containsMouse ? 0.22 : 0.10)
                    Behavior on border.color { ColorAnimation { duration: 140 } }
                }
                // specular top edge — glass sheen, parity with the expanded card
                Rectangle {
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    anchors.topMargin: 1; anchors.leftMargin: cr.s(10); anchors.rightMargin: cr.s(10)
                    height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.12) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                // left identity stripe
                Rectangle {
                    anchors.left: parent.left; anchors.leftMargin: cr.s(7)
                    anchors.verticalCenter: parent.verticalCenter
                    width: cr.s(3); height: parent.height - cr.s(18)
                    radius: cr.s(2); color: cr.blue
                }

                // icon in a tinted tile
                Rectangle {
                    id: chipIconTile
                    anchors.left: parent.left; anchors.leftMargin: cr.s(16)
                    anchors.verticalCenter: parent.verticalCenter
                    width: cr.s(30); height: cr.s(30); radius: cr.s(8)
                    color: Qt.rgba(cr.blue.r, cr.blue.g, cr.blue.b, 0.16)
                    Text {
                        anchors.centerIn: parent
                        text: cr.spec.icon ? cr.resolveIcon(cr.spec.icon, cr.spec.title) : "▤"
                        font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(14); font.weight: Font.Bold
                        color: cr.blue
                    }
                }

                Text {
                    id: chipTitle
                    anchors.left: chipIconTile.right; anchors.leftMargin: cr.s(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: cr.spec.title || ""
                    font.family: "JetBrains Mono"; font.pixelSize: cr.s(11); font.weight: Font.Bold
                    color: cr.text
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, chipRect.hasStats ? cr.s(110) : (chipRect.width - cr.s(90)))
                }

                // fallback: glance one-liner when the card has no numeric blocks
                Text {
                    visible: !chipRect.hasStats && (cr.spec.glance || "") !== ""
                    anchors.left: chipTitle.right; anchors.leftMargin: cr.s(8)
                    anchors.right: chipClose.left; anchors.rightMargin: cr.s(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: cr.spec.glance || ""
                    font.family: "JetBrains Mono"; font.pixelSize: cr.s(11)
                    color: cr.subtext0; elide: Text.ElideRight
                }

                // live mini-dashboard: real stats pulled from display/gauges/bars blocks
                Row {
                    visible: chipRect.hasStats
                    anchors.right: chipClose.left; anchors.rightMargin: cr.s(10)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: cr.s(14)
                    Repeater {
                        model: cr.glanceStats
                        delegate: Column {
                            id: gStat
                            required property var modelData
                            required property int index
                            property color statColor: cr.tileColors[index % cr.tileColors.length]
                            property string liveVal: modelData.value
                            spacing: 0

                            Process { id: gBus; running: false; command: ["python3", "-c", cr.metricsBusSpawnScript] }
                            Process {
                                id: gProc
                                command: modelData.metric
                                    ? ["bash", "-c", "cat " + cr.metricsBusFile]
                                    : ["bash", "-c", modelData.source || (modelData.watch ? ("cat '" + modelData.watch + "'") : "true")]
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        if (modelData.metric) gStat.liveVal = cr.extractMetric(this.text, modelData.metric);
                                        else if (modelData.source || modelData.watch) gStat.liveVal = this.text.trim();
                                    }
                                }
                            }
                            Timer {
                                interval: modelData.interval_ms || 4000
                                running: cr.compact && !!(modelData.source || modelData.metric) && !modelData.watch
                                repeat: true; triggeredOnStart: true
                                onTriggered: {
                                    if (modelData.metric) { gBus.running = false; gBus.running = true; }
                                    gProc.running = false; gProc.running = true;
                                }
                            }
                            Process {
                                id: gWatch
                                running: cr.compact && !!modelData.watch
                                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
                                    "f='" + (modelData.watch || "") + "'; mkdir -p \"$(dirname \"$f\")\"; touch \"$f\"; " +
                                    "inotifywait -m -e close_write,create,moved_to \"$f\" 2>/dev/null"]
                                stdout: SplitParser { splitMarker: "\n"; onRead: (data) => { gProc.running = false; gProc.running = true; } }
                            }
                            Component.onCompleted: if (cr.compact && modelData.watch) gProc.running = true;

                            Text {
                                id: gStatVal
                                anchors.right: parent.right
                                text: gStat.liveVal + (modelData.unit ? (" " + modelData.unit) : "")
                                font.family: "JetBrains Mono"; font.pixelSize: cr.s(13); font.weight: Font.Bold
                                color: gStat.statColor
                                transformOrigin: Item.Right
                                // pulse on update — a live value that changes should feel alive,
                                // not silently swap. Also gives a subtle entrance on appear.
                                onTextChanged: gStatPulse.restart()
                                NumberAnimation { id: gStatPulse; target: gStatVal; property: "scale"; from: 1.18; to: 1.0; duration: 280; easing.type: Easing.OutBack }
                            }
                            Text {
                                anchors.right: parent.right
                                text: ("" + (modelData.label || "")).toUpperCase()
                                font.family: "JetBrains Mono"; font.pixelSize: cr.s(8); font.weight: Font.Bold
                                color: cr.subtext0
                            }
                        }
                    }
                }

                Rectangle {
                    id: chipClose
                    anchors.right: parent.right; anchors.rightMargin: cr.s(6)
                    anchors.verticalCenter: parent.verticalCenter
                    width: cr.s(22); height: cr.s(22); radius: cr.s(6)
                    color: chipUnpinMa.containsMouse ? cr.surface2 : "transparent"
                    visible: cr.standalone
                    Text {
                        anchors.centerIn: parent; text: String.fromCharCode(0xf00d)
                        font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(10); color: cr.subtext0
                    }
                    MouseArea { id: chipUnpinMa; anchors.fill: parent; hoverEnabled: true; onClicked: cr.unpinRequested() }
                }
                MouseArea {
                    id: chipBgMa
                    anchors.fill: parent
                    anchors.rightMargin: cr.standalone ? cr.s(28) : 0
                    hoverEnabled: true
                    onClicked: { cr.compact = false; cr.compactToggled(false); }
                }
            }

            Rectangle {
                id: ccard
                width: parent.width
                height: cr.s(24)
                    + (cardHeader.visible ? cardHeader.height + cr.s(12) : 0)
                    + (cr.isBuilding ? cr.s(104) : cr._totalBlocksH)
                visible: !cr.compact
                radius: cr.s(12)
                color: Qt.rgba(cr.base.r, cr.base.g, cr.base.b, 0.92)
                // hover glow parity with the collapsed chip — HoverHandler doesn't steal
                // clicks from blocks/buttons the way a MouseArea would.
                border.width: 1
                border.color: cardHover.hovered
                    ? Qt.rgba(cr.accent.r, cr.accent.g, cr.accent.b, 0.60)
                    : Qt.rgba(cr.accent.r, cr.accent.g, cr.accent.b, 0.30)
                Behavior on border.color { ColorAnimation { duration: 160 } }
                HoverHandler { id: cardHover }
                // micro-lift on hover — pairs with the depth shadow so the card reads as
                // physically rising toward the cursor. transform, not y, so layout is untouched.
                transform: Translate { y: (cr.cardAnimations && cardHover.hovered) ? -cr.s(2) : 0; Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } } }
                // specular top edge — a faint bright line catching light like frosted glass
                Rectangle {
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    anchors.topMargin: 1; anchors.leftMargin: cr.s(12); anchors.rightMargin: cr.s(12)
                    height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.10) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
                // soft depth shadow — stacked translucent rects fake a blur (MultiEffect blur
                // is unreliable in quickshell-git per project notes) to ground the card with
                // premium z-depth. Offset down so light reads as coming from above.
                Repeater {
                    model: cr.cardDepth ? 6 : 0
                    Rectangle {
                        required property int index
                        z: -2
                        width: ccard.width + index * cr.s(4)
                        height: ccard.height + index * cr.s(4)
                        x: -index * cr.s(2)
                        y: -index * cr.s(2) + cr.s(7)
                        radius: ccard.radius + index * cr.s(2)
                        color: Qt.rgba(0, 0, 0, 0.06)
                    }
                }
                Rectangle {
                    anchors.fill: parent; anchors.margins: -cr.s(2)
                    z: -1; radius: cr.s(14)
                    visible: cr.cardDepth
                    color: "transparent"
                    border.width: cr.s(3)
                    border.color: Qt.rgba(cr.accent.r, cr.accent.g, cr.accent.b, cardHover.hovered ? 0.20 : 0.08)
                    Behavior on border.color { ColorAnimation { duration: 160 } }
                }

                // skeleton shimmer while a card streams in (card_start placeholder before
                // card_update fills blocks) — replaces the bare empty housing with a calm,
                // alive loading state.
                Item {
                    id: skeleton
                    visible: cr.isBuilding
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: cr.s(16); anchors.rightMargin: cr.s(16)
                    anchors.top: parent.top
                    anchors.topMargin: cr.s(16) + (cardHeader.visible ? cardHeader.height + cr.s(12) : 0)
                    height: cr.s(88)
                    clip: true
                    Column {
                        anchors.fill: parent
                        spacing: cr.s(12)
                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                width: parent.width * (index === 0 ? 0.45 : index === 1 ? 0.9 : 0.7)
                                height: cr.s(20); radius: cr.s(6)
                                color: Qt.rgba(cr.surface1.r, cr.surface1.g, cr.surface1.b, 0.55)
                            }
                        }
                    }
                    Rectangle {
                        id: shimmerSweep
                        width: cr.s(130); height: parent.height * 2
                        y: -parent.height / 2
                        rotation: 14
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.5; color: Qt.rgba(cr.text.r, cr.text.g, cr.text.b, 0.09) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        NumberAnimation on x {
                            running: skeleton.visible; loops: Animation.Infinite
                            from: -cr.s(150); to: skeleton.width + cr.s(150)
                            duration: 1150; easing.type: Easing.InOutSine
                        }
                    }
                }

                Column {
                    id: cardCol
                    width: parent.width - cr.s(32)
                    x: cr.s(16); y: cr.s(12)
                    spacing: cr.s(12)

                    Item {
                        id: cardHeader
                        width: cardCol.width
                        height: Math.max(headerRow.implicitHeight, pinBtn.height)
                        visible: (cr.spec.title || "") !== "" || cr.standalone

                        Row {
                            id: headerRow
                            spacing: cr.s(8)
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                visible: (cr.spec.title || "") !== ""
                                text: cr.spec.icon ? cr.resolveIcon(cr.spec.icon, cr.spec.title) : "▤"
                                font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(15); font.weight: Font.Bold
                                color: cr.blue
                            }
                            Text {
                                text: cr.spec.title || ""
                                font.family: "JetBrains Mono"; font.pixelSize: cr.s(11); font.weight: Font.Bold
                                color: cr.blue; wrapMode: Text.Wrap
                            }
                        }

                        // one toggle: off = nothing extra; on = the message-Claude composer
                        // appears at the bottom AND block backgrounds become clickable to
                        // select (the border-highlight + Edit pill). Same button, icon swaps —
                        // no separate always-visible chat icon, no permanently-clickable blocks.
                        Rectangle {
                            id: editModeBtn
                            visible: !cr.hasSecret && !cr.hasApproval
                            anchors.right: revertBtn.visible ? revertBtn.left : (shrinkBtn.visible ? shrinkBtn.left : pinBtn.left)
                            anchors.rightMargin: cr.s(6)
                            anchors.verticalCenter: parent.verticalCenter
                            width: cr.s(22); height: cr.s(22); radius: cr.s(6)
                            color: cr.editMode ? Qt.rgba(cr.blue.r, cr.blue.g, cr.blue.b, 0.22)
                                   : (editModeMa.containsMouse ? cr.surface2 : "transparent")
                            Text {
                                anchors.centerIn: parent
                                text: String.fromCharCode(cr.editMode ? 0xf245 : 0xf075)
                                font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(10)
                                color: cr.editMode ? cr.blue : (editModeMa.containsMouse ? cr.text : cr.subtext0)
                            }
                            MouseArea {
                                id: editModeMa; anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    cr.editMode = !cr.editMode;
                                    if (!cr.editMode) cr.selectedBlockIndex = -1;
                                }
                            }
                        }

                        // undo the last update_card/re-pin patch — only shows once there's
                        // actually a prior snapshot to go back to, never for a secret card
                        Rectangle {
                            id: revertBtn
                            visible: cr.hasHistory && !cr.hasSecret
                            anchors.right: shrinkBtn.visible ? shrinkBtn.left : pinBtn.left
                            anchors.rightMargin: cr.s(6)
                            anchors.verticalCenter: parent.verticalCenter
                            width: cr.s(22); height: cr.s(22); radius: cr.s(6)
                            color: revertMa.containsMouse ? cr.surface2 : "transparent"
                            Text {
                                anchors.centerIn: parent; text: String.fromCharCode(0xf0e2)
                                font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(10)
                                color: revertMa.containsMouse ? cr.text : cr.subtext0
                            }
                            MouseArea { id: revertMa; anchors.fill: parent; hoverEnabled: true; onClicked: cr.requestRevert() }
                        }

                        // shrink back to the compact chip — standalone-only, mirrors the chip's
                        // own click-to-expand so collapsing is just as reachable as expanding
                        Rectangle {
                            id: shrinkBtn
                            visible: cr.standalone
                            anchors.right: pinBtn.left
                            anchors.rightMargin: cr.s(6)
                            anchors.verticalCenter: parent.verticalCenter
                            width: cr.s(22); height: cr.s(22); radius: cr.s(6)
                            color: shrinkMa.containsMouse ? cr.surface2 : "transparent"
                            Text {
                                anchors.centerIn: parent; text: String.fromCharCode(0xf078)
                                font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(10)
                                color: shrinkMa.containsMouse ? cr.text : cr.subtext0
                            }
                            MouseArea { id: shrinkMa; anchors.fill: parent; hoverEnabled: true; onClicked: { cr.compact = true; cr.compactToggled(true); } }
                        }

                        // pin (in chat) / unpin (in the standalone panel) — pinned cards keep
                        // refreshing/clickable on their own, independent of this card's chat row
                        Rectangle {
                            id: pinBtn
                            visible: !cr.hasSecret && !cr.hasApproval
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: cr.s(22); height: cr.s(22); radius: cr.s(6)
                            // pinned state needs a background fill too — the thumb-tack glyph is
                            // a solid pictograph either way, so icon color alone read as "always
                            // filled" with low theme contrast. Background makes the toggle obvious.
                            color: (!cr.standalone && cr.pinned) ? Qt.rgba(cr.peach.r, cr.peach.g, cr.peach.b, 0.22)
                                   : (pinMa.containsMouse ? cr.surface2 : "transparent")
                            Text {
                                anchors.centerIn: parent
                                text: cr.standalone ? String.fromCharCode(0xf00d) : String.fromCharCode(0xf08d)
                                font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(11)
                                color: cr.standalone ? (pinMa.containsMouse ? cr.text : cr.subtext0)
                                       : (cr.pinned ? cr.peach : (pinMa.containsMouse ? cr.text : cr.subtext0))
                                rotation: cr.standalone ? 0 : 45
                            }
                            MouseArea {
                                id: pinMa; anchors.fill: parent; hoverEnabled: true
                                onClicked: cr.standalone ? cr.unpinRequested() : cr.pinRequested()
                            }
                        }
                    }

                    Repeater {
                        id: blocksRepeater
                        model: cr.spec.blocks || []
                        onItemAdded: (index, item) => Qt.callLater(cr.updateTotalHeight)
                        onItemRemoved: (index, item) => Qt.callLater(cr.updateTotalHeight)
                        delegate: Item {
                            id: blockWrap
                            required property var modelData
                            required property int index
                            property bool editOpen: false
                            Connections {
                                target: cr
                                function onEditModeChanged() { if (!cr.editMode) blockWrap.editOpen = false; }
                                function onSelectedBlockIndexChanged() { if (cr.selectedBlockIndex !== blockWrap.index) blockWrap.editOpen = false; }
                            }
                            readonly property bool selected: cr.selectedBlockIndex === index
                            readonly property bool editable: blockWrap.modelData.kind !== "secret"
                            // exposed so cr.reportAll() (debug-only UI probe manifest, see
                            // qs_probe.py) can read exact click targets without screenshots
                            property alias loaderRef: blockLoader
                            property alias pillRef: pill
                            width: cardCol.width
                            height: blockLoader.height + cr.s(10) + (pill.visible ? pill.height : 0) + (editOpen ? editComposer.height + cr.s(6) : 0)
                            z: blockLoader.item && blockLoader.item["expanded"] && blockLoader.item["fitsInCard"] ? 100 : 0
                            onHeightChanged: Qt.callLater(cr.updateTotalHeight)
                            Component.onCompleted: Qt.callLater(cr.updateTotalHeight)

                            Loader {
                                id: blockLoader
                                property var dBlock: blockWrap.modelData
                                width: cardCol.width
                                // read implicitHeight, not height: a positioner-rooted block
                                // (Row/Column/Grid/Flow) has no explicit height, so Loader would
                                // force item.height = Loader.height while Loader.height binds back
                                // to item.height — a circular binding Qt breaks to 0, collapsing
                                // the block. implicitHeight is computed from children and never
                                // written by Loader, so it's stable for both positioner and Item roots.
                                height: item ? item.implicitHeight : implicitHeight
                                sourceComponent: {
                                    switch (dBlock.kind) {
                                                        case "rows":       return rowsBlock;
                                        case "gauges":     return gaugesBlock;
                                        case "bars":       return barsBlock;
                                        case "pills":      return pillsBlock;
                                        case "buttons":    return buttonsBlock;
                                        case "list":       return listBlock;
                                        case "agenda":     return agendaBlock;
                                        case "text":       return textBlock;
                                        case "secret":     return secretBlock;
                                        case "dropdown":   return dropdownBlock;
                                        case "iconbuttons": return iconbuttonsBlock;
                                        case "display":    return displayBlock;
                                        case "input":      return inputBlock;
                                        case "table":      return tableBlock;
                                        case "sparkline":  return sparklineBlock;
                                        default:           return null;
                                    }
                                }
                            }

                            // background-only click target, sitting behind the loaded block's
                            // own content (z:-1) so a button/pill/field inside the block still
                            // gets first claim on any click — only empty block background
                            // reaches this. Click to select, click again to deselect. Nothing
                            // is shown until this happens — no permanent icon, no permanent box.
                            MouseArea {
                                anchors.fill: blockLoader
                                z: -1
                                enabled: blockWrap.editable && cr.editMode
                                onClicked: cr.selectedBlockIndex = blockWrap.selected ? -1 : blockWrap.index
                            }
                            // soft fill + left accent bar instead of a hard outline — a stark
                            // border looked like a glitch/cutout; this reads as "highlighted",
                            // matching the soft-glow selection language Linear/Notion use
                            Rectangle {
                                id: selectGlow
                                anchors.fill: blockLoader
                                anchors.margins: -cr.s(6)
                                visible: opacity > 0.01
                                opacity: blockWrap.selected ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                radius: cr.s(10)
                                color: Qt.rgba(cr.blue.r, cr.blue.g, cr.blue.b, 0.10)
                            }
                            Rectangle {
                                anchors.left: blockLoader.left; anchors.top: blockLoader.top; anchors.bottom: blockLoader.bottom
                                anchors.leftMargin: -cr.s(6)
                                visible: selectGlow.visible
                                opacity: selectGlow.opacity
                                width: cr.s(3); radius: cr.s(2)
                                color: cr.blue
                            }

                            // the floating pill — the only thing a selected block grows, and
                            // only while editOpen is false (the composer below replaces it)
                            Row {
                                id: pill
                                visible: blockWrap.selected && !blockWrap.editOpen
                                anchors.top: blockLoader.bottom; anchors.topMargin: cr.s(8)
                                anchors.right: blockLoader.right
                                height: cr.s(22)
                                spacing: cr.s(6)
                                Rectangle {
                                    width: editLbl.implicitWidth + cr.s(16); height: cr.s(22); radius: cr.s(7)
                                    color: editPillMa.containsMouse ? cr.blue : Qt.rgba(cr.blue.r, cr.blue.g, cr.blue.b, 0.16)
                                    Text { id: editLbl; anchors.centerIn: parent; text: "Edit"; font.family: "JetBrains Mono"; font.pixelSize: cr.s(10); font.weight: Font.Bold; color: editPillMa.containsMouse ? cr.crust : cr.blue }
                                    MouseArea { id: editPillMa; anchors.fill: parent; hoverEnabled: true; onClicked: blockWrap.editOpen = true }
                                }
                            }

                            Rectangle {
                                id: editComposer
                                visible: blockWrap.editOpen
                                anchors.top: blockLoader.bottom; anchors.topMargin: cr.s(6)
                                width: cardCol.width; height: cr.s(30)
                                radius: cr.s(8)
                                color: Qt.alpha(cr.surface0, 0.6)
                                border.width: 1; border.color: cr.surface1
                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: cr.s(10); anchors.rightMargin: cr.s(6)
                                    spacing: cr.s(6)
                                    TextField {
                                        id: editInput
                                        width: parent.width - editSendBtn.width - cr.s(6)
                                        height: parent.height
                                        background: Item {}
                                        color: cr.text
                                        font.family: "JetBrains Mono"; font.pixelSize: cr.s(11)
                                        placeholderText: "What should change here?"
                                        placeholderTextColor: cr.subtext0
                                        verticalAlignment: TextInput.AlignVCenter
                                        Keys.onReturnPressed: blockWrap.submitEdit()
                                    }
                                    Rectangle {
                                        id: editSendBtn
                                        width: cr.s(20); height: cr.s(20); radius: cr.s(6)
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: editSendMa.containsMouse ? cr.surface2 : "transparent"
                                        Text {
                                            anchors.centerIn: parent; text: String.fromCharCode(0xf1d8)
                                            font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(9); color: cr.blue
                                        }
                                        MouseArea { id: editSendMa; anchors.fill: parent; hoverEnabled: true; onClicked: blockWrap.submitEdit() }
                                    }
                                }
                            }

                            function submitEdit() {
                                if (editInput.text.trim() === "") return;
                                let idStr = cr.spec.card_id ? ("card_id:" + cr.spec.card_id) : ("title:\"" + (cr.spec.title || "") + "\"");
                                cr.sendPlain("Edit block #" + blockWrap.index + " (" + (blockWrap.modelData.kind || "") +
                                    ") on the card (" + idStr + "): " + editInput.text.trim() +
                                    "\nCurrent block: " + JSON.stringify(blockWrap.modelData));
                                editInput.text = "";
                                blockWrap.editOpen = false;
                                cr.selectedBlockIndex = -1;
                            }
                        }
                    }

                    // message-Claude composer — standalone-only, driven entirely by the
                    // header's editModeBtn toggle now (no separate collapsed icon living down
                    // here; that icon moved into the header next to shrink/close).
                    Item {
                        width: cardCol.width
                        height: (cr.standalone && cr.editMode) ? cr.s(28) : 0
                        visible: cr.standalone && cr.editMode

                        Rectangle {
                            anchors.fill: parent
                            radius: cr.s(8)
                            color: Qt.alpha(cr.surface0, 0.6)
                            border.width: 1; border.color: cr.surface1
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: cr.s(10); anchors.rightMargin: cr.s(6)
                                spacing: cr.s(6)
                                TextField {
                                    id: quickSendInput
                                    width: parent.width - sendBtn.width - cr.s(6)
                                    height: parent.height
                                    background: Item {}
                                    color: cr.text
                                    font.family: "JetBrains Mono"; font.pixelSize: cr.s(11)
                                    placeholderText: "Message Claude…"
                                    placeholderTextColor: cr.subtext0
                                    verticalAlignment: TextInput.AlignVCenter
                                    focus: cr.editMode
                                    Keys.onEscapePressed: cr.editMode = false
                                    Keys.onReturnPressed: {
                                        if (text.trim() === "") return;
                                        cr.sendPlain(text.trim());
                                        text = "";
                                    }
                                }
                                Rectangle {
                                    id: sendBtn
                                    width: cr.s(22); height: cr.s(22); radius: cr.s(6)
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: sendMa.containsMouse ? cr.surface2 : "transparent"
                                    Text {
                                        anchors.centerIn: parent; text: String.fromCharCode(0xf1d8)
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: cr.s(10); color: cr.blue
                                    }
                                    MouseArea {
                                        id: sendMa; anchors.fill: parent; hoverEnabled: true
                                        onClicked: {
                                            if (quickSendInput.text.trim() === "") return;
                                            cr.sendPlain(quickSendInput.text.trim());
                                            quickSendInput.text = "";
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
