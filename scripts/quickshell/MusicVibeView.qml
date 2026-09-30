import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

ColumnLayout {
    id: vibe
    property var host: null
    property var ui: null
    property bool active: false
    readonly property var p: host && host.stats ? (host.stats.personality || null) : null
    readonly property bool hasData: p !== null && ui !== null
    readonly property var facts: hasData ? p.facts : ({})
    readonly property string fanArtist: hasData ? facts.superfan.artist : ""
    readonly property var pal: hasData ? host.paletteFor(fanArtist, "", 2) : ["#888888", "#888888"]
    readonly property var traitColors: ui ? ({
        night: ui.mauve, morning: ui.peach, replay: ui.pink, loyal: ui.red,
        explore: ui.teal, marathon: ui.blue, vintage: ui.yellow
    }) : ({})
    function tint(key) { return host.boost(traitColors[key] || ui.mauve) }
    function pct(v) { return Math.round((v || 0) * 100) + "%" }
    function focusWord(d) { return d < 25 ? "Laser-focused" : d < 50 ? "Focused" : d < 75 ? "Eclectic" : "All over the map" }
    function titleCase(s) { return String(s || "").replace(/\b\w/g, function (c) { return c.toUpperCase() }) }
    function fmtSpan(secs) {
        let h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60)
        return h > 0 ? h + "h " + m + "m" : m + "m"
    }

    property real prog: 0
    NumberAnimation { id: vibeIn; target: vibe; property: "prog"; from: 0; to: 1; duration: 1400; easing.type: Easing.OutCubic }
    onActiveChanged: if (active) vibeIn.restart()
    Component.onCompleted: if (active) vibeIn.restart()

    Layout.fillWidth: true
    spacing: ui ? ui.s(22) : 22

    component SectionTitle: Text {
        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui.s(16)
        color: vibe.ui.text
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: ui ? ui.s(120) : 0
        visible: !vibe.hasData && ui !== null
        radius: ui ? ui.s(28) : 0
        color: ui ? ui.surface0 : "transparent"
        border.width: 1; border.color: ui ? ui.surface1 : "transparent"
        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - (vibe.ui ? vibe.ui.s(80) : 0)
            spacing: vibe.ui ? vibe.ui.s(6) : 0
            Text { Layout.alignment: Qt.AlignHCenter; text: "Still getting to know you"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui ? vibe.ui.s(18) : 18; color: vibe.ui ? vibe.ui.text : "white" }
            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: "Needs at least 20 logged plays before a personality read means anything."; font.family: "JetBrains Mono"; font.pixelSize: vibe.ui ? vibe.ui.s(11) : 11; color: vibe.ui ? vibe.ui.subtext0 : "white" }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: vibe.hasData ? vibe.ui.s(284) : 0
        visible: vibe.hasData

        WrappedBackdrop {
            id: typeBg
            anchors.fill: parent
            anchors.bottomMargin: vibe.ui ? vibe.ui.s(14) : 0
            radius: vibe.ui ? vibe.ui.s(32) : 0
            bedSpread: vibe.ui ? vibe.ui.s(24) : 0
            from1: vibe.hasData ? vibe.tint(vibe.p.archetype.key) : "#888888"
            from2: vibe.pal[1]
            art: vibe.hasData ? vibe.host.artFor(vibe.fanArtist, "") : ""
            live: vibe.active
            wash: 0.5
        }

        Item {
            id: medal
            anchors.left: typeBg.left; anchors.leftMargin: vibe.ui ? vibe.ui.s(34) : 0
            anchors.verticalCenter: typeBg.verticalCenter
            width: typeBg.height - (vibe.ui ? vibe.ui.s(64) : 0); height: width
            scale: 0.6 + 0.4 * vibe.prog
            opacity: Math.min(1, vibe.prog * 2)

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.alpha(typeBg.deep, 0.38)
                border.width: vibe.ui ? vibe.ui.s(2) : 2
                border.color: Qt.alpha(typeBg.ink, 0.35)
            }
            Shape {
                id: orbit
                anchors.fill: parent
                anchors.margins: -(vibe.ui ? vibe.ui.s(10) : 10)
                RotationAnimation on rotation { running: vibe.active; loops: Animation.Infinite; from: 0; to: 360; duration: 24000 }
                ShapePath {
                    strokeWidth: vibe.ui ? vibe.ui.s(2) : 2
                    strokeColor: Qt.alpha(typeBg.ink, 0.5)
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [1, 5]
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathAngleArc { centerX: orbit.width / 2; centerY: orbit.height / 2; radiusX: orbit.width / 2 - 2; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
                }
            }
            Rectangle {
                width: vibe.ui ? vibe.ui.s(12) : 12; height: width; radius: width / 2
                color: typeBg.glow
                x: orbit.x + orbit.width / 2 + (orbit.width / 2 - 2) * Math.cos(orbit.rotation * Math.PI / 180) - width / 2
                y: orbit.y + orbit.height / 2 + (orbit.height / 2 - 2) * Math.sin(orbit.rotation * Math.PI / 180) - height / 2
            }
            Text {
                anchors.centerIn: parent
                text: vibe.hasData ? vibe.p.archetype.glyph : ""
                font.family: "Iosevka Nerd Font"; font.pixelSize: medal.width * 0.46
                color: typeBg.ink
                style: Text.Raised; styleColor: Qt.alpha(typeBg.deep, 0.5)
            }
        }

        ColumnLayout {
            anchors.left: medal.right; anchors.leftMargin: vibe.ui ? vibe.ui.s(44) : 0
            anchors.right: typeBg.right; anchors.rightMargin: vibe.ui ? vibe.ui.s(30) : 0
            anchors.verticalCenter: typeBg.verticalCenter
            spacing: vibe.ui ? vibe.ui.s(4) : 0
            transform: Translate { x: (1 - vibe.prog) * (vibe.ui ? vibe.ui.s(30) : 0) }
            opacity: vibe.prog

            Rectangle {
                Layout.preferredWidth: typeEyebrow.implicitWidth + (vibe.ui ? vibe.ui.s(18) : 0)
                Layout.preferredHeight: vibe.ui ? vibe.ui.s(20) : 0
                Layout.bottomMargin: vibe.ui ? vibe.ui.s(2) : 0
                radius: height / 2
                color: Qt.alpha(typeBg.ink, 0.16)
                border.width: 1; border.color: Qt.alpha(typeBg.ink, 0.22)
                Text {
                    id: typeEyebrow
                    anchors.centerIn: parent
                    text: "YOUR LISTENER TYPE"
                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui ? vibe.ui.s(9) : 9; font.letterSpacing: vibe.ui ? vibe.ui.s(1.2) : 1
                    color: typeBg.ink
                }
            }
            Text {
                Layout.fillWidth: true
                text: vibe.hasData ? vibe.p.archetype.name : ""
                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui ? vibe.ui.s(44) : 44; font.letterSpacing: -(vibe.ui ? vibe.ui.s(1.5) : 1)
                color: typeBg.ink
                style: Text.Raised; styleColor: Qt.alpha(typeBg.deep, 0.45)
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: vibe.hasData ? vibe.p.archetype.blurb : ""
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: vibe.ui ? vibe.ui.s(13) : 13
                color: Qt.alpha(typeBg.ink, 0.88)
            }
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: vibe.ui ? vibe.ui.s(10) : 0
                spacing: vibe.ui ? vibe.ui.s(8) : 0
                Repeater {
                    model: vibe.hasData ? [{ k: "BECAUSE", v: vibe.p.archetype.because }].concat(vibe.p.archetype.runnersUp.map(function (r) { return { k: "ALSO", v: r.fact } })) : []
                    delegate: Rectangle {
                        width: Math.min(tagRow.implicitWidth + vibe.ui.s(22), typeBg.width * 0.62)
                        height: vibe.ui.s(28)
                        radius: height / 2
                        color: Qt.alpha(typeBg.ink, tagMa.containsMouse ? 0.24 : 0.15)
                        border.width: 1; border.color: Qt.alpha(typeBg.ink, 0.24)
                        scale: tagMa.containsMouse ? 1.04 : 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                        Row {
                            id: tagRow
                            anchors.centerIn: parent
                            spacing: vibe.ui.s(8)
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.k; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui.s(9); font.letterSpacing: vibe.ui.s(1); color: Qt.alpha(typeBg.ink, 0.7) }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.v; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: vibe.ui.s(11); color: typeBg.ink }
                        }
                        MouseArea { id: tagMa; anchors.fill: parent; hoverEnabled: true }
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: vibe.hasData
        spacing: vibe.ui ? vibe.ui.s(12) : 0
        RowLayout {
            Layout.fillWidth: true
            SectionTitle { text: "Your listening DNA" }
            Item { Layout.fillWidth: true }
            Text {
                text: "how strongly each habit shows up in your plays"
                font.family: "JetBrains Mono"; font.pixelSize: vibe.ui ? vibe.ui.s(10) : 10; color: vibe.ui ? vibe.ui.subtext0 : "white"
            }
        }
        GridLayout {
            Layout.fillWidth: true
            columns: 4
            columnSpacing: vibe.ui ? vibe.ui.s(12) : 0
            rowSpacing: vibe.ui ? vibe.ui.s(12) : 0
            Repeater {
                model: vibe.hasData ? vibe.p.traits : []
                delegate: Rectangle {
                    id: tc
                    readonly property color accent: vibe.tint(modelData.key)
                    readonly property bool isType: vibe.p.archetype.key === modelData.key
                    property real reveal: 0
                    SequentialAnimation {
                        id: tcIn
                        PropertyAction { target: tc; property: "reveal"; value: 0 }
                        PauseAnimation { duration: 70 * index }
                        NumberAnimation { target: tc; property: "reveal"; to: 1; duration: 900; easing.type: Easing.OutCubic }
                    }
                    Connections { target: vibe; function onActiveChanged() { if (vibe.active) tcIn.restart() } }
                    Component.onCompleted: if (vibe.active) tcIn.restart()
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: vibe.ui.s(186)
                    radius: vibe.ui.s(26)
                    color: Qt.alpha(accent, tcMa.containsMouse ? 0.2 : (isType ? 0.17 : 0.1))
                    border.width: isType ? 2 : 1
                    border.color: Qt.alpha(accent, isType ? 0.7 : (tcMa.containsMouse ? 0.5 : 0.26))
                    scale: tcMa.containsMouse ? 1.03 : 1
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: 160 } }

                    Rectangle {
                        visible: tc.isType
                        anchors.top: parent.top; anchors.right: parent.right
                        anchors.topMargin: vibe.ui.s(12); anchors.rightMargin: vibe.ui.s(12)
                        width: typeBadge.implicitWidth + vibe.ui.s(14); height: vibe.ui.s(18)
                        radius: height / 2
                        color: tc.accent
                        Text { id: typeBadge; anchors.centerIn: parent; text: "YOUR TYPE"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui.s(8); font.letterSpacing: vibe.ui.s(0.8); color: vibe.ui.crust }
                    }

                    Item {
                        id: ring
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top; anchors.topMargin: vibe.ui.s(18)
                        width: vibe.ui.s(84); height: width
                        Shape {
                            anchors.fill: parent
                            ShapePath {
                                strokeWidth: vibe.ui.s(8)
                                strokeColor: Qt.alpha(tc.accent, 0.18)
                                fillColor: "transparent"
                                PathAngleArc { centerX: ring.width / 2; centerY: ring.height / 2; radiusX: ring.width / 2 - vibe.ui.s(5); radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
                            }
                            ShapePath {
                                strokeWidth: vibe.ui.s(8)
                                strokeColor: tc.accent
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                PathAngleArc { centerX: ring.width / 2; centerY: ring.height / 2; radiusX: ring.width / 2 - vibe.ui.s(5); radiusY: radiusX; startAngle: -90; sweepAngle: Math.max(0.5, 360 * modelData.value * tc.reveal) }
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: Math.round(modelData.value * 100 * tc.reveal) + "%"
                            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui.s(19)
                            color: vibe.ui.text
                        }
                    }
                    ColumnLayout {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: ring.bottom
                        anchors.leftMargin: vibe.ui.s(14); anchors.rightMargin: vibe.ui.s(14); anchors.topMargin: vibe.ui.s(12)
                        spacing: vibe.ui.s(3)
                        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: modelData.label.toUpperCase(); font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui.s(11); font.letterSpacing: vibe.ui.s(1); color: tc.accent; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: modelData.fact; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: vibe.ui.s(10); color: vibe.ui.subtext0 }
                    }
                    MouseArea { id: tcMa; anchors.fill: parent; hoverEnabled: true }
                }
            }
            Rectangle {
                readonly property int n: vibe.hasData ? vibe.p.traits.length : 0
                visible: n % 4 !== 0
                Layout.columnSpan: Math.max(1, 4 - n % 4)
                Layout.fillWidth: true
                Layout.preferredWidth: Layout.columnSpan
                Layout.preferredHeight: vibe.ui ? vibe.ui.s(186) : 0
                radius: vibe.ui ? vibe.ui.s(26) : 0
                color: "transparent"
                border.width: 1
                border.color: vibe.ui ? Qt.alpha(vibe.ui.subtext0, 0.18) : "transparent"
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: vibe.ui ? vibe.ui.s(20) : 0
                    spacing: vibe.ui ? vibe.ui.s(6) : 0
                    Item { Layout.fillHeight: true }
                    Text { text: "HOW YOUR TYPE IS PICKED"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui ? vibe.ui.s(10) : 10; font.letterSpacing: vibe.ui ? vibe.ui.s(1.2) : 1; color: vibe.hasData ? vibe.tint(vibe.p.archetype.key) : "white" }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Each ring is the real share of your plays that fit that habit. Your type is the one furthest above its neutral baseline (night: 29%, what round-the-clock listening would give)."
                        font.family: "JetBrains Mono"; font.pixelSize: vibe.ui ? vibe.ui.s(10) : 10; color: vibe.ui ? vibe.ui.subtext0 : "white"
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: vibe.hasData && (!!vibe.p.taste || !!vibe.p.era)
        spacing: vibe.ui ? vibe.ui.s(12) : 0

        Rectangle {
            id: tasteCard
            visible: vibe.hasData && !!vibe.p.taste
            readonly property var t: vibe.hasData ? vibe.p.taste : null
            readonly property color accent: vibe.hasData ? vibe.host.boost(vibe.pal[0]) : "#888888"
            readonly property color accent2: vibe.hasData ? vibe.host.boost(vibe.pal[1]) : "#888888"
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.preferredHeight: vibe.ui ? vibe.ui.s(318) : 0
            radius: vibe.ui ? vibe.ui.s(28) : 0
            border.width: 1; border.color: Qt.alpha(accent, 0.34)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.alpha(tasteCard.accent, 0.24) }
                GradientStop { position: 1.0; color: Qt.alpha(tasteCard.accent2, 0.08) }
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: vibe.ui ? vibe.ui.s(22) : 0
                spacing: vibe.ui ? vibe.ui.s(4) : 0
                Text { text: "YOUR SOUND"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui ? vibe.ui.s(10) : 10; font.letterSpacing: vibe.ui ? vibe.ui.s(1.5) : 1; color: tasteCard.accent }
                Text {
                    Layout.fillWidth: true
                    text: tasteCard.t ? vibe.titleCase(tasteCard.t.signature) : ""
                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui ? vibe.ui.s(30) : 30; font.letterSpacing: -(vibe.ui ? vibe.ui.s(1) : 1)
                    color: vibe.ui ? vibe.ui.text : "white"
                    elide: Text.ElideRight
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: vibe.ui ? vibe.ui.s(4) : 0
                    spacing: vibe.ui ? vibe.ui.s(10) : 0
                    Text { text: tasteCard.t ? Math.round(tasteCard.t.diversity * vibe.prog) : ""; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui ? vibe.ui.s(22) : 22; color: tasteCard.accent }
                    ColumnLayout {
                        spacing: 0
                        Text { text: tasteCard.t ? vibe.focusWord(tasteCard.t.diversity) : ""; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui ? vibe.ui.s(12) : 12; color: vibe.ui ? vibe.ui.text : "white" }
                        Text {
                            text: {
                                if (!tasteCard.t) return ""
                                let core = tasteCard.t.genres.filter(function (g) { return g.share >= 0.95 })
                                return "genre spread / 100" + (core.length ? "  ·  " + vibe.pct(core[0].share) + " " + core[0].name + " at the core" : "")
                            }
                            font.family: "JetBrains Mono"; font.pixelSize: vibe.ui ? vibe.ui.s(9) : 9; color: vibe.ui ? vibe.ui.subtext0 : "white"
                        }
                    }
                }
                Item { Layout.preferredHeight: vibe.ui ? vibe.ui.s(8) : 0 }
                Repeater {
                    model: tasteCard.t ? tasteCard.t.genres.filter(function (g) { return g.share < 0.95 }) : []
                    delegate: Item {
                        id: gRow
                        Layout.fillWidth: true
                        Layout.preferredHeight: vibe.ui.s(22)
                        readonly property color barTint: vibe.host.boost(vibe.host.paletteFor("", "", index + 1)[0])
                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: Qt.alpha(gRow.barTint, 0.14)
                        }
                        Rectangle {
                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                            radius: height / 2
                            width: Math.max(height, parent.width * modelData.share * vibe.prog)
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.alpha(gRow.barTint, 0.8) }
                                GradientStop { position: 1.0; color: Qt.alpha(gRow.barTint, 0.4) }
                            }
                        }
                        Text { anchors.left: parent.left; anchors.leftMargin: vibe.ui.s(10); anchors.verticalCenter: parent.verticalCenter; text: modelData.name; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: vibe.ui.s(10); color: vibe.ui.text }
                        Text { anchors.right: parent.right; anchors.rightMargin: vibe.ui.s(10); anchors.verticalCenter: parent.verticalCenter; text: vibe.pct(modelData.share); font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui.s(10); color: vibe.ui.text }
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }

        Rectangle {
            id: eraCard
            visible: vibe.hasData && !!vibe.p.era
            readonly property var e: vibe.hasData ? vibe.p.era : null
            readonly property color accent: vibe.ui ? vibe.host.boost(vibe.ui.yellow) : "#888888"
            readonly property color accent2: vibe.ui ? vibe.host.boost(vibe.ui.peach) : "#888888"
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.preferredHeight: vibe.ui ? vibe.ui.s(318) : 0
            radius: vibe.ui ? vibe.ui.s(28) : 0
            border.width: 1; border.color: Qt.alpha(accent, 0.34)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.alpha(eraCard.accent, 0.2) }
                GradientStop { position: 1.0; color: Qt.alpha(eraCard.accent2, 0.08) }
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: vibe.ui ? vibe.ui.s(22) : 0
                spacing: vibe.ui ? vibe.ui.s(2) : 0
                Text { text: "YOUR MUSIC WAS BORN IN"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui ? vibe.ui.s(10) : 10; font.letterSpacing: vibe.ui ? vibe.ui.s(1.5) : 1; color: eraCard.accent }
                RowLayout {
                    spacing: vibe.ui ? vibe.ui.s(12) : 0
                    Text {
                        text: eraCard.e ? Math.round(eraCard.e.medianYear - (1 - vibe.prog) * 40) : ""
                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui ? vibe.ui.s(52) : 52; font.letterSpacing: -(vibe.ui ? vibe.ui.s(2) : 2)
                        color: vibe.ui ? vibe.ui.text : "white"
                    }
                    Text {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: vibe.ui ? vibe.ui.s(12) : 0
                        text: eraCard.e ? "avg track is " + Math.round(eraCard.e.avgAge) + " years old" : ""
                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: vibe.ui ? vibe.ui.s(11) : 11; color: vibe.ui ? vibe.ui.subtext0 : "white"
                    }
                }
                RowLayout {
                    id: decadeRow
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: vibe.ui ? vibe.ui.s(6) : 0
                    spacing: vibe.ui ? vibe.ui.s(10) : 0
                    readonly property real maxShare: eraCard.e ? Math.max.apply(null, eraCard.e.decades.map(function (d) { return d.share })) : 1
                    Repeater {
                        model: eraCard.e ? eraCard.e.decades : []
                        delegate: Item {
                            id: dcol
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            readonly property bool peak: modelData.share === decadeRow.maxShare
                            readonly property color barTint: peak ? eraCard.accent : eraCard.accent2
                            Text {
                                id: dLabel
                                anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                                text: "'" + String(modelData.decade).slice(2) + "s"
                                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui.s(11)
                                color: dcol.peak ? vibe.ui.text : vibe.ui.subtext0
                            }
                            Rectangle {
                                id: dBar
                                anchors.bottom: dLabel.top; anchors.bottomMargin: vibe.ui.s(6)
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(parent.width, vibe.ui.s(56))
                                readonly property real room: parent.height - dLabel.height - vibe.ui.s(26)
                                height: Math.max(vibe.ui.s(6), room * (modelData.share / decadeRow.maxShare) * vibe.prog)
                                radius: vibe.ui.s(10)
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: dcol.barTint }
                                    GradientStop { position: 1.0; color: Qt.alpha(dcol.barTint, 0.35) }
                                }
                            }
                            Text {
                                anchors.bottom: dBar.top; anchors.bottomMargin: vibe.ui.s(4); anchors.horizontalCenter: parent.horizontalCenter
                                text: vibe.pct(modelData.share)
                                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui.s(10)
                                color: dcol.peak ? dcol.barTint : vibe.ui.subtext0
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: vibe.ui ? vibe.ui.s(8) : 0
                    text: eraCard.e ? "Oldest: " + eraCard.e.oldest.title + " — " + eraCard.e.oldest.artist + " (" + eraCard.e.oldest.year + ")" : ""
                    font.family: "JetBrains Mono"; font.pixelSize: vibe.ui ? vibe.ui.s(10) : 10; color: vibe.ui ? vibe.ui.subtext0 : "white"
                    elide: Text.ElideRight
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: vibe.hasData
        spacing: vibe.ui ? vibe.ui.s(12) : 0
        SectionTitle { text: "Receipts" }
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: vibe.ui ? vibe.ui.s(12) : 0
            rowSpacing: vibe.ui ? vibe.ui.s(12) : 0
            Repeater {
                model: {
                    if (!vibe.hasData) return []
                    let f = vibe.p.facts, out = []
                    out.push({ glyph: "󰋑", color: vibe.ui.red, big: f.superfan.vsEven + "×", art: vibe.host.artFor(f.superfan.artist, ""),
                        head: "Superfan of " + f.superfan.artist,
                        sub: vibe.pct(f.superfan.share) + " of your plays — " + f.superfan.vsEven + "× what an even split across your " + f.superfan.artists + " artists would give" })
                    out.push({ glyph: "󰑘", color: vibe.ui.pink, big: "×" + f.loop.count, art: vibe.host.artFor(f.loop.artist, f.loop.title),
                        head: "On loop: " + f.loop.title,
                        sub: f.loop.artist + " — " + f.loop.count + " plays in a single day" })
                    out.push({ glyph: "󰒭", color: vibe.ui.sapphire, big: f.backToBack.count, art: vibe.host.artFor(f.backToBack.artist, ""),
                        head: "Back-to-back " + f.backToBack.artist,
                        sub: f.backToBack.count + " of their tracks in a row, no one else allowed in" })
                    out.push({ glyph: "󰋋", color: vibe.ui.blue, big: vibe.fmtSpan(f.longestSession.secs), art: "",
                        head: "Longest session",
                        sub: f.longestSession.plays + " tracks without a 20-minute break, started " + Qt.formatDateTime(new Date(f.longestSession.startTs * 1000), "ddd HH:mm") })
                    if (f.explicitShare !== null && f.explicitShare !== undefined)
                        out.push({ glyph: "E", color: vibe.ui.peach, big: vibe.pct(f.explicitShare), art: "",
                            head: "Parental advisory",
                            sub: "of the tracks you played carry Spotify's explicit tag" })
                    if (f.drift)
                        out.push({ glyph: "󰔵", color: vibe.ui.green, big: f.drift.kept + "/" + f.drift.of, art: "",
                            head: f.drift.kept >= f.drift.of * 0.6 ? "Ride or die" : "Taste on the move",
                            sub: "of your all-time top " + f.drift.of + " artists are still in your last-4-weeks top" + (f.drift.newcomers.length ? " · new: " + f.drift.newcomers.slice(0, 2).join(", ") : "") })
                    return out
                }
                delegate: Rectangle {
                    id: fc
                    readonly property color accent: vibe.host.boost(modelData.color)
                    property real reveal: 0
                    SequentialAnimation {
                        id: fcIn
                        PropertyAction { target: fc; property: "reveal"; value: 0 }
                        PauseAnimation { duration: 80 * index }
                        NumberAnimation { target: fc; property: "reveal"; to: 1; duration: 520; easing.type: Easing.OutBack }
                    }
                    Connections { target: vibe; function onActiveChanged() { if (vibe.active) fcIn.restart() } }
                    Component.onCompleted: if (vibe.active) fcIn.restart()
                    opacity: Math.min(1, reveal)
                    transform: Translate { y: (1 - fc.reveal) * vibe.ui.s(18) }
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: vibe.ui.s(150)
                    radius: vibe.ui.s(26)
                    color: Qt.alpha(accent, fcMa.containsMouse ? 0.2 : 0.12)
                    border.width: 1; border.color: Qt.alpha(accent, fcMa.containsMouse ? 0.6 : 0.3)
                    scale: fcMa.containsMouse ? 1.03 : 1
                    Behavior on color { ColorAnimation { duration: 160 } }
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                    clip: true

                    Text {
                        anchors.right: parent.right; anchors.rightMargin: -vibe.ui.s(8)
                        anchors.top: parent.top; anchors.topMargin: -vibe.ui.s(22)
                        visible: modelData.art === ""
                        text: modelData.glyph
                        font.family: modelData.glyph === "E" ? "JetBrains Mono" : "Iosevka Nerd Font"
                        font.weight: Font.Black
                        font.pixelSize: vibe.ui.s(110)
                        color: Qt.alpha(fc.accent, 0.16)
                    }
                    WrappedArt {
                        visible: modelData.art !== ""
                        anchors.right: parent.right; anchors.top: parent.top
                        anchors.rightMargin: vibe.ui.s(16); anchors.topMargin: vibe.ui.s(16)
                        width: vibe.ui.s(52); height: width
                        radius: width / 2
                        art: modelData.art
                        fallback: fc.accent
                        edge: Qt.alpha(fc.accent, 0.5)
                        rotation: fcMa.containsMouse ? -8 : 0
                        Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                    }
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: vibe.ui.s(18)
                        spacing: vibe.ui.s(2)
                        Text {
                            text: modelData.big
                            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui.s(34); font.letterSpacing: -vibe.ui.s(1)
                            color: fc.accent
                        }
                        Text { Layout.fillWidth: true; Layout.rightMargin: vibe.ui.s(56); text: modelData.head; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: vibe.ui.s(12); color: vibe.ui.text; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: modelData.sub; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: vibe.ui.s(10); color: vibe.ui.subtext0 }
                        Item { Layout.fillHeight: true }
                    }
                    MouseArea { id: fcMa; anchors.fill: parent; hoverEnabled: true }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: vibe.hasData
        wrapMode: Text.Wrap
        text: vibe.hasData
            ? "Read from " + vibe.p.sample.plays + " plays over " + vibe.p.sample.days + " days (Spotify, all devices + this machine). Genres via MusicBrainz"
              + (vibe.p.taste ? " (" + vibe.p.taste.taggedArtists + "/" + vibe.p.taste.totalArtists + " artists tagged)" : "")
              + ". Every number here is your own history — no invented global percentiles. Sharpens as more history accumulates."
            : ""
        font.family: "JetBrains Mono"; font.pixelSize: vibe.ui ? vibe.ui.s(10) : 10; color: vibe.ui ? vibe.ui.subtext1 : "white"
    }
}
