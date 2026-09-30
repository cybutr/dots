import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root

    // --- Responsive Scaling Logic ---
    Scaler {
        id: scaler
        // Uses the physical screen width so the popup scales synchronously
        currentWidth: Screen.width
    }
    
    // Helper function scoped to the root Item for easy access
    function s(val) { 
        return scaler.s(val); 
    }

    // Theme Colors
    MatugenColors { id: _theme }

    // Theme Colors
    readonly property color base: _theme.base
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color overlay0: _theme.overlay0
    readonly property color overlay1: _theme.overlay1
    readonly property color overlay2: _theme.overlay2
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color subtext1: _theme.subtext1
    readonly property color blue: _theme.blue
    readonly property color sapphire: _theme.sapphire
    readonly property color lavender: _theme.blue // Mapped to blue as Matugen template lacks lavender
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color red: _theme.red
    readonly property color yellow: _theme.yellow

    // Data State Properties
    property var musicData: {
        "title": "Loading...", "artist": "", "status": "Stopped", "percent": 0,
        "lengthStr": "00:00", "positionStr": "00:00", "timeStr": "--:-- / --:--",
        "source": "Offline", "playerName": "", "blur": "", "grad": "",
        "textColor": "#cdd6f4", "deviceIcon": "󰓃", "deviceName": "Speaker",
        "artUrl": "", "bpm": 0
    }

    // --- TEMPO-DRIVEN MOTION ---
    // bpm comes from music_info.sh (locally analyzed, cached per track).
    // Falls back to 120 (the same value every fixed-duration animation
    // below was originally tuned against) when no song / no analysis yet.
    readonly property real bpm: (musicData && musicData.bpm && musicData.bpm > 0) ? musicData.bpm : 120
    readonly property real beatMs: 60000 / root.bpm

    // --- VISUAL FX — entirely automatic, driven by the song itself, no manual controls ---
    // Tempo picks the mood/color band; nothing here is user-set.
    readonly property string accentColorKey:
        root.bpm < 80  ? "sapphire" :
        root.bpm < 105 ? "blue" :
        root.bpm < 135 ? "mauve" :
        root.bpm < 165 ? "pink" : "red"
    readonly property color accentColor: _theme[root.accentColorKey] || root.mauve
    readonly property real beatsPerRotation: 16 // cover art / flow gradient: one full cycle per N beats
    readonly property real beatsPerOrbit: 180   // background orbit circles: one revolution per N beats
    // 0..1 "energy" derived from tempo — scales how bold/lively the visuals get.
    readonly property real energy: Math.max(0, Math.min(1, (root.bpm - 60) / 140))

    // Fires once per beat while playing — drives the cover glow's beat-flash.
    property bool beatPulse: false
    Timer {
        id: beatClock
        interval: root.beatMs
        running: root.musicData.status === "Playing"
        repeat: true
        onTriggered: { root.beatPulse = !root.beatPulse }
    }

    function sanitizePresetName(name) {
        return String(name).replace(/[^a-zA-Z0-9 _-]/g, '').trim().slice(0, 40);
    }

    Component.onCompleted: {
        refreshEqUserPresets();
    }

    property var eqData: {
        "b1": 0, "b2": 0, "b3": 0, "b4": 0, "b5": 0,
        "b6": 0, "b7": 0, "b8": 0, "b9": 0, "b10": 0,
        "preset": "Flat", "pending": false
    }

    property var eqLive: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    function setEqLive(idx, v) {
        if (Math.abs((root.eqLive[idx - 1] || 0) - v) < 0.01) return
        let a = root.eqLive.slice()
        a[idx - 1] = v
        root.eqLive = a
    }

    // --- USER-SAVED EQ PRESETS (custom 10-band snapshots, distinct from the built-in ones) ---
    property var eqUserPresets: []

    function refreshEqUserPresets() {
        eqUserPresetsListProc.running = false;
        eqUserPresetsListProc.running = true;
    }

    function saveEqUserPreset(name) {
        var safeName = root.sanitizePresetName(name);
        if (safeName.length === 0) return;
        root.execCmd(`$HOME/.config/hypr/scripts/quickshell/music/equalizer.sh save_user "${safeName}"`);
        eqUserPresetsSaveDelay.restart();
    }

    function deleteEqUserPreset(name) {
        var safeName = root.sanitizePresetName(name);
        if (safeName.length === 0) return;
        root.execCmd(`$HOME/.config/hypr/scripts/quickshell/music/equalizer.sh delete_user "${safeName}"`);
        eqUserPresetsSaveDelay.restart();
    }

    function applyEqUserPreset(preset) {
        if (!preset) return;
        var temp = Object.assign({}, root.eqData);
        for (var i = 1; i <= 10; i++) {
            temp["b" + i] = Number(preset["b" + i]) || 0;
        }
        temp.preset = preset.name;
        temp.pending = false;
        root.eqData = temp;

        root.lastEqUpdate = Date.now();
        root.triggerEqLightning();
        root.execCmd(`$HOME/.config/hypr/scripts/quickshell/music/equalizer.sh apply_user "${preset.name}"`);
    }

    Timer {
        id: eqUserPresetsSaveDelay
        interval: 250
        onTriggered: root.refreshEqUserPresets()
    }

    Process {
        id: eqUserPresetsListProc
        command: ["bash", "-c", "$HOME/.config/hypr/scripts/quickshell/music/equalizer.sh list_user"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text) {
                    try {
                        var parsed = JSON.parse(this.text.trim());
                        root.eqUserPresets = parsed.presets || [];
                    } catch(e) {}
                }
            }
        }
    }

    // Accumulators for Process standard output
    property string accumulatedMusicOut: ""
    property string accumulatedEqOut: ""

    // UI State for debouncing the slider and play button
    property bool userIsSeeking: false
    property bool userToggledPlay: false
    
    // ANTI-JITTER LOCK: Prevents background polling from reverting UI during processing
    property real lastEqUpdate: 0

    // Decoupled Global Animation States
    property real catppuccinFlowOffset: 0
    NumberAnimation on catppuccinFlowOffset {
        from: 0; to: 1.0
        // Tempo-synced: one full flow cycle per beatsPerRotation beats (was a fixed 8000ms)
        duration: root.beatMs * root.beatsPerRotation
        loops: Animation.Infinite
        running: true
    }

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2
        // Tempo-synced: slow drifting orbit, one revolution per beatsPerOrbit beats
        duration: root.beatMs * root.beatsPerOrbit
        loops: Animation.Infinite
        running: true
    }

    // --- CANVAS LIGHTNING ANIMATION STATE ---
    property real eqLightningProgress: 0.0
    property real eqLightningFade: 1.0 // 1.0 = fully faded out

    SequentialAnimation {
        id: eqLightningAnim
        running: false
        ScriptAction { script: { root.eqLightningFade = 0.0; root.eqLightningProgress = 0.0; } }
        NumberAnimation { 
            target: root; property: "eqLightningProgress"; 
            from: 0.0; to: 10.0; // 10 points = 9 segments
            duration: 650; // Fast, snappy, energetic strike
            easing.type: Easing.OutSine 
        }
        PauseAnimation { duration: 150 } // Hold the core flash at the end
        NumberAnimation { 
            target: root; property: "eqLightningFade"; 
            from: 0.0; to: 1.0; 
            duration: 800; // Smooth dissipation
            easing.type: Easing.OutQuad 
        }
        ScriptAction { script: { root.eqLightningProgress = 0.0; } }
    }

    function triggerEqLightning() {
        eqLightningAnim.restart();
    }

    // --- GLOBAL PLAY/PAUSE EVENT LISTENER ---
    property string lastMusicStatus: "Stopped"
    onMusicDataChanged: {
        if (musicData && musicData.status && musicData.status !== lastMusicStatus) {
            if (musicData.status === "Playing") {
                playPulse.trigger();
            }
            lastMusicStatus = musicData.status;
        }
    }

    // --- ENHANCED STARTUP ANIMATION STATES ---
    property real introMain: 0
    property real introCover: 0
    property real introText: 0
    property real introControls: 0
    property real introSeparator: 0
    property real introEqHeader: 0
    property real introEqSliders: 0
    property real introPresets: 0

    ParallelAnimation {
        running: true

        // 1. Base window fades, scales, and lifts smoothly (sped up by ~40ms)
        NumberAnimation { target: root; property: "introMain"; from: 0; to: 1.0; duration: 760; easing.type: Easing.OutQuart }

        // 2. Cover art snaps in with a premium elastic feel
        SequentialAnimation {
            PauseAnimation { duration: 70 }
            NumberAnimation { target: root; property: "introCover"; from: 0; to: 1.0; duration: 810; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
        }

        // 3. Text block glides in smoothly
        SequentialAnimation {
            PauseAnimation { duration: 150 }
            NumberAnimation { target: root; property: "introText"; from: 0; to: 1.0; duration: 760; easing.type: Easing.OutQuart }
        }

        // 4. Progress bar and Media Controls bounce in
        SequentialAnimation {
            PauseAnimation { duration: 230 }
            NumberAnimation { target: root; property: "introControls"; from: 0; to: 1.0; duration: 760; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }

        // 5. Separator line drops and fades
        SequentialAnimation {
            PauseAnimation { duration: 310 }
            NumberAnimation { target: root; property: "introSeparator"; from: 0; to: 1.0; duration: 660; easing.type: Easing.OutQuart }
        }

        // 6. EQ header follows down seamlessly
        SequentialAnimation {
            PauseAnimation { duration: 370 }
            NumberAnimation { target: root; property: "introEqHeader"; from: 0; to: 1.0; duration: 710; easing.type: Easing.OutQuart }
        }

        // 7. EQ Sliders sweep up in a sequential waterfall wave
        SequentialAnimation {
            PauseAnimation { duration: 430 }
            NumberAnimation { target: root; property: "introEqSliders"; from: 0; to: 1.0; duration: 860; easing.type: Easing.OutExpo }
        }

        // 8. Presets finish the orchestration with a final pop
        SequentialAnimation {
            PauseAnimation { duration: 550 }
            NumberAnimation { target: root; property: "introPresets"; from: 0; to: 1.0; duration: 810; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }
    }

    // --- FIXED COLOR PARSING LOGIC ---
    property var borderColors: {
        var defaultColors = [root.mauve, root.blue, root.red, root.mauve];
        if (!root.musicData || !root.musicData.grad) return defaultColors;
        
        var hexRegex = /#[0-9a-fA-F]{6}/g;
        var matches = root.musicData.grad.match(hexRegex);
        
        if (matches && matches.length >= 3) {
            return [matches[0], matches[1], matches[2], matches[0]]; // Wrap around for looping
        }
        return defaultColors;
    }

    // PROPER EXCEPTION-FREE FIX: Explicit bindings so GradientStop actually repaints
    property color bc1: borderColors[0] || root.mauve
    property color bc2: borderColors[1] || root.blue
    property color bc3: borderColors[2] || root.red
    property color bc4: borderColors[3] || root.mauve

    property color dynamicTextColor: {
        if (root.musicData && root.musicData.textColor) {
            var c = String(root.musicData.textColor).trim();
            // Securely extract exactly #RRGGBB, ignoring any alpha leak from the shell
            var match = c.match(/^(#[0-9a-fA-F]{6})/);
            if (match) return match[1];
        }
        return root.text;
    }

    // --- PER-SONG COLOR BLENDING ---
    // bc1/bc2 already come from the actual album art (music_info.sh quantizes it).
    // Blend them into matugen accents so glows shift with the song, not just the wallpaper.
    function mixColor(a, b, t) {
        return Qt.rgba(
            a.r + (b.r - a.r) * t,
            a.g + (b.g - a.g) * t,
            a.b + (b.b - a.b) * t,
            1.0
        );
    }

    readonly property color songGlow: mixColor(root.accentColor, root.bc1, 0.6)
    function boostColor(c) {
        return Qt.hsla(c.hslHue < 0 ? 0.7 : c.hslHue, Math.max(c.hslSaturation, 0.55), Math.min(Math.max(c.hslLightness, 0.55), 0.75), 1.0)
    }
    readonly property color vizC1: boostColor(root.bc1)
    readonly property color vizC2: boostColor(root.bc2)
    readonly property color songOrbit1: mixColor(root.accentColor, root.bc1, 0.65)
    readonly property color songOrbit2: mixColor(root.blue, root.bc2, 0.65)

    // --- LIGHTWEIGHT AUDIO-REACTIVE PULSE ---
    // Short parec RMS sample per poll (same spawn pattern as musicProc/eqProc below),
    // only runs while actually playing. Drives a subtle breathing glow, not a strobe.
    property real audioLevel: 0
    Behavior on audioLevel { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

    Timer {
        interval: 700
        running: root.musicData.status === "Playing"
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!audioLevelProc.running) audioLevelProc.running = true;
        }
    }

    Process {
        id: audioLevelProc
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "$HOME/.config/hypr/scripts/quickshell/music/audio_level.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseFloat(this.text.trim());
                if (!isNaN(v)) root.audioLevel = Math.max(0, Math.min(1, v));
            }
        }
    }

    // --- UTILITIES & OPTIMISTIC UPDATES ---
    function execCmd(cmdStr) {
        var safeCmd = cmdStr.replace(/`/g, "\\`");
        var p = Qt.createQmlObject(`
            import Quickshell.Io
            Process {
                command: ["bash", "-c", \`${safeCmd}\`]
                running: true
                onExited: (exitCode) => destroy()
            }
        `, root);
    }

    function applyPresetOptimistically(presetName) {
        var presets = {
            "Flat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            "Bass": [5, 7, 5, 2, 1, 0, 0, 0, 1, 2],
            "Treble": [-2, -1, 0, 1, 2, 3, 4, 5, 6, 6],
            "Vocal": [-2, -1, 1, 3, 5, 5, 4, 2, 1, 0],
            "Pop": [2, 4, 2, 0, 1, 2, 4, 2, 1, 2],
            "Rock": [5, 4, 2, -1, -2, -1, 2, 4, 5, 6],
            "Jazz": [3, 3, 1, 1, 1, 1, 2, 1, 2, 3],
            "Classic": [0, 1, 2, 2, 2, 2, 1, 2, 3, 4]
        };
        if (presets[presetName]) {
            var temp = Object.assign({}, root.eqData);
            for (var i = 0; i < 10; i++) {
                temp["b" + (i + 1)] = presets[presetName][i];
            }
            temp.preset = presetName;
            temp.pending = false; 
            root.eqData = temp; 
            
            // Blind the polling process to stop it from fetching old data
            root.lastEqUpdate = Date.now(); 
            
            root.triggerEqLightning();
            execCmd(`$HOME/.config/hypr/scripts/quickshell/music/equalizer.sh preset ${presetName}`);
        }
    }

    // --- DATA POLLING ---
    Timer {
        id: seekDebounceTimer
        interval: 2500 
        onTriggered: root.userIsSeeking = false
    }

    Timer {
        id: playDebounceTimer
        interval: 1500
        onTriggered: root.userToggledPlay = false
    }

    // Watchdog: if a poll Process ever gets stuck (never exits — e.g. a
    // hung shell/playerctl call), the `if (!x.running)` guard above would
    // permanently skip every future tick and the popup would freeze on
    // stale status forever with no way to recover short of a restart. Force
    // it back off after one missed cycle so polling always resumes.
    property int musicProcStuckTicks: 0
    property int eqProcStuckTicks: 0
    Timer {
        interval: 500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (musicProc.running) {
                root.musicProcStuckTicks++;
                if (root.musicProcStuckTicks >= 3) { musicProc.running = false; root.musicProcStuckTicks = 0; }
            } else {
                root.musicProcStuckTicks = 0;
                musicProc.running = true;
            }
            if (eqProc.running) {
                root.eqProcStuckTicks++;
                if (root.eqProcStuckTicks >= 3) { eqProc.running = false; root.eqProcStuckTicks = 0; }
            } else {
                root.eqProcStuckTicks = 0;
                eqProc.running = true;
            }
        }
    }

    Process {
        id: musicProc
        running: true
        command: ["bash", "-c", "$HOME/.config/hypr/scripts/quickshell/music/music_info.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text) {
                    var outStr = this.text.trim();
                    if (outStr.length > 0) {
                        try { 
                            var newData = JSON.parse(outStr); 
                            if (root.userToggledPlay) {
                                newData.status = root.musicData.status; 
                            }
                            root.musicData = newData; 
                        } catch(e) {}
                    }
                }
            }
        }
    }

    Process {
        id: eqProc
        running: true
        command: ["bash", "-c", "$HOME/.config/hypr/scripts/quickshell/music/equalizer.sh get"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text) {
                    // Ignore background data entirely if we recently pushed an optimistic update
                    if (Date.now() - root.lastEqUpdate < 2000) return;

                    var outStr = this.text.trim();
                    if (outStr.length > 0) {
                        try { root.eqData = JSON.parse(outStr); } catch(e) {}
                    }
                }
            }
        }
    }

    // --- UI LAYOUT ---
    Item {
        id: mainWrapper
        anchors.fill: parent
        
        // Deepened scale effect and introduced a gentle Y-axis translation for the main container
        scale: 0.92 + (0.08 * root.introMain)
        opacity: root.introMain
        transform: Translate { y: root.s(15) * (1 - root.introMain) }

        // OUTER ANIMATED BORDER WITH PROPER CLIPPING
        Item {
            anchors.fill: parent

            Shape {
                id: maskRectOuter
                anchors.fill: parent
                visible: false // Hidden because MultiEffect will render it as a mask
                layer.enabled: true
                preferredRendererType: Shape.GeometryRenderer // Fixes lag by hardware accelerating the stroke

                property real sw: root.s(6)
                property real inset: (sw / 2) + root.s(0.5) 
                property real w: width
                property real h: height
                property real r: root.s(14) - inset
                
                // Mathematical perimeter
                property real straightLines: 2 * (w - 2 * inset - 2 * r) + 2 * (h - 2 * inset - 2 * r)
                property real arcLines: 2 * Math.PI * r
                property real perimeter: straightLines + arcLines

                property real drawProgress: 0

                NumberAnimation on drawProgress {
                    id: chargeAnim
                    from: 0
                    to: maskRectOuter.perimeter
                    duration: 1200 // The time it takes to "charge" the whole wick
                    easing.type: Easing.OutCubic
                    running: true // Ensure it starts reliably
                }

                ShapePath {
                    strokeWidth: maskRectOuter.sw
                    strokeColor: "black" 
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap 

                    // QML Shape dash patterns are measured in units of strokeWidth! 
                    dashPattern: [maskRectOuter.perimeter / maskRectOuter.sw, maskRectOuter.perimeter / maskRectOuter.sw]
                    dashOffset: (maskRectOuter.perimeter - maskRectOuter.drawProgress) / maskRectOuter.sw

                    // Start exactly at Bottom-Left corner, going UP clockwise
                    startX: maskRectOuter.inset
                    startY: maskRectOuter.h - maskRectOuter.inset - maskRectOuter.r

                    // 1. Up to top-left corner
                    PathLine { x: maskRectOuter.inset; y: maskRectOuter.inset + maskRectOuter.r }
                    // 2. Arc top-left
                    PathArc { 
                        x: maskRectOuter.inset + maskRectOuter.r; y: maskRectOuter.inset 
                        radiusX: maskRectOuter.r; radiusY: maskRectOuter.r; direction: PathArc.Clockwise 
                    }
                    // 3. Right to top-right corner
                    PathLine { x: maskRectOuter.w - maskRectOuter.inset - maskRectOuter.r; y: maskRectOuter.inset }
                    // 4. Arc top-right
                    PathArc { 
                        x: maskRectOuter.w - maskRectOuter.inset; y: maskRectOuter.inset + maskRectOuter.r 
                        radiusX: maskRectOuter.r; radiusY: maskRectOuter.r; direction: PathArc.Clockwise 
                    }
                    // 5. Down to bottom-right corner
                    PathLine { x: maskRectOuter.w - maskRectOuter.inset; y: maskRectOuter.h - maskRectOuter.inset - maskRectOuter.r }
                    // 6. Arc bottom-right
                    PathArc { 
                        x: maskRectOuter.w - maskRectOuter.inset - maskRectOuter.r; y: maskRectOuter.h - maskRectOuter.inset 
                        radiusX: maskRectOuter.r; radiusY: maskRectOuter.r; direction: PathArc.Clockwise 
                    }
                    // 7. Left to bottom-left corner
                    PathLine { x: maskRectOuter.inset + maskRectOuter.r; y: maskRectOuter.h - maskRectOuter.inset }
                    // 8. Arc bottom-left to finish
                    PathArc { 
                        x: maskRectOuter.inset; y: maskRectOuter.h - maskRectOuter.inset - maskRectOuter.r 
                        radiusX: maskRectOuter.r; radiusY: maskRectOuter.r; direction: PathArc.Clockwise 
                    }
                }
            }

            Item {
                id: gradContainer
                anchors.fill: parent
                visible: false // Hidden for MultiEffect mapping
                clip: true // Prevents the rotated gradient bounding box from bulging out the sides!

                Rectangle {
                    width: Math.max(parent.width, parent.height) * 2
                    height: width
                    anchors.centerIn: parent
                    
                    NumberAnimation on rotation {
                        from: 0; to: 360
                        // Tempo-synced border gradient sweep
                        duration: root.beatMs * root.beatsPerRotation * 0.625
                        loops: Animation.Infinite
                        running: true
                    }

                    gradient: Gradient {
                        // FIXED: Using securely unpacked color bindings
                        GradientStop { position: 0.0; color: root.bc1; Behavior on color { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } } }
                        GradientStop { position: 0.33; color: root.bc2; Behavior on color { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } } }
                        GradientStop { position: 0.66; color: root.bc3; Behavior on color { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } } }
                        GradientStop { position: 1.0; color: root.bc4; Behavior on color { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } } }
                    }
                }
            }

            MultiEffect {
                source: gradContainer
                anchors.fill: parent
                maskEnabled: true
                maskSource: maskRectOuter
            }
        }

        // INNER WINDOW BOX
        Rectangle {
            id: innerBg
            anchors.fill: parent
            anchors.margins: root.s(3)
            color: root.base
            radius: root.s(10)

            // FIX: This forces the entire background to render as a single hardware texture,
            // preventing the UI from dragging and causing "shadow boxes" during the StackView transition!
            layer.enabled: true

            // Provide a perfectly rounded mask for the inner content
            Rectangle {
                id: innerBgMask
                anchors.fill: parent
                radius: root.s(10)
                visible: false
                
                // FIX: Masks in MultiEffect strictly require layer.enabled to correctly capture the radius during scaling!
                layer.enabled: true 
            }

            Item {
                id: bgEffectsLayer
                anchors.fill: parent
                
                // This correctly clamps the blur and orbit circles to the 10px radius corners
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: innerBgMask
                }

                // LAYER 1: Background Blur (Smooth fade-in)
                Image {
                    anchors.fill: parent
                    source: root.musicData.blur ? "file://" + root.musicData.blur : ""
                    fillMode: Image.PreserveAspectCrop
                    
                    // Fixed: Ensures blur is completely hidden when stopped so the pure base color matches the calendar
                    opacity: (status === Image.Ready && root.musicData.status !== "Stopped" && root.musicData.status !== "Offline") ? 0.9 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 800; easing.type: Easing.InOutQuad } }
                }

                // LAYER 1.5: Flowing Orbits
                Rectangle {
                    width: parent.width * 0.8; height: width; radius: width / 2
                    x: (parent.width / 2 - width / 2) + Math.cos(root.globalOrbitAngle * 2) * root.s(150)
                    y: (parent.height / 2 - height / 2) + Math.sin(root.globalOrbitAngle * 2) * root.s(100)
                    
                    // Hidden when stopped; scales up with tempo energy when playing
                    opacity: root.musicData.status === "Playing" ? (0.05 + root.energy * 0.08) : (root.musicData.status === "Paused" ? 0.04 : 0.0)
                    // Blended with the album art's own dominant color, so this shifts per song
                    color: root.musicData.status === "Playing" ? root.songOrbit1 : root.surface2
                    Behavior on color { ColorAnimation { duration: 1000 } }
                    Behavior on opacity { NumberAnimation { duration: 1000 } }
                }

                Rectangle {
                    width: parent.width * 0.9; height: width; radius: width / 2
                    x: (parent.width / 2 - width / 2) + Math.sin(root.globalOrbitAngle * 1.5) * root.s(-150)
                    y: (parent.height / 2 - height / 2) + Math.cos(root.globalOrbitAngle * 1.5) * root.s(-100)

                    // Hidden when stopped; scales up with tempo energy when playing
                    opacity: root.musicData.status === "Playing" ? (0.05 + root.energy * 0.08) : (root.musicData.status === "Paused" ? 0.02 : 0.0)
                    // Blended with the album art's own dominant color, so this shifts per song
                    color: root.musicData.status === "Playing" ? root.songOrbit2 : root.surface1
                    Behavior on color { ColorAnimation { duration: 1000 } }
                    Behavior on opacity { NumberAnimation { duration: 1000 } }
                }
            }

            // LAYER 2: UI Content
            // Content grew past the popup's fixed height (EQ / My Presets
            // sections), so it needs to scroll instead of silently overflowing the window.
            ScrollView {
                anchors.fill: parent
                anchors.margins: root.s(20)
                clip: true
                // Without this, QQC2 binds contentWidth from the child's
                // OWN implicit width (a circular resolve against the child's
                // `width: parent.width` below) instead of the viewport, so
                // the ColumnLayout never actually stretches to fill —
                // this was the "empty space on the right" bug.
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle { implicitWidth: root.s(4); radius: root.s(2); color: root.surface2; opacity: 0.5 }
                }

            ColumnLayout {
                width: parent.width
                spacing: 0

                // ==========================================
                // TOP INFO SECTION
                // ==========================================
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(220)
                    spacing: root.s(25)

                    // Cover Art Wrapper
                    Item {
                        id: coverWrap
                        Layout.preferredWidth: root.s(220)
                        Layout.preferredHeight: root.s(220)
                        Layout.alignment: Qt.AlignVCenter

                        opacity: root.introCover
                        // Enhanced 2D drift animation
                        transform: Translate { x: root.s(-40) * (1 - root.introCover); y: root.s(10) * (1 - root.introCover) }

                        // Elastic response to play/pause state
                        scale: root.musicData.status === "Playing" ? 1.0 : 0.90
                        Behavior on scale { NumberAnimation { duration: 800; easing.type: Easing.OutElastic; easing.overshoot: 1.2 } }

                        Item {
                            id: vizRing
                            anchors.fill: parent
                            readonly property bool playing: root.musicData.status === "Playing"
                            readonly property bool alive: root.musicData.status === "Playing" || root.musicData.status === "Paused"
                            property real t: 0
                            property real kick: 0
                            property real amp: playing ? 1 : 0.2
                            Behavior on amp { NumberAnimation { duration: 900; easing.type: Easing.InOutCubic } }
                            opacity: alive ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 600 } }
                            NumberAnimation on t {
                                from: 0; to: Math.PI * 8
                                duration: vizRing.playing ? 9000 : 26000
                                loops: Animation.Infinite
                                running: vizRing.alive && root.visible
                            }
                            NumberAnimation { id: vizKickAnim; target: vizRing; property: "kick"; from: 1; to: 0; duration: Math.max(140, root.beatMs * 0.8); easing.type: Easing.OutCubic }
                            Connections {
                                target: root
                                function onBeatPulseChanged() { if (vizRing.playing) vizKickAnim.restart() }
                            }
                            Repeater {
                                model: 64
                                delegate: Item {
                                    anchors.fill: parent
                                    rotation: index * 360 / 64
                                    readonly property real wave: 0.5 + 0.5 * Math.sin(vizRing.t * 3 + index * 0.62) * Math.cos(vizRing.t * 2 - index * 0.27)
                                    Rectangle {
                                        width: root.s(3)
                                        radius: width / 2
                                        height: Math.min(root.s(21), root.s(3) + vizRing.amp * (root.s(4) + root.s(12) * parent.wave * (0.45 + root.audioLevel) + root.s(7) * vizRing.kick * parent.wave))
                                        x: parent.width / 2 - width / 2
                                        y: parent.height / 2 - root.s(91) - height
                                        color: root.mixColor(root.vizC1, root.vizC2, Math.abs((index / 32) % 2 - 1))
                                        opacity: 0.45 + 0.55 * parent.wave
                                    }
                                }
                            }
                        }

                        property real spin: root.musicData.status === "Playing" ? 1 : 0
                        Behavior on spin { NumberAnimation { duration: coverWrap.spin < 0.5 ? 700 : 1800; easing.type: Easing.InOutCubic } }
                        FrameAnimation {
                            running: coverWrap.spin > 0.001 && root.visible
                            onTriggered: vinylDisc.rotation = (vinylDisc.rotation + frameTime * 360000 / Math.max(1, root.beatMs * root.beatsPerRotation) * coverWrap.spin) % 360
                        }

                        Rectangle {
                            id: vinylDisc
                            anchors.centerIn: parent
                            width: parent.width * 0.78; height: width
                            radius: width / 2
                            color: root.surface1
                            border.width: root.s(4)
                            border.color: root.musicData.status === "Playing" ? root.accentColor : root.overlay0
                            Behavior on border.color { ColorAnimation { duration: 500 } }

                            // Glow Effect surrounding the thumbnail
                            // Color blends per-song album art with the matugen accent (root.songGlow);
                            // scale/opacity breathe gently with root.audioLevel (short parec RMS sample).
                            Rectangle {
                                z: -1
                                anchors.centerIn: parent
                                width: (parent.width + root.s(20)) * (1.0 + root.audioLevel * 0.035)
                                height: (parent.height + root.s(20)) * (1.0 + root.audioLevel * 0.035)
                                radius: width / 2
                                color: root.songGlow
                                Behavior on color { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }
                                opacity: root.musicData.status === "Playing" ? (0.42 + root.audioLevel * 0.18) : 0.0
                                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    blurEnabled: true
                                    blurMax: 32
                                    blur: 1.0
                                }
                            }

                            // Beat-flash ring — a quick sonar-ping pulse fired once per beat
                            // (root.beatPulse toggles on beatClock), separate from the slow
                            // continuous breathing above, for a sharper "on the beat" feel.
                            Rectangle {
                                id: beatRing
                                z: -1
                                anchors.centerIn: parent
                                width: parent.width; height: parent.height
                                radius: width / 2
                                color: "transparent"
                                border.width: root.s(3)
                                border.color: root.songGlow
                                opacity: 0
                                scale: 1.0
                                visible: root.musicData.status === "Playing"

                                Connections {
                                    target: root
                                    function onBeatPulseChanged() { beatPulseAnim.restart(); }
                                }
                                ParallelAnimation {
                                    id: beatPulseAnim
                                    NumberAnimation { target: beatRing; property: "opacity"; from: 0.35 + root.energy * 0.35; to: 0; duration: Math.max(120, root.beatMs * 0.85); easing.type: Easing.OutQuad }
                                    NumberAnimation { target: beatRing; property: "scale"; from: 1.0; to: 1.1 + root.energy * 0.12; duration: Math.max(120, root.beatMs * 0.85); easing.type: Easing.OutQuad }
                                }
                            }

                            Item {
                                anchors.fill: parent
                                anchors.margins: root.s(4)
                                Image {
                                    id: artImg
                                    anchors.fill: parent
                                    source: root.musicData.artUrl ? "file://" + root.musicData.artUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                    visible: false 
                                }
                                Rectangle {
                                    id: maskRect
                                    anchors.fill: parent
                                    radius: width / 2
                                    visible: false
                                    layer.enabled: true 
                                }
                                MultiEffect {
                                    anchors.fill: parent
                                    source: artImg
                                    maskEnabled: true
                                    maskSource: maskRect
                                    opacity: artImg.status === Image.Ready ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 800 } }
                                }
                                
                                // NEW: Dimmed slightly by tinting with the primary accent color
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.2)
                                    opacity: artImg.status === Image.Ready ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 800 } }
                                }

                                Repeater {
                                    model: 6
                                    delegate: Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width * (0.42 + index * 0.1); height: width
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Qt.alpha(root.base, 0.16 + (index % 2) * 0.08)
                                        opacity: artImg.status === Image.Ready ? 1 : 0
                                    }
                                }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: root.s(58); height: width
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: root.s(2)
                                    border.color: Qt.alpha(root.accentColor, 0.55)
                                }
                                Rectangle {
                                    width: root.s(40); height: root.s(40)
                                    radius: root.s(20); color: "#000000"
                                    opacity: 0.8; anchors.centerIn: parent
                                }
                            }
                        }

                        Shape {
                            id: vinylSheen
                            anchors.centerIn: vinylDisc
                            width: vinylDisc.width - root.s(8); height: width
                            opacity: artImg.status === Image.Ready ? (coverWrap.spin > 0.5 ? 0.95 : 0.6) : 0
                            Behavior on opacity { NumberAnimation { duration: 800 } }
                            ShapePath {
                                strokeWidth: -1
                                strokeColor: "transparent"
                                fillGradient: ConicalGradient {
                                    centerX: vinylSheen.width / 2; centerY: vinylSheen.height / 2
                                    angle: 40
                                    GradientStop { position: 0.00; color: "transparent" }
                                    GradientStop { position: 0.07; color: Qt.alpha(root.text, 0.28) }
                                    GradientStop { position: 0.15; color: "transparent" }
                                    GradientStop { position: 0.50; color: "transparent" }
                                    GradientStop { position: 0.57; color: Qt.alpha(root.text, 0.2) }
                                    GradientStop { position: 0.65; color: "transparent" }
                                    GradientStop { position: 1.00; color: "transparent" }
                                }
                                startX: vinylSheen.width; startY: vinylSheen.height / 2
                                PathAngleArc {
                                    centerX: vinylSheen.width / 2; centerY: vinylSheen.height / 2
                                    radiusX: vinylSheen.width / 2; radiusY: vinylSheen.height / 2
                                    startAngle: 0; sweepAngle: 360
                                }
                            }
                        }

                        Item {
                            id: tonearm
                            z: 5
                            x: parent.width - root.s(10); y: root.s(8)
                            width: 0; height: 0
                            opacity: vizRing.alive ? 1 : 0.35
                            Behavior on opacity { NumberAnimation { duration: 600 } }
                            property real angle: vizRing.playing ? 22 : -4
                            Behavior on angle { SpringAnimation { spring: 2.4; damping: 0.16; epsilon: 0.05 } }
                            property real wob: 0
                            NumberAnimation { id: tonearmWobAnim; target: tonearm; property: "wob"; from: 0.6; to: 0; duration: Math.max(140, root.beatMs * 0.7); easing.type: Easing.OutElastic }
                            Connections {
                                target: root
                                function onBeatPulseChanged() { if (vizRing.playing) tonearmWobAnim.restart() }
                            }
                            Item {
                                rotation: tonearm.angle + tonearm.wob
                                Rectangle {
                                    x: -root.s(2); y: 0
                                    width: root.s(4); height: root.s(112)
                                    radius: root.s(2)
                                    antialiasing: true
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: Qt.alpha(root.text, 0.9) }
                                        GradientStop { position: 1.0; color: Qt.alpha(root.text, 0.6) }
                                    }
                                }
                                Rectangle {
                                    x: -root.s(7); y: root.s(104)
                                    width: root.s(14); height: root.s(20)
                                    radius: root.s(3)
                                    antialiasing: true
                                    color: root.text
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom; anchors.bottomMargin: root.s(3)
                                        width: root.s(4); height: width; radius: width / 2
                                        color: root.accentColor
                                    }
                                }
                            }
                            Rectangle {
                                x: -width / 2; y: -height / 2
                                width: root.s(20); height: width
                                radius: width / 2
                                color: root.surface2
                                border.width: 1
                                border.color: Qt.alpha(root.text, 0.3)
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: root.s(8); height: width; radius: width / 2
                                    color: root.accentColor
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: root.s(15)

                        // TEXT INFO CHUNK
                        ColumnLayout {
                            spacing: root.s(6)
                            opacity: root.introText
                            transform: Translate { x: root.s(30) * (1 - root.introText) }
                            
                            // HARD-LOCKED SEAMLESS INFINITE MARQUEE
                            Item {
                                id: titleClipRect
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(34)
                                clip: true

                                // This is the distance between the end of the text and the clone
                                property int marqueeSpacing: root.s(60)

                                Item {
                                    id: marqueeContainer
                                    height: parent.height

                                    Row {
                                        spacing: titleClipRect.marqueeSpacing
                                        Text {
                                            id: titleTextMain
                                            text: root.musicData.title
                                            color: root.dynamicTextColor
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: root.s(25)
                                            font.weight: Font.Black
                                            Behavior on color { ColorAnimation { duration: 600 } }

                                            // A flex-worthy hero glow behind the title — subtle at rest,
                                            // brightens with the same audioLevel breathing the cover art uses.
                                            layer.enabled: root.musicData.status === "Playing"
                                            layer.effect: MultiEffect {
                                                shadowEnabled: true
                                                shadowColor: root.accentColor
                                                shadowBlur: 0.7
                                                shadowOpacity: 0.55 + root.audioLevel * 0.25
                                                shadowHorizontalOffset: 0
                                                shadowVerticalOffset: 0
                                            }

                                            // Only animate if the text is physically wider than our container
                                            onTextChanged: {
                                                marqueeContainer.x = 0;
                                                if (implicitWidth > titleClipRect.width) {
                                                    titleAnim.restart();
                                                } else {
                                                    titleAnim.stop();
                                                }
                                            }
                                        }
                                        // The clone that creates the seamless endless loop
                                        Text {
                                            id: titleTextClone
                                            text: root.musicData.title
                                            color: root.dynamicTextColor
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: root.s(25)
                                            font.weight: Font.Black
                                            visible: titleTextMain.implicitWidth > titleClipRect.width
                                        }
                                    }

                                    SequentialAnimation on x {
                                        id: titleAnim
                                        loops: Animation.Infinite
                                        running: titleTextMain.implicitWidth > titleClipRect.width

                                        // 1. Stop for a few seconds in the initial position
                                        PauseAnimation { duration: 3000 }
                                        
                                        // 2. Smoothly run left until the clone is exactly where the original started
                                        NumberAnimation {
                                            from: 0
                                            to: -(titleTextMain.implicitWidth + titleClipRect.marqueeSpacing)
                                            // The duration calculates dynamically to maintain a constant scroll speed
                                            duration: (titleTextMain.implicitWidth + titleClipRect.marqueeSpacing) * 25
                                        }
                                        
                                        // 3. Instantly snap back to 0 without stopping (creating the seamless loop)
                                        PropertyAction { target: marqueeContainer; property: "x"; value: 0 }
                                    }
                                }
                            }

                            Text {
                                text: root.musicData.artist ? "BY " + root.musicData.artist : ""
                                color: root.subtext0 // Better matugen match
                                font.family: "JetBrains Mono"
                                font.pixelSize: root.s(14)
                                font.bold: true
                                elide: Text.ElideRight
                                maximumLineCount: 1 // Strict 1 line
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(20)
                            }
                            RowLayout {
                                spacing: root.s(10)
                                Rectangle {
                                    color: "#1AFFFFFF"
                                    radius: root.s(4)
                                    Layout.preferredHeight: root.s(24)
                                    Layout.preferredWidth: pillContent.width + root.s(20)
                                    RowLayout {
                                        id: pillContent
                                        anchors.centerIn: parent
                                        spacing: root.s(6)
                                        Text { text: root.musicData.deviceIcon || "󰓃"; color: root.mauve; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(14) }
                                        Text { text: root.musicData.deviceName || "Speaker"; color: root.overlay2; font.family: "JetBrains Mono"; font.pixelSize: root.s(12); font.bold: true }
                                    }
                                }
                                Text {
                                    text: "VIA " + (root.musicData.source || "Offline")
                                    color: root.overlay2 // Better matugen match
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: root.s(12)
                                    font.bold: true
                                    font.italic: true
                                }
                                Rectangle {
                                    visible: root.musicData.status === "Playing" && root.musicData.bpm > 0
                                    color: "#1AFFFFFF"
                                    radius: root.s(4)
                                    Layout.preferredHeight: root.s(24)
                                    Layout.preferredWidth: bpmPillContent.width + root.s(20)
                                    RowLayout {
                                        id: bpmPillContent
                                        anchors.centerIn: parent
                                        spacing: root.s(6)
                                        Text { text: "󰽲"; color: root.accentColor; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(14) }
                                        Text { text: root.musicData.bpm.toFixed(0) + " BPM"; color: root.overlay2; font.family: "JetBrains Mono"; font.pixelSize: root.s(12); font.bold: true }
                                    }
                                }
                            }
                        }

                        // PROGRESS AREA CHUNK
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: root.s(5)
                            opacity: root.introControls
                            transform: Translate { x: root.s(20) * (1 - root.introControls); y: root.s(10) * (1 - root.introControls) }

                            Slider {
                                id: progBar
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(20) 
                                from: 0; to: 100

                                Connections {
                                    target: root
                                    function onMusicDataChanged() {
                                        if (!progBar.pressed && !root.userIsSeeking) {
                                            if (root.musicData && root.musicData.percent !== undefined) {
                                                var p = Number(root.musicData.percent);
                                                if (!isNaN(p)) progBar.value = p;
                                            }
                                        }
                                    }
                                }

                                Behavior on value {
                                    enabled: !progBar.pressed && !root.userIsSeeking
                                    NumberAnimation { duration: 400; easing.type: Easing.OutSine }
                                }

                                onPressedChanged: {
                                    if (pressed) {
                                        root.userIsSeeking = true;
                                        seekDebounceTimer.stop();
                                    } else {
                                        var temp = Object.assign({}, root.musicData);
                                        temp.percent = value;
                                        root.musicData = temp;

                                        var safePlayer = root.musicData.playerName ? root.musicData.playerName : "";
                                        root.execCmd(`$HOME/.config/hypr/scripts/quickshell/music/player_control.sh seek ${value.toFixed(2)} ${root.musicData.length} "${safePlayer}"`);
                                        
                                        seekDebounceTimer.restart();
                                    }
                                }

                                background: Item {
                                    x: progBar.leftPadding
                                    y: progBar.topPadding + (progBar.availableHeight - root.s(12)) / 2
                                    width: progBar.availableWidth
                                    height: root.s(12)

                                    // Shadows mimicking the EQ slider background
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: root.s(6)
                                        // Dynamic tint: surface0 with 70% opacity for a softer dark look
                                        color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.7)

                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            shadowEnabled: true
                                            shadowColor: "#000000"
                                            shadowOpacity: 0.9
                                            shadowBlur: 0.5
                                            shadowVerticalOffset: 1
                                        }
                                    }

                                    // Masked Gradient Fill (Completely redesigned for smooth, light, synergistic palette)
                                    Item {
                                        width: progBar.handle.x - progBar.leftPadding + (progBar.handle.width / 2)
                                        height: parent.height
                                        
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            maskEnabled: true
                                            maskSource: sliderFillMask
                                        }

                                        Rectangle {
                                            id: sliderFillMask
                                            width: parent.width
                                            height: parent.height
                                            radius: root.s(6)
                                            visible: false
                                            layer.enabled: true 
                                        }

                                        Rectangle {
                                            width: root.s(2000)
                                            height: parent.height
                                            // Sliding the gradient perfectly by exactly half its width (1000px)
                                            x: -(root.catppuccinFlowOffset * root.s(1000)) 
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                // Mathematically precise loops with lighter, cooler colors & theme change support
                                                GradientStop { position: 0.0000; color: Qt.lighter(root.blue, 1.2); Behavior on color { ColorAnimation { duration: 800 } } }
                                                GradientStop { position: 0.1666; color: Qt.lighter(root.sapphire, 1.15); Behavior on color { ColorAnimation { duration: 800 } } }
                                                GradientStop { position: 0.3333; color: Qt.lighter(root.mauve, 1.15); Behavior on color { ColorAnimation { duration: 800 } } }
                                                GradientStop { position: 0.5000; color: Qt.lighter(root.blue, 1.2); Behavior on color { ColorAnimation { duration: 800 } } }
                                                GradientStop { position: 0.6666; color: Qt.lighter(root.sapphire, 1.15); Behavior on color { ColorAnimation { duration: 800 } } }
                                                GradientStop { position: 0.8333; color: Qt.lighter(root.mauve, 1.15); Behavior on color { ColorAnimation { duration: 800 } } }
                                                GradientStop { position: 1.0000; color: Qt.lighter(root.blue, 1.2); Behavior on color { ColorAnimation { duration: 800 } } }
                                            }
                                        }
                                    }
                                }

                                handle: Rectangle {
                                    x: progBar.leftPadding + progBar.visualPosition * (progBar.availableWidth - width)
                                    y: progBar.topPadding + (progBar.availableHeight - height) / 2
                                    implicitWidth: root.s(18)
                                    implicitHeight: root.s(18)
                                    width: root.s(18); height: root.s(18)
                                    radius: root.s(9); color: root.text
                                    scale: progBar.pressed ? 1.3 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                    Rectangle {
                                        z: -1
                                        anchors.centerIn: parent
                                        width: parent.width + root.s(14); height: width
                                        radius: width / 2
                                        color: root.accentColor
                                        opacity: root.musicData.status === "Playing" ? (0.35 + root.audioLevel * 0.25) : (progBar.pressed || progBar.hovered ? 0.3 : 0.0)
                                        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }
                                        Behavior on color { ColorAnimation { duration: 800 } }
                                        layer.enabled: true
                                        layer.effect: MultiEffect { blurEnabled: true; blurMax: 24; blur: 1.0 }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: root.musicData.positionStr || "00:00"; color: root.overlay2; font.family: "JetBrains Mono"; font.bold: true; font.pixelSize: root.s(13) }
                                Item { Layout.fillWidth: true }
                                Text { text: root.musicData.lengthStr || "00:00"; color: root.overlay2; font.family: "JetBrains Mono"; font.bold: true; font.pixelSize: root.s(13) }
                            }
                        }

                        // MEDIA CONTROLS CHUNK
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: root.s(30)
                            opacity: root.introControls
                            transform: Translate { y: root.s(20) * (1 - root.introControls) }

                            MouseArea {
                                id: prevBtn
                                width: root.s(38); height: root.s(38)
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.execCmd("playerctl --player=spotify previous")
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width; height: parent.height; radius: width / 2
                                    color: root.accentColor
                                    opacity: prevBtn.containsMouse ? (prevBtn.pressed ? 0.28 : 0.14) : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                }
                                Text {
                                    anchors.centerIn: parent; text: ""
                                    color: prevBtn.pressed ? root.text : root.overlay2
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(24)
                                    scale: prevBtn.pressed ? 0.85 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                            }
                            MouseArea {
                                id: playPauseBtn
                                width: root.s(50); height: root.s(50)
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.userToggledPlay = true;
                                    playDebounceTimer.restart();
                                    var temp = Object.assign({}, root.musicData);
                                    temp.status = (temp.status === "Playing" ? "Paused" : "Playing");
                                    root.musicData = temp;
                                    root.execCmd("playerctl --player=spotify play-pause");
                                }

                                // Steady ambient halo — always present while
                                // playing, brightens further on hover/press;
                                // separate from the one-shot ripple below.
                                Rectangle {
                                    z: -1
                                    anchors.centerIn: parent
                                    width: parent.width + root.s(20); height: width
                                    radius: width / 2
                                    color: root.accentColor
                                    opacity: (root.musicData.status === "Playing" ? 0.28 : 0.1) + (playPauseBtn.containsMouse ? 0.16 : 0.0)
                                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }
                                    Behavior on color { ColorAnimation { duration: 800 } }
                                    layer.enabled: true
                                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: 1.0 }
                                }

                                // Fluid Ripple Animation Element
                                Rectangle {
                                    id: playPulse
                                    anchors.centerIn: parent
                                    width: parent.width
                                    height: parent.height
                                    radius: width / 2
                                    color: root.accentColor
                                    opacity: 0
                                    scale: 1

                                    NumberAnimation {
                                        id: playPulseScaleAnim
                                        target: playPulse
                                        property: "scale"
                                        from: 1.0; to: 1.8
                                        duration: root.beatMs // one beat's worth of ripple
                                        easing.type: Easing.OutQuart
                                    }
                                    NumberAnimation {
                                        id: playPulseFadeAnim
                                        target: playPulse
                                        property: "opacity"
                                        from: 0.5; to: 0.0
                                        duration: root.beatMs
                                        easing.type: Easing.OutQuart
                                    }

                                    function trigger() {
                                        playPulseScaleAnim.restart();
                                        playPulseFadeAnim.restart();
                                    }
                                }

                                Text { 
                                    anchors.centerIn: parent
                                    text: root.musicData.status === "Playing" ? "" : ""
                                    color: parent.pressed ? root.pink : root.accentColor
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: root.s(42)
                                    scale: parent.pressed ? 0.8 : 1.0
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                }
                            }
                            MouseArea {
                                id: nextBtn
                                width: root.s(38); height: root.s(38)
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.execCmd("playerctl --player=spotify next")
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width; height: parent.height; radius: width / 2
                                    color: root.accentColor
                                    opacity: nextBtn.containsMouse ? (nextBtn.pressed ? 0.28 : 0.14) : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                }
                                Text {
                                    anchors.centerIn: parent; text: ""
                                    color: nextBtn.pressed ? root.text : root.overlay2
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(24)
                                    scale: nextBtn.pressed ? 0.85 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                            }
                        }
                    }
                }

                // ==========================================
                // SEPARATOR
                // ==========================================
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(2)
                    Layout.topMargin: root.s(20)
                    Layout.bottomMargin: root.s(20)
                    color: "#1AFFFFFF"
                    radius: root.s(1)

                    opacity: root.introSeparator
                    transform: Translate { y: root.s(15) * (1 - root.introSeparator) }
                }

                // ==========================================
                // EQUALIZER
                // ==========================================
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: root.s(15)

                    // Header Row
                    RowLayout {
                        Layout.fillWidth: true
                        opacity: root.introEqHeader
                        transform: Translate { y: root.s(15) * (1 - root.introEqHeader) }

                        Text { text: "Equalizer"; color: root.mauve; font.family: "JetBrains Mono"; font.pixelSize: root.s(16); font.bold: true; Layout.fillWidth: true }
                        
                        // Redesigned Apply Button
                        Rectangle {
                            Layout.preferredHeight: root.s(28)
                            Layout.preferredWidth: applyTxt.width + root.s(30)
                            radius: root.s(10)
                            color: root.eqData.pending ? root.mauve : root.surface1
                            border.color: root.eqData.pending ? root.mauve : root.surface2
                            border.width: 1
                            
                            Behavior on color { ColorAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 300; easing.type: Easing.OutCubic } }

                            layer.enabled: root.eqData.pending
                            layer.effect: MultiEffect {
                                shadowEnabled: true; shadowColor: root.mauve; shadowOpacity: 0.4; shadowBlur: 0.6
                            }

                            Text {
                                id: applyTxt
                                anchors.centerIn: parent
                                text: root.eqData.pending ? "Apply" : "Saved"
                                color: root.eqData.pending ? root.base : root.subtext0
                                font.family: "JetBrains Mono"
                                font.pixelSize: root.s(12)
                                font.bold: true
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: root.eqData.pending ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (root.eqData.pending) {
                                        var temp = Object.assign({}, root.eqData);
                                        temp.pending = false;
                                        root.eqData = temp;
                                        
                                        // Blind the polling process to stop it from fetching old data
                                        root.lastEqUpdate = Date.now(); 
                                        
                                        root.triggerEqLightning();
                                        root.execCmd("$HOME/.config/hypr/scripts/quickshell/music/equalizer.sh apply");
                                    }
                                }
                            }
                        }
                        Text { text: root.eqData.preset || "Flat"; color: root.subtext0; font.family: "JetBrains Mono"; font.pixelSize: root.s(14); font.bold: true; Layout.leftMargin: root.s(15) }
                    }

                    // Eq Sliders Container with Canvas Lightning Overlay
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(180)

                        Row {
                            id: eqSliderRow
                            anchors.fill: parent
                            z: 1 // Ensures sliders (and their handles) render over the lightning

                            Repeater {
                                model: [
                                    {"idx": 1, "lbl": "31"}, {"idx": 2, "lbl": "63"}, {"idx": 3, "lbl": "125"},
                                    {"idx": 4, "lbl": "250"}, {"idx": 5, "lbl": "500"}, {"idx": 6, "lbl": "1k"},
                                    {"idx": 7, "lbl": "2k"}, {"idx": 8, "lbl": "4k"}, {"idx": 9, "lbl": "8k"},
                                    {"idx": 10, "lbl": "16k"}
                                ]
                                delegate: Item {
                                    id: sliderDelegate
                                    width: eqSliderRow.width / 10 
                                    height: eqSliderRow.height

                                    // --- ENHANCED SLIDER CASCADING ANIMATION ---
                                    opacity: root.introEqSliders
                                    transform: Translate {
                                        y: root.s(30) * (1 - root.introEqSliders) + (index * root.s(8) * (1 - root.introEqSliders))
                                    }

                                    // Mathematical evaluation mapping to the exact timeline of the strike
                                    property real dist: root.eqLightningProgress - (modelData.idx - 1)
                                    property real hitPulse: dist >= 0 && dist < 1.0 ? Math.sin((dist) * Math.PI) : 0.0
                                    
                                    // Massive Energy Pulses
                                    property real trackPulse: 0.0
                                    property real ringPulse: 0.0
                                    property real flashFade: 0.0
                                    property bool hasFired: false

                                    onDistChanged: {
                                        // Reset the fire lock when the animation sweeps past or starts over
                                        if (dist <= 0.05) {
                                            hasFired = false;
                                        } else if (dist > 0.4 && !hasFired) {
                                            // Trigger strictly once per bolt passing over
                                            hasFired = true;
                                            trackPulseAnim.restart();
                                            ringPulseAnim.restart();
                                            flashFadeAnim.restart();
                                        }
                                    }

                                    SequentialAnimation {
                                        id: trackPulseAnim
                                        // Animates the bolt perfectly down the track
                                        NumberAnimation { target: sliderDelegate; property: "trackPulse"; from: 0.0; to: 1.0; duration: 1000; easing.type: Easing.OutQuart }
                                    }
                                    SequentialAnimation {
                                        id: ringPulseAnim
                                        // Explodes outward creating a physical shockwave
                                        NumberAnimation { target: sliderDelegate; property: "ringPulse"; from: 1.0; to: 0.0; duration: 1500; easing.type: Easing.OutExpo }
                                    }
                                    SequentialAnimation {
                                        id: flashFadeAnim
                                        // Slowly cools the inner track gradient back to normal
                                        NumberAnimation { target: sliderDelegate; property: "flashFade"; from: 1.0; to: 0.0; duration: 1500; easing.type: Easing.OutSine }
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        spacing: root.s(5)
                                        Slider {
                                            id: eqSlider
                                            Layout.fillHeight: true
                                            Layout.alignment: Qt.AlignHCenter
                                            orientation: Qt.Vertical
                                            from: -12; to: 12
                                            stepSize: 1

                                            Connections {
                                                target: root
                                                function onEqDataChanged() {
                                                    if (!eqSlider.pressed) {
                                                        if (root.eqData && root.eqData["b" + modelData.idx] !== undefined) {
                                                            var p = Number(root.eqData["b" + modelData.idx]);
                                                            if (!isNaN(p)) eqSlider.value = p;
                                                        }
                                                    }
                                                }
                                            }

                                            Behavior on value {
                                                enabled: !eqSlider.pressed
                                                NumberAnimation {
                                                    duration: 350
                                                    easing.type: Easing.OutQuart
                                                }
                                            }
                                            onValueChanged: root.setEqLive(modelData.idx, value)

                                            onPressedChanged: {
                                                if (!pressed) {
                                                    var temp = Object.assign({}, root.eqData);
                                                    temp["b" + modelData.idx] = Math.round(value);
                                                    temp.preset = "Custom";
                                                    temp.pending = true;
                                                    root.eqData = temp;
                                                    
                                                    // Set lock here too to protect individual slider tweaks
                                                    root.lastEqUpdate = Date.now();
                                                    
                                                    root.execCmd(`$HOME/.config/hypr/scripts/quickshell/music/equalizer.sh set_band ${modelData.idx} ${Math.round(value)}`);
                                                }
                                            }

                                            background: Rectangle {
                                                id: trackBg
                                                x: eqSlider.leftPadding + (eqSlider.availableWidth - width) / 2
                                                y: eqSlider.topPadding
                                                implicitWidth: root.s(10) 
                                                implicitHeight: root.s(150)
                                                width: root.s(10); height: eqSlider.availableHeight
                                                radius: root.s(4); 
                                                
                                                // Dynamic tint: surface0 with 70% opacity for a softer dark look
                                                color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.7)

                                                layer.enabled: true
                                                layer.effect: MultiEffect {
                                                    id: trackEffect
                                                    shadowEnabled: true
                                                    shadowColor: "#000000"
                                                    shadowOpacity: 0.9
                                                    shadowBlur: 0.5
                                                    shadowVerticalOffset: 1
                                                }

                                                // MASSIVE Outer Energy Shockwave Ring 
                                                Rectangle {
                                                    z: -1
                                                    anchors.centerIn: parent
                                                    width: parent.width + root.s(20) + sliderDelegate.ringPulse * root.s(40)
                                                    height: parent.height + root.s(20) + sliderDelegate.ringPulse * root.s(60)
                                                    radius: parent.radius + root.s(10) + sliderDelegate.ringPulse * root.s(20)
                                                    color: "transparent"
                                                    border.color: root.mauve
                                                    border.width: root.s(2) + sliderDelegate.ringPulse * root.s(4)
                                                    opacity: sliderDelegate.ringPulse * 0.8 * (1.0 - root.eqLightningFade)
                                                    
                                                    layer.enabled: true
                                                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: 1.0 }
                                                }

                                                // The Track Fill Base (FIXED THE SQUARE CORNERS ISSUE)
                                                Item {
                                                    width: parent.width
                                                    height: (1 - eqSlider.visualPosition) * parent.height
                                                    y: eqSlider.visualPosition * parent.height
                                                    
                                                    layer.enabled: true
                                                    layer.effect: MultiEffect {
                                                        maskEnabled: true
                                                        maskSource: eqFillMask
                                                    }

                                                    Rectangle {
                                                        id: eqFillMask
                                                        anchors.fill: parent
                                                        radius: root.s(4)
                                                        visible: false
                                                        layer.enabled: true 
                                                    }

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        color: root.blue

                                                        // Track Override: Changes entire gradient of track
                                                        Rectangle {
                                                            anchors.fill: parent
                                                            opacity: sliderDelegate.flashFade
                                                            gradient: Gradient {
                                                                orientation: Gradient.Vertical
                                                                GradientStop { position: 0.0; color: root.mauve }
                                                                GradientStop { position: 0.5; color: root.blue }
                                                                GradientStop { position: 1.0; color: "transparent" }
                                                            }
                                                        }

                                                        // The Internal Charging Surge Bolt 
                                                        Rectangle {
                                                            width: parent.width
                                                            height: root.s(80) // Massive physical bolt
                                                            y: (sliderDelegate.trackPulse * (parent.height + height)) - height
                                                            opacity: Math.sin(sliderDelegate.trackPulse * Math.PI) * 2.0 * (1.0 - root.eqLightningFade)
                                                            
                                                            gradient: Gradient {
                                                                orientation: Gradient.Vertical
                                                                GradientStop { position: 0.0; color: "transparent" }
                                                                GradientStop { position: 0.2; color: root.blue }
                                                                GradientStop { position: 0.5; color: root.text } // Theme integrated bright center
                                                                GradientStop { position: 0.8; color: root.mauve }
                                                                GradientStop { position: 1.0; color: "transparent" }
                                                            }
                                                            
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true; shadowColor: root.blue; shadowBlur: 1.0; shadowOpacity: 1.0
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            handle: Rectangle {
                                                x: eqSlider.leftPadding + (eqSlider.availableWidth - width) / 2
                                                y: eqSlider.topPadding + eqSlider.visualPosition * (eqSlider.availableHeight - height)
                                                implicitWidth: root.s(18)
                                                implicitHeight: root.s(18)
                                                width: root.s(18); height: root.s(18)
                                                radius: root.s(9); color: root.text

                                                property var catColors: [root.mauve, root.pink, root.lavender, root.mauve, root.blue]

                                                // Core glow flare that cleanly fades out matching the canvas
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: parent.width + root.s(36) * sliderDelegate.hitPulse // Bigger bloom
                                                    height: width
                                                    radius: width / 2
                                                    color: parent.catColors[index % parent.catColors.length]
                                                    opacity: sliderDelegate.hitPulse * (1.0 - root.eqLightningFade)
                                                    layer.enabled: true
                                                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: 1.0 }
                                                }

                                                property real press: eqSlider.pressed ? 1 : (eqSlider.hovered ? 0.35 : 0)
                                                Behavior on press { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
                                                scale: 1.0 + press * 0.28 + (sliderDelegate.hitPulse * 0.4 * (1.0 - root.eqLightningFade))

                                                Rectangle {
                                                    z: -1
                                                    anchors.centerIn: parent
                                                    width: parent.width + root.s(12) * parent.press; height: width
                                                    radius: width / 2
                                                    color: "transparent"
                                                    border.width: root.s(2)
                                                    border.color: root.accentColor
                                                    opacity: parent.press * 0.7
                                                }

                                                Rectangle {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    anchors.bottom: parent.top; anchors.bottomMargin: root.s(10)
                                                    width: eqBubbleTxt.implicitWidth + root.s(14); height: root.s(20)
                                                    radius: height / 2
                                                    color: root.accentColor
                                                    opacity: eqSlider.pressed ? 1 : 0
                                                    scale: eqSlider.pressed ? 1 : 0.5
                                                    transformOrigin: Item.Bottom
                                                    visible: opacity > 0.01
                                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                                    Text {
                                                        id: eqBubbleTxt
                                                        anchors.centerIn: parent
                                                        text: (Math.round(eqSlider.value) > 0 ? "+" : "") + Math.round(eqSlider.value) + " dB"
                                                        color: root.base
                                                        font.family: "JetBrains Mono"; font.pixelSize: root.s(10); font.bold: true
                                                    }
                                                }
                                            }
                                        }
                                        Text {
                                            text: modelData.lbl
                                            color: root.overlay1
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: root.s(10)
                                            font.bold: true
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                    }
                                }
                            }
                        }

                        Canvas {
                            id: eqCurve
                            anchors.fill: parent
                            z: 0
                            renderTarget: Canvas.FramebufferObject
                            property color tint: root.vizC1
                            onTintChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            Connections {
                                target: root
                                function onEqLiveChanged() { eqCurve.requestPaint() }
                            }
                            onPaint: {
                                let ctx = getContext("2d")
                                ctx.reset()
                                if (width <= 0) return
                                let pts = []
                                for (let i = 0; i < 10; i++) {
                                    let v = root.eqLive[i] || 0
                                    pts.push({ x: (i + 0.5) * (width / 10), y: root.s(10) + (1.0 - (v + 12) / 24) * (height - root.s(35)) })
                                }
                                let rgb = Math.round(tint.r * 255) + "," + Math.round(tint.g * 255) + "," + Math.round(tint.b * 255)
                                let trace = function () {
                                    ctx.moveTo(pts[0].x, pts[0].y)
                                    for (let i = 0; i < pts.length - 1; i++) {
                                        let p0 = pts[Math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(pts.length - 1, i + 2)]
                                        ctx.bezierCurveTo(p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6,
                                                          p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6, p2.x, p2.y)
                                    }
                                }
                                let base = height - root.s(25)
                                ctx.beginPath()
                                trace()
                                ctx.lineTo(pts[9].x, base)
                                ctx.lineTo(pts[0].x, base)
                                ctx.closePath()
                                let g = ctx.createLinearGradient(0, 0, 0, base)
                                g.addColorStop(0, "rgba(" + rgb + ",0.30)")
                                g.addColorStop(1, "rgba(" + rgb + ",0)")
                                ctx.fillStyle = g
                                ctx.fill()
                                ctx.beginPath()
                                trace()
                                ctx.lineCap = "round"
                                ctx.lineJoin = "round"
                                ctx.strokeStyle = "rgba(" + rgb + ",0.18)"
                                ctx.lineWidth = root.s(7)
                                ctx.stroke()
                                ctx.strokeStyle = "rgba(" + rgb + ",0.85)"
                                ctx.lineWidth = root.s(2)
                                ctx.stroke()
                            }
                        }

                        // --- THE FLUID CANVAS LIGHTNING (Optimized for Realism and multiple waves) ---
                        Canvas {
                            id: lightningCanvas
                            anchors.fill: parent
                            opacity: 1.0 - root.eqLightningFade
                            z: 0 // Draw securely behind the sliders

                            // Force hardware FBO backend instead of slow software rendering
                            renderTarget: Canvas.FramebufferObject 

                            // GPU Layer effect to provide bloom WITHOUT locking up the CPU via ctx.shadowBlur
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: root.mauve
                                shadowBlur: 1.0 // 1.0 is max blur in MultiEffect
                                shadowOpacity: 0.6
                                shadowVerticalOffset: 0
                                shadowHorizontalOffset: 0
                            }

                            Timer {
                                interval: 16 // ~60fps for silky smooth arcs
                                running: root.eqLightningFade < 1.0 && root.eqLightningProgress > 0.0
                                repeat: true
                                onTriggered: lightningCanvas.requestPaint()
                            }

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);

                                if (root.eqLightningProgress <= 0.0 || root.eqLightningFade >= 1.0) return;

                                var time = Date.now() / 1000;
                                var maxIdx = root.eqLightningProgress; // 0 to 9

                                ctx.lineJoin = "round";
                                ctx.lineCap = "round";

                                // Step 1: Map the spatial coordinates of the 10 handles
                                var pts = [];
                                for (var i = 1; i <= 10; i++) {
                                    var val = root.eqData["b" + i] !== undefined ? Number(root.eqData["b" + i]) : 0;
                                    var norm = 1.0 - ((val + 12) / 24);
                                    
                                    // Py uses margins rough mapping to the handles visible track
                                    var py = root.s(10) + norm * (height - root.s(35)); 
                                    var px = (i - 0.5) * (width / 10);
                                    pts.push({ x: px, y: py });
                                }

                                // Step 2: Draw the multi-wave arcing structure
                                // Strand 0: Slow erratic mauve glow/wave
                                // Strand 1: Complex pink glow
                                // Strand 2: Crackling secondary core
                                // Strand 3: Hot white center core
                                for (var s = 0; s < 4; s++) { 
                                    ctx.beginPath();
                                    ctx.moveTo(pts[0].x, pts[0].y);

                                    for (var i = 0; i < pts.length - 1; i++) {
                                        if (i > maxIdx) break; // Stop drawing ahead of current progress

                                        var p1 = pts[i];
                                        var p2 = pts[i+1];

                                        var fraction = 1.0;
                                        if (maxIdx < i + 1) {
                                            fraction = maxIdx - i;
                                        }

                                        // Subdivision steps create the crackle noise
                                        var steps = s === 3 ? 6 : 8; // Ultra smooth subdivision, s=3 core has less subdiv for straighter look
                                        for (var j = 1; j <= steps; j++) {
                                            var t = j / steps;
                                            if (t > fraction) t = fraction;

                                            var cx = p1.x + (p2.x - p1.x) * t;
                                            var cy = p1.y + (p2.y - p1.y) * t;

                                            // Wave calculations: create distinct arcs and noise branching
                                            var envelope = Math.sin(t * Math.PI);

                                            // s=3 core noise (straightest) to s=0 outer glow noise (most waves)
                                            var noiseAmpX = s === 3 ? 1.0 : (4 - s) * 4; 
                                            var noiseAmpY = s === 3 ? 1.0 : (4 - s) * 5; 
                                            
                                            // Combine multiple frequencies for complex branching/crackle appearance
                                            // Glow strands (0, 1) also get a sweeping sine wave applied to create distinct separating waves
                                            var sepWaveX = (s < 2) ? Math.sin(time * 3 + i + j + s) * root.s(10) * envelope : 0;
                                            var sepWaveY = (s < 2) ? Math.cos(time * 2.5 + i - j - s) * root.s(15) * envelope : 0;

                                            // Primary erratic crackle noise using high frequency combined sine/cos
                                            var noiseX = Math.sin(time * (10+s) + i + j) * Math.cos(time * 8 - i + j) * noiseAmpX * envelope * (1 - root.eqLightningFade);
                                            var noiseY = Math.cos(time * (9-s) + i - j) * Math.sin(time * 7 + i - j) * noiseAmpY * envelope * (1 - root.eqLightningFade);

                                            ctx.lineTo(cx + sepWaveX + noiseX, cy + sepWaveY + noiseY);

                                            if (t === fraction) break;
                                        }
                                    }

                                    // Step 3: Theme and render each distinct strand
                                    if (s === 0) { // Massive Sweeping Outer Glow (Mauve)
                                        ctx.lineWidth = root.s(20);
                                        ctx.strokeStyle = root.mauve;
                                        ctx.globalAlpha = 0.2;
                                    } else if (s === 1) { // Medium Sweeping Wave (Pink)
                                        ctx.lineWidth = root.s(8);
                                        ctx.strokeStyle = root.pink;
                                        ctx.globalAlpha = 0.45;
                                    } else if (s === 2) { // Tight erratic core (Lavender)
                                        ctx.lineWidth = root.s(3.5);
                                        ctx.strokeStyle = root.lavender;
                                        ctx.globalAlpha = 0.85;
                                    } else if (s === 3) { // Pure white straight hot core - heavily transparent
                                        ctx.lineWidth = root.s(1.0);
                                        ctx.strokeStyle = "#ffffff";
                                        ctx.globalAlpha = 0.1;
                                    }

                                    ctx.stroke();
                                }
                            }
                        }
                    }

                    // Presets Grid
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: root.s(8)
                        
                        opacity: root.introPresets
                        transform: Translate { y: root.s(20) * (1 - root.introPresets) }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: root.s(10)
                            Repeater {
                                model: ["Flat", "Bass", "Treble", "Vocal"]
                                delegate: PresetButton { name: modelData }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: root.s(10)
                            Repeater {
                                model: ["Pop", "Rock", "Jazz", "Classic"]
                                delegate: PresetButton { name: modelData }
                            }
                        }
                    }

                    // ==========================================
                    // MY PRESETS — user-saved custom 10-band snapshots
                    // ==========================================
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: root.s(8)
                        spacing: root.s(8)

                        opacity: root.introPresets
                        transform: Translate { y: root.s(20) * (1 - root.introPresets) }

                        Text { text: "My Presets"; color: root.subtext0; font.family: "JetBrains Mono"; font.pixelSize: root.s(13); font.bold: true }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: root.s(10)

                            TextField {
                                id: eqPresetNameField
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(30)
                                placeholderText: "Save current EQ as..."
                                color: root.text
                                placeholderTextColor: root.overlay1
                                font.family: "JetBrains Mono"
                                font.pixelSize: root.s(12)
                                background: Rectangle { color: root.surface0; radius: root.s(6) }
                                onAccepted: {
                                    root.saveEqUserPreset(text);
                                    text = "";
                                }
                            }
                            Rectangle {
                                Layout.preferredHeight: root.s(30)
                                Layout.preferredWidth: root.s(60)
                                radius: root.s(8)
                                color: root.mauve
                                Text { anchors.centerIn: parent; text: "Save"; color: root.base; font.family: "JetBrains Mono"; font.pixelSize: root.s(12); font.bold: true }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.saveEqUserPreset(eqPresetNameField.text);
                                        eqPresetNameField.text = "";
                                    }
                                }
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: root.s(8)
                            visible: root.eqUserPresets.length > 0

                            Repeater {
                                model: root.eqUserPresets
                                delegate: Rectangle {
                                    id: eqChipDelegate
                                    height: root.s(32)
                                    width: eqChipRow.width + root.s(24)
                                    radius: height / 2

                                    property bool isActive: root.eqData.preset === modelData.name

                                    color: isActive ? root.mauve : (chipMa.containsMouse ? root.surface2 : root.surface1)
                                    scale: chipMa.pressed ? 0.94 : (chipMa.containsMouse && !isActive ? 1.04 : 1.0)
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

                                    layer.enabled: isActive
                                    layer.effect: MultiEffect {
                                        shadowEnabled: true; shadowColor: root.mauve; shadowOpacity: 0.5; shadowBlur: 0.5
                                    }

                                    readonly property var preset: modelData
                                    RowLayout {
                                        id: eqChipRow
                                        anchors.centerIn: parent
                                        spacing: root.s(8)
                                        Item {
                                            Layout.preferredWidth: root.s(10 * 3.5)
                                            Layout.preferredHeight: root.s(16)
                                            Row {
                                                anchors.bottom: parent.bottom
                                                spacing: root.s(1)
                                                Repeater {
                                                    model: 10
                                                    delegate: Rectangle {
                                                        anchors.bottom: parent.bottom
                                                        width: root.s(2.5)
                                                        radius: width / 2
                                                        readonly property real g: Number(eqChipDelegate.preset["b" + (index + 1)]) || 0
                                                        height: root.s(3) + (g + 12) / 24 * root.s(13) * (chipMa.containsMouse || eqChipDelegate.isActive ? 1 : 0.8)
                                                        color: eqChipDelegate.isActive ? root.base : root.accentColor
                                                        opacity: eqChipDelegate.isActive ? 0.8 : 0.75
                                                        Behavior on height { NumberAnimation { duration: 260 + index * 25; easing.type: Easing.OutBack } }
                                                    }
                                                }
                                            }
                                        }
                                        Text {
                                            text: modelData.name
                                            color: eqChipDelegate.isActive ? root.base : root.subtext0
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: root.s(11)
                                            font.bold: true
                                        }
                                        Text {
                                            text: "×"
                                            color: eqChipDelegate.isActive ? root.base : root.overlay1
                                            font.pixelSize: root.s(13)
                                            font.bold: true
                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: root.s(-4)
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.deleteEqUserPreset(modelData.name)
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: chipMa
                                        anchors.fill: parent
                                        z: -1
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.applyEqUserPreset(modelData)
                                    }
                                }
                            }
                        }
                    }
                }

            }
            }
        }
    }

    // --- HELPER COMPONENT FOR PRESETS ---
    component PresetButton : Rectangle {
        property string name: ""
        Layout.fillWidth: true
        Layout.preferredHeight: root.s(32)
        radius: root.s(8)
        
        property bool isActivePreset: root.eqData && root.eqData.preset === name
        property bool isHovered: hoverMa.containsMouse

        border.width: isActivePreset ? root.s(1.5) : 0
        border.color: root.mauve
        color: isActivePreset ? root.mauve : (isHovered ? root.surface1 : "#BF1E1E2E")
        scale: hoverMa.pressed ? 0.94 : (isHovered && !isActivePreset ? 1.05 : (isActivePreset ? 1.02 : 1.0))

        Behavior on color { ColorAnimation { duration: 200 } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

        layer.enabled: isActivePreset
        layer.effect: MultiEffect {
            shadowEnabled: true; shadowColor: root.mauve; shadowOpacity: 0.5; shadowBlur: 0.6
        }

        Text {
            anchors.centerIn: parent
            text: parent.name
            color: parent.isActivePreset ? root.base : (parent.isHovered ? root.text : root.subtext0)
            font.family: "JetBrains Mono"
            font.pixelSize: root.s(12)
            font.bold: true
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        MouseArea {
            id: hoverMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.applyPresetOptimistically(parent.name)
        }
    }
}
