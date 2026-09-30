import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import "./"

// output volume OSD. trigger file payload: "<percent>" or "muted"
// percent can exceed 100 (overcharge) - bar and accent switch to a warning
// color past 100 instead of just flattening against a wider scale.
OsdBase {
    id: osd
    WlrLayershell.namespace: "qs-volume-osd"
    watchFile: "/tmp/qs_volume_osd"
    holdMs: 1200

    readonly property int overchargeMax: 150
    property bool muted: false
    property int vol: 0
    readonly property bool overcharged: !osd.muted && osd.vol > 100

    accent: osd.muted ? osd.cRed : (osd.overcharged ? "#ff9a3c" : osd.cBlue)

    onTriggered: (text) => {
        let t = text.trim()
        if (t === "muted") {
            osd.muted = true
        } else {
            osd.muted = false
            osd.vol = Math.max(0, parseInt(t) || 0)
        }
    }

    RowLayout {
        spacing: osd.s(14)

        Text {
            font.family: "Iosevka Nerd Font"; font.pixelSize: osd.s(20)
            color: osd.accent
            text: osd.muted ? "󰖁" : (osd.overcharged ? "󰕾" : (osd.vol > 50 ? "󰕾" : (osd.vol > 0 ? "󰖀" : "󰕿")))
        }

        // Track: fixed width representing 0-100%. Past 100 the fill keeps
        // going in an "overcharge" strip appended past the normal end, so
        // 100% always looks the same (full) and only the extra spills over.
        Item {
            Layout.preferredWidth: osd.s(160)
            Layout.preferredHeight: osd.s(10)

            Rectangle {
                id: track
                width: osd.s(130)
                height: parent.height
                radius: height / 2
                color: osd.cMantle
                border.width: 1
                border.color: Qt.rgba(osd.cText.r, osd.cText.g, osd.cText.b, 0.08)
                clip: true

                Rectangle {
                    height: parent.height
                    width: parent.width * (Math.min(100, osd.vol) / 100)
                    radius: parent.height / 2
                    color: osd.muted ? osd.cSubtext0 : osd.cBlue
                    opacity: osd.muted ? 0.35 : 1.0
                }
            }

            // Overcharge strip - only appears past 100%, separated by a gap
            // so it reads as a distinct "extra" zone, not a bigger normal bar.
            Rectangle {
                anchors.left: track.right
                anchors.leftMargin: osd.s(6)
                width: osd.s(24) * (Math.min(osd.overchargeMax, osd.vol) - 100) / (osd.overchargeMax - 100)
                height: parent.height
                radius: height / 2
                visible: osd.overcharged
                color: "#ff9a3c"
                Behavior on width { NumberAnimation { duration: 150 } }
            }
        }

        Text {
            Layout.preferredWidth: osd.s(38)
            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: osd.s(14)
            color: osd.overcharged ? "#ff9a3c" : osd.cText
            text: osd.muted ? "MUTE" : (osd.vol + "%")
            horizontalAlignment: Text.AlignRight
        }
    }
}
