import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import Quickshell
import Quickshell._Window
import Quickshell.Io
import "./"

FloatingWindow {
    id: win
    title: "qs-scratchpad"
    implicitWidth: s(700)
    implicitHeight: s(500)
    color: "transparent"
    visible: cardVisible

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val) }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color text: _theme.text
    readonly property color overlay0: _theme.overlay0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color mauve: _theme.mauve
    readonly property color blue: _theme.blue
    readonly property color red: _theme.red

    // Custom-styled hover tooltip — replaces the default QML ToolTip (a
    // plain system-styled box that clashed with the rest of this window's
    // dark theme). Usage: drop one as a child of the button Rectangle,
    // `show: someMouseArea.containsMouse`.
    component ScratchTip: Rectangle {
        property string text: ""
        property bool show: false
        visible: opacity > 0.01
        opacity: show ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        anchors.top: parent.bottom; anchors.topMargin: win.s(6)
        anchors.horizontalCenter: parent.horizontalCenter
        width: tipText.implicitWidth + win.s(14); height: win.s(22)
        radius: win.s(6)
        color: win.base
        border.width: 1; border.color: win.surface2
        z: 200
        Text {
            id: tipText
            anchors.centerIn: parent
            text: parent.text
            font.family: "JetBrains Mono"; font.pixelSize: win.s(10)
            color: win.text
        }
    }

    readonly property string homeDir: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "")
    readonly property string savePath: win.homeDir + "/.local/share/qs_scratchpad.txt"
    readonly property string posPath:  win.homeDir + "/.local/share/qs_scratchpad_pos"

    property bool cardVisible: false
    property bool suppressSave: false
    property bool previewMode: false
    property bool showFind: false
    property int  findMatchCount: 0
    property real cardOpacity: 0.0

    onCardVisibleChanged: {
        if (cardVisible) {
            cardOpacity = 0.0
            posRestoreProc.running = true
            showAnim.start()
        } else {
            posSaveProc.running = true
            hideAnim.start()
        }
    }

    NumberAnimation {
        id: showAnim
        target: win; property: "cardOpacity"
        to: 1.0; duration: 400; easing.type: Easing.OutExpo
    }

    NumberAnimation {
        id: hideAnim
        target: win; property: "cardOpacity"
        to: 0.0; duration: 300; easing.type: Easing.InExpo
        onFinished: win.cardVisible = false
    }

    Component.onCompleted: textLoadProc.running = true

    // Restore saved position after window appears
    Process {
        id: posRestoreProc
        command: ["bash", "-c", "cat '" + win.posPath + "' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = this.text.trim().split(" ")
                if (parts.length >= 2 && !isNaN(parseInt(parts[0]))) {
                    posMoveTimer.savedX = parts[0]
                    posMoveTimer.savedY = parts[1]
                    posMoveTimer.start()
                }
            }
        }
    }

    Timer {
        id: posMoveTimer
        interval: 120
        property string savedX: ""
        property string savedY: ""
        onTriggered: Quickshell.execDetached(["bash", "-c",
            "hyprctl dispatch movewindowpixel 'exact " + savedX + " " + savedY + ",title:qs-scratchpad'"
        ])
    }

    // Save position on hide
    Process {
        id: posSaveProc
        command: ["bash", "-c",
            "hyprctl -j clients 2>/dev/null | python3 -c \"" +
            "import sys,json; data=json.load(sys.stdin); " +
            "w=[c for c in data if c.get('title')=='qs-scratchpad']; " +
            "print(w[0]['at'][0], w[0]['at'][1]) if w else print('')\" > '" + win.posPath + "'"
        ]
    }

    Process {
        id: textLoadProc
        command: ["bash", "-c", "cat '" + win.savePath + "' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                win.suppressSave = true
                noteArea.text = this.text
                win.suppressSave = false
            }
        }
    }

    function saveText() {
        Quickshell.execDetached(["python3", "-c",
            "import sys, os; os.makedirs(os.path.dirname(sys.argv[1]), exist_ok=True); open(sys.argv[1], 'w').write(sys.argv[2])",
            win.savePath, noteArea.text
        ])
    }

    Timer { id: saveDebounce; interval: 1000; onTriggered: win.saveText() }

    readonly property string obsidianScript: "/home/czeddaru/.config/hypr/scripts/quickshell/claude/save_to_obsidian.py"
    property string obsidianStatus: ""
    property bool obsidianPickerOpen: false
    property var obsidianFolders: []
    property string obsidianSelectedFolder: "Scratchpad"

    Process {
        id: obsidianListProc
        command: ["bash", "-c", "cat '" + win.savePath + "' 2>/dev/null | python3 " + win.obsidianScript + " --list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let r = JSON.parse(this.text.trim())
                    win.obsidianFolders = r.folders || []
                    win.obsidianSelectedFolder = r.suggested || "Scratchpad"
                } catch (e) {
                    win.obsidianFolders = []
                    win.obsidianSelectedFolder = "Scratchpad"
                }
            }
        }
    }

    Process {
        id: obsidianSaveProc
        command: ["python3", win.obsidianScript]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let r = JSON.parse(this.text.trim())
                    win.obsidianStatus = r.ok ? "saved ✓" : "failed"
                } catch (e) {
                    win.obsidianStatus = "failed"
                }
                obsidianStatusTimer.restart()
            }
        }
    }
    Timer { id: obsidianStatusTimer; interval: 2500; onTriggered: win.obsidianStatus = "" }

    // Opens the folder-picker popover with a live smart suggestion instead
    // of saving immediately — user picks a suggested/existing folder or
    // types a new one, per their ask for a "really good integration", not
    // a blind always-Scratchpad dump.
    function openObsidianPicker() {
        win.saveText()
        obsidianListProc.running = false
        obsidianListProc.running = true
        win.obsidianPickerOpen = true
    }

    function confirmObsidianSave(folder) {
        win.obsidianPickerOpen = false
        obsidianSaveProc.running = false
        obsidianSaveProc.command = ["python3", win.obsidianScript, win.savePath, "--folder", folder]
        obsidianSaveProc.running = true
    }

    readonly property string aiScript: "/home/czeddaru/.config/hypr/scripts/quickshell/claude/scratchpad_ai.py"
    readonly property string acFlagPath: win.homeDir + "/.local/share/qs_scratchpad_autocomplete"
    property bool showAi: false
    property bool aiBusy: false
    property string aiStatus: ""
    property string aiSnapshot: ""
    property bool aiHadSel: false
    property string aiUndoText: ""
    property bool aiCanUndo: false
    property bool autoComplete: false
    property string ghostText: ""
    property int ghostPos: -1
    property string ghostSnapshot: ""
    property bool ghostBusy: false
    property bool ghostManual: false

    readonly property var aiPresets: [
        { label: "clean up", instr: "Clean up this rough text: fix spelling, grammar and structure, turn it into clear, well-organized markdown notes. Keep all information." },
        { label: "summarize", instr: "If a target is given, replace it with a concise summary. Otherwise keep the note and add a short '## Summary' section at the end." },
        { label: "bullets", instr: "Turn it into concise, well-structured markdown bullet points. Keep all key facts." },
        { label: "fix grammar", instr: "Fix only spelling, grammar and punctuation. Change nothing else." },
        { label: "expand", instr: "Expand it with more detail and clear explanations in a student-notes style. Stay factual." },
        { label: "flashcards", instr: "Keep the content and append a '## Flashcards' section with Q: / A: pairs covering the key facts." }
    ]

    function openAi() {
        win.showAi = true
        win.showFind = false
        aiInput.forceActiveFocus()
    }

    function closeAi() {
        if (win.aiBusy) cancelAi()
        win.showAi = false
        noteArea.forceActiveFocus()
    }

    function runAi(instruction) {
        if (win.aiBusy || instruction.trim().length === 0) return
        win.clearGhost()
        win.aiSnapshot = noteArea.text
        win.aiHadSel = noteArea.selectionEnd > noteArea.selectionStart
        win.aiBusy = true
        win.aiStatus = "thinking…"
        aiStatusTimer.stop()
        aiEditProc.command = ["python3", win.aiScript, "edit", instruction, noteArea.text,
                              String(noteArea.selectionStart), String(noteArea.selectionEnd)]
        aiEditProc.running = true
    }

    function cancelAi() {
        win.aiBusy = false
        aiEditProc.running = false
        win.aiStatus = "cancelled"
        aiStatusTimer.restart()
    }

    function applyAi(raw) {
        if (!win.aiBusy) return
        win.aiBusy = false
        let r = null
        try { r = JSON.parse(raw.trim()) } catch (e) { r = { ok: false, error: "failed" } }
        if (!r.ok) {
            win.aiStatus = r.error || "failed"
        } else if (noteArea.text !== win.aiSnapshot) {
            win.aiStatus = "note changed, discarded"
        } else {
            win.aiUndoText = win.aiSnapshot
            noteArea.remove(r.start, r.end)
            noteArea.insert(r.start, r.replacement)
            if (win.aiHadSel) noteArea.select(r.start, r.start + r.replacement.length)
            else noteArea.deselect()
            win.aiCanUndo = true
            win.aiStatus = "done"
            aiInput.text = ""
        }
        aiStatusTimer.restart()
    }

    function undoAi() {
        if (!win.aiCanUndo) return
        noteArea.text = win.aiUndoText
        win.aiCanUndo = false
        win.aiStatus = "reverted"
        aiStatusTimer.restart()
    }

    function toggleAutoComplete() {
        win.autoComplete = !win.autoComplete
        if (!win.autoComplete) win.clearGhost()
        Quickshell.execDetached(["bash", "-c", "echo " + (win.autoComplete ? 1 : 0) + " > '" + win.acFlagPath + "'"])
    }

    function requestGhost(manual) {
        if (win.previewMode || win.aiBusy) return
        if (noteArea.selectionStart !== noteArea.selectionEnd) return
        let t = noteArea.text, pos = noteArea.cursorPosition
        if (!manual && pos < t.length && t.charAt(pos) !== "\n") return
        win.ghostText = ""
        win.ghostPos = pos
        win.ghostSnapshot = t
        win.ghostBusy = true
        win.ghostManual = manual
        ghostProc.running = false
        ghostProc.command = ["python3", win.aiScript, "complete", t.substring(0, pos), t.substring(pos), manual ? "manual" : "auto"]
        ghostProc.running = true
    }

    function applyGhost(raw) {
        if (!win.ghostBusy) return
        win.ghostBusy = false
        let r = null
        try { r = JSON.parse(raw.trim()) } catch (e) { return }
        if (!r.ok || !r.completion) return
        if (noteArea.text !== win.ghostSnapshot || noteArea.cursorPosition !== win.ghostPos) return
        win.ghostText = r.completion
    }

    function clearGhost() {
        if (win.ghostBusy) ghostProc.running = false
        win.ghostBusy = false
        win.ghostText = ""
    }

    function acceptGhost() {
        let g = win.ghostText, pos = win.ghostPos
        win.clearGhost()
        noteArea.insert(pos, g)
        noteArea.cursorPosition = pos + g.length
    }

    function escHtml(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    function handleAppend(raw) {
        let lines = raw.split("\n")
        let opened = false, src = ""
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].trim().length === 0) continue
            let o = null
            try { o = JSON.parse(lines[i]) } catch (e) { continue }
            let body = (o.text || "").replace(/^\n+|\n+$/g, "")
            if (body.length === 0) continue
            if (o.heading) body = "## " + o.heading + "\n\n" + body
            let cur = noteArea.text
            let sep = cur.length === 0 ? "" : (cur.endsWith("\n\n") ? "" : (cur.endsWith("\n") ? "\n" : "\n\n"))
            noteArea.insert(noteArea.length, sep + body + "\n")
            if (o.open) opened = true
            src = o.source || "claude"
        }
        if (src.length === 0) return
        win.aiStatus = "+ note from " + src
        aiStatusTimer.restart()
        if (opened && !win.cardVisible) win.cardVisible = true
    }

    Timer { id: aiStatusTimer; interval: 3000; onTriggered: win.aiStatus = "" }
    Timer { id: acDebounce; interval: 900; onTriggered: if (win.autoComplete && win.cardVisible && noteArea.activeFocus) win.requestGhost(false) }

    Process {
        id: aiEditProc
        stdout: StdioCollector { onStreamFinished: win.applyAi(this.text) }
    }

    Process {
        id: ghostProc
        stdout: StdioCollector { onStreamFinished: win.applyGhost(this.text) }
    }

    Process {
        id: acFlagProc
        running: true
        command: ["bash", "-c", "cat '" + win.acFlagPath + "' 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: win.autoComplete = this.text.trim() === "1" }
    }

    Process {
        id: appendWatcher
        running: true
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "touch /tmp/qs_scratchpad_append; exec inotifywait -qq -e close_write /tmp/qs_scratchpad_append"]
        onExited: {
            appendReader.running = true
            appendWatcher.running = true
        }
    }

    Process {
        id: appendReader
        command: ["bash", "-c", "mv /tmp/qs_scratchpad_append /tmp/qs_scratchpad_append_read 2>/dev/null && cat /tmp/qs_scratchpad_append_read && rm -f /tmp/qs_scratchpad_append_read"]
        stdout: StdioCollector { onStreamFinished: win.handleAppend(this.text) }
    }

    function countMatches(q) {
        if (q.length === 0) return 0
        let src = noteArea.text.toLowerCase(), needle = q.toLowerCase()
        let count = 0, idx = 0
        while ((idx = src.indexOf(needle, idx)) !== -1) { count++; idx += needle.length }
        return count
    }

    function findNext() {
        let q = findInput.text
        if (q.length === 0) return
        let src = noteArea.text.toLowerCase(), needle = q.toLowerCase()
        let idx = src.indexOf(needle, noteArea.cursorPosition)
        if (idx === -1) idx = src.indexOf(needle, 0)
        if (idx !== -1) noteArea.select(idx, idx + q.length)
    }

    function findPrev() {
        let q = findInput.text
        if (q.length === 0) return
        let src = noteArea.text.toLowerCase(), needle = q.toLowerCase()
        let end = noteArea.selectionStart > 0 ? noteArea.selectionStart - 1 : src.length - 1
        let idx = src.lastIndexOf(needle, end)
        if (idx === -1) idx = src.lastIndexOf(needle, src.length - 1)
        if (idx !== -1) noteArea.select(idx, idx + q.length)
    }

    Process {
        id: ipcWatcher
        running: true
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "touch /tmp/qs_scratchpad_cmd; exec inotifywait -qq -e close_write /tmp/qs_scratchpad_cmd"]
        onExited: {
            ipcReader.running = true
            ipcWatcher.running = true
        }
    }

    Process {
        id: ipcReader
        command: ["bash", "-c", "mv /tmp/qs_scratchpad_cmd /tmp/qs_scratchpad_cmd_read 2>/dev/null && cat /tmp/qs_scratchpad_cmd_read && rm -f /tmp/qs_scratchpad_cmd_read"]
        stdout: StdioCollector {
            onStreamFinished: {
                let cmd = this.text.trim()
                if (cmd === "toggle") {
                    if (win.cardVisible) {
                        hideAnim.start()
                    } else {
                        win.cardVisible = true
                    }
                } else if (cmd === "show") {
                    if (!win.cardVisible) win.cardVisible = true
                } else if (cmd === "hide") {
                    if (win.cardVisible) hideAnim.start()
                } else if (cmd === "clear") {
                    win.aiUndoText = noteArea.text
                    win.aiCanUndo = noteArea.text.length > 0
                    noteArea.text = ""
                    win.saveText()
                }
            }
        }
    }

    Rectangle {
        id: contentRect
        anchors.fill: parent
        opacity: win.cardOpacity

        radius: win.s(16)
        color: Qt.rgba(win.base.r, win.base.g, win.base.b, 0.75)
        border.color: win.surface0
        border.width: 1
        clip: true

        Rectangle {
            width: parent.width * 0.7; height: width; radius: width / 2
            x: parent.width * 0.15; y: -parent.height * 0.2
            opacity: 0.04
            color: win.mauve
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: win.s(16)
            spacing: win.s(10)

            Item {
                id: headerItem
                z: 10
                Layout.fillWidth: true
                height: win.s(22)

                HoverHandler { cursorShape: Qt.OpenHandCursor }

                MouseArea {
                    anchors.fill: parent
                    onPressed: win.startSystemMove()
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: win.s(8)

                    Text { text: "󰈙"; font.family: "Iosevka Nerd Font"; font.pixelSize: win.s(16); color: win.mauve }

                    Text {
                        text: "SCRATCHPAD"
                        font.family: "JetBrains Mono"; font.weight: Font.Black
                        font.pixelSize: win.s(12); font.letterSpacing: 1.5
                        color: win.mauve
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: win.aiStatus.length > 0 ? win.aiStatus
                            : win.obsidianStatus.length > 0 ? win.obsidianStatus
                            : win.ghostText.length > 0 ? "tab accept · esc dismiss"
                            : noteArea.length + " chars"
                        font.family: "JetBrains Mono"; font.pixelSize: win.s(11)
                        color: win.overlay0; verticalAlignment: Text.AlignVCenter
                    }

                    Rectangle {
                        width: win.s(24); height: width; radius: win.s(5)
                        color: findBtnMa.containsMouse ? Qt.rgba(win.blue.r, win.blue.g, win.blue.b, 0.15) : "transparent"
                        border.color: win.showFind ? win.blue : (findBtnMa.containsMouse ? win.blue : "transparent")
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text { anchors.centerIn: parent; text: "󰍉"; font.family: "Iosevka Nerd Font"; font.pixelSize: win.s(13)
                            color: win.showFind ? win.blue : (findBtnMa.containsMouse ? win.blue : win.overlay0)
                            Behavior on color { ColorAnimation { duration: 150 } } }
                        MouseArea { id: findBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { win.showFind = !win.showFind; if (win.showFind) findInput.forceActiveFocus(); else noteArea.forceActiveFocus() } }
                        ScratchTip { text: "Find (Ctrl+F)"; show: findBtnMa.containsMouse }
                    }

                    Rectangle {
                        width: win.s(24); height: width; radius: win.s(5)
                        color: win.previewMode ? Qt.rgba(win.blue.r, win.blue.g, win.blue.b, 0.18) : (previewBtnMa.containsMouse ? Qt.rgba(win.blue.r, win.blue.g, win.blue.b, 0.15) : "transparent")
                        border.color: win.previewMode ? win.blue : (previewBtnMa.containsMouse ? win.blue : "transparent"); border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text { anchors.centerIn: parent; text: "MD"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: win.s(9)
                            color: win.previewMode ? win.blue : (previewBtnMa.containsMouse ? win.blue : win.overlay0)
                            Behavior on color { ColorAnimation { duration: 150 } } }
                        MouseArea { id: previewBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { win.previewMode = !win.previewMode; if (!win.previewMode) noteArea.forceActiveFocus() }
                        }
                        ScratchTip { text: "Toggle markdown preview"; show: previewBtnMa.containsMouse }
                    }

                    Rectangle {
                        Layout.preferredWidth: win.s(24); Layout.preferredHeight: win.s(24)
                        width: win.s(24); height: width; radius: win.s(5)
                        color: win.autoComplete ? Qt.rgba(win.blue.r, win.blue.g, win.blue.b, 0.18) : (acBtnMa.containsMouse ? Qt.rgba(win.blue.r, win.blue.g, win.blue.b, 0.15) : "transparent")
                        border.color: win.autoComplete ? win.blue : (acBtnMa.containsMouse ? win.blue : "transparent"); border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text { anchors.centerIn: parent; text: "AC"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: win.s(9)
                            color: win.autoComplete ? win.blue : (acBtnMa.containsMouse ? win.blue : win.overlay0)
                            Behavior on color { ColorAnimation { duration: 150 } } }
                        MouseArea { id: acBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { win.toggleAutoComplete(); noteArea.forceActiveFocus() }
                        }
                        ScratchTip { text: win.autoComplete ? "Autocomplete on (Ctrl+Space anytime)" : "Autocomplete off (Ctrl+Space anytime)"; show: acBtnMa.containsMouse }
                    }

                    Rectangle {
                        Layout.preferredWidth: win.s(24); Layout.preferredHeight: win.s(24)
                        width: win.s(24); height: width; radius: win.s(5)
                        color: (win.showAi || aiBtnMa.containsMouse) ? Qt.rgba(win.mauve.r, win.mauve.g, win.mauve.b, 0.15) : "transparent"
                        border.color: (win.showAi || aiBtnMa.containsMouse) ? win.mauve : "transparent"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            id: aiBtnIcon
                            anchors.centerIn: parent; text: "✦"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: win.s(13)
                            color: (win.showAi || aiBtnMa.containsMouse || win.aiBusy) ? win.mauve : win.overlay0
                            Behavior on color { ColorAnimation { duration: 150 } }
                            SequentialAnimation on opacity {
                                running: win.aiBusy
                                loops: Animation.Infinite
                                onRunningChanged: if (!running) aiBtnIcon.opacity = 1
                                NumberAnimation { to: 0.25; duration: 450; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 450; easing.type: Easing.InOutSine }
                            }
                        }
                        MouseArea { id: aiBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: win.showAi ? win.closeAi() : win.openAi()
                        }
                        ScratchTip { text: "Ask Claude (Ctrl+K)"; show: aiBtnMa.containsMouse }
                    }

                    Rectangle {
                        id: obsidianBtn
                        width: win.s(24); height: width; radius: win.s(5)
                        color: (obsidianBtnMa.containsMouse || win.obsidianPickerOpen) ? Qt.rgba(win.mauve.r, win.mauve.g, win.mauve.b, 0.15) : "transparent"
                        border.color: (obsidianBtnMa.containsMouse || win.obsidianPickerOpen) ? win.mauve : "transparent"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text { anchors.centerIn: parent; text: "↗"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: win.s(14)
                            color: (obsidianBtnMa.containsMouse || win.obsidianPickerOpen) ? win.mauve : win.overlay0
                            Behavior on color { ColorAnimation { duration: 150 } } }
                        MouseArea { id: obsidianBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: win.openObsidianPicker()
                        }
                        ScratchTip { text: "Save as Obsidian note"; show: obsidianBtnMa.containsMouse && !win.obsidianPickerOpen }

                        // Click-outside-to-close — huge, deliberately out of
                        // this button's own 24x24 bounds via negative
                        // margins, sitting z-below the popover but above
                        // everything else so any click elsewhere dismisses it.
                        MouseArea {
                            visible: win.obsidianPickerOpen
                            enabled: win.obsidianPickerOpen
                            x: -2000; y: -2000; width: 4000; height: 4000
                            z: 250
                            onClicked: win.obsidianPickerOpen = false
                        }

                        Rectangle {
                            id: obsidianPicker
                            visible: win.obsidianPickerOpen
                            anchors.top: parent.bottom; anchors.topMargin: win.s(8)
                            anchors.right: parent.right
                            width: win.s(220)
                            implicitHeight: pickerCol.implicitHeight + win.s(20)
                            radius: win.s(10)
                            color: win.base
                            border.width: 1; border.color: win.surface2
                            z: 300

                            MouseArea { anchors.fill: parent } // eat clicks so they don't fall through to the header drag handler

                            ColumnLayout {
                                id: pickerCol
                                anchors.fill: parent
                                anchors.margins: win.s(10)
                                spacing: win.s(8)

                                Text {
                                    text: "SAVE TO"
                                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: win.s(9)
                                    color: win.overlay0
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: win.s(6)
                                    Repeater {
                                        model: win.obsidianFolders.includes("Scratchpad") ? win.obsidianFolders : ["Scratchpad", ...win.obsidianFolders]
                                        delegate: Rectangle {
                                            readonly property bool isSelected: win.obsidianSelectedFolder === modelData
                                            height: win.s(22)
                                            width: folderChipTxt.implicitWidth + win.s(14)
                                            radius: win.s(11)
                                            color: isSelected ? Qt.rgba(win.mauve.r, win.mauve.g, win.mauve.b, 0.25) : (folderChipMa.containsMouse ? win.surface1 : win.surface0)
                                            border.width: isSelected ? 1 : 0; border.color: win.mauve
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                            Text {
                                                id: folderChipTxt
                                                anchors.centerIn: parent
                                                text: modelData
                                                font.family: "JetBrains Mono"; font.pixelSize: win.s(10)
                                                color: isSelected ? win.mauve : win.text
                                            }
                                            MouseArea { id: folderChipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: win.obsidianSelectedFolder = modelData }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: win.s(6)
                                    TextInput {
                                        id: newFolderInput
                                        Layout.fillWidth: true
                                        font.family: "JetBrains Mono"; font.pixelSize: win.s(11)
                                        color: win.text
                                        clip: true
                                        Text { text: "new folder…"; visible: !newFolderInput.text.length && !newFolderInput.activeFocus; color: win.overlay0; font: newFolderInput.font }
                                        Keys.onReturnPressed: if (text.length > 0) win.obsidianSelectedFolder = text
                                        onActiveFocusChanged: if (!activeFocus && text.length > 0) win.obsidianSelectedFolder = text
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: win.s(8)
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        width: win.s(52); height: win.s(24); radius: win.s(6)
                                        color: cancelPickerMa.containsMouse ? win.surface1 : "transparent"
                                        border.width: 1; border.color: win.surface2
                                        Text { anchors.centerIn: parent; text: "cancel"; font.family: "JetBrains Mono"; font.pixelSize: win.s(10); color: win.overlay0 }
                                        MouseArea { id: cancelPickerMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: win.obsidianPickerOpen = false }
                                    }
                                    Rectangle {
                                        width: win.s(52); height: win.s(24); radius: win.s(6)
                                        color: savePickerMa.containsMouse ? Qt.darker(win.mauve, 1.1) : win.mauve
                                        Text { anchors.centerIn: parent; text: "save"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: win.s(10); color: win.base }
                                        MouseArea { id: savePickerMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: win.confirmObsidianSave(win.obsidianSelectedFolder || "Scratchpad") }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: win.s(24); height: width; radius: win.s(5)
                        color: clearBtnMa.containsMouse ? Qt.rgba(win.red.r, win.red.g, win.red.b, 0.15) : "transparent"
                        border.color: clearBtnMa.containsMouse ? win.red : "transparent"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text { anchors.centerIn: parent; text: "󰃢"; font.family: "Iosevka Nerd Font"; font.pixelSize: win.s(13)
                            color: clearBtnMa.containsMouse ? win.red : win.overlay0
                            Behavior on color { ColorAnimation { duration: 150 } } }
                        MouseArea { id: clearBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { noteArea.text = ""; win.saveText() } }
                        ScratchTip { text: "Clear (Ctrl+Shift+Del)"; show: clearBtnMa.containsMouse }
                    }

                    Rectangle {
                        width: win.s(24); height: width; radius: win.s(5)
                        color: closeMa.containsMouse ? Qt.rgba(win.red.r, win.red.g, win.red.b, 0.15) : "transparent"
                        border.color: closeMa.containsMouse ? win.red : "transparent"; border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text { anchors.centerIn: parent; text: "󰅖"; font.family: "Iosevka Nerd Font"; font.pixelSize: win.s(13)
                            color: closeMa.containsMouse ? win.red : win.overlay0
                            Behavior on color { ColorAnimation { duration: 150 } } }
                        MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: hideAnim.start() }
                        ScratchTip { text: "Close"; show: closeMa.containsMouse }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(win.surface2.r, win.surface2.g, win.surface2.b, 0.5) }

            Rectangle {
                Layout.fillWidth: true
                Layout.bottomMargin: win.showFind ? win.s(10) : 0
                height: win.showFind ? win.s(36) : 0
                color: Qt.rgba(win.surface0.r, win.surface0.g, win.surface0.b, 0.6)
                radius: win.s(8); clip: true; visible: height > 0
                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: win.s(10); anchors.rightMargin: win.s(6)
                    spacing: win.s(8)

                    Text { text: "󰍉"; font.family: "Iosevka Nerd Font"; font.pixelSize: win.s(13); color: win.overlay0 }

                    TextInput {
                        id: findInput
                        Layout.fillWidth: true
                        font.family: "JetBrains Mono"; font.pixelSize: win.s(13)
                        color: win.text
                        selectionColor: Qt.rgba(win.mauve.r, win.mauve.g, win.mauve.b, 0.3)
                        selectedTextColor: win.text
                        onTextChanged: { win.findMatchCount = win.countMatches(text); if (text.length > 0) win.findNext() }
                        Keys.onReturnPressed: win.findNext()
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                win.showFind = false; noteArea.forceActiveFocus(); event.accepted = true
                            }
                        }
                    }

                    Text { text: findInput.text.length > 0 ? win.findMatchCount + " matches" : ""; font.family: "JetBrains Mono"; font.pixelSize: win.s(11); color: win.overlay0 }

                    Rectangle { width: win.s(22); height: width; radius: win.s(4)
                        color: prevMa.containsMouse ? Qt.rgba(win.mauve.r, win.mauve.g, win.mauve.b, 0.15) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text { anchors.centerIn: parent; text: "󰅁"; font.family: "Iosevka Nerd Font"; font.pixelSize: win.s(12); color: prevMa.containsMouse ? win.mauve : win.overlay0 }
                        MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.findPrev() } }

                    Rectangle { width: win.s(22); height: width; radius: win.s(4)
                        color: nextMa.containsMouse ? Qt.rgba(win.mauve.r, win.mauve.g, win.mauve.b, 0.15) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text { anchors.centerIn: parent; text: "󰅂"; font.family: "Iosevka Nerd Font"; font.pixelSize: win.s(12); color: nextMa.containsMouse ? win.mauve : win.overlay0 }
                        MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.findNext() } }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: win.showAi ? aiCol.implicitHeight + win.s(16) : 0
                color: Qt.rgba(win.surface0.r, win.surface0.g, win.surface0.b, 0.6)
                border.width: 1
                border.color: win.aiBusy ? Qt.rgba(win.mauve.r, win.mauve.g, win.mauve.b, 0.6) : "transparent"
                radius: win.s(8); clip: true; visible: Layout.preferredHeight > 0
                Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    id: aiCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.leftMargin: win.s(10); anchors.rightMargin: win.s(8); anchors.topMargin: win.s(8)
                    spacing: win.s(8)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: win.s(8)

                        Text { text: "✦"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: win.s(13); color: win.mauve }

                        TextInput {
                            id: aiInput
                            Layout.fillWidth: true
                            font.family: "JetBrains Mono"; font.pixelSize: win.s(13)
                            color: win.text
                            readOnly: win.aiBusy
                            clip: true
                            selectionColor: Qt.rgba(win.mauve.r, win.mauve.g, win.mauve.b, 0.3)
                            selectedTextColor: win.text
                            Text {
                                text: noteArea.selectionEnd > noteArea.selectionStart
                                      ? "tell Claude what to do with the selection…"
                                      : "tell Claude what to do with the note…"
                                visible: !aiInput.text.length
                                color: win.overlay0; font: aiInput.font
                            }
                            Keys.onReturnPressed: win.runAi(text)
                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Escape) {
                                    if (win.aiBusy) win.cancelAi()
                                    else win.closeAi()
                                    event.accepted = true
                                }
                            }
                        }

                        Text {
                            text: noteArea.selectionEnd > noteArea.selectionStart
                                  ? "selection · " + (noteArea.selectionEnd - noteArea.selectionStart)
                                  : "whole note"
                            font.family: "JetBrains Mono"; font.pixelSize: win.s(10)
                            color: win.aiBusy ? win.mauve : win.overlay0
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: win.s(6)
                        Repeater {
                            model: win.aiPresets
                            delegate: Rectangle {
                                height: win.s(22)
                                width: aiChipTxt.implicitWidth + win.s(14)
                                radius: win.s(11)
                                opacity: win.aiBusy ? 0.4 : 1
                                color: aiChipMa.containsMouse ? Qt.rgba(win.mauve.r, win.mauve.g, win.mauve.b, 0.2) : win.surface0
                                border.width: aiChipMa.containsMouse ? 1 : 0; border.color: win.mauve
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    id: aiChipTxt
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.family: "JetBrains Mono"; font.pixelSize: win.s(10)
                                    color: aiChipMa.containsMouse ? win.mauve : win.text
                                }
                                MouseArea { id: aiChipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    enabled: !win.aiBusy
                                    onClicked: win.runAi(modelData.instr) }
                            }
                        }

                        Rectangle {
                            visible: win.aiCanUndo && !win.aiBusy
                            height: win.s(22)
                            width: aiUndoTxt.implicitWidth + win.s(14)
                            radius: win.s(11)
                            color: aiUndoMa.containsMouse ? Qt.rgba(win.red.r, win.red.g, win.red.b, 0.15) : "transparent"
                            border.width: 1; border.color: aiUndoMa.containsMouse ? win.red : win.surface2
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                id: aiUndoTxt
                                anchors.centerIn: parent
                                text: "undo"
                                font.family: "JetBrains Mono"; font.pixelSize: win.s(10)
                                color: aiUndoMa.containsMouse ? win.red : win.overlay0
                            }
                            MouseArea { id: aiUndoMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: win.undoAi() }
                        }
                    }
                }
            }

            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                visible: !win.previewMode

                TextArea {
                    id: noteArea
                    width: parent.width; wrapMode: TextArea.Wrap; topPadding: win.s(8)
                    font.family: "JetBrains Mono"; font.pixelSize: win.s(14)
                    color: win.text
                    selectionColor: Qt.rgba(win.mauve.r, win.mauve.g, win.mauve.b, 0.3)
                    selectedTextColor: win.text
                    placeholderText: "Start typing... (supports Markdown — toggle MD to preview)"; placeholderTextColor: win.overlay0
                    background: null; focus: true
                    persistentSelection: true
                    readOnly: win.aiBusy

                    onTextChanged: {
                        if (win.ghostText.length > 0 || win.ghostBusy) win.clearGhost()
                        if (win.suppressSave) return
                        saveDebounce.restart()
                        if (win.autoComplete) acDebounce.restart()
                    }

                    onCursorPositionChanged: if ((win.ghostText.length > 0 || win.ghostBusy) && cursorPosition !== win.ghostPos) win.clearGhost()

                    Text {
                        id: ghostOverlay
                        visible: win.ghostText.length > 0
                        readonly property rect cr: visible ? noteArea.positionToRectangle(win.ghostPos) : Qt.rect(0, 0, 0, 0)
                        readonly property int lineStart: visible ? noteArea.positionAt(noteArea.leftPadding, cr.y + cr.height / 2) : 0
                        x: noteArea.leftPadding
                        y: cr.y
                        width: noteArea.width - noteArea.leftPadding - noteArea.rightPadding
                        wrapMode: Text.Wrap
                        textFormat: Text.RichText
                        font: noteArea.font
                        color: win.text
                        opacity: 0.38
                        text: visible
                              ? "<span style='white-space:pre-wrap'><span style='color:transparent'>"
                                + win.escHtml(noteArea.text.substring(lineStart, win.ghostPos))
                                + "</span><i>" + win.escHtml(win.ghostText) + "</i></span>"
                              : ""
                    }

                    Rectangle {
                        visible: win.ghostBusy && win.ghostManual
                        readonly property rect cr: visible ? noteArea.positionToRectangle(win.ghostPos) : Qt.rect(0, 0, 0, 0)
                        x: cr.x + win.s(4); y: cr.y + cr.height / 2 - height / 2
                        width: win.s(6); height: width; radius: width / 2
                        color: win.mauve
                        SequentialAnimation on opacity {
                            running: win.ghostBusy
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.2; duration: 400 }
                            NumberAnimation { to: 1.0; duration: 400 }
                        }
                    }

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Tab && win.ghostText.length > 0 && !(event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier))) {
                            win.acceptGhost(); event.accepted = true
                        } else if (event.key === Qt.Key_Escape && (win.ghostText.length > 0 || win.ghostBusy)) {
                            win.clearGhost(); event.accepted = true
                        } else if (event.key === Qt.Key_Space && (event.modifiers & Qt.ControlModifier)) {
                            win.requestGhost(true); event.accepted = true
                        } else if (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) {
                            win.openAi(); event.accepted = true
                        } else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                            win.showFind = !win.showFind
                            if (win.showFind) findInput.forceActiveFocus()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Delete &&
                                   (event.modifiers & Qt.ControlModifier) &&
                                   (event.modifiers & Qt.ShiftModifier)) {
                            noteArea.text = ""; win.saveText(); event.accepted = true
                        } else if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) {
                            win.previewMode = true; event.accepted = true
                        }
                    }
                }
            }

            // Rendered markdown preview — QML's Text natively understands
            // Text.MarkdownText (headings, bold/italic, lists, code, links)
            // so this needs no external renderer, just a read-only mirror
            // of the same content.
            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                visible: win.previewMode

                Text {
                    width: parent.width
                    topPadding: win.s(8)
                    text: noteArea.text.length > 0 ? noteArea.text : "*Nothing to preview yet.*"
                    textFormat: Text.MarkdownText
                    wrapMode: Text.Wrap
                    font.family: "JetBrains Mono"; font.pixelSize: win.s(14)
                    color: win.text
                    linkColor: win.blue
                    onLinkActivated: (link) => Qt.openUrlExternally(link)

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        hoverEnabled: true
                        cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }
            }
        }
    }
}
