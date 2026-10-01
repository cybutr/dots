import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

FocusScope {
    id: root
    focus: true

    property string widgetArg: ""

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val); }

    MatugenColors { id: _theme }
    readonly property color cBase: _theme.base
    readonly property color cMantle: _theme.mantle
    readonly property color cCrust: _theme.crust
    readonly property color cText: _theme.text
    readonly property color cSub0: _theme.subtext0
    readonly property color cSub1: _theme.subtext1
    readonly property color cSurf0: _theme.surface0
    readonly property color cSurf1: _theme.surface1
    readonly property color cSurf2: _theme.surface2
    readonly property color cOver0: _theme.overlay0
    readonly property color cOver1: _theme.overlay1
    readonly property color cAccent: _theme.mauve

    readonly property string home: Quickshell.env("HOME")
    readonly property string leaderDir: home + "/.config/hypr/scripts/quickshell/leader"
    readonly property string promptsPy: home + "/.config/hypr/scripts/quickshell/claude/shot_prompts.py"
    readonly property string monoFont: "JetBrains Mono"
    readonly property string iconFont: "Iosevka Nerd Font"

    property string view: widgetArg === "prompts" ? "prompts" : "main"
    property bool formOpen: false
    property int sel: 0
    property int promptSel: 0
    property string armedDelete: ""
    property var st: ({})
    property string activePrompt: ""
    property var prompts: []
    property real intro: 0

    signal keyFlash(string id)

    readonly property var opens: [
        { id: "calendar", key: "C", label: "Calendar", icon: "󰃭", cmd: "calendar" },
        { id: "music", key: "M", label: "Music", icon: "󰎆", cmd: "music" },
        { id: "network", key: "N", label: "Network", icon: "󰖩", cmd: "network" },
        { id: "prompts", key: "P", label: "Screenshot prompt", icon: "󰄀", cmd: "" }
    ]

    readonly property var toggles: [
        { id: "wakelock", key: "1", label: "Stay awake", on: "󰛊", off: "󰤄", tint: root.cAccent },
        { id: "mic", key: "2", label: "Mic muted", on: "󰍭", off: "󰍬", tint: _theme.red },
        { id: "idle", key: "3", label: "Idle lock", on: "󰒳", off: "󰒲", tint: root.cAccent },
        { id: "nightlight", key: "4", label: "Night light", on: "󰌔", off: "󰌵", tint: root.cAccent },
        { id: "curve", key: "5", label: "Brightness curve", on: "󰃟", off: "󰃠", tint: root.cAccent },
        { id: "kandor", key: "6", label: "Kandor wake word", on: "󰍬", off: "󰍭", tint: root.cAccent },
        { id: "quiet", key: "7", label: "Quiet cards", on: "󰂛", off: "󰂚", tint: root.cAccent },
        { id: "wifi", key: "8", label: "Wi-Fi", on: "󰖩", off: "󰖪", tint: root.cAccent },
        { id: "bt", key: "9", label: "Bluetooth", on: "󰂯", off: "󰂲", tint: root.cAccent },
        { id: "eco", key: "0", label: "Eco mode", on: "󰌪", off: "󰌪", tint: root.cAccent }
    ]

    function toggleOn(id) {
        switch (id) {
            case "wakelock": return !!st.wakelock;
            case "mic": return !!st.mic_muted;
            case "idle": return st.idle_paused === false;
            case "nightlight": return st.nl_mode === "on";
            case "curve": return st.brightness_curve !== false;
            case "kandor": return !!st.kandor_enabled;
            case "quiet": return !!st.cards_quiet;
            case "wifi": return !!st.wifi;
            case "bt": return !!st.bt;
            case "eco": return st.eco !== false;
        }
        return false;
    }
    function toggleKnob(id) {
        if (id === "nightlight") return st.nl_mode === "on" ? 1 : (st.nl_mode === "off" ? 0 : 0.5);
        return toggleOn(id) ? 1 : 0;
    }
    function toggleState(id) {
        if (id === "nightlight") return st.nl_mode === "on" ? "Forced on" : (st.nl_mode === "off" ? "Forced off" : "Auto");
        return toggleOn(id) ? "On" : "Off";
    }

    function close() {
        Quickshell.execDetached(["bash", "-c", "echo close > /tmp/qs_widget_state"]);
    }

    function runToggle(id) {
        keyFlash(id);
        let n = Object.assign({}, st);
        if (id === "wakelock") n.wakelock = !n.wakelock;
        else if (id === "mic") n.mic_muted = !n.mic_muted;
        else if (id === "idle") n.idle_paused = !n.idle_paused;
        else if (id === "curve") n.brightness_curve = !(n.brightness_curve !== false);
        else if (id === "kandor") n.kandor_enabled = !n.kandor_enabled;
        else if (id === "quiet") n.cards_quiet = !n.cards_quiet;
        else if (id === "wifi") n.wifi = !n.wifi;
        else if (id === "bt") n.bt = !n.bt;
        else if (id === "eco") n.eco = !(n.eco !== false);
        st = n;
        Quickshell.execDetached(["bash", leaderDir + "/leader_do.sh", id]);
        refreshSoon.restart();
        refreshLate.restart();
    }

    function runOpen(o) {
        keyFlash(o.id);
        if (o.id === "prompts") { openPrompts(); return; }
        Quickshell.execDetached(["bash", home + "/.config/hypr/scripts/qs_manager.sh", "toggle", o.cmd]);
    }

    function openPrompts() {
        view = "prompts";
        formOpen = false;
        armedDelete = "";
        promptSel = Math.max(0, prompts.findIndex(p => p.name === activePrompt));
        root.forceActiveFocus();
    }
    function backToMain() {
        view = "main";
        formOpen = false;
        armedDelete = "";
        sel = 3;
        root.forceActiveFocus();
    }

    function promptCmd(args) {
        if (promptMut.running) return;
        promptMut.command = ["python3", promptsPy].concat(args);
        promptMut.running = true;
    }
    function activateAt(i) {
        if (i < 0 || i >= prompts.length) return;
        promptSel = i;
        keyFlash("p:" + prompts[i].name);
        activePrompt = prompts[i].name;
        promptCmd(["activate", prompts[i].name]);
    }
    function deleteSelected() {
        if (promptSel >= prompts.length || prompts.length < 2) return;
        let name = prompts[promptSel].name;
        if (armedDelete !== name) { armedDelete = name; disarm.restart(); return; }
        armedDelete = "";
        promptCmd(["delete", name]);
    }
    function openForm() {
        armedDelete = "";
        formOpen = true;
        nameField.text = "";
        bodyField.text = "";
        nameField.forceActiveFocus();
    }
    function closeForm() {
        formOpen = false;
        nameField.focus = false;
        bodyField.focus = false;
        root.forceActiveFocus();
    }
    function submitForm() {
        let n = nameField.text.trim(), b = bodyField.text.trim();
        if (!n) { nameField.forceActiveFocus(); formNudge.restart(); return; }
        if (!b) { bodyField.forceActiveFocus(); formNudge.restart(); return; }
        promptCmd(["add", n, b]);
        closeForm();
    }

    function applyPromptView(txt) {
        try {
            let v = JSON.parse((txt || "").trim());
            prompts = v.prompts || [];
            activePrompt = v.active || "";
            if (promptSel >= prompts.length) promptSel = Math.max(0, prompts.length - 1);
        } catch (e) { }
    }

    Process {
        id: stateProc
        command: ["bash", root.leaderDir + "/leader_state.sh"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.st = JSON.parse(this.text.trim()); } catch (e) { } }
        }
    }
    Process {
        id: promptRead
        command: ["python3", root.promptsPy, "json"]
        stdout: StdioCollector { onStreamFinished: root.applyPromptView(this.text) }
    }
    Process {
        id: promptMut
        stdout: StdioCollector { onStreamFinished: root.applyPromptView(this.text) }
    }
    function refreshState() { stateProc.running = false; stateProc.running = true; }
    Timer { id: refreshSoon; interval: 450; onTriggered: root.refreshState() }
    Timer { id: refreshLate; interval: 1600; onTriggered: root.refreshState() }
    Timer { interval: 2500; repeat: true; running: true; onTriggered: if (!stateProc.running) root.refreshState() }
    Timer { id: disarm; interval: 3000; onTriggered: root.armedDelete = "" }

    Component.onCompleted: {
        refreshState();
        promptRead.running = true;
        root.forceActiveFocus();
    }

    NumberAnimation on intro { from: 0; to: 1; duration: 520; easing.type: Easing.OutCubic; running: true }

    function gridPos(i) {
        if (i < 4) return { r: 0, c: i };
        let k = i - 4;
        return { r: 1 + (k % 5), c: Math.floor(k / 5) };
    }
    function gridIndex(r, c) {
        if (r <= 0) return Math.max(0, Math.min(3, c));
        return 4 + Math.max(0, Math.min(1, c)) * 5 + Math.min(4, r - 1);
    }
    function moveSel(dr, dc) {
        let p = gridPos(sel);
        if (dr !== 0) {
            let r = Math.max(0, Math.min(5, p.r + dr));
            let c = p.c;
            if (p.r === 0 && r > 0) c = p.c < 2 ? 0 : 1;
            else if (p.r > 0 && r === 0) c = p.c * 2;
            sel = gridIndex(r, c);
        } else {
            let max = p.r === 0 ? 3 : 1;
            sel = gridIndex(p.r, Math.max(0, Math.min(max, p.c + dc)));
        }
    }
    function activateSel() {
        if (sel < 4) runOpen(opens[sel]);
        else runToggle(toggles[sel - 4].id);
    }

    Keys.onPressed: (e) => {
        if (formOpen) return;
        let k = e.key;
        if (k === Qt.Key_Escape) {
            if (view === "prompts") backToMain(); else close();
            e.accepted = true; return;
        }
        if (view === "main") {
            if (k >= Qt.Key_0 && k <= Qt.Key_9) {
                let idx = k === Qt.Key_0 ? 9 : k - Qt.Key_1;
                sel = 4 + idx;
                runToggle(toggles[idx].id);
            } else if (k === Qt.Key_C) { sel = 0; runOpen(opens[0]); }
            else if (k === Qt.Key_M) { sel = 1; runOpen(opens[1]); }
            else if (k === Qt.Key_N) { sel = 2; runOpen(opens[2]); }
            else if (k === Qt.Key_P) { sel = 3; runOpen(opens[3]); }
            else if (k === Qt.Key_Up || k === Qt.Key_K) moveSel(-1, 0);
            else if (k === Qt.Key_Down || k === Qt.Key_J) moveSel(1, 0);
            else if (k === Qt.Key_Left || k === Qt.Key_H) moveSel(0, -1);
            else if (k === Qt.Key_Right || k === Qt.Key_L) moveSel(0, 1);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) activateSel();
            else return;
            e.accepted = true;
        } else {
            if (k >= Qt.Key_1 && k <= Qt.Key_9) activateAt(k - Qt.Key_1);
            else if (k === Qt.Key_Up || k === Qt.Key_K) { promptSel = Math.max(0, promptSel - 1); armedDelete = ""; }
            else if (k === Qt.Key_Down || k === Qt.Key_J) { promptSel = Math.min(prompts.length - 1, promptSel + 1); armedDelete = ""; }
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) activateAt(promptSel);
            else if (k === Qt.Key_A || k === Qt.Key_Plus || k === Qt.Key_Equal) openForm();
            else if (k === Qt.Key_D || k === Qt.Key_Delete) deleteSelected();
            else if (k === Qt.Key_Backspace || k === Qt.Key_Left || k === Qt.Key_H) backToMain();
            else return;
            e.accepted = true;
        }
    }

    component KeyCap: Item {
        id: cap
        property string label: ""
        property color tint: root.cAccent
        property bool lit: false
        property real depth: root.s(3)
        property real press: 0
        property int order: 0
        property real settle: Math.max(0, Math.min(1, root.intro * 1.6 - order * 0.06))
        implicitWidth: Math.max(root.s(28), capText.implicitWidth + root.s(16))
        implicitHeight: root.s(28) + depth
        width: implicitWidth
        height: implicitHeight

        function flash() { pressAnim.restart(); }
        SequentialAnimation {
            id: pressAnim
            NumberAnimation { target: cap; property: "press"; to: 1; duration: 60; easing.type: Easing.OutQuad }
            NumberAnimation { target: cap; property: "press"; to: 0; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
        }

        Rectangle {
            x: 0; y: cap.depth
            width: parent.width; height: parent.height - cap.depth
            radius: root.s(7)
            color: Qt.darker(cap.lit ? Qt.tint(root.cSurf1, Qt.rgba(cap.tint.r, cap.tint.g, cap.tint.b, 0.35)) : root.cSurf0, 1.45)
        }
        Rectangle {
            id: capFace
            x: 0
            y: cap.depth * Math.max(cap.press, 1 - cap.settle)
            width: parent.width; height: parent.height - cap.depth
            radius: root.s(7)
            color: cap.lit ? Qt.tint(root.cSurf1, Qt.rgba(cap.tint.r, cap.tint.g, cap.tint.b, 0.28)) : root.cSurf1
            border.width: 1
            border.color: cap.lit ? Qt.rgba(cap.tint.r, cap.tint.g, cap.tint.b, 0.55) : Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.08)
            Behavior on color { ColorAnimation { duration: 180 } }
            Rectangle {
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                anchors.margins: 1
                height: parent.height * 0.5
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.07) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Text {
                id: capText
                anchors.centerIn: parent
                text: cap.label
                font.family: root.monoFont; font.pixelSize: root.s(12); font.weight: Font.Black
                color: cap.lit ? root.cText : root.cSub1
                Behavior on color { ColorAnimation { duration: 180 } }
            }
        }
    }

    component SectionLabel: Text {
        font.family: root.monoFont
        font.pixelSize: root.s(11)
        font.weight: Font.Bold
        color: root.cOver1
    }

    Item {
        id: shell
        anchors.fill: parent
        anchors.margins: root.s(10)
        opacity: Math.min(1, root.intro * 1.5)

        Repeater {
            model: 3
            Rectangle {
                required property int index
                anchors.fill: card
                anchors.topMargin: root.s(2 + index * 3)
                anchors.leftMargin: index
                anchors.rightMargin: index
                radius: card.radius + index * 2
                color: root.cCrust
                opacity: 0.30 - index * 0.08
            }
        }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: root.s(18)
            border.width: 1
            border.color: Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.10)
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(root.cSurf0.r, root.cSurf0.g, root.cSurf0.b, 0.97) }
                GradientStop { position: 1.0; color: Qt.rgba(root.cBase.r, root.cBase.g, root.cBase.b, 0.98) }
            }
            Rectangle {
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                anchors.margins: 1
                height: root.s(90)
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.045) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        Item {
            id: header
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            anchors.topMargin: root.s(22); anchors.leftMargin: root.s(26); anchors.rightMargin: root.s(26)
            height: root.s(32)

            Row {
                id: chord
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.s(6)
                KeyCap { label: "Super"; order: 0; lit: true }
                Text { anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -root.s(1); text: "+"; font.family: root.monoFont; font.pixelSize: root.s(12); color: root.cOver0 }
                KeyCap { label: "J"; order: 1; lit: true }
            }
            Text {
                id: crumbRoot
                anchors.left: chord.right; anchors.leftMargin: root.s(16)
                anchors.verticalCenter: parent.verticalCenter
                text: "Leader"
                font.family: root.monoFont; font.pixelSize: root.s(17); font.weight: Font.Black
                color: root.view === "main" ? root.cText : root.cOver1
                Behavior on color { ColorAnimation { duration: 180 } }
                MouseArea { anchors.fill: parent; enabled: root.view !== "main"; cursorShape: Qt.PointingHandCursor; onClicked: root.backToMain() }
            }
            Text {
                id: crumbSep
                anchors.left: crumbRoot.right; anchors.leftMargin: root.s(10)
                anchors.verticalCenter: parent.verticalCenter
                visible: root.view === "prompts"
                text: "󰅂"; font.family: root.iconFont; font.pixelSize: root.s(14); color: root.cOver0
            }
            Text {
                anchors.left: crumbSep.right; anchors.leftMargin: root.s(10)
                anchors.verticalCenter: parent.verticalCenter
                visible: root.view === "prompts"
                text: root.formOpen ? "New screenshot prompt" : "Screenshot prompt"
                font.family: root.monoFont; font.pixelSize: root.s(17); font.weight: Font.Black
                color: root.cText
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.s(8)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.view === "main" ? "close" : "back"
                    font.family: root.monoFont; font.pixelSize: root.s(11); color: root.cOver1
                }
                KeyCap { label: "Esc"; order: 2; depth: root.s(2); scale: 0.86 }
            }
        }

        Rectangle {
            id: rule
            anchors.top: header.bottom; anchors.topMargin: root.s(18)
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: root.s(26); anchors.rightMargin: root.s(26)
            height: 1
            color: Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.07)
        }

        Item {
            id: mainView
            anchors.top: rule.bottom; anchors.bottom: footer.top
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: root.s(26); anchors.rightMargin: root.s(26)
            anchors.topMargin: root.s(16)
            visible: opacity > 0
            opacity: root.view === "main" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            transform: Translate { x: root.view === "main" ? 0 : -root.s(24); Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } } }

            SectionLabel { id: openLabel; text: "Open" }

            Row {
                id: openRow
                anchors.top: openLabel.bottom; anchors.topMargin: root.s(10)
                anchors.left: parent.left; anchors.right: parent.right
                spacing: root.s(10)
                readonly property real tileW: (width - spacing * 3) / 4

                Repeater {
                    model: root.opens
                    Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool selected: root.sel === index && root.view === "main"
                        readonly property bool hot: selected || tileMouse.containsMouse
                        width: modelData.id === "prompts" ? openRow.tileW * 1.3 : openRow.tileW * 0.9
                        height: root.s(66)
                        radius: root.s(12)
                        color: hot ? Qt.rgba(root.cSurf1.r, root.cSurf1.g, root.cSurf1.b, 0.55) : Qt.rgba(root.cSurf0.r, root.cSurf0.g, root.cSurf0.b, 0.45)
                        border.width: 1
                        border.color: selected ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.55) : Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.06)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on border.color { ColorAnimation { duration: 140 } }

                        Connections {
                            target: root
                            function onKeyFlash(id) { if (id === tile.modelData.id) tileCap.flash() }
                        }

                        KeyCap {
                            id: tileCap
                            anchors.left: parent.left; anchors.leftMargin: root.s(12)
                            anchors.verticalCenter: parent.verticalCenter
                            label: tile.modelData.key
                            order: 3 + tile.index
                            lit: tile.selected
                        }
                        Text {
                            id: tileIcon
                            anchors.left: tileCap.right; anchors.leftMargin: root.s(12)
                            anchors.verticalCenter: parent.verticalCenter
                            text: tile.modelData.icon
                            font.family: root.iconFont; font.pixelSize: root.s(18)
                            color: tile.hot ? root.cAccent : root.cSub0
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                        Column {
                            anchors.left: tileIcon.right; anchors.leftMargin: root.s(10)
                            anchors.right: parent.right; anchors.rightMargin: root.s(10)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.s(2)
                            Text {
                                width: parent.width
                                text: tile.modelData.label
                                elide: Text.ElideRight
                                font.family: root.monoFont; font.pixelSize: root.s(13); font.weight: Font.Bold
                                color: root.cText
                            }
                            Text {
                                width: parent.width
                                visible: tile.modelData.id === "prompts"
                                text: root.activePrompt ? "Using " + root.activePrompt : "No prompt saved"
                                elide: Text.ElideRight
                                font.family: root.monoFont; font.pixelSize: root.s(11)
                                color: root.cAccent
                            }
                        }
                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.sel = tile.index
                            onClicked: root.runOpen(tile.modelData)
                        }
                    }
                }
            }

            SectionLabel { id: toggleLabel; anchors.top: openRow.bottom; anchors.topMargin: root.s(22); text: "Toggles" }

            Grid {
                id: toggleGrid
                anchors.top: toggleLabel.bottom; anchors.topMargin: root.s(10)
                anchors.left: parent.left; anchors.right: parent.right
                columns: 2
                flow: Grid.TopToBottom
                rows: 5
                columnSpacing: root.s(12)
                rowSpacing: root.s(6)
                readonly property real cellW: (width - columnSpacing) / 2

                Repeater {
                    model: root.toggles
                    Rectangle {
                        id: trow
                        required property var modelData
                        required property int index
                        readonly property int gi: 4 + index
                        readonly property bool selected: root.sel === gi && root.view === "main"
                        readonly property bool hot: selected || rowMouse.containsMouse
                        readonly property bool isOn: root.toggleOn(modelData.id)
                        readonly property real knob: root.toggleKnob(modelData.id)
                        readonly property color tint: modelData.tint
                        width: toggleGrid.cellW
                        height: root.s(48)
                        radius: root.s(11)
                        color: hot ? Qt.rgba(root.cSurf1.r, root.cSurf1.g, root.cSurf1.b, 0.45) : "transparent"
                        border.width: 1
                        border.color: selected ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.45) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Connections {
                            target: root
                            function onKeyFlash(id) { if (id === trow.modelData.id) rowCap.flash() }
                        }

                        KeyCap {
                            id: rowCap
                            anchors.left: parent.left; anchors.leftMargin: root.s(10)
                            anchors.verticalCenter: parent.verticalCenter
                            label: trow.modelData.key
                            order: 7 + trow.index
                            tint: trow.tint
                            lit: trow.knob > 0
                        }
                        Text {
                            id: rowIcon
                            anchors.left: rowCap.right; anchors.leftMargin: root.s(14)
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.s(20)
                            horizontalAlignment: Text.AlignHCenter
                            text: trow.knob > 0 ? trow.modelData.on : trow.modelData.off
                            font.family: root.iconFont; font.pixelSize: root.s(17)
                            color: trow.knob > 0 ? trow.tint : root.cOver1
                            Behavior on color { ColorAnimation { duration: 180 } }
                        }
                        Text {
                            anchors.left: rowIcon.right; anchors.leftMargin: root.s(12)
                            anchors.right: stateText.left; anchors.rightMargin: root.s(10)
                            anchors.verticalCenter: parent.verticalCenter
                            text: trow.modelData.label
                            elide: Text.ElideRight
                            font.family: root.monoFont; font.pixelSize: root.s(13); font.weight: Font.Bold
                            color: trow.knob > 0 ? root.cText : root.cSub1
                        }
                        Text {
                            id: stateText
                            anchors.right: track.left; anchors.rightMargin: root.s(10)
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.toggleState(trow.modelData.id)
                            font.family: root.monoFont; font.pixelSize: root.s(11)
                            color: trow.knob > 0 ? trow.tint : root.cOver0
                            Behavior on color { ColorAnimation { duration: 180 } }
                        }
                        Rectangle {
                            id: track
                            anchors.right: parent.right; anchors.rightMargin: root.s(12)
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.s(36); height: root.s(20); radius: height / 2
                            color: trow.knob > 0 ? Qt.rgba(trow.tint.r, trow.tint.g, trow.tint.b, 0.24 + 0.14 * trow.knob) : Qt.rgba(root.cCrust.r, root.cCrust.g, root.cCrust.b, 0.55)
                            border.width: 1
                            border.color: trow.knob > 0 ? Qt.rgba(trow.tint.r, trow.tint.g, trow.tint.b, 0.5) : Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.08)
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Rectangle {
                                width: root.s(14); height: width; radius: width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                x: root.s(3) + (parent.width - width - root.s(6)) * trow.knob
                                color: trow.knob > 0 ? trow.tint : root.cOver0
                                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                        }
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.sel = trow.gi
                            onClicked: { root.sel = trow.gi; root.runToggle(trow.modelData.id) }
                        }
                    }
                }
            }
        }

        Item {
            id: promptView
            anchors.top: rule.bottom; anchors.bottom: footer.top
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: root.s(26); anchors.rightMargin: root.s(26)
            anchors.topMargin: root.s(16); anchors.bottomMargin: root.formOpen ? 0 : root.s(12)
            visible: opacity > 0
            opacity: root.view === "prompts" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            transform: Translate { x: root.view === "prompts" ? 0 : root.s(24); Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } } }

            Item {
                id: listPane
                anchors.fill: parent
                visible: !root.formOpen

                SectionLabel {
                    id: listLabel
                    text: "Sent with the screenshot when you press Super+Ctrl+Z"
                }

                Flickable {
                    id: promptFlick
                    anchors.top: listLabel.bottom; anchors.topMargin: root.s(10)
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.bottom: addRow.top; anchors.bottomMargin: root.s(10)
                    contentHeight: promptCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: promptCol
                        width: promptFlick.width
                        spacing: root.s(6)

                        Repeater {
                            model: root.prompts
                            Rectangle {
                                id: prow
                                required property var modelData
                                required property int index
                                readonly property bool isActive: modelData.name === root.activePrompt
                                readonly property bool selected: root.promptSel === index
                                readonly property bool armed: root.armedDelete === modelData.name
                                width: promptCol.width
                                height: root.s(70)
                                radius: root.s(12)
                                color: armed ? Qt.rgba(_theme.red.r, _theme.red.g, _theme.red.b, 0.12)
                                    : (selected || pMouse.containsMouse ? Qt.rgba(root.cSurf1.r, root.cSurf1.g, root.cSurf1.b, 0.45) : Qt.rgba(root.cSurf0.r, root.cSurf0.g, root.cSurf0.b, 0.35))
                                border.width: 1
                                border.color: armed ? Qt.rgba(_theme.red.r, _theme.red.g, _theme.red.b, 0.55)
                                    : (isActive ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.55)
                                    : (selected ? Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.14) : Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.05)))
                                Behavior on color { ColorAnimation { duration: 140 } }
                                Behavior on border.color { ColorAnimation { duration: 180 } }

                                Connections {
                                    target: root
                                    function onKeyFlash(id) { if (id === "p:" + prow.modelData.name) pCap.flash() }
                                }

                                Rectangle {
                                    anchors.left: parent.left; anchors.leftMargin: root.s(1)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(3); radius: width / 2
                                    height: prow.isActive ? parent.height - root.s(24) : 0
                                    color: root.cAccent
                                    Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                }
                                KeyCap {
                                    id: pCap
                                    anchors.left: parent.left; anchors.leftMargin: root.s(14)
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: prow.index < 9 ? String(prow.index + 1) : ""
                                    visible: prow.index < 9
                                    order: 3 + prow.index
                                    lit: prow.isActive
                                }
                                Column {
                                    anchors.left: pCap.right; anchors.leftMargin: root.s(14)
                                    anchors.right: pState.left; anchors.rightMargin: root.s(14)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(4)
                                    Text {
                                        width: parent.width
                                        text: prow.modelData.name
                                        elide: Text.ElideRight
                                        font.family: root.monoFont; font.pixelSize: root.s(14); font.weight: Font.Black
                                        color: prow.isActive ? root.cText : root.cSub1
                                    }
                                    Text {
                                        width: parent.width
                                        text: prow.armed ? "Press D again to delete this prompt" : prow.modelData.text.replace(/\s+/g, " ")
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        font.family: root.monoFont; font.pixelSize: root.s(11)
                                        color: prow.armed ? _theme.red : root.cOver1
                                    }
                                }
                                Text {
                                    id: pState
                                    anchors.right: parent.right; anchors.rightMargin: root.s(16)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: prow.isActive ? "Active" : "Use"
                                    font.family: root.monoFont; font.pixelSize: root.s(11); font.weight: prow.isActive ? Font.Black : Font.Normal
                                    color: prow.isActive ? root.cAccent : (pMouse.containsMouse ? root.cSub1 : "transparent")
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                }
                                MouseArea {
                                    id: pMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onEntered: { if (root.promptSel !== prow.index) root.armedDelete = ""; root.promptSel = prow.index }
                                    onClicked: (m) => {
                                        if (m.button === Qt.RightButton) { root.promptSel = prow.index; root.deleteSelected(); }
                                        else root.activateAt(prow.index);
                                    }
                                }
                            }
                        }
                    }
                }

                Row {
                    id: addRow
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    spacing: root.s(10)
                    Rectangle {
                        width: addInner.implicitWidth + root.s(20)
                        height: root.s(42)
                        radius: root.s(11)
                        color: addMouse.containsMouse ? Qt.rgba(root.cSurf1.r, root.cSurf1.g, root.cSurf1.b, 0.55) : Qt.rgba(root.cSurf0.r, root.cSurf0.g, root.cSurf0.b, 0.45)
                        border.width: 1
                        border.color: Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.07)
                        Row {
                            id: addInner
                            anchors.centerIn: parent
                            spacing: root.s(10)
                            KeyCap { label: "A"; order: 12; depth: root.s(2) }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "New prompt"; font.family: root.monoFont; font.pixelSize: root.s(13); font.weight: Font.Bold; color: root.cText }
                        }
                        MouseArea { id: addMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openForm() }
                    }
                    Rectangle {
                        visible: root.prompts.length > 1
                        width: delInner.implicitWidth + root.s(20)
                        height: root.s(42)
                        radius: root.s(11)
                        color: delMouse.containsMouse ? Qt.rgba(_theme.red.r, _theme.red.g, _theme.red.b, 0.12) : "transparent"
                        border.width: 1
                        border.color: Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.07)
                        Row {
                            id: delInner
                            anchors.centerIn: parent
                            spacing: root.s(10)
                            KeyCap { label: "D"; order: 13; depth: root.s(2); tint: _theme.red; lit: root.armedDelete !== "" }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.armedDelete !== "" ? "Confirm delete" : "Delete selected"
                                font.family: root.monoFont; font.pixelSize: root.s(13); font.weight: Font.Bold
                                color: root.armedDelete !== "" ? _theme.red : root.cSub1
                            }
                        }
                        MouseArea { id: delMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.deleteSelected() }
                    }
                }
            }

            Item {
                id: formPane
                anchors.fill: parent
                visible: root.formOpen

                SequentialAnimation {
                    id: formNudge
                    NumberAnimation { target: formShift; property: "x"; to: root.s(6); duration: 50 }
                    NumberAnimation { target: formShift; property: "x"; to: -root.s(6); duration: 70 }
                    NumberAnimation { target: formShift; property: "x"; to: 0; duration: 90; easing.type: Easing.OutBack }
                }
                transform: Translate { id: formShift }

                SectionLabel { id: nameLabel; text: "Name" }
                Rectangle {
                    id: nameBox
                    anchors.top: nameLabel.bottom; anchors.topMargin: root.s(8)
                    anchors.left: parent.left; anchors.right: parent.right
                    height: root.s(44)
                    radius: root.s(11)
                    color: Qt.rgba(root.cCrust.r, root.cCrust.g, root.cCrust.b, 0.45)
                    border.width: 1
                    border.color: nameField.activeFocus ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.6) : Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.08)
                    Behavior on border.color { ColorAnimation { duration: 140 } }
                    TextField {
                        id: nameField
                        anchors.fill: parent
                        anchors.leftMargin: root.s(14); anchors.rightMargin: root.s(14)
                        verticalAlignment: TextInput.AlignVCenter
                        background: Item {}
                        color: root.cText
                        selectionColor: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.35)
                        placeholderText: "e.g. quiz, translate, geoguessr-hard"
                        placeholderTextColor: root.cOver0
                        maximumLength: 32
                        font.family: root.monoFont; font.pixelSize: root.s(14); font.weight: Font.Bold
                        Keys.onReturnPressed: (e) => { bodyField.forceActiveFocus(); e.accepted = true; }
                        Keys.onEnterPressed: (e) => { bodyField.forceActiveFocus(); e.accepted = true; }
                        Keys.onTabPressed: (e) => { bodyField.forceActiveFocus(); e.accepted = true; }
                        Keys.onEscapePressed: (e) => { root.closeForm(); e.accepted = true; }
                    }
                }

                SectionLabel { id: bodyLabel; anchors.top: nameBox.bottom; anchors.topMargin: root.s(16); text: "Prompt" }
                Rectangle {
                    id: bodyBox
                    anchors.top: bodyLabel.bottom; anchors.topMargin: root.s(8)
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.bottom: formActions.top; anchors.bottomMargin: root.s(14)
                    radius: root.s(11)
                    color: Qt.rgba(root.cCrust.r, root.cCrust.g, root.cCrust.b, 0.45)
                    border.width: 1
                    border.color: bodyField.activeFocus ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.6) : Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.08)
                    Behavior on border.color { ColorAnimation { duration: 140 } }
                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: root.s(4)
                        TextArea {
                            id: bodyField
                            wrapMode: TextEdit.Wrap
                            background: Item {}
                            color: root.cText
                            selectionColor: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.35)
                            placeholderText: "What should Claude do with the screenshot?"
                            placeholderTextColor: root.cOver0
                            font.family: root.monoFont; font.pixelSize: root.s(13)
                            leftPadding: root.s(10); rightPadding: root.s(10); topPadding: root.s(10); bottomPadding: root.s(10)
                            Keys.onReturnPressed: (e) => {
                                if (e.modifiers & Qt.ShiftModifier) { e.accepted = false; return; }
                                root.submitForm(); e.accepted = true;
                            }
                            Keys.onEnterPressed: (e) => { root.submitForm(); e.accepted = true; }
                            Keys.onBacktabPressed: (e) => { nameField.forceActiveFocus(); e.accepted = true; }
                            Keys.onEscapePressed: (e) => { root.closeForm(); e.accepted = true; }
                        }
                    }
                }

                Row {
                    id: formActions
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    spacing: root.s(10)
                    Rectangle {
                        width: saveInner.implicitWidth + root.s(20)
                        height: root.s(42)
                        radius: root.s(11)
                        color: saveMouse.containsMouse ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.22) : Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.13)
                        border.width: 1
                        border.color: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.45)
                        Row {
                            id: saveInner
                            anchors.centerIn: parent
                            spacing: root.s(10)
                            KeyCap { label: "Enter"; depth: root.s(2); lit: true }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Save and use"; font.family: root.monoFont; font.pixelSize: root.s(13); font.weight: Font.Bold; color: root.cText }
                        }
                        MouseArea { id: saveMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.submitForm() }
                    }
                    Rectangle {
                        width: cancelInner.implicitWidth + root.s(20)
                        height: root.s(42)
                        radius: root.s(11)
                        color: cancelMouse.containsMouse ? Qt.rgba(root.cSurf1.r, root.cSurf1.g, root.cSurf1.b, 0.45) : "transparent"
                        border.width: 1
                        border.color: Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.07)
                        Row {
                            id: cancelInner
                            anchors.centerIn: parent
                            spacing: root.s(10)
                            KeyCap { label: "Esc"; depth: root.s(2) }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Cancel"; font.family: root.monoFont; font.pixelSize: root.s(13); font.weight: Font.Bold; color: root.cSub1 }
                        }
                        MouseArea { id: cancelMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeForm() }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: root.s(6)
                        text: "Shift+Enter for a new line"
                        font.family: root.monoFont; font.pixelSize: root.s(11); color: root.cOver0
                    }
                }
            }
        }

        Item {
            id: footer
            anchors.bottom: parent.bottom; anchors.bottomMargin: root.s(18)
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: root.s(26); anchors.rightMargin: root.s(26)
            height: root.s(24)
            visible: !root.formOpen

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.view === "main"
                    ? "Press a key or click. Arrows and Enter work too."
                    : "Press 1 to " + Math.min(9, Math.max(1, root.prompts.length)) + " or click to switch. Right-click deletes."
                font.family: root.monoFont; font.pixelSize: root.s(11)
                color: root.cOver0
            }
        }
    }
}
