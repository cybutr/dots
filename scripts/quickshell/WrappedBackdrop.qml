import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets

Item {
    id: wb

    property color from1
    property color from2
    property string art: ""
    property real radius: 24
    property bool live: true
    property real artStrength: 0.55
    property real wash: 0.55
    Behavior on wash { NumberAnimation { duration: 500 } }
    property real breath: 0
    property real bedSpread: 0
    default property alias inner: innerSlot.data

    function hueOf(c) { return c.hslHue < 0 ? 0.72 : c.hslHue }
    function boost(c) {
        let s = c.hslHue < 0 ? 0.4 : Math.max(c.hslSaturation, 0.66)
        let l = Math.min(Math.max(c.hslLightness, 0.42), 0.56)
        return Qt.hsla(hueOf(c), s, l, 1.0)
    }

    property color tone1: boost(from1)
    property color tone2: boost(from2)
    Behavior on tone1 { ColorAnimation { duration: 700; easing.type: Easing.InOutQuad } }
    Behavior on tone2 { ColorAnimation { duration: 700; easing.type: Easing.InOutQuad } }
    readonly property color ink: Qt.hsla(hueOf(tone1), 0.5, 0.97, 1.0)
    readonly property color deep: Qt.hsla(hueOf(tone1), 0.6, 0.11, 1.0)
    readonly property color glow: Qt.hsla(hueOf(tone2), 0.9, 0.7, 1.0)
    readonly property bool running: live && visible && width > 0

    property int _front: -1
    function _swap() {
        if (wb.art === "") { wb._front = -1; return }
        let target = wb._front === 0 ? artB : artA
        let idx = wb._front === 0 ? 1 : 0
        if (String(target.source) === wb.art && target.status === Image.Ready) { wb._front = idx; return }
        target.source = wb.art
    }
    onArtChanged: _swap()
    Component.onCompleted: _swap()

    component Blob: Shape {
        id: blob
        property color tint
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: blob.width / 2; centerY: blob.height / 2
                focalX: blob.width / 2; focalY: blob.height / 2
                centerRadius: blob.width / 2
                GradientStop { position: 0.0; color: Qt.alpha(blob.tint, 0.85) }
                GradientStop { position: 0.4; color: Qt.alpha(blob.tint, 0.38) }
                GradientStop { position: 1.0; color: Qt.alpha(blob.tint, 0) }
            }
            PathRectangle { x: 0; y: 0; width: blob.width; height: blob.height }
        }
    }

    Item {
        id: bed
        visible: wb.bedSpread > 0
        anchors.fill: parent
        anchors.topMargin: wb.bedSpread * 0.3
        anchors.bottomMargin: -wb.bedSpread * 0.3
        opacity: 0.8 + 0.2 * wb.breath
        Repeater {
            model: 7
            delegate: Rectangle {
                readonly property real grow: (index + 1) * wb.bedSpread / 7
                x: -grow; y: -grow * 0.8
                width: bed.width + grow * 2; height: bed.height + grow * 1.8
                radius: wb.radius + grow
                color: Qt.alpha(wb.tone2, 0.055)
            }
        }
    }

    ClippingRectangle {
        id: stack
        anchors.fill: parent
        radius: wb.radius
        color: wb.tone1

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: wb.tone1 }
                GradientStop { position: 1.0; color: wb.tone2 }
            }
        }

        Image {
            id: artA
            anchors.fill: parent
            sourceSize: Qt.size(5, 5)
            smooth: true
            asynchronous: true
            fillMode: Image.Stretch
            opacity: wb._front === 0 ? wb.artStrength : 0
            Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }
            onStatusChanged: if (status === Image.Ready && String(source) === wb.art) wb._front = 0
        }
        Image {
            id: artB
            anchors.fill: parent
            sourceSize: Qt.size(5, 5)
            smooth: true
            asynchronous: true
            fillMode: Image.Stretch
            opacity: wb._front === 1 ? wb.artStrength : 0
            Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }
            onStatusChanged: if (status === Image.Ready && String(source) === wb.art) wb._front = 1
        }

        Blob {
            id: blobA
            tint: Qt.lighter(wb.tone1, 1.35)
            width: wb.height * 1.6; height: width
            y: -height * 0.35
            x: -width * 0.2
            opacity: 0.6
            SequentialAnimation on x {
                running: wb.running
                loops: Animation.Infinite
                NumberAnimation { to: wb.width * 0.45; duration: 11000; easing.type: Easing.InOutSine }
                NumberAnimation { to: -blobA.width * 0.25; duration: 11000; easing.type: Easing.InOutSine }
            }
            SequentialAnimation on y {
                running: wb.running
                loops: Animation.Infinite
                NumberAnimation { to: wb.height * 0.1; duration: 7000; easing.type: Easing.InOutSine }
                NumberAnimation { to: -blobA.height * 0.45; duration: 7000; easing.type: Easing.InOutSine }
            }
        }
        Blob {
            id: blobB
            tint: wb.glow
            width: wb.height * 1.3; height: width
            x: wb.width - width * 0.7
            y: wb.height - height * 0.5
            opacity: 0.45
            SequentialAnimation on x {
                running: wb.running
                loops: Animation.Infinite
                NumberAnimation { to: wb.width * 0.35; duration: 13000; easing.type: Easing.InOutSine }
                NumberAnimation { to: wb.width - blobB.width * 0.6; duration: 13000; easing.type: Easing.InOutSine }
            }
            SequentialAnimation on y {
                running: wb.running
                loops: Animation.Infinite
                NumberAnimation { to: -blobB.height * 0.2; duration: 9000; easing.type: Easing.InOutSine }
                NumberAnimation { to: wb.height - blobB.height * 0.45; duration: 9000; easing.type: Easing.InOutSine }
            }
        }

        Item {
            id: innerSlot
            anchors.fill: parent
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.alpha(wb.deep, wb.wash) }
                GradientStop { position: 0.62; color: Qt.alpha(wb.deep, wb.wash * 0.15) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(wb.ink, 0.10) }
                GradientStop { position: 0.35; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.alpha(wb.deep, wb.wash * 0.6) }
            }
        }

        Rectangle {
            id: sheen
            width: wb.height * 0.9
            height: wb.height * 3
            y: -wb.height
            x: -width * 2
            rotation: 22
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.alpha(wb.ink, 0.16) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            SequentialAnimation on x {
                running: wb.running
                loops: Animation.Infinite
                PauseAnimation { duration: 2600 }
                NumberAnimation { from: -sheen.width * 2; to: wb.width + sheen.width; duration: 1600; easing.type: Easing.InOutCubic }
                PauseAnimation { duration: 5200 }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: wb.radius
        color: "transparent"
        border.width: 1.5
        border.color: Qt.alpha(wb.ink, 0.16 + 0.14 * wb.breath)
    }
    SequentialAnimation on breath {
        running: wb.running
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 2200; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 2200; easing.type: Easing.InOutSine }
    }
}
