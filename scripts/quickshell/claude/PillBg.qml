import QtQuick

Item {
    id: root
    property string kind: ""
    property real radius: 10
    property real px: 1
    property bool shown: false
    property real level: 0
    property real rate: 0
    property real rate2: 0
    property int count: 0
    property color tint: "#89dceb"
    property var hist: []
    property string phase: "day"
    property string weather: "sunny"
    property real pulseT: 1
    property real t: 0
    property real phA: 0
    property real phB: 0
    property real skyOffset: 0
    property bool flatTop: false
    property real skyTotal: 0
    Behavior on rate { NumberAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on rate2 { NumberAnimation { duration: 900; easing.type: Easing.OutQuad } }
    readonly property bool animated: kind === "sky" || kind === "radar" || kind === "particles" || kind === "aurora" || kind === "border"

    anchors.fill: parent
    opacity: shown ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

    function fire() { pulseAnim.restart() }
    NumberAnimation { id: pulseAnim; target: root; property: "pulseT"; from: 0; to: 1; duration: 1100; easing.type: Easing.OutCubic }

    Timer {
        interval: 66; repeat: true
        running: root.visible && root.animated
        onTriggered: {
            root.t += 0.066
            if (root.kind === "radar") root.phA += 0.066 * (0.22 + root.rate * 0.9)
            if (root.kind === "particles") {
                root.phA += 0.066 * (0.2 + root.rate * 1.2)
                root.phB += 0.066 * (0.2 + root.rate2 * 1.2)
            }
            cv.requestPaint()
        }
    }
    onLevelChanged: cv.requestPaint()
    onHistChanged: cv.requestPaint()
    onCountChanged: cv.requestPaint()
    onTintChanged: cv.requestPaint()
    onPhaseChanged: cv.requestPaint()
    onWeatherChanged: cv.requestPaint()
    onPulseTChanged: cv.requestPaint()
    onVisibleChanged: if (visible) cv.requestPaint()
    onWidthChanged: cv.requestPaint()
    onHeightChanged: cv.requestPaint()

    Canvas {
        id: cv
        anchors.fill: parent

        function rnd(n) { let x = Math.sin(n * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x) }

        function clipRounded(ctx, w, h, r) {
            r = Math.min(r, h / 2, w / 2)
            ctx.beginPath()
            if (root.flatTop) {
                ctx.moveTo(0, 0); ctx.lineTo(w, 0)
            } else {
                ctx.moveTo(r, 0); ctx.lineTo(w - r, 0); ctx.arcTo(w, 0, w, r, r)
            }
            ctx.lineTo(w, h - r); ctx.arcTo(w, h, w - r, h, r)
            ctx.lineTo(r, h); ctx.arcTo(0, h, 0, h - r, r)
            if (root.flatTop) ctx.lineTo(0, 0)
            else { ctx.lineTo(0, r); ctx.arcTo(0, 0, r, 0, r) }
            ctx.closePath()
            ctx.clip()
        }

        function paintSky(ctx, w, h) {
            let p = root.phase, wx = root.weather
            let H = root.skyTotal > 0 ? root.skyTotal : h
            let off = root.skyOffset
            let tt = (Date.now() % 1000000) / 1000
            let top, bot, a
            if (p === "dawn") { top = [245, 194, 231]; bot = [250, 179, 135]; a = 0.30 }
            else if (p === "day") { top = [116, 199, 236]; bot = [249, 226, 175]; a = 0.28 }
            else if (p === "dusk") { top = [203, 166, 247]; bot = [243, 139, 168]; a = 0.30 }
            else { top = [30, 30, 63]; bot = [69, 71, 90]; a = 0.55 }
            if (wx === "rainy" || wx === "storm" || wx === "cloudy" || wx === "snow") { top = [top[0] * 0.6 + 60, top[1] * 0.6 + 60, top[2] * 0.6 + 70]; bot = top }
            let g = ctx.createLinearGradient(0, -off, 0, H - off)
            g.addColorStop(0, "rgba(" + Math.round(top[0]) + "," + Math.round(top[1]) + "," + Math.round(top[2]) + "," + a + ")")
            g.addColorStop(1, "rgba(" + Math.round(bot[0]) + "," + Math.round(bot[1]) + "," + Math.round(bot[2]) + "," + a + ")")
            ctx.fillStyle = g
            ctx.fillRect(0, 0, w, h)
            let night = p === "night" || p === "dusk"
            if (night) {
                for (let i = 0; i < 9; i++) {
                    let sx = rnd(i + 1) * w, sy = rnd(i + 20) * H * 0.8 - off
                    let al = 0.25 + 0.45 * (0.5 + 0.5 * Math.sin(tt * 1.4 + i * 1.9))
                    ctx.fillStyle = "rgba(205,214,244," + al + ")"
                    ctx.fillRect(sx, sy, root.px * 1.4, root.px * 1.4)
                }
            }
            if ((wx === "sunny" || wx === "clear") && off === 0) {
                let sx = w * 0.88, sy = h * 0.32
                let rg = ctx.createRadialGradient(sx, sy, 0, sx, sy, root.px * 9)
                let col = night ? "205,214,244" : "249,226,175"
                rg.addColorStop(0, "rgba(" + col + ",0.45)")
                rg.addColorStop(1, "rgba(" + col + ",0)")
                ctx.fillStyle = rg
                ctx.beginPath(); ctx.arc(sx, sy, root.px * 9, 0, Math.PI * 2); ctx.fill()
            }
            let nc = (wx === "sunny" || wx === "clear") ? 1 : 3
            for (let i = 0; i < nc; i++) {
                let cw = (18 + rnd(i + 40) * 14) * root.px
                let cx = ((rnd(i + 50) * (w + cw) + tt * (5 + i * 2.5) * root.px) % (w + cw * 2)) - cw
                let cy = H * (0.2 + 0.5 * rnd(i + 60)) - off
                ctx.fillStyle = "rgba(255,255,255,0.13)"
                ctx.beginPath(); ctx.ellipse(cx, cy, cw, cw * 0.38); ctx.fill()
            }
            if (wx === "rainy" || wx === "storm") {
                ctx.strokeStyle = "rgba(137,180,250,0.5)"
                ctx.lineWidth = root.px
                let n = wx === "storm" ? 16 : 11
                for (let i = 0; i < n; i++) {
                    let x = rnd(i + 80) * w
                    let y = ((rnd(i + 90) * H + tt * (55 + rnd(i) * 40) * root.px) % (H + 8 * root.px)) - 4 * root.px - off
                    ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x - root.px * 1.5, y + root.px * 5); ctx.stroke()
                }
            } else if (wx === "snow") {
                ctx.fillStyle = "rgba(255,255,255,0.6)"
                for (let i = 0; i < 12; i++) {
                    let x = rnd(i + 100) * w + Math.sin(tt + i) * root.px * 2
                    let y = (rnd(i + 110) * H + tt * 12 * root.px) % H - off
                    ctx.fillRect(x, y, root.px * 1.4, root.px * 1.4)
                }
            }
        }

        function paintRadar(ctx, w, h) {
            let maxR = Math.sqrt(w * w + h * h) / 2
            let br = 0.35 + 0.65 * root.level
            let c = root.tint
            for (let i = 0; i < 3; i++) {
                let vis = Math.max(0, Math.min(1, root.level * 3 - i + 0.5))
                if (vis <= 0) continue
                let ph = (root.phA + i / 3) % 1
                let al = (1 - ph) * Math.min(1, ph * 6) * 0.55 * br * vis
                ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, al)
                ctx.lineWidth = root.px * 1.3
                ctx.beginPath(); ctx.arc(w / 2, h / 2, ph * maxR, 0, Math.PI * 2); ctx.stroke()
            }
            ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.08 * br)
            ctx.fillRect(0, 0, w, h)
        }

        function paintPulse(ctx, w, h) {
            let c = root.tint
            ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.10)
            ctx.fillRect(0, 0, w, h)
            if (root.pulseT < 1) {
                let maxR = Math.sqrt(w * w + h * h) / 2
                ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, (1 - root.pulseT) * 0.75)
                ctx.lineWidth = root.px * 2
                ctx.beginPath(); ctx.arc(w / 2, h / 2, root.pulseT * maxR, 0, Math.PI * 2); ctx.stroke()
                ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, (1 - root.pulseT) * 0.18)
                ctx.fillRect(0, 0, w, h)
            }
        }

        function roundedRectPath(ctx, x, y, w, h, r) {
            r = Math.max(0, Math.min(r, h / 2, w / 2))
            ctx.beginPath()
            ctx.moveTo(x + r, y); ctx.lineTo(x + w - r, y); ctx.arcTo(x + w, y, x + w, y + r, r)
            ctx.lineTo(x + w, y + h - r); ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
            ctx.lineTo(x + r, y + h); ctx.arcTo(x, y + h, x, y + h - r, r)
            ctx.lineTo(x, y + r); ctx.arcTo(x, y, x + r, y, r)
            ctx.closePath()
        }

        // Alternative to paintPulse — a breathing border ring instead of a
        // fill wash, for findings that read better as "look here" than as
        // an ambient tint (connect/disconnect events, alerts). Ambient
        // breathe via root.t, plus an extra burst ring on fire() same as
        // paintPulse's expanding-circle burst.
        function paintBorder(ctx, w, h) {
            let c = root.tint
            let breathe = 0.5 + 0.5 * Math.sin(root.t * 2.4)
            let burst = root.pulseT < 1 ? (1 - root.pulseT) : 0
            let lw = root.px * (1.3 + 0.9 * breathe + burst * 1.8)
            let al = Math.min(1, 0.4 + 0.4 * breathe + burst * 0.5)
            ctx.lineWidth = lw
            ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, al)
            roundedRectPath(ctx, lw / 2, lw / 2, w - lw, h - lw, root.radius - lw / 2)
            ctx.stroke()
            if (burst > 0) {
                ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, burst * 0.35)
                ctx.lineWidth = root.px * 0.9
                roundedRectPath(ctx, root.px * 2.4, root.px * 2.4, w - root.px * 4.8, h - root.px * 4.8, Math.max(0, root.radius - root.px * 2.4))
                ctx.stroke()
            }
        }

        function paintArea(ctx, w, h) {
            let hist = root.hist
            if (!hist || hist.length < 2) return
            let lv = root.level
            let c = lv >= 0.85 ? [243, 139, 168] : (lv >= 0.6 ? [249, 226, 175] : [148, 226, 213])
            let step = w / Math.max(1, hist.length - 1)
            ctx.beginPath()
            ctx.moveTo(0, h)
            for (let i = 0; i < hist.length; i++) ctx.lineTo(i * step, h - (Math.min(100, hist[i]) / 100) * h * 0.9)
            ctx.lineTo(w, h)
            ctx.closePath()
            let g = ctx.createLinearGradient(0, 0, 0, h)
            g.addColorStop(0, "rgba(" + c[0] + "," + c[1] + "," + c[2] + ",0.34)")
            g.addColorStop(1, "rgba(" + c[0] + "," + c[1] + "," + c[2] + ",0.04)")
            ctx.fillStyle = g
            ctx.fill()
        }

        // Same history-area idea as paintArea, rotated 90° — used for pills
        // that stand taller than they're wide (e.g. the quickshell-CPU pill),
        // where a left-to-right timeline reads wrong. Oldest sample at the
        // top, newest at the bottom, filling outward from the left edge.
        function paintAreaV(ctx, w, h) {
            let hist = root.hist
            if (!hist || hist.length < 2) return
            let lv = root.level
            let c = lv >= 0.85 ? [243, 139, 168] : (lv >= 0.6 ? [249, 226, 175] : [148, 226, 213])
            let step = h / Math.max(1, hist.length - 1)
            ctx.beginPath()
            ctx.moveTo(0, 0)
            for (let i = 0; i < hist.length; i++) ctx.lineTo((Math.min(100, hist[i]) / 100) * w * 0.9, i * step)
            ctx.lineTo(0, h)
            ctx.closePath()
            let g = ctx.createLinearGradient(0, 0, w, 0)
            g.addColorStop(0, "rgba(" + c[0] + "," + c[1] + "," + c[2] + ",0.34)")
            g.addColorStop(1, "rgba(" + c[0] + "," + c[1] + "," + c[2] + ",0.04)")
            ctx.fillStyle = g
            ctx.fill()
        }

        function paintParticles(ctx, w, h) {
            let N = 8
            let aDn = 0.25 + 0.6 * root.rate, aUp = 0.25 + 0.6 * root.rate2
            for (let i = 0; i < N; i++) {
                let x = (0.06 + 0.88 * rnd(i + 1)) * w * 0.5
                let f = (rnd(i + 30) + root.phA * (0.6 + rnd(i + 9) * 0.8)) % 1
                ctx.fillStyle = "rgba(116,199,236," + (aDn * Math.sin(Math.PI * f)) + ")"
                ctx.fillRect(x, f * h, root.px * 1.5, root.px * 1.5)
            }
            for (let i = 0; i < N; i++) {
                let x = w * 0.5 + (0.06 + 0.88 * rnd(i + 60)) * w * 0.5
                let f = (rnd(i + 90) + root.phB * (0.6 + rnd(i + 19) * 0.8)) % 1
                ctx.fillStyle = "rgba(250,179,135," + (aUp * Math.sin(Math.PI * f)) + ")"
                ctx.fillRect(x, (1 - f) * h, root.px * 1.5, root.px * 1.5)
            }
        }

        function paintStars(ctx, w, h) {
            let n = Math.min(40, Math.max(0, root.count))
            let px0 = -1, py0 = -1
            for (let i = 0; i < n; i++) {
                let x = 3 * root.px + rnd(i + 3) * (w - 6 * root.px)
                let y = 3 * root.px + rnd(i + 70) * (h - 6 * root.px)
                if (i > 0) {
                    ctx.strokeStyle = "rgba(205,214,244,0.10)"
                    ctx.lineWidth = root.px * 0.8
                    ctx.beginPath(); ctx.moveTo(px0, py0); ctx.lineTo(x, y); ctx.stroke()
                }
                ctx.fillStyle = "rgba(205,214,244," + (0.30 + 0.25 * rnd(i + 11)) + ")"
                let sz = root.px * (1 + rnd(i + 21))
                ctx.fillRect(x - sz / 2, y - sz / 2, sz, sz)
                px0 = x; py0 = y
            }
        }

        function paintTint(ctx, w, h) {
            let c = root.tint
            let g = ctx.createLinearGradient(0, 0, w, h)
            g.addColorStop(0, Qt.rgba(c.r, c.g, c.b, 0.55))
            g.addColorStop(1, Qt.rgba(c.r, c.g, c.b, 0.15))
            ctx.fillStyle = g
            ctx.fillRect(0, 0, w, h)
        }

        function paintAurora(ctx, w, h) {
            let cols = [[148, 226, 213], [203, 166, 247], [245, 194, 231]]
            let boost = 1 + (root.pulseT < 1 ? (1 - root.pulseT) * 0.9 : 0)
            for (let b = 0; b < 3; b++) {
                let c = cols[b]
                let cx = w * (0.5 + 0.42 * Math.sin(root.t * 0.55 + b * 2.1))
                let cy = h * (0.5 + 0.22 * Math.sin(root.t * 0.9 + b * 1.3))
                let r = h * 1.15
                ctx.save()
                ctx.translate(cx, cy)
                ctx.scale(Math.max(1, w / h * 0.75), 1)
                let g = ctx.createRadialGradient(0, 0, 0, 0, 0, r)
                g.addColorStop(0, "rgba(" + c[0] + "," + c[1] + "," + c[2] + "," + (0.30 * boost) + ")")
                g.addColorStop(1, "rgba(" + c[0] + "," + c[1] + "," + c[2] + ",0)")
                ctx.fillStyle = g
                ctx.beginPath(); ctx.arc(0, 0, r, 0, Math.PI * 2); ctx.fill()
                ctx.restore()
            }
        }

        onPaint: {
            let ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (width < 2 || height < 2 || !root.visible) return
            ctx.save()
            clipRounded(ctx, width, height, root.radius)
            if (root.kind === "sky") paintSky(ctx, width, height)
            else if (root.kind === "radar") paintRadar(ctx, width, height)
            else if (root.kind === "pulse") paintPulse(ctx, width, height)
            else if (root.kind === "border") paintBorder(ctx, width, height)
            else if (root.kind === "area") paintArea(ctx, width, height)
            else if (root.kind === "areaV") paintAreaV(ctx, width, height)
            else if (root.kind === "particles") paintParticles(ctx, width, height)
            else if (root.kind === "stars") paintStars(ctx, width, height)
            else if (root.kind === "tint") paintTint(ctx, width, height)
            else if (root.kind === "aurora") paintAurora(ctx, width, height)
            ctx.restore()
        }
    }
}
