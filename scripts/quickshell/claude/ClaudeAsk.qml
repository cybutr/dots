import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window
    focus: true

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val); }

    // "shimmer" sweeping line vs "dots" pulsing dots while Claude thinks — set in the guide
    property string thinkingStyle: "shimmer"
    Process {
        id: thinkStyleReader
        running: true
        command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
        stdout: StdioCollector { onStreamFinished: { try { let p = JSON.parse(this.text.trim() || "{}"); if (p.chatThinkingStyle !== undefined) window.thinkingStyle = p.chatThinkingStyle; } catch (e) {} } }
    }
    Process {
        id: thinkStyleWatcher
        running: true
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "while [ ! -f ~/.config/hypr/settings.json ]; do sleep 1; done; inotifywait -m -e close_write,modify ~/.config/hypr/settings.json 2>/dev/null"]
        stdout: SplitParser { splitMarker: "\n"; onRead: (data) => { thinkStyleReader.running = false; thinkStyleReader.running = true; } }
    }

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

    readonly property color modeColor: agentMode === "plan" ? green : (agentMode === "auto" ? peach : blue)
    readonly property string modeLabel: agentMode === "plan" ? "PLAN" : (agentMode === "auto" ? "AUTO" : "ASK")
    readonly property string modeIcon: agentMode === "plan" ? "◐" : (agentMode === "auto" ? "●" : "○")

    // --- work timer (commitment timer; pill + Stop-hook enforced) ---
    property real timerDeadline: 0
    property string timerTask: ""
    property int timerRemaining: 0
    readonly property bool timerActive: timerRemaining > 0
    readonly property string timerLabel: {
        let m = Math.floor(timerRemaining / 60);
        let s = timerRemaining % 60;
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
    }
    function recomputeTimer() {
        if (timerDeadline <= 0) { timerRemaining = 0; return; }
        let r = Math.floor(timerDeadline - Date.now() / 1000);
        timerRemaining = r > 0 ? r : 0;
        if (r <= 0) timerDeadline = 0;
    }
    Process {
        id: timerReader
        command: ["cat", "/tmp/qs_worktimer.json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(this.text.trim() || "{}");
                    window.timerDeadline = d.deadline || 0;
                    window.timerTask = d.task || "";
                } catch (e) { window.timerDeadline = 0; window.timerTask = ""; }
                window.recomputeTimer();
            }
        }
    }
    Process { id: timerCanceller; running: false }
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: { timerReader.running = false; timerReader.running = true; window.recomputeTimer(); }
    }

    // --- state ---
    property string windowCtx: ""
    property string clipCtx: ""
    property string clipSnippet: ""
    readonly property string contextStr: [clipCtx, windowCtx].filter(x => x !== "").join("\n\n")
    property string ctxFile: Quickshell.env("HOME") + "/.cache/quickshell/claude/ask_ctx.txt"
    property string chatFile: Quickshell.env("HOME") + "/.cache/quickshell/claude/chat.json"
    property string suppressFile: Quickshell.env("HOME") + "/.cache/quickshell/claude/dismissed_cards.json"

    // card_ids of one-shot approval cards the user already resolved — never re-show
    // them when the daemon replays its stream on reconnect.
    property var suppressedCards: ({})
    Process { id: suppressWriter; running: false }
    Process {
        id: suppressLoader; running: true
        command: ["bash", "-c", "cat '" + suppressFile + "' 2>/dev/null || echo '{}'"]
        stdout: StdioCollector { onStreamFinished: {
            try { window.suppressedCards = JSON.parse(this.text.trim() || "{}"); } catch (e) { window.suppressedCards = {}; }
        } }
    }
    function suppressCard(cardId) {
        if (!cardId) return;
        let m = window.suppressedCards || {};
        m[cardId] = Date.now();
        window.suppressedCards = m;
        suppressWriter.command = ["bash", "-c", "printf '%s' \"$1\" > '" + suppressFile + "'", "_", JSON.stringify(m)];
        suppressWriter.running = false; suppressWriter.running = true;
    }
    function isCardSuppressed(cardId) {
        return cardId && window.suppressedCards && window.suppressedCards[cardId] !== undefined;
    }

    property string agentMode: "ask"
    property string modelName: ""
    property string authSel: "auto"
    property var authEntries: []
    property string workDir: ""
    property string globalAcctLabel: ""
    property string globalAcctType: "account"
    property string globalAcctEmail: ""
    property string sessionId: ""
    property int turnCount: 0
    property bool busy: false
    property string streamBuf: ""
    property string fullBuf: ""

    // persistent agent session
    property bool agentReady: false
    property var pendingMsgs: []
    // texts this widget rendered locally already; their transcript echo is skipped
    // so live sends don't double. Echoes with no match (replay) still render.
    property var pendingEcho: []

    // selectable models — depends on the active source. z.ai (GLM) sources expose
    // GLM model ids; opencode sources expose opencode's own catalog; every
    // other source uses the Claude family aliases.
    property var modelOptions: srcModels()
    property var opencodeModels: []
    function isGlmSource() {
        let e = window.authEntry();
        return !!(e && e.base_url && e.base_url.indexOf("z.ai") >= 0);
    }
    function isOpencodeSource() {
        let e = window.authEntry();
        return !!(e && e.type === "opencode");
    }
    function srcModels() {
        if (window.isGlmSource()) return [
            { id: "glm-5.2",     desc: "flagship · coding" },
            { id: "glm-4.6",     desc: "cheaper" },
            { id: "glm-4.5-air", desc: "fastest" },
            { id: "",            desc: "default (glm-5.2)" }
        ];
        if (window.isOpencodeSource()) {
            if (window.opencodeModels.length > 0) return window.opencodeModels;
            return [{ id: "", desc: "loading models…" }];
        }
        return [
            { id: "opus",   desc: "most capable" },
            { id: "sonnet", desc: "balanced" },
            { id: "haiku",  desc: "fastest" },
            { id: "fable",  desc: "Fable 5" },
            { id: "",       desc: "default (proxy)" }
        ];
    }
    // keep the saved model valid for the active source: GLM sources can't run
    // claude-* ids (z.ai 404s), opencode ids don't apply outside opencode,
    // and vice-versa. Snap to the source default on mismatch.
    function syncModelToSource() {
        let glm = window.isGlmSource();
        let oc = window.isOpencodeSource();
        let isGlmModel = window.modelName.indexOf("glm") === 0;
        let isOcModel = window.opencodeModels.some(m => m.id === window.modelName && m.id !== "");
        if (glm && !isGlmModel) window.setModel("glm-5.2");
        else if (oc && !isOcModel) window.setModel("");
        else if (!glm && !oc && (isGlmModel || isOcModel)) window.setModel("");
    }

    // slash command / skill suggestions
    property var allSugg: []
    property var suggMatches: []
    property int suggIndex: 0
    property bool suggOpen: false

    // typewriter reveal — decouples display from chunky network arrival
    Timer {
        id: revealTimer
        interval: 16; repeat: true
        running: window.busy && window.streamBuf.length < window.fullBuf.length
        onTriggered: {
            let remaining = window.fullBuf.length - window.streamBuf.length;
            if (remaining <= 0) return;
            let step = Math.max(1, Math.ceil(remaining / 22));
            window.streamBuf = window.fullBuf.substring(0, window.streamBuf.length + step);
        }
    }

    property real nowTs: Date.now()
    Timer { interval: 30000; running: true; repeat: true; onTriggered: window.nowTs = Date.now() }

    // streaming caret blink
    property bool caretOn: true
    Timer { interval: 530; running: window.busy; repeat: true; onTriggered: window.caretOn = !window.caretOn }

    function isRunnable(lang) {
        return ["sh", "bash", "shell", "zsh", "fish", "console"].indexOf(lang) >= 0;
    }

    function relTime(ts) {
        if (!ts) return "";
        let d = Math.max(0, Math.floor((window.nowTs - ts) / 1000));
        if (d < 10) return "just now";
        if (d < 60) return d + "s ago";
        if (d < 3600) return Math.floor(d / 60) + "m ago";
        if (d < 86400) return Math.floor(d / 3600) + "h ago";
        return Math.floor(d / 86400) + "d ago";
    }

    function escHtml(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }

    function highlight(code, lang) {
        let kw = "if|then|else|elif|fi|for|while|do|done|case|esac|function|return|in|export|local|echo|cd|sudo|set|def|class|import|from|as|const|let|var|new|await|async|try|except|catch|finally|with|pass|lambda|print|and|or|not|True|False|None|true|false|null|undefined|public|private|void|int|string|bool";
        let kwre = new RegExp("\\b(" + kw + ")\\b", "g");
        function kwrap(t) { return window.escHtml(t).replace(kwre, '<span style="color:#cba6f7">$1</span>'); }
        let re = /(#[^\n]*|\/\/[^\n]*)|("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`)|\b(\d+(?:\.\d+)?)\b|(--?[A-Za-z][\w-]*)/g;
        let out = "", last = 0, m;
        while ((m = re.exec(code)) !== null) {
            if (m.index > last) out += kwrap(code.slice(last, m.index));
            if (m[1]) out += '<span style="color:#6c7086">' + window.escHtml(m[1]) + '</span>';
            else if (m[2]) out += '<span style="color:#a6e3a1">' + window.escHtml(m[2]) + '</span>';
            else if (m[3]) out += '<span style="color:#fab387">' + window.escHtml(m[3]) + '</span>';
            else if (m[4]) out += '<span style="color:#89dceb">' + window.escHtml(m[4]) + '</span>';
            last = re.lastIndex;
        }
        if (last < code.length) out += kwrap(code.slice(last));
        out = out.replace(/ /g, "&nbsp;").replace(/\n/g, "<br/>");
        return '<span style="font-family:JetBrains Mono">' + out + '</span>';
    }

    // --- persistence: mode ---
    Process {
        id: modeLoader
        running: true
        command: ["bash", "-c", "cat ~/.cache/quickshell/claude/mode 2>/dev/null || echo ask"]
        stdout: StdioCollector {
            onStreamFinished: {
                let m = this.text.trim();
                if (m === "auto" || m === "ask" || m === "plan") window.agentMode = m;
            }
        }
    }
    Process { id: modeSaver; running: false }
    function saveMode() {
        modeSaver.command = ["python3", "-c",
            "import sys,os; os.makedirs(os.path.dirname(sys.argv[1]),exist_ok=True); open(sys.argv[1],'w').write(sys.argv[2])",
            Quickshell.env("HOME") + "/.cache/quickshell/claude/mode", window.agentMode];
        modeSaver.running = false; modeSaver.running = true;
    }
    function toggleMode() {
        window.agentMode = window.agentMode === "ask" ? "auto" : (window.agentMode === "auto" ? "plan" : "ask");
        saveMode();
        window.stopAgent();
    }

    Process {
        id: modelLoader
        running: true
        command: ["bash", "-c", "cat ~/.cache/quickshell/claude/model 2>/dev/null || echo ''"]
        stdout: StdioCollector { onStreamFinished: window.modelName = this.text.trim() }
    }
    Process { id: modelSaver; running: false }
    function setModel(m) {
        window.modelName = m.trim();
        modelSaver.command = ["python3", "-c",
            "import sys,os; os.makedirs(os.path.dirname(sys.argv[1]),exist_ok=True); open(sys.argv[1],'w').write(sys.argv[2])",
            Quickshell.env("HOME") + "/.cache/quickshell/claude/model", window.modelName];
        modelSaver.running = false; modelSaver.running = true;
        window.stopAgent();
    }

    // --- working directory ---
    Process {
        id: workDirLoader
        running: true
        command: ["bash", "-c", "cat ~/.cache/quickshell/claude/workdir 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: window.workDir = this.text.trim() }
    }
    Process { id: workDirSaver; running: false }
    Process {
        id: workDirCheck
        property string candidate: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let resolved = this.text.trim();
                if (resolved === "") { window.sysMsg("no such directory: " + workDirCheck.candidate); return; }
                window.workDir = resolved;
                workDirSaver.command = ["python3", "-c",
                    "import sys,os; os.makedirs(os.path.dirname(sys.argv[1]),exist_ok=True); open(sys.argv[1],'w').write(sys.argv[2])",
                    Quickshell.env("HOME") + "/.cache/quickshell/claude/workdir", resolved];
                workDirSaver.running = false; workDirSaver.running = true;
                window.stopAgent();
                window.sysMsg("cwd → " + resolved);
            }
        }
    }
    function setWorkDir(path) {
        if (path === "" || path === "~") {
            window.workDir = "";
            workDirSaver.command = ["bash", "-c", "rm -f ~/.cache/quickshell/claude/workdir"];
            workDirSaver.running = false; workDirSaver.running = true;
            window.stopAgent();
            window.sysMsg("cwd → home (default)");
            return;
        }
        workDirCheck.candidate = path;
        workDirCheck.command = ["bash", "-c",
            "p=\"$1\"; p=\"${p/#\\~/$HOME}\"; [ -d \"$p\" ] && cd \"$p\" && pwd || echo ''",
            "bash", path];
        workDirCheck.running = false; workDirCheck.running = true;
    }

    // --- auth selection (account / key / auto-follow-global) ---
    Process {
        id: authLoader
        running: true
        command: ["bash", "-c", "cat ~/.cache/quickshell/claude/auth 2>/dev/null || echo auto"]
        stdout: StdioCollector { onStreamFinished: { let a = this.text.trim(); if (a) window.authSel = a; } }
    }
    Process { id: authSaver; running: false }
    Process {
        id: globalAcctReader
        running: true
        command: ["bash", "-c", "jq -r '[.label // \"\", .type // \"account\", .email // \"\"] | @tsv' ~/.config/anthropic/current.json 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = this.text.trim().split("\t");
                window.globalAcctLabel = p[0] || "";
                window.globalAcctType = p[1] || "account";
                window.globalAcctEmail = p[2] || "";
            }
        }
    }
    Process {
        id: authEntriesLoader
        running: true
        command: ["bash", "-c", "~/.config/hypr/scripts/anthropic_acct.sh list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let arr = [];
                let lines = this.text.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    if (!lines[i]) continue;
                    try { arr.push(JSON.parse(lines[i])); } catch (e) {}
                }
                window.authEntries = arr;
                window.syncModelToSource();
            }
        }
    }
    // real opencode catalog (provider/model ids, e.g. "opencode/big-pickle") —
    // includes whatever providers are actually authenticated right now
    // (opencode auth login), not a hardcoded guess
    Process {
        id: opencodeModelsLoader
        running: true
        command: ["bash", "-c", "PATH=\"$HOME/.local/bin:$PATH\" opencode models 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let arr = [];
                let lines = this.text.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let id = lines[i].trim();
                    if (!id) continue;
                    let provider = id.split("/")[0] || "";
                    arr.push({ id: id, desc: provider });
                }
                arr.push({ id: "", desc: "default" });
                window.opencodeModels = arr;
                window.syncModelToSource();
            }
        }
    }
    function refreshOpencodeModels() {
        opencodeModelsLoader.running = false; opencodeModelsLoader.running = true;
    }
    function saveAuth() {
        authSaver.command = ["python3", "-c",
            "import sys,os; os.makedirs(os.path.dirname(sys.argv[1]),exist_ok=True); open(sys.argv[1],'w').write(sys.argv[2])",
            Quickshell.env("HOME") + "/.cache/quickshell/claude/auth", window.authSel];
        authSaver.running = false; authSaver.running = true;
    }
    function cycleAuth() {
        let opts = ["auto"];
        for (let i = 0; i < window.authEntries.length; i++) opts.push(window.authEntries[i].id);
        let idx = opts.indexOf(window.authSel);
        if (idx < 0) idx = 0;
        window.authSel = opts[(idx + 1) % opts.length];
        window.saveAuth();
        if (window.isOpencodeSource()) window.refreshOpencodeModels();
        window.syncModelToSource();
        window.stopAgent();
    }
    // the entry the chip currently resolves to (the explicit pick, or the
    // global active account when on "auto")
    function authEntry() {
        let id = window.authSel;
        if (id === "auto") {
            for (let i = 0; i < window.authEntries.length; i++)
                if (window.authEntries[i].email === window.globalAcctEmail && window.globalAcctEmail !== "")
                    return window.authEntries[i];
            return { label: window.globalAcctLabel, type: window.globalAcctType, email: window.globalAcctEmail };
        }
        for (let i = 0; i < window.authEntries.length; i++)
            if (window.authEntries[i].id === id) return window.authEntries[i];
        return { label: id, type: "account", email: "" };
    }
    // ◇ auto-follow · 🔑 key ·  account
    function authGlyph() {
        if (window.authSel === "auto") return "◇";
        return window.authEntry().type === "key" ? "" : "";
    }
    function authLabel() {
        let e = window.authEntry();
        let lbl = e.label || "auto";
        // disambiguate the two Pro accounts by their email local-part
        if (e.type !== "key" && e.email && e.email.indexOf("@") > 0)
            lbl += " · " + e.email.split("@")[0];
        return lbl;
    }

    // --- slash command / skill suggestions ---
    Process {
        id: suggLoader
        running: false
        command: ["python3", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/claude/suggest.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                let builtins = [
                    { name: "/help", desc: "command reference", kind: "local", group: "Session", icon: "" },
                    { name: "/clear", desc: "start a new chat", kind: "local", group: "Session", icon: "" },
                    { name: "/retry", desc: "regenerate last reply", kind: "local", group: "Session", icon: "" },
                    { name: "/stop", desc: "abort current stream", kind: "local", group: "Session", icon: "" },
                    { name: "/copy", desc: "copy last reply", kind: "local", group: "Session", icon: "" },
                    { name: "/export", desc: "save chat → markdown", kind: "local", group: "Session", icon: "" },
                    { name: "/cd", desc: "set working directory", kind: "local", group: "Navigation", icon: "" },
                    { name: "/cwd", desc: "show working directory", kind: "local", group: "Navigation", icon: "" },
                    { name: "/mode", desc: "set mode ask·auto·plan", kind: "local", group: "Mode", icon: "" },
                    { name: "/model", desc: "set or show the model", kind: "local", group: "Mode", icon: "" },
                    { name: "/auth", desc: "switch account", kind: "local", group: "Mode", icon: "" },
                    { name: "/pin", desc: "pin last card to panel", kind: "local", group: "Cards", icon: "" },
                    { name: "/cards", desc: "toggle pinned panel", kind: "local", group: "Cards", icon: "" },
                    { name: "/accent", desc: "set card accent color", kind: "local", group: "Cards", icon: "" },
                    { name: "/shot", desc: "screenshot → attach", kind: "local", group: "Capture", icon: "" },
                    { name: "/rec", desc: "record screen", kind: "local", group: "Capture", icon: "" }
                ];
                let parsed = [];
                try { parsed = JSON.parse(this.text.trim() || "[]"); } catch (e) {}
                window.allSugg = builtins.concat(parsed);
            }
        }
    }

    function updateSugg() {
        let t = input.text;
        if (window.busy || t.charAt(0) !== "/") {
            window.suggMatches = []; window.suggOpen = false; return;
        }
        let m = [];
        if (t.toLowerCase().indexOf("/model ") === 0) {
            // suggest model names after "/model "
            let arg = t.slice(7).trim().toLowerCase();
            for (let i = 0; i < window.modelOptions.length; i++) {
                let mo = window.modelOptions[i];
                let nm = mo.id === "" ? "default" : mo.id;
                if (nm.toLowerCase().indexOf(arg) === 0)
                    m.push({ name: "/model " + nm, label: nm, desc: mo.desc, kind: "model" });
            }
        } else {
            if (t.indexOf(" ") >= 0) { window.suggMatches = []; window.suggOpen = false; return; }
            let q = t.toLowerCase();
            for (let i = 0; i < window.allSugg.length; i++) {
                if (window.allSugg[i].name.toLowerCase().indexOf(q) === 0) m.push(window.allSugg[i]);
            }
        }
        window.suggMatches = m.slice(0, 9);
        window.suggIndex = 0;
        window.suggOpen = window.suggMatches.length > 0;
    }

    function acceptSugg(i) {
        if (i < 0 || i >= window.suggMatches.length) return;
        input.text = window.suggMatches[i].name + " ";
        input.cursorPosition = input.text.length;
        window.suggMatches = []; window.suggOpen = false;
    }

    // --- answer an AskUserQuestion / plan card ---
    function answerAsk(rowIdx, label, kind) {
        if (window.busy) return;
        if (rowIdx >= 0 && rowIdx < chatModel.count) {
            chatModel.remove(rowIdx);
            window.saveChat(); // force immediate save
        }
        if (kind === "plan" && window.agentMode === "plan") {
            // approving a plan means "go do it" — drop to AUTO so the agent can
            // actually execute. staying in plan left it unable to act on its own plan.
            window.agentMode = "auto"; window.saveMode(); window.stopAgent();
            window.sysMsg("Plan approved → AUTO mode, executing.");
        }
        chatModel.append({ role: "user", text: label, lang: "", ok: true, result: "", ts: Date.now() });
        window.scheduleSave();
        window.busy = true; window.streamBuf = ""; window.fullBuf = "";
        window.turnCount++;
        window.pendingEcho.push(label);
        window.agentSend(label, "");
    }
    function sysMsg(t) {
        chatModel.append({ role: "meta", text: t, lang: "", ok: true, result: "", ts: Date.now() });
        window.scheduleSave();
        Qt.callLater(scrollToBottom);
    }

    // /help — render the command reference as a real grouped card, not a flat line
    function helpCard() {
        let spec = {
            title: "Commands",
            subtitle: "local commands run instantly · everything else passes to Claude",
            blocks: [
                { kind: "text", text: "NAVIGATION" },
                { kind: "rows", items: [
                    { icon: "", label: "/cd <path>", value: "set working dir" },
                    { icon: "", label: "/cwd", value: "show working dir" }
                ] },
                { kind: "text", text: "MODES   ⇧⇥ cycles ASK · AUTO · PLAN" },
                { kind: "rows", items: [
                    { icon: "", label: "/mode ask|auto|plan", value: "set mode" },
                    { icon: "", label: "/model <name>", value: "set model" },
                    { icon: "", label: "/auth <acct|key|auto>", value: "switch account" }
                ] },
                { kind: "text", text: "SESSION" },
                { kind: "rows", items: [
                    { icon: "", label: "/clear", value: "new chat" },
                    { icon: "", label: "/retry", value: "regenerate last reply" },
                    { icon: "", label: "/stop", value: "abort current stream" },
                    { icon: "", label: "/copy", value: "copy last reply" },
                    { icon: "", label: "/export", value: "save chat → markdown" }
                ] },
                { kind: "text", text: "CARDS & CAPTURE" },
                { kind: "rows", items: [
                    { icon: "", label: "/pin", value: "pin last card to panel" },
                    { icon: "", label: "/cards", value: "toggle pinned panel" },
                    { icon: "", label: "/accent <color>", value: "blue·mauve·green·peach·teal·red" },
                    { icon: "", label: "/shot", value: "screenshot → attach" },
                    { icon: "", label: "/rec [secs]", value: "record screen → ~/Videos" }
                ] },
                { kind: "text", text: "+ attaches a clipboard image · /commands & skills not listed pass through to Claude" }
            ]
        };
        chatModel.append({ role: "card", text: JSON.stringify(spec), lang: "", ok: true, result: "", ts: Date.now() });
        window.scheduleSave();
        Qt.callLater(scrollToBottom);
    }

    // --- pin a card to the persistent side panel (PinnedCards.qml), which keeps it
    // live/clickable independent of this chat window being open or closed. Pure toggle,
    // no chat message — same idiom as favoriting a clipboard item or pinning an app. ---
    property string pinnedCardsFile: Quickshell.env("HOME") + "/.cache/quickshell/claude/pinned_cards.json"
    Process { id: pinWriter; running: false }
    // shell "&"-backgrounding here didn't actually survive (the spawned quickshell
    // process kept dying with the parent job) — subprocess.Popen(start_new_session=True)
    // gives it a real new session/process-group. And the "already running?" check
    // can't be pgrep -f matching on "PinnedCards.qml" — this very checker's own argv
    // contains that exact substring (the path we're about to launch), so it always
    // matches itself and the spawn never actually happens. PID file instead.
    Process { id: pinPanelStarter; running: false
        command: ["python3", "-c",
            "import subprocess,sys,os\n" +
            "pidf = os.path.expanduser('~/.cache/quickshell/claude/pinned_panel.pid')\n" +
            "alive = False\n" +
            "try:\n" +
            "    pid = int(open(pidf).read().strip())\n" +
            "    os.kill(pid, 0)\n" +
            "    alive = True\n" +
            "except Exception:\n" +
            "    pass\n" +
            "if not alive:\n" +
            "    p = subprocess.Popen(['quickshell', '-p', sys.argv[1]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)\n" +
            "    os.makedirs(os.path.dirname(pidf), exist_ok=True)\n" +
            "    open(pidf, 'w').write(str(p.pid))\n",
            Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/PinnedCards.qml"] }

    // Same alive-check as pinPanelStarter, but only fires when there's
    // actually something saved to show — and called on every chat open, not
    // just on a fresh pin. Without this, the pinned-cards viewer process
    // (its own standalone `quickshell -p`, not autostarted anywhere) simply
    // doesn't exist after a reboot/full quickshell restart even though
    // pinned_cards.json still has entries on disk — nothing ever relaunched
    // the viewer for existing cards, only pinning a brand-new one did (as a
    // side effect of pinCard() below), so old pins stayed invisible until
    // the next pin.
    Process { id: pinPanelEnsurer; running: false
        command: ["python3", "-c",
            "import subprocess, sys, os, json\n" +
            "cardsf = sys.argv[2]\n" +
            "try:\n" +
            "    n = len(json.load(open(cardsf))) if os.path.exists(cardsf) else 0\n" +
            "except Exception:\n" +
            "    n = 0\n" +
            "if n == 0:\n" +
            "    sys.exit(0)\n" +
            "pidf = os.path.expanduser('~/.cache/quickshell/claude/pinned_panel.pid')\n" +
            "alive = False\n" +
            "try:\n" +
            "    pid = int(open(pidf).read().strip())\n" +
            "    os.kill(pid, 0)\n" +
            "    alive = True\n" +
            "except Exception:\n" +
            "    pass\n" +
            "if not alive:\n" +
            "    p = subprocess.Popen(['quickshell', '-p', sys.argv[1]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)\n" +
            "    os.makedirs(os.path.dirname(pidf), exist_ok=True)\n" +
            "    open(pidf, 'w').write(str(p.pid))\n",
            Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/PinnedCards.qml",
            window.pinnedCardsFile] }
    function ensurePinnedPanel() { pinPanelEnsurer.running = false; pinPanelEnsurer.running = true; }

    function pinCard(spec, id) {
        // dedup by title — re-pinning a card with the same title updates the existing
        // panel entry in place instead of piling up duplicates (mirrors qs_mcp.py's
        // _pin_card for agent-initiated pins)
        pinWriter.command = ["python3", "-c",
            "import sys,json,os\n" +
            "p=sys.argv[1]\n" +
            "spec=json.loads(sys.argv[2])\n" +
            "pid=int(sys.argv[3])\n" +
            "title=(spec.get('title') or '').strip().lower()\n" +
            "m=json.load(open(p)) if os.path.exists(p) else []\n" +
            "existing=next((e for e in m if title and (e.get('spec',{}).get('title') or '').strip().lower()==title), None)\n" +
            "if existing is not None:\n" +
            "    existing['spec']=spec\n" +
            "else:\n" +
            "    try:\n" +
            "        compact=bool(json.load(open(os.path.expanduser('~/.config/hypr/settings.json'))).get('pinCompactMode', True))\n" +
            "    except Exception:\n" +
            "        compact=True\n" +
            "    m.append({'id':pid,'spec':spec,'board':'Default','compact':compact})\n" +
            "os.makedirs(os.path.dirname(p), exist_ok=True)\n" +
            "json.dump(m, open(p+'.tmp','w'))\n" +
            "os.replace(p+'.tmp', p)\n",
            window.pinnedCardsFile, JSON.stringify(spec), "" + id];
        pinWriter.running = false; pinWriter.running = true;
        pinPanelStarter.running = false; pinPanelStarter.running = true;
    }
    function unpinCard(id) {
        pinWriter.command = ["python3", "-c",
            "import sys,json,os\n" +
            "p=sys.argv[1]\n" +
            "m=json.load(open(p)) if os.path.exists(p) else []\n" +
            "m=[x for x in m if x.get('id')!=int(sys.argv[2])]\n" +
            "json.dump(m, open(p+'.tmp','w'))\n" +
            "os.replace(p+'.tmp', p)\n",
            window.pinnedCardsFile, "" + id];
        pinWriter.running = false; pinWriter.running = true;
    }

    // --- context gathering ---
    Process {
        id: contextBuilder
        running: false
        command: ["bash", "-c",
            "w=$(hyprctl activewindow 2>/dev/null); " +
            "cls=$(echo \"$w\" | grep -oP 'class: \\K.*'); " +
            "ttl=$(echo \"$w\" | grep -oP 'title: \\K.*'); " +
            "clip=$(cliphist list 2>/dev/null | head -1 | cut -f2- | head -c 400); " +
            "echo \"Focused app: $cls — $ttl\"; echo \"Latest clipboard: $clip\"; " +
            "python3 ~/.config/hypr/scripts/quickshell/claude/inject_ctx.py 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: window.windowCtx = this.text.trim() }
    }
    // prefill the input from a proactive nudge handed off by the topbar dot
    Process {
        id: prefillReader
        running: false
        command: ["bash", "-c", "f=/tmp/qs_claude_prefill; if [ -s \"$f\" ]; then cat \"$f\"; rm -f \"$f\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let t = this.text.trim();
                if (t !== "") { input.text = t; input.cursorPosition = input.text.length; }
            }
        }
    }
    // screenshot handed off by screenshot_ask.sh's global keybind — same
    // one-shot file idiom as prefillReader above, but populates the image
    // attachment (window.attachPath) instead of the input text, so the user
    // types their own question against it exactly like the in-chat /shot
    // command already lets them do.
    Process {
        id: attachFileReader
        running: false
        command: ["bash", "-c", "f=/tmp/qs_claude_attach; if [ -s \"$f\" ]; then cat \"$f\"; rm -f \"$f\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = this.text.trim();
                if (p !== "") {
                    window.attachPath = p;
                    window.attachName = p.split("/").pop();
                    window.sysMsg("screenshot attached — type a prompt and send");
                }
            }
        }
    }
    Process {
        id: clipCtxReader
        running: false
        command: ["bash", "-c", "f='" + window.ctxFile + "'; if [ -f \"$f\" ]; then cat \"$f\"; rm -f \"$f\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let t = this.text.trim();
                if (t === "") { window.clipCtx = ""; window.clipSnippet = ""; return; }
                window.clipCtx = "The user is asking about this clipboard item:\n" + t;
                window.clipSnippet = t.replace(/\s+/g, " ").slice(0, 90);
            }
        }
    }

    function clearClip() { window.clipCtx = ""; window.clipSnippet = ""; }

    // --- image attachment (from clipboard) ---
    property string attachPath: ""
    property string attachName: ""
    function clearAttach() { window.attachPath = ""; window.attachName = ""; }

    Process {
        id: attachGrab
        running: false
        command: ["bash", "-c",
            "d=~/.cache/quickshell/claude; mkdir -p \"$d\"; " +
            "t=$(wl-paste --list-types 2>/dev/null); " +
            "if echo \"$t\" | grep -q '^image/png'; then f=\"$d/paste-$(date +%s).png\"; wl-paste -t image/png > \"$f\" && echo \"$f\"; " +
            "elif echo \"$t\" | grep -q '^image/'; then f=\"$d/paste-$(date +%s).img\"; wl-paste > \"$f\" && echo \"$f\"; " +
            "else echo ''; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = this.text.trim();
                if (p !== "") { window.attachPath = p; window.attachName = p.split("/").pop(); }
            }
        }
    }
    function attachFromClipboard() { attachGrab.running = false; attachGrab.running = true; }

    // ============================================================
    //  local slash-command helpers (run client-side, no round-trip)
    // ============================================================

    // /copy — last assistant reply → clipboard
    Process { id: clipCopy; running: false }
    function copyLast() {
        for (let i = chatModel.count - 1; i >= 0; i--) {
            let r = chatModel.get(i);
            if (r.role === "text" || r.role === "code") {
                clipCopy.command = ["bash", "-c", "printf '%s' \"$1\" | wl-copy", "bash", r.text];
                clipCopy.running = false; clipCopy.running = true;
                window.sysMsg("copied last reply to clipboard");
                return;
            }
        }
        window.sysMsg("nothing to copy yet");
    }

    // /pin — last rendered card → persistent side panel
    function pinLast() {
        for (let i = chatModel.count - 1; i >= 0; i--) {
            if (chatModel.get(i).role !== "card") continue;
            let spec = {};
            try { spec = JSON.parse(chatModel.get(i).text); } catch (e) { continue; }
            if (!spec.blocks && !spec.title) continue;
            if (window.cardHasApproval(spec)) {
                window.sysMsg("auth/approval card: not pinnable");
                return;
            }
            window.pinCard(spec, Date.now());
            window.sysMsg("pinned: " + (spec.title || "card"));
            return;
        }
        window.sysMsg("no card to pin");
    }
    // mirrors CardRenderer.hasApproval / qs_mcp._has_approval_block — one-shot auth &
    // approval cards (autopilot_decide, or open_url to Google consent) must stay bound
    // to the chat row that raised them, never detach to the side panel.
    function cardHasApproval(spec) {
        let blk = spec.blocks;
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

    // /export — chat → markdown file
    Process { id: chatExport; running: false
        stdout: StdioCollector { onStreamFinished: { let p = this.text.trim(); if (p) window.sysMsg("exported → " + p); } } }
    function exportChat() {
        let md = "# Claude chat — " + new Date().toLocaleString() + "\n\n";
        for (let i = 0; i < chatModel.count; i++) {
            let r = chatModel.get(i);
            if (r.role === "user") md += "**You:** " + r.text + "\n\n";
            else if (r.role === "text") md += r.text + "\n\n";
            else if (r.role === "code") md += "```" + (r.lang || "") + "\n" + r.text + "\n```\n\n";
            else if (r.role === "meta") md += "_" + r.text + "_\n\n";
            else if (r.role === "tool") md += "› `" + r.text + "`\n\n";
        }
        let path = "~/Documents/claude-chat-" + Date.now() + ".md";
        chatExport.command = ["bash", "-c", "p=\"$1\"; p=\"${p/#\\~/$HOME}\"; mkdir -p \"$(dirname \"$p\")\"; printf '%s' \"$2\" > \"$p\"; echo \"$p\"", "bash", path, md];
        chatExport.running = false; chatExport.running = true;
    }

    // /mode — set agent mode directly
    function setMode(m) {
        m = ("" + m).toLowerCase();
        if (["ask", "auto", "plan"].indexOf(m) < 0) { window.sysMsg("mode must be: ask · auto · plan"); return; }
        window.agentMode = m; window.saveMode(); window.stopAgent();
        window.sysMsg("mode → " + m.toUpperCase());
    }

    // /auth — switch account directly
    function setAuth(a) {
        let opts = ["auto"];
        for (let i = 0; i < window.authEntries.length; i++) opts.push(window.authEntries[i].id);
        if (opts.indexOf(a) < 0) { window.sysMsg("auth: " + opts.join(" · ")); return; }
        window.authSel = a; window.saveAuth(); window.stopAgent();
        window.sysMsg("auth → " + a);
    }

    // /accent — set card accent color (writes settings.json, hot-reloads)
    Process { id: accentSaver; running: false }
    function setAccent(c) {
        c = ("" + c).toLowerCase();
        let valid = ["blue", "mauve", "green", "peach", "teal", "red"];
        if (valid.indexOf(c) < 0) { window.sysMsg("accent must be: " + valid.join(" · ")); return; }
        accentSaver.command = ["python3", "-c",
            "import json,os,sys;p=os.path.expanduser('~/.config/hypr/settings.json');d=json.load(open(p)) if os.path.exists(p) else {};d['cardAccent']=sys.argv[1];json.dump(d,open(p,'w'),indent=2)",
            c];
        accentSaver.running = false; accentSaver.running = true;
        window.sysMsg("card accent → " + c);
    }

    // /cards — toggle the pinned side panel
    Process { id: cardsToggle; running: false
        stdout: StdioCollector { onStreamFinished: { let s = this.text.trim(); if (s) window.sysMsg(s); } } }
    function togglePanel() {
        cardsToggle.command = ["python3", "-c",
            "import subprocess,os,sys\n" +
            "pidf=os.path.expanduser('~/.cache/quickshell/claude/pinned_panel.pid')\n" +
            "alive=False;pid=0\n" +
            "try:\n pid=int(open(pidf).read().strip());os.kill(pid,0);alive=True\n" +
            "except Exception:\n pass\n" +
            "if alive:\n os.kill(pid,15);os.remove(pidf);print('pinned panel closed')\n" +
            "else:\n p=subprocess.Popen(['quickshell','-p',sys.argv[1]],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True);os.makedirs(os.path.dirname(pidf),exist_ok=True);open(pidf,'w').write(str(p.pid));print('pinned panel opened')\n",
            Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/PinnedCards.qml"];
        cardsToggle.running = false; cardsToggle.running = true;
    }

    // /shot — grim screenshot → attach for next message
    Process { id: shotGrab; running: false
        stdout: StdioCollector { onStreamFinished: {
            let p = this.text.trim();
            if (p !== "") { window.attachPath = p; window.attachName = p.split("/").pop(); window.sysMsg("screenshot attached — type a prompt and send"); }
            else window.sysMsg("screenshot failed");
        } } }
    function attachShot() {
        let f = "~/.cache/quickshell/claude/shot-" + Date.now() + ".png";
        shotGrab.command = ["bash", "-c", "f=\"$1\"; f=\"${f/#\\~/$HOME}\"; mkdir -p \"$(dirname \"$f\")\"; grim \"$f\" && echo \"$f\"", "bash", f];
        shotGrab.running = false; shotGrab.running = true;
    }

    // /rec [secs] — record the screen to ~/Videos
    Process { id: recProc; running: false
        stdout: StdioCollector { onStreamFinished: { let l = this.text.trim(); if (l) window.sysMsg(l); } } }
    function recordScreen(secs) {
        let s = secs > 0 ? secs : 8;
        let f = "~/Videos/claude-rec-" + Date.now() + ".mp4";
        window.sysMsg("recording " + s + "s…");
        recProc.command = ["bash", "-c",
            "f=\"$1\"; f=\"${f/#\\~/$HOME}\"; mkdir -p \"$(dirname \"$f\")\"; bash ~/.config/hypr/scripts/screenrec.sh \"$2\" \"$f\" full >/dev/null 2>&1; echo \"saved → $f\"",
            "bash", f, "" + s];
        recProc.running = false; recProc.running = true;
    }

    // --- chat model ---
    ListModel { id: chatModel }

    // --- persistence ---
    property bool loaded: false
    Process { id: chatSaver; running: false }
    Timer { id: saveDebounce; interval: 250; repeat: false; onTriggered: window.saveChat() }
    function scheduleSave() { saveDebounce.restart(); }

    function saveChat() {
        let rows = [];
        for (let i = 0; i < chatModel.count; i++) {
            let r = chatModel.get(i);
            rows.push({ role: r.role, text: r.text, lang: r.lang || "", ok: r.ok === undefined ? true : r.ok, result: r.result || "", ts: r.ts || 0 });
        }
        let payload = JSON.stringify({ sessionId: window.sessionId, turnCount: window.turnCount, messages: rows });
        chatSaver.command = ["python3", "-c",
            "import sys,os; os.makedirs(os.path.dirname(sys.argv[1]),exist_ok=True); open(sys.argv[1],'w').write(sys.argv[2])",
            window.chatFile, payload];
        chatSaver.running = false; chatSaver.running = true;
    }

    Process {
        id: chatLoader
        running: false
        command: ["bash", "-c", "cat '" + window.chatFile + "' 2>/dev/null || echo ''"]
        stdout: StdioCollector {
            onStreamFinished: {
                window.loaded = true;
                let t = this.text.trim();
                if (t === "") return;
                try {
                    let d = JSON.parse(t);
                    window.sessionId = d.sessionId || "";
                    window.turnCount = d.turnCount || 0;
                    chatModel.clear();
                    let msgs = d.messages || [];
                    for (let i = 0; i < msgs.length; i++) {
                        let m = msgs[i];
                        chatModel.append({ role: m.role, text: m.text || "", lang: m.lang || "", ok: m.ok === undefined ? true : m.ok, result: m.result || "", ts: m.ts || 0 });
                    }
                    Qt.callLater(scrollToBottom);
                } catch (e) {}
            }
        }
    }

    function parseSegments(md) {
        let segs = [];
        let re = /```([\w-]*)\n?([\s\S]*?)```/g;
        let last = 0, m;
        while ((m = re.exec(md)) !== null) {
            if (m.index > last) {
                let t = md.slice(last, m.index).trim();
                if (t) segs.push({ kind: "text", text: t });
            }
            segs.push({ kind: "code", lang: (m[1] || "").toLowerCase(), code: m[2].replace(/\n+$/, "") });
            last = re.lastIndex;
        }
        if (last < md.length) {
            let t = md.slice(last).trim();
            if (t) segs.push({ kind: "text", text: t });
        }
        return segs;
    }

    function flushStream() {
        if (window.fullBuf.trim() === "") { window.fullBuf = ""; window.streamBuf = ""; return; }
        let segs = parseSegments(window.fullBuf);
        for (let i = 0; i < segs.length; i++) {
            let sg = segs[i];
            if (sg.kind === "text")
                chatModel.append({ role: "text", text: sg.text, lang: "", ok: true, result: "", ts: Date.now() });
            else
                chatModel.append({ role: "code", text: sg.code, lang: sg.lang, ok: true, result: "", ts: Date.now() });
        }
        window.fullBuf = "";
        window.streamBuf = "";
        window.scheduleSave();
    }

    // --- live transcript reader: the persistent daemon owns the agent and
    //     streams newline-delimited JSON events to /tmp/qs_claude_stream.
    //     Tailing a file means turns keep running while this widget is closed. ---
    Process {
        id: agent
        running: false
        command: ["tail", "-n", "+1", "-F", "/tmp/qs_claude_stream"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (data) => { window.handleEvent(data); }
        }
    }

    function findCardRow(sid) {
        for (let i = chatModel.count - 1; i >= 0; i--) {
            let row = chatModel.get(i);
            if (row.role !== "card") continue;
            try { if (JSON.parse(row.text)._sid === sid) return i; } catch (e) {}
        }
        return -1;
    }

    function findCardRowByCardId(cardId) {
        for (let i = chatModel.count - 1; i >= 0; i--) {
            let row = chatModel.get(i);
            if (row.role !== "card") continue;
            try { if (JSON.parse(row.text).card_id === cardId) return i; } catch (e) {}
        }
        return -1;
    }

    // mirrors qs_mcp.py's _apply_block_ops — surgical block edits without resending the
    // whole spec, addressed by index or by {kind} for "the first block of this kind"
    function applyBlockOps(blocks, ops) {
        blocks = (blocks || []).slice();
        for (let i = 0; i < (ops || []).length; i++) {
            let op = ops[i];
            if (op.op === "insert") {
                let idx = op.index !== undefined ? op.index : blocks.length;
                blocks.splice(Math.max(0, Math.min(idx, blocks.length)), 0, op.block || {});
            } else if (op.op === "replace" || op.op === "remove") {
                let idx = op.index;
                if (idx === undefined && op.match && op.match.kind) {
                    idx = blocks.findIndex(b => b && b.kind === op.match.kind);
                    if (idx < 0) idx = undefined;
                }
                if (idx !== undefined && idx >= 0 && idx < blocks.length) {
                    if (op.op === "replace") blocks[idx] = op.block !== undefined ? op.block : blocks[idx];
                    else blocks.splice(idx, 1);
                }
            }
        }
        return blocks;
    }

    function hasSecretBlock(spec) {
        return (spec.blocks || []).some(b => b && b.kind === "secret");
    }

    function applyCardPatch(cardId, patch) {
        let idx = window.findCardRowByCardId(cardId);
        if (idx < 0) return;
        try {
            let spec = JSON.parse(chatModel.get(idx).text);
            // one-shot credential cards refuse any patch, same rule as the server side —
            // a patch could otherwise resurrect/re-target a field meant to fire once
            if (window.hasSecretBlock(spec)) return;
            if (patch.title !== undefined) spec.title = patch.title;
            if (patch.icon !== undefined) spec.icon = patch.icon;
            if (patch.glance !== undefined) spec.glance = patch.glance;
            if (patch.blocks !== undefined) spec.blocks = patch.blocks;
            if (patch.block_ops !== undefined) spec.blocks = window.applyBlockOps(spec.blocks, patch.block_ops);
            chatModel.setProperty(idx, "text", JSON.stringify(spec));
        } catch (e) {}
    }

    // a card_pin event can race ahead of (or behind) the card row it belongs to —
    // buffer by sid and apply whenever the row actually exists, instead of silently
    // dropping the pin_id and leaving the chat-side icon permanently out of sync.
    property var pendingPinIds: ({})
    function applyPendingPin(rowIdx, sid) {
        if (!(sid in window.pendingPinIds)) return;
        try {
            let spec = JSON.parse(chatModel.get(rowIdx).text);
            spec._pin_id = window.pendingPinIds[sid];
            chatModel.setProperty(rowIdx, "text", JSON.stringify(spec));
        } catch (e) {}
        delete window.pendingPinIds[sid];
    }

    function handleEvent(data) {
        let o;
        try { o = JSON.parse(data); } catch (e) { return; }
        if (o.t === "ready") {
            window.agentReady = true;
            window.sendConfig(); // daemon resets to ASK on (re)start — push real mode/model
            window.flushQueue();
        } else if (o.t === "session") {
            window.sessionId = o.id;
        } else if (o.t === "user") {
            let idx = window.pendingEcho.indexOf(o.d || "");
            if (idx >= 0) {
                window.pendingEcho.splice(idx, 1);   // already shown locally — skip
            } else {
                window.flushStream();
                chatModel.append({ role: "user", text: o.d || "", lang: "", ok: true, result: "", ts: Date.now() });
                window.turnCount = Math.max(window.turnCount, 1);
            }
        } else if (o.t === "text") {
            window.fullBuf += o.d;
        } else if (o.t === "tool") {
            window.flushStream();
            chatModel.append({ role: "tool", text: o.summary || "", lang: o.name, ok: true, result: "", ts: Date.now() });
        } else if (o.t === "tool_result") {
            for (let i = chatModel.count - 1; i >= 0; i--) {
                if (chatModel.get(i).role === "tool") {
                    chatModel.setProperty(i, "result", o.d);
                    chatModel.setProperty(i, "ok", o.ok);
                    break;
                }
            }
        } else if (o.t === "ask") {
            window.flushStream();
            // auto mode: skip plan cards (daemon should auto-approve, not ask)
            if (o.kind === "plan" && window.agentMode === "auto") {
                window.sysMsg("(auto-approved plan, executing)");
                return;
            }
            chatModel.append({ role: "ask", text: JSON.stringify(o.questions || []),
                lang: o.kind || "question", ok: true, result: o.plan || "", ts: Date.now() });
        } else if (o.t === "card_start") {
            window.flushStream();
            chatModel.append({ role: "card", text: JSON.stringify({ _sid: o.sid }),
                lang: "", ok: true, result: "", ts: Date.now() });
            window.applyPendingPin(chatModel.count - 1, o.sid);
        } else if (o.t === "card_update") {
            let spec = o.input || {};
            if (typeof spec.blocks === "string") { try { spec.blocks = JSON.parse(spec.blocks); } catch(e) { spec.blocks = []; } }
            spec._sid = o.sid;
            // already-resolved one-shot approval card replayed on reconnect — drop the
            // placeholder card_start row and skip re-adding it. card_id is usually absent
            // on approval cards (see CardRenderer.send's dismiss handling), so check the
            // _sid fallback too — same key CardRenderer suppresses under.
            if (window.isCardSuppressed(spec.card_id) || window.isCardSuppressed(spec._sid)) {
                let ph = window.findCardRow(o.sid);
                if (ph >= 0) chatModel.remove(ph);
                return;
            }
            let found = window.findCardRow(o.sid);
            // dedup: same card_id already exists at a different sid (agent retried after ToolSearch) —
            // update the original row in-place, remove the new placeholder created by card_start
            if (found < 0 && spec.card_id) {
                let prior = window.findCardRowByCardId(spec.card_id);
                if (prior >= 0) {
                    let newRow = window.findCardRow(o.sid);
                    chatModel.setProperty(prior, "text", JSON.stringify(spec));
                    if (newRow >= 0 && newRow !== prior) chatModel.remove(newRow);
                    found = prior;
                }
            }
            if (found >= 0) chatModel.setProperty(found, "text", JSON.stringify(spec));
            else { window.flushStream(); chatModel.append({ role: "card", text: JSON.stringify(spec),
                lang: "", ok: true, result: "", ts: Date.now() }); found = chatModel.count - 1; }
            window.applyPendingPin(found, o.sid);
        } else if (o.t === "card_pin") {
            // the tool *call* args (what the card renders from) never carry a pin_id —
            // it's assigned server-side and only shows up in the tool *result*, so merge
            // it in after the fact to keep the chat-side pin icon truthful. The row may
            // not exist yet (this can race ahead of card_start/card_update) — buffer it.
            window.pendingPinIds[o.sid] = o.pin_id;
            let row2 = window.findCardRow(o.sid);
            if (row2 >= 0) window.applyPendingPin(row2, o.sid);
        } else if (o.t === "card_patch") {
            window.applyCardPatch(o.card_id || "", o.patch || {});
        } else if (o.t === "card") {
            window.flushStream();
            chatModel.append({ role: "card", text: JSON.stringify(o.input || {}),
                lang: "", ok: true, result: "", ts: Date.now() });
        } else if (o.t === "meta") {
            window.flushStream();
            let kt = (n) => n >= 1000 ? (n / 1000).toFixed(1) + "k" : ("" + n);
            let parts = [];
            if (o.model) parts.push(o.model);
            if (o.in || o.out) parts.push(kt(o.in || 0) + "→" + kt(o.out || 0) + " tok");
            if (o.ms) parts.push((o.ms / 1000).toFixed(1) + "s");
            chatModel.append({ role: "meta", text: parts.join("  ·  "), lang: "", ok: true, result: "", ts: Date.now() });
        } else if (o.t === "error") {
            window.flushStream();
            chatModel.append({ role: "error", text: o.d, lang: "", ok: false, result: "", ts: Date.now() });
        } else if (o.t === "turn" || o.t === "done") {
            window.flushStream();
            window.busy = false;
        }
        Qt.callLater(scrollToBottom);
    }

    // --- daemon control (file/FIFO IPC, survives widget close) ---
    Process { id: daemonStarter; running: false
        command: ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/claude/claude_daemon.sh"] }
    Process { id: fifoWriter; running: false }

    function ensureDaemon() { daemonStarter.running = false; daemonStarter.running = true; }

    function daemonSend(obj) {
        fifoWriter.command = ["bash", "-c", "printf '%s\\n' \"$1\" > /tmp/qs_claude_in", "_", JSON.stringify(obj)];
        fifoWriter.running = false; fifoWriter.running = true;
    }

    function sendConfig() {
        window.daemonSend({ cmd: "config", mode: window.agentMode, model: window.modelName,
            auth: window.authSel, workdir: window.workDir });
    }

    // daemon owns the real busy state; resync on (re)open so a turn still
    // running in the background keeps the input locked instead of letting a
    // second message slip in.
    Process {
        id: statusReader
        running: false
        command: ["cat", "/tmp/qs_claude_status"]
        stdout: StdioCollector {
            onStreamFinished: { window.busy = (this.text.trim() === "busy"); }
        }
    }
    // daemon status is the source of truth; poll while the widget is open so
    // replaying the transcript can't desync the busy lock (and an unlock after
    // a background-finished turn lands promptly).
    Timer {
        interval: 1000; repeat: true
        running: window.visible
        onTriggered: { statusReader.running = false; statusReader.running = true; }
    }

    // (re)attach: rebuild chat from the transcript, then follow it live.
    // guarded so the onCompleted + onVisibleChanged pair can't replay twice.
    function startReader() {
        if (agent.running) return;
        chatModel.clear();
        window.fullBuf = "";
        window.streamBuf = "";
        window.pendingEcho = [];
        statusReader.running = false; statusReader.running = true;
        agent.running = true;
    }

    function ensureAgent() {
        window.ensureDaemon();
        if (!agent.running) window.startReader();
    }

    function flushQueue() {
        while (window.pendingMsgs.length > 0) {
            let m = window.pendingMsgs.shift();
            window.daemonSend({ text: m.text, context: m.context });
        }
    }

    function agentSend(text, ctx) {
        window.pendingMsgs.push({ text: text, context: ctx });
        window.ensureAgent();
        window.flushQueue();
        Qt.callLater(scrollToBottom);
    }

    // push current settings to the daemon; it respawns the worker (resuming the
    // session) only if mode/model/auth/workdir actually changed. Called by the setters.
    function stopAgent() { window.sendConfig(); }

    function send(q) {
        if (window.busy) return;
        let t = q.trim();
        if (t === "" && window.attachPath === "") return;

        // local slash commands
        if (t.charAt(0) === "/") {
            let cp = t.split(/\s+/);
            let cmd = cp[0].toLowerCase();
            if (cmd === "/clear") { window.newChat(); return; }
            if (cmd === "/help") { window.helpCard(); return; }
            if (cmd === "/retry") { window.regenerateLast(); return; }
            if (cmd === "/stop") { window.cancel(); window.sysMsg("stopped"); return; }
            if (cmd === "/copy") { window.copyLast(); return; }
            if (cmd === "/export") { window.exportChat(); return; }
            if (cmd === "/pin") { window.pinLast(); return; }
            if (cmd === "/cards") { window.togglePanel(); return; }
            if (cmd === "/shot") { window.attachShot(); return; }
            if (cmd === "/rec") { window.recordScreen(cp.length > 1 ? parseInt(cp[1]) : 0); return; }
            if (cmd === "/cwd") { window.sysMsg("cwd: " + (window.workDir || "home (default)")); return; }
            if (cmd === "/mode") {
                if (cp.length < 2) window.sysMsg("mode: " + window.agentMode.toUpperCase() + " — /mode ask|auto|plan");
                else window.setMode(cp[1]);
                return;
            }
            if (cmd === "/auth") {
                if (cp.length < 2) window.sysMsg("auth: " + window.authSel + " — /auth <acct|key|auto>");
                else window.setAuth(cp[1]);
                return;
            }
            if (cmd === "/accent") {
                if (cp.length < 2) window.sysMsg("/accent blue|mauve|green|peach|teal|red");
                else window.setAccent(cp[1]);
                return;
            }
            if (cmd === "/cd") {
                if (cp.length < 2) window.sysMsg("cwd: " + (window.workDir || "home (default)"));
                else window.setWorkDir(cp.slice(1).join(" "));
                return;
            }
            if (cmd === "/model") {
                if (cp.length < 2) {
                    let names = window.modelOptions.map(o => o.id === "" ? "default" : o.id).join(" · ");
                    window.sysMsg("model: " + (window.modelName || "default (proxy)") + "\navailable: " + names);
                } else {
                    let arg = cp.slice(1).join(" ");
                    if (arg.toLowerCase() === "default") arg = "";
                    window.setModel(arg);
                    window.sysMsg("model set → " + (window.modelName || "default (proxy)"));
                }
                return;
            }
            // any other /command or skill falls through to Claude
        }

        let label = t === "" && window.attachPath !== "" ? ("🖼 " + window.attachName) : q;
        chatModel.append({ role: "user", text: label, lang: "", ok: true, result: "", ts: Date.now() });
        window.scheduleSave();
        let parts = [];
        if (window.turnCount === 0 && window.contextStr !== "") parts.push(window.contextStr);
        if (window.attachPath !== "") parts.push("[attached image: " + window.attachPath + "] Use the Read tool to view this image, then answer.");
        let ctx = parts.join("\n\n");
        window.clearClip();
        window.clearAttach();
        window.turnCount++;
        window.busy = true; window.streamBuf = ""; window.fullBuf = "";
        let sentText = q.trim() === "" ? "Describe this image." : q;
        window.pendingEcho.push(sentText);
        window.agentSend(sentText, ctx);
    }

    function regenerateLast() {
        if (window.busy) return;
        let ui = -1;
        for (let i = chatModel.count - 1; i >= 0; i--) {
            if (chatModel.get(i).role === "user") { ui = i; break; }
        }
        if (ui < 0) return;
        let q = chatModel.get(ui).text;
        while (chatModel.count > ui + 1) chatModel.remove(chatModel.count - 1);
        window.scheduleSave();
        window.busy = true; window.streamBuf = ""; window.fullBuf = "";
        window.pendingEcho.push(q);
        window.agentSend(q, "");
    }

    // --- run a code card's command, capture output into a result row ---
    Process {
        id: runner
        running: false
        property int targetIdx: -1
        stdout: StdioCollector {
            onStreamFinished: {
                if (runner.targetIdx >= 0)
                    chatModel.setProperty(runner.targetIdx, "result", this.text.trim() || "(no output)");
                window.scheduleSave();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "" && runner.targetIdx >= 0) {
                    let cur = chatModel.get(runner.targetIdx).result || "";
                    chatModel.setProperty(runner.targetIdx, "result", (cur + "\n" + this.text.trim()).trim());
                    chatModel.setProperty(runner.targetIdx, "ok", false);
                }
                window.scheduleSave();
            }
        }
    }
    function runCommand(cmd) {
        chatModel.append({ role: "tool", text: cmd, lang: "Run", ok: true, result: "…", ts: Date.now() });
        window.scheduleSave();
        runner.targetIdx = chatModel.count - 1;
        runner.command = ["bash", "-c", cmd];
        runner.running = false; runner.running = true;
        Qt.callLater(scrollToBottom);
    }

    function cancel() {
        window.daemonSend({ cmd: "stop" });
        window.flushStream();
        window.busy = false;
    }

    function newChat() {
        window.daemonSend({ cmd: "clear" });
        chatModel.clear();
        window.sessionId = "";
        window.turnCount = 0;
        window.streamBuf = "";
        window.fullBuf = "";
        window.busy = false;
        window.clearClip();
    }

    function scrollToBottom() { chatView.positionViewAtEnd(); }

    // ============================================================
    //  history / resume — lists real Claude Code project transcripts
    //  (~/.claude/projects/<escaped-cwd>/*.jsonl) rather than keeping a
    //  parallel index, so it can't drift from what `claude --resume` itself
    //  sees. Picking one hands the id to the daemon (config cmd, session
    //  field) which respawns agent.py with --resume <id> — a genuine resume,
    //  not just a cosmetic transcript replay.
    // ============================================================
    property bool historyOpen: false
    property var sessionList: []

    function agoText(ts) {
        let d = Math.max(0, Math.floor(Date.now() / 1000 - ts));
        if (d < 60) return d + "s ago";
        if (d < 3600) return Math.floor(d / 60) + "m ago";
        if (d < 86400) return Math.floor(d / 3600) + "h ago";
        return Math.floor(d / 86400) + "d ago";
    }

    Process {
        id: sessionListLoader
        running: false
        command: ["python3", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/claude/list_sessions.py", window.workDir]
        stdout: StdioCollector {
            onStreamFinished: {
                try { window.sessionList = JSON.parse(this.text.trim()) || []; }
                catch (e) { window.sessionList = []; }
            }
        }
    }

    function toggleHistory() {
        window.historyOpen = !window.historyOpen;
        if (window.historyOpen) { sessionListLoader.running = false; sessionListLoader.running = true; }
    }

    Process {
        id: sessionContentLoader
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let msgs = [];
                try { msgs = JSON.parse(this.text.trim()) || []; } catch (e) {}
                chatModel.clear();
                for (let i = 0; i < msgs.length; i++) {
                    chatModel.append({ role: msgs[i].role, text: msgs[i].text || "", lang: "", ok: true, result: "", ts: 0 });
                }
                Qt.callLater(scrollToBottom);
                window.saveChat();
            }
        }
    }

    function resumeSession(sid) {
        window.historyOpen = false;
        if (sid === window.sessionId) return;   // already on it
        window.sessionId = sid;
        window.turnCount = 0;
        window.busy = false;
        window.clearClip();
        sessionContentLoader.command = ["python3", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/claude/load_session.py", window.workDir, sid];
        sessionContentLoader.running = false; sessionContentLoader.running = true;
        window.daemonSend({ cmd: "config", mode: window.agentMode, model: window.modelName,
            auth: window.authSel, workdir: window.workDir, session: sid });
    }

    // --- focus / lifecycle ---
    Timer { id: focusTimer; interval: 50; running: true; repeat: false; onTriggered: input.forceActiveFocus() }

    Component.onCompleted: {
        clipCtxReader.running = true;
        contextBuilder.running = true;
        suggLoader.running = true;
        prefillReader.running = true;
        attachFileReader.running = true;
        window.ensurePinnedPanel();
        window.ensureDaemon();
        window.sendConfig();
        window.startReader();
    }

    Connections {
        target: window
        function onVisibleChanged() {
            if (window.visible) {
                focusTimer.restart();
                introPhaseAnim.restart();
                window.clearClip();
                clipCtxReader.running = true;
                contextBuilder.running = true;
                input.text = "";
                prefillReader.running = true;
        attachFileReader.running = true;
        window.ensurePinnedPanel();
                window.ensureDaemon();
                window.sendConfig();
                window.startReader();
            }
            // when hidden: leave the daemon running so turns finish in the background
        }
    }

    Keys.onEscapePressed: {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
        event.accepted = true;
    }

    property real globalOrbitAngle: 0
    // range is 4π, not 2π: the blobs apply *2 and *1.5 multipliers, so only a 4π period
    // lands every term back on a whole sin/cos cycle (1.5*4π = 6π) — a 2π loop snaps the
    // 1.5 blob from cos(3π)=-1 back to cos(0)=1 on wrap. duration doubled to keep speed.
    NumberAnimation on globalOrbitAngle { from: 0; to: Math.PI * 4; duration: 180000; loops: Animation.Infinite; running: true }
    property real introPhase: 0
    NumberAnimation on introPhase { id: introPhaseAnim; from: 0; to: 1; duration: 600; easing.type: Easing.OutExpo; running: true }

    // =========================================================================
    Rectangle {
        id: mainBg
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        radius: window.s(18)
        color: Qt.rgba(window.base.r, window.base.g, window.base.b, 1.0)
        border.color: window.surface1
        border.width: 1
        clip: true

        property bool hasAttach: window.clipSnippet !== "" || window.attachPath !== ""
        property real chromeH: window.s(54) + window.s(62) + 2 + (mainBg.hasAttach ? window.s(48) : 0)
        property real chatContentH: chatView.contentHeight + window.s(32)
        height: Math.min(chromeH + chatContentH, parent.height)
        Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutExpo } }

        transform: Translate { y: (window.introPhase - 1) * window.s(40) }
        opacity: window.introPhase

        // ambient blobs (subtle)
        Rectangle {
            width: parent.width * 0.55; height: width; radius: width / 2
            x: (parent.width / 2 - width / 2) + Math.cos(window.globalOrbitAngle * 2) * window.s(150)
            y: (parent.height / 2 - height / 2) + Math.sin(window.globalOrbitAngle * 2) * window.s(110)
            opacity: 0.035; color: window.mauve
            Behavior on color { ColorAnimation { duration: 1000 } }
        }
        Rectangle {
            width: parent.width * 0.45; height: width; radius: width / 2
            x: (parent.width / 2 - width / 2) + Math.sin(window.globalOrbitAngle * 1.5) * window.s(-160)
            y: (parent.height / 2 - height / 2) + Math.cos(window.globalOrbitAngle * 1.5) * window.s(-110)
            opacity: 0.03; color: window.blue
            Behavior on color { ColorAnimation { duration: 1000 } }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ---------------- HEADER ----------------
            Rectangle {
                id: headerBar
                Layout.fillWidth: true
                Layout.preferredHeight: window.s(54)
                color: "transparent"
                z: 50

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: window.s(22)
                    anchors.rightMargin: window.s(16)
                    spacing: window.s(12)

                    Rectangle {
                        Layout.preferredWidth: window.s(10); Layout.preferredHeight: window.s(10)
                        radius: width / 2
                        color: window.busy ? window.peach : window.mauve
                        SequentialAnimation on opacity {
                            running: window.busy; loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 600 } NumberAnimation { to: 1.0; duration: 600 }
                        }
                    }
                    Text {
                        text: window.modelName.indexOf("glm") === 0 ? "GLM" : "Claude"
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(15); font.weight: Font.Bold; font.letterSpacing: window.s(0.5)
                        color: window.text
                    }
                    Text {
                        visible: window.modelName !== ""
                        Layout.alignment: Qt.AlignVCenter
                        text: window.modelName.replace("claude-", "")
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.overlay0
                        elide: Text.ElideRight; Layout.maximumWidth: window.s(160)
                    }
                    Item { Layout.fillWidth: true }

                    // history / resume
                    Rectangle {
                        Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(30)
                        radius: window.s(8)
                        color: (historyMa.containsMouse || window.historyOpen) ? window.surface1 : "transparent"
                        scale: historyMa.pressed ? 0.9 : 1.0
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                        Text {
                            anchors.centerIn: parent; text: ""
                            font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(15)
                            color: window.historyOpen ? window.mauve : window.subtext0
                        }
                        MouseArea { id: historyMa; anchors.fill: parent; hoverEnabled: true; onClicked: window.toggleHistory() }
                    }

                    // new chat
                    Rectangle {
                        Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(30)
                        radius: window.s(8)
                        visible: chatModel.count > 0
                        color: newMa.containsMouse ? window.surface1 : "transparent"
                        scale: newMa.pressed ? 0.9 : 1.0
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                        Text {
                            anchors.centerIn: parent; text: "✕"
                            font.family: "JetBrains Mono"; font.pixelSize: window.s(14); color: window.subtext0
                        }
                        MouseArea { id: newMa; anchors.fill: parent; hoverEnabled: true; onClicked: window.newChat() }
                    }

                    // work-timer pill (commitment countdown; click to release)
                    Rectangle {
                        id: timerPill
                        visible: window.timerActive
                        Layout.preferredHeight: window.s(30)
                        Layout.preferredWidth: timerRow.width + window.s(20)
                        radius: window.s(15)
                        scale: timerMa.pressed ? 0.94 : 1.0
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                        color: Qt.rgba(window.peach.r, window.peach.g, window.peach.b, 0.16)
                        border.width: 1
                        border.color: Qt.rgba(window.peach.r, window.peach.g, window.peach.b, 0.45)
                        SequentialAnimation on border.color {
                            running: timerPill.visible; loops: Animation.Infinite
                            ColorAnimation { to: Qt.rgba(window.peach.r, window.peach.g, window.peach.b, 0.85); duration: 900 }
                            ColorAnimation { to: Qt.rgba(window.peach.r, window.peach.g, window.peach.b, 0.45); duration: 900 }
                        }
                        Row {
                            id: timerRow
                            anchors.centerIn: parent
                            spacing: window.s(6)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: ""
                                font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(12)
                                color: window.peach
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: window.timerLabel
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(11); font.weight: Font.Bold
                                color: window.peach
                            }
                        }
                        MouseArea {
                            id: timerMa
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                timerCanceller.command = ["rm", "-f", "/tmp/qs_worktimer.json"];
                                timerCanceller.running = true;
                                window.timerDeadline = 0;
                                window.recomputeTimer();
                            }
                        }

                        // hover tooltip — styled like the systray right-click menu
                        Rectangle {
                            id: timerTip
                            visible: timerMa.containsMouse
                            anchors.top: parent.bottom
                            anchors.right: parent.right
                            anchors.topMargin: window.s(6)
                            width: Math.max(window.s(120), timerTipCol.implicitWidth + window.s(20))
                            height: timerTipCol.implicitHeight + window.s(12)
                            radius: window.s(10)
                            color: Qt.rgba(window.base.r, window.base.g, window.base.b, 0.97)
                            border.width: 1
                            border.color: Qt.rgba(window.text.r, window.text.g, window.text.b, 0.1)
                            z: 1000
                            opacity: visible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }

                            ColumnLayout {
                                id: timerTipCol
                                anchors.centerIn: parent
                                spacing: window.s(3)
                                Text {
                                    visible: window.timerTask !== ""
                                    Layout.alignment: Qt.AlignLeft
                                    text: window.timerTask
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(12)
                                    color: window.text
                                    elide: Text.ElideRight; Layout.maximumWidth: window.s(260)
                                }
                                Text {
                                    Layout.alignment: Qt.AlignLeft
                                    text: "click to release"
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(11)
                                    color: window.subtext0
                                }
                            }
                        }
                    }

                    // auth pill (account / key / auto-follow-global)
                    Rectangle {
                        Layout.preferredHeight: window.s(30)
                        Layout.preferredWidth: authRow.width + window.s(20)
                        radius: window.s(15)
                        scale: authMa.pressed ? 0.94 : 1.0
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                        color: Qt.rgba(window.blue.r, window.blue.g, window.blue.b, 0.14)
                        border.width: 1
                        border.color: Qt.rgba(window.blue.r, window.blue.g, window.blue.b, 0.40)
                        Row {
                            id: authRow
                            anchors.centerIn: parent
                            spacing: window.s(6)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: window.authGlyph()
                                font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(11)
                                color: window.blue
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: window.authLabel()
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(11); font.weight: Font.Bold
                                color: window.blue
                            }
                        }
                        MouseArea { id: authMa; anchors.fill: parent; hoverEnabled: true; onClicked: window.cycleAuth() }
                    }

                    // mode pill
                    Rectangle {
                        Layout.preferredHeight: window.s(30)
                        Layout.preferredWidth: modeRow.width + window.s(20)
                        radius: window.s(15)
                        scale: modeMa.pressed ? 0.94 : 1.0
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                        color: Qt.rgba(window.modeColor.r, window.modeColor.g, window.modeColor.b, 0.16)
                        border.width: 1
                        border.color: Qt.rgba(window.modeColor.r, window.modeColor.g, window.modeColor.b, 0.45)
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Behavior on border.color { ColorAnimation { duration: 200 } }

                        Row {
                            id: modeRow
                            anchors.centerIn: parent
                            spacing: window.s(6)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: window.modeIcon
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(11)
                                color: window.modeColor
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: window.modeLabel
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(11); font.weight: Font.Bold
                                color: window.modeColor
                            }
                        }
                        MouseArea { id: modeMa; anchors.fill: parent; hoverEnabled: true; onClicked: window.toggleMode() }
                    }
                }

                // ---- history / resume dropdown ----
                Rectangle {
                    id: historyPanel
                    visible: window.historyOpen
                    anchors.top: parent.bottom
                    anchors.left: parent.left
                    anchors.leftMargin: window.s(22)
                    anchors.topMargin: window.s(2)
                    width: window.s(340)
                    height: Math.min(window.s(320), historyCol.implicitHeight + window.s(16))
                    radius: window.s(12)
                    color: window.mantle
                    border.width: 1; border.color: window.surface1
                    clip: true
                    z: 200

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: window.s(8)
                        contentWidth: width
                        contentHeight: historyCol.implicitHeight
                        clip: true
                        Column {
                            id: historyCol
                            width: parent.width
                            spacing: window.s(2)
                            Text {
                                visible: window.sessionList.length === 0
                                text: "no past sessions here yet"
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(11)
                                color: window.overlay0
                                width: parent.width
                                padding: window.s(8)
                            }
                            Repeater {
                                model: window.sessionList
                                delegate: Rectangle {
                                    width: historyCol.width
                                    height: entryCol.implicitHeight + window.s(14)
                                    radius: window.s(8)
                                    color: modelData.id === window.sessionId
                                        ? Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.18)
                                        : (entryMa.containsMouse ? window.surface0 : "transparent")
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Column {
                                        id: entryCol
                                        anchors.left: parent.left; anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.margins: window.s(7)
                                        spacing: window.s(2)
                                        Text {
                                            width: parent.width
                                            text: modelData.title
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(11); font.weight: Font.Bold
                                            color: window.text
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                        Text {
                                            text: window.agoText(modelData.ts) + (modelData.id === window.sessionId ? "  ·  current" : "")
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(9)
                                            color: window.overlay0
                                        }
                                    }
                                    MouseArea {
                                        id: entryMa
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: window.resumeSession(modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5) }

            // ---------------- CHAT ----------------
            ListView {
                id: chatView
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: window.s(16)
                clip: true
                model: chatModel
                spacing: window.s(12)
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 4000

                onCountChanged: Qt.callLater(positionViewAtEnd)

                add: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "y"; from: window.s(8); duration: 0 }
                    }
                }
                displaced: Transition {
                    NumberAnimation { properties: "y"; duration: 250; easing.type: Easing.OutCubic }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle { implicitWidth: window.s(4); radius: window.s(2); color: window.surface2; opacity: 0.5 }
                }

                // empty state
                header: Item {
                    width: chatView.width
                    height: chatModel.count === 0 ? window.s(86) : 0
                    visible: chatModel.count === 0
                    Column {
                        anchors.centerIn: parent
                        spacing: window.s(8)
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "❯"
                            font.family: "JetBrains Mono"; font.pixelSize: window.s(30); font.weight: Font.Bold; color: window.surface2
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: window.agentMode === "plan" ? "Plan mode — I think it through, don't act"
                                : (window.agentMode === "auto" ? "Auto agent — I can act on your machine" : "Ask me anything")
                            font.family: "JetBrains Mono"; font.pixelSize: window.s(12); color: window.overlay0
                        }
                    }
                }

                footer: Item {
                    width: chatView.width - window.s(12)
                    visible: window.busy || window.streamBuf !== ""
                    height: !visible ? 0 : (window.streamBuf !== "" ? liveText.implicitHeight + window.s(10) : window.s(30))

                    // pre-stream "thinking" indicator — shimmer line OR pulsing dots (guide setting)
                    Item {
                        id: thinkShimmer
                        visible: window.busy && window.streamBuf === "" && window.thinkingStyle === "shimmer"
                        x: window.s(16); y: window.s(11)
                        width: window.s(190); height: window.s(8)
                        clip: true
                        Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5) }
                        Rectangle {
                            width: window.s(70); height: parent.height * 2; y: -parent.height / 2; rotation: 12
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 0.5; color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.30) }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                            NumberAnimation on x { running: thinkShimmer.visible; loops: Animation.Infinite; from: -window.s(80); to: thinkShimmer.width + window.s(80); duration: 1150; easing.type: Easing.InOutSine }
                        }
                    }

                    Row {
                        id: thinkingDots
                        x: window.s(16); y: window.s(8)
                        spacing: window.s(5)
                        visible: window.busy && window.streamBuf === "" && window.thinkingStyle === "dots"
                        Repeater {
                            model: 3
                            Rectangle {
                                width: window.s(7); height: window.s(7); radius: width / 2
                                color: window.mauve
                                SequentialAnimation on opacity {
                                    running: thinkingDots.visible
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 180 }
                                    NumberAnimation { to: 0.25; duration: 420; easing.type: Easing.InOutQuad }
                                    NumberAnimation { to: 1.0;  duration: 420; easing.type: Easing.InOutQuad }
                                    PauseAnimation { duration: (2 - index) * 180 }
                                }
                            }
                        }
                    }

                    // accent bar beside streaming text
                    Rectangle {
                        x: 0; y: window.s(13)
                        width: window.s(3); height: Math.max(window.s(8), liveText.implicitHeight - window.s(6))
                        radius: window.s(2)
                        color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.45)
                        visible: window.streamBuf !== ""
                    }
                    TextEdit {
                        id: liveText
                        x: window.s(16)
                        y: window.s(10)
                        width: (parent.width - window.s(16)) * 0.96
                        visible: window.streamBuf !== ""
                        text: window.streamBuf + (window.busy && window.caretOn ? " ▋" : "")
                        textFormat: TextEdit.PlainText
                        color: window.text
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(14)
                        wrapMode: TextEdit.Wrap
                        readOnly: true
                        onTextChanged: Qt.callLater(chatView.positionViewAtEnd)
                    }
                }

                delegate: Item {
                    width: chatView.width - window.s(12)
                    height: (loader.item && (model.role !== "ask" || model.ok !== false)) ? loader.item.implicitHeight : 0
                    visible: model.role !== "ask" || model.ok !== false
                    z: loader.item && loader.item["dropdownExpandH"] > 0 ? 10 : 0
                    onHeightChanged: if (model.role === "card") Qt.callLater(chatView.forceLayout)

                    Loader {
                        id: loader
                        width: parent.width
                        property string dText: model.text
                        property string dLang: model.lang
                        property string dResult: model.result === undefined ? "" : model.result
                        property bool dOk: model.ok
                        property double dTs: model.ts === undefined ? 0 : model.ts
                        property int dIndex: model.index
                        // entrance: fade + slide up, cards also scale-in — motion connecting
                        // bottom→list, "calm not bouncy". OutExpo settle, OutBack for the card pop.
                        property bool appeared: false
                        opacity: appeared ? 1 : 0
                        transformOrigin: Item.Bottom
                        scale: (model.role === "card") ? (appeared ? 1 : 0.97) : 1
                        transform: Translate { y: loader.appeared ? 0 : window.s(12); Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutExpo } } }
                        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                        Behavior on scale { NumberAnimation { duration: 360; easing.type: Easing.OutBack } }
                        Component.onCompleted: appearTimer.start()
                        Timer { id: appearTimer; interval: 16; onTriggered: loader.appeared = true }
                        sourceComponent: {
                            switch (model.role) {
                                case "user":  return userMsg;
                                case "code":  return codeCard;
                                case "tool":  return toolCard;
                                case "ask":   return askCard;
                                case "card":  return cardCard;
                                case "error": return errorMsg;
                                case "meta":  return metaMsg;
                                default:      return textMsg;
                            }
                        }
                    }
                }
            }

            // ---------------- CLIP CHIP ----------------
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: window.s(16)
                Layout.rightMargin: window.s(16)
                Layout.preferredHeight: mainBg.hasAttach ? window.s(40) : 0
                Layout.bottomMargin: mainBg.hasAttach ? window.s(6) : 0
                visible: Layout.preferredHeight > 1
                clip: true
                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutExpo } }
                radius: window.s(10)
                color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.10)
                border.width: 1; border.color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.30)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: window.s(12)
                    anchors.rightMargin: window.s(8)
                    spacing: window.s(8)
                    Text {
                        text: window.attachPath !== "" ? "🖼" : "✂"
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(13); color: window.mauve
                    }
                    Text {
                        text: window.attachPath !== "" ? "image" : "clipboard"
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(10); font.weight: Font.Bold; color: window.mauve
                    }
                    Text {
                        Layout.fillWidth: true
                        text: window.attachPath !== "" ? window.attachName : ("\"" + window.clipSnippet + (window.clipSnippet.length >= 90 ? "…" : "") + "\"")
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(12); color: window.subtext0
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        Layout.preferredWidth: window.s(24); Layout.preferredHeight: window.s(24)
                        radius: window.s(7)
                        color: clipX.containsMouse ? Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.2) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text { anchors.centerIn: parent; text: "✕"; font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.subtext0 }
                        MouseArea { id: clipX; anchors.fill: parent; hoverEnabled: true; onClicked: { window.clearClip(); window.clearAttach(); } }
                    }
                }
            }

            // ---------------- INPUT ----------------
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5) }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: window.s(62)
                color: "transparent"

                // composer pill: glass surface that lifts + glows on focus
                Rectangle {
                    id: composerPill
                    anchors.fill: parent
                    anchors.topMargin: window.s(5); anchors.bottomMargin: window.s(9)
                    anchors.leftMargin: window.s(12); anchors.rightMargin: window.s(12)
                    radius: window.s(13)
                    color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, input.activeFocus ? 0.6 : 0.38)
                    border.width: 1
                    border.color: input.activeFocus
                        ? Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.5)
                        : Qt.rgba(window.surface2.r, window.surface2.g, window.surface2.b, 0.6)
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Behavior on border.color { ColorAnimation { duration: 180 } }
                    // focus glow halo
                    Rectangle {
                        anchors.fill: parent; anchors.margins: -window.s(2)
                        radius: parent.radius + window.s(2); z: -1
                        color: "transparent"
                        border.width: window.s(2)
                        border.color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.16)
                        opacity: input.activeFocus ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                    // top specular edge
                    Rectangle {
                        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                        anchors.leftMargin: window.s(12); anchors.rightMargin: window.s(12); height: 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.08) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: window.s(26)
                    anchors.rightMargin: window.s(24)
                    spacing: window.s(12)

                    Text {
                        text: "❯"
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(16); font.weight: Font.Bold
                        color: input.activeFocus ? window.mauve : window.subtext0
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    TextField {
                        id: input
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        background: Item {}
                        color: window.text
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(15)
                        placeholderText: window.busy ? "Working…" : (window.clipSnippet !== "" ? "Ask about the clipboard item…" : "Ask Claude…  (Shift+Tab: mode)")
                        placeholderTextColor: window.subtext0
                        verticalAlignment: TextInput.AlignVCenter
                        focus: true
                        enabled: !window.busy

                        onTextChanged: window.updateSugg()

                        Keys.onReturnPressed: {
                            if (window.suggOpen) { window.acceptSugg(window.suggIndex); event.accepted = true; return; }
                            window.send(text); text = ""; event.accepted = true;
                        }
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                                window.toggleMode(); event.accepted = true;
                            } else if (window.suggOpen && event.key === Qt.Key_Tab) {
                                window.acceptSugg(window.suggIndex); event.accepted = true;
                            } else if (window.suggOpen && event.key === Qt.Key_Up) {
                                window.suggIndex = Math.max(0, window.suggIndex - 1); event.accepted = true;
                            } else if (window.suggOpen && event.key === Qt.Key_Down) {
                                window.suggIndex = Math.min(window.suggMatches.length - 1, window.suggIndex + 1); event.accepted = true;
                            }
                        }
                        Keys.onEscapePressed: {
                            if (window.suggOpen) { window.suggMatches = []; window.suggOpen = false; event.accepted = true; return; }
                            Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
                            event.accepted = true;
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: window.s(34); Layout.preferredHeight: window.s(34)
                        radius: window.s(10)
                        scale: attachMa.pressed ? 0.9 : 1.0
                        opacity: window.busy ? 0.4 : 1.0
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                        color: attachMa.containsMouse ? window.surface2 : window.surface1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text { anchors.centerIn: parent; text: "+"; font.family: "JetBrains Mono"; font.pixelSize: window.s(18); color: window.subtext0 }
                        MouseArea { id: attachMa; anchors.fill: parent; hoverEnabled: true; enabled: !window.busy; onClicked: window.attachFromClipboard() }
                    }

                    Rectangle {
                        id: sendBtn
                        // success tick flashes briefly when a message commits — tactile
                        // acknowledgment the send landed.
                        property bool justSent: false
                        Layout.preferredWidth: window.s(36); Layout.preferredHeight: window.s(36)
                        radius: window.s(10)
                        scale: sendMa.pressed ? 0.9 : 1.0
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                        color: sendBtn.justSent ? window.green
                            : (window.busy
                                ? (sendMa.containsMouse ? window.red : Qt.rgba(window.red.r, window.red.g, window.red.b, 0.7))
                                : ((input.text.trim() !== "" || window.attachPath !== "")
                                    ? (sendMa.containsMouse ? window.mauve : Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.7))
                                    : window.surface1))
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            id: sendGlyph
                            anchors.centerIn: parent
                            text: sendBtn.justSent ? "✓" : (window.busy ? "✕" : "→")
                            font.family: "JetBrains Mono"; font.pixelSize: window.s(17); font.weight: Font.Bold
                            color: sendBtn.justSent ? window.crust
                                : (window.busy ? window.crust
                                    : ((input.text.trim() !== "" || window.attachPath !== "") ? window.crust : window.overlay0))
                            transformOrigin: Item.Center
                        }
                        Timer { id: sentTickTimer; interval: 650; onTriggered: sendBtn.justSent = false }
                        SequentialAnimation {
                            id: sentPop
                            NumberAnimation { target: sendGlyph; property: "scale"; from: 0.4; to: 1.0; duration: 280; easing.type: Easing.OutBack }
                        }
                        MouseArea {
                            id: sendMa; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                if (window.busy) { window.cancel(); }
                                else if (input.text.trim() !== "" || window.attachPath !== "") {
                                    window.send(input.text); input.text = "";
                                    sendBtn.justSent = true; sentPop.restart(); sentTickTimer.restart();
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---------------- SLASH SUGGESTIONS (grouped command palette) ----------------
        Rectangle {
            id: suggBox
            visible: window.suggOpen
            z: 100
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: window.s(16)
            anchors.rightMargin: window.s(16)
            anchors.bottomMargin: window.s(66)
            height: suggCol.implicitHeight + window.s(12)
            radius: window.s(14)
            color: Qt.rgba(window.mantle.r, window.mantle.g, window.mantle.b, 0.98)
            border.width: 1; border.color: Qt.rgba(window.surface2.r, window.surface2.g, window.surface2.b, 0.8)
            clip: true
            // soft glass sheen
            Rectangle {
                anchors.fill: parent; radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.04) }
                    GradientStop { position: 0.4; color: "transparent" }
                }
            }
            Rectangle {
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: window.s(12); anchors.rightMargin: window.s(12); height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.10) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Column {
                id: suggCol
                width: parent.width
                y: window.s(6)
                Repeater {
                    model: window.suggMatches
                    delegate: Column {
                        required property int index
                        required property var modelData
                        width: suggCol.width
                        property bool showHeader: (modelData.group || "") !== ""
                            && (index === 0 || (window.suggMatches[index - 1].group || "") !== modelData.group)

                        Item {
                            width: parent.width; height: showHeader ? window.s(22) : 0
                            visible: showHeader
                            Text {
                                anchors.left: parent.left; anchors.leftMargin: window.s(16)
                                anchors.bottom: parent.bottom; anchors.bottomMargin: window.s(3)
                                text: ("" + (modelData.group || "")).toUpperCase()
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(9); font.weight: Font.Bold; font.letterSpacing: window.s(1)
                                color: window.overlay0
                            }
                        }

                        Rectangle {
                            width: parent.width; height: window.s(36)
                            radius: window.s(8)
                            color: index === window.suggIndex
                                ? Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.16) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            // selection accent bar
                            Rectangle {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                width: window.s(3); height: parent.height * 0.55; radius: width / 2
                                color: window.mauve
                                visible: index === window.suggIndex
                            }
                            Row {
                                anchors.left: parent.left; anchors.leftMargin: window.s(14)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: window.s(10)
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: window.s(16)
                                    text: modelData.icon || "›"
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13)
                                    color: index === window.suggIndex ? window.mauve : window.subtext0
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(13); font.weight: Font.Bold
                                    color: window.mauve
                                }
                            }
                            Text {
                                anchors.right: chip.left; anchors.rightMargin: window.s(10)
                                anchors.left: parent.left; anchors.leftMargin: window.s(180)
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: modelData.desc
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(11)
                                color: window.subtext0; elide: Text.ElideRight
                            }
                            // kbd chip on the selected row
                            Rectangle {
                                id: chip
                                anchors.right: parent.right; anchors.rightMargin: window.s(12)
                                anchors.verticalCenter: parent.verticalCenter
                                width: window.s(18); height: window.s(18); radius: window.s(5)
                                visible: index === window.suggIndex
                                color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.18)
                                Text {
                                    anchors.centerIn: parent; text: "↵"
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.mauve
                                }
                            }
                            MouseArea {
                                anchors.fill: parent; hoverEnabled: true
                                onEntered: window.suggIndex = index
                                onClicked: window.acceptSugg(index)
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // DELEGATE COMPONENTS
    // =========================================================================
    Component {
        id: userMsg
        Item {
            id: r
            property string mText: parent ? parent.dText : ""
            property double mTs: parent ? parent.dTs : 0
            implicitHeight: bubble.height + stamp.height + window.s(3)
            Rectangle {
                id: bubble
                anchors.right: parent.right
                width: Math.min(uText.implicitWidth + window.s(28), r.width * 0.82)
                height: uText.implicitHeight + window.s(20)
                radius: window.s(13)
                color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.16)
                border.width: 1; border.color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.3)
                Text {
                    id: uText
                    anchors.fill: parent; anchors.margins: window.s(12); anchors.leftMargin: window.s(14); anchors.rightMargin: window.s(14)
                    text: r.mText
                    font.family: "JetBrains Mono"; font.pixelSize: window.s(14)
                    color: window.text; wrapMode: Text.Wrap
                }
            }
            Text {
                id: stamp
                anchors.right: parent.right
                anchors.top: bubble.bottom
                anchors.topMargin: window.s(3)
                text: window.relTime(r.mTs)
                font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay0
                opacity: 0.7
            }
        }
    }

    Component {
        id: textMsg
        Item {
            id: r
            property string mText: parent ? parent.dText : ""
            property bool hov: hovMa.containsMouse || cMa.containsMouse || rgMa.containsMouse
            implicitHeight: tText.implicitHeight
            Rectangle {
                x: 0; y: window.s(3)
                width: window.s(3); height: Math.max(window.s(8), tText.implicitHeight - window.s(6))
                radius: window.s(2)
                color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.45)
            }
            TextEdit {
                id: tText
                x: window.s(16)
                width: (r.width - window.s(16)) * 0.96
                text: r.mText
                textFormat: TextEdit.MarkdownText
                color: window.text
                font.family: "JetBrains Mono"; font.pixelSize: window.s(14)
                wrapMode: TextEdit.Wrap
                readOnly: true; selectByMouse: true
                selectionColor: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.3)
                selectedTextColor: window.text
            }
            // hover-tracking (NoButton so text selection still works)
            MouseArea {
                id: hovMa
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                hoverEnabled: true
            }
            Row {
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: window.s(4)
                opacity: r.hov ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Rectangle {
                    id: tapCopy
                    property bool copied: false
                    width: window.s(26); height: window.s(22); radius: window.s(6)
                    color: tapCopy.copied ? Qt.rgba(window.green.r, window.green.g, window.green.b, 0.3)
                                          : (cMa.containsMouse ? window.surface2 : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8))
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Timer { id: tapCopyReset; interval: 1200; onTriggered: tapCopy.copied = false }
                    Text { anchors.centerIn: parent; text: tapCopy.copied ? "✓" : "⧉"; font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: tapCopy.copied ? window.green : window.subtext0 }
                    MouseArea { id: cMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Quickshell.execDetached(["wl-copy", "--", r.mText]); tapCopy.copied = true; tapCopyReset.restart(); } }
                }
                Rectangle {
                    width: window.s(26); height: window.s(22); radius: window.s(6)
                    color: rgMa.containsMouse ? window.surface2 : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text { anchors.centerIn: parent; text: "↻"; font.family: "JetBrains Mono"; font.pixelSize: window.s(12); color: window.subtext0 }
                    MouseArea { id: rgMa; anchors.fill: parent; hoverEnabled: true; onClicked: window.regenerateLast() }
                }
            }
        }
    }

    Component {
        id: metaMsg
        Item {
            id: r
            property string mText: parent ? parent.dText : ""
            implicitHeight: mt.implicitHeight + window.s(2)
            Text {
                id: mt
                anchors.right: parent.right
                anchors.rightMargin: window.s(2)
                text: r.mText
                font.family: "JetBrains Mono"; font.pixelSize: window.s(10)
                color: window.overlay0; opacity: 0.65
            }
        }
    }

    Component {
        id: errorMsg
        Item {
            id: r
            property string mText: parent ? parent.dText : ""
            implicitHeight: eb.height
            Rectangle {
                id: eb
                width: r.width * 0.92
                height: eText.implicitHeight + window.s(20)
                radius: window.s(10)
                color: Qt.rgba(window.red.r, window.red.g, window.red.b, 0.12)
                border.width: 1; border.color: Qt.rgba(window.red.r, window.red.g, window.red.b, 0.35)
                Text {
                    id: eText
                    anchors.fill: parent; anchors.margins: window.s(12)
                    text: "▲  " + r.mText
                    font.family: "JetBrains Mono"; font.pixelSize: window.s(13)
                    color: window.red; wrapMode: Text.Wrap
                }
            }
        }
    }

    Component {
        id: codeCard
        Item {
            id: r
            property string mText: parent ? parent.dText : ""
            property string mLang: parent ? parent.dLang : ""
            implicitHeight: card.height
            Rectangle {
                id: card
                width: parent.width
                height: cardCol.implicitHeight + window.s(2)
                radius: window.s(10)
                color: Qt.rgba(window.crust.r, window.crust.g, window.crust.b, 1.0)
                border.width: 1; border.color: window.surface1
                clip: true

                Column {
                    id: cardCol
                    width: parent.width
                    spacing: 0

                    Rectangle {
                        width: parent.width; height: window.s(34)
                        color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.5)
                        radius: window.s(10)
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: window.s(10); color: parent.color }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: window.s(14); anchors.verticalCenter: parent.verticalCenter
                            text: r.mLang === "" ? "code" : r.mLang
                            font.family: "JetBrains Mono"; font.pixelSize: window.s(11); font.weight: Font.Bold
                            color: window.overlay0
                        }
                        Row {
                            anchors.right: parent.right; anchors.rightMargin: window.s(10); anchors.verticalCenter: parent.verticalCenter
                            spacing: window.s(6)
                            Rectangle {
                                id: copyBtn
                                property bool copied: false
                                width: copyRow.width + window.s(16); height: window.s(24); radius: window.s(7)
                                color: copyBtn.copied ? Qt.rgba(window.green.r, window.green.g, window.green.b, 0.3)
                                                      : (copyMa.containsMouse ? window.surface2 : window.surface1)
                                scale: copyMa.pressed ? 0.92 : 1.0
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }
                                Timer { id: copyResetTimer; interval: 1200; onTriggered: copyBtn.copied = false }
                                Row {
                                    id: copyRow; anchors.centerIn: parent; spacing: window.s(5)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: copyBtn.copied ? "✓" : "⧉"; font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: copyBtn.copied ? window.green : window.subtext0 }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: copyBtn.copied ? "Copied!" : "Copy"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: copyBtn.copied ? window.green : window.subtext0 }
                                }
                                MouseArea {
                                    id: copyMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { Quickshell.execDetached(["wl-copy", "--", r.mText]); copyBtn.copied = true; copyResetTimer.restart(); }
                                }
                            }
                            Rectangle {
                                visible: window.isRunnable(r.mLang)
                                width: runRow.width + window.s(16); height: window.s(24); radius: window.s(7)
                                color: runMa.containsMouse ? window.green : Qt.rgba(window.green.r, window.green.g, window.green.b, 0.25)
                                scale: runMa.pressed ? 0.92 : 1.0
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }
                                Row {
                                    id: runRow; anchors.centerIn: parent; spacing: window.s(5)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "▶"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: runMa.containsMouse ? window.crust : window.green }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Run"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); font.weight: Font.Bold; color: runMa.containsMouse ? window.crust : window.green }
                                }
                                MouseArea { id: runMa; anchors.fill: parent; hoverEnabled: true; onClicked: window.runCommand(r.mText) }
                            }
                        }
                    }
                    TextEdit {
                        width: parent.width - window.s(28)
                        x: window.s(14)
                        topPadding: window.s(10); bottomPadding: window.s(12)
                        text: window.highlight(r.mText, r.mLang)
                        textFormat: TextEdit.RichText
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(13)
                        color: window.text; wrapMode: TextEdit.NoWrap
                        readOnly: true; selectByMouse: true
                        selectionColor: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.3)
                    }
                }
            }
        }
    }

    Component {
        id: toolCard
        Item {
            id: rootTool
            implicitHeight: tcard.height
            property bool expanded: false
            property string mText: parent ? parent.dText : ""
            property string mLang: parent ? parent.dLang : ""
            property string mResult: parent ? parent.dResult : ""
            property bool mOk: parent ? parent.dOk : true
            Rectangle {
                id: tcard
                width: parent.width
                height: tcol.implicitHeight + window.s(20)
                radius: window.s(10)
                color: Qt.rgba(window.blue.r, window.blue.g, window.blue.b, 0.08)
                border.width: 1; border.color: Qt.rgba(window.blue.r, window.blue.g, window.blue.b, 0.25)

                Column {
                    id: tcol
                    width: parent.width - window.s(28)
                    x: window.s(14); y: window.s(10)
                    spacing: window.s(6)

                    Row {
                        spacing: window.s(8)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: rootTool.mOk ? "▸" : "▲"
                            font.family: "JetBrains Mono"; font.pixelSize: window.s(12)
                            color: rootTool.mOk ? window.blue : window.red
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: rootTool.mLang
                            font.family: "JetBrains Mono"; font.pixelSize: window.s(11); font.weight: Font.Bold
                            color: window.blue
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: tcard.width - window.s(90)
                            text: rootTool.mText
                            font.family: "JetBrains Mono"; font.pixelSize: window.s(12)
                            color: window.subtext0; elide: Text.ElideRight
                        }
                    }
                    Text {
                        visible: rootTool.mResult !== ""
                        width: parent.width
                        text: rootTool.mResult
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(11)
                        color: window.overlay0; wrapMode: Text.Wrap
                        maximumLineCount: rootTool.expanded ? 9999 : 6
                        elide: Text.ElideRight
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: rootTool.expanded = !rootTool.expanded
                }
            }
        }
    }

    Component {
        id: askCard
        Item {
            id: r
            property string mText: parent ? parent.dText : "[]"
            property string mKind: parent ? parent.dLang : "question"
            property string mPlan: parent ? parent.dResult : ""
            property bool mOpen: parent ? parent.dOk : true
            property int mIdx: parent ? parent.dIndex : -1
            property var qs: {
                try { return JSON.parse(r.mText); } catch (e) { return []; }
            }
            implicitHeight: r.mOpen ? card.height : 0
            visible: r.mOpen
            Rectangle {
                id: card
                width: parent.width
                height: r.mOpen ? (askCol.implicitHeight + window.s(24)) : 0
                radius: window.s(12)
                color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.08)
                border.width: 1; border.color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.30)

                Column {
                    id: askCol
                    width: parent.width - window.s(32)
                    x: window.s(16); y: window.s(12)
                    spacing: window.s(10)

                    Row {
                        spacing: window.s(8)
                        Text {
                            text: r.mKind === "plan" ? "◐" : "?"
                            font.family: "JetBrains Mono"; font.pixelSize: window.s(13); font.weight: Font.Bold
                            color: window.mauve
                        }
                        Text {
                            text: r.mKind === "plan" ? "PLAN — review before running" : "Claude is asking"
                            font.family: "JetBrains Mono"; font.pixelSize: window.s(11); font.weight: Font.Bold
                            color: window.mauve
                        }
                    }

                    // plan body
                    TextEdit {
                        visible: r.mKind === "plan" && r.mPlan !== ""
                        width: parent.width
                        text: r.mPlan
                        textFormat: TextEdit.MarkdownText
                        color: window.text
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(13)
                        wrapMode: TextEdit.Wrap; readOnly: true; selectByMouse: true
                        selectionColor: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.3)
                    }

                    // plan approve / keep-planning buttons
                    Row {
                        visible: r.mKind === "plan"
                        spacing: window.s(8)
                        Repeater {
                            model: [
                                { label: "Approve & run", send: "Approved — implement the plan now.", kind: "plan", accent: true },
                                { label: "Keep planning", send: "Keep refining the plan, don't implement yet.", kind: "question", accent: false }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                height: window.s(30)
                                width: planLbl.implicitWidth + window.s(24)
                                radius: window.s(8)
                                opacity: r.mOpen ? 1 : 0.4
                                color: modelData.accent
                                    ? (planMa.containsMouse ? window.mauve : Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.7))
                                    : (planMa.containsMouse ? window.surface2 : window.surface1)
                                scale: planMa.pressed ? 0.94 : 1.0
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }
                                Text {
                                    id: planLbl
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(12); font.weight: Font.Bold
                                    color: modelData.accent ? window.crust : window.subtext0
                                }
                                MouseArea {
                                    id: planMa; anchors.fill: parent; hoverEnabled: true
                                    enabled: r.mOpen
                                    onClicked: window.answerAsk(r.mIdx, modelData.send, modelData.kind)
                                }
                            }
                        }
                    }

                    // question blocks
                    Repeater {
                        model: r.mKind === "plan" ? [] : r.qs
                        delegate: Column {
                            required property var modelData
                            width: askCol.width
                            spacing: window.s(6)
                            Text {
                                width: parent.width
                                text: modelData.question || ""
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(13)
                                color: window.text; wrapMode: Text.Wrap
                            }
                            Flow {
                                width: parent.width
                                spacing: window.s(8)
                                Repeater {
                                    model: modelData.options || []
                                    delegate: Rectangle {
                                        required property var modelData
                                        height: window.s(32)
                                        width: Math.min(optLbl.implicitWidth + window.s(24), askCol.width)
                                        radius: window.s(8)
                                        opacity: r.mOpen ? 1 : 0.4
                                        color: optMa.containsMouse ? window.mauve : Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.16)
                                        border.width: 1; border.color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.35)
                                        scale: optMa.pressed ? 0.94 : 1.0
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }
                                        Text {
                                            id: optLbl
                                            anchors.centerIn: parent
                                            text: modelData.label || ""
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(12); font.weight: Font.Bold
                                            color: optMa.containsMouse ? window.crust : window.mauve
                                        }
                                        MouseArea {
                                            id: optMa; anchors.fill: parent; hoverEnabled: true
                                            enabled: r.mOpen
                                            onClicked: window.answerAsk(r.mIdx, modelData.label || "", "question")
                                        }
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
        id: cardCard
        CardRenderer {
            id: cr2
            spec: { try { return JSON.parse(parent ? parent.dText : "{}"); } catch (e) { return {}; } }
            sendPlain: function(text) {
                window.answerAsk(parent ? parent.dIndex : -1, text, "card");
            }
            // optimistic instant feedback, then re-verify against the actual file shortly
            // after — CardRenderer's own checkPinnedState() is the real source of truth
            // (handles dedup reassigning this title to a different id, or it having been
            // unpinned from the side panel since), this is just so the icon doesn't sit at
            // the old value for the ~200ms until that runs.
            onPinRequested: {
                if (cr2.pinId >= 0) { window.unpinCard(cr2.pinId); cr2.pinId = -1; }
                else { let id = Date.now(); window.pinCard(cr2.spec, id); cr2.pinId = id; }
                cr2.recheckSoon();
            }
            // popped spec carries the authored fields (title/icon/blocks/glance/card_id) from
            // before the last patch — merge over the current row so runtime-only fields like
            // _sid/_pin_id (not part of the popped snapshot) survive the revert
            onRevertRequested: (specJson) => {
                try {
                    let popped = JSON.parse(specJson);
                    let idx = parent ? parent.dIndex : -1;
                    if (idx < 0) return;
                    let cur = JSON.parse(parent.dText);
                    chatModel.setProperty(idx, "text", JSON.stringify(Object.assign({}, cur, popped)));
                } catch (e) {}
            }
            // one-shot approval/reauth card resolved — drop the row entirely so the
            // collapsed gap disappears, and record the card_id so a daemon stream
            // replay on reopen can't resurrect it (the row is gone from chat.json,
            // but the agent re-streams card_start/card_update on reconnect).
            onDismissRequested: (cardId) => {
                let idx = parent ? parent.dIndex : -1;
                if (idx >= 0 && idx < chatModel.count) {
                    chatModel.remove(idx);
                    window.saveChat();
                }
                if (cardId) window.suppressCard(cardId);
            }
        }
    }
}
