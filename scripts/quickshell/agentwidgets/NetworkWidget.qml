import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

// Agent-only: live network + ProtonVPN status panel.
FocusScope {
    id: win
    focus: true

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(v) { return scaler.s(v) }
    MatugenColors { id: th }
    readonly property color accent: th.blue || "#89b4fa"
    readonly property color good: th.green || "#a6e3a1"
    readonly property color bad: th.red || "#f38ba8"

    function close() { Quickshell.execDetached(["bash", "-c", "echo close > /tmp/qs_widget_state"]) }

    property real intro: 0
    NumberAnimation on intro { from: 0; to: 1; duration: 360; easing.type: Easing.OutBack; easing.overshoot: 1.05; running: true }
    Timer { interval: 900; running: true; onTriggered: win.intro = 1 }

    Rectangle {
        anchors.fill: parent; radius: s(22)
        color: Qt.rgba(th.crust.r, th.crust.g, th.crust.b, 0.98)
        border.width: 1; border.color: Qt.rgba(th.text.r, th.text.g, th.text.b, 0.08)
        opacity: win.intro
        transform: Scale { origin.x: width/2; origin.y: height/2; xScale: win.intro; yScale: win.intro }
        Rectangle { anchors.fill: parent; radius: parent.radius; gradient: Gradient { GradientStop { position: 0.0; color: Qt.rgba(th.surface0.r, th.surface0.g, th.surface0.b, 0.4) } GradientStop { position: 1.0; color: "transparent" } } }

        Column {
            anchors.fill: parent; anchors.margins: s(24); spacing: s(16)

            Row {
                spacing: s(10)
                Rectangle { width: s(28); height: s(28); radius: s(9); color: Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.18)
                    Text { anchors.centerIn: parent; text: "󰒩"; font.family: "Iosevka Nerd Font"; font.pixelSize: win.s(15); color: win.accent } }
                Text { text: "Network"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: win.s(18); color: th.text; anchors.verticalCenter: parent.verticalCenter }
            }

            Rectangle {
                width: parent.width; height: s(120); radius: s(14)
                color: Qt.rgba(th.mantle.r, th.mantle.g, th.mantle.b, 0.6)
                border.width: 1; border.color: Qt.rgba(th.text.r, th.text.g, th.text.b, 0.06)
                Column { anchors.fill: parent; anchors.margins: win.s(16); spacing: win.s(8)
                    Row { spacing: win.s(8)
                        Text { text: "󰤨"; font.family: "Iosevka Nerd Font"; font.pixelSize: win.s(18); color: win.accent }
                        Text { text: net.ssid || "—"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: win.s(15); color: th.text; elide: Text.ElideRight; width: win.s(380) } }
                    Text { text: "IP  " + (net.ip || "—"); font.family: "JetBrains Mono"; font.pixelSize: win.s(11); color: th.subtext0 }
                    Text { text: "GW  " + (net.gw || "—"); font.family: "JetBrains Mono"; font.pixelSize: win.s(11); color: th.subtext0 }
                }
            }

            Rectangle {
                width: parent.width; height: s(150); radius: s(14)
                color: Qt.rgba(th.mantle.r, th.mantle.g, th.mantle.b, 0.6)
                border.width: 1
                border.color: vpn.connected ? Qt.rgba(win.good.r, win.good.g, win.good.b, 0.3) : Qt.rgba(th.text.r, th.text.g, th.text.b, 0.06)
                Column { anchors.fill: parent; anchors.margins: win.s(16); spacing: win.s(8)
                    Row { spacing: win.s(8)
                        Rectangle { width: win.s(10); height: win.s(10); radius: width/2; anchors.verticalCenter: parent.verticalCenter; color: vpn.connected ? win.good : win.bad
                            SequentialAnimation on scale { running: vpn.connected; loops: Animation.Infinite
                                NumberAnimation { to: 1.3; duration: 900; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine } } }
                        Text { text: vpn.connected ? "ProtonVPN · connected" : "ProtonVPN · idle"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: win.s(14); color: th.text } }
                    Text { visible: vpn.connected; text: "Server  " + (vpn.server || ""); font.family: "JetBrains Mono"; font.pixelSize: win.s(11); color: th.subtext0; elide: Text.ElideRight; width: win.s(420) }
                    Text { text: "Auto-vpn on this wifi:  " + (vpn.auto ? "yes" : "no"); font.family: "JetBrains Mono"; font.pixelSize: win.s(11); color: th.subtext0 }
                    Text { text: vpn.note; font.family: "JetBrains Mono"; font.pixelSize: win.s(10); color: th.subtext0; wrapMode: Text.Wrap; width: win.s(420) }
                }
            }
        }
        Text { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottomMargin: win.s(8)
            text: "esc / click outside to close"; font.family: "JetBrains Mono"; font.pixelSize: win.s(9); color: th.subtext0 }
    }

    property var net: ({ ssid: "", ip: "", gw: "" })
    property var vpn: ({ connected: false, server: "", auto: false, note: "" })

    Process {
        id: netReader
        running: true
        command: ["bash", "-c", "ssid=$(nmcli -t -f ACTIVE,SSID device wifi 2>/dev/null | grep '^yes:' | cut -d: -f2); ip=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1); gw=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1); printf '{\"ssid\":\"%s\",\"ip\":\"%s\",\"gw\":\"%s\"}' \"$ssid\" \"$ip\" \"$gw\""]
        stdout: StdioCollector { onStreamFinished: { try { win.net = JSON.parse(this.text.trim() || "{}") } catch (e) {} } }
    }
    Timer { interval: 4000; repeat: true; running: true; onTriggered: { netReader.running = false; netReader.running = true } }

    Process {
        id: vpnReader
        running: true
        command: ["bash", "-c", "python3 -c \"import importlib.util,os,json; b=os.path.expanduser('~/.config/hypr/scripts/quickshell/claude'); s=importlib.util.spec_from_file_location('qs_mcp',b+'/qs_mcp.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); r=m.t_vpn_control({'action':'status'}); print(json.dumps({'connected':r.get('connected',False),'server':r.get('server',''),'auto':r.get('auto_here',False)}))\" 2>/dev/null || echo '{}'"]
        stdout: StdioCollector { onStreamFinished: {
            try { let d = JSON.parse(this.text.trim() || "{}")
                  win.vpn = { connected: d.connected||false, server: d.server||"", auto: !!d.auto, note: d.auto ? "Auto-connects here." : "Idle unless told." } }
            catch (e) {} } }
    }
    Timer { interval: 5000; repeat: true; running: true; onTriggered: { vpnReader.running = false; vpnReader.running = true } }

    Keys.onEscapePressed: win.close()
}
