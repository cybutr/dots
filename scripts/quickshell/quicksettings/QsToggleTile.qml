import QtQuick
import QtQuick.Layouts

// Big touch-friendly toggle pill — icon, label, status text, colored fill
// when active. Shared by every row in QuickSettingsDrawer.qml.
Rectangle {
    id: tile

    property string icon: ""
    property string label: ""
    property string sub: ""
    property bool active: false
    property color accent: "#89b4fa"
    property var theme: null // exposes .s(), .text, .subtext0, .surface0, .surface1

    signal toggled()

    Layout.fillWidth: true
    Layout.preferredHeight: theme ? theme.s(64) : 64
    radius: theme ? theme.s(16) : 16
    color: theme ? theme.surface0 : "#313244"
    border.width: 1
    border.color: active ? accent : (theme ? theme.surface1 : "#45475a")
    Behavior on border.color { ColorAnimation { duration: 200 } }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: accent
        opacity: tile.active ? 0.16 : 0.0
        Behavior on opacity { NumberAnimation { duration: 220 } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: theme ? theme.s(14) : 14
        spacing: theme ? theme.s(14) : 14

        Item {
            Layout.preferredWidth: theme ? theme.s(40) : 40
            Layout.preferredHeight: theme ? theme.s(40) : 40
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: accent
                opacity: tile.active ? 0.22 : 0.10
                Behavior on opacity { NumberAnimation { duration: 220 } }
            }
            Text {
                anchors.centerIn: parent
                font.family: "Iosevka Nerd Font"
                font.pixelSize: theme ? theme.s(20) : 20
                color: tile.active ? accent : (theme ? theme.subtext0 : "#a6adc8")
                text: tile.icon
                Behavior on color { ColorAnimation { duration: 200 } }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                text: tile.label
                font.family: "JetBrains Mono"
                font.weight: Font.Bold
                font.pixelSize: theme ? theme.s(13) : 13
                color: theme ? theme.text : "#cdd6f4"
            }
            Text {
                text: tile.sub
                font.family: "JetBrains Mono"
                font.pixelSize: theme ? theme.s(11) : 11
                color: theme ? theme.subtext0 : "#a6adc8"
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        Rectangle {
            Layout.preferredWidth: theme ? theme.s(46) : 46
            Layout.preferredHeight: theme ? theme.s(26) : 26
            radius: height / 2
            color: tile.active ? accent : (theme ? theme.surface1 : "#45475a")
            Behavior on color { ColorAnimation { duration: 200 } }

            Rectangle {
                width: parent.height - 4
                height: parent.height - 4
                radius: height / 2
                anchors.verticalCenter: parent.verticalCenter
                x: tile.active ? parent.width - width - 2 : 2
                color: "#ffffff"
                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.toggled()
    }
}
