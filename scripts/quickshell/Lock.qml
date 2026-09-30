import QtQuick
import QtQuick.Window
import QtCore
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

ShellRoot {
    id: lockRoot
    readonly property bool preview: Quickshell.env("QS_LOCK_PREVIEW") === "1"

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color crust: _theme.crust
    readonly property color mantle: _theme.mantle
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color overlay2: _theme.overlay2
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2

    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color red: _theme.red
    readonly property color peach: _theme.peach
    readonly property color blue: _theme.blue
    readonly property color green: _theme.green

    property bool cfgMusic: true
    property bool cfgWeather: true
    property string cfgNotifs: "count"
    property bool cfgBrief: true
    property real cfgBlur: 0.8
    property bool cfgParallax: true
    property string cfgAmbient: "occasional"
    property string cfgClock: "big"
    property bool cfgQuickActions: true

    Process {
        id: cfgReader
        running: true
        command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let p = JSON.parse(this.text || "{}");
                    if (p.lockShowMusic !== undefined) lockRoot.cfgMusic = p.lockShowMusic;
                    if (p.lockShowWeather !== undefined) lockRoot.cfgWeather = p.lockShowWeather;
                    if (p.lockShowNotifs !== undefined) lockRoot.cfgNotifs = p.lockShowNotifs;
                    if (p.lockShowBrief !== undefined) lockRoot.cfgBrief = p.lockShowBrief;
                    if (p.lockBlurStrength !== undefined) lockRoot.cfgBlur = Math.max(0, Math.min(1, p.lockBlurStrength));
                    if (p.lockParallax !== undefined) lockRoot.cfgParallax = p.lockParallax;
                    if (p.lockAmbientFx !== undefined) lockRoot.cfgAmbient = p.lockAmbientFx;
                    if (p.lockClockStyle !== undefined) lockRoot.cfgClock = p.lockClockStyle;
                    if (p.lockShowQuickActions !== undefined) lockRoot.cfgQuickActions = p.lockShowQuickActions;
                } catch (e) {}
            }
        }
    }

    Settings {
        id: lockPrefs
        category: "QuickshellLockscreen"
        property bool hidePassword: false
        property int revealDuration: 300
    }

    QtObject {
        id: lockState
        property bool failed: false
        property bool authenticating: false
        property bool unlocking: false
        property string statusText: "Locked"
        property string pendingPassword: ""
        property string previewPassword: ""
        property var content: null

        function clearInput() { if (content) content.clearInput(); }

        function tryRespond() {
            if (!pamLoader.item) return;
            if (pamLoader.item.responseRequired && pendingPassword !== "") {
                let pwd = pendingPassword;
                pendingPassword = "";
                authenticating = true;
                statusText = "Authenticating...";
                failed = false;
                pamLoader.item.respond(pwd);
                clearInput();
            }
        }

        function submit(pwd) {
            if (authenticating || unlocking) return;
            if (lockRoot.preview) {
                authenticating = true;
                statusText = "Authenticating...";
                failed = false;
                previewPassword = pwd;
                previewTimer.restart();
                return;
            }
            if (pamLoader.item && pamLoader.item.responseRequired) {
                authenticating = true;
                statusText = "Authenticating...";
                failed = false;
                pamLoader.item.respond(pwd);
            } else {
                pendingPassword = pwd;
            }
        }

        function succeed() {
            authenticating = false;
            unlocking = true;
            unlockTimer.start();
        }

        function reset(denied) {
            authenticating = false;
            failed = !!denied;
            statusText = denied ? "Access Denied" : "Locked";
            pendingPassword = "";
            clearInput();
            pamLoader.active = false;
            if (!lockRoot.preview) pamRestartTimer.restart();
        }
    }

    Timer {
        id: unlockTimer
        interval: 650
        repeat: false
        onTriggered: {
            if (!lockRoot.preview) rootLock.locked = false;
            Qt.quit();
        }
    }

    Timer {
        id: previewTimer
        interval: 700
        repeat: false
        onTriggered: {
            if (lockState.previewPassword === "test") lockState.succeed();
            else lockState.reset(true);
        }
    }

    Timer {
        interval: 90000
        running: lockRoot.preview
        repeat: false
        onTriggered: Qt.quit()
    }

    Timer {
        id: pamRespondWatcher
        interval: 30
        repeat: true
        running: lockState.pendingPassword !== ""
        onTriggered: lockState.tryRespond()
    }

    Timer {
        id: pamRestartTimer
        interval: 50
        repeat: false
        onTriggered: pamLoader.active = true
    }

    Loader {
        id: pamLoader
        active: !lockRoot.preview
        sourceComponent: Component {
            PamContext {
                Component.onCompleted: start()

                onResponseRequiredChanged: lockState.tryRespond()

                onCompleted: (result) => {
                    if (result === PamResult.Success) {
                        lockState.succeed();
                    } else {
                        lockState.reset(true);
                    }
                }

                onError: (error) => {
                    lockState.reset(true);
                }
            }
        }
    }

    WlSessionLock {
        id: rootLock
        locked: !lockRoot.preview

        WlSessionLockSurface {
            id: surface

            LockContent {
                anchors.fill: parent
                root: lockRoot
                lockUI: lockState
                lockSettings: lockPrefs
            }
        }
    }

    LazyLoader {
        active: lockRoot.preview
        PanelWindow {
            id: previewWin
            visible: true
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            color: "black"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "qs-lock-preview"

            LockContent {
                anchors.fill: parent
                root: lockRoot
                lockUI: lockState
                lockSettings: lockPrefs
            }
        }
    }
}
