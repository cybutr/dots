import QtQuick
import Quickshell
import Quickshell.Io
import "./"

Item {
    id: window
    focus: true

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val) }

    MatugenColors { id: _theme }
    readonly property color base:     _theme.base
    readonly property color mantle:   _theme.mantle
    readonly property color text:     _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color overlay1: _theme.overlay1
    readonly property color surface0: _theme.surface0
    readonly property color surface2: _theme.surface2
    readonly property color mauve:    _theme.mauve
    readonly property color red:      _theme.red
    readonly property color peach:    _theme.peach
    readonly property color yellow:   _theme.yellow
    readonly property color green:    _theme.green
    readonly property color teal:     _theme.teal
    readonly property color sapphire: _theme.sapphire
    readonly property color blue:     _theme.blue

    property var regularData: []
    property var specialData: []
    property var clientData:  []
    property int activeWsId:      0
    property int activeSpecialId: 0
    property int monW: Screen.width
    property int monH: Screen.height - 60

    property int selectedIndex: -1
    property int thumbRefreshTick: 0

    property var navCards: regularData.concat(specialData)

    property int gapSide:  s(18)
    property int gapCard:  s(10)
    property int headerH:  s(34)
    property real availW:  width - gapSide * 2
    property real cardAR:  monH / monW

    property int flowCols: {
        let n = regularData.length
        if (n <= 0) return 1
        let ar = monW / monH
        let c = Math.max(1, Math.ceil(Math.sqrt(n * ar)))
        return Math.min(c, n)
    }

    property real cardW: (availW - (flowCols - 1) * gapCard) / Math.max(1, flowCols)
    property real cardH: cardW * cardAR

    property real specialCardW: cardW
    property real specialCardH: cardH

    property int regularRows: regularData.length > 0 ? Math.ceil(regularData.length / Math.max(1, flowCols)) : 0
    property real regularFlowH: regularRows > 0 ? (regularRows * cardH + Math.max(0, regularRows - 1) * gapCard) : 0

    property real contentH: {
        let h = gapSide + headerH + gapCard
        if (regularData.length > 0) h += regularFlowH
        if (specialData.length > 0) h += gapCard + s(18) + gapCard + specialCardH
        return h + gapSide
    }

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 80000; loops: Animation.Infinite; running: true
    }

    property real introProgress: 0.0
    NumberAnimation on introProgress {
        from: 0.0; to: 1.0; duration: 380; easing.type: Easing.OutQuart; running: true
    }

    Timer {
        interval: 15000; running: true; repeat: true
        onTriggered: window.thumbRefreshTick++
    }

    Keys.onPressed: (event) => {
        let num = -1
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) num = event.key - Qt.Key_0
        else if (event.key === Qt.Key_0) num = 10
        if (num > 0) {
            let ws = window.regularData.find(w => w.id === num)
            if (ws) window.dispatchWs(ws)
            event.accepted = true
            return
        }

        let n = window.navCards.length
        if (n === 0) return

        let cur = window.selectedIndex
        if (cur < 0) {
            cur = window.regularData.findIndex(w => w.id === window.activeWsId)
            if (cur < 0) cur = 0
        }

        let cols = window.flowCols

        if (event.key === Qt.Key_Left || event.key === Qt.Key_A) {
            window.selectedIndex = Math.max(0, cur - 1)
            event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) {
            window.selectedIndex = Math.min(n - 1, cur + 1)
            event.accepted = true
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_W) {
            window.selectedIndex = Math.max(0, cur - cols)
            event.accepted = true
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) {
            window.selectedIndex = Math.min(n - 1, cur + cols)
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Space) {
            if (cur >= 0 && cur < n) window.dispatchWs(window.navCards[cur])
            event.accepted = true
        }
    }

    Process {
        id: dataPoller
        running: true
        command: ["bash", "-c",
            "jq -n " +
            "--argjson ws \"$(hyprctl workspaces -j)\" " +
            "--argjson cl \"$(hyprctl clients -j)\" " +
            "--argjson aw \"$(hyprctl activeworkspace -j)\" " +
            "--argjson mon \"$(hyprctl monitors -j)\" " +
            "'{workspaces:$ws,clients:$cl,activeId:$aw.id,activeSpecialId:($mon[0].specialWorkspace.id//0)}'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(this.text.trim())
                    window.regularData = d.workspaces.filter(w => w.id > 0).sort((a, b) => a.id - b.id)
                    window.specialData = d.workspaces.filter(w => w.id < 0).sort((a, b) => a.name.localeCompare(b.name))
                    window.clientData  = d.clients.filter(c => c.workspace && c.workspace.id !== 0)
                    window.activeWsId      = d.activeId
                    window.activeSpecialId = d.activeSpecialId
                } catch(e) {}
            }
        }
    }

    Timer { interval: 2000; running: true; repeat: true; onTriggered: dataPoller.running = true }

    Timer {
        interval: 50; running: true; repeat: true
        onTriggered: { if (!altTabPoller.running) altTabPoller.running = true }
    }

    Process {
        id: altTabPoller
        command: ["bash", "-c", "f=/tmp/qs_alttab_nav; [ -s \"$f\" ] && mv \"$f\" \"${f}_read\" 2>/dev/null && cat \"${f}_read\"; rm -f \"${f}_read\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let cmd = this.text.trim()
                if (cmd === "next") window.cycleNext()
                else if (cmd === "confirm") window.confirmSelection()
            }
        }
    }

    function cycleNext() {
        let n = window.navCards.length
        if (n === 0) return
        if (window.selectedIndex < 0) {
            let cur = window.regularData.findIndex(w => w.id === window.activeWsId)
            window.selectedIndex = ((cur >= 0 ? cur : 0) + 1) % n
        } else {
            window.selectedIndex = (window.selectedIndex + 1) % n
        }
    }

    function confirmSelection() {
        let n = window.navCards.length
        if (n === 0) { Quickshell.execDetached(["bash", "-c", "echo 'close' > /tmp/qs_widget_state"]); return }
        if (window.selectedIndex < 0) {
            let cur = window.regularData.findIndex(w => w.id === window.activeWsId)
            window.dispatchWs(window.navCards[((cur >= 0 ? cur : 0) + 1) % n])
        } else {
            window.dispatchWs(window.navCards[window.selectedIndex])
        }
    }

    function clientsFor(wsId) {
        let _ = window.clientData
        return clientData.filter(c => c.workspace.id === wsId)
    }

    function classColor(cls) {
        cls = (cls || "").toLowerCase()
        if (/vivaldi|chrome|chromium|brave/.test(cls))                      return window.blue
        if (/firefox/.test(cls))                                             return window.peach
        if (/code|vscodium|codium/.test(cls))                               return window.sapphire
        if (/nvim|vim|neovim/.test(cls))                                    return window.green
        if (/kitty|alacritty|foot|wezterm|ghostty|konsole|xterm/.test(cls)) return window.teal
        if (/vesktop|discord/.test(cls))                                     return window.mauve
        if (/spotify|rhythmbox/.test(cls))                                   return window.green
        if (/gimp|inkscape|blender|krita/.test(cls))                         return window.peach
        if (/telegram|signal/.test(cls))                                     return window.blue
        if (/obs/.test(cls))                                                 return window.red
        if (/steam|lutris|heroic/.test(cls))                                 return window.yellow
        if (/nautilus|thunar|dolphin|nemo/.test(cls))                        return window.teal
        return window.overlay1
    }

    function classIcon(cls) {
        cls = (cls || "").toLowerCase()
        if (/vivaldi|chrome|chromium|brave/.test(cls))                       return "󰖟"
        if (/firefox/.test(cls))                                              return "󰈹"
        if (/code|vscodium|codium/.test(cls))                                return "󰨞"
        if (/nvim|vim|neovim/.test(cls))                                     return ""
        if (/kitty|alacritty|foot|wezterm|ghostty|konsole|xterm/.test(cls))  return ""
        if (/vesktop|discord/.test(cls))                                      return "󰙯"
        if (/spotify/.test(cls))                                              return "󰓇"
        if (/telegram/.test(cls))                                             return "󰔁"
        if (/obs/.test(cls))                                                  return "󰐌"
        if (/steam/.test(cls))                                                return "󰓓"
        if (/nautilus|thunar|dolphin|nemo/.test(cls))                         return "󰝰"
        return "󰣆"
    }

    function specialName(ws) { return ws.name.replace("special:", "") }

    function dispatchWs(ws) {
        if (ws.id > 0 && window.activeSpecialId !== 0) {
            let spec = window.specialData.find(s => s.id === window.activeSpecialId)
            if (spec) Quickshell.execDetached(["hyprctl", "dispatch", "togglespecialworkspace", specialName(spec)])
        }
        if (ws.id > 0)
            Quickshell.execDetached(["hyprctl", "dispatch", "workspace", ws.id.toString()])
        else
            Quickshell.execDetached(["hyprctl", "dispatch", "togglespecialworkspace", specialName(ws)])
        Quickshell.execDetached(["bash", "-c", "echo 'close' > /tmp/qs_widget_state"])
    }

    // ── BACKGROUND (self-sizing, vertically centered in full-screen container) ─
    Rectangle {
        id: bg
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: window.contentH
        radius: s(16)
        color: window.base
        border.color: Qt.rgba(window.text.r, window.text.g, window.text.b, 0.06)
        border.width: 1
        clip: true
        opacity: window.introProgress
        transform: Translate { y: s(12) * (1 - window.introProgress) }
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Rectangle {
            width: parent.width * 0.55; height: width; radius: width / 2
            x: (parent.width * 0.5 - width * 0.5) + Math.cos(window.globalOrbitAngle * 1.2) * s(220)
            y: (parent.height * 0.5 - height * 0.5) + Math.sin(window.globalOrbitAngle * 1.2) * s(80)
            color: window.blue; opacity: 0.04
        }
        Rectangle {
            width: parent.width * 0.38; height: width; radius: width / 2
            x: (parent.width * 0.5 - width * 0.5) + Math.sin(window.globalOrbitAngle) * s(-200)
            y: (parent.height * 0.5 - height * 0.5) + Math.cos(window.globalOrbitAngle) * s(70)
            color: window.mauve; opacity: 0.03
        }

        Column {
            x: window.gapSide
            y: window.gapSide
            width: window.availW
            spacing: 0

            // ── HEADER ────────────────────────────────────────────────────────
            Row {
                id: headerRow
                width: parent.width
                height: window.headerH
                spacing: s(10)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󱇛"
                    font.family: "Iosevka Nerd Font"; font.pixelSize: s(16)
                    color: window.blue
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "WORKSPACES"
                    font.family: "JetBrains Mono"; font.weight: Font.Black
                    font.pixelSize: s(11); font.letterSpacing: s(2)
                    color: window.subtext0
                }
                Item { width: headerRow.width - x - countPill.width - s(40); height: 1 }
                Rectangle {
                    id: countPill
                    anchors.verticalCenter: parent.verticalCenter
                    height: s(20); radius: s(6)
                    width: countText.implicitWidth + s(16)
                    color: Qt.rgba(window.blue.r, window.blue.g, window.blue.b, 0.10)
                    border.color: Qt.rgba(window.blue.r, window.blue.g, window.blue.b, 0.22)
                    border.width: 1
                    Text {
                        id: countText
                        anchors.centerIn: parent
                        text: regularData.length + " workspaces  ·  " + clientData.filter(c => c.workspace.id > 0).length + " windows"
                        font.family: "JetBrains Mono"; font.pixelSize: s(10)
                        color: window.blue
                    }
                }
            }

            Item { width: 1; height: window.gapCard }

            // ── REGULAR WORKSPACES ────────────────────────────────────────────
            Flow {
                id: regularFlow
                width: parent.width
                spacing: window.gapCard
                Repeater {
                    model: window.regularData
                    delegate: cardDelegateComp
                }
            }

            // ── SPECIAL SECTION ───────────────────────────────────────────────
            Item {
                id: specialSection
                width: parent.width
                height: window.specialData.length > 0
                    ? (window.gapCard + s(18) + window.gapCard + window.specialCardH)
                    : 0
                visible: window.specialData.length > 0

                Item {
                    y: window.gapCard
                    width: parent.width
                    height: s(18)

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: s(8)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: s(20); height: 1
                            color: Qt.rgba(window.overlay0.r, window.overlay0.g, window.overlay0.b, 0.30)
                        }
                        Text {
                            id: specialDivLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: "SPECIAL"
                            font.family: "JetBrains Mono"; font.pixelSize: s(9); font.letterSpacing: s(2)
                            color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.7)
                        }
                    }
                    Rectangle {
                        anchors {
                            left: parent.left
                            leftMargin: s(20) + s(8) + specialDivLabel.implicitWidth + s(8)
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        height: 1
                        color: Qt.rgba(window.overlay0.r, window.overlay0.g, window.overlay0.b, 0.30)
                    }
                }

                Flow {
                    y: window.gapCard + s(18) + window.gapCard
                    x: Math.floor((parent.width - window.specialCardW) / 2)
                    width: window.specialCardW
                    spacing: window.gapCard
                    Repeater {
                        model: window.specialData
                        delegate: specialCardDelegateComp
                    }
                }
            }
        }
    }

    // ── REGULAR CARD COMPONENT ────────────────────────────────────────────────
    Component {
        id: cardDelegateComp
        Item {
            id: cardWrapper
            width:  window.cardW
            height: window.cardH

            property var wsData:      modelData
            property int flatIndex:   index
            property bool isActive:   wsData.id === window.activeWsId
            property bool isSelected: window.selectedIndex === flatIndex
            property bool isHovered:  cardMa.containsMouse
            property var wins:        window.clientsFor(wsData.id)
            property real mapScale:   width > s(20) ? (width - s(16)) / window.monW : 0
            property color accent:    window.blue
            property string thumbSrc: "file:///tmp/ws_thumbs/ws_" + wsData.id + ".png?v=" + window.thumbRefreshTick

            property real cardIntro: 0.0
            SequentialAnimation {
                running: true
                PauseAnimation { duration: index * 50 }
                NumberAnimation {
                    target: cardWrapper; property: "cardIntro"
                    from: 0.0; to: 1.0; duration: 340
                    easing.type: Easing.OutBack; easing.overshoot: 0.75
                }
            }

            opacity: cardIntro
            scale: cardIntro < 0.99 ? (0.88 + 0.12 * cardIntro) : (isHovered ? 1.025 : 1.0)
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
            transform: Translate { y: s(10) * (1 - cardWrapper.cardIntro) }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -s(6)
                radius: s(18)
                color: accent
                opacity: isSelected ? 0.22 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            Rectangle {
                anchors.centerIn: parent
                width: parent.width + s(10); height: parent.height + s(10)
                radius: s(14); color: "transparent"
                border.color: isSelected
                    ? Qt.rgba(accent.r, accent.g, accent.b, 0.60)
                    : Qt.rgba(accent.r, accent.g, accent.b, isActive ? 0.22 : 0.0)
                border.width: 2
                Behavior on border.color { ColorAnimation { duration: 150 } }
            }

            Rectangle {
                anchors.fill: parent
                radius: s(12)
                color: isActive
                    ? Qt.rgba(accent.r, accent.g, accent.b, 0.08)
                    : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, isHovered ? 0.65 : 0.45)
                border.color: isSelected
                    ? Qt.rgba(accent.r, accent.g, accent.b, 1.0)
                    : isActive
                        ? Qt.rgba(accent.r, accent.g, accent.b, isHovered ? 0.80 : 0.55)
                        : Qt.rgba(window.text.r, window.text.g, window.text.b, isHovered ? 0.18 : 0.08)
                border.width: (isActive || isSelected) ? 2 : 1
                Behavior on color        { ColorAnimation { duration: 180 } }
                Behavior on border.color { ColorAnimation { duration: 180 } }
                clip: true

                Rectangle {
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    height: parent.height * 0.35; radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(accent.r, accent.g, accent.b, isActive ? 0.07 : 0.0) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                Rectangle {
                    id: thumbArea
                    x: s(8); y: s(8) + s(26) + s(5)
                    width: parent.width - s(16)
                    height: parent.height - s(8) - s(26) - s(5) - s(8)
                    radius: s(7)
                    color: Qt.rgba(window.mantle.r, window.mantle.g, window.mantle.b, 0.85)
                    border.color: Qt.rgba(window.text.r, window.text.g, window.text.b, 0.05)
                    border.width: 1
                    clip: true

                    Image {
                        id: wsThumb
                        anchors.fill: parent
                        source: cardWrapper.thumbSrc
                        fillMode: Image.PreserveAspectCrop
                        cache: false; smooth: true; asynchronous: true

                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(0, 0, 0, isActive ? 0.10 : 0.28)
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(accent.r, accent.g, accent.b, isActive ? 0.07 : 0.0)
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                    }

                    Repeater {
                        model: cardWrapper.wins
                        delegate: Rectangle {
                            property var cl: modelData
                            property color tc: window.classColor(cl["class"])
                            visible: wsThumb.status !== Image.Ready
                            x: Math.max(0, cl.at[0] * cardWrapper.mapScale)
                            y: Math.max(0, (cl.at[1] - 60) * cardWrapper.mapScale)
                            width:  Math.max(s(6), cl.size[0] * cardWrapper.mapScale)
                            height: Math.max(s(4), cl.size[1] * cardWrapper.mapScale)
                            radius: s(3); clip: true
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0.0; color: Qt.rgba(tc.r, tc.g, tc.b, 0.70) }
                                GradientStop { position: 1.0; color: Qt.rgba(tc.r, tc.g, tc.b, 0.40) }
                            }
                            border.color: Qt.rgba(tc.r, tc.g, tc.b, 0.90); border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: window.classIcon(cl["class"])
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: Math.min(s(16), Math.max(s(8), parent.height * 0.42))
                                color: Qt.rgba(tc.r, tc.g, tc.b, 1.0)
                                visible: parent.width > s(20) && parent.height > s(14)
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: s(4)
                        visible: wsThumb.status !== Image.Ready && cardWrapper.wins.length === 0
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "󰄰"; font.family: "Iosevka Nerd Font"; font.pixelSize: s(20)
                            color: Qt.rgba(window.overlay0.r, window.overlay0.g, window.overlay0.b, 0.35)
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "empty"; font.family: "JetBrains Mono"; font.pixelSize: s(8)
                            color: Qt.rgba(window.overlay0.r, window.overlay0.g, window.overlay0.b, 0.35)
                        }
                    }
                }

                Row {
                    x: s(8); y: s(8)
                    width: parent.width - s(16)
                    height: s(26)
                    spacing: s(6)

                    Rectangle {
                        width: s(24); height: s(24)
                        anchors.verticalCenter: parent.verticalCenter
                        radius: s(7)
                        color: isActive
                            ? Qt.rgba(accent.r, accent.g, accent.b, 0.28)
                            : Qt.rgba(window.surface2.r, window.surface2.g, window.surface2.b, 0.55)
                        border.color: isActive
                            ? Qt.rgba(accent.r, accent.g, accent.b, 0.45)
                            : Qt.rgba(window.text.r, window.text.g, window.text.b, 0.10)
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: wsData.id
                            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: s(11)
                            color: isActive ? accent : window.subtext0
                        }
                    }

                    Text {
                        width: parent.width - s(24) - s(6) - winBadge.width - s(6)
                        anchors.verticalCenter: parent.verticalCenter
                        text: wsData.windows > 0 ? wsData.lastwindowtitle : "empty"
                        font.family: "JetBrains Mono"; font.pixelSize: s(9)
                        font.weight: isActive ? Font.SemiBold : Font.Normal
                        color: isActive ? window.text : window.subtext0
                        elide: Text.ElideRight
                        opacity: isActive ? 1.0 : 0.75
                    }

                    Rectangle {
                        id: winBadge
                        anchors.verticalCenter: parent.verticalCenter
                        width: winBadgeLbl.implicitWidth + s(8); height: s(16); radius: s(5)
                        color: Qt.rgba(window.overlay0.r, window.overlay0.g, window.overlay0.b, 0.15)
                        visible: wsData.windows > 0
                        Text {
                            id: winBadgeLbl
                            anchors.centerIn: parent
                            text: wsData.windows
                            font.family: "JetBrains Mono"; font.pixelSize: s(9)
                            color: isActive ? Qt.rgba(accent.r, accent.g, accent.b, 0.9) : window.overlay0
                        }
                    }
                }

                MouseArea {
                    id: cardMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: window.dispatchWs(wsData)
                }

                Rectangle {
                    id: activeBorder
                    anchors.fill: parent
                    color: "transparent"
                    border.color: accent
                    border.width: s(2)
                    radius: parent.radius
                    opacity: 0.4
                    visible: isActive
                }
                SequentialAnimation {
                    running: isActive
                    loops: Animation.Infinite
                    NumberAnimation { target: activeBorder; property: "opacity"; to: 0.9; duration: 1200; easing.type: Easing.InOutSine }
                    NumberAnimation { target: activeBorder; property: "opacity"; to: 0.4; duration: 1200; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    // ── SPECIAL CARD COMPONENT ────────────────────────────────────────────────
    Component {
        id: specialCardDelegateComp
        Item {
            id: sCardWrapper
            width:  window.specialCardW
            height: window.specialCardH

            property var wsData:      modelData
            property int flatIndex:   window.regularData.length + index
            property bool isActive:   wsData.id === window.activeSpecialId
            property bool isSelected: window.selectedIndex === flatIndex
            property bool isHovered:  sCardMa.containsMouse
            property var wins:        window.clientsFor(wsData.id)
            property real mapScale:   width > s(20) ? (width - s(16)) / window.monW : 0
            property color accent:    window.mauve
            property string thumbSrc: "file:///tmp/ws_thumbs/ws_special_"
                                      + window.specialName(wsData) + ".png?v=" + window.thumbRefreshTick

            property real cardIntro: 0.0
            SequentialAnimation {
                running: true
                PauseAnimation { duration: (window.regularData.length + index) * 50 }
                NumberAnimation {
                    target: sCardWrapper; property: "cardIntro"
                    from: 0.0; to: 1.0; duration: 340
                    easing.type: Easing.OutBack; easing.overshoot: 0.75
                }
            }

            opacity: cardIntro
            scale: cardIntro < 0.99 ? (0.88 + 0.12 * cardIntro) : (isHovered ? 1.025 : 1.0)
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
            transform: Translate { y: s(10) * (1 - sCardWrapper.cardIntro) }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -s(6)
                radius: s(18)
                color: accent
                opacity: isSelected ? 0.22 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            Rectangle {
                anchors.centerIn: parent
                width: parent.width + s(10); height: parent.height + s(10)
                radius: s(14); color: "transparent"
                border.color: isSelected
                    ? Qt.rgba(accent.r, accent.g, accent.b, 0.60)
                    : Qt.rgba(accent.r, accent.g, accent.b, isActive ? 0.22 : 0.0)
                border.width: 2
                Behavior on border.color { ColorAnimation { duration: 150 } }
            }

            Rectangle {
                anchors.fill: parent
                radius: s(12)
                color: isActive
                    ? Qt.rgba(accent.r, accent.g, accent.b, 0.08)
                    : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, isHovered ? 0.65 : 0.45)
                border.color: isSelected
                    ? Qt.rgba(accent.r, accent.g, accent.b, 1.0)
                    : isActive
                        ? Qt.rgba(accent.r, accent.g, accent.b, isHovered ? 0.80 : 0.55)
                        : Qt.rgba(window.text.r, window.text.g, window.text.b, isHovered ? 0.18 : 0.08)
                border.width: (isActive || isSelected) ? 2 : 1
                Behavior on color        { ColorAnimation { duration: 180 } }
                Behavior on border.color { ColorAnimation { duration: 180 } }
                clip: true

                Rectangle {
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    height: parent.height * 0.35; radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(accent.r, accent.g, accent.b, isActive ? 0.07 : 0.0) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                Rectangle {
                    id: sThumbArea
                    x: s(8); y: s(8) + s(26) + s(5)
                    width: parent.width - s(16)
                    height: parent.height - s(8) - s(26) - s(5) - s(8)
                    radius: s(7)
                    color: Qt.rgba(window.mantle.r, window.mantle.g, window.mantle.b, 0.85)
                    border.color: Qt.rgba(window.text.r, window.text.g, window.text.b, 0.05)
                    border.width: 1
                    clip: true

                    Image {
                        id: sThumb
                        anchors.fill: parent
                        source: sCardWrapper.thumbSrc
                        fillMode: Image.PreserveAspectCrop
                        cache: false; smooth: true; asynchronous: true

                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(0, 0, 0, isActive ? 0.10 : 0.28)
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(accent.r, accent.g, accent.b, isActive ? 0.07 : 0.0)
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                    }

                    Repeater {
                        model: sCardWrapper.wins
                        delegate: Rectangle {
                            property var cl: modelData
                            property color tc: window.classColor(cl["class"])
                            visible: sThumb.status !== Image.Ready
                            x: Math.max(0, cl.at[0] * sCardWrapper.mapScale)
                            y: Math.max(0, (cl.at[1] - 60) * sCardWrapper.mapScale)
                            width:  Math.max(s(6), cl.size[0] * sCardWrapper.mapScale)
                            height: Math.max(s(4), cl.size[1] * sCardWrapper.mapScale)
                            radius: s(3); clip: true
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0.0; color: Qt.rgba(tc.r, tc.g, tc.b, 0.70) }
                                GradientStop { position: 1.0; color: Qt.rgba(tc.r, tc.g, tc.b, 0.40) }
                            }
                            border.color: Qt.rgba(tc.r, tc.g, tc.b, 0.90); border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: window.classIcon(cl["class"])
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: Math.min(s(16), Math.max(s(8), parent.height * 0.42))
                                color: Qt.rgba(tc.r, tc.g, tc.b, 1.0)
                                visible: parent.width > s(20) && parent.height > s(14)
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: s(4)
                        visible: sThumb.status !== Image.Ready && sCardWrapper.wins.length === 0
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "󰄰"; font.family: "Iosevka Nerd Font"; font.pixelSize: s(20)
                            color: Qt.rgba(window.overlay0.r, window.overlay0.g, window.overlay0.b, 0.35)
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "empty"; font.family: "JetBrains Mono"; font.pixelSize: s(8)
                            color: Qt.rgba(window.overlay0.r, window.overlay0.g, window.overlay0.b, 0.35)
                        }
                    }
                }

                Row {
                    x: s(8); y: s(8)
                    width: parent.width - s(16)
                    height: s(26)
                    spacing: s(6)

                    Rectangle {
                        width: s(24); height: s(24)
                        anchors.verticalCenter: parent.verticalCenter
                        radius: s(7)
                        color: isActive
                            ? Qt.rgba(accent.r, accent.g, accent.b, 0.28)
                            : Qt.rgba(window.surface2.r, window.surface2.g, window.surface2.b, 0.55)
                        border.color: isActive
                            ? Qt.rgba(accent.r, accent.g, accent.b, 0.45)
                            : Qt.rgba(window.text.r, window.text.g, window.text.b, 0.10)
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "✦"
                            font.pixelSize: s(9); font.weight: Font.Black
                            color: isActive ? accent : window.subtext0
                        }
                    }

                    Text {
                        width: parent.width - s(24) - s(6) - sWinBadge.width - s(6)
                        anchors.verticalCenter: parent.verticalCenter
                        text: window.specialName(wsData)
                        font.family: "JetBrains Mono"; font.pixelSize: s(9)
                        font.weight: isActive ? Font.SemiBold : Font.Normal
                        color: isActive ? window.text : window.subtext0
                        elide: Text.ElideRight
                        opacity: isActive ? 1.0 : 0.75
                    }

                    Rectangle {
                        id: sWinBadge
                        anchors.verticalCenter: parent.verticalCenter
                        width: sWinBadgeLbl.implicitWidth + s(8); height: s(16); radius: s(5)
                        color: Qt.rgba(window.overlay0.r, window.overlay0.g, window.overlay0.b, 0.15)
                        visible: wsData.windows > 0
                        Text {
                            id: sWinBadgeLbl
                            anchors.centerIn: parent
                            text: wsData.windows
                            font.family: "JetBrains Mono"; font.pixelSize: s(9)
                            color: isActive ? Qt.rgba(accent.r, accent.g, accent.b, 0.9) : window.overlay0
                        }
                    }
                }

                MouseArea {
                    id: sCardMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: window.dispatchWs(wsData)
                }

                Rectangle {
                    id: sActiveBorder
                    anchors.fill: parent
                    color: "transparent"
                    border.color: accent
                    border.width: s(2)
                    radius: parent.radius
                    opacity: 0.4
                    visible: isActive
                }
                SequentialAnimation {
                    running: isActive
                    loops: Animation.Infinite
                    NumberAnimation { target: sActiveBorder; property: "opacity"; to: 0.9; duration: 1200; easing.type: Easing.InOutSine }
                    NumberAnimation { target: sActiveBorder; property: "opacity"; to: 0.4; duration: 1200; easing.type: Easing.InOutSine }
                }
            }
        }
    }
}
