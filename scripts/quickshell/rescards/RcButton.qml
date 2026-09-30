import QtQuick

Row {
    id: rb

    property var bar
    property var theme
    property color accent: theme ? theme.mauve : "transparent"
    property string label: ""
    property bool showLater: true
    signal primary()
    signal later()

    function s(v) { return rb.bar ? rb.bar.s(v) : v }

    spacing: s(10)

    Rectangle {
        visible: rb.label !== ""
        width: rbText.implicitWidth + rb.s(22)
        height: rb.s(24)
        radius: height / 2
        color: rbMa.containsMouse ? rb.accent : Qt.alpha(rb.accent, 0.22)
        border.width: 1; border.color: Qt.alpha(rb.accent, 0.45)
        scale: rbMa.pressed ? 0.94 : (rbMa.containsMouse ? 1.05 : 1)
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        Text {
            id: rbText
            anchors.centerIn: parent
            text: rb.label
            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: rb.s(10)
            color: rb.theme ? (rbMa.containsMouse ? rb.theme.crust : rb.theme.text) : "transparent"
        }
        MouseArea { id: rbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.primary() }
    }

    Text {
        visible: rb.showLater
        anchors.verticalCenter: parent.verticalCenter
        text: "later"
        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: rb.s(10)
        color: rb.theme ? (rbLaterMa.containsMouse ? rb.theme.text : rb.theme.subtext0) : "transparent"
        MouseArea { id: rbLaterMa; anchors.fill: parent; anchors.margins: -rb.s(5); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.later() }
    }
}
