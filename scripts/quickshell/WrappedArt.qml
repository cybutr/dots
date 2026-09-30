import QtQuick
import Quickshell.Widgets

Item {
    id: wa

    property string art: ""
    property real radius: 12
    property color fallback
    property color shadowColor: "transparent"
    property real shadowOffset: 0
    property color edge: "transparent"
    readonly property bool ready: artImg.status === Image.Ready

    Rectangle {
        visible: wa.shadowOffset > 0
        anchors.fill: parent
        anchors.topMargin: wa.shadowOffset
        anchors.bottomMargin: -wa.shadowOffset
        anchors.leftMargin: wa.shadowOffset * 0.4
        anchors.rightMargin: -wa.shadowOffset * 0.4
        radius: wa.radius
        color: wa.shadowColor
    }
    ClippingRectangle {
        anchors.fill: parent
        radius: wa.radius
        color: wa.fallback
        Image {
            id: artImg
            anchors.fill: parent
            source: wa.art
            sourceSize: Qt.size(Math.max(64, Math.round(wa.width * 2)), Math.max(64, Math.round(wa.height * 2)))
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            opacity: wa.ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: wa.radius
        color: "transparent"
        border.width: 1
        border.color: wa.edge
    }
}
