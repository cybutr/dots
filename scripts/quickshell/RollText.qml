import QtQuick

Item {
    id: root

    property string val: ""
    property string fontFamily: "JetBrains Mono"
    property int pixelSize: 13
    property int weight: Font.Black
    property color color: "white"
    property int rollH: pixelSize + 4

    width: sizer.implicitWidth
    height: rollH
    clip: true

    property string _shown: ""
    property int _dir: 1

    function _num(s) { let m = ("" + s).match(/-?\d+/); return m ? parseInt(m[0]) : NaN }

    Text { id: sizer; visible: false; text: root.val; font.family: root.fontFamily; font.pixelSize: root.pixelSize; font.weight: root.weight }

    Text {
        id: outgoing
        anchors.horizontalCenter: parent.horizontalCenter
        font.family: root.fontFamily; font.pixelSize: root.pixelSize; font.weight: root.weight
        color: root.color
        y: 0
    }
    Text {
        id: incoming
        anchors.horizontalCenter: parent.horizontalCenter
        font.family: root.fontFamily; font.pixelSize: root.pixelSize; font.weight: root.weight
        color: root.color
        text: root.val
        y: 0
    }

    onValChanged: {
        if (_shown === "") { _shown = val; incoming.text = val; incoming.y = 0; outgoing.opacity = 0; return }
        if (val === _shown) return
        let a = _num(_shown), b = _num(val)
        _dir = (!isNaN(a) && !isNaN(b)) ? (b >= a ? 1 : -1) : 1
        outgoing.text = _shown
        outgoing.y = 0; outgoing.opacity = 1
        incoming.text = val
        incoming.y = _dir > 0 ? rollH : -rollH   // increased → new rolls up from below
        incoming.opacity = 0
        rollAnim.restart()
        _shown = val
    }

    ParallelAnimation {
        id: rollAnim
        NumberAnimation { target: incoming; property: "y"; to: 0; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: outgoing; property: "y"; to: root._dir > 0 ? -root.rollH : root.rollH; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: incoming; property: "opacity"; to: 1; duration: 200 }
        NumberAnimation { target: outgoing; property: "opacity"; to: 0; duration: 200 }
    }
}
