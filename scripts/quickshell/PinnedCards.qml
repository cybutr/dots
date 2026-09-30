import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Standalone process (autostarted from ClaudeAsk.qml on first pin, exits itself once the
// pinned list is empty) — keeps pinned cards live/clickable on screen independent of the
// chat widget being open or closed. Mirrors BatteryAlarm.qml's "own process, own window" shape.
PanelWindow {
    id: root
    color: "transparent"
    WlrLayershell.namespace: "qs-pinned-cards"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    width: Screen.width
    height: Screen.height
    // Plain "wantShown && mapped" binding would stay mapped continuously while the
    // chat reopens — but Hyprland remaps masterWindow to the top of the overlay layer
    // on every reopen, which pushes this surface *behind* it, and Hyprland's
    // blur-behind-floating then blurs it like background. Forcing our own brief
    // unmap+remap (mapped, below) after every reopen re-raises us above it.
    visible: wantShown && mapped

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val); }

    MatugenColors { id: _theme }
    readonly property color surface1: _theme.surface1
    readonly property color subtext0: _theme.subtext0

    property var pinned: []
    property string pinnedFile: Quickshell.env("HOME") + "/.cache/quickshell/claude/pinned_cards.json"

    // user-configurable from the guide (SUPER+SHIFT+H): snap grid size, clutter cap,
    // compact-by-default — mirrors Scaler.qml's read+inotify pattern for settings.json
    property int gridSize: 12
    property bool clutterCapEnabled: true
    property bool compactDefault: true
    Process {
        id: settingsReader
        command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let p = JSON.parse(this.text.trim() || "{}");
                    if (p.pinGridSize !== undefined) root.gridSize = p.pinGridSize;
                    if (p.pinClutterCap !== undefined) root.clutterCapEnabled = p.pinClutterCap;
                    if (p.pinCompactMode !== undefined) root.compactDefault = p.pinCompactMode;
                } catch (e) {}
            }
        }
    }
    Process {
        id: settingsWatcher
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "while [ ! -f ~/.config/hypr/settings.json ]; do sleep 1; done; inotifywait -qq -e modify,close_write ~/.config/hypr/settings.json"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                settingsReader.running = false; settingsReader.running = true;
                settingsWatcher.running = false; settingsWatcher.running = true;
            }
        }
    }
    readonly property int clutterCapLimit: 6

    // named boards — group pinned cards instead of one infinite pile. Board is set at
    // pin time (ClaudeAsk.qml/qs_mcp.py write modelData.board), this just filters/tabs.
    property string currentBoard: "All"
    property var boardNames: {
        let names = ["All"];
        for (let i = 0; i < root.pinned.length; i++) {
            let b = root.pinned[i].board || "Default";
            if (names.indexOf(b) < 0) names.push(b);
        }
        return names;
    }
    property var visiblePinned: root.currentBoard === "All" ? root.pinned
        : root.pinned.filter(p => (p.board || "Default") === root.currentBoard)
    // dropped board's tab if we were filtered to it and it no longer has any cards
    onBoardNamesChanged: { if (root.boardNames.indexOf(root.currentBoard) < 0) root.currentBoard = "All"; }
    // chat widget's own centered rect (mirrors WindowRegistry.js's "claudeask" entry)
    // — cards must never sit on top of it, push them out instead.
    readonly property real chatW: root.s(920)
    readonly property real chatH: root.s(720)
    readonly property real chatLeft: (root.width - chatW) / 2
    readonly property real chatTop: (root.height - chatH) / 2
    readonly property real chatRight: chatLeft + chatW
    readonly property real chatBottom: chatTop + chatH
    // cards must never overlap each other either — used both to find a free spot for
    // a freshly-pinned card with no saved x/y, and to push a dragged card off one it
    // was dropped on top of.
    function rectsOverlap(ax, ay, aw, ah, bx, by, bw, bh) {
        return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
    }
    function collidesAny(x, y, w, h, excludeId) {
        let c = clampOutsideChat(x, y, w, h);
        if (c.x !== x || c.y !== y) return true;
        for (let i = 0; i < cardsRepeater.count; i++) {
            let it = cardsRepeater.itemAt(i);
            if (!it || it.modelData.id === excludeId) continue;
            if (rectsOverlap(x, y, w, h, it.x, it.y, it.width, it.height)) return true;
        }
        return false;
    }
    // push a card off the chat rect toward whichever of the FOUR edges is nearest — not
    // just left/right. The gap above/below the centered chat is valid parking now.
    function clampOutsideChat(x, y, w, h) {
        let ix = Math.max(x, chatLeft) < Math.min(x + w, chatRight);
        let iy = Math.max(y, chatTop) < Math.min(y + h, chatBottom);
        if (!(ix && iy)) return { x: x, y: y };
        let g = root.gridSize;
        let dRight = Math.abs((chatRight + g) - x);
        let dLeft = Math.abs(x - (chatLeft - w - g));
        let dBottom = Math.abs((chatBottom + g) - y);
        let dTop = Math.abs(y - (chatTop - h - g));
        let m = Math.min(dRight, dLeft, dBottom, dTop);
        if (m === dRight) return { x: chatRight + g, y: y };
        if (m === dLeft) return { x: chatLeft - w - g, y: y };
        if (m === dBottom) return { x: x, y: chatBottom + g };
        return { x: x, y: chatTop - h - g };
    }
    // nudge (x,y) out from underneath whatever it's overlapping — chat rect or another
    // card — toward whichever edge is closest, instead of teleporting to a found-by-scan
    // slot. Mirrors clampOutsideChat's "push to nearest side" feel for every obstacle.
    function pushOutOverlaps(x, y, w, h, excludeId) {
        for (let iter = 0; iter < 16; iter++) {
            let c = root.clampOutsideChat(x, y, w, h);
            if (c.x !== x || c.y !== y) {
                x = Math.min(Math.max(c.x, 0), root.width - w);
                y = Math.min(Math.max(c.y, 0), root.height - h);
                continue;
            }
            let hit = null;
            for (let i = 0; i < cardsRepeater.count; i++) {
                let it = cardsRepeater.itemAt(i);
                if (!it || it.modelData.id === excludeId) continue;
                if (root.rectsOverlap(x, y, w, h, it.x, it.y, it.width, it.height)) { hit = it; break; }
            }
            if (!hit) break;
            let g = root.gridSize;
            let dRight = Math.abs(x - (hit.x + hit.width));
            let dLeft = Math.abs((x + w) - hit.x);
            let dBottom = Math.abs(y - (hit.y + hit.height));
            let dTop = Math.abs((y + h) - hit.y);
            let m = Math.min(dRight, dLeft, dBottom, dTop);
            if (m === dRight) x = hit.x + hit.width + g;
            else if (m === dLeft) x = hit.x - w - g;
            else if (m === dBottom) y = hit.y + hit.height + g;
            else y = hit.y - h - g;
            x = Math.min(Math.max(x, 0), root.width - w);
            y = Math.min(Math.max(y, 0), root.height - h);
        }
        return { x: x, y: y };
    }

    property bool wantShown: pinned.length > 0 && chatOpen
    property bool mapped: false
    onWantShownChanged: {
        mapped = false;
        if (wantShown) remapTimer.restart();
    }
    Timer { id: remapTimer; interval: 80; repeat: false; onTriggered: root.mapped = true }

    // tied to the chat widget's own workspace: only show alongside an open chat, same
    // active-widget signal Main.qml already writes on every switchWidget call
    property bool chatOpen: false
    Process {
        id: activeWidgetReader
        running: true
        command: ["cat", "/tmp/qs_active_widget"]
        stdout: StdioCollector { onStreamFinished: root.chatOpen = this.text.trim() === "claudeask" }
    }
    Process {
        id: activeWidgetWatcher
        running: true
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "inotifywait -m -e close_write,create /tmp/qs_active_widget 2>/dev/null"]
        stdout: SplitParser { splitMarker: "\n"; onRead: (data) => { activeWidgetReader.running = false; activeWidgetReader.running = true; } }
    }

    // a layout-only write (position/size/compact) is already applied locally — swallow the
    // inotify it triggers so the Repeater doesn't rebuild every delegate and flash all the
    // cards' entrance/hover-glow at once. Real external edits (outside this window) still reload.
    property double _selfWriteUntil: 0
    // a reload mid-drag rebuilds the Repeater, recreating the dragged delegate at its saved
    // origin while the in-flight drag lingers on the old item — looks like the card cloned
    // itself. defer any reload until the drag/resize gesture ends.
    property bool _dragActive: false
    property bool _reloadPending: false
    function reload() {
        if (root._dragActive) { root._reloadPending = true; return; }
        if (Date.now() < _selfWriteUntil) return;
        loader.running = false; loader.running = true;
    }
    Process {
        id: loader
        running: true
        command: ["bash", "-c", "cat '" + root.pinnedFile + "' 2>/dev/null || echo '[]'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.pinned = JSON.parse(this.text.trim() || "[]"); } catch (e) { root.pinned = []; }
            }
        }
    }
    Process {
        id: watcher
        running: true
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
            "mkdir -p \"$(dirname '" + root.pinnedFile + "')\"; touch '" + root.pinnedFile + "'; " +
            "inotifywait -m -e close_write,create '" + root.pinnedFile + "' 2>/dev/null"]
        stdout: SplitParser { splitMarker: "\n"; onRead: (data) => root.reload() }
    }
    Process { id: remover; running: false }
    function unpin(id) {
        remover.command = ["python3", "-c",
            "import sys,json,os\n" +
            "p=sys.argv[1]\n" +
            "m=json.load(open(p)) if os.path.exists(p) else []\n" +
            "m=[x for x in m if x.get('id')!=int(sys.argv[2])]\n" +
            "json.dump(m, open(p+'.tmp','w'))\n" +
            "os.replace(p+'.tmp', p)\n",
            root.pinnedFile, "" + id];
        remover.running = false; remover.running = true;
        // optimistic local removal so the click feels instant, ahead of the inotify round-trip
        root.pinned = root.pinned.filter(p => p.id !== id);
    }
    Process { id: reverter; running: false }
    function applyReverted(id, specJson) {
        reverter.command = ["python3", "-c",
            "import sys,json,os\n" +
            "p=sys.argv[1]\n" +
            "m=json.load(open(p)) if os.path.exists(p) else []\n" +
            "spec=json.loads(sys.argv[3])\n" +
            "for e in m:\n" +
            "    if e.get('id')==int(sys.argv[2]): e['spec']=spec\n" +
            "json.dump(m, open(p+'.tmp','w'))\n" +
            "os.replace(p+'.tmp', p)\n",
            root.pinnedFile, "" + id, specJson];
        reverter.running = false; reverter.running = true;
    }
    Process { id: mover; running: false }
    function savePosition(id, x, y) {
        mover.command = ["python3", "-c",
            "import sys,json,os\n" +
            "p=sys.argv[1]\n" +
            "m=json.load(open(p)) if os.path.exists(p) else []\n" +
            "for e in m:\n" +
            "    if e.get('id')==int(sys.argv[2]): e['x']=float(sys.argv[3]); e['y']=float(sys.argv[4])\n" +
            "json.dump(m, open(p+'.tmp','w'))\n" +
            "os.replace(p+'.tmp', p)\n",
            root.pinnedFile, "" + id, "" + x, "" + y];
        root._selfWriteUntil = Date.now() + 500;
        mover.running = false; mover.running = true;
    }
    Process { id: resizer; running: false }
    function saveSize(id, w, h) {
        resizer.command = ["python3", "-c",
            "import sys,json,os\n" +
            "p=sys.argv[1]\n" +
            "m=json.load(open(p)) if os.path.exists(p) else []\n" +
            "for e in m:\n" +
            "    if e.get('id')==int(sys.argv[2]): e['w']=float(sys.argv[3]); e['h']=float(sys.argv[4])\n" +
            "json.dump(m, open(p+'.tmp','w'))\n" +
            "os.replace(p+'.tmp', p)\n",
            root.pinnedFile, "" + id, "" + w, "" + h];
        root._selfWriteUntil = Date.now() + 500;
        resizer.running = false; resizer.running = true;
    }
    Process { id: compactSetter; running: false }
    function saveCompact(id, compact) {
        compactSetter.command = ["python3", "-c",
            "import sys,json,os\n" +
            "p=sys.argv[1]\n" +
            "m=json.load(open(p)) if os.path.exists(p) else []\n" +
            "for e in m:\n" +
            "    if e.get('id')==int(sys.argv[2]): e['compact']=(sys.argv[3]=='1')\n" +
            "json.dump(m, open(p+'.tmp','w'))\n" +
            "os.replace(p+'.tmp', p)\n",
            root.pinnedFile, "" + id, compact ? "1" : "0"];
        root._selfWriteUntil = Date.now() + 500;
        compactSetter.running = false; compactSetter.running = true;
    }

    // self-exit once nothing is pinned anymore, instead of idling forever in the background
    Timer {
        interval: 4000; running: root.pinned.length === 0; repeat: false
        onTriggered: Qt.quit()
    }


    // Without a mask the whole screen-sized transparent surface eats every click
    // underneath it (same bug TopBar.qml already hit) — restrict hit-testing to just
    // the actual card rectangles. Region's "regions" list is read-only — it's only
    // populated by static declarative children, a Repeater can't inject into it like
    // it does for a visual Item's "data" — so this is a fixed bank of slots (plenty for
    // a side panel) rather than one Region per card dynamically.
    mask: Region {
        Region { item: root.boardNames.length > 2 ? boardTabs : null }
        Region { item: cardsRepeater.count > 0 ? cardsRepeater.itemAt(0) : null }
        Region { item: cardsRepeater.count > 1 ? cardsRepeater.itemAt(1) : null }
        Region { item: cardsRepeater.count > 2 ? cardsRepeater.itemAt(2) : null }
        Region { item: cardsRepeater.count > 3 ? cardsRepeater.itemAt(3) : null }
        Region { item: cardsRepeater.count > 4 ? cardsRepeater.itemAt(4) : null }
        Region { item: cardsRepeater.count > 5 ? cardsRepeater.itemAt(5) : null }
        Region { item: cardsRepeater.count > 6 ? cardsRepeater.itemAt(6) : null }
        Region { item: cardsRepeater.count > 7 ? cardsRepeater.itemAt(7) : null }
    }

    // board filter tabs — only shown once there's more than one board to switch between
    Row {
        id: boardTabs
        visible: root.boardNames.length > 2
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: root.s(16)
        anchors.rightMargin: root.s(16)
        spacing: root.s(6)
        Repeater {
            model: root.boardNames
            delegate: Rectangle {
                required property string modelData
                property bool sel: modelData === root.currentBoard
                width: tabLbl.implicitWidth + root.s(16); height: root.s(24)
                radius: root.s(7)
                color: sel ? root.surface1 : "transparent"
                border.width: 1; border.color: root.surface1
                Text {
                    id: tabLbl
                    anchors.centerIn: parent
                    text: modelData
                    font.family: "JetBrains Mono"; font.pixelSize: root.s(10); font.weight: Font.Bold
                    color: sel ? root.subtext0 : Qt.alpha(root.subtext0, 0.6)
                }
                MouseArea { anchors.fill: parent; onClicked: root.currentBoard = modelData }
            }
        }
    }

    // freeform draggable layout (not a stacked list) — each card remembers its own x/y,
    // dragged from any empty card background since the drag MouseArea sits *behind*
    // CardRenderer's own content and only catches clicks that fall through it
    Item {
        anchors.fill: parent

        Repeater {
            id: cardsRepeater
            model: root.visiblePinned
            delegate: Item {
                id: cardWrap
                required property var modelData
                required property int index
                readonly property real gridUnit: root.gridSize
                readonly property real minW: root.s(280)
                readonly property real minH: root.s(140)
                // clamp/overlap with the expanded footprint even while collapsed, so a chip
                // parked above/below the chat reserves the room its expanded form needs
                readonly property real effH: Math.max(height, cr3.expandedH)
                // forced compact past the clutter cap regardless of the per-card flag — keeps
                // an unbounded pile of pins from turning the panel into wallpaper soup
                readonly property bool cappedCompact: root.clutterCapEnabled && index >= root.clutterCapLimit
                x: modelData.x !== undefined ? modelData.x : 0
                y: modelData.y !== undefined ? modelData.y : 0
                width: modelData.w !== undefined ? modelData.w : root.s(360)
                height: (cappedCompact || modelData.compact === true) ? cr3.implicitHeight
                    : Math.max(modelData.h !== undefined ? modelData.h : 0, cr3.implicitHeight)

                // Track the pre-dropdown height so we can restore it on close.
                property real _baseH: 0

                // dropdownExpandH is set synchronously by CardRenderer when a dropdown
                // opens/closes, so cardWrap.height updates in the same frame — this
                // ensures Qt Quick's hit-testing includes the expanded area immediately.
                Connections {
                    target: cr3
                    function onDropdownExpandHChanged() {
                        if (cappedCompact || modelData.compact === true) return
                        if (cr3.dropdownExpandH > 0) {
                            if (cardWrap._baseH === 0) cardWrap._baseH = cardWrap.height
                            cardWrap.height = cardWrap._baseH + cr3.dropdownExpandH
                        } else if (cardWrap._baseH > 0) {
                            cardWrap.height = cardWrap._baseH
                            cardWrap._baseH = 0
                        }
                    }
                }

                // entrance/exit polish — a card never just pops into or out of existence; this
                // also covers a board-tab switch revealing/hiding cards (those delegates get
                // destroyed/recreated by the Repeater same as a genuine pin/unpin) and even a
                // plain data-refresh re-render, where a quick fade reads as an intentional
                // "updated" flash rather than a glitch, not just the literal first appearance.
                property bool exiting: false
                opacity: exiting ? 0 : 1
                scale: exiting ? 0.92 : 1
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
                Timer { id: entranceTimer; interval: 1; onTriggered: { cardWrap.opacity = 1; cardWrap.scale = 1; } }
                Timer { id: exitTimer; interval: 160; onTriggered: root.unpin(cardWrap.modelData.id) }
                function requestExit() { exiting = true; exitTimer.start(); }

                // position/size Behaviors only animate the *corrective settle* (post-drag snap,
                // post-overlap push, post-pack placement) — disabled while actively dragging or
                // resizing so the card still tracks the cursor 1:1 instead of lagging behind it.
                // one-shot animations, not Behaviors — a Behavior attached to a property
                // that's also live-driven by drag.target/imperative resize fights the drag
                // itself (broke 1:1 cursor tracking and snapping). These only ever get
                // start()ed explicitly, after release, to tween the corrective settle.
                NumberAnimation { id: settleX; target: cardWrap; property: "x"; duration: 200; easing.type: Easing.OutQuart }
                NumberAnimation { id: settleY; target: cardWrap; property: "y"; duration: 200; easing.type: Easing.OutQuart }
                NumberAnimation { id: settleW; target: cardWrap; property: "width"; duration: 200; easing.type: Easing.OutQuart }
                NumberAnimation { id: settleH; target: cardWrap; property: "height"; duration: 200; easing.type: Easing.OutQuart }
                function settleTo(x, y) {
                    settleX.to = x; settleY.to = y;
                    settleX.restart(); settleY.restart();
                }
                function settleSizeTo(w, h) {
                    settleW.to = w; settleH.to = h;
                    settleW.restart(); settleH.restart();
                }

                function snap(v) { return Math.round(v / gridUnit) * gridUnit; }

                Component.onCompleted: {
                    opacity = 0; scale = 0.96;
                    entranceTimer.start();
                    // brand-new pin (no saved x/y yet) starts just right of the chat, like
                    // before grid-pack existed; an existing pin re-validates its saved spot
                    // against both the chat rect AND every other card every time the panel
                    // loads — a position saved before this clamp existed (or saved back when
                    // the chat/other cards were laid out differently) must still get pushed
                    // clear now, not just at the moment it's next dragged.
                    let h0 = Math.max(modelData.h !== undefined ? modelData.h : root.s(180), cr3.expandedH);
                    let startX = modelData.x !== undefined ? modelData.x : (root.chatRight + root.s(16));
                    let startY = modelData.y !== undefined ? modelData.y : root.s(70);
                    let slot = root.pushOutOverlaps(startX, startY, width, h0, modelData.id);
                    if (slot.x !== cardWrap.x || slot.y !== cardWrap.y) {
                        cardWrap.x = slot.x; cardWrap.y = slot.y;
                        root.savePosition(modelData.id, slot.x, slot.y);
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    // expanded: sit behind the card (z:-1) so block buttons/dropdowns claim
                    // clicks first, only empty bg drags. compact: the chip has no interactive
                    // blocks, so raise above it to drag — a no-move click still falls through
                    // to onClicked, which expands (same as the chip's own tap). rightMargin
                    // keeps the chip's close button clickable.
                    anchors.rightMargin: cr3.compact ? root.s(30) : 0
                    z: cr3.compact ? 5 : -1
                    drag.target: cardWrap
                    drag.axis: Drag.XAndYAxis
                    drag.minimumX: 0; drag.maximumX: root.width - cardWrap.width
                    drag.minimumY: 0; drag.maximumY: root.height - cardWrap.effH
                    onPressedChanged: {
                        root._dragActive = pressed;
                        if (!pressed && root._reloadPending) { root._reloadPending = false; Qt.callLater(root.reload); }
                    }
                    onClicked: {
                        if (cr3.compact && !cardWrap.cappedCompact) {
                            cr3.compact = false;
                            root.saveCompact(cardWrap.modelData.id, false);
                        }
                    }
                    onReleased: {
                        let sx = Math.min(Math.max(cardWrap.snap(cardWrap.x), 0), root.width - cardWrap.width);
                        let sy = Math.min(Math.max(cardWrap.snap(cardWrap.y), 0), root.height - cardWrap.effH);
                        // dropped on/over the chat or another card — push clear toward
                        // whichever edge is closest instead of letting it stack. clamp with the
                        // expanded footprint so a collapsed chip never lands where it can't expand
                        let slot = root.pushOutOverlaps(sx, sy, cardWrap.width, cardWrap.effH, cardWrap.modelData.id);
                        cardWrap.settleTo(slot.x, slot.y);
                        root.savePosition(cardWrap.modelData.id, slot.x, slot.y);
                    }
                }

                CardRenderer {
                    id: cr3
                    width: cardWrap.width
                    standalone: true
                    spec: cardWrap.modelData.spec || {}
                    compact: cardWrap.cappedCompact || cardWrap.modelData.compact === true
                    onUnpinRequested: cardWrap.requestExit()
                    onCompactToggled: (v) => { if (!cardWrap.cappedCompact) root.saveCompact(cardWrap.modelData.id, v); }
                    onRevertRequested: (specJson) => root.applyReverted(cardWrap.modelData.id, specJson)
                }

                Item {
                    id: resizeGrip
                    visible: !cr3.compact
                    width: root.s(16)
                    height: root.s(16)
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    z: 10

                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            ctx.strokeStyle = root.subtext0;
                            ctx.lineWidth = Math.max(1, root.s(1));
                            var pad = root.s(3);
                            var step = root.s(4);
                            for (var i = 0; i < 3; i++) {
                                var off = pad + i * step;
                                ctx.beginPath();
                                ctx.moveTo(width - pad, height - off);
                                ctx.lineTo(width - off, height - pad);
                                ctx.stroke();
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.SizeFDiagCursor
                        z: 11
                        onPressedChanged: {
                            root._dragActive = pressed;
                            if (!pressed && root._reloadPending) { root._reloadPending = false; Qt.callLater(root.reload); }
                        }
                        onPositionChanged: (mouse) => {
                            if (!pressed) return;
                            var newW = Math.max(cardWrap.minW, cardWrap.width + mouse.x);
                            var newH = Math.max(cardWrap.minH, cardWrap.height + mouse.y);
                            newW = Math.min(newW, root.width - cardWrap.x);
                            newH = Math.min(newH, root.height - cardWrap.y);
                            // don't let growth reach into the chat rect when we're parked left of it
                            if (cardWrap.x < root.chatLeft && cardWrap.x + newW > root.chatLeft &&
                                Math.max(cardWrap.y, root.chatTop) < Math.min(cardWrap.y + newH, root.chatBottom)) {
                                newW = root.chatLeft - cardWrap.x;
                            }
                            cardWrap.width = newW;
                            cardWrap.height = newH;
                        }
                        onReleased: {
                            let sw = Math.max(cardWrap.minW, cardWrap.snap(cardWrap.width));
                            let sh = Math.max(cardWrap.minH, cardWrap.snap(cardWrap.height));
                            cardWrap.settleSizeTo(sw, sh);
                            root.saveSize(cardWrap.modelData.id, sw, sh);
                        }
                    }
                }
            }
        }
    }
}
