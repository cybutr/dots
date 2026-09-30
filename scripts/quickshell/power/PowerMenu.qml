import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val) }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color mauve: _theme.mauve
    readonly property color blue: _theme.blue
    readonly property color yellow: _theme.yellow
    readonly property color red: _theme.red

    property string currentUser: ""
    property string currentTime: "--:--:--"
    property string currentDate: ""
    property string currentUptime: ""
    property string currentHostname: ""
    property string currentKernel: ""

    Process {
        command: ["bash", "-c", "echo $USER"]
        running: true
        stdout: StdioCollector { onStreamFinished: root.currentUser = this.text.trim() }
    }
    Process {
        command: ["bash", "-c", "hostname"]
        running: true
        stdout: StdioCollector { onStreamFinished: root.currentHostname = this.text.trim() }
    }
    Process {
        command: ["bash", "-c", "uname -r"]
        running: true
        stdout: StdioCollector { onStreamFinished: root.currentKernel = this.text.trim() }
    }
    Process {
        command: ["bash", "-c", "uptime -p | sed 's/up //'"]
        running: true
        stdout: StdioCollector { onStreamFinished: root.currentUptime = this.text.trim() }
    }

    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            var d = new Date()
            root.currentTime = Qt.formatTime(d, "HH:mm:ss")
            root.currentDate = Qt.formatDate(d, "dddd, MMMM d")
        }
    }

    property real introFade: 0
    property real introContent: 0

    ParallelAnimation {
        running: true
        NumberAnimation { target: root; property: "introFade"; from: 0; to: 1.0; duration: 350; easing.type: Easing.OutQuart }
        SequentialAnimation {
            PauseAnimation { duration: 80 }
            NumberAnimation { target: root; property: "introContent"; from: 0; to: 1.0; duration: 600; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
        }
    }

    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: root; property: "introFade"; to: 0; duration: 300; easing.type: Easing.InQuart }
        NumberAnimation { target: root; property: "introContent"; to: 0; duration: 200; easing.type: Easing.InQuart }
    }

    property real orbitAngle: 0
    NumberAnimation on orbitAngle {
        from: 0; to: Math.PI * 2; duration: 100000; loops: Animation.Infinite; running: true
    }

    // Background
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5 * root.introFade)
    }

    // Ambient blobs
    Rectangle {
        width: parent.width * 0.45; height: width; radius: width / 2
        x: (parent.width / 2 - width / 2) + Math.cos(root.orbitAngle) * root.s(300)
        y: (parent.height / 2 - height / 2) + Math.sin(root.orbitAngle) * root.s(200)
        opacity: 0.06 * root.introFade
        color: "#f38ba8"
    }
    Rectangle {
        width: parent.width * 0.35; height: width; radius: width / 2
        x: (parent.width / 2 - width / 2) + Math.sin(root.orbitAngle * 1.3) * root.s(-280)
        y: (parent.height / 2 - height / 2) + Math.cos(root.orbitAngle * 1.3) * root.s(-180)
        opacity: 0.05 * root.introFade
        color: "#b4befe"
    }

    // Main content
    Item {
        anchors.centerIn: parent
        width: childrenRect.width
        height: childrenRect.height
        opacity: root.introContent
        scale: 0.88 + (0.12 * root.introContent)

        Column {
            spacing: root.s(36)

            // Clock
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.s(6)

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.currentTime
                    font.family: "JetBrains Mono"
                    font.weight: Font.Bold
                    font.pixelSize: root.s(76)
                    color: root.text
                    font.letterSpacing: root.s(2)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.currentDate
                    font.family: "JetBrains Mono"
                    font.pixelSize: root.s(15)
                    color: root.subtext0
                    font.letterSpacing: root.s(3)
                }
            }

            // Avatar + user
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.s(12)

                // Avatar circle
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.s(72); height: root.s(72)
                    radius: width / 2
                    color: root.surface0
                    border.color: root.surface1
                    border.width: root.s(2)
                    layer.enabled: true

                    Text {
                        anchors.centerIn: parent
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: root.s(34)
                        color: root.overlay0
                        text: "󰀄"
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.currentUser
                    font.family: "JetBrains Mono"
                    font.weight: Font.Bold
                    font.pixelSize: root.s(17)
                    color: root.overlay0
                    font.letterSpacing: root.s(4)
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.s(40); height: root.s(1)
                    color: root.surface1
                }
            }

            // Buttons
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.s(28)

                Repeater {
                    model: ListModel {
                        ListElement { cmd: "bash ~/.config/hypr/scripts/lock.sh";               icon: "󰌾"; label: "LOCK";     colorName: "mauve";  glowHex: "#b4befe"; weight: 1.0 }
                        ListElement { cmd: "bash ~/.config/hypr/scripts/lock.sh & systemctl suspend"; icon: "ᶻ 𝗓 𐰁"; label: "SLEEP"; colorName: "blue";   glowHex: "#89dceb"; weight: 1.5 }
                        ListElement { cmd: "systemctl reboot";                                  icon: "󰑓"; label: "REBOOT";   colorName: "yellow"; glowHex: "#fab387"; weight: 2.5 }
                        ListElement { cmd: "systemctl poweroff -i";                             icon: "󰐥"; label: "SHUTDOWN"; colorName: "red";    glowHex: "#f38ba8"; weight: 3.5 }
                    }

                    delegate: Column {
                        id: delegateCol
                        spacing: root.s(16)
                        property color c1: root[colorName] || root.surface1
                        property color c2: Qt.lighter(c1, 1.2)
                        property color glow: glowHex

                        Item {
                            width: root.s(150); height: root.s(150)

                            // Color glow — fixed semantic color, not matugen
                            Rectangle {
                                anchors.centerIn: parent
                                width: root.s(168); height: root.s(168)
                                radius: root.s(38)
                                color: delegateCol.glow
                                opacity: (btnMa.containsMouse || actionBtn.fillLevel > 0.01) ? 0.40 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }
                            }

                            Rectangle {
                                id: actionBtn
                                anchors.fill: parent
                                radius: root.s(32)
                                color: btnMa.containsMouse ? "#2bffffff" : "#14ffffff"
                                Behavior on color { ColorAnimation { duration: 200 } }

                                scale: btnMa.pressed ? (0.94 - (0.01 * weight)) : (btnMa.containsMouse ? 1.07 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }

                                property real fillLevel: 0.0
                                property bool triggered: false
                                property real flashOpacity: 0.0

                                Canvas {
                                    id: waveCanvas
                                    anchors.fill: parent

                                    property real wavePhase: 0.0
                                    NumberAnimation on wavePhase {
                                        running: actionBtn.fillLevel > 0.0 && actionBtn.fillLevel < 1.0
                                        loops: Animation.Infinite
                                        from: 0; to: Math.PI * 2; duration: 800
                                    }
                                    onWavePhaseChanged: requestPaint()
                                    Connections { target: actionBtn; function onFillLevelChanged() { waveCanvas.requestPaint() } }

                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        if (actionBtn.fillLevel <= 0.001) return;

                                        var r = root.s(32);
                                        var fillY = height * (1.0 - actionBtn.fillLevel);
                                        ctx.save();
                                        ctx.beginPath();
                                        ctx.moveTo(r, 0); ctx.lineTo(width - r, 0);
                                        ctx.arcTo(width, 0, width, r, r);
                                        ctx.lineTo(width, height - r);
                                        ctx.arcTo(width, height, width - r, height, r);
                                        ctx.lineTo(r, height);
                                        ctx.arcTo(0, height, 0, height - r, r);
                                        ctx.lineTo(0, r);
                                        ctx.arcTo(0, 0, r, 0, r);
                                        ctx.closePath();
                                        ctx.clip();

                                        ctx.beginPath();
                                        ctx.moveTo(0, fillY);
                                        if (actionBtn.fillLevel < 0.99) {
                                            var waveAmp = root.s(12) * Math.sin(actionBtn.fillLevel * Math.PI);
                                            var cp1y = fillY + Math.sin(wavePhase) * waveAmp;
                                            var cp2y = fillY + Math.cos(wavePhase + Math.PI) * waveAmp;
                                            ctx.bezierCurveTo(width * 0.33, cp2y, width * 0.66, cp1y, width, fillY);
                                            ctx.lineTo(width, height); ctx.lineTo(0, height);
                                        } else {
                                            ctx.lineTo(width, 0); ctx.lineTo(width, height); ctx.lineTo(0, height);
                                        }
                                        ctx.closePath();

                                        var grad = ctx.createLinearGradient(0, 0, 0, height);
                                        grad.addColorStop(0, delegateCol.glow.toString());
                                        grad.addColorStop(1, Qt.lighter(delegateCol.glow, 1.3).toString());
                                        ctx.fillStyle = grad;
                                        ctx.fill();
                                        ctx.restore();
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent; radius: parent.radius; color: "#ffffff"
                                    opacity: actionBtn.flashOpacity
                                    PropertyAnimation on opacity { id: flashAnim; to: 0; duration: 500; easing.type: Easing.OutExpo }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: root.s(46)
                                    color: btnMa.containsMouse ? root.text : root.subtext0
                                    text: icon
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                Item {
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                    height: actionBtn.height * actionBtn.fillLevel
                                    clip: true
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: (actionBtn.height / 2) - (height / 2) - (actionBtn.height - parent.height)
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: root.s(46)
                                        color: root.crust
                                        text: icon
                                    }
                                }

                                // Border overlay — on top of canvas
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: "transparent"
                                    property bool active: btnMa.containsMouse || actionBtn.fillLevel > 0.01
                                    border.color: active ? Qt.rgba(Qt.color(glowHex).r, Qt.color(glowHex).g, Qt.color(glowHex).b, 0.9) : "#33ffffff"
                                    border.width: active ? 2 : 1
                                    Behavior on border.color { ColorAnimation { duration: 200 } }
                                }

                                MouseArea {
                                    id: btnMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: actionBtn.triggered ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    onPressed: { if (!actionBtn.triggered) { drainAnim.stop(); fillAnim.start(); } }
                                    onReleased: { if (!actionBtn.triggered && actionBtn.fillLevel < 1.0) { fillAnim.stop(); drainAnim.start(); } }
                                }

                                NumberAnimation {
                                    id: fillAnim; target: actionBtn; property: "fillLevel"; to: 1.0
                                    duration: (550 * weight) * (1.0 - actionBtn.fillLevel); easing.type: Easing.InSine
                                    onFinished: {
                                        actionBtn.triggered = true;
                                        actionBtn.flashOpacity = 0.6;
                                        flashAnim.start();
                                        exitAnim.start();
                                        exitTimer.start();
                                    }
                                }

                                NumberAnimation {
                                    id: drainAnim; target: actionBtn; property: "fillLevel"; to: 0.0
                                    duration: 1500 * actionBtn.fillLevel; easing.type: Easing.OutQuad
                                }

                                Timer {
                                    id: exitTimer; interval: 400
                                    onTriggered: {
                                        Quickshell.execDetached(["sh", "-c", cmd]);
                                        Quickshell.execDetached(["sh", "-c", "echo 'close' > /tmp/qs_widget_state"]);
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: label
                            font.family: "JetBrains Mono"
                            font.weight: Font.Bold
                            font.pixelSize: root.s(11)
                            color: root.subtext0
                            font.letterSpacing: root.s(2)
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "hold to confirm"
                font.family: "JetBrains Mono"
                font.pixelSize: root.s(12)
                color: root.overlay0
            }
        }
    }

    // Stats footer
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.s(32)
        spacing: root.s(20)
        opacity: root.introFade * 0.6

        Repeater {
            model: [
                { icon: "󰅐", text: root.currentUptime },
                { icon: "󰒋", text: root.currentHostname },
                { icon: "󰌽", text: root.currentKernel }
            ]

            delegate: Row {
                spacing: root.s(6)
                required property var modelData
                required property int index

                Text {
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: root.s(12)
                    color: root.overlay0
                    text: modelData.icon
                }
                Text {
                    font.family: "JetBrains Mono"
                    font.pixelSize: root.s(11)
                    color: root.overlay0
                    text: modelData.text
                }
                Rectangle {
                    visible: index < 2
                    width: root.s(1); height: root.s(11)
                    color: root.surface1
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    Keys.onEscapePressed: {
        Quickshell.execDetached(["sh", "-c", "echo 'close' > /tmp/qs_widget_state"]);
        event.accepted = true;
    }
}
