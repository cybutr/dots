import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "WindowRegistry.js" as Registry
import "notifications" as Notifs

PanelWindow {
    id: masterWindow
    color: "transparent"

    WlrLayershell.namespace: "qs-master"
    // Top, not Overlay: its full-screen blur samples everything below it. Pinned
    // cards (PinnedCards.qml) stay on Overlay, a strictly higher layer level, so
    // the blur can never reach them — they render sharp on top while the chat
    // still blurs the wallpaper + windows behind it. Same-layer order rules and
    // remap pulses were racy; a layer-level split is deterministic.
    WlrLayershell.layer: WlrLayer.Top
    
    exclusionMode: ExclusionMode.Ignore 
    focusable: true

    width: Screen.width
    height: Screen.height

    visible: isVisible

    // Punches holes in the full-screen click-catcher below: the topbar strip, plus every
    // currently-pinned card's rect — without this, clicking a pinned card (a *different*
    // PanelWindow/process entirely, PinnedCards.qml) still gets intercepted by this
    // surface's own full-screen MouseArea and closes the chat, because Wayland's input
    // stacking order between two separate layer-shell surfaces doesn't necessarily match
    // which one rendered on top visually (PinnedCards' own remap-pulse fix only fixes the
    // visual side of that). A fixed bank of hole slots, same reasoning as PinnedCards.qml's
    // own click-passthrough mask: Region's "regions" list only accepts static declarative
    // children, a Repeater can't populate it dynamically.
    // Pinned-card holes are cut from *cached* rects (pinned_cards.json) that don't know
    // or care whether a widget popup (battery/volume/notifications/network etc.) is
    // currently open and rendered on top of that same screen region — those popups
    // live in this same PanelWindow's own Item tree, not a separate surface, so a stale
    // pinned-card hole sitting under an open popup silently eats clicks meant for the
    // popup's own buttons. activeWidgetHole re-adds the currently open widget's exact
    // rect after all the Subtracts, guaranteeing its input region always wins over any
    // pinned-card hole it happens to overlap.
    mask: Region {
        item: maskBase
        Region { item: topBarHole; intersection: Intersection.Subtract }
        Region { item: pinnedHole0; intersection: Intersection.Subtract }
        Region { item: pinnedHole1; intersection: Intersection.Subtract }
        Region { item: pinnedHole2; intersection: Intersection.Subtract }
        Region { item: pinnedHole3; intersection: Intersection.Subtract }
        Region { item: pinnedHole4; intersection: Intersection.Subtract }
        Region { item: pinnedHole5; intersection: Intersection.Subtract }
        Region { item: pinnedHole6; intersection: Intersection.Subtract }
        Region { item: pinnedHole7; intersection: Intersection.Subtract }
        Region { item: activeWidgetHole; intersection: Intersection.Combine }
    }

    Item {
        id: activeWidgetHole
        x: masterWindow.animX
        y: masterWindow.animY
        width: masterWindow.isVisible ? masterWindow.animW : 0
        height: masterWindow.isVisible ? masterWindow.animH : 0
    }

    Item { id: maskBase; anchors.fill: parent }

    Item {
        id: topBarHole
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 65 // Safely covers your TopBar height + margins
    }

    // live pinned-card rects, read the same file PinnedCards.qml itself watches
    property var pinnedRects: []
    Process {
        id: pinnedRectsLoader
        running: true
        command: ["bash", "-c", "cat '" + Quickshell.env("HOME") + "/.cache/quickshell/claude/pinned_cards.json' 2>/dev/null || echo '[]'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let m = JSON.parse(this.text.trim() || "[]");
                    masterWindow.pinnedRects = m.map(e => ({
                        x: (e.x !== undefined && e.x !== null) ? e.x : -1000,
                        y: (e.y !== undefined && e.y !== null) ? e.y : -1000,
                        w: (e.w !== undefined && e.w !== null) ? e.w : 360,
                        // h is frequently null (CardRenderer computes it at render time,
                        // never persisted unless resized) — pad generously rather than
                        // under-cover, a hole slightly too big just means a tiny dead zone
                        // right at a card's edge never closes the chat, harmless
                        h: (e.h !== undefined && e.h !== null) ? e.h : 280
                    }));
                } catch (e) { masterWindow.pinnedRects = []; }
            }
        }
    }
    Process {
        id: pinnedRectsWatcher
        running: true
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
            "f=" + Quickshell.env("HOME") + "/.cache/quickshell/claude/pinned_cards.json; mkdir -p \"$(dirname \"$f\")\"; touch \"$f\"; " +
            "inotifywait -m -e close_write,create \"$f\" 2>/dev/null"]
        stdout: SplitParser { splitMarker: "\n"; onRead: (data) => { pinnedRectsLoader.running = false; pinnedRectsLoader.running = true; } }
    }
    Item { id: pinnedHole0; x: masterWindow.pinnedRects[0] ? masterWindow.pinnedRects[0].x : -1000; y: masterWindow.pinnedRects[0] ? masterWindow.pinnedRects[0].y : -1000; width: masterWindow.pinnedRects[0] ? masterWindow.pinnedRects[0].w : 0; height: masterWindow.pinnedRects[0] ? masterWindow.pinnedRects[0].h : 0 }
    Item { id: pinnedHole1; x: masterWindow.pinnedRects[1] ? masterWindow.pinnedRects[1].x : -1000; y: masterWindow.pinnedRects[1] ? masterWindow.pinnedRects[1].y : -1000; width: masterWindow.pinnedRects[1] ? masterWindow.pinnedRects[1].w : 0; height: masterWindow.pinnedRects[1] ? masterWindow.pinnedRects[1].h : 0 }
    Item { id: pinnedHole2; x: masterWindow.pinnedRects[2] ? masterWindow.pinnedRects[2].x : -1000; y: masterWindow.pinnedRects[2] ? masterWindow.pinnedRects[2].y : -1000; width: masterWindow.pinnedRects[2] ? masterWindow.pinnedRects[2].w : 0; height: masterWindow.pinnedRects[2] ? masterWindow.pinnedRects[2].h : 0 }
    Item { id: pinnedHole3; x: masterWindow.pinnedRects[3] ? masterWindow.pinnedRects[3].x : -1000; y: masterWindow.pinnedRects[3] ? masterWindow.pinnedRects[3].y : -1000; width: masterWindow.pinnedRects[3] ? masterWindow.pinnedRects[3].w : 0; height: masterWindow.pinnedRects[3] ? masterWindow.pinnedRects[3].h : 0 }
    Item { id: pinnedHole4; x: masterWindow.pinnedRects[4] ? masterWindow.pinnedRects[4].x : -1000; y: masterWindow.pinnedRects[4] ? masterWindow.pinnedRects[4].y : -1000; width: masterWindow.pinnedRects[4] ? masterWindow.pinnedRects[4].w : 0; height: masterWindow.pinnedRects[4] ? masterWindow.pinnedRects[4].h : 0 }
    Item { id: pinnedHole5; x: masterWindow.pinnedRects[5] ? masterWindow.pinnedRects[5].x : -1000; y: masterWindow.pinnedRects[5] ? masterWindow.pinnedRects[5].y : -1000; width: masterWindow.pinnedRects[5] ? masterWindow.pinnedRects[5].w : 0; height: masterWindow.pinnedRects[5] ? masterWindow.pinnedRects[5].h : 0 }
    Item { id: pinnedHole6; x: masterWindow.pinnedRects[6] ? masterWindow.pinnedRects[6].x : -1000; y: masterWindow.pinnedRects[6] ? masterWindow.pinnedRects[6].y : -1000; width: masterWindow.pinnedRects[6] ? masterWindow.pinnedRects[6].w : 0; height: masterWindow.pinnedRects[6] ? masterWindow.pinnedRects[6].h : 0 }
    Item { id: pinnedHole7; x: masterWindow.pinnedRects[7] ? masterWindow.pinnedRects[7].x : -1000; y: masterWindow.pinnedRects[7] ? masterWindow.pinnedRects[7].y : -1000; width: masterWindow.pinnedRects[7] ? masterWindow.pinnedRects[7].w : 0; height: masterWindow.pinnedRects[7] ? masterWindow.pinnedRects[7].h : 0 }

    MouseArea {
        anchors.fill: parent
        enabled: masterWindow.isVisible
        onClicked: switchWidget("hidden", "")
    }

    // Initialize state on boot
    Component.onCompleted: {
        Quickshell.execDetached(["bash", "-c", "echo '" + currentActive + "' > /tmp/qs_active_widget"]);
    }

    property string currentActive: "hidden" 
    property bool isVisible: false
    property string activeArg: ""
    property bool disableMorph: false 
    property bool isWallpaperTransition: false 
    property int morphDuration: 500

    property real animW: 1
    property real animH: 1
    property real animX: 0
    property real animY: 0
    
    property real targetW: 1
    property real targetH: 1

    property real globalUiScale: 1.0
    property var widgetStyles: ({})

    onGlobalUiScaleChanged: {
        handleNativeScreenChange();
    }

    // --- NOTIFICATIONS ---
    ListModel { id: globalNotificationHistory }
    ListModel { id: activePopupsModel }
    property var liveNotifs: ({})
    property int _popupCounter: 0
    property var notifModel: globalNotificationHistory

    property bool isStartup: true
    Timer { interval: 500; running: true; onTriggered: masterWindow.isStartup = false }

    property var warmComponents: []
    property int warmIndex: 0
    readonly property var warmWidgets: ["claudeask", "palette", "guide", "quicksettings", "volume", "battery", "calendar", "music", "network", "power", "wallpaper", "workspaces", "focustime", "monitors", "notifications", "applauncher"]
    Timer {
        interval: 350; repeat: true; running: !masterWindow.isStartup && masterWindow.warmIndex < masterWindow.warmWidgets.length
        onTriggered: {
            let t = masterWindow.getLayout(masterWindow.warmWidgets[masterWindow.warmIndex])
            masterWindow.warmIndex++
            if (!t || !t.comp) return
            let c = Qt.createComponent(Qt.resolvedUrl(t.comp), Component.Asynchronous)
            let keep = masterWindow.warmComponents.slice()
            keep.push(c)
            masterWindow.warmComponents = keep
        }
    }

    function removePopup(uid) {
        for (let i = 0; i < activePopupsModel.count; i++) {
            if (activePopupsModel.get(i).uid === uid) { activePopupsModel.remove(i); break; }
        }
    }

    NotificationServer {
        id: globalNotificationServer
        bodySupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: (n) => {
            n.tracked = true;
            let extractedActions = [];
            if (n.actions) {
                for (let i = 0; i < n.actions.length; i++) {
                    extractedActions.push({ "id": n.actions[i].identifier || "", "text": n.actions[i].text || n.actions[i].name || "Action" });
                }
            }
            masterWindow._popupCounter++;
            let uid = masterWindow._popupCounter;
            masterWindow.liveNotifs[uid] = n;
            let data = {
                "appName":     n.appName  !== "" ? n.appName  : "System",
                "summary":     n.summary  !== "" ? n.summary  : "No Title",
                "body":        n.body     !== "" ? n.body     : "",
                "iconPath":    n.appIcon  !== "" ? n.appIcon  : "",
                "actionsJson": JSON.stringify(extractedActions),
                "uid":         uid,
                "notif":       n
            };
            globalNotificationHistory.insert(0, data);
            if (!masterWindow.isStartup) {
                activePopupsModel.append(data);
                if (osdPopups.item) osdPopups.item.storeNotif(uid, n);
            }
            masterWindow.writeNotificationSnapshot();
        }
    }

    function writeNotificationSnapshot() {
        let out = [];
        for (let i = 0; i < Math.min(globalNotificationHistory.count, 20); i++) {
            let it = globalNotificationHistory.get(i);
            out.push({ "appName": it.appName, "summary": it.summary, "body": it.body, "uid": it.uid });
        }
        Quickshell.execDetached(["python3", "-c",
            "import sys, json; open(sys.argv[1], 'w').write(sys.argv[2])",
            "/tmp/qs_notifications.json", JSON.stringify(out)
        ]);
    }

    Loader {
        id: osdPopups
        source: masterWindow.widgetStyles.notifications_popup === "revamp"
            ? "notifications/NotificationPopupsRevamp.qml"
            : "notifications/NotificationPopups.qml"
        onLoaded: {
            item.popupModel = activePopupsModel;
            item.uiScale = Qt.binding(() => masterWindow.globalUiScale);
            item.removeRequested.connect((uid) => masterWindow.removePopup(uid));
        }
    }
    // ---------------------

    // --- Dynamic Settings Reader ---
    Process {
        id: settingsReader
        command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
        running: true // Run once at startup
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (this.text && this.text.trim().length > 0 && this.text.trim() !== "{}") {
                        let parsed = JSON.parse(this.text);
                        if (parsed.uiScale !== undefined && masterWindow.globalUiScale !== parsed.uiScale) {
                            masterWindow.globalUiScale = parsed.uiScale;
                        }
                        if (parsed.widgetStyles !== undefined) {
                            masterWindow.widgetStyles = parsed.widgetStyles;
                        }
                    }
                } catch (e) {
                    console.log("Error parsing settings.json in main.qml:", e);
                }
            }
        }
    }

    // EVENT-DRIVEN WATCHER
    Process {
        id: settingsWatcher
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "while [ ! -f ~/.config/hypr/settings.json ]; do sleep 1; done; exec inotifywait -qq -e modify,close_write ~/.config/hypr/settings.json"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                settingsReader.running = false;
                settingsReader.running = true;
                
                settingsWatcher.running = false;
                settingsWatcher.running = true;
            }
        }
    }
    // -------------------------------

    function getLayout(name) {
        return Registry.getLayout(name, 0, 0, Screen.width, Screen.height, masterWindow.globalUiScale, masterWindow.widgetStyles);
    }

    Connections {
        target: Screen
        function onWidthChanged() { handleNativeScreenChange(); }
        function onHeightChanged() { handleNativeScreenChange(); }
    }

    function buildProps(widget, arg) {
        let props = {};
        if (widget === "notifications") {
            props["notifModel"] = masterWindow.notifModel;
            props["liveNotifs"] = masterWindow.liveNotifs;
        }
        if (widget === "wallpaper" || widget === "quicktell" || widget === "holdaction" || widget === "guide" || widget === "leader") props["widgetArg"] = arg;
        return props;
    }

    property bool debugLog: false
    function dbg(msg) {
        if (!masterWindow.debugLog) return;
        Quickshell.execDetached(["bash", "-c", "printf '%s %s\\n' \"$(date +%H:%M:%S.%3N)\" '" + msg + "' >> /tmp/qs_widget_debug.log"]);
    }

    function handleNativeScreenChange() {
        if (masterWindow.currentActive === "hidden") return;
        
        let t = getLayout(masterWindow.currentActive);
        if (t) {
            masterWindow.animX = t.rx;
            masterWindow.animY = t.ry;
            masterWindow.animW = t.w;
            masterWindow.animH = t.h;
            masterWindow.targetW = t.w;
            masterWindow.targetH = t.h;
        }
    }

    onIsVisibleChanged: {
        if (isVisible && typeof masterWindow.requestActivate === "function") masterWindow.requestActivate();
    }

    // --- THE WIDGET CONTAINER ---
    Item {
        x: masterWindow.animX
        y: masterWindow.animY
        width: masterWindow.animW
        height: masterWindow.animH
        clip: true 

        Behavior on x { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }
        Behavior on y { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }
        Behavior on width { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }
        Behavior on height { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }

        opacity: masterWindow.isVisible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: masterWindow.isWallpaperTransition ? 150 : (masterWindow.morphDuration === 500 ? 300 : 200); easing.type: Easing.InOutSine } }

        MouseArea {
            anchors.fill: parent
        }

        Item {
            anchors.centerIn: parent
            width: masterWindow.targetW
            height: masterWindow.targetH

            StackView {
                id: widgetStack
                anchors.fill: parent
                focus: true
                
                Keys.onEscapePressed: {
                    switchWidget("hidden", "");
                    event.accepted = true;
                }

                onCurrentItemChanged: {
                    dbg("currentItemChanged depth=" + widgetStack.depth + " vis=" + masterWindow.isVisible + " active=" + masterWindow.currentActive);
                    if (currentItem) currentItem.forceActiveFocus();
                }

                replaceEnter: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 220; easing.type: Easing.OutExpo }
                        NumberAnimation { property: "scale"; from: 0.98; to: 1.0; duration: 220; easing.type: Easing.OutBack }
                    }
                }
                replaceExit: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 160; easing.type: Easing.InExpo }
                        NumberAnimation { property: "scale"; from: 1.0; to: 1.02; duration: 160; easing.type: Easing.InExpo }
                    }
                }
            }
        }
    }

    function switchWidget(newWidget, arg) {
        Quickshell.execDetached(["bash", "-c", "echo '" + newWidget + "' > /tmp/qs_active_widget"]);
        dbg("switchWidget → " + newWidget + " (from " + currentActive + ", vis=" + isVisible + ", depth=" + widgetStack.depth + ")");

        prepTimer.stop();
        teleportFadeOutTimer.stop();
        teleportFadeInTimer.stop();
        delayedClear.stop();

        let involvesWallpaper = (newWidget === "wallpaper" || currentActive === "wallpaper");
        masterWindow.isWallpaperTransition = involvesWallpaper;

        if (newWidget === "hidden") {
            if (currentActive !== "hidden") {
                masterWindow.morphDuration = 180; 
                masterWindow.disableMorph = false;
                
                masterWindow.animW = 1;
                masterWindow.animH = 1;
                masterWindow.isVisible = false; 
                
                delayedClear.start();
            }
        } else {
            if (currentActive === "hidden") {
                masterWindow.morphDuration = 180;
                masterWindow.disableMorph = false;
                
                let t = getLayout(newWidget);
                masterWindow.animX = t.rx;
                masterWindow.animY = t.ry;
                masterWindow.animW = 1;
                masterWindow.animH = 1;

                prepTimer.newWidget = newWidget;
                prepTimer.newArg = arg;
                prepTimer.start();
                
            } else {
                masterWindow.morphDuration = 500;
                if (involvesWallpaper) {
                    masterWindow.disableMorph = true;
                    masterWindow.isVisible = false; 
                    teleportFadeOutTimer.newWidget = newWidget;
                    teleportFadeOutTimer.newArg = arg;
                    teleportFadeOutTimer.start();
                } else {
                    masterWindow.disableMorph = false;
                    executeSwitch(newWidget, arg, false);
                }
            }
        }
    }

    Timer {
        id: prepTimer
        interval: 10
        property string newWidget: ""
        property string newArg: ""
        onTriggered: executeSwitch(newWidget, newArg, false)
    }

    Timer {
        id: teleportFadeOutTimer
        interval: 150 
        property string newWidget: ""
        property string newArg: ""
        onTriggered: {
            let t = getLayout(newWidget);

            masterWindow.currentActive = newWidget;
            masterWindow.activeArg = newArg;

            masterWindow.animX = t.rx;
            masterWindow.animY = t.ry;
            masterWindow.animW = t.w;
            masterWindow.animH = t.h;
            masterWindow.targetW = t.w;
            masterWindow.targetH = t.h;

            let props = buildProps(newWidget, newArg);
            widgetStack.replace(t.comp, props, StackView.Immediate);

            teleportFadeInTimer.newWidget = newWidget;
            teleportFadeInTimer.newArg = newArg;
            teleportFadeInTimer.start();
        }
    }

    Timer {
        id: teleportFadeInTimer
        interval: 50 
        property string newWidget: ""
        property string newArg: ""
        onTriggered: {
            masterWindow.isVisible = true; 
            if (newWidget !== "wallpaper") resetMorphTimer.start();
        }
    }

    Timer {
        id: resetMorphTimer
        interval: masterWindow.morphDuration 
        onTriggered: masterWindow.disableMorph = false
    }

    function executeSwitch(newWidget, arg, immediate) {
        masterWindow.currentActive = newWidget;
        masterWindow.activeArg = arg;
        
        let t = getLayout(newWidget);
        masterWindow.animX = t.rx;
        masterWindow.animY = t.ry;
        masterWindow.animW = t.w;
        masterWindow.animH = t.h;
        masterWindow.targetW = t.w;
        masterWindow.targetH = t.h;
        
        let props = buildProps(newWidget, arg);

        if (immediate) {
            widgetStack.replace(t.comp, props, StackView.Immediate);
        } else {
            widgetStack.replace(t.comp, props);
        }
        if (widgetStack.currentItem) { widgetStack.currentItem.opacity = 1; widgetStack.currentItem.scale = 1; }

        masterWindow.isVisible = true;
        dbg("executeSwitch done comp=" + t.comp + " vis=" + masterWindow.isVisible + " depth=" + widgetStack.depth + " item=" + (widgetStack.currentItem !== null));
    }

    Process {
        id: ipcWatcher
        running: true
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "touch /tmp/qs_widget_state; exec inotifywait -qq -e close_write /tmp/qs_widget_state"]
        onExited: {
            ipcPoller.running = true;
            running = true;
        }
    }

    Process {
        id: ipcPoller
        command: ["bash", "-c", "if [ -f /tmp/qs_widget_state ]; then mv /tmp/qs_widget_state /tmp/qs_widget_state_read 2>/dev/null && cat /tmp/qs_widget_state_read && rm /tmp/qs_widget_state_read; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let rawCmd = this.text.trim();
                if (rawCmd === "") return;
                dbg("ipc rawCmd='" + rawCmd + "' active=" + currentActive + " vis=" + isVisible + " depth=" + widgetStack.depth);

                let parts = rawCmd.split(":");
                let cmd = parts[0];
                let arg = parts.length > 1 ? parts[1] : "";

                if (cmd === "close") {
                    switchWidget("hidden", "");
                } else if (rawCmd.indexOf("claude:") === 0) {
                    let seedText = rawCmd.substring("claude:".length);
                    claudePrefillWriter.seedText = seedText;
                    claudePrefillWriter.running = false;
                    claudePrefillWriter.running = true;
                    switchWidget("claudeask", "");
                } else if (getLayout(cmd)) {
                    delayedClear.stop();
                    if (cmd === currentActive) {
                        switchWidget("hidden", "");
                    } else {
                        switchWidget(cmd, arg);
                    }
                }
            }
        }
    }

    Process {
        id: claudePrefillWriter
        property string seedText: ""
        running: false
        command: ["bash", "-c", "printf '%s' '" + seedText.replace(/'/g, "'\\''") + "' > /tmp/qs_claude_prefill"]
    }

    Timer {
        id: delayedClear
        interval: masterWindow.isWallpaperTransition ? 150 : masterWindow.morphDuration 
        onTriggered: {
            masterWindow.currentActive = "hidden";
            widgetStack.clear();
            masterWindow.disableMorph = false;
            dbg("delayedClear fired depth=" + widgetStack.depth + " vis=" + masterWindow.isVisible);
        }
    }
}
