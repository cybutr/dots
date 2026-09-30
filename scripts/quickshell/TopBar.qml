//@ pragma UseQApplication
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import "claude"
import "rescards"

Variants {
    model: Quickshell.screens
    
    delegate: Component {
        PanelWindow {
            id: barWindow

            required property var modelData
            
            // Bind this specific bar instance to the dynamically assigned screen
            screen: modelData
            
            anchors {
                top: true
                left: true
                right: true
            }
            
            // --- Responsive Scaling Logic ---
            Scaler {
                id: scaler
                currentWidth: barWindow.width
            }

            property real baseScale: scaler.baseScale
            
            // Helper function mapped to the external scaler
            function s(val) { 
                return scaler.s(val); 
            }

            property int barHeight: s(48)

            // THICKER BAR, MINIMAL MARGINS (Scaled)
            // Window spans the full screen height — same trick Main.qml uses for its
            // click-outside-closes catcher — so that while the tray menu is open we
            // can briefly widen the input mask to fullscreen and catch a click
            // anywhere (not just inside our own small bar strip) to close it.
            // exclusiveZone still only reserves barHeight of screen space.
            height: trayMenuPopup.visible ? Screen.height : Math.min(Screen.height, s(640))
            margins { top: s(8); bottom: 0; left: s(4); right: s(4) }

            // exclusiveZone = height + top margin
            exclusiveZone: barHeight + s(4)
            color: "transparent"

            // Normally restrict hit-testing to the bar row plus the tray popup when
            // it's open — otherwise the whole transparent surface eats every click
            // underneath it. While the tray menu is open, widen to fullscreen so a
            // click anywhere outside the bar/popup (e.g. on a browser window) is
            // actually seen by us and can close the menu.
            mask: Region {
                item: barRow
                Region { item: trayMenuPopup.visible ? fullScreenCatcher : null }
                Region { item: claudeCard.visible && claudeTipState.hoverConfirmed ? claudeCard : null }
                Region { item: residentCard.visible ? residentCard : null }
                Region { item: mediaCard.visible && mediaBox.hoverConfirmed ? mediaCard : null }
                Region { item: wsCard.visible && wsGroupBox.hoverConfirmed ? wsCard : null }
                Region { item: acctTip.visible && acctBox.hoverConfirmed ? acctTip : null }
                Region { item: statsCard.visible && sysStatsPill.hoverConfirmed ? statsCard : null }
                Region { item: weatherTip.visible && weatherBox.hoverConfirmed ? weatherTip : null }
                Region { item: clockTip.visible && clockBox.hoverConfirmed ? clockTip : null }
                Region { item: volTip.visible && volWrap.hoverConfirmed ? volTip : null }
                Region { item: batTip.visible && batteryStatusPill.hoverConfirmed ? batTip : null }
                Region { item: wifiTip.visible && wifiWrap.hoverConfirmed ? wifiTip : null }
                Region { item: btTip.visible && btWrap.hoverConfirmed ? btTip : null }            }

            // Dynamic Matugen Palette
            MatugenColors {
                id: mocha
            }

            // --- State Variables ---
            
            // Desktop Chassis Detection
            property bool isDesktop: false
            property string ethStatus: "Ethernet"

            Process {
                id: chassisDetector
                running: true
                command: ["bash", "-c", "if ls /sys/class/power_supply/BAT* 1> /dev/null 2>&1; then echo 'laptop'; else echo 'desktop'; fi"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        barWindow.isDesktop = (this.text.trim() === "desktop");
                    }
                }
            }

            Process {
                id: ethStatusPoller
                running: barWindow.isDesktop
                command: ["bash", "-c", "nmcli -t -f TYPE,STATE dev | grep 'ethernet' | grep -q 'connected' && echo 'Connected' || echo 'Disconnected'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let status = this.text.trim();
                        if (status !== "") barWindow.ethStatus = status;
                    }
                }
            }
            Timer {
                interval: 3000; running: barWindow.isDesktop; repeat: true
                onTriggered: ethStatusPoller.running = true
            }

            // Triggers layout animations immediately to feel fast
            property bool isStartupReady: false
            Timer { interval: 10; running: true; onTriggered: barWindow.isStartupReady = true }
            
            // Prevents repeaters (Workspaces/Tray) from flickering on data updates
            property bool startupCascadeFinished: false
            Timer { interval: 1000; running: true; onTriggered: barWindow.startupCascadeFinished = true }
            
            // Data gating to prevent startup layout jumping
            property bool sysPollerLoaded: false
            property bool fastPollerLoaded: false
            
            // FIXED: Only wait for the instant data to load the UI. 
            // The slow network scripts will populate smoothly when they finish.
            property bool isDataReady: fastPollerLoaded
            // Failsafe: Force the layout to show after 600ms even if fast poller hangs
            Timer { interval: 600; running: true; onTriggered: barWindow.isDataReady = true }
            
            property string timeStr: ""
            property string fullDateStr: ""

            // Settings-driven: "Show Calendar Pill in Top Bar" toggle
            property bool showCalendarPill: true
            Process {
                id: calPillSettingReader
                command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            let parsed = JSON.parse(this.text || "{}");
                            if (parsed.showCalendarPill !== undefined) barWindow.showCalendarPill = parsed.showCalendarPill;
                        } catch (e) {}
                    }
                }
            }
            Process {
                id: calPillSettingWatcher
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "while [ ! -f ~/.config/hypr/settings.json ]; do sleep 1; done; exec inotifywait -qq -e modify,close_write ~/.config/hypr/settings.json"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        calPillSettingReader.running = false; calPillSettingReader.running = true;
                        calPillSettingWatcher.running = false; calPillSettingWatcher.running = true;
                    }
                }
            }
            property int typeInIndex: 0
            property string dateStr: fullDateStr.substring(0, typeInIndex)

            property string weatherIcon: ""
            property string weatherTemp: "--°"
            property string weatherHex: mocha.yellow

            // Hold-action progress (emergency-kill etc.) — mirrored from the
            // quickshell-independent bash timer in scripts/quickshell/holdactions/.
            // Purely cosmetic: the timer/executor works regardless of whether
            // this ever gets read.
            property real holdActionProgress: 0.0
            property string holdActionGlow: mocha.red
            property bool holdActionActive: false
            
            property string wifiStatus: "Off"
            property string wifiIcon: "󰤮"
            property string wifiSsid: ""
            
            property string btStatus: "Off"
            property string btIcon: "󰂲"
            property string btDevice: ""
            
            property string volPercent: "0%"
            property string volIcon: "󰕾"
            property bool isMuted: false
            
            property string batPercent: "100%"
            property string batIcon: "󰁹"
            property string batStatus: "Unknown"
            
            property string kbLayout: "us"
            
            ListModel { id: workspacesModel }
            
            property var musicData: { "status": "Stopped", "title": "", "artUrl": "", "timeStr": "" }
            property var currentEventData: ({"active": false, "events": []})
            property int pillIndex: 0
            property bool pillManual: false
            property var pillEvent: {
                let evs = barWindow.currentEventData && barWindow.currentEventData.events
                if (!evs || evs.length === 0) return null
                return evs[Math.min(barWindow.pillIndex, evs.length - 1)]
            }

            Process {
                id: eventReader
                command: ["bash", "-c", "cat /tmp/qs_current_event.json 2>/dev/null || echo '{\"active\":false,\"events\":[]}'"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            let d = JSON.parse(this.text.trim())
                            barWindow.currentEventData = d
                            barWindow.pillIndex = 0
                        } catch(e) {}
                    }
                }
            }
            Process {
                id: eventWatcher
                running: true
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "touch /tmp/qs_current_event.json; exec inotifywait -qq -e close_write /tmp/qs_current_event.json"]
                onExited: { eventReader.running = true; running = true }
            }
            Timer {
                id: pillCycleTimer
                interval: 5000
                repeat: true
                running: {
                    let evs = barWindow.currentEventData && barWindow.currentEventData.events
                    return evs && evs.length > 1 && !barWindow.pillManual
                }
                onTriggered: {
                    let evs = barWindow.currentEventData.events
                    barWindow.pillIndex = (barWindow.pillIndex + 1) % evs.length
                }
            }
            Timer {
                id: pillManualTimer
                interval: 8000
                onTriggered: barWindow.pillManual = false
            }

            // Derived properties for UI logic
            property bool isMediaActive: barWindow.musicData.status !== "Stopped" && barWindow.musicData.title !== ""
            property bool isWifiOn: barWindow.wifiStatus.toLowerCase() === "enabled" || barWindow.wifiStatus.toLowerCase() === "on"
            property bool isBtOn: barWindow.btStatus.toLowerCase() === "enabled" || barWindow.btStatus.toLowerCase() === "on"
            
            property bool isSoundActive: !barWindow.isMuted && parseInt(barWindow.volPercent) > 0
            property int batCap: parseInt(barWindow.batPercent) || 0
            property bool isCharging: barWindow.batStatus === "Charging" || barWindow.batStatus === "Full"
            property color batDynamicColor: {
                if (isCharging) return mocha.green;
                if (batCap >= 70) return mocha.blue;
                if (batCap >= 30) return mocha.yellow;
                return mocha.red;
            }

            // ==========================================
            // DATA FETCHING 
            // ==========================================

            // Workspaces --------------------------------
            // 1. The continuous background daemon
            Process {
                id: wsDaemon
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "~/.config/hypr/scripts/quickshell/workspaces.sh"]
                running: true
            }

            // 2. The lightweight reader
            Process {
                id: wsReader
                command: ["cat", "/tmp/qs_workspaces.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try { 
                                let newData = JSON.parse(txt);
                                if (workspacesModel.count !== newData.length) {
                                    workspacesModel.clear();
                                    for (let i = 0; i < newData.length; i++) {
                                        // Stored as a JSON STRING, not a raw array — a ListModel
                                        // role holding a JS array gets silently auto-converted
                                        // into a nested QQmlListModel object instead of staying a
                                        // plain array, so .length/indexing on it always came back
                                        // wrong (iconCount stuck at 0 no matter what). Round-trip
                                        // through JSON to keep it a plain string role.
                                        workspacesModel.append({ "wsId": newData[i].id.toString(), "wsState": newData[i].state, "wsClasses": JSON.stringify(newData[i].classes || []), "wsWins": JSON.stringify(newData[i].wins || []) });
                                    }
                                } else {
                                    for (let i = 0; i < newData.length; i++) {
                                        if (workspacesModel.get(i).wsState !== newData[i].state) {
                                            workspacesModel.setProperty(i, "wsState", newData[i].state);
                                        }
                                        if (workspacesModel.get(i).wsId !== newData[i].id.toString()) {
                                            workspacesModel.setProperty(i, "wsId", newData[i].id.toString());
                                        }
                                        let newClassesStr = JSON.stringify(newData[i].classes || []);
                                        if (workspacesModel.get(i).wsClasses !== newClassesStr) {
                                            workspacesModel.setProperty(i, "wsClasses", newClassesStr);
                                        }
                                        let newWinsStr = JSON.stringify(newData[i].wins || []);
                                        if (workspacesModel.get(i).wsWins !== newWinsStr) {
                                            workspacesModel.setProperty(i, "wsWins", newWinsStr);
                                        }
                                    }
                                }
                                wsGroupBox.refreshShown()
                            } catch(e) {}
                        }
                    }
                }
            }

            // 3. ZERO-CPU Event Watcher (Replaces the brutal 50ms timer)
            Process {
                id: wsWatcher
                running: true
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "exec inotifywait -qq -e close_write,modify /tmp/qs_workspaces.json"]
                onExited: {
                    wsReader.running = true;
                    running = true;
                }
            }

            // Music -------------------------------------
            // 1. Direct executor for heavy DBus fetching and downloading art (only runs on actual song changes)
            Process {
                id: musicForceRefresh
                running: true
                property bool refreshPending: false
                command: ["bash", "-c", "bash ~/.config/hypr/scripts/quickshell/music/music_info.sh | tee /tmp/music_info.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try { barWindow.musicData = JSON.parse(txt); } catch(e) {}
                        }
                    }
                }
                onExited: {
                    if (musicForceRefresh.refreshPending) {
                        musicForceRefresh.refreshPending = false;
                        musicForceRefresh.running = true;
                    }
                }
            }

            // Guarantees a refresh always eventually runs, even if one is already
            // mid-flight (setting running=true while already running is a no-op,
            // which used to silently drop the DBus-signal-triggered refresh that
            // arrives right after a next/prev/play click and fixes stale track data)
            function requestMusicRefresh() {
                if (musicForceRefresh.running) {
                    musicForceRefresh.refreshPending = true;
                } else {
                    musicForceRefresh.running = true;
                }
            }

            // 2. Lightweight JS Timer ONLY for clock progress (Zero CPU/Zero DBus cost)
            // It parses the current time string and increments it locally while playing.
            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: {
                    if (!barWindow.musicData || barWindow.musicData.status !== "Playing") return;
                    if (!barWindow.musicData.timeStr || barWindow.musicData.timeStr === "") return;

                    let parts = barWindow.musicData.timeStr.split(" / ");
                    if (parts.length !== 2) return;

                    let posParts = parts[0].split(":").map(Number);
                    let lenParts = parts[1].split(":").map(Number);

                    // Handle mm:ss or hh:mm:ss formats automatically
                    let posSecs = (posParts.length === 3) 
                        ? (posParts[0] * 3600 + posParts[1] * 60 + posParts[2]) 
                        : (posParts[0] * 60 + posParts[1]);

                    let lenSecs = (lenParts.length === 3) 
                        ? (lenParts[0] * 3600 + lenParts[1] * 60 + lenParts[2]) 
                        : (lenParts[0] * 60 + lenParts[1]);

                    if (isNaN(posSecs) || isNaN(lenSecs)) return;

                    posSecs++;
                    if (posSecs > lenSecs) posSecs = lenSecs;

                    let newPosStr = "";
                    if (posParts.length === 3) {
                        let h = Math.floor(posSecs / 3600);
                        let m = Math.floor((posSecs % 3600) / 60);
                        let s = posSecs % 60;
                        newPosStr = h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
                    } else {
                        let m = Math.floor(posSecs / 60);
                        let s = posSecs % 60;
                        newPosStr = (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
                    }

                    // Reassign to trigger UI bindings
                    let newData = Object.assign({}, barWindow.musicData);
                    newData.timeStr = newPosStr + " / " + parts[1];
                    // Also update absolute strings to sync smoothly
                    newData.positionStr = newPosStr;
                    if (lenSecs > 0) newData.percent = (posSecs / lenSecs) * 100;
                    
                    barWindow.musicData = newData;
                }
            }

            // 3. INSTANT Zero-CPU Event Watcher for MPRIS (Play/Pause/Skip/Seek)
            // Keeps a single long-lived dbus-monitor connection open and refreshes
            // on every matching line instead of respawning per-event. The old
            // "grep -m 1 ... || sleep 2" design killed dbus-monitor after each
            // single event and paid a real (tens-of-ms) reconnect cost to spin
            // up a fresh dbus-monitor + re-register match rules before the next
            // signal could be caught — any PlaybackStatus/Seeked signal landing
            // in that reconnect gap was silently dropped by the bus (no queuing
            // for a client that isn't connected yet), which under normal bursty
            // usage (quick pause/unpause, skip, seek) meant most transitions
            // never triggered a refresh and the icon went stale until the next
            // event happened to land outside the gap.
            Process {
                id: mprisWatcher
                running: true
                // dbus-monitor block-buffers its stdout once it's piped (not a tty),
                // so a signal could sit unflushed for a long time before grep/SplitParser
                // ever saw it — exactly the "sometimes ages late" symptom. stdbuf -oL
                // forces line-buffering at the source so every signal is flushed instantly.
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "stdbuf -oL dbus-monitor --session \"type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.mpris.MediaPlayer2.Player'\" \"type='signal',interface='org.mpris.MediaPlayer2.Player',member='Seeked'\" 2>/dev/null | grep --line-buffered 'member='"]
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: (line) => {
                        barWindow.requestMusicRefresh()
                        if ((mediaBox.hoverConfirmed || volWrap.hoverConfirmed) && !mediaVolMa.pressed) { mediaVolReader.running = false; mediaVolReader.running = true }
                    }
                }
                // dbus-monitor should run forever; only exits if the session bus
                // connection itself dies (bus restart, logout/login) — respawn it.
                onExited: running = true
            }
            Process {
                id: mprisStatusFollower
                running: true
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "exec playerctl --player=spotify --follow status 2>/dev/null"]
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: (line) => {
                        let st = line.trim()
                        if (st !== "Playing" && st !== "Paused" && st !== "Stopped") return
                        if (barWindow.musicData && barWindow.musicData.status !== st) {
                            let d = Object.assign({}, barWindow.musicData)
                            d.status = st
                            barWindow.musicData = d
                        }
                        barWindow.requestMusicRefresh()
                    }
                }
                onExited: running = true
            }
            // 4. Safety-net poll — refreshes every few seconds regardless of the
            // DBus watcher above, so a missed/late signal (bus restart gap,
            // player emitting a signal type we don't filter for) self-heals
            // within a few seconds instead of staying stale indefinitely.
            Timer {
                interval: 2000
                running: barWindow.isMediaActive
                repeat: true
                onTriggered: barWindow.requestMusicRefresh()
            }
            // Unified System Info ------------------------
            Process {
                id: sysPoller
                running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/sys_info.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try {
                                let data = JSON.parse(txt);
                                
                                // Targeted Updates
                                if (barWindow.wifiStatus !== data.wifi.status) barWindow.wifiStatus = data.wifi.status;
                                if (barWindow.wifiIcon !== data.wifi.icon) barWindow.wifiIcon = data.wifi.icon;
                                if (barWindow.wifiSsid !== data.wifi.ssid) barWindow.wifiSsid = data.wifi.ssid;

                                if (barWindow.btStatus !== data.bt.status) barWindow.btStatus = data.bt.status;
                                if (barWindow.btIcon !== data.bt.icon) barWindow.btIcon = data.bt.icon;
                                if (barWindow.btDevice !== data.bt.connected) barWindow.btDevice = data.bt.connected;

                                let newVol = data.audio.volume.toString() + "%";
                                if (barWindow.volPercent !== newVol) barWindow.volPercent = newVol;
                                if (barWindow.volIcon !== data.audio.icon) barWindow.volIcon = data.audio.icon;
                                
                                let newMuted = (data.audio.is_muted === "true");
                                if (barWindow.isMuted !== newMuted) barWindow.isMuted = newMuted;

                                let newBat = data.battery.percent.toString() + "%";
                                if (barWindow.batPercent !== newBat) barWindow.batPercent = newBat;
                                if (barWindow.batIcon !== data.battery.icon) barWindow.batIcon = data.battery.icon;
                                if (barWindow.batStatus !== data.battery.status) barWindow.batStatus = data.battery.status;

                                if (barWindow.kbLayout !== data.keyboard.layout) barWindow.kbLayout = data.keyboard.layout;

                                barWindow.sysPollerLoaded = true;
                                barWindow.fastPollerLoaded = true;
                            } catch(e) {}
                        }
                        
                        // THE FIX: Removed `musicForceRefresh.running = true;` from here
                        // This completely severs the DBus spam loop during music playback.
                        sysWaiter.running = true;
                    }
                }
            }
            
            Process {
                id: sysWaiter
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "~/.config/hypr/scripts/quickshell/sys_waiter.sh"]
                // Strictly use onExited. Quickshell will no longer hook into stdout, preventing pipe deadlocks.
                onExited: sysPoller.running = true 
            }            // Weather remains a slow poll since it fetches from web
            Process {
                id: weatherPoller
                command: ["bash", "-c", `
                    echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-icon)"
                    echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-temp)"
                    echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-hex)"
                `]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let lines = this.text.trim().split("\n");
                        if (lines.length >= 3) {
                            barWindow.weatherIcon = lines[0];
                            barWindow.weatherTemp = lines[1];
                            barWindow.weatherHex = lines[2] || mocha.yellow;
                        }
                    }
                }
            }
            Timer { interval: 150000; running: true; repeat: true; triggeredOnStart: true; onTriggered: weatherPoller.running = true }

            // Hold-action state — best-effort read of the file the bash timer
            // (scripts/quickshell/holdactions/holdaction_run.sh) writes to. If
            // quickshell is dead/hung this simply never updates; the underlying
            // kill still fires from the bash side regardless.
            Process {
                id: holdActionReader
                command: ["bash", "-c", "cat /tmp/qs_holdaction_state.json 2>/dev/null || echo '{}'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            let d = JSON.parse(this.text.trim());
                            if (!d.phase) return;
                            if (d.phase === "start" || d.phase === "progress") {
                                barWindow.holdActionActive = true;
                                barWindow.holdActionProgress = d.progress || 0;
                                barWindow.holdActionGlow = d.glowHex || mocha.red;
                            } else {
                                barWindow.holdActionActive = false;
                                barWindow.holdActionProgress = 0;
                            }
                        } catch (e) {}
                    }
                }
            }
            Process {
                id: holdActionWatcher
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "f=/tmp/qs_holdaction_state.json; touch \"$f\"; exec inotifywait -m -q -e close_write \"$f\""]
                running: true
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: {
                        holdActionReader.running = false;
                        holdActionReader.running = true;
                    }
                }
            }

            // CPU sparkline sampler — cpu_usage.sh is a long-lived /proc/stat
            // delta loop (2s cadence) so this is a zero-cost SplitParser read,
            // not a spawn-per-poll script.
            property var cpuHistory: []
            property int cpuPct: 0

            // Quickshell's OWN CPU cost — separate from the user's app CPU
            // above. Fed by scripts/perf_watch.py (samples every ~10s across
            // all "quickshell -p ..." processes), written to /tmp/qs_perf.json
            // and picked up here via the same inotifywait+cat idiom used
            // everywhere else in this file, so the bar can flag itself
            // running hot instead of only ever pointing at other apps.
            property real qsCpuPct: 0
            property var qsCpuHistory: []
            property int qsOrphans: 0
            Process {
                id: qsPerfReader
                command: ["bash", "-c", "cat /tmp/qs_perf.json 2>/dev/null || echo '{}'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            let d = JSON.parse(this.text.trim())
                            if (d.cpu_pct !== undefined) barWindow.qsCpuPct = d.cpu_pct
                            if (d.hist) barWindow.qsCpuHistory = d.hist
                            if (d.orphans !== undefined) barWindow.qsOrphans = d.orphans
                        } catch (e) {}
                    }
                }
            }
            Process {
                id: qsPerfWatcher
                running: true
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "touch /tmp/qs_perf.json; exec inotifywait -qq -e close_write /tmp/qs_perf.json"]
                onExited: { qsPerfReader.running = false; qsPerfReader.running = true; running = true }
            }

            // Easter egg: a rare "sigh" — CPU briefly spikes then drops back
            // to idle. Purely decorative pulse on cpuPill, no functional
            // meaning, very subtle, never obtrusive.
            property bool cpuSighing: false
            Timer { id: cpuSighTimer; interval: 1700; onTriggered: barWindow.cpuSighing = false }

            Process {
                id: cpuPoller
                running: true
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "~/.config/hypr/scripts/quickshell/cpu_usage.sh"]
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: (line) => {
                        let v = parseInt(line)
                        if (isNaN(v)) return
                        let hist = barWindow.cpuHistory.slice()
                        let recentMax = 0
                        for (let i = Math.max(0, hist.length - 4); i < hist.length; i++) recentMax = Math.max(recentMax, hist[i])
                        if (barWindow.topBarFlourishesEnabled && barWindow.topBarFlourishCpuCalmEnabled && !barWindow.cpuSighing && recentMax >= 65 && (recentMax - v) >= 40
                                && (Date.now() - barWindow.lastCpuSighTime) > barWindow.flourishCooldownMs) {
                            barWindow.lastCpuSighTime = Date.now()
                            barWindow.cpuSighing = true
                            cpuSighTimer.restart()
                        }
                        barWindow.cpuPct = v
                        hist.push(v)
                        if (hist.length > 24) hist.shift()
                        barWindow.cpuHistory = hist
                    }
                }
            }

            // GPU sparkline sampler — gpu_usage.sh mirrors cpu_usage.sh's
            // long-lived loop shape (nvidia-smi or amd gpu_busy_percent, 2s
            // cadence). No value ever arriving (no GPU detected) keeps
            // gpuAvailable false so the pill just stays hidden.
            property var gpuHistory: []
            property int gpuPct: 0
            property int gpuTemp: 0

            // ============================================================
            // HOVER CARD TUNABLES — one group per pill (weather/volume/
            // battery/wifi/bluetooth), all together here instead of
            // scattered through the file. Each card now matches its source
            // pill's own width/x/color exactly (extends its bottom edge
            // downward, same shape/shade, rather than a separately-sized
            // floating card) — with matching width there's no spare room to
            // wiggle side-to-side, so the old cursor-follow nudge (and its
            // per-card Cap/Gain knobs) is gone. Only knob left per card:
            //   ...Overlap    — px the card tucks up into the pill's bottom
            //                   edge (negative = gap instead)
            //   ...GrowScale  — starting scale before it pops to 1.0
            // ============================================================
            property real weatherHoverOverlap: s(1)
            property real weatherHoverGrowScale: 0.9

            property real volHoverOverlap: s(1)
            property real volHoverGrowScale: 0.9

            property real batHoverOverlap: s(1)
            property real batHoverGrowScale: 0.9

            property real wifiHoverOverlap: s(1)
            property real wifiHoverGrowScale: 0.9

            property real btHoverOverlap: s(1)
            property real btHoverGrowScale: 0.9
            property bool gpuAvailable: false
            Process {
                id: gpuPoller
                running: barWindow.topBarShowGpu
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "~/.config/hypr/scripts/quickshell/gpu_usage.sh"]
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: (line) => {
                        let parts = line.split(",")
                        let v = parseInt(parts[0])
                        if (isNaN(v)) return
                        barWindow.gpuAvailable = true
                        barWindow.gpuPct = v
                        if (parts.length > 1) barWindow.gpuTemp = parseInt(parts[1]) || 0
                        let hist = barWindow.gpuHistory.slice()
                        hist.push(v)
                        if (hist.length > 24) hist.shift()
                        barWindow.gpuHistory = hist
                    }
                }
            }

            // Net rate sampler — net_usage.sh mirrors cpu_usage.sh's
            // long-lived delta-loop shape, reading /sys/class/net stats.
            property real netDownBps: 0
            property real netUpBps: 0
            Process {
                id: netPoller
                running: barWindow.topBarShowNet
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "~/.config/hypr/scripts/quickshell/net_usage.sh"]
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: (line) => {
                        try {
                            let d = JSON.parse(line)
                            barWindow.netDownBps = d.down || 0
                            barWindow.netUpBps = d.up || 0
                        } catch (e) {}
                    }
                }
            }
            function fmtNetRate(bps) {
                if (bps >= 1048576) return (bps / 1048576).toFixed(1) + "M"
                if (bps >= 1024) return (bps / 1024).toFixed(0) + "K"
                return bps.toFixed(0) + "B"
            }

            // Uptime — barely changes, one-shot Process on a slow Timer
            // rather than a persistent loop (unlike cpu/gpu/net above).
            property string uptimeStr: ""
            onUptimeStrChanged: barWindow.checkUptimeMilestone()

            // ---- Idle/achievement flourishes (topBarFlourishesEnabled umbrella) ----
            // Rare, one-shot celebratory bursts on genuine milestones — reuses the
            // cpuSighing/sparkDot visual idiom (search sparkDot) for all three so they
            // share one visual language. Each has its own sub-toggle plus the shared
            // umbrella. Test trigger: `echo uptime|battery|cpu > /tmp/qs_topbar_test_flourish`
            // force-fires the matching one immediately, ungated by the toggles, so it can
            // be previewed before deciding to enable it — see testFlourishReader below.
            property int lastCelebratedUptimeDays: -1
            property bool uptimeFlourishActive: false
            property bool batteryFlourishFired: false
            property bool batteryFlourishActive: false
            // Minimum real gap between fires of the SAME flourish, on top of the
            // 3.5s visual timer above — without this, a flappy trigger condition
            // (cpu staying spiky, battery reading hovering right at 100%) can
            // restart the burst the instant the previous one ends, which reads
            // as "never goes away" even though each individual burst is bounded.
            property real lastCpuSighTime: 0
            property real lastUptimeFlourishTime: 0
            property real lastBatteryFlourishTime: 0
            readonly property int flourishCooldownMs: 60000
            // 2000ms was barely longer than the sparkle animation's own ~1.6s run
            // time, so by the time anyone actually looked it had already finished —
            // reads as "did nothing" even when it fired correctly. 3.5s gives a real
            // window to actually notice it, especially when triggered via the test
            // file rather than a genuine milestone you're staring at already.
            Timer { id: uptimeFlourishTimer; interval: 3500; onTriggered: barWindow.uptimeFlourishActive = false }
            Timer { id: batteryFlourishTimer; interval: 3500; onTriggered: barWindow.batteryFlourishActive = false }

            function fireUptimeFlourish() {
                barWindow.lastUptimeFlourishTime = Date.now()
                barWindow.uptimeFlourishActive = true
                uptimeFlourishTimer.restart()
            }
            function fireBatteryFlourish() {
                barWindow.lastBatteryFlourishTime = Date.now()
                barWindow.batteryFlourishActive = true
                batteryFlourishTimer.restart()
            }
            // Detects a day-boundary crossing in uptimeStr (e.g. "1d 2h 3m") that
            // hasn't already been celebrated this boot. The first read after launch
            // just records the current day count without firing, so restarting the
            // bar mid-uptime doesn't immediately celebrate an already-known day.
            function checkUptimeMilestone() {
                let m = barWindow.uptimeStr.match(/(\d+)d/)
                let days = m ? parseInt(m[1]) : 0
                if (days <= 0) return
                if (barWindow.lastCelebratedUptimeDays === -1) {
                    barWindow.lastCelebratedUptimeDays = days
                    return
                }
                if (days > barWindow.lastCelebratedUptimeDays) {
                    barWindow.lastCelebratedUptimeDays = days
                    if (barWindow.topBarFlourishesEnabled && barWindow.topBarFlourishUptimeEnabled
                            && (Date.now() - barWindow.lastUptimeFlourishTime) > barWindow.flourishCooldownMs) barWindow.fireUptimeFlourish()
                }
            }
            // batPercent defaults to the "100%" placeholder before the first real
            // sys_info poll lands, so batCap READS as 100 at cold start regardless
            // of true battery level — firing on that would celebrate every single
            // bar restart. Skip the very first onBatCapChanged like
            // lastCelebratedUptimeDays does for uptime, only acting once a real
            // reading has actually come in.
            property bool batteryFlourishSawRealReading: false
            onBatCapChanged: {
                barWindow.fireBatFillBurst()
                if (!barWindow.batteryFlourishSawRealReading) {
                    barWindow.batteryFlourishSawRealReading = true
                    barWindow.batteryFlourishFired = barWindow.batCap === 100
                    return
                }
                if (barWindow.batCap === 100) {
                    if (!barWindow.batteryFlourishFired) {
                        barWindow.batteryFlourishFired = true
                        if (barWindow.topBarFlourishesEnabled && barWindow.topBarFlourishBatteryEnabled
                                && (Date.now() - barWindow.lastBatteryFlourishTime) > barWindow.flourishCooldownMs) barWindow.fireBatteryFlourish()
                    }
                } else {
                    barWindow.batteryFlourishFired = false
                }
            }

            // Hidden debug affordance for previewing all 3 flourishes on demand:
            //   echo uptime  > /tmp/qs_topbar_test_flourish
            //   echo battery > /tmp/qs_topbar_test_flourish
            //   echo cpu     > /tmp/qs_topbar_test_flourish
            // Unrecognized text is silently ignored. Deliberately NOT gated behind the
            // topBarFlourish*Enabled toggles, so a flourish can be previewed before
            // deciding whether to enable it.
            Process {
                id: testFlourishWatcher
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "touch /tmp/qs_topbar_test_flourish; exec inotifywait -qq -e modify,close_write /tmp/qs_topbar_test_flourish"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        testFlourishReader.running = false; testFlourishReader.running = true;
                        testFlourishWatcher.running = false; testFlourishWatcher.running = true;
                    }
                }
            }
            Process {
                id: testFlourishReader
                command: ["bash", "-c", "cat /tmp/qs_topbar_test_flourish 2>/dev/null"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let cmd = (this.text || "").trim()
                        if (cmd === "uptime") barWindow.fireUptimeFlourish()
                        else if (cmd === "battery") barWindow.fireBatteryFlourish()
                        else if (cmd === "cpu") { barWindow.cpuSighing = true; cpuSighTimer.restart() }
                        else if (cmd === "batteryfill") barWindow.fireBatFillBurst()
                        else if (cmd === "volumefill") barWindow.fireVolFillFlash()
                        else if (cmd === "skyfx") barWindow.fireFx("sky", 8000)
                        else if (cmd === "wififx") barWindow.fireFx("wifi", 8000)
                        else if (cmd === "btfx") { barWindow.fireFx("bt", 8000); barWindow.btPulseBurst++ }
                        else if (cmd === "cpufx") barWindow.fireFx("cpu", 8000)
                        else if (cmd === "netfx") barWindow.fireFx("net", 8000)
                        else if (cmd === "uptimefx") barWindow.fireFx("uptime", 8000)
                        else if (cmd === "wsfx") barWindow.fireFx("ws", 8000)
                        else if (cmd === "claudefx") barWindow.fireFx("claude", 8000)
                    }
                }
            }

            Timer {
                interval: 30000; running: barWindow.topBarShowUptime; repeat: true; triggeredOnStart: true
                onTriggered: uptimePoller.running = true
            }
            Process {
                id: uptimePoller
                // `uptime -p` drops any unit that's exactly 0 (e.g. "up 1 day, 23
                // hours" with no minutes clause at all right when minutes rolls to
                // :00) — the component COUNT changing at random made the pill look
                // broken/inconsistent (and would've jittered its width, the same
                // class of bug already fixed for cpu/gpu/net). Computing straight
                // from /proc/uptime instead so d/h/m are always all three present,
                // zero or not.
                command: ["bash", "-c",
                    "s=$(cut -d. -f1 /proc/uptime); d=$((s/86400)); h=$((s%86400/3600)); m=$((s%3600/60)); " +
                    "if [ \"$d\" -gt 0 ]; then printf '%dd, %dh, %dm' \"$d\" \"$h\" \"$m\"; " +
                    "else printf '%dh, %dm' \"$h\" \"$m\"; fi"]
                stdout: StdioCollector {
                    onStreamFinished: barWindow.uptimeStr = this.text.trim()
                }
            }

            // Weather condition category — derived from the icon glyph
            // codepoints emitted by weather.sh's get_icon() (mist/sunny/
            // clear-night/cloudy/rainy/storm/snow), used purely to pick an
            // ambient animation style for the weather icon.
            property string weatherCategory: {
                let i = barWindow.weatherIcon
                if (i === "󰖙") return "sunny"
                if (i === "󰖔") return "clear"
                if (i === "󰖐") return "cloudy"
                if (i === "󰖗") return "rainy"
                if (i === "󰙾") return "storm"
                if (i === "󰖘") return "snow"
                return "misc"
            }

            // Media-pill audio-reactive visualizer — reuses audio_level.py's
            // parec RMS sample (same approach as MusicPopup's audioLevel),
            // its own lightweight poll here since the bar is a separate
            // process from the popup and can't share its property. Polled
            // slower (1000ms) than the popup since the bar is always visible.
            property real mediaAudioLevel: 0
            Behavior on mediaAudioLevel { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
            // Real per-band spectrum for "fft" mode — audio_spectrum.py, 14
            // log-spaced bands matching the Repeater's bar count below.
            property var mediaSpectrumLevels: [0,0,0,0,0,0,0,0,0,0,0,0,0,0]
            // Single amplitude for non-per-bar visuals (the glow wash below) —
            // real spectrum average in "fft" mode, the RMS scalar in "pulse".
            // Lyric sync offset (seconds) — positive shifts the highlight
            // earlier/ahead of the estimated playback position, negative
            // shifts it later. Guide → Settings → Media & Audio.
            property real lyricsSyncOffsetSec: 1.0
            property real mediaVizAmplitude: barWindow.mediaVisualizerMode === "fft"
                ? barWindow.mediaSpectrumLevels.reduce((a, b) => a + b, 0) / barWindow.mediaSpectrumLevels.length
                : barWindow.mediaAudioLevel
            // "pulse" stays one-shot-per-poll (audio_level.py) — its visual
            // smoothness comes from the never-stopping phase animation below,
            // not from data rate, so this is fine as-is.
            Timer {
                id: mediaVizTimer
                interval: 900
                running: barWindow.mediaVisualizerEnabled && barWindow.isMediaActive && barWindow.musicData.status === "Playing" && barWindow.mediaVisualizerMode !== "fft"
                repeat: true
                triggeredOnStart: true
                onTriggered: if (!mediaAudioLevelProc.running) mediaAudioLevelProc.running = true
            }
            Process {
                id: mediaAudioLevelProc
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "$HOME/.config/hypr/scripts/quickshell/music/audio_level.py"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let v = parseFloat(this.text.trim())
                        if (!isNaN(v)) barWindow.mediaAudioLevel = Math.max(0, Math.min(1, v))
                    }
                }
            }
            // "fft" is a genuinely PERSISTENT stream, not poll-per-tick — a
            // one-shot-per-poll design was tried first and measured ~0.5-0.7s
            // wall time per invocation (almost all numpy import + interpreter
            // startup, not the ~0.12s capture itself), which put a hard floor
            // on update rate no timer tuning could fix and felt visibly
            // choppier than "pulse". audio_spectrum.py now imports numpy once
            // and streams a fresh line every ~100ms over a persistent pipe.
            //
            // `running` is deliberately NOT a live binding here — assigning to
            // a property that has a binding permanently detaches the binding
            // in QML, which would break the onExited respawn below (every
            // other persistent watcher in this file avoids the same trap by
            // using a plain `running: true` since they're unconditional; this
            // one needs to start/stop conditionally, so the enable condition
            // is a separate computed property and this process is toggled
            // imperatively from the one place that watches it change).
            property bool spectrumWanted: barWindow.mediaVisualizerEnabled && barWindow.isMediaActive && barWindow.musicData.status === "Playing" && barWindow.mediaVisualizerMode === "fft"
            onSpectrumWantedChanged: mediaSpectrumProc.running = spectrumWanted
            Process {
                id: mediaSpectrumProc
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "$HOME/.config/hypr/scripts/quickshell/music/audio_spectrum.py"]
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: (line) => {
                        let parts = line.trim().split(",").map(parseFloat)
                        if (parts.length === 14 && parts.every(v => !isNaN(v))) {
                            barWindow.mediaSpectrumLevels = parts.map(v => Math.max(0, Math.min(1, v)))
                        }
                    }
                }
                // Only respawn if still wanted — parec/the script exiting while
                // "fft" mode was switched off in the same tick shouldn't relaunch it.
                onExited: if (barWindow.spectrumWanted) running = true
            }
            // Fade level back to 0 the instant playback stops/pauses instead
            // of holding the last sampled value.
            onIsMediaActiveChanged: if (!barWindow.isMediaActive) {
                barWindow.mediaAudioLevel = 0
                barWindow.mediaSpectrumLevels = [0,0,0,0,0,0,0,0,0,0,0,0,0,0]
            }

            // "dominant" (default) = most-frequent pixel colors (music_info.sh's
            // original quantization). "vibrant" = same quantize pass but picking
            // the most saturated candidates instead of the most frequent ones —
            // for a cover where the two differ a lot (e.g. a mostly-black cover
            // with one small vivid logo), this is often the more legible choice.
            // Guide → Settings → Media & Audio.
            property string topBarVisualizerColorSource: "dominant"
            // Some covers are genuinely near-monochrome — even the "vibrant"
            // pick above is still muted because there's no real color in the
            // source image to find, and the bars/ring/accent line all read as
            // barely-there against the pill background. Floors saturation and
            // clamps lightness into a visible range regardless of source, so
            // this is always applied rather than being its own toggle — the
            // dominant/vibrant choice controls which hue/relationship of
            // colors is used, this just guarantees whichever is chosen is
            // actually visible.
            function boostColor(c) {
                let s = Math.max(c.hslSaturation, 0.5)
                let l = Math.min(Math.max(c.hslLightness, 0.38), 0.72)
                return Qt.hsla(c.hslHue, s, l, 1.0)
            }
            // Same album-art color quantization music_info.sh writes (for
            // MusicPopup's bc1/bc2 border too) — parsed here from musicData's
            // grad/vibrantGrad so the bar visualizer matches the popup's
            // per-song palette, then boosted for visibility (see above).
            property var mediaBorderColors: {
                let defaults = [mocha.mauve, mocha.blue]
                if (!barWindow.musicData) return defaults
                let src = barWindow.topBarVisualizerColorSource === "vibrant"
                    ? (barWindow.musicData.vibrantGrad || barWindow.musicData.grad)
                    : barWindow.musicData.grad
                if (!src) return defaults
                let matches = src.match(/#[0-9a-fA-F]{6}/g)
                if (matches && matches.length >= 2) return [barWindow.boostColor(Qt.color(matches[0])), barWindow.boostColor(Qt.color(matches[1]))]
                return defaults
            }
            property color mediaBc1: mediaBorderColors[0] || mocha.mauve
            property color mediaBc2: mediaBorderColors[1] || mocha.blue
            Behavior on mediaBc1 { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }
            Behavior on mediaBc2 { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }

            // Settings-driven: "Bottom Accent Line" toggle + edge position
            property bool topBarAccentLine: true
            property string topBarAccentLinePosition: "bottom" // "top" | "bottom" | "left" | "right"
            property real topBarAccentLineThickness: 1
            property int topBarAccentLineSpeedMs: 5200
            property string topBarAccentLineColorMode: "cycle" // "cycle" | "fixed" | "album"
            property color topBarAccentLineFixedColor: "#cba6f7"
            // Settings-driven: media pill audio-reactive visualizer on/off
            // (toggle lives in Guide → Settings → Media & Audio)
            property bool mediaVisualizerEnabled: true
            property bool mediaVisualizerPeakHoldEnabled: true
            // "pulse" = single overall RMS scalar with per-bar sine offsets (original
            // behavior). "fft" = real per-band spectrum from audio_spectrum.py, one
            // frequency band per bar.
            property string mediaVisualizerMode: "pulse"
            // Feature toggles for the 4 additive TopBar features — all default
            // true (ship on), each independently flippable from the Guide.
            property bool topBarHoverCardsEnabled: true
            property string topBarBatteryLiquidMode: "occasional"
            property string topBarVolumeFillMode: "occasional"
            property bool batFillBurst: false
            property bool volFillFlash: false
            Timer { id: batFillBurstTimer; interval: 6000; onTriggered: barWindow.batFillBurst = false }
            Timer { id: volFillFlashTimer; interval: 3000; onTriggered: barWindow.volFillFlash = false }
            function fireBatFillBurst() { barWindow.batFillBurst = true; batFillBurstTimer.restart() }
            function fireVolFillFlash() { barWindow.volFillFlash = true; volFillFlashTimer.restart() }

            property string topBarPillBgMaster: "occasional"
            property string topBarSkyMode: "occasional"
            property string topBarWifiRadarMode: "occasional"
            property string topBarBtPulseMode: "occasional"
            property string topBarCpuAreaMode: "occasional"
            property string topBarNetParticlesMode: "occasional"
            property string topBarUptimeStarsMode: "occasional"
            property string topBarWorkspaceTintMode: "occasional"
            property string topBarClaudeAuroraMode: "occasional"
            property int btPulseBurst: 0
            property var pillFxUntil: ({})
            property int pillFxTick: 0
            function fireFx(name, ms) {
                let u = Object.assign({}, barWindow.pillFxUntil)
                u[name] = Date.now() + ms
                barWindow.pillFxUntil = u
                pillFxTimer.restart()
            }
            function fxFlash(name) { barWindow.pillFxTick; return (barWindow.pillFxUntil[name] || 0) > Date.now() }
            function pillFxOn(mode, cond) {
                let m = barWindow.topBarPillBgMaster
                if (m === "never" || mode === "never") return false
                if (m === "always") return true
                return mode === "always" || (mode === "occasional" && cond)
            }
            Timer {
                id: pillFxTimer
                interval: 500; repeat: true; running: false
                onTriggered: {
                    barWindow.pillFxTick++
                    let now = Date.now(), any = false
                    for (let k in barWindow.pillFxUntil) if (barWindow.pillFxUntil[k] > now) any = true
                    if (!any) pillFxTimer.stop()
                }
            }
            property int skyHour: new Date().getHours()
            readonly property string skyPhase: (skyHour >= 5 && skyHour < 8) ? "dawn" : (skyHour >= 8 && skyHour < 17) ? "day" : (skyHour >= 17 && skyHour < 20) ? "dusk" : "night"
            Timer {
                interval: 60000; repeat: true
                running: barWindow.topBarPillBgMaster !== "never" && barWindow.topBarSkyMode !== "never"
                onTriggered: barWindow.skyHour = new Date().getHours()
            }
            readonly property color btTintColor: {
                let n = barWindow.btDevice.toLowerCase()
                if (/bud|phone|airpod|head|wh-|wf-|earb|sound|speaker|jbl/.test(n)) return "#f5c2e7"
                if (/key|kb/.test(n)) return "#f9e2af"
                if (/mouse|mx |trackpad/.test(n)) return "#89b4fa"
                if (/pixel|iphone|galaxy|redmi|xiaomi|oneplus/.test(n)) return "#a6e3a1"
                return "#cba6f7"
            }
            onBtDeviceChanged: if (barWindow.isStartupReady) { barWindow.fireFx("bt", 4000); barWindow.btPulseBurst++ }
            function classColor(cls) {
                let c = (cls || "").toLowerCase()
                let map = { "vivaldi-stable": "#ef5350", "firefox": "#ff9500", "vesktop": "#5865f2", "discord": "#5865f2", "spotify": "#1db954", "kitty": "#a6e3a1", "foot": "#a6e3a1", "alacritty": "#a6e3a1", "steam": "#66c0f4", "org.telegram.desktop": "#2aabee", "telegramdesktop": "#2aabee", "code": "#007acc", "obs": "#a6adc8", "thunar": "#f9e2af", "nautilus": "#f9e2af" }
                if (c === "") return "#cba6f7"
                if (map[c] !== undefined) return map[c]
                let h = 0
                for (let i = 0; i < c.length; i++) h = (h * 31 + c.charCodeAt(i)) % 360
                return Qt.hsla(h / 360, 0.6, 0.62, 1)
            }
            onWifiIconChanged: if (barWindow.isStartupReady) barWindow.fireFx("wifi", 5000)
            onWifiSsidChanged: if (barWindow.isStartupReady) barWindow.fireFx("wifi", 5000)
            onSkyPhaseChanged: if (barWindow.isStartupReady) barWindow.fireFx("sky", 8000)
            onWeatherCategoryChanged: if (barWindow.isStartupReady) barWindow.fireFx("sky", 8000)

            property string topBarEcoIndicatorMode: "occasional"
            property bool ecoModeEnabled: true
            property var ecoByWs: ({})
            property var ecoByAddr: ({})
            property int ecoCount: 0
            property real ecoNow: Date.now() / 1000
            property string ecoPowerProfile: ""
            readonly property bool ecoShow: barWindow.ecoModeEnabled && barWindow.topBarEcoIndicatorMode !== "never"
            function ecoRebuild(list) {
                let byWs = {}, byAddr = {}
                for (let i = 0; i < list.length; i++) {
                    let e = list[i]
                    let lv = e.level === "freeze" ? 2 : 1
                    let wins = e.wins || []
                    for (let j = 0; j < wins.length; j++) {
                        let w = wins[j]
                        let a = (w.addr || "").replace("0x", "").toLowerCase()
                        if (a !== "" && (!byAddr[a] || byAddr[a].level < lv)) byAddr[a] = { level: lv, since: e.since || 0, quota: e.quota || "" }
                        let k = "" + w.ws
                        if (w.ws !== undefined && w.ws !== null && (!byWs[k] || byWs[k].level < lv)) byWs[k] = { level: lv }
                    }
                }
                barWindow.ecoByWs = byWs
                barWindow.ecoByAddr = byAddr
                barWindow.ecoCount = Math.max(Object.keys(byAddr).length, list.length)
            }
            function ecoFmtDur(secs) {
                let t = Math.max(0, Math.floor(secs))
                if (t < 60) return t + "s"
                if (t < 3600) return Math.floor(t / 60) + "m"
                return Math.floor(t / 3600) + "h" + (Math.floor((t % 3600) / 60) < 10 ? "0" : "") + Math.floor((t % 3600) / 60) + "m"
            }
            Process {
                id: ecoWatcher
                running: true
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "exec inotifywait -qq -e moved_to -e close_write --include 'qs_eco_state\\.json$' /tmp"]
                onExited: {
                    ecoReader.running = true
                    running = true
                }
            }
            Process {
                id: ecoReader
                running: true
                command: ["cat", "/tmp/qs_eco_state.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim()
                        let list = []
                        if (txt !== "") { try { list = JSON.parse(txt) } catch (e) { return } }
                        barWindow.ecoRebuild(list)
                    }
                }
            }
            Timer {
                interval: 6000
                running: barWindow.ecoShow
                repeat: true
                onTriggered: if (!ecoReader.running) ecoReader.running = true
            }
            Process {
                id: ecoProfileReader
                running: false
                command: ["powerprofilesctl", "get"]
                stdout: StdioCollector {
                    onStreamFinished: { let t = this.text.trim(); if (t !== "") barWindow.ecoPowerProfile = t }
                }
            }

            // ---- Resident pill takeover — a Claude resident finding can
            // briefly tint one named bar pill via a single active flag file
            // (resident_card.pill_flag()), same inotify+cat idiom as
            // qs_eco_state.json above. Consumed via barWindow.residentPillActive(name).
            property bool residentPillTakeoverEnabled: true
            property var residentPillFlag: ({})
            property int residentPillBurst: 0
            property real residentPillNow: Date.now() / 1000
            function residentPillActive(name) {
                barWindow.residentPillNow
                if (!barWindow.residentPillTakeoverEnabled) return false
                let f = barWindow.residentPillFlag
                return !!f && f.pill === name && (f.expires_ts || 0) > barWindow.residentPillNow
            }
            Timer {
                interval: 1000; repeat: true
                running: !!barWindow.residentPillFlag && !!barWindow.residentPillFlag.pill
                onTriggered: barWindow.residentPillNow = Date.now() / 1000
            }
            Process {
                id: residentPillWatcher
                running: true
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "exec inotifywait -qq -e moved_to -e close_write --include 'qs_resident_pill_flag\\.json$' /tmp"]
                onExited: { residentPillReader.running = true; running = true }
            }
            Process {
                id: residentPillReader
                running: true
                command: ["cat", "/tmp/qs_resident_pill_flag.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim()
                        if (txt === "") return
                        try { barWindow.residentPillFlag = JSON.parse(txt); barWindow.residentPillBurst++ } catch (e) {}
                    }
                }
            }

            property string smartWsAutoNames: "hover"
            property bool smartWsLayoutsEnabled: true
            property bool smartWsRestoreConfirm: true
            property var smartWsWs: ({})
            property var smartWsLayouts: []
            property string smartWsPendingRestore: ""
            property string smartWsPendingDelete: ""
            Timer { id: smartWsPendingClear; interval: 3000; onTriggered: { barWindow.smartWsPendingRestore = ""; barWindow.smartWsPendingDelete = "" } }
            function smartWsCmd(line) {
                Quickshell.execDetached(["bash", "-c", "printf '%s\\n' \"$1\" >> /tmp/qs_smartws_cmd", "bash", line])
            }
            Process {
                id: smartWsWatcher
                running: barWindow.smartWsAutoNames !== "off" || barWindow.smartWsLayoutsEnabled
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "exec inotifywait -qq -e moved_to -e close_write --include 'qs_smartws\\.json$' /tmp"]
                onExited: {
                    smartWsReader.running = true
                    if (barWindow.smartWsAutoNames !== "off" || barWindow.smartWsLayoutsEnabled) running = true
                }
            }
            Process {
                id: smartWsReader
                running: true
                command: ["cat", "/tmp/qs_smartws.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim()
                        if (txt === "") return
                        try {
                            let d = JSON.parse(txt)
                            barWindow.smartWsWs = d.ws || {}
                            barWindow.smartWsLayouts = d.layouts || []
                        } catch (e) {}
                    }
                }
            }
            property bool residentCardsEnabled: true
            property string residentCardPosition: "under-middle-pill"
            property string residentCardMaxHeight: "medium"
            property string residentCardHoldMode: "auto"
            property string residentCardSound: "on"
            property string residentCardSoundFile: "complete"
            property bool residentQuiet: false
            readonly property string residentQuietPath: "/home/czeddaru/.config/hypr/scripts/quickshell/claude/resident_quiet.json"
            function residentIsNoise(c) {
                if (!c || c.kind) return false
                let src = String(c.source || ""), id = String(c.id || "")
                return src === "screenshot" || id.indexOf("screenshot-answer") === 0 || id.indexOf("shot-action-") === 0 || id.indexOf("clip-error-") === 0
            }
            function residentSetQuiet(q) {
                barWindow.residentQuiet = q
                Quickshell.execDetached(["bash", "-c", "printf '%s\\n' \"$1\" > \"$2\"", "_", JSON.stringify({ quiet: q }), barWindow.residentQuietPath])
            }
            function residentSoundPath(v) {
                let s = String(v || "complete")
                return s.charAt(0) === "/" ? s : "/usr/share/sounds/freedesktop/stereo/" + s + ".oga"
            }
            property var residentQueue: []
            property int residentIdx: 0
            property var residentHistory: []
            property var residentSeen: ({})
            property bool residentBaselined: false
            property bool residentHistoryPinned: false
            property real residentHoldElapsed: 0
            property int residentAgeTick: 0
            readonly property var residentCur: residentQueue.length > 0 ? residentQueue[Math.min(residentIdx, residentQueue.length - 1)] : null
            readonly property real residentMaxBody: residentCardMaxHeight === "small" ? s(90) : (residentCardMaxHeight === "large" ? s(360) : s(200))
            readonly property real residentHoldSecs: {
                let c = barWindow.residentCur
                if (!c) return 0
                if (barWindow.residentCardHoldMode === "until-dismissed") return 0
                if (barWindow.residentCardHoldMode === "short") return 8
                if (c.hold_secs === undefined || c.hold_secs === null) return Math.min(45, Math.max(6, String(c.body || "").length * 0.06))
                let h = Number(c.hold_secs)
                return isNaN(h) || h < 0 ? 0 : h
            }
            function residentGlyph(icon) {
                let map = { "camera": "\udb80\udd00", "screenshot": "\udb80\udd00", "timer": "\udb81\udd1b", "warning": "\udb80\udc26", "alert": "\udb80\udc26", "info": "\udb80\udefc", "error": "\udb80\udd5a", "claude": "\udb81\udea9", "robot": "\udb81\udea9" }
                let i = String(icon || "")
                if (map[i]) return map[i]
                if (i !== "" && !/^[a-z0-9_\- ]+$/i.test(i)) return i
                return "\udb81\udea9"
            }
            function residentAgeStr(ts) {
                let d = Math.max(0, Math.floor(Date.now() / 1000 - Number(ts || 0)))
                if (d < 5) return "now"
                if (d < 60) return d + "s"
                if (d < 3600) return Math.floor(d / 60) + "m"
                return Math.floor(d / 3600) + "h"
            }
            function residentPersist() {
                let keys = Object.keys(barWindow.residentSeen)
                if (keys.length > 300) {
                    let trimmed = {}
                    for (let i = keys.length - 300; i < keys.length; i++) trimmed[keys[i]] = barWindow.residentSeen[keys[i]]
                    barWindow.residentSeen = trimmed
                }
                Quickshell.execDetached(["bash", "-c",
                    "printf '%s' \"$1\" > /tmp/qs_resident_cards_seen.json.tmp && mv -f /tmp/qs_resident_cards_seen.json.tmp /tmp/qs_resident_cards_seen.json",
                    "_", JSON.stringify({ seen: barWindow.residentSeen, history: barWindow.residentHistory })])
            }
            function residentPlaySound(c) {
                if (barWindow.residentCardSound !== "on" || c.urgency === "low") return
                Quickshell.execDetached(["bash", "-c",
                    "find /tmp -maxdepth 1 -name 'qs_rc_snd_*' -mmin +2 -exec rmdir {} + 2>/dev/null; " +
                    "mkdir \"/tmp/qs_rc_snd_$1\" 2>/dev/null || exit 0; " +
                    "f=\"$2\"; [ -f \"$f\" ] || f=/usr/share/sounds/freedesktop/stereo/complete.oga; paplay \"$f\"",
                    "_", String(c.id), barWindow.residentSoundPath(barWindow.residentCardSoundFile)])
            }
            function residentIngest(text) {
                let lines = text.split("\n")
                let now = Date.now() / 1000
                let fresh = []
                for (let i = 0; i < lines.length; i++) {
                    let ln = lines[i].trim()
                    if (ln === "") continue
                    let c
                    try { c = JSON.parse(ln) } catch (e) { continue }
                    if (!c || !c.id) continue
                    let key = String(c.id)
                    let stamp = String(c.ts || 0)
                    if (barWindow.residentSeen[key] === stamp) continue
                    barWindow.residentSeen[key] = stamp
                    if (!barWindow.residentBaselined && (now - Number(c.ts || 0)) > 30) continue
                    fresh.push(c)
                }
                barWindow.residentBaselined = true
                if (fresh.length > 0 && barWindow.residentCardsEnabled) {
                    let q = barWindow.residentQueue.slice()
                    let hadNone = q.length === 0
                    let curId = hadNone ? "" : barWindow.residentCur.id
                    let muted = []
                    for (let i = 0; i < fresh.length; i++) {
                        let c = fresh[i]
                        if (barWindow.residentQuiet && barWindow.residentIsNoise(c) && !q.some(function (x) { return x.id === c.id })) { muted.push(c); continue }
                        let at = -1
                        for (let j = 0; j < q.length; j++) if (q[j].id === c.id) { at = j; break }
                        if (at >= 0) q[at] = c
                        else q.push(c)
                        if (c.id === curId) barWindow.residentHoldElapsed = 0
                        barWindow.residentPlaySound(c)
                    }
                    if (muted.length > 0) {
                        let mids = muted.map(function (x) { return x.id })
                        barWindow.residentHistory = muted.slice().reverse().concat(barWindow.residentHistory.filter(function (x) { return mids.indexOf(x.id) < 0 })).slice(0, 20)
                    }
                    barWindow.residentQueue = q
                    if (hadNone && q.length > 0) { barWindow.residentIdx = 0; barWindow.residentHoldElapsed = 0 }
                }
                barWindow.residentPersist()
            }
            function residentDismiss() {
                let q = barWindow.residentQueue.slice()
                if (q.length === 0) return
                let i = Math.min(barWindow.residentIdx, q.length - 1)
                let c = q.splice(i, 1)[0]
                let h = barWindow.residentHistory.filter(function (x) { return x.id !== c.id })
                h.unshift(c)
                barWindow.residentHistory = h.slice(0, 20)
                barWindow.residentQueue = q
                barWindow.residentIdx = Math.min(i, Math.max(0, q.length - 1))
                barWindow.residentHoldElapsed = 0
                if (q.length === 0) barWindow.residentHistoryPinned = false
                barWindow.residentPersist()
            }
            function residentNav(d) {
                let n = barWindow.residentQueue.length
                if (n < 2) return
                barWindow.residentIdx = (barWindow.residentIdx + d + n) % n
                barWindow.residentHoldElapsed = 0
            }
            function residentRecall(c) {
                let q = [c].concat(barWindow.residentQueue.filter(function (x) { return x.id !== c.id }))
                barWindow.residentQueue = q
                barWindow.residentHistory = barWindow.residentHistory.filter(function (x) { return x.id !== c.id })
                barWindow.residentIdx = 0
                barWindow.residentHoldElapsed = 0
                barWindow.residentHistoryPinned = false
                barWindow.residentPersist()
            }
            Process {
                id: residentSeenReader
                running: true
                command: ["bash", "-c", "cat /tmp/qs_resident_cards_seen.json 2>/dev/null; true"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            let d = JSON.parse(this.text)
                            if (d.seen) barWindow.residentSeen = d.seen
                            if (d.history) barWindow.residentHistory = d.history
                        } catch (e) {}
                        residentQueueReader.running = true
                    }
                }
            }
            Process {
                id: residentQueueReader
                running: false
                command: ["bash", "-c", "cat /tmp/qs_resident_cards.jsonl 2>/dev/null; true"]
                stdout: StdioCollector { onStreamFinished: barWindow.residentIngest(this.text) }
            }
            Process {
                id: residentWatcher
                running: true
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "exec stdbuf -oL inotifywait -m -q -e moved_to,close_write --include 'qs_resident_cards\\.jsonl$' --format %f /tmp"]
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: (line) => { residentQueueReader.running = false; residentQueueReader.running = true }
                }
            }
            Timer {
                id: residentHoldTimer
                interval: 100
                repeat: true
                running: barWindow.residentCur !== null && barWindow.residentHoldSecs > 0 && !residentCard.cardHovered
                onTriggered: {
                    barWindow.residentHoldElapsed += 0.1
                    if (barWindow.residentHoldElapsed >= barWindow.residentHoldSecs) barWindow.residentDismiss()
                }
            }
            Timer {
                interval: 1000
                repeat: true
                running: barWindow.residentCur !== null
                onTriggered: barWindow.residentAgeTick++
            }
            property bool topBarTimerEnabled: true
            property string topBarTimerFillMode: "always"
            property string timerState: "idle"
            property int timerDurationSecs: 1500
            property real timerEndTs: 0
            property int timerRemainingSecs: 0
            property int timerTick: 0
            property bool timerConfirmStop: false
            property bool timerFlash: false
            property real timerLastStartMs: 0
            readonly property int timerRemainingNow: {
                let _t = barWindow.timerTick
                if (barWindow.timerState === "running") return Math.max(0, Math.ceil((barWindow.timerEndTs - Date.now()) / 1000))
                if (barWindow.timerState === "paused") return barWindow.timerRemainingSecs
                return barWindow.timerDurationSecs
            }
            function timerFmt(s, active) {
                if (active && s <= 60) return s + "s"
                let m = active ? Math.ceil(s / 60) : Math.round(s / 60)
                let h = Math.floor(m / 60)
                let mm = m % 60
                return h > 0 ? (h + "h" + (mm < 10 ? "0" : "") + mm + "m") : (mm + "m")
            }
            function timerWrite(state, dur, endTs, rem) {
                barWindow.timerState = state
                barWindow.timerDurationSecs = dur
                barWindow.timerEndTs = endTs
                barWindow.timerRemainingSecs = rem
                barWindow.timerTick++
                Quickshell.execDetached(["bash", "-c", "printf '%s' \"$1\" > /tmp/qs_timer.json", "_",
                    JSON.stringify({ state: state, durationSecs: dur, endTs: endTs, remainingSecs: rem })])
            }
            function timerStart() {
                if (barWindow.timerState === "idle") {
                    barWindow.timerLastStartMs = Date.now()
                    barWindow.timerWrite("running", barWindow.timerDurationSecs, Date.now() + barWindow.timerDurationSecs * 1000, 0)
                } else if (barWindow.timerState === "paused") {
                    barWindow.timerWrite("running", barWindow.timerDurationSecs, Date.now() + barWindow.timerRemainingSecs * 1000, 0)
                }
            }
            function timerPause() {
                if (barWindow.timerState === "running") barWindow.timerWrite("paused", barWindow.timerDurationSecs, 0, barWindow.timerRemainingNow)
                else if (barWindow.timerState === "paused") barWindow.timerStart()
            }
            function timerStop() {
                barWindow.timerConfirmStop = false
                barWindow.timerWrite("idle", barWindow.timerDurationSecs, 0, 0)
            }
            function timerAdjust(deltaSecs) {
                if (barWindow.timerState === "idle") {
                    let d = Math.max(60, Math.min(86340, barWindow.timerDurationSecs + deltaSecs))
                    barWindow.timerWrite("idle", d, 0, 0)
                } else if (barWindow.timerState === "paused") {
                    let r = Math.max(60, Math.min(86340, barWindow.timerRemainingSecs + deltaSecs))
                    barWindow.timerWrite("paused", Math.max(barWindow.timerDurationSecs, r), 0, r)
                }
            }
            function timerSetMinutes(mins) {
                let d = Math.max(1, Math.min(1439, Math.round(mins))) * 60
                if (barWindow.timerState === "idle") barWindow.timerWrite("idle", d, 0, 0)
            }
            function timerFinish() {
                let endTs = barWindow.timerEndTs
                let label = barWindow.timerFmt(barWindow.timerDurationSecs, false)
                barWindow.timerFlash = true
                timerFlashTimer.restart()
                barWindow.timerWrite("idle", barWindow.timerDurationSecs, 0, 0)
                Quickshell.execDetached(["bash", "-c",
                    "find /tmp -maxdepth 1 -name 'qs_timer_fin_*' -mmin +2 -exec rmdir {} + 2>/dev/null; " +
                    "mkdir \"/tmp/qs_timer_fin_$1\" 2>/dev/null || exit 0; " +
                    "if [ \"$3\" = \"1\" ]; then " +
                    "  python3 ~/.config/hypr/scripts/quickshell/claude/resident_extras.py --focus-done \"$4\" \"$1\" >/dev/null 2>&1; " +
                    "else " +
                    "  notify-send -a Timer -i alarm-symbolic 'Timer done' \"$2 elapsed\"; " +
                    "fi; " +
                    "f=/usr/share/sounds/freedesktop/stereo/complete.oga; [ -f \"$f\" ] && paplay \"$f\"",
                    "_", String(Math.round(endTs)), label, barWindow.residentCardsEnabled ? "1" : "0", String(barWindow.timerDurationSecs)])
            }
            function timerApplyFile(d) {
                if (!d || !d.state) return
                if (barWindow.timerState === "running" && d.state === "idle" && (barWindow.timerEndTs - Date.now()) < 2000) {
                    barWindow.timerFlash = true
                    timerFlashTimer.restart()
                }
                barWindow.timerDurationSecs = d.durationSecs || 1500
                barWindow.timerEndTs = d.endTs || 0
                barWindow.timerRemainingSecs = d.remainingSecs || 0
                barWindow.timerState = d.state
                barWindow.timerTick++
            }
            Timer { id: timerFlashTimer; interval: 1800; onTriggered: barWindow.timerFlash = false }
            Timer { id: timerConfirmTimer; interval: 3000; onTriggered: barWindow.timerConfirmStop = false }
            Timer {
                interval: 1000
                repeat: true
                running: barWindow.timerState === "running"
                onTriggered: {
                    barWindow.timerTick++
                    if (barWindow.timerRemainingNow <= 0) barWindow.timerFinish()
                }
            }
            Process {
                id: timerStateWatcher
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "touch /tmp/qs_timer.json; exec inotifywait -m -q -e close_write /tmp/qs_timer.json"]
                running: true
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: (line) => { timerStateReader.running = false; timerStateReader.running = true }
                }
            }
            Process {
                id: timerStateReader
                command: ["bash", "-c", "cat /tmp/qs_timer.json 2>/dev/null"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try { barWindow.timerApplyFile(JSON.parse((this.text || "").trim())) } catch (e) { }
                    }
                }
            }
            Process {
                id: residentQuietWatcher
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "f=" + barWindow.residentQuietPath + "; [ -f \"$f\" ] || printf '{\"quiet\": false}\\n' > \"$f\"; echo init; exec inotifywait -m -q -e close_write \"$f\""]
                running: true
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: (line) => { residentQuietReader.running = false; residentQuietReader.running = true }
                }
            }
            Process {
                id: residentQuietReader
                command: ["bash", "-c", "cat \"$1\" 2>/dev/null", "_", barWindow.residentQuietPath]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try { barWindow.residentQuiet = !!JSON.parse((this.text || "").trim()).quiet } catch (e) { }
                    }
                }
            }
            Process {
                id: timerCmdWatcher
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "touch /tmp/qs_timer_cmd; exec inotifywait -m -q -e close_write /tmp/qs_timer_cmd"]
                running: true
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: (line) => { timerCmdReader.running = false; timerCmdReader.running = true }
                }
            }
            Process {
                id: timerCmdReader
                command: ["bash", "-c", "tail -n 1 /tmp/qs_timer_cmd 2>/dev/null"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let parts = (this.text || "").trim().split(/\s+/)
                        let c = parts[0]
                        if (c === "start") barWindow.timerStart()
                        else if (c === "pause") { if (barWindow.timerState === "running") barWindow.timerPause() }
                        else if (c === "resume") { if (barWindow.timerState === "paused") barWindow.timerStart() }
                        else if (c === "stop") barWindow.timerStop()
                        else if (c === "set" && parts.length > 1) barWindow.timerSetMinutes(parseFloat(parts[1]))
                    }
                }
            }
            onIsChargingChanged: barWindow.fireBatFillBurst()
            onVolPercentChanged: barWindow.fireVolFillFlash()
            onIsMutedChanged: barWindow.fireVolFillFlash()
            property bool topBarShowGpu: true
            property bool topBarShowNet: true
            property bool topBarShowUptime: true
            property bool topBarShowQuickshellCpu: true
            property bool topBarBpmRingEnabled: true
            property bool topBarWorkspaceIconsEnabled: true
            property bool topBarWallpaperSweepEnabled: true
            property bool topBarFlourishesEnabled: true
            property bool topBarFlourishUptimeEnabled: true
            property bool topBarFlourishBatteryEnabled: true
            property bool topBarFlourishCpuCalmEnabled: true
            Process {
                id: accentLineSettingReader
                command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            let parsed = JSON.parse(this.text || "{}");
                            if (parsed.topBarAccentLine !== undefined) barWindow.topBarAccentLine = parsed.topBarAccentLine;
                            if (parsed.topBarAccentLinePosition !== undefined) barWindow.topBarAccentLinePosition = parsed.topBarAccentLinePosition;
                            if (parsed.topBarAccentLineThickness !== undefined) barWindow.topBarAccentLineThickness = parsed.topBarAccentLineThickness;
                            if (parsed.topBarAccentLineSpeedMs !== undefined) barWindow.topBarAccentLineSpeedMs = parsed.topBarAccentLineSpeedMs;
                            if (parsed.topBarAccentLineColorMode !== undefined) barWindow.topBarAccentLineColorMode = parsed.topBarAccentLineColorMode;
                            if (parsed.topBarAccentLineFixedColor !== undefined) barWindow.topBarAccentLineFixedColor = parsed.topBarAccentLineFixedColor;
                            if (parsed.mediaVisualizerEnabled !== undefined) barWindow.mediaVisualizerEnabled = parsed.mediaVisualizerEnabled;
                            if (parsed.mediaVisualizerPeakHoldEnabled !== undefined) barWindow.mediaVisualizerPeakHoldEnabled = parsed.mediaVisualizerPeakHoldEnabled;
                            if (parsed.mediaVisualizerMode !== undefined) barWindow.mediaVisualizerMode = parsed.mediaVisualizerMode;
                            if (parsed.topBarVisualizerColorSource !== undefined) barWindow.topBarVisualizerColorSource = parsed.topBarVisualizerColorSource;
                            if (parsed.lyricsSyncOffsetSec !== undefined) barWindow.lyricsSyncOffsetSec = parsed.lyricsSyncOffsetSec;
                            if (parsed.topBarHoverCardsEnabled !== undefined) barWindow.topBarHoverCardsEnabled = parsed.topBarHoverCardsEnabled;
                            if (parsed.smartWsAutoNames !== undefined) barWindow.smartWsAutoNames = parsed.smartWsAutoNames;
                            if (parsed.smartWsLayoutsEnabled !== undefined) barWindow.smartWsLayoutsEnabled = parsed.smartWsLayoutsEnabled;
                            if (parsed.smartWsRestoreConfirm !== undefined) barWindow.smartWsRestoreConfirm = parsed.smartWsRestoreConfirm;
                            if (parsed.topBarBatteryLiquidMode !== undefined) barWindow.topBarBatteryLiquidMode = parsed.topBarBatteryLiquidMode;
                            if (parsed.topBarVolumeFillMode !== undefined) barWindow.topBarVolumeFillMode = parsed.topBarVolumeFillMode;
                            if (parsed.topBarPillBgMaster !== undefined) barWindow.topBarPillBgMaster = parsed.topBarPillBgMaster;
                            if (parsed.topBarSkyMode !== undefined) barWindow.topBarSkyMode = parsed.topBarSkyMode;
                            if (parsed.topBarWifiRadarMode !== undefined) barWindow.topBarWifiRadarMode = parsed.topBarWifiRadarMode;
                            if (parsed.topBarBtPulseMode !== undefined) barWindow.topBarBtPulseMode = parsed.topBarBtPulseMode;
                            if (parsed.topBarCpuAreaMode !== undefined) barWindow.topBarCpuAreaMode = parsed.topBarCpuAreaMode;
                            if (parsed.topBarNetParticlesMode !== undefined) barWindow.topBarNetParticlesMode = parsed.topBarNetParticlesMode;
                            if (parsed.topBarUptimeStarsMode !== undefined) barWindow.topBarUptimeStarsMode = parsed.topBarUptimeStarsMode;
                            if (parsed.topBarWorkspaceTintMode !== undefined) barWindow.topBarWorkspaceTintMode = parsed.topBarWorkspaceTintMode;
                            if (parsed.topBarClaudeAuroraMode !== undefined) barWindow.topBarClaudeAuroraMode = parsed.topBarClaudeAuroraMode;
                            if (parsed.topBarEcoIndicatorMode !== undefined) barWindow.topBarEcoIndicatorMode = parsed.topBarEcoIndicatorMode;
                            if (parsed.ecoModeEnabled !== undefined) barWindow.ecoModeEnabled = parsed.ecoModeEnabled;
                            if (parsed.topBarTimerEnabled !== undefined) barWindow.topBarTimerEnabled = parsed.topBarTimerEnabled;
                            if (parsed.topBarTimerFillMode !== undefined) barWindow.topBarTimerFillMode = parsed.topBarTimerFillMode;
                            if (parsed.residentCardsEnabled !== undefined) barWindow.residentCardsEnabled = parsed.residentCardsEnabled;
                            if (parsed.residentCardPosition !== undefined) barWindow.residentCardPosition = parsed.residentCardPosition;
                            if (parsed.residentCardMaxHeight !== undefined) barWindow.residentCardMaxHeight = parsed.residentCardMaxHeight;
                            if (parsed.residentCardHoldMode !== undefined) barWindow.residentCardHoldMode = parsed.residentCardHoldMode;
                            if (parsed.residentCardSound !== undefined) barWindow.residentCardSound = parsed.residentCardSound;
                            if (parsed.residentCardSoundFile !== undefined) barWindow.residentCardSoundFile = parsed.residentCardSoundFile;
                            if (parsed.topBarShowGpu !== undefined) barWindow.topBarShowGpu = parsed.topBarShowGpu;
                            if (parsed.topBarShowNet !== undefined) barWindow.topBarShowNet = parsed.topBarShowNet;
                            if (parsed.topBarShowUptime !== undefined) barWindow.topBarShowUptime = parsed.topBarShowUptime;
                            if (parsed.topBarShowQuickshellCpu !== undefined) barWindow.topBarShowQuickshellCpu = parsed.topBarShowQuickshellCpu;
                            if (parsed.topBarBpmRingEnabled !== undefined) barWindow.topBarBpmRingEnabled = parsed.topBarBpmRingEnabled;
                            if (parsed.topBarWorkspaceIconsEnabled !== undefined) barWindow.topBarWorkspaceIconsEnabled = parsed.topBarWorkspaceIconsEnabled;
                            if (parsed.topBarWallpaperSweepEnabled !== undefined) barWindow.topBarWallpaperSweepEnabled = parsed.topBarWallpaperSweepEnabled;
                            if (parsed.topBarFlourishesEnabled !== undefined) barWindow.topBarFlourishesEnabled = parsed.topBarFlourishesEnabled;
                            if (parsed.topBarFlourishUptimeEnabled !== undefined) barWindow.topBarFlourishUptimeEnabled = parsed.topBarFlourishUptimeEnabled;
                            if (parsed.topBarFlourishBatteryEnabled !== undefined) barWindow.topBarFlourishBatteryEnabled = parsed.topBarFlourishBatteryEnabled;
                            if (parsed.topBarFlourishCpuCalmEnabled !== undefined) barWindow.topBarFlourishCpuCalmEnabled = parsed.topBarFlourishCpuCalmEnabled;
                            if (parsed.residentPillTakeoverEnabled !== undefined) barWindow.residentPillTakeoverEnabled = parsed.residentPillTakeoverEnabled;
                        } catch (e) {}
                    }
                }
            }
            Process {
                id: accentLineSettingWatcher
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "while [ ! -f ~/.config/hypr/settings.json ]; do sleep 1; done; exec inotifywait -qq -e modify,close_write ~/.config/hypr/settings.json"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        accentLineSettingReader.running = false; accentLineSettingReader.running = true;
                        accentLineSettingWatcher.running = false; accentLineSettingWatcher.running = true;
                    }
                }
            }

            // Accent-line notification pulse — zero-CPU watcher on the same
            // file Main.qml's notification list writes to, so the underline
            // briefly brightens whenever a fresh notification lands.
            property bool accentPulse: false
            Process {
                id: accentPulseWatcher
                running: true
                command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "touch /tmp/qs_notifications.json; exec inotifywait -qq -e close_write /tmp/qs_notifications.json"]
                onExited: {
                    barWindow.accentPulse = true;
                    accentPulseTimer.restart();
                    running = true;
                }
            }
            Timer { id: accentPulseTimer; interval: 1400; onTriggered: barWindow.accentPulse = false }

            // ---- Ambient "alive" accent state, shared by the bottom accent
            // line and the pill border echoes below — one cohesive lighting
            // system rather than separate bolted-on effects. Color cycles
            // through the same mauve/pink/blue trio already used by the
            // active-workspace ring (wsActiveRing), so it reads as the same
            // visual language. Runs only while topBarAccentLine is enabled.
            property real slowT: 0
            readonly property bool weatherAnimNeeded: barWindow.weatherCategory === "sunny" || barWindow.weatherCategory === "cloudy" || barWindow.weatherCategory === "snow"
            Timer {
                interval: 100; repeat: true; triggeredOnStart: true
                running: barWindow.topBarAccentLine || barWindow.weatherAnimNeeded
                onTriggered: barWindow.slowT = Date.now()
            }
            function easeSine(u) { return 0.5 - 0.5 * Math.cos(Math.PI * u) }
            function cyc3(a, b, c, t, d) {
                let seg = Math.floor(t / d) % 3
                let e = barWindow.easeSine((t % d) / d)
                let from = seg === 0 ? a : (seg === 1 ? b : c)
                let to = seg === 0 ? b : (seg === 1 ? c : a)
                return Qt.rgba(from.r + (to.r - from.r) * e, from.g + (to.g - from.g) * e, from.b + (to.b - from.b) * e, 1)
            }
            function pingPong(t, d) {
                let p = (t % (2 * d)) / (2 * d)
                return barWindow.easeSine(p < 0.5 ? p * 2 : 2 - p * 2)
            }
            QtObject {
                id: accentAmbient
                readonly property color cycleColor: barWindow.cyc3(mocha.mauve, mocha.pink, mocha.blue, barWindow.slowT, 5200)
            }
            readonly property color accentCycleColor: accentAmbient.cycleColor

            // Continuous phase carrier for the staggered ambient "breathe"
            // used by every non-status pill's border below. Linear so the
            // sine it feeds is a genuine one rather than an eased ramp
            // fighting the wave shape, and the loop is seamless because
            // sin(2*PI*1) === sin(2*PI*0) — no jump at the wrap. Each pill
            // reads this through ambientBreath() with its own phase offset,
            // so the "alive" glow visibly travels across the bar instead of
            // every pill lighting up in lockstep — the thing that read as
            // mechanical before.
            readonly property real ambientWave: (barWindow.slowT % 9000) / 9000
            readonly property color cardFill: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.94)
            function ambientBreath(phase) {
                return 0.5 + 0.5 * Math.sin((barWindow.ambientWave + phase) * Math.PI * 2)
            }
            // Never wrap a border.color bound to this in a Behavior — the
            // value already changes every frame (ambientWave/accentCycleColor
            // are both live animations), so a Behavior just restarts its own
            // animation 60x/second chasing a moving target, which low-pass
            // filters the motion down to near-static. Same bug class as the
            // old mediaVizRow height fight.

            // Beat pulse — one pulse per beat synced to the current song's
            // BPM (music_info.sh's bpm_detect.py) while something is
            // playing, falling back to a slower ambient "breathing" rate
            // when idle/no BPM data so the system is never fully static.
            readonly property real beatIntervalMs: {
                let bpm = (barWindow.musicData && barWindow.musicData.bpm) ? barWindow.musicData.bpm : 0
                let playing = barWindow.musicData && barWindow.musicData.status === "Playing"
                return (playing && bpm >= 40 && bpm <= 220) ? (60000.0 / bpm) : 5200
            }
            readonly property bool beatIsPlaying: barWindow.musicData && barWindow.musicData.status === "Playing"
            property real beatPulse: 0
            // While actually playing: a real percussive attack/decay locked
            // to BPM (OutCubic snap in, InCubic snap out). At idle there's no
            // beat to lock to, so it switches to a slow symmetric InOutSine
            // breathe instead of reusing the percussive snap shape — reads as
            // calm rest rather than a fake heartbeat.
            Binding {
                target: barWindow; property: "beatPulse"
                value: barWindow.easeSine((barWindow.slowT % 5200) / 5200 * 2 <= 1 ? (barWindow.slowT % 5200) / 5200 * 2 : 2 - (barWindow.slowT % 5200) / 5200 * 2)
                when: barWindow.topBarAccentLine && !barWindow.beatIsPlaying
            }
            SequentialAnimation {
                loops: Animation.Infinite
                running: barWindow.topBarAccentLine && barWindow.beatIsPlaying
                NumberAnimation { target: barWindow; property: "beatPulse"; to: 1.0; duration: Math.max(120, barWindow.beatIntervalMs * (barWindow.beatIsPlaying ? 0.32 : 0.5)); easing.type: barWindow.beatIsPlaying ? Easing.OutCubic : Easing.InOutSine }
                NumberAnimation { target: barWindow; property: "beatPulse"; to: 0.0; duration: Math.max(180, barWindow.beatIntervalMs * (barWindow.beatIsPlaying ? 0.68 : 0.5)); easing.type: barWindow.beatIsPlaying ? Easing.InCubic : Easing.InOutSine }
            }

            // BPM-reactive album art ring — own pulse, independent of
            // topBarAccentLine's beatPulse above (different setting, only
            // ever runs when actually playing with a real BPM in range).
            // No Behavior on this anywhere downstream — it's already a
            // continuously-running per-frame animation, wrapping it in a
            // Behavior would just fight it and collapse to near-static
            // (same bug class as mediaVizRow/pill ambient borders).
            readonly property bool bpmRingActive: barWindow.topBarBpmRingEnabled && barWindow.beatIsPlaying
                && barWindow.musicData && barWindow.musicData.bpm >= 40 && barWindow.musicData.bpm <= 220
            property real bpmRingPulse: 0
            SequentialAnimation {
                loops: Animation.Infinite
                running: barWindow.bpmRingActive
                NumberAnimation { target: barWindow; property: "bpmRingPulse"; to: 1.0; duration: Math.max(120, barWindow.beatIntervalMs * 0.32); easing.type: Easing.OutCubic }
                NumberAnimation { target: barWindow; property: "bpmRingPulse"; to: 0.0; duration: Math.max(180, barWindow.beatIntervalMs * 0.68); easing.type: Easing.InCubic }
            }

            // Easter egg: clock hits a fun time (00:00, 04:20, 13:37) — the
            // clockbox gets one very soft, brief glow pulse. No text change,
            // no popup, purely a "huh, neat" discovery.
            property bool funTimeHit: false
            readonly property var funTimes: ["00:00", "04:20", "13:37"]

            // Native Qt Time Formatting
            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: {
                    let d = new Date();
                    barWindow.timeStr = Qt.formatDateTime(d, "hh:mm:ss AP");
                    barWindow.fullDateStr = Qt.formatDateTime(d, "dddd, MMMM dd");
                    if (barWindow.typeInIndex >= barWindow.fullDateStr.length) {
                        barWindow.typeInIndex = barWindow.fullDateStr.length;
                    }
                    let hm = Qt.formatDateTime(d, "hh:mm");
                    if (d.getSeconds() === 0 && barWindow.funTimes.indexOf(hm) !== -1 && !barWindow.funTimeHit) {
                        barWindow.funTimeHit = true;
                        funTimeGlowTimer.restart();
                    }
                }
            }
            Timer { id: funTimeGlowTimer; interval: 2200; onTriggered: barWindow.funTimeHit = false }

            // Typewriter effect timer for the date
            Timer {
                id: typewriterTimer
                interval: 40
                running: barWindow.isStartupReady && barWindow.typeInIndex < barWindow.fullDateStr.length
                repeat: true
                onTriggered: barWindow.typeInIndex += 1
            }

            // Fullscreen click-outside-closes catcher for the tray menu — only part
            // of the input mask while trayMenuPopup is visible (see mask above), and
            // declared before barRow so it's the lowest z-order layer: anything the
            // bar itself handles (pills, the popup) still gets the click first.
            Item {
                id: fullScreenCatcher
                anchors.fill: parent
                MouseArea {
                    anchors.fill: parent
                    enabled: trayMenuPopup.visible
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: trayMenuPopup.visible = false
                }
            }

            // ==========================================
            // UI LAYOUT
            // ==========================================
            // Pinned to the top barHeight strip, not anchors.fill: parent — the window
            // itself is taller than the visible bar (see height/exclusiveZone above) so
            // dropdowns (tray menu, overflow list) have real surface space to render into
            // below the bar instead of being clipped at the Wayland surface edge.
            Item {
                id: barRow
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: barWindow.barHeight

                // Closes the tray menu on a click anywhere else in the bar — declared
                // first so it sits lowest in z-order and only fires when nothing above
                // it (a pill, the menu itself) already consumed the click.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: trayMenuPopup.visible = false
                }

                component HoverCard: Rectangle {
                    id: hc
                    property bool active: false
                    property bool confirmed: false
                    property real phase: 0.5
                    property bool flush: true
                    readonly property bool cardHovered: cardHover.hovered
                    default property alias content: holder.data
                    visible: barWindow.topBarHoverCardsEnabled && active
                    opacity: confirmed ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Top
                    scale: confirmed ? 1.0 : 0.9
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                    radius: barWindow.s(14)
                    topLeftRadius: flush ? 0 : radius
                    topRightRadius: flush ? 0 : radius
                    color: barWindow.cardFill
                    border.width: 1
                    border.color: barWindow.topBarAccentLine
                        ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(hc.phase)))
                        : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                    clip: true
                    z: 100
                    Rectangle {
                        visible: hc.flush
                        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                        height: 1
                        color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                    }
                    Item { id: holder; anchors.fill: parent }
                    HoverHandler { id: cardHover; enabled: hc.confirmed }
                }

                // ---------------- CENTER (MUST BE DECLARED FIRST OR Z-INDEXED FOR PROPER ANCHORING BORDERS) ----------------

                // Hold-action glow — soft, layered outer glow around the center
                // cluster that builds with hold progress. Color comes from the
                // registry's glowHex (per-action), never hardcoded, so this
                // generalizes to any future hold-action, not just emergency-kill.
                Item {
                    id: holdActionGlowRoot
                    anchors.centerIn: centerBox
                    width: centerBox.width
                    height: centerBox.height
                    z: -1

                    property color glowColor: barWindow.holdActionGlow
                    property real intensity: barWindow.holdActionActive ? barWindow.holdActionProgress : 0.0
                    // Snappy while actively holding (tracks real progress), springs back
                    // smoothly on release/abort instead of snapping to 0 instantly.
                    property int glowAnimDuration: barWindow.holdActionActive ? 90 : 480
                    property int glowAnimEasing: barWindow.holdActionActive ? Easing.Linear : Easing.OutBack
                    Behavior on intensity { NumberAnimation { duration: holdActionGlowRoot.glowAnimDuration; easing.type: holdActionGlowRoot.glowAnimEasing } }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + barWindow.s(36) * holdActionGlowRoot.intensity
                        height: parent.height + barWindow.s(36) * holdActionGlowRoot.intensity
                        radius: height / 2
                        color: holdActionGlowRoot.glowColor
                        opacity: 0.10 * holdActionGlowRoot.intensity
                        Behavior on width { NumberAnimation { duration: holdActionGlowRoot.glowAnimDuration; easing.type: holdActionGlowRoot.glowAnimEasing } }
                        Behavior on height { NumberAnimation { duration: holdActionGlowRoot.glowAnimDuration; easing.type: holdActionGlowRoot.glowAnimEasing } }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + barWindow.s(20) * holdActionGlowRoot.intensity
                        height: parent.height + barWindow.s(20) * holdActionGlowRoot.intensity
                        radius: height / 2
                        color: holdActionGlowRoot.glowColor
                        opacity: 0.18 * holdActionGlowRoot.intensity
                        Behavior on width { NumberAnimation { duration: holdActionGlowRoot.glowAnimDuration; easing.type: holdActionGlowRoot.glowAnimEasing } }
                        Behavior on height { NumberAnimation { duration: holdActionGlowRoot.glowAnimDuration; easing.type: holdActionGlowRoot.glowAnimEasing } }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height
                        radius: barWindow.s(14)
                        color: "transparent"
                        border.width: barWindow.s(2)
                        border.color: Qt.rgba(holdActionGlowRoot.glowColor.r, holdActionGlowRoot.glowColor.g, holdActionGlowRoot.glowColor.b, 0.7 * holdActionGlowRoot.intensity)
                    }
                }

                Rectangle {
                    id: centerBox
                    anchors.centerIn: parent
                    property bool isHovered: centerMouse.containsMouse
                    color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                    radius: barWindow.s(14); border.width: 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 : 0.05)
                    // Square off when weatherTip is attached flush below — otherwise
                    // this Rectangle's own rounded bottom corners curve inward and leave
                    // a visible notch/gap at the seam where the flat-topped tip meets it,
                    // instead of the two reading as one continuous shape.
                    bottomLeftRadius: ((weatherTip.visible && weatherBox.hoverConfirmed) || (clockTip.visible && clockBox.hoverConfirmed) || (claudeCard.visible && claudeTipState.hoverConfirmed) || (residentCard.shown && !residentCard.isDetached)) ? 0 : radius
                    bottomRightRadius: ((weatherTip.visible && weatherBox.hoverConfirmed) || (clockTip.visible && clockBox.hoverConfirmed) || (claudeCard.visible && claudeTipState.hoverConfirmed) || (residentCard.shown && !residentCard.isDetached)) ? 0 : radius
                    height: barWindow.barHeight
                    
                    width: centerLayout.implicitWidth + barWindow.s(36)
                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
                    
                    // Staggered Center Transition.
                    // opacity binds to isStartupReady (self-heals via its own 10ms
                    // timer) so a hot-reload can never leave the center stuck hidden.
                    // showLayout only drives the cosmetic entrance slide.
                    property bool showLayout: false
                    opacity: barWindow.isStartupReady ? 1 : 0
                    transform: Translate {
                        y: centerBox.showLayout ? 0 : barWindow.s(-30)
                        Behavior on y { NumberAnimation { duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                    }

                    Timer {
                        running: barWindow.isStartupReady
                        interval: 150
                        onTriggered: centerBox.showLayout = true
                    }
                    // safety net: even if the stagger timer is lost on a reload race,
                    // force the slide home so the box is never left translated off-view.
                    Component.onCompleted: centerBox.showLayout = true

                    PillBg {
                        kind: "sky"
                        radius: centerBox.radius
                        px: barWindow.s(1)
                        phase: barWindow.skyPhase
                        weather: barWindow.weatherCategory
                        skyTotal: weatherTip.visible ? centerBox.height - barWindow.weatherHoverOverlap + weatherTip.height : 0
                        shown: barWindow.pillFxOn(barWindow.topBarSkyMode, centerBox.isHovered || weatherTip.visible || barWindow.fxFlash("sky"))
                        z: 0
                    }

                    // Resident pill takeover — centerBox houses both the clock and
                    // weather pills, so this one PillBg + Connections pair covers
                    // both names, same idiom as sysCapsule's shared vol/battery page.
                    PillBg {
                        id: residentCenterBg
                        kind: barWindow.residentPillFlag.style === "border" ? "border" : "pulse"
                        radius: centerBox.radius
                        px: barWindow.s(1)
                        tint: barWindow.residentPillFlag.tint || "#f9e2af"
                        shown: barWindow.residentPillActive("clock") || barWindow.residentPillActive("weather")
                    }
                    Connections {
                        target: barWindow
                        function onResidentPillBurstChanged() {
                            let pill = barWindow.residentPillFlag.pill
                            if (pill !== "clock" && pill !== "weather") return
                            residentCenterBg.fire()
                            if (!barWindow.residentPillFlag.open_card) return
                            let box = pill === "clock" ? clockBox : weatherBox
                            let closeGrace = pill === "clock" ? clockCloseGrace : weatherCloseGrace
                            closeGrace.stop()
                            box.hoverConfirmed = true
                            centerForceOpenTimer.targetBox = box
                            centerForceOpenTimer.interval = Math.max(200, ((barWindow.residentPillFlag.expires_ts || 0) - Date.now() / 1000) * 1000)
                            centerForceOpenTimer.restart()
                        }
                    }
                    Timer { id: centerForceOpenTimer; property var targetBox: null; onTriggered: if (targetBox && !targetBox.cardKeep) targetBox.hoverConfirmed = false }

                    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

                    // Hover Scaling
                    scale: isHovered ? 1.03 : 1.0
                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                    Behavior on color { ColorAnimation { duration: 250 } }
                    
                    MouseArea {
                        id: centerMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle calendar"])
                    }

                    // Using RowLayout to perfectly align children to vertical center naturally
                    RowLayout {
                        id: centerLayout
                        anchors.centerIn: parent
                        spacing: barWindow.s(14)

                        // Claude status dot (embedded; clicks fall through to calendar)
                        ClaudeStatus {
                            id: claudeStatus
                            bar: barWindow
                            theme: mocha
                            compact: true
                        }

                        // Screen-recording indicator (hidden unless recording)
                        RecordingIndicator {
                            bar: barWindow
                            theme: mocha
                        }

                        // Clockbox — outer plain Item (not a Layout, not a positioner),
                        // same reasoning as weatherBox below: a MouseArea added as a direct
                        // child of a Layout (this used to be a ColumnLayout) gets its
                        // geometry silently overridden to 0x0 by that Layout every relayout
                        // pass, since it has no implicitWidth/Height of its own — that's
                        // exactly why hovering the clock/date text alone did nothing even
                        // after wiring up isHovered/hoverConfirmed. The outer Item is
                        // Layout-managed (it's the actual RowLayout child, sized one-
                        // directionally from the inner Column's implicit size); the inner
                        // Column and the MouseArea are NOT Layout children, so they keep
                        // their real geometry.
                        Item {
                            id: clockBox
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: clockCol.implicitWidth
                            implicitHeight: clockCol.implicitHeight
                            width: implicitWidth
                            height: implicitHeight

                            property bool isHovered: clockHoverArea.containsMouse
                            property bool hoverConfirmed: false
                            readonly property bool cardKeep: isHovered || clockTip.cardHovered
                            // Rich agenda data — the OLD /tmp/qs_current_event.json feed
                            // (barWindow.currentEventData) was a different, effectively-dead
                            // pipeline that always read back empty, which is why the card
                            // said "No events today" even with real events on the calendar.
                            // This reads the exact same schedule_manager.sh output (all-day
                            // items, Google Tasks due today, timed events with time ranges,
                            // gap dividers) that the full Calendar popup already shows
                            // correctly — same source, same data, just condensed for the pill.
                            property var scheduleData: ({ header: "", link: "", lessons: [] })
                            Process {
                                id: clockScheduleReader
                                command: ["bash", "-c", "bash ~/.config/hypr/scripts/quickshell/calendar/schedule/schedule_manager.sh 2>/dev/null || echo '{}'"]
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        try {
                                            let d = JSON.parse(this.text.trim())
                                            if (d && d.lessons) clockBox.scheduleData = d
                                        } catch (e) {}
                                    }
                                }
                            }
                            // Connected Bluetooth devices — same status query the bt pill's
                            // own hover card already uses (bluetooth_panel_logic.sh --status),
                            // reused as-is rather than building a second data source.
                            property var btDevices: []
                            Process {
                                id: clockBtReader
                                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/network/bluetooth_panel_logic.sh --status"]
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        try {
                                            let d = JSON.parse(this.text.trim())
                                            if (d.power === undefined) return
                                            clockBox.btDevices = d.connected || []
                                        } catch (e) {}
                                    }
                                }
                            }
                            // Connected wired (USB-cable) devices — lsusb filtered down to
                            // actually-external hardware: drops the 1d6b Linux Foundation
                            // root hubs (virtual bus entries), drops anything reporting
                            // removable=="fixed" in sysfs (this laptop's integrated camera
                            // and fingerprint reader), and drops the internal Bluetooth
                            // adapter by name (redundant with the section above anyway).
                            property var wiredDevices: []
                            Process {
                                id: clockWiredReader
                                command: ["bash", "-c", "bash ~/.config/hypr/scripts/quickshell/claude/list_wired_devices.sh"]
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        try {
                                            let d = JSON.parse(this.text.trim())
                                            clockBox.wiredDevices = d.wired || []
                                        } catch (e) {}
                                    }
                                }
                            }
                            Timer { interval: 1000; repeat: true; running: clockBox.hoverConfirmed; onTriggered: if (!clockBtReader.running) clockBtReader.running = true }
                            Timer { interval: 1000; repeat: true; running: clockBox.hoverConfirmed; onTriggered: if (!clockWiredReader.running) clockWiredReader.running = true }
                            Timer { id: clockHoverDelay; interval: 1000; onTriggered: clockBox.hoverConfirmed = true }
                            Timer { id: clockCloseGrace; interval: 200; onTriggered: { clockHoverDelay.stop(); clockBox.hoverConfirmed = false } }
                            onCardKeepChanged: {
                                if (cardKeep) {
                                    clockCloseGrace.stop()
                                    clockScheduleReader.running = false; clockScheduleReader.running = true
                                    if (!clockBtReader.running) clockBtReader.running = true
                                    if (!clockWiredReader.running) clockWiredReader.running = true
                                    if (!hoverConfirmed) clockHoverDelay.restart()
                                } else {
                                    clockHoverDelay.stop()
                                    clockCloseGrace.restart()
                                }
                            }

                            Column {
                                id: clockCol
                                anchors.fill: parent
                                spacing: -2
                                // Fun-time easter egg — see barWindow.funTimeHit above. Just a
                                // soft color shift-and-settle on the clock text itself, no
                                // extra geometry, so it can never fight the surrounding
                                // layouts.
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: barWindow.timeStr
                                    font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(16); font.weight: Font.Black
                                    color: barWindow.funTimeHit ? mocha.mauve : mocha.blue
                                    Behavior on color { ColorAnimation { duration: 900; easing.type: Easing.InOutSine } }
                                }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: barWindow.dateStr; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: mocha.subtext0 }
                            }

                            MouseArea {
                                id: clockHoverArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        }

                        // Weatherbox — outer plain Item (not a Layout, not a positioner)
                        // wrapping an inner Row. weatherHoverArea needs a real hitbox
                        // (plain width/height bound to its parent's geometry); a
                        // RowLayout overrides a direct child's plain width/height every
                        // relayout pass (the same mechanism that silently collapsed the
                        // hover tooltips to 0-size earlier this session — that's why
                        // hovering the weather pill never triggered anything, the hitbox
                        // itself was 0x0). Making weatherBox a plain Row instead fixed
                        // that but introduced a NEW bug: a Row's own width is the sum of
                        // its children's widths, and the hover MouseArea (a direct Row
                        // child) had its width bound back FROM that same Row width —
                        // circular, causing a live relayout loop (console-visible
                        // "possible QQuickItem::polish() loop"). This outer Item breaks
                        // the cycle: its size comes ONE-DIRECTIONALLY from the inner
                        // Row's implicit content size, and the MouseArea fills the outer
                        // Item's already-settled size, not the Row's live-growing one.
                        Item {
                            id: weatherBox
                            // weatherBox itself IS a direct child of the outer centerLayout
                            // RowLayout — that one legitimately needs Layout.alignment, not
                            // anchors (anchors here is the same "layout vs child geometry"
                            // conflict already fixed inside weatherBox for its own children).
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: weatherRow.implicitWidth
                            implicitHeight: weatherRow.implicitHeight
                            width: implicitWidth
                            height: implicitHeight

                            property bool isHovered: weatherHoverArea.containsMouse
                            property bool hoverConfirmed: false
                            property var hourly: []
                            property var today: ({})
                            property var days: []
                            readonly property bool cardKeep: isHovered || weatherTip.cardHovered
                            Timer { id: weatherHoverDelay; interval: 1000; onTriggered: weatherBox.hoverConfirmed = true }
                            Timer { id: weatherCloseGrace; interval: 200; onTriggered: { weatherHoverDelay.stop(); weatherBox.hoverConfirmed = false } }
                            Process {
                                id: weatherHourlyReader
                                command: ["bash", "-c", "cat ~/.cache/quickshell/weather/weather.json 2>/dev/null || echo '{}'"]
                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        try {
                                            let d = JSON.parse(this.text.trim())
                                            weatherBox.hourly = (d.forecast && d.forecast[0] && d.forecast[0].hourly) ? d.forecast[0].hourly.slice(0, 8) : []
                                            weatherBox.today = (d.forecast && d.forecast[0]) ? d.forecast[0] : ({})
                                            weatherBox.days = d.forecast ? d.forecast.slice(0, 5) : []
                                        } catch (e) {}
                                    }
                                }
                            }
                            onCardKeepChanged: {
                                if (cardKeep) {
                                    weatherCloseGrace.stop()
                                    weatherHourlyReader.running = false; weatherHourlyReader.running = true
                                    if (!hoverConfirmed) weatherHoverDelay.restart()
                                } else {
                                    weatherHoverDelay.stop()
                                    weatherCloseGrace.restart()
                                }
                            }

                        Row {
                            id: weatherRow
                            anchors.fill: parent
                            spacing: barWindow.s(8)
                            // Ambient, tasteful motion per weather.sh condition category —
                            // gentle sun-ray rotation, drifting rain, floating clouds,
                            // storm flicker. Slow durations on purpose, never distracting.
                            Item {
                                id: weatherIconWrap
                                anchors.verticalCenter: parent.verticalCenter
                                implicitWidth: weatherIconText.implicitWidth
                                implicitHeight: weatherIconText.implicitHeight
                                // RowLayout auto-sizes a child from its implicitWidth/Height;
                                // a plain Row (what weatherBox is now) does not — it needs
                                // the actual width/height set, or this collapses to 0 and
                                // the icon (and its parent's implicit sizing) disappears.
                                width: implicitWidth
                                height: implicitHeight

                                rotation: barWindow.weatherCategory === "sunny" ? (barWindow.slowT % 22000) / 22000 * 360 : 0
                                Behavior on rotation { enabled: barWindow.weatherCategory !== "sunny"; NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }


                                SequentialAnimation on y {
                                    running: barWindow.weatherCategory === "rainy"
                                    loops: Animation.Infinite
                                    NumberAnimation { to: barWindow.s(3); duration: 420; easing.type: Easing.InQuad }
                                    NumberAnimation { to: 0; duration: 90; easing.type: Easing.OutQuad }
                                    PauseAnimation { duration: 900 }
                                }

                                transform: Translate { x: (barWindow.weatherCategory === "cloudy" || barWindow.weatherCategory === "snow") ? barWindow.s(3) * (2 * barWindow.pingPong(barWindow.slowT, 2600) - 1) : 0 }

                                SequentialAnimation on opacity {
                                    running: barWindow.weatherCategory === "storm"
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: 1400 }
                                    NumberAnimation { to: 0.35; duration: 70 }
                                    NumberAnimation { to: 1.0; duration: 90 }
                                    PauseAnimation { duration: 120 }
                                    NumberAnimation { to: 0.5; duration: 60 }
                                    NumberAnimation { to: 1.0; duration: 100 }
                                }

                                Text {
                                    id: weatherIconText
                                    text: barWindow.weatherIcon;
                                    font.family: "Iosevka Nerd Font";
                                    font.pixelSize: barWindow.s(24);
                                    color: Qt.tint(barWindow.weatherHex, Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.4))
                                }
                            }
                            Text {
                                text: barWindow.weatherTemp;
                                anchors.verticalCenter: parent.verticalCenter;
                                font.family: "JetBrains Mono";
                                font.pixelSize: barWindow.s(17);
                                font.weight: Font.Black;
                                color: mocha.peach
                            }
                        } // weatherRow

                            MouseArea {
                                id: weatherHoverArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        } // weatherBox

                        // Hover card — hourly forecast strip. Reparented onto centerBox to
                        // escape the RowLayout's own layouting (a plain child would get
                        // laid out as another row item instead of floating). Positioned via
                        // mapToItem + plain x/y rather than anchors — anchors bound in the
                        // same Component as a `parent:` reassignment race against the
                        // reparent taking effect ("Cannot anchor to an item that isn't a
                        // parent or sibling" at load), mapToItem sidesteps that entirely.
                        Rectangle {
                            id: weatherTip
                            readonly property bool cardHovered: weatherTipHover.hovered
                            HoverHandler { id: weatherTipHover; enabled: weatherBox.hoverConfirmed }
                            visible: barWindow.topBarHoverCardsEnabled && (weatherBox.cardKeep || weatherBox.hoverConfirmed) && weatherBox.hourly.length > 0
                            opacity: weatherBox.hoverConfirmed ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            // Grows out of the pill rather than popping in flat — scaled
                            // from its top edge, flush against the pill (slight overlap)
                            // so it reads as an extension of it, not a separate floating
                            // box. transformOrigin.y=0 with a plain `scale` (not scale.y
                            // alone — QML Item has no independent y-scale property, a
                            // Scale transform would be needed for that; a uniform scale
                            // reads close enough here and avoids a second transform node).
                            transformOrigin: Item.Top
                            scale: weatherBox.hoverConfirmed ? 1.0 : barWindow.weatherHoverGrowScale
                            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                            parent: centerBox
                            // Exact same width/x/color as centerBox itself (the whole
                            // clock+weather pill, not just the narrow weather sub-row) —
                            // reads as the pill's own bottom growing an extra panel
                            // rather than a separate floating card of a different size
                            // and shade next to it. No side-to-side wiggle anymore: with
                            // matching width there's no spare room to wiggle into.
                            x: 0
                            y: centerBox.height - barWindow.weatherHoverOverlap
                            width: centerBox.width
                            // Capped so a full forecast (hourly row + 5-day + the
                            // humidity/wind/pressure grid) can't overflow the card past
                            // the window's own bounds at small scale/screen heights — the
                            // window itself is capped at Math.min(Screen.height, s(640))
                            // (see PanelWindow height above), it does NOT grow to fit an
                            // uncapped card. Content scrolls internally past this instead,
                            // same pattern as clockTip's agenda Flickable and the resident
                            // card's residentMaxBody cap.
                            readonly property real maxBody: barWindow.s(340)
                            height: Math.min(weatherTipRow.implicitHeight, maxBody) + barWindow.s(18)
                            radius: barWindow.s(14)
                            topLeftRadius: 0
                            topRightRadius: 0
                            clip: true
                            // Opaque now (was inheriting centerBox's semi-transparent
                            // fill, which read as flimsy hanging off a solid pill) plus
                            // the same ambient-cycling border every other pill in this
                            // bar has, instead of no border at all.
                            color: barWindow.cardFill
                            border.width: 1
                            border.color: barWindow.topBarAccentLine
                                ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.5)))
                                : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                            z: 100
                            PillBg {
                                kind: "sky"
                                radius: weatherTip.radius
                                flatTop: true
                                px: barWindow.s(1)
                                phase: barWindow.skyPhase
                                weather: barWindow.weatherCategory
                                skyOffset: centerBox.height - barWindow.weatherHoverOverlap
                                skyTotal: centerBox.height - barWindow.weatherHoverOverlap + weatherTip.height
                                shown: barWindow.pillFxOn(barWindow.topBarSkyMode, true)
                            }
                            // Soft glow bleeding up from the bottom inner edge — same
                            // "alive" ambient wash the quicksettings drawer/OSDs use,
                            // just a much smaller dose here.
                            // Thin highlight where the card meets the pill above it —
                            // sells the "grew out of it" continuity a flat seam doesn't.
                            Rectangle {
                                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                height: 1
                                color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                            }
                            Flickable {
                                id: weatherTipFlick
                                anchors.top: parent.top
                                anchors.topMargin: barWindow.s(8)
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - barWindow.s(28)
                                height: parent.height - barWindow.s(16)
                                contentWidth: width
                                contentHeight: weatherTipRow.implicitHeight
                                clip: true
                                interactive: weatherTipRow.implicitHeight > height
                                Column {
                                id: weatherTipRow
                                width: parent.width
                                spacing: barWindow.s(8)
                                readonly property var t: weatherBox.today
                                readonly property real curT: parseFloat(barWindow.weatherTemp)
                                readonly property real minT: parseFloat(t.min)
                                readonly property real maxT: parseFloat(t.max)
                                readonly property real frac: (isNaN(curT) || isNaN(minT) || isNaN(maxT) || maxT <= minT) ? 0.5 : Math.max(0, Math.min(1, (curT - minT) / (maxT - minT)))
                                readonly property real dirDeg: parseFloat(t.wind_deg) || 0

                                Row {
                                    width: parent.width
                                    spacing: barWindow.s(10)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: weatherTipRow.t.icon || ""; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(26); color: weatherTipRow.t.hex || mocha.yellow }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - barWindow.s(36) - barWindow.s(10) - rainChip.width - barWindow.s(10)
                                        Text { width: parent.width; text: weatherTipRow.t.desc || ""; elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Bold; color: mocha.text }
                                        Text { width: parent.width; text: "feels like " + (weatherTipRow.t.feels_like || "--") + "°  ·  " + (weatherTipRow.t.day_full || ""); elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); color: mocha.overlay0 }
                                    }
                                    Rectangle {
                                        id: rainChip
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: rainChipText.implicitWidth + barWindow.s(14); height: barWindow.s(20); radius: height / 2
                                        color: Qt.rgba(0.455, 0.78, 0.925, 0.14)
                                        border.width: 1; border.color: Qt.rgba(0.455, 0.78, 0.925, 0.35)
                                        Text { id: rainChipText; anchors.centerIn: parent; text: "󰖗 " + (weatherTipRow.t.pop || "0") + "%"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold; color: "#74c7ec" }
                                    }
                                }

                                Row {
                                    width: parent.width
                                    spacing: barWindow.s(8)
                                    Text { anchors.verticalCenter: parent.verticalCenter; width: barWindow.s(34); horizontalAlignment: Text.AlignRight; text: (weatherTipRow.t.min || "--") + "°"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold; color: "#89dceb" }
                                    Item {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - barWindow.s(34) * 2 - barWindow.s(16)
                                        height: barWindow.s(12)
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width; height: barWindow.s(5); radius: height / 2
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: "#89dceb" }
                                                GradientStop { position: 0.55; color: "#f9e2af" }
                                                GradientStop { position: 1.0; color: "#fab387" }
                                            }
                                        }
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: (parent.width - width) * weatherTipRow.frac
                                            width: barWindow.s(11); height: width; radius: width / 2
                                            color: mocha.text
                                            border.width: 2; border.color: mocha.mantle
                                        }
                                    }
                                    Text { anchors.verticalCenter: parent.verticalCenter; width: barWindow.s(34); text: (weatherTipRow.t.max || "--") + "°"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold; color: "#fab387" }
                                }

                                Grid {
                                    width: parent.width
                                    columns: 4
                                    columnSpacing: 0
                                    rowSpacing: barWindow.s(5)
                                    Repeater {
                                        model: [
                                            { g: "󰖎", c: "#74c7ec", v: (weatherTipRow.t.humidity || "--") + "%" },
                                            { g: "󰖝", c: "#a6e3a1", v: (weatherTipRow.t.wind || "--") + " m/s", rot: weatherTipRow.dirDeg },
                                            { g: "󰊚", c: "#cba6f7", v: (weatherTipRow.t.pressure || "--") + " hPa" },
                                            { g: "󰈈", c: "#94e2d5", v: ((parseFloat(weatherTipRow.t.visibility) || 0) / 1000).toFixed(1) + " km" },
                                            { g: "󰅟", c: "#bac2de", v: (weatherTipRow.t.clouds || "--") + "%" },
                                            { g: "󰖜", c: "#f9e2af", v: weatherTipRow.t.sunrise || "--:--" },
                                            { g: "󰖛", c: "#fab387", v: weatherTipRow.t.sunset || "--:--" },
                                            { g: "󰢃", c: "#f38ba8", v: (weatherTipRow.t.gust || "0") + " m/s" }
                                        ]
                                        delegate: Row {
                                            width: parent.width / 4
                                            spacing: barWindow.s(4)
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.g; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(12); color: modelData.c
                                                rotation: modelData.rot !== undefined ? modelData.rot + 180 : 0
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - barWindow.s(16)
                                                text: modelData.v; elide: Text.ElideRight
                                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Bold; color: mocha.text
                                            }
                                        }
                                    }
                                }

                                Rectangle { width: parent.width; height: 1; color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.07) }

                                Flickable {
                                    id: hourlyFlick
                                    width: parent.width
                                    height: hourlyRow.implicitHeight
                                    contentWidth: hourlyRow.implicitWidth
                                    contentHeight: height
                                    clip: true
                                    interactive: hourlyRow.implicitWidth > width
                                    boundsBehavior: Flickable.StopAtBounds
                                    Row {
                                        id: hourlyRow
                                        anchors.horizontalCenter: hourlyFlick.contentWidth <= hourlyFlick.width ? hourlyFlick.horizontalCenter : undefined
                                        spacing: barWindow.s(14)
                                        Repeater {
                                            model: weatherBox.hourly
                                            Column {
                                                spacing: barWindow.s(2)
                                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.time || ""; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); color: mocha.overlay0 }
                                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon || ""; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(14); color: modelData.hex || mocha.yellow }
                                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: (modelData.temp || "") + "°"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold; color: mocha.text }
                                                Text { anchors.horizontalCenter: parent.horizontalCenter; visible: (parseInt(modelData.pop) || 0) > 0; text: "󰖗" + modelData.pop + "%"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(8); color: "#74c7ec" }
                                            }
                                        }
                                    }
                                }

                                Rectangle { width: parent.width; height: 1; color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.07) }

                                Row {
                                    width: parent.width
                                    Repeater {
                                        model: weatherBox.days
                                        Column {
                                            width: weatherTipRow.width / Math.max(1, weatherBox.days.length)
                                            spacing: barWindow.s(1)
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: index === 0 ? "today" : (modelData.day || ""); font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: index === 0 ? Font.Bold : Font.Normal; color: index === 0 ? mocha.text : mocha.overlay0 }
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon || ""; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(14); color: modelData.hex || mocha.yellow }
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(parseFloat(modelData.min)) + "° / " + Math.round(parseFloat(modelData.max)) + "°"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(8); color: mocha.text }
                                        }
                                    }
                                }
                            } // closes weatherTipRow Column
                            } // closes weatherTipFlick Flickable

                        } // closes weatherTip Rectangle

                        // Separate card for the clock/date pill — was briefly folded into
                        // weatherTip above, but clock and weather are two different pills
                        // side by side and should show two different cards, not the same
                        // one regardless of which half you hover. Same flush/growing-out
                        // styling as weatherTip, just clock-flavored content.
                        Rectangle {
                            id: clockTip
                            readonly property bool cardHovered: clockTipHover.hovered
                            HoverHandler { id: clockTipHover; enabled: clockBox.hoverConfirmed }
                            visible: barWindow.topBarHoverCardsEnabled && (clockBox.cardKeep || clockBox.hoverConfirmed)
                            opacity: clockBox.hoverConfirmed ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            transformOrigin: Item.Top
                            scale: clockBox.hoverConfirmed ? 1.0 : barWindow.weatherHoverGrowScale
                            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                            parent: centerBox
                            x: 0
                            y: centerBox.height - barWindow.weatherHoverOverlap
                            width: centerBox.width
                            // Reactive to real content, clamped to the same s(320) ceiling
                            // the old flat constant used — the Region{item: clockTip} input
                            // mask (PanelWindow's `mask:` near the top of this file) tracks
                            // this item's live geometry, so as long as height only ever
                            // grows/shrinks in response to clockTipCol's actual size (not a
                            // one-time snapshot taken before async agenda data arrives), the
                            // mask stays in sync instead of drifting — that was the failure
                            // mode the flat constant worked around, not something reactivity
                            // itself causes. Floor at s(140) so an empty-agenda day doesn't
                            // look like a sliver.
                            height: Math.max(barWindow.s(140), Math.min(barWindow.s(320), clockTipCol.y + clockTipCol.implicitHeight + barWindow.s(16)))
                            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            radius: barWindow.s(14)
                            topLeftRadius: 0
                            topRightRadius: 0
                            color: barWindow.cardFill
                            border.width: 1
                            border.color: barWindow.topBarAccentLine
                                ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.55)))
                                : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                            z: 100
                            clip: true
                            Rectangle {
                                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                height: 1
                                color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                            }
                            Column {
                                id: clockTipCol
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: barWindow.s(8)
                                width: parent.width - barWindow.s(28)
                                spacing: barWindow.s(8)
                                readonly property var sd: clockBox.scheduleData || ({})
                                readonly property var lessons: sd.lessons || []
                                readonly property bool authError: sd.header === "Auth error"
                                // barWindow.slowT ticks continuously — referenced only to
                                // force this to re-evaluate periodically so "isNow" below
                                // actually updates as time passes, not just on data refresh.
                                readonly property real nowEpoch: { barWindow.slowT; return Date.now() / 1000 }

                                Row {
                                    width: parent.width
                                    spacing: barWindow.s(8)
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: barWindow.s(22); height: width; radius: width / 2
                                        color: Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.16)
                                        Text { anchors.centerIn: parent; text: "󰃭"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(12); color: mocha.mauve }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - barWindow.s(30) - (headerLink.visible ? headerLink.width + barWindow.s(8) : 0)
                                        text: clockTipCol.sd.header || "Loading…"
                                        elide: Text.ElideRight
                                        font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: mocha.text
                                    }
                                    Rectangle {
                                        id: headerLink
                                        visible: clockTipCol.sd.header !== undefined && clockTipCol.sd.header !== ""
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: headerLinkText.implicitWidth + barWindow.s(14); height: barWindow.s(20); radius: height / 2
                                        color: headerLinkMa.containsMouse ? mocha.mauve : Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.14)
                                        border.width: 1; border.color: Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.35)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text { id: headerLinkText; anchors.centerIn: parent; text: (clockTipCol.authError ? "Re-auth" : "Open Web") + " 󰏌"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Bold; color: headerLinkMa.containsMouse ? mocha.crust : mocha.mauve }
                                        MouseArea {
                                            id: headerLinkMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (clockTipCol.authError) Quickshell.execDetached(["bash", "-c", "bash ~/.config/hypr/scripts/quickshell/calendar/schedule/reauth.sh"])
                                                else Quickshell.execDetached(["xdg-open", clockTipCol.sd.link || "https://calendar.google.com"])
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: clockTipCol.lessons.length === 0 && !clockTipCol.authError
                                    width: parent.width
                                    text: "No events today"
                                    font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); color: mocha.overlay0
                                }

                                // Scrollable so a genuinely busy day doesn't blow the card
                                // past a sane height — same overlap/flush styling either way.
                                Flickable {
                                    width: parent.width
                                    height: Math.min(agendaCol.implicitHeight, barWindow.s(260))
                                    contentWidth: width
                                    contentHeight: agendaCol.implicitHeight
                                    clip: true
                                    interactive: agendaCol.implicitHeight > height
                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                                    Column {
                                        id: agendaCol
                                        width: parent.width
                                        spacing: barWindow.s(7)
                                        Repeater {
                                            model: clockTipCol.lessons
                                            delegate: Item {
                                                width: agendaCol.width
                                                height: modelData.type === "gap" ? gapRow.height : eventRow.height
                                                // Gap divider between events — mirrors the full
                                                // Calendar popup's free-time indicator.
                                                Row {
                                                    id: gapRow
                                                    visible: modelData.type === "gap"
                                                    width: parent.width
                                                    spacing: barWindow.s(6)
                                                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: (parent.width - gapText.width - barWindow.s(12)) / 2; height: 1; color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.10) }
                                                    Text { id: gapText; anchors.verticalCenter: parent.verticalCenter; text: (modelData.desc || "") + " gap"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(8); color: mocha.overlay0 }
                                                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: (parent.width - gapText.width - barWindow.s(12)) / 2; height: 1; color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.10) }
                                                }
                                                Row {
                                                    id: eventRow
                                                    visible: modelData.type !== "gap"
                                                    width: parent.width
                                                    spacing: barWindow.s(8)
                                                    readonly property bool isAllDay: modelData.time === "All day"
                                                    readonly property bool isTask: modelData.time === "Task"
                                                    readonly property bool isNow: !isAllDay && !isTask && clockTipCol.nowEpoch >= (modelData.start || 0) && clockTipCol.nowEpoch < (modelData.end || 0)
                                                    readonly property color accent: isNow ? mocha.mauve : (isTask ? mocha.yellow : (isAllDay ? mocha.blue : mocha.peach))
                                                    readonly property string glyph: isTask ? "󰄬" : (isAllDay ? "󰃭" : "󰃰")

                                                    Rectangle {
                                                        anchors.top: parent.top
                                                        width: barWindow.s(18); height: barWindow.s(18); radius: width / 2
                                                        color: Qt.rgba(eventRow.accent.r, eventRow.accent.g, eventRow.accent.b, eventRow.isNow ? 0.28 : 0.14)
                                                        Behavior on color { ColorAnimation { duration: 300 } }
                                                        Text { anchors.centerIn: parent; text: eventRow.glyph; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(10); color: eventRow.accent }
                                                    }
                                                    Column {
                                                        width: parent.width - barWindow.s(26)
                                                        spacing: barWindow.s(1)
                                                        Text {
                                                            width: parent.width
                                                            text: modelData.subject || ""
                                                            elide: Text.ElideRight
                                                            font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold
                                                            color: eventRow.isNow ? mocha.mauve : mocha.text
                                                        }
                                                        Row {
                                                            spacing: barWindow.s(6)
                                                            Text { text: "󰥔 " + (modelData.time || ""); font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); color: mocha.subtext1 }
                                                            Text { visible: !!modelData.room; text: "󰍎 " + (modelData.room || ""); elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); color: mocha.subtext1 }
                                                            Rectangle {
                                                                visible: eventRow.isNow
                                                                width: nowTxt.implicitWidth + barWindow.s(10); height: barWindow.s(14); radius: height / 2
                                                                color: Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.22)
                                                                Text { id: nowTxt; anchors.centerIn: parent; text: "now"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(8); font.weight: Font.Bold; color: mocha.mauve }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Connected Bluetooth devices — hidden entirely when nothing's
                                // connected, no empty section header.
                                Column {
                                    width: parent.width
                                    spacing: barWindow.s(6)
                                    visible: clockBox.btDevices.length > 0
                                    Text { text: "CONNECTED DEVICES"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Bold; color: mocha.overlay0 }
                                    Repeater {
                                        model: clockBox.btDevices
                                        Item {
                                            id: devRow
                                            readonly property int batt: parseInt(modelData.battery) || 0
                                            width: clockTipCol.width; height: barWindow.s(26)
                                            Rectangle { anchors.fill: parent; radius: barWindow.s(7); color: Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4) }
                                            Text { id: devIcon; anchors.left: parent.left; anchors.leftMargin: barWindow.s(7); anchors.verticalCenter: parent.verticalCenter; text: modelData.icon || "󰂯"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(12); color: mocha.mauve }
                                            Text {
                                                anchors.left: devIcon.right; anchors.leftMargin: barWindow.s(7)
                                                anchors.right: devBatt.left; anchors.rightMargin: barWindow.s(8)
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.name || ""; elide: Text.ElideRight
                                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold; color: mocha.text
                                            }
                                            Text {
                                                id: devBatt
                                                visible: devRow.batt > 0
                                                anchors.right: parent.right; anchors.rightMargin: barWindow.s(7); anchors.verticalCenter: parent.verticalCenter
                                                text: devRow.batt + "%"
                                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Black
                                                color: devRow.batt <= 20 ? mocha.red : (devRow.batt <= 50 ? mocha.yellow : mocha.green)
                                            }
                                        }
                                    }
                                }

                                // Connected wired (USB-cable) devices — hidden entirely when
                                // nothing's connected, no empty section header.
                                Column {
                                    width: parent.width
                                    spacing: barWindow.s(6)
                                    visible: clockBox.wiredDevices.length > 0
                                    Text { text: "WIRED"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Bold; color: mocha.overlay0 }
                                    Repeater {
                                        model: clockBox.wiredDevices
                                        Item {
                                            width: clockTipCol.width; height: barWindow.s(26)
                                            Rectangle { anchors.fill: parent; radius: barWindow.s(7); color: Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4) }
                                            Text { id: wiredIcon; anchors.left: parent.left; anchors.leftMargin: barWindow.s(7); anchors.verticalCenter: parent.verticalCenter; text: "󰇺"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(12); color: mocha.mauve }
                                            Text {
                                                anchors.left: wiredIcon.right; anchors.leftMargin: barWindow.s(7)
                                                anchors.right: parent.right; anchors.rightMargin: barWindow.s(8)
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.name || ""; elide: Text.ElideRight
                                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold; color: mocha.text
                                            }
                                        }
                                    }
                                }
                            }
                        }

                    }
                }

                // ---------------- LEFT ----------------
                RowLayout {
                    id: leftLayout
                    anchors.left: parent.left
                    anchors.right: centerBox.left  // Hard boundary to prevent overlaps
                    anchors.rightMargin: barWindow.s(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: barWindow.s(4)
                    clip: true

                    // Staggered Main Transition
                    property bool showLayout: false
                    opacity: showLayout ? 1 : 0
                    transform: Translate {
                        x: leftLayout.showLayout ? 0 : barWindow.s(-30)
                        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                    }
                    
                    Timer {
                        running: barWindow.isStartupReady
                        interval: 10
                        onTriggered: leftLayout.showLayout = true
                    }

                    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

                    property int moduleHeight: barWindow.barHeight

                    // Workspaces
                    Rectangle {
                        id: wsGroupBox
                        color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                        radius: barWindow.s(14); border.width: 1
                        // No inherent status meaning of its own (the active
                        // workspace's own mauve/pink fill carries that) — full
                        // ambient border treatment, phase 0.0 so the traveling
                        // breathe starts here, leftmost in the bar.
                        readonly property color baseBorder: barWindow.topBarAccentLine
                            ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.0)))
                            : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                        readonly property bool ecoActive: barWindow.ecoShow && barWindow.ecoCount > 0
                        border.color: ecoActive ? Qt.tint(baseBorder, Qt.rgba(0.537, 0.863, 0.922, 0.3)) : baseBorder
                        Behavior on border.color { ColorAnimation { duration: 300 } }
                        Layout.preferredHeight: parent.moduleHeight
                        clip: true
                        bottomLeftRadius: (wsCard.visible && wsGroupBox.hoverConfirmed) ? 0 : radius
                        bottomRightRadius: (wsCard.visible && wsGroupBox.hoverConfirmed) ? 0 : radius

                        property int hoveredIdx: -1
                        property int shownIdx: 0
                        property var shownWins: []
                        property bool hoverConfirmed: false
                        readonly property bool cardKeep: (hoveredIdx >= 0 || wsCard.cardHovered) && shownWins.length > 0
                        function refreshShown() {
                            let w = []
                            if (shownIdx >= 0 && shownIdx < workspacesModel.count) {
                                try { w = JSON.parse(workspacesModel.get(shownIdx).wsWins || "[]") } catch (e) {}
                            }
                            shownWins = w
                        }
                        onHoveredIdxChanged: if (hoveredIdx >= 0) { shownIdx = hoveredIdx; refreshShown() }
                        onCardKeepChanged: {
                            if (cardKeep) {
                                wsCloseGrace.stop()
                                if (!hoverConfirmed) wsHoverDelay.restart()
                            } else {
                                wsHoverDelay.stop()
                                wsCloseGrace.restart()
                            }
                        }
                        Timer { id: wsHoverDelay; interval: 1000; onTriggered: wsGroupBox.hoverConfirmed = true }
                        Timer { id: wsCloseGrace; interval: 200; onTriggered: { wsHoverDelay.stop(); wsGroupBox.hoverConfirmed = false } }
                        Timer {
                            interval: 1000; repeat: true; triggeredOnStart: true
                            running: wsGroupBox.hoverConfirmed && barWindow.ecoShow
                            onTriggered: barWindow.ecoNow = Date.now() / 1000
                        }
                        Timer {
                            interval: 3000; repeat: true; triggeredOnStart: true
                            running: wsGroupBox.hoverConfirmed && barWindow.ecoShow
                            onTriggered: if (!ecoProfileReader.running) ecoProfileReader.running = true
                        }
                        property real targetWidth: workspacesModel.count > 0 ? wsLayout.width + barWindow.s(20) : 0
                        Layout.preferredWidth: targetWidth
                        visible: targetWidth > 0
                        opacity: workspacesModel.count > 0 ? 1 : 0
                        
                        Behavior on opacity { NumberAnimation { duration: 300 } }

                        // Using standard Row completely removes internal width sizing bugs
                        Row {
                            id: wsLayout
                            anchors.centerIn: parent
                            spacing: barWindow.s(6)
                            
                            Repeater {
                                model: workspacesModel
                                delegate: Item {
                                    id: wsPill
                                    property bool isHovered: wsPillMouse.containsMouse
                                    property string stateLabel: model.wsState
                                    property string wsName: model.wsId
                                    readonly property bool isActive: stateLabel === "active"
                                    readonly property bool isOccupied: stateLabel === "occupied"
                                    // Guarded against `model` itself being transiently null
                                    // during the Repeater's initial model-population swap (a
                                    // real one-shot startup race, seen live as a single
                                    // "Value is null" TypeError at cold start) — harmless
                                    // once settled, but cheap to guard outright.
                                    // wsClasses is stored as a JSON STRING role (see wsReader) —
                                    // a raw array role gets silently turned into a nested
                                    // ListModel object by QML instead of staying a plain array.
                                    readonly property var wsClasses: {
                                        try { return JSON.parse((model && model.wsClasses) || "[]") } catch (e) { return [] }
                                    }
                                    // Up to 3 tiny app-icon glyphs (first letter of each window
                                    // class), only for occupied pills, only when the setting is on.
                                    readonly property int iconCount: (barWindow.topBarWorkspaceIconsEnabled && isOccupied && wsClasses.length > 0) ? Math.min(3, wsClasses.length) : 0
                                    readonly property int ecoLevel: (barWindow.ecoShow && barWindow.ecoByWs[wsName]) ? barWindow.ecoByWs[wsName].level : 0
                                    readonly property color ecoHex: ecoLevel === 2 ? "#74c7ec" : "#89dceb"
                                    readonly property var smartInfo: (barWindow.smartWsAutoNames === "always" && isActive) ? barWindow.smartWsWs[wsName] : undefined
                                    readonly property real smartExtra: smartInfo !== undefined ? smartTm.width + barWindow.s(18) : 0
                                    TextMetrics {
                                        id: smartTm
                                        text: wsPill.smartInfo !== undefined ? wsPill.smartInfo.name : ""
                                        font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Bold
                                    }

                                    width: isActive ? barWindow.s(46) + smartExtra : (isOccupied ? (barWindow.s(26) + iconCount * barWindow.s(12)) : barWindow.s(14))
                                    height: barWindow.s(34)
                                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

                                    property bool initAnimTrigger: false
                                    opacity: initAnimTrigger ? 1 : 0
                                    transform: Translate {
                                        y: wsPill.initAnimTrigger ? 0 : barWindow.s(15)
                                        Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
                                    }
                                    Component.onCompleted: {
                                        if (!barWindow.startupCascadeFinished) {
                                            animTimer.interval = index * 60;
                                            animTimer.start();
                                        } else {
                                            initAnimTrigger = true;
                                        }
                                    }
                                    Timer { id: animTimer; running: false; repeat: false; onTriggered: wsPill.initAnimTrigger = true }
                                    Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

                                    // ---- Workspace indicator, redesigned ----
                                    // Active: a wide gradient capsule (mauve→pink, same
                                    // family as the accent line/media pill) with a bright
                                    // WHITE outline for real contrast against the fill
                                    // (not a same-hue ring on a same-hue fill like before),
                                    // a soft two-layer glow behind it, and a quick pop-bounce
                                    // the moment it becomes active.
                                    // Occupied: a plain outlined pill showing the number,
                                    // no fill/glow — clearly a step down from active.
                                    // Empty: a tiny dim dot, no number, no border.
                                    property real popScale: 1.0
                                    onIsActiveChanged: if (isActive) { wsPopAnim.restart(); if (barWindow.isStartupReady) barWindow.fireFx("ws", 3000) }
                                    onIsHoveredChanged: {
                                        if (isHovered) wsGroupBox.hoveredIdx = index
                                        else if (wsGroupBox.hoveredIdx === index) wsGroupBox.hoveredIdx = -1
                                    }
                                    SequentialAnimation {
                                        id: wsPopAnim
                                        NumberAnimation { target: wsPill; property: "popScale"; to: 1.22; duration: 130; easing.type: Easing.OutCubic }
                                        NumberAnimation { target: wsPill; property: "popScale"; to: 1.0; duration: 280; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                                    }

                                    Rectangle {
                                        id: wsGlowOuter
                                        visible: wsPill.isActive
                                        anchors.centerIn: wsShape
                                        width: wsShape.width + barWindow.s(10)
                                        height: wsShape.height + barWindow.s(10)
                                        radius: height / 2
                                        z: -2
                                        color: Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.18)
                                    }
                                    Rectangle {
                                        id: wsGlowInner
                                        visible: wsPill.isActive
                                        anchors.centerIn: wsShape
                                        width: wsShape.width + barWindow.s(4)
                                        height: wsShape.height + barWindow.s(4)
                                        radius: height / 2
                                        z: -1
                                        color: Qt.rgba(mocha.pink.r, mocha.pink.g, mocha.pink.b, 0.26)
                                    }

                                    Rectangle {
                                        id: wsShape
                                        anchors.centerIn: parent
                                        width: wsPill.isActive ? barWindow.s(32) + wsPill.smartExtra : (wsPill.isOccupied ? (barWindow.s(22) + wsPill.iconCount * barWindow.s(12)) : barWindow.s(9))
                                        height: wsPill.isActive ? barWindow.s(22) : (wsPill.isOccupied ? barWindow.s(22) : barWindow.s(9))
                                        radius: height / 2
                                        scale: wsPill.popScale * (wsPill.isHovered && !wsPill.isActive ? 1.15 : 1.0)
                                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.7 } }
                                        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.7 } }
                                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

                                        color: wsPill.isActive
                                                ? "transparent"
                                                : (wsPill.isOccupied
                                                    ? (wsPill.isHovered
                                                        ? Qt.rgba(mocha.overlay2.r, mocha.overlay2.g, mocha.overlay2.b, 0.9)
                                                        : Qt.rgba(mocha.surface2.r, mocha.surface2.g, mocha.surface2.b, 0.85))
                                                    : Qt.rgba(mocha.overlay0.r, mocha.overlay0.g, mocha.overlay0.b, 0.3))
                                        Behavior on color { ColorAnimation { duration: 250 } }

                                        border.width: wsPill.isActive ? barWindow.s(1.4) : (wsPill.isOccupied ? 1 : 0)
                                        border.color: wsPill.isActive
                                                ? (wsPill.ecoLevel > 0 ? Qt.tint(Qt.rgba(1, 1, 1, 0.8), Qt.rgba(wsPill.ecoHex.r, wsPill.ecoHex.g, wsPill.ecoHex.b, 0.45)) : Qt.rgba(1, 1, 1, 0.8))
                                                : (wsPill.ecoLevel > 0 ? Qt.rgba(wsPill.ecoHex.r, wsPill.ecoHex.g, wsPill.ecoHex.b, 0.6) : (wsPill.isHovered ? mocha.text : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.2)))
                                        Behavior on border.color { ColorAnimation { duration: 250 } }

                                        Rectangle {
                                            id: wsEcoTint
                                            anchors.fill: parent
                                            radius: parent.radius
                                            visible: wsPill.ecoLevel > 0
                                            z: 3
                                            property real breathe: 1.0
                                            opacity: wsPill.ecoLevel === 1 ? breathe : 1.0
                                            SequentialAnimation on breathe {
                                                loops: Animation.Infinite
                                                running: wsEcoTint.visible && wsPill.ecoLevel === 1
                                                NumberAnimation { to: 0.55; duration: 2600; easing.type: Easing.InOutSine }
                                                NumberAnimation { to: 1.0; duration: 2600; easing.type: Easing.InOutSine }
                                            }
                                            gradient: Gradient {
                                                orientation: Gradient.Vertical
                                                GradientStop { position: 0.0; color: Qt.rgba(wsPill.ecoHex.r, wsPill.ecoHex.g, wsPill.ecoHex.b, wsPill.ecoLevel === 2 ? 0.38 : 0.2) }
                                                GradientStop { position: 0.55; color: Qt.rgba(wsPill.ecoHex.r, wsPill.ecoHex.g, wsPill.ecoHex.b, wsPill.ecoLevel === 2 ? 0.16 : 0.1) }
                                                GradientStop { position: 1.0; color: Qt.rgba(wsPill.ecoHex.r, wsPill.ecoHex.g, wsPill.ecoHex.b, wsPill.ecoLevel === 2 ? 0.22 : 0.12) }
                                            }
                                        }
                                        Rectangle {
                                            id: wsActiveFill
                                            anchors.fill: parent
                                            radius: parent.radius
                                            visible: wsPill.isActive
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: mocha.mauve }
                                                GradientStop { position: 1.0; color: mocha.pink }
                                            }
                                        }
                                        PillBg {
                                            kind: "tint"
                                            radius: wsShape.radius
                                            px: barWindow.s(1)
                                            tint: barWindow.classColor(wsPill.wsClasses.length > 0 ? wsPill.wsClasses[0] : "")
                                            shown: wsPill.isActive && barWindow.pillFxOn(barWindow.topBarWorkspaceTintMode, barWindow.fxFlash("ws"))
                                        }

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: barWindow.s(3)
                                            opacity: wsPill.ecoLevel === 2 ? 0.7 : 1
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: wsPill.isOccupied || wsPill.isActive
                                                text: wsPill.wsName
                                                font.family: "JetBrains Mono"
                                                font.pixelSize: barWindow.s(11)
                                                font.weight: Font.Bold
                                                color: wsPill.isActive
                                                        ? mocha.crust
                                                        : (wsPill.isHovered ? mocha.text : mocha.subtext0)
                                                Behavior on color { ColorAnimation { duration: 250 } }
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: wsPill.smartInfo !== undefined
                                                text: wsPill.smartInfo !== undefined ? wsPill.smartInfo.glyph + " " + wsPill.smartInfo.name : ""
                                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Bold
                                                color: mocha.crust
                                                opacity: 0.75
                                            }
                                            // App-icon-preview dots — first letter of each open
                                            // window's class, up to 3, occupied pills only.
                                            Repeater {
                                                model: wsPill.iconCount
                                                delegate: Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: barWindow.s(10); height: barWindow.s(10); radius: width / 2
                                                    color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, wsPill.isHovered ? 0.28 : 0.16)
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: (wsPill.wsClasses[index] || "?").charAt(0).toUpperCase()
                                                        font.family: "JetBrains Mono"
                                                        font.pixelSize: barWindow.s(7)
                                                        font.weight: Font.Bold
                                                        color: wsPill.isHovered ? mocha.text : mocha.subtext0
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    MouseArea {
                                        id: wsPillMouse
                                        hoverEnabled: true
                                        anchors.fill: parent
                                        onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh " + wsName])
                                    }
                                }
                            }
                        }
                    }            

                    // Claude account / key indicator — always minimal in the bar row,
                    // full label/type/email only in the acctTip hover card below
                    // (same reveal-on-hover pattern as batTip/weatherTip/clockTip).
                    Rectangle {
                        id: acctBox
                        color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                        radius: barWindow.s(14); border.width: 1
                        // Always-on echo of the shared cycling color, phase
                        // 0.08 — just behind wsGroupBox in the traveling
                        // breathe so the two nearest pills don't light up
                        // in perfect unison.
                        border.color: barWindow.topBarAccentLine
                            ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.12 + 0.24 * barWindow.ambientBreath(0.08)))
                            : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                        Layout.preferredHeight: parent.moduleHeight
                        Layout.preferredWidth: acctRowCompact.width + barWindow.s(20)
                        clip: true
                        bottomLeftRadius: (acctTip.visible && acctBox.hoverConfirmed) ? 0 : radius
                        bottomRightRadius: (acctTip.visible && acctBox.hoverConfirmed) ? 0 : radius

                        PillBg {
                            id: residentAcctBg
                            kind: barWindow.residentPillFlag.style === "border" ? "border" : "pulse"
                            radius: acctBox.radius
                            px: barWindow.s(1)
                            tint: barWindow.residentPillFlag.tint || "#cba6f7"
                            shown: barWindow.residentPillActive("account")
                        }
                        Connections {
                            target: barWindow
                            function onResidentPillBurstChanged() {
                                if (barWindow.residentPillFlag.pill !== "account") return
                                residentAcctBg.fire()
                                if (barWindow.residentPillFlag.open_card) {
                                    acctCloseGrace.stop()
                                    acctBox.hoverConfirmed = true
                                    acctForceOpenTimer.interval = Math.max(200, ((barWindow.residentPillFlag.expires_ts || 0) - Date.now() / 1000) * 1000)
                                    acctForceOpenTimer.restart()
                                }
                            }
                        }
                        Timer { id: acctForceOpenTimer; onTriggered: if (!acctBox.cardKeep) acctBox.hoverConfirmed = false }

                        property string acctLabel: ""
                        property string acctType: "account"
                        property string acctEmail: ""
                        property bool isHovered: acctMouse.containsMouse
                        readonly property color acctAccent: mocha.mauve

                        property bool hoverConfirmed: false
                        readonly property bool cardKeep: isHovered || acctTip.cardHovered
                        onCardKeepChanged: {
                            if (cardKeep) {
                                acctCloseGrace.stop()
                                if (!hoverConfirmed) acctHoverDelay.restart()
                            } else {
                                acctHoverDelay.stop()
                                acctCloseGrace.restart()
                            }
                        }
                        Timer { id: acctHoverDelay; interval: 1000; onTriggered: acctBox.hoverConfirmed = true }
                        Timer { id: acctCloseGrace; interval: 200; onTriggered: { acctHoverDelay.stop(); acctBox.hoverConfirmed = false } }

                        Process {
                            id: acctReader
                            command: ["bash", "-c", "jq -r '[.label // \"\", .type // \"account\", .email // \"\"] | @tsv' ~/.config/anthropic/current.json 2>/dev/null"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let p = this.text.trim().split("\t")
                                    acctBox.acctLabel = p[0] || ""
                                    acctBox.acctType = p[1] || "account"
                                    acctBox.acctEmail = p[2] || ""
                                }
                            }
                        }
                        Process {
                            id: acctWatch
                            running: true
                            command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "touch ~/.config/anthropic/current.json; exec inotifywait -qq -e close_write ~/.config/anthropic/current.json"]
                            onExited: { acctReader.running = true; running = true }
                        }
                        Component.onCompleted: acctReader.running = true

                        // Icon only — same collapse pattern as ClaudeStatus.qml's compact
                        // status dot. Full label/type/email lives in acctTip, one hover away.
                        Row {
                            id: acctRowCompact
                            anchors.centerIn: parent
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: barWindow.s(15)
                                color: acctBox.acctAccent
                                text: acctBox.acctType === "key" ? "󰌆" : "󰀄"
                            }
                        }
                        MouseArea {
                            id: acctMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/anthropic_acct.sh cycle silent"])
                        }
                    }

                    // Media Player
                    Rectangle {
                        id: mediaBox
                        color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                        radius: barWindow.s(14); border.width: 1
                        // Border echoes the bottom accent line's shared cycling
                        // color/beat system while a track is actually playing —
                        // same lighting language, event-triggered by playback
                        // rather than always-on, so it reads as "this pill is
                        // the one making the bar pulse" rather than a separate
                        // effect bolted on. Idle/paused has no meaningful signal
                        // to protect, so it gets the same quiet staggered
                        // breathe as the rest of the bar (phase 0.95, wrapping
                        // in right before wsGroupBox at 0.0) instead of going
                        // fully static.
                        readonly property color idleBorder: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                        readonly property real glowAmt: !barWindow.topBarAccentLine ? 0.0
                            : (barWindow.musicData.status === "Playing")
                                ? (0.16 + barWindow.beatPulse * 0.5)
                                : (0.06 + 0.14 * barWindow.ambientBreath(0.95))
                        border.color: Qt.tint(mediaBox.idleBorder, Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, mediaBox.glowAmt))
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                        Layout.preferredHeight: parent.moduleHeight
                        clip: true
                        bottomLeftRadius: (mediaCard.visible && mediaBox.hoverConfirmed) ? 0 : radius
                        bottomRightRadius: (mediaCard.visible && mediaBox.hoverConfirmed) ? 0 : radius

                        PillBg {
                            id: residentMediaBg
                            kind: barWindow.residentPillFlag.style === "border" ? "border" : "pulse"
                            radius: mediaBox.radius
                            px: barWindow.s(1)
                            tint: barWindow.residentPillFlag.tint || "#a6e3a1"
                            shown: barWindow.residentPillActive("media")
                        }
                        Connections {
                            target: barWindow
                            function onResidentPillBurstChanged() {
                                if (barWindow.residentPillFlag.pill !== "media") return
                                residentMediaBg.fire()
                                if (barWindow.residentPillFlag.open_card && barWindow.isMediaActive) {
                                    mediaCloseGrace.stop()
                                    mediaBox.hoverConfirmed = true
                                    mediaForceOpenTimer.interval = Math.max(200, ((barWindow.residentPillFlag.expires_ts || 0) - Date.now() / 1000) * 1000)
                                    mediaForceOpenTimer.restart()
                                }
                            }
                        }
                        Timer { id: mediaForceOpenTimer; onTriggered: if (!mediaBox.cardKeep) mediaBox.hoverConfirmed = false }

                        HoverHandler { id: mediaBoxHover }
                        readonly property bool cardKeep: barWindow.isMediaActive && (mediaBoxHover.hovered || mediaCard.cardHovered)
                        property bool hoverConfirmed: false
                        property real playerVol: 0
                        Timer { id: mediaHoverDelay; interval: 1000; onTriggered: mediaBox.hoverConfirmed = true }
                        Timer { id: mediaCloseGrace; interval: 200; onTriggered: { mediaHoverDelay.stop(); mediaBox.hoverConfirmed = false } }
                        Timer { interval: 1000; repeat: true; running: (mediaBox.hoverConfirmed || volWrap.hoverConfirmed) && !mediaVolMa.pressed; onTriggered: if (!mediaVolReader.running) mediaVolReader.running = true }
                        Process {
                            id: mediaVolReader
                            command: ["bash", "-c", "playerctl --player=spotify volume 2>/dev/null"]
                            stdout: StdioCollector {
                                onStreamFinished: { let v = parseFloat(this.text.trim()); if (!isNaN(v)) mediaBox.playerVol = v }
                            }
                        }
                        onCardKeepChanged: {
                            if (cardKeep) {
                                mediaCloseGrace.stop()
                                mediaVolReader.running = false; mediaVolReader.running = true
                                if (!hoverConfirmed) mediaHoverDelay.restart()
                            } else {
                                mediaHoverDelay.stop()
                                mediaCloseGrace.restart()
                            }
                        }
                        
                        property real targetWidth: barWindow.isMediaActive ? mediaLayoutContainer.width + barWindow.s(24) : 0
                        Layout.maximumWidth: targetWidth
                        Layout.preferredWidth: targetWidth
                        
                        visible: targetWidth > 0 || opacity > 0
                        opacity: barWindow.isMediaActive ? 1.0 : 0.0

                        Behavior on targetWidth { NumberAnimation { duration: 700; easing.type: Easing.OutQuint } }
                        Behavior on opacity { NumberAnimation { duration: 400 } }

                        // Audio-reactive equalizer background — real RMS level
                        // (barWindow.mediaAudioLevel) sets the overall amplitude,
                        // per-bar phase offsets give it a "live" multi-band look.
                        // Kept behind all text/art so it never fights legibility.
                        // Colored from the actual album-art palette (mediaBc1/
                        // mediaBc2), blended per-bar-position rather than a flat
                        // repeated 2-stop gradient, plus a soft blurred colour
                        // wash underneath for a cohesive "alive" background.
                        //
                        // Kept clear of the rounded corners by insetting left/right
                        // by the pill's own radius, rather than a MultiEffect mask —
                        // a mask here turned out fragile (rendered blank in practice,
                        // verified live: real audio level + nonzero geometry, but
                        // nothing painted). A plain inset is simple and guaranteed
                        // to render every time.
                        Item {
                            id: mediaVizLayer
                            visible: barWindow.mediaVisualizerEnabled
                            anchors.fill: parent
                            anchors.leftMargin: mediaBox.radius
                            anchors.rightMargin: mediaBox.radius

                            // Soft blurred colour wash behind the bars — a single
                            // blur layer (not stacked with others) keyed to the
                            // song palette so the whole pill background feels
                            // like a living gradient, not just bar shapes.
                            Rectangle {
                                id: mediaVizGlow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: barWindow.s(5)
                                height: barWindow.s(30)
                                opacity: barWindow.musicData.status === "Playing" ? (0.22 + 0.18 * barWindow.mediaVizAmplitude) : 0.0
                                Behavior on opacity { NumberAnimation { duration: 500 } }
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: barWindow.mediaBc1 }
                                    GradientStop { position: 0.5; color: barWindow.mediaBc2 }
                                    GradientStop { position: 1.0; color: barWindow.mediaBc1 }
                                }
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    blurEnabled: true
                                    blur: 1.0
                                    blurMax: 48
                                }
                            }

                            Row {
                                id: mediaVizRow
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottomMargin: barWindow.s(5)
                                height: parent.height - barWindow.s(5)
                                spacing: barWindow.s(3)
                                opacity: barWindow.musicData.status === "Playing" ? 0.5 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 500 } }

                                property real phase: 0
                                NumberAnimation on phase {
                                    from: 0; to: Math.PI * 2
                                    duration: 3200
                                    loops: Animation.Infinite
                                    // Only drives the "pulse" sine-fake below — pointless
                                    // per-frame work in "fft" mode, where real per-band
                                    // levels are used instead and this is never read.
                                    running: barWindow.musicData.status === "Playing" && barWindow.mediaVisualizerMode !== "fft"
                                }

                                Repeater {
                                    model: 14
                                    delegate: Item {
                                        width: (mediaVizRow.width - barWindow.s(3) * 13) / 14
                                        height: parent.height
                                        anchors.bottom: parent.bottom

                                        // "fft" = each bar is its own real frequency band
                                        // (audio_spectrum.py); "pulse" = single RMS scalar
                                        // with a per-bar sine phase-offset faking motion.
                                        property real fftLevel: barWindow.mediaSpectrumLevels[index] || 0
                                        Behavior on fftLevel { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
                                        property real barHeight: barWindow.mediaVisualizerMode === "fft"
                                            ? barWindow.s(4) + barWindow.s(30) * fftLevel
                                            : barWindow.s(4) + (barWindow.s(30) * Math.sqrt(barWindow.mediaAudioLevel) *
                                                (0.35 + 0.65 * Math.abs(Math.sin(mediaVizRow.phase * (1.0 + (index % 4) * 0.35) + index * 0.9))))

                                        // Classic spectrum-analyzer peak-hold — snaps up
                                        // instantly with the bar, falls back slowly on its
                                        // own. fft-only: pulse's sine-fake motion has no
                                        // real "peak" to hold, it'd just chase the wave.
                                        property real peakLevel: 0
                                        onFftLevelChanged: if (fftLevel > peakLevel) peakLevel = fftLevel
                                        Timer {
                                            interval: 50
                                            repeat: true
                                            running: barWindow.mediaVisualizerMode === "fft" && barWindow.musicData.status === "Playing"
                                            onTriggered: parent.peakLevel = Math.max(parent.fftLevel, parent.peakLevel - 0.018)
                                        }

                                        // Blend across the row's x-position (not just
                                        // a flat vertical gradient repeated per bar)
                                        // so the equalizer reads as one continuous
                                        // colour sweep rather than 14 identical bars.
                                        property real t: index / 13

                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: parent.barHeight
                                            radius: width / 2
                                            gradient: Gradient {
                                                orientation: Gradient.Vertical
                                                GradientStop { position: 0.0; color: Qt.tint(barWindow.mediaBc2, Qt.rgba(barWindow.mediaBc1.r, barWindow.mediaBc1.g, barWindow.mediaBc1.b, parent.parent.t * 0.5)) }
                                                GradientStop { position: 1.0; color: Qt.tint(barWindow.mediaBc1, Qt.rgba(barWindow.mediaBc2.r, barWindow.mediaBc2.g, barWindow.mediaBc2.b, (1.0 - parent.parent.t) * 0.5)) }
                                            }
                                        }
                                        Rectangle {
                                            visible: barWindow.mediaVisualizerMode === "fft" && barWindow.mediaVisualizerPeakHoldEnabled && parent.peakLevel > 0.02
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: barWindow.s(4) + barWindow.s(30) * parent.peakLevel
                                            width: parent.width
                                            height: barWindow.s(1.5)
                                            radius: height / 2
                                            color: mocha.text
                                            opacity: 0.7
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            id: mediaLayoutContainer
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: barWindow.s(16)
                            height: parent.height
                            width: innerMediaLayout.width
                            
                            opacity: barWindow.isMediaActive ? 1.0 : 0.0
                            transform: Translate { 
                                x: barWindow.isMediaActive ? 0 : barWindow.s(-20) 
                                Behavior on x { NumberAnimation { duration: 700; easing.type: Easing.OutQuint } }
                            }
                            Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

                            Row {
                                id: innerMediaLayout
                                anchors.verticalCenter: parent.verticalCenter
                                // Dynamically reduce spacing between song info and controls on smaller screens
                                spacing: barWindow.width < 1920 ? barWindow.s(8) : barWindow.s(16)
                                
                                MouseArea {
                                    id: mediaInfoMouse
                                    width: infoLayout.width
                                    height: innerMediaLayout.height
                                    hoverEnabled: true
                                    onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle music"])
                                    
                                    Row {
                                        id: infoLayout
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: barWindow.s(10)
                                        
                                        scale: mediaInfoMouse.containsMouse ? 1.02 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

                                        Item {
                                            width: barWindow.s(32); height: barWindow.s(32)

                                            // Thin glowing ring, pulsing in sync with the real
                                            // song BPM. Fixed lavender hex fallback (never a
                                            // matugen name for glow semantics), prefers the
                                            // song's own extracted accent colors when available.
                                            Rectangle {
                                                anchors.centerIn: parent
                                                visible: barWindow.bpmRingActive
                                                readonly property color ringColor: barWindow.mediaBc1 || "#b4befe"
                                                width: parent.width * 1.6
                                                height: width
                                                radius: height / 2
                                                color: "transparent"
                                                border.width: barWindow.s(1)
                                                border.color: Qt.rgba(ringColor.r, ringColor.g, ringColor.b, 0.12 + 0.18 * barWindow.bpmRingPulse)
                                            }

                                            Rectangle {
                                                anchors.centerIn: parent
                                                visible: barWindow.bpmRingActive
                                                readonly property color ringColor: barWindow.mediaBc1 || "#b4befe"
                                                width: parent.width + barWindow.s(8) + barWindow.s(6) * barWindow.bpmRingPulse
                                                height: width
                                                radius: height / 2
                                                color: "transparent"
                                                border.width: barWindow.s(2.5)
                                                border.color: Qt.rgba(ringColor.r, ringColor.g, ringColor.b, 0.85 - 0.5 * barWindow.bpmRingPulse)
                                            }

                                            Rectangle {
                                                // Circular, matching the ring around it. Plain
                                                // `radius: width/2` + `layer.enabled` on the
                                                // Rectangle does NOT actually clip a child Image
                                                // to the rounded shape in this Qt/Quickshell
                                                // build (confirmed — still rendered square) —
                                                // MultiEffect's mask does the real crop, same
                                                // module already used for mediaVizGlow's blur
                                                // above, no new import needed.
                                                id: artFrame
                                                anchors.fill: parent
                                                radius: width / 2; color: mocha.surface1

                                                Item {
                                                    id: artMaskSource
                                                    anchors.fill: parent
                                                    layer.enabled: true
                                                    visible: false
                                                    Rectangle { anchors.fill: parent; radius: width / 2; color: "white" }
                                                }
                                                Item {
                                                    anchors.fill: parent
                                                    layer.enabled: true
                                                    layer.effect: MultiEffect { maskEnabled: true; maskSource: artMaskSource }
                                                    Image {
                                                        anchors.fill: parent
                                                        source: barWindow.musicData.artUrl ? "file://" + barWindow.musicData.artUrl : ""
                                                        fillMode: Image.PreserveAspectCrop
                                                    }
                                                    Rectangle {
                                                        anchors.fill: parent
                                                        color: Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.2)
                                                    }
                                                }

                                                // Border drawn AFTER the masked Image, as a
                                                // transparent-fill overlay — a Rectangle's own
                                                // border paints UNDER a later sibling that fills
                                                // the same rect (same "canvas covers border"
                                                // gotcha this project already hit elsewhere), so
                                                // setting border.* directly on artFrame above got
                                                // completely painted over by the mask layer.
                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: width / 2
                                                    color: "transparent"
                                                    border.width: barWindow.musicData.status === "Playing" ? barWindow.s(1.5) : barWindow.s(1)
                                                    border.color: barWindow.musicData.status === "Playing"
                                                        ? mocha.mauve
                                                        : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.35)
                                                    Behavior on border.color { ColorAnimation { duration: 300 } }
                                                }
                                            }
                                        }
                                        Column {
                                            spacing: -2
                                            anchors.verticalCenter: parent.verticalCenter
                                            // Make column explicitly sized to enforce elide truncating on text
                                            property real maxColWidth: barWindow.width < 1920 ? barWindow.s(120) : barWindow.s(180)
                                            width: maxColWidth 
                                            
                                            Text { 
                                                text: barWindow.musicData.title; 
                                                font.family: "JetBrains Mono"; 
                                                font.weight: Font.Black; 
                                                font.pixelSize: barWindow.s(13); 
                                                color: mocha.text;
                                                width: parent.width
                                                elide: Text.ElideRight; 
                                            }
                                            Text { 
                                                text: barWindow.musicData.timeStr; 
                                                font.family: "JetBrains Mono"; 
                                                font.weight: Font.Black; 
                                                font.pixelSize: barWindow.s(10); 
                                                color: mocha.subtext0;
                                                width: parent.width
                                                elide: Text.ElideRight;
                                            }
                                        }
                                    }
                                }

                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: barWindow.width < 1920 ? barWindow.s(4) : barWindow.s(8)
                                    Item { 
                                        width: barWindow.s(24); height: barWindow.s(24); 
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text { 
                                            anchors.centerIn: parent; text: "󰒮"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(26); 
                                            color: prevMouse.containsMouse ? mocha.text : mocha.overlay2; 
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            scale: prevMouse.containsMouse ? 1.1 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        }
                                        MouseArea { id: prevMouse; hoverEnabled: true; anchors.fill: parent; onClicked: { Quickshell.execDetached(["playerctl", "--player=spotify", "previous"]); barWindow.requestMusicRefresh(); } }
                                    }
                                    Item { 
                                        width: barWindow.s(28); height: barWindow.s(28); 
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text { 
                                            anchors.centerIn: parent; text: barWindow.musicData.status === "Playing" ? "󰏤" : "󰐊"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(30); 
                                            color: playMouse.containsMouse ? mocha.green : mocha.text; 
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            scale: playMouse.containsMouse ? 1.15 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        }
                                        MouseArea { id: playMouse; hoverEnabled: true; anchors.fill: parent; onClicked: { let d = Object.assign({}, barWindow.musicData); d.status = d.status === "Playing" ? "Paused" : "Playing"; barWindow.musicData = d; Quickshell.execDetached(["playerctl", "--player=spotify", "play-pause"]); barWindow.requestMusicRefresh(); } }
                                    }
                                    Item { 
                                        width: barWindow.s(24); height: barWindow.s(24); 
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text { 
                                            anchors.centerIn: parent; text: "󰒭"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(26); 
                                            color: nextMouse.containsMouse ? mocha.text : mocha.overlay2; 
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            scale: nextMouse.containsMouse ? 1.1 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        }
                                        MouseArea { id: nextMouse; hoverEnabled: true; anchors.fill: parent; onClicked: { Quickshell.execDetached(["playerctl", "--player=spotify", "next"]); barWindow.requestMusicRefresh(); } }
                                    }
                                }
                            }
                        }
                    }
                    
                    // DYNAMIC SPACER: Pushes everything tightly to the left side
                    Item { Layout.fillWidth: true } 
                }

                Item {
                    id: claudeTipState
                    property bool hoverConfirmed: false
                    readonly property bool cardKeep: claudeStatus.hovered || claudeCard.cardHovered
                    Timer { id: claudeTipDelay; interval: 1000; onTriggered: claudeTipState.hoverConfirmed = true }
                    Timer { id: claudeTipGrace; interval: 200; onTriggered: { claudeTipDelay.stop(); claudeTipState.hoverConfirmed = false } }
                    onCardKeepChanged: {
                        if (cardKeep) {
                            claudeTipGrace.stop()
                            if (!hoverConfirmed) claudeTipDelay.restart()
                        } else {
                            claudeTipDelay.stop()
                            claudeTipGrace.restart()
                        }
                    }
                    Connections {
                        target: barWindow
                        function onResidentPillBurstChanged() {
                            if (barWindow.residentPillFlag.pill !== "claude" || !barWindow.residentPillFlag.open_card) return
                            claudeTipGrace.stop()
                            claudeTipState.hoverConfirmed = true
                            claudeForceOpenTimer.interval = Math.max(200, ((barWindow.residentPillFlag.expires_ts || 0) - Date.now() / 1000) * 1000)
                            claudeForceOpenTimer.restart()
                        }
                    }
                    Timer { id: claudeForceOpenTimer; onTriggered: if (!claudeTipState.cardKeep) claudeTipState.hoverConfirmed = false }
                }

                Rectangle {
                    id: residentGlow
                    visible: residentCard.visible && !residentCard.isDetached
                    x: residentCard.x - barWindow.s(2)
                    y: residentCard.y
                    width: residentCard.width + barWindow.s(4)
                    height: residentCard.height + barWindow.s(3)
                    radius: barWindow.s(16)
                    color: "transparent"
                    border.width: barWindow.s(2)
                    border.color: Qt.rgba(residentCard.accent.r, residentCard.accent.g, residentCard.accent.b, 0.16 + 0.22 * residentCard.pulse)
                    opacity: residentCard.opacity
                    z: 109
                }

                Rectangle {
                    id: residentCard
                    readonly property var cur: barWindow.residentCur
                    property var disp: null
                    onCurChanged: if (cur) disp = cur
                    readonly property bool shown: barWindow.residentCardsEnabled && cur !== null
                    readonly property bool isWrapped: disp !== null && disp.kind === "wrapped"
                    readonly property bool isNowPlaying: disp !== null && disp.kind === "nowplaying"
                    readonly property bool isCalendar: disp !== null && disp.kind === "calendar"
                    readonly property bool isBatteryHealth: disp !== null && disp.kind === "batteryhealth"
                    readonly property bool isUptimeGuilt: disp !== null && disp.kind === "uptimeguilt"
                    readonly property bool isFocusDone: disp !== null && disp.kind === "focusdone"
                    readonly property bool isBrief: disp !== null && disp.kind === "brief"
                    readonly property string briefPeriod: isBrief && disp.data && disp.data.period ? disp.data.period : ""
                    readonly property bool isGitPush: disp !== null && disp.kind === "gitpush"
                    readonly property bool isTailscale: disp !== null && disp.kind === "tailscale"
                    readonly property bool isArtKind: isWrapped || isNowPlaying
                    readonly property bool isDetached: isArtKind || isCalendar || isBatteryHealth || isUptimeGuilt || isFocusDone || isBrief || isGitPush || isTailscale
                    readonly property var kindData: isDetached && disp.data ? disp.data : ({})
                    readonly property var kindActions: isDetached && disp.actions ? disp.actions : []
                    function runKindAction(cmd) {
                        if (cmd) Quickshell.execDetached(["bash", "-c", cmd])
                        barWindow.residentDismiss()
                    }
                    readonly property color accent: disp && disp.urgency === "high" ? "#f38ba8" : (disp && disp.urgency === "low" ? "#89dceb" : "#cba6f7")
                    readonly property bool cardHovered: rcHover.hovered
                    readonly property bool historyOpen: barWindow.residentHistoryPinned || rcBadgeHover.hovered
                    property real pulse: 0
                    SequentialAnimation on pulse {
                        running: residentCard.shown && residentCard.disp !== null && residentCard.disp.urgency === "high"
                        loops: Animation.Infinite
                        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0; duration: 900; easing.type: Easing.InOutSine }
                    }
                    visible: shown || opacity > 0.01
                    opacity: shown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Top
                    scale: shown ? 1 : 0.92
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                    x: Math.round(centerBox.x + (centerBox.width - width) / 2)
                    y: Math.round(centerBox.y + centerBox.height + (isDetached ? barWindow.s(8) : -barWindow.s(1)))
                    width: isDetached ? Math.max(centerBox.width, barWindow.s(430)) : centerBox.width
                    height: isArtKind ? barWindow.s(150)
                        : isCalendar ? rcCalendar.implicitHeight
                        : isBatteryHealth ? rcBatteryHealth.implicitHeight
                        : isUptimeGuilt ? rcUptime.implicitHeight
                        : isFocusDone ? rcFocusDone.implicitHeight
                        : isGitPush ? rcGit.implicitHeight
                        : isTailscale ? rcTailscale.implicitHeight
                        : briefPeriod === "afternoon" ? rcBriefAfternoon.implicitHeight
                        : briefPeriod === "night" ? rcBriefNight.implicitHeight
                        : isBrief ? rcBriefMorning.implicitHeight
                        : rcCol.implicitHeight + barWindow.s(20)
                    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    radius: isArtKind ? barWindow.s(26) : (isDetached ? barWindow.s(18) : barWindow.s(14))
                    topLeftRadius: isDetached ? radius : 0
                    topRightRadius: isDetached ? radius : 0
                    color: isDetached ? "transparent" : barWindow.cardFill
                    border.width: isDetached ? 0 : 1
                    border.color: Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(accent.r, accent.g, accent.b, 0.22 + 0.2 * pulse))
                    clip: !isDetached
                    z: 110

                    Rectangle {
                        visible: !residentCard.isDetached
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                        height: parent.height * 0.6
                        opacity: 0.07
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: residentCard.accent }
                        }
                    }
                    Rectangle {
                        visible: !residentCard.isDetached
                        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                        height: barWindow.s(2)
                        color: residentCard.accent
                        opacity: 0.75
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.MiddleButton | Qt.RightButton
                        onClicked: barWindow.residentDismiss()
                    }
                    HoverHandler { id: rcHover }

                    Column {
                        id: rcCol
                        visible: !residentCard.isDetached
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.leftMargin: barWindow.s(14); anchors.rightMargin: barWindow.s(12)
                        anchors.topMargin: barWindow.s(10)
                        spacing: barWindow.s(6)

                        Item {
                            id: rcHeader
                            width: parent.width
                            height: barWindow.s(24)
                            Row {
                                id: rcHeadLeft
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: barWindow.s(8)
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: barWindow.residentGlyph(residentCard.disp ? residentCard.disp.icon : "")
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16)
                                    color: residentCard.accent
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(barWindow.s(40), rcHeader.width - x - rcHeadRight.width - barWindow.s(6))
                                    text: residentCard.disp ? residentCard.disp.title : ""
                                    elide: Text.ElideRight
                                    font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Black
                                    color: mocha.text
                                }
                            }
                            Row {
                                id: rcHeadRight
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: barWindow.s(6)
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: residentCard.disp !== null && !!residentCard.disp.source
                                    width: srcText.implicitWidth + barWindow.s(10); height: barWindow.s(15); radius: height / 2
                                    color: Qt.rgba(residentCard.accent.r, residentCard.accent.g, residentCard.accent.b, 0.16)
                                    Text {
                                        id: srcText
                                        anchors.centerIn: parent
                                        text: residentCard.disp ? String(residentCard.disp.source || "") : ""
                                        font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(8); font.weight: Font.Bold
                                        color: residentCard.accent
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: barWindow.residentQueue.length < 2
                                    text: { barWindow.residentAgeTick; return residentCard.disp ? barWindow.residentAgeStr(residentCard.disp.ts) : "" }
                                    font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9)
                                    color: mocha.subtext0
                                }
                                Rectangle {
                                    id: rcBadge
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: barWindow.residentQueue.length > 1 || barWindow.residentHistory.length > 0
                                    width: badgeText.implicitWidth + barWindow.s(10); height: barWindow.s(16); radius: height / 2
                                    color: residentCard.historyOpen ? Qt.rgba(residentCard.accent.r, residentCard.accent.g, residentCard.accent.b, 0.3) : Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.7)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text {
                                        id: badgeText
                                        anchors.centerIn: parent
                                        text: barWindow.residentQueue.length > 1 ? "+" + (barWindow.residentQueue.length - 1) : "\udb80\udeda"
                                        font.family: barWindow.residentQueue.length > 1 ? "JetBrains Mono" : "Iosevka Nerd Font"
                                        font.pixelSize: barWindow.s(9); font.weight: Font.Bold
                                        color: mocha.text
                                    }
                                    HoverHandler { id: rcBadgeHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: barWindow.residentHistoryPinned = !barWindow.residentHistoryPinned
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: barWindow.residentQueue.length > 1
                                    text: "\udb80\udd41"
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(14)
                                    color: prevMouse2.containsMouse ? mocha.text : mocha.subtext0
                                    MouseArea { id: prevMouse2; anchors.fill: parent; anchors.margins: -barWindow.s(3); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: barWindow.residentNav(-1) }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: barWindow.residentQueue.length > 1
                                    text: "\udb80\udd42"
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(14)
                                    color: nextMouse2.containsMouse ? mocha.text : mocha.subtext0
                                    MouseArea { id: nextMouse2; anchors.fill: parent; anchors.margins: -barWindow.s(3); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: barWindow.residentNav(1) }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "\udb80\udd56"
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(14)
                                    color: closeMouse2.containsMouse ? "#f38ba8" : mocha.subtext0
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    MouseArea { id: closeMouse2; anchors.fill: parent; anchors.margins: -barWindow.s(3); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: barWindow.residentDismiss() }
                                }
                            }
                        }

                        Item {
                            id: rcBodyWrap
                            visible: !residentCard.historyOpen
                            width: parent.width
                            height: visible ? Math.min(rcBodyText.implicitHeight, barWindow.residentMaxBody) : 0
                            Flickable {
                                id: rcFlick
                                anchors.fill: parent
                                clip: true
                                contentWidth: width
                                contentHeight: rcBodyText.implicitHeight
                                boundsBehavior: Flickable.StopAtBounds
                                Text {
                                    id: rcBodyText
                                    width: rcFlick.width - barWindow.s(8)
                                    text: residentCard.disp ? String(residentCard.disp.body || "") : ""
                                    textFormat: Text.PlainText
                                    wrapMode: Text.Wrap
                                    font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12)
                                    lineHeight: 1.15
                                    color: mocha.text
                                }
                            }
                            Rectangle {
                                visible: rcFlick.contentHeight > rcFlick.height + 1
                                anchors.right: parent.right
                                width: barWindow.s(3); radius: width / 2
                                y: rcFlick.visibleArea.yPosition * rcFlick.height
                                height: Math.max(barWindow.s(14), rcFlick.visibleArea.heightRatio * rcFlick.height)
                                color: Qt.rgba(residentCard.accent.r, residentCard.accent.g, residentCard.accent.b, 0.55)
                            }
                        }

                        Item {
                            id: rcHistWrap
                            visible: residentCard.historyOpen
                            width: parent.width
                            height: visible ? Math.min(rcHistCol.implicitHeight, barWindow.residentMaxBody) : 0
                            Flickable {
                                anchors.fill: parent
                                clip: true
                                contentWidth: width
                                contentHeight: rcHistCol.implicitHeight
                                boundsBehavior: Flickable.StopAtBounds
                                Column {
                                    id: rcHistCol
                                    width: parent.width
                                    spacing: barWindow.s(2)
                                    Text {
                                        visible: barWindow.residentHistory.length === 0
                                        text: "no earlier cards"
                                        font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11)
                                        color: mocha.subtext0
                                    }
                                    Repeater {
                                        model: barWindow.residentHistory
                                        delegate: Rectangle {
                                            width: rcHistCol.width; height: barWindow.s(24); radius: barWindow.s(6)
                                            color: histMouse.containsMouse ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.7) : "transparent"
                                            Text {
                                                anchors.left: parent.left; anchors.leftMargin: barWindow.s(6)
                                                anchors.right: histAge.left; anchors.rightMargin: barWindow.s(6)
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.title
                                                elide: Text.ElideRight
                                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11)
                                                color: mocha.text
                                            }
                                            Text {
                                                id: histAge
                                                anchors.right: parent.right; anchors.rightMargin: barWindow.s(6)
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: { barWindow.residentAgeTick; return barWindow.residentAgeStr(modelData.ts) }
                                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9)
                                                color: mocha.subtext0
                                            }
                                            MouseArea { id: histMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: barWindow.residentRecall(modelData) }
                                        }
                                    }
                                }
                            }
                        }

                        Flow {
                            id: rcActions
                            visible: residentCard.disp !== null && !!residentCard.disp.actions && residentCard.disp.actions.length > 0 && !residentCard.historyOpen
                            width: parent.width
                            spacing: barWindow.s(6)
                            Repeater {
                                model: residentCard.disp && residentCard.disp.actions ? residentCard.disp.actions : []
                                delegate: Rectangle {
                                    width: actText.implicitWidth + barWindow.s(18); height: barWindow.s(24); radius: height / 2
                                    color: actMouse.containsMouse ? residentCard.accent : Qt.rgba(residentCard.accent.r, residentCard.accent.g, residentCard.accent.b, 0.2)
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Text {
                                        id: actText
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); font.weight: Font.Bold
                                        color: actMouse.containsMouse ? mocha.crust : mocha.text
                                    }
                                    MouseArea {
                                        id: actMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { Quickshell.execDetached(["bash", "-c", modelData.cmd]); barWindow.residentDismiss() }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: barWindow.residentHoldSecs > 0 && !residentCard.isDetached
                        anchors.left: parent.left; anchors.bottom: parent.bottom
                        height: barWindow.s(2)
                        width: parent.width * Math.max(0, 1 - barWindow.residentHoldElapsed / Math.max(0.1, barWindow.residentHoldSecs))
                        color: residentCard.accent
                        opacity: 0.8
                    }

                    Item {
                        id: rcWrapped
                        anchors.fill: parent
                        visible: residentCard.isArtKind
                        readonly property var wd: residentCard.isArtKind && residentCard.disp.data ? residentCard.disp.data : ({})
                        readonly property var arts: wd.arts || []
                        readonly property var pal: {
                            let m = String(wd.grad || "").match(/#[0-9a-fA-F]{6}/g)
                            return m && m.length >= 2 ? [m[0], m[1]] : [String(mocha.mauve), String(mocha.blue)]
                        }
                        readonly property bool live: residentCard.shown && residentCard.isArtKind
                        property int panel: 0
                        property real fill: 0
                        property real prog: 0
                        property real fan: 0
                        onLiveChanged: if (live) { panel = 0; fill = 0; rcWrapIn.restart() }
                        onPanelChanged: fill = 0
                        SequentialAnimation {
                            id: rcWrapIn
                            PropertyAction { target: rcWrapped; property: "fan"; value: 0 }
                            PropertyAction { target: rcWrapped; property: "prog"; value: 0 }
                            PauseAnimation { duration: 160 }
                            ParallelAnimation {
                                NumberAnimation { target: rcWrapped; property: "fan"; to: 1; duration: 700; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                                NumberAnimation { target: rcWrapped; property: "prog"; to: 1; duration: 1100; easing.type: Easing.OutCubic }
                            }
                        }
                        Timer {
                            interval: 30; repeat: true
                            running: rcWrapped.live && !residentCard.cardHovered
                            onTriggered: {
                                rcWrapped.fill += 30 / 3400
                                if (rcWrapped.fill >= 1) rcWrapped.panel = (rcWrapped.panel + 1) % 3
                            }
                        }
                        function openWrapped() {
                            let acts = residentCard.disp && residentCard.disp.actions ? residentCard.disp.actions : []
                            if (acts.length > 0) Quickshell.execDetached(["bash", "-c", acts[0].cmd])
                            barWindow.residentDismiss()
                        }

                        WrappedBackdrop {
                            id: rcWrapBg
                            anchors.fill: parent
                            radius: residentCard.radius
                            bedSpread: barWindow.s(10)
                            from1: rcWrapped.pal[0]
                            from2: rcWrapped.pal[1]
                            art: rcWrapped.arts.length > 0 ? rcWrapped.arts[0] : ""
                            live: rcWrapped.live
                            wash: 0.5
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: rcWrapped.openWrapped()
                        }

                        Row {
                            id: rcWrapBars
                            anchors.top: parent.top; anchors.topMargin: barWindow.s(10)
                            anchors.left: rcWrapText.left
                            anchors.right: parent.right; anchors.rightMargin: barWindow.s(40)
                            height: barWindow.s(3)
                            spacing: barWindow.s(4)
                            Repeater {
                                model: 3
                                delegate: Rectangle {
                                    width: (rcWrapBars.width - rcWrapBars.spacing * 2) / 3
                                    height: parent.height; radius: height / 2
                                    color: Qt.alpha(rcWrapBg.ink, 0.25)
                                    Rectangle {
                                        height: parent.height; radius: parent.radius
                                        color: rcWrapBg.ink
                                        width: parent.width * (index < rcWrapped.panel ? 1 : (index === rcWrapped.panel ? rcWrapped.fill : 0))
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.right: parent.right; anchors.rightMargin: barWindow.s(12)
                            anchors.verticalCenter: rcWrapBars.verticalCenter
                            text: "󰅖"
                            font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(14)
                            color: rcWrapClose.containsMouse ? rcWrapBg.ink : Qt.alpha(rcWrapBg.ink, 0.6)
                            scale: rcWrapClose.containsMouse ? 1.2 : 1
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            MouseArea { id: rcWrapClose; anchors.fill: parent; anchors.margins: -barWindow.s(5); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: barWindow.residentDismiss() }
                        }

                        Item {
                            id: rcWrapFan
                            anchors.left: parent.left; anchors.leftMargin: barWindow.s(20)
                            anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: barWindow.s(4)
                            width: barWindow.s(94); height: width
                            Repeater {
                                model: Math.min(3, rcWrapped.arts.length)
                                delegate: WrappedArt {
                                    z: 3 - index
                                    width: rcWrapFan.width; height: width
                                    radius: barWindow.s(16)
                                    art: rcWrapped.arts[index]
                                    fallback: Qt.alpha(rcWrapBg.ink, 0.14)
                                    shadowColor: Qt.alpha(rcWrapBg.deep, 0.45)
                                    shadowOffset: barWindow.s(5)
                                    edge: Qt.alpha(rcWrapBg.ink, 0.28)
                                    property real spread: residentCard.cardHovered ? 1.5 : 1
                                    Behavior on spread { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
                                    rotation: [-5, 7, 16][index] * rcWrapped.fan * spread
                                    x: [0, barWindow.s(10), barWindow.s(19)][index] * rcWrapped.fan * spread
                                    scale: [1, 0.9, 0.8][index]
                                    opacity: [1, 0.82, 0.62][index]
                                }
                            }
                        }

                        Column {
                            id: rcWrapText
                            anchors.left: rcWrapFan.right; anchors.leftMargin: barWindow.s(32)
                            anchors.right: parent.right; anchors.rightMargin: barWindow.s(16)
                            anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: barWindow.s(4)
                            spacing: barWindow.s(6)

                            Rectangle {
                                width: rcWrapEyebrow.implicitWidth + barWindow.s(14)
                                height: barWindow.s(17)
                                radius: height / 2
                                color: Qt.alpha(rcWrapBg.ink, 0.16)
                                border.width: 1; border.color: Qt.alpha(rcWrapBg.ink, 0.22)
                                Text {
                                    id: rcWrapEyebrow
                                    anchors.centerIn: parent
                                    text: residentCard.isNowPlaying ? "REPLAY MILESTONE · #" + (rcWrapped.wd.rank || 1) + " ALL-TIME" : (rcWrapped.wd.period === "month" ? "YOUR MONTHLY WRAPPED" : "YOUR WEEKLY WRAPPED")
                                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: barWindow.s(8); font.letterSpacing: barWindow.s(1)
                                    color: rcWrapBg.ink
                                }
                            }

                            Item {
                                width: parent.width
                                height: barWindow.s(44)
                                Repeater {
                                    model: 3
                                    delegate: Column {
                                        id: rcWrapPanel
                                        width: parent.width
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 0
                                        readonly property bool active: rcWrapped.panel === index
                                        opacity: active ? 1 : 0
                                        property real shift: active ? 0 : (index < rcWrapped.panel ? -barWindow.s(18) : barWindow.s(18))
                                        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                        Behavior on shift { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                                        transform: Translate { x: rcWrapPanel.shift }
                                        Text {
                                            width: parent.width
                                            text: residentCard.isNowPlaying
                                                ? (index === 0 ? "all-time plays" : (index === 1 ? "on repeat · " + (rcWrapped.wd.artist || "") : "listened · since " + (rcWrapped.wd.firstStr || "")))
                                                : (index === 0 ? "listened · last " + Math.max(1, Math.round(rcWrapped.wd.spanDays || 1)) + (Math.round(rcWrapped.wd.spanDays || 1) > 1 ? " days" : " day")
                                                : (index === 1 ? "#1 artist · " + (rcWrapped.wd.topArtistCount || 0) + " plays" : "#1 track · " + (rcWrapped.wd.topTrackArtist || "")))
                                            elide: Text.ElideRight
                                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: barWindow.s(10)
                                            color: Qt.alpha(rcWrapBg.ink, 0.8)
                                        }
                                        Text {
                                            width: parent.width
                                            text: {
                                                if (residentCard.isNowPlaying) {
                                                    if (index === 0) return Math.round((rcWrapped.wd.count || 0) * rcWrapped.prog) + " plays"
                                                    if (index === 1) return rcWrapped.wd.title || "—"
                                                    let n = Math.round((rcWrapped.wd.listenSeconds || 0) * rcWrapped.prog)
                                                    let nh = Math.floor(n / 3600), nm = Math.floor((n % 3600) / 60)
                                                    return nh > 0 ? nh + "h " + nm + "m" : nm + "m"
                                                }
                                                if (index === 0) {
                                                    let t = Math.round((rcWrapped.wd.listenSeconds || 0) * rcWrapped.prog)
                                                    let h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60)
                                                    return h > 0 ? h + "h " + m + "m" : m + "m"
                                                }
                                                return index === 1 ? (rcWrapped.wd.topArtist || "—") : (rcWrapped.wd.topTrack || "—")
                                            }
                                            elide: Text.ElideRight
                                            font.family: "JetBrains Mono"; font.weight: Font.Black
                                            font.pixelSize: index === 0 ? barWindow.s(26) : barWindow.s(19)
                                            font.letterSpacing: -barWindow.s(0.5)
                                            color: rcWrapBg.ink
                                            style: Text.Raised; styleColor: Qt.alpha(rcWrapBg.deep, 0.45)
                                        }
                                    }
                                }
                            }

                            Row {
                                spacing: barWindow.s(10)
                                Rectangle {
                                    width: rcWrapGo.implicitWidth + barWindow.s(22)
                                    height: barWindow.s(24)
                                    radius: height / 2
                                    color: rcWrapGoMa.containsMouse ? rcWrapBg.ink : Qt.alpha(rcWrapBg.ink, 0.88)
                                    scale: rcWrapGoMa.pressed ? 0.94 : (rcWrapGoMa.containsMouse ? 1.06 : 1)
                                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                    Text {
                                        id: rcWrapGo
                                        anchors.centerIn: parent
                                        text: residentCard.isNowPlaying ? "Open Stats" : "Open Wrapped"
                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: barWindow.s(10)
                                        color: rcWrapBg.deep
                                    }
                                    MouseArea { id: rcWrapGoMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rcWrapped.openWrapped() }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "later"
                                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: barWindow.s(10)
                                    color: rcWrapLaterMa.containsMouse ? rcWrapBg.ink : Qt.alpha(rcWrapBg.ink, 0.65)
                                    MouseArea { id: rcWrapLaterMa; anchors.fill: parent; anchors.margins: -barWindow.s(5); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: barWindow.residentDismiss() }
                                }
                            }
                        }
                    }

                    RcCalendar {
                        id: rcCalendar
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        height: implicitHeight
                        visible: residentCard.isCalendar
                        bar: barWindow
                        theme: mocha
                        d: residentCard.isCalendar ? residentCard.kindData : ({})
                        actions: residentCard.isCalendar ? residentCard.kindActions : []
                        live: residentCard.shown && residentCard.isCalendar
                        onDismissRequested: barWindow.residentDismiss()
                        onRunRequested: (cmd) => residentCard.runKindAction(cmd)
                    }

                    RcBatteryHealth {
                        id: rcBatteryHealth
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        height: implicitHeight
                        visible: residentCard.isBatteryHealth
                        bar: barWindow
                        theme: mocha
                        d: residentCard.isBatteryHealth ? residentCard.kindData : ({})
                        actions: residentCard.isBatteryHealth ? residentCard.kindActions : []
                        live: residentCard.shown && residentCard.isBatteryHealth
                        onDismissRequested: barWindow.residentDismiss()
                        onRunRequested: (cmd) => residentCard.runKindAction(cmd)
                    }

                    RcUptime {
                        id: rcUptime
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        height: implicitHeight
                        visible: residentCard.isUptimeGuilt
                        bar: barWindow
                        theme: mocha
                        d: residentCard.isUptimeGuilt ? residentCard.kindData : ({})
                        actions: residentCard.isUptimeGuilt ? residentCard.kindActions : []
                        live: residentCard.shown && residentCard.isUptimeGuilt
                        onDismissRequested: barWindow.residentDismiss()
                        onRunRequested: (cmd) => residentCard.runKindAction(cmd)
                    }

                    RcGit {
                        id: rcGit
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        height: implicitHeight
                        visible: residentCard.isGitPush
                        bar: barWindow
                        theme: mocha
                        d: residentCard.isGitPush ? residentCard.kindData : ({})
                        actions: residentCard.isGitPush ? residentCard.kindActions : []
                        live: residentCard.shown && residentCard.isGitPush
                        onDismissRequested: barWindow.residentDismiss()
                        onRunRequested: (cmd) => residentCard.runKindAction(cmd)
                    }

                    RcTailscale {
                        id: rcTailscale
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        height: implicitHeight
                        visible: residentCard.isTailscale
                        bar: barWindow
                        theme: mocha
                        d: residentCard.isTailscale ? residentCard.kindData : ({})
                        actions: residentCard.isTailscale ? residentCard.kindActions : []
                        live: residentCard.shown && residentCard.isTailscale
                        onDismissRequested: barWindow.residentDismiss()
                        onRunRequested: (cmd) => residentCard.runKindAction(cmd)
                    }

                    RcFocusDone {
                        id: rcFocusDone
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        height: implicitHeight
                        visible: residentCard.isFocusDone
                        bar: barWindow
                        theme: mocha
                        d: residentCard.isFocusDone ? residentCard.kindData : ({})
                        actions: residentCard.isFocusDone ? residentCard.kindActions : []
                        live: residentCard.shown && residentCard.isFocusDone
                        onDismissRequested: barWindow.residentDismiss()
                        onRunRequested: (cmd) => residentCard.runKindAction(cmd)
                    }

                    RcBriefMorning {
                        id: rcBriefMorning
                        readonly property bool on: residentCard.isBrief && residentCard.briefPeriod !== "afternoon" && residentCard.briefPeriod !== "night"
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        height: implicitHeight
                        visible: on
                        bar: barWindow
                        theme: mocha
                        d: on ? residentCard.kindData : ({})
                        actions: on ? residentCard.kindActions : []
                        live: residentCard.shown && on
                        onDismissRequested: barWindow.residentDismiss()
                        onRunRequested: (cmd) => residentCard.runKindAction(cmd)
                    }

                    RcBriefAfternoon {
                        id: rcBriefAfternoon
                        readonly property bool on: residentCard.briefPeriod === "afternoon"
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        height: implicitHeight
                        visible: on
                        bar: barWindow
                        theme: mocha
                        d: on ? residentCard.kindData : ({})
                        actions: on ? residentCard.kindActions : []
                        live: residentCard.shown && on
                        onDismissRequested: barWindow.residentDismiss()
                        onRunRequested: (cmd) => residentCard.runKindAction(cmd)
                    }

                    RcBriefNight {
                        id: rcBriefNight
                        readonly property bool on: residentCard.briefPeriod === "night"
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        height: implicitHeight
                        visible: on
                        bar: barWindow
                        theme: mocha
                        d: on ? residentCard.kindData : ({})
                        actions: on ? residentCard.kindActions : []
                        live: residentCard.shown && on
                        onDismissRequested: barWindow.residentDismiss()
                        onRunRequested: (cmd) => residentCard.runKindAction(cmd)
                    }
                }

                HoverCard {
                    id: claudeCard
                    active: claudeTipState.cardKeep || claudeTipState.hoverConfirmed
                    confirmed: claudeTipState.hoverConfirmed
                    phase: 0.02
                    x: centerBox.x
                    y: centerBox.y + centerBox.height - barWindow.s(1)
                    width: centerBox.width
                    height: claudeTipCol.implicitHeight + barWindow.s(18)

                    Column {
                        id: claudeTipCol
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: barWindow.s(14); anchors.rightMargin: barWindow.s(14)
                        spacing: barWindow.s(6)

                        Row {
                            width: parent.width
                            spacing: barWindow.s(8)
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: barWindow.s(8); height: width; radius: width / 2
                                color: claudeStatus.accent
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: claudeStatus.status === "working" ? "Claude is working" : (claudeStatus.status === "waiting" ? "Claude needs you" : "Claude is idle")
                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Black; color: mocha.text
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: claudeStatus.hasSuggestion
                                text: { claudeStatus._clockTick; return claudeStatus.agoText(claudeStatus.sugTs) }
                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); color: mocha.overlay0
                            }
                        }
                        Text {
                            visible: claudeStatus.hasSuggestion
                            width: parent.width
                            text: claudeStatus.sugMsg
                            wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                            font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: mocha.text
                        }
                        Row {
                            visible: claudeStatus.hasSuggestion
                            spacing: barWindow.s(8)
                            Rectangle {
                                visible: claudeStatus.sugActionCmd !== ""
                                width: claudeRunRow.implicitWidth + barWindow.s(16); height: barWindow.s(20); radius: barWindow.s(6)
                                color: claudeRunMa.containsMouse ? Qt.rgba(claudeStatus.accent.r, claudeStatus.accent.g, claudeStatus.accent.b, 0.30) : Qt.rgba(claudeStatus.accent.r, claudeStatus.accent.g, claudeStatus.accent.b, 0.16)
                                border.width: 1; border.color: Qt.rgba(claudeStatus.accent.r, claudeStatus.accent.g, claudeStatus.accent.b, 0.5)
                                Row {
                                    id: claudeRunRow
                                    anchors.centerIn: parent
                                    spacing: barWindow.s(5)
                                    Text { text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(10); color: claudeStatus.accent }
                                    Text { text: claudeStatus.sugActionLabel !== "" ? claudeStatus.sugActionLabel : "run"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold; color: claudeStatus.accent }
                                }
                                MouseArea { id: claudeRunMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: claudeStatus.runSuggestedAction() }
                            }
                            Rectangle {
                                width: claudeDismissText.implicitWidth + barWindow.s(16); height: barWindow.s(20); radius: barWindow.s(6)
                                color: claudeDismissMa.containsMouse ? Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.12) : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.06)
                                Text { id: claudeDismissText; anchors.centerIn: parent; text: "dismiss"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); color: mocha.subtext0 }
                                MouseArea { id: claudeDismissMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: claudeStatus.dismissSuggestion() }
                            }
                        }
                        Text {
                            visible: !claudeStatus.hasSuggestion && claudeStatus.history.length === 0
                            width: parent.width
                            text: "No nudges yet — I'll speak up when something needs you."
                            wrapMode: Text.WordWrap
                            font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); color: mocha.subtext0
                        }
                        Rectangle { visible: claudeHistRep.count > 0; width: parent.width; height: 1; color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08) }
                        Repeater {
                            id: claudeHistRep
                            model: {
                                let h = claudeStatus.history.slice().reverse()
                                if (claudeStatus.hasSuggestion && h.length > 0 && h[0].msg === claudeStatus.sugMsg) h = h.slice(1)
                                return h.slice(0, 4)
                            }
                            Row {
                                width: claudeTipCol.width
                                spacing: barWindow.s(8)
                                Text { anchors.verticalCenter: parent.verticalCenter; width: barWindow.s(44); text: claudeStatus.agoText(modelData.ts + 0 * claudeStatus._clockTick); font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); color: mocha.overlay0 }
                                Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - barWindow.s(52); text: modelData.msg; elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); color: mocha.subtext0 }
                            }
                        }
                    }
                }

                HoverCard {
                    id: acctTip
                    active: acctBox.cardKeep || acctBox.hoverConfirmed
                    confirmed: acctBox.hoverConfirmed
                    phase: 0.05
                    x: leftLayout.x + acctBox.x
                    y: barRow.height - barWindow.s(1)
                    width: Math.max(acctBox.width, barWindow.s(230))
                    height: acctTipCol.implicitHeight + barWindow.s(18)

                    Column {
                        id: acctTipCol
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: barWindow.s(14); anchors.rightMargin: barWindow.s(14)
                        spacing: barWindow.s(8)

                        Row {
                            width: parent.width
                            spacing: barWindow.s(9)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: barWindow.s(18)
                                color: acctBox.acctAccent
                                text: acctBox.acctType === "key" ? "󰌆" : "󰀄"
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - barWindow.s(27)
                                spacing: barWindow.s(2)
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: barWindow.s(12)
                                    font.weight: Font.Bold
                                    color: mocha.text
                                    text: acctBox.acctLabel !== "" ? acctBox.acctLabel : "No active account"
                                }
                                Text {
                                    visible: acctBox.acctEmail !== ""
                                    width: parent.width
                                    elide: Text.ElideRight
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: barWindow.s(10)
                                    color: mocha.subtext0
                                    opacity: 0.8
                                    text: acctBox.acctEmail
                                }
                            }
                        }
                        Rectangle { width: parent.width; height: 1; color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08) }
                        Rectangle {
                            width: parent.width; height: barWindow.s(26); radius: barWindow.s(8)
                            color: acctCycleMa.containsMouse ? Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.12) : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.06)
                            Row {
                                anchors.centerIn: parent
                                spacing: barWindow.s(6)
                                Text { anchors.verticalCenter: parent.verticalCenter; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(11); color: mocha.subtext0; text: "󰑖" }
                                Text { anchors.verticalCenter: parent.verticalCenter; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold; color: mocha.subtext0; text: "cycle account" }
                            }
                            MouseArea {
                                id: acctCycleMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/anthropic_acct.sh cycle silent"])
                            }
                        }
                    }
                }

                HoverCard {
                    id: mediaCard
                    active: mediaBox.cardKeep || mediaBox.hoverConfirmed
                    confirmed: mediaBox.hoverConfirmed
                    phase: 0.97
                    x: leftLayout.x + mediaBox.x
                    y: barRow.height - barWindow.s(1)
                    width: mediaBox.width
                    // Flat constant, NOT derived from mediaCol.implicitHeight at
                    // all — Math.min(implicitHeight, cap) was tried first and
                    // didn't fix it: the window's input mask (Region { item:
                    // mediaCard }, in the PanelWindow's `mask:` near the top of
                    // this file) most likely snapshots geometry once rather than
                    // tracking it live, so even a capped-but-still-reactive
                    // height could still be registered from before the lyrics
                    // section (loaded async, after the card may already be open)
                    // finished settling mediaCol's real size. Below wherever that
                    // mask actually ends, the pointer isn't over quickshell's
                    // input region at all — it falls through to whatever's
                    // underneath, which is exactly "hovering the sync button
                    // selects text / closes the card": some other window was
                    // receiving it, not this one. A flat number removes the
                    // race entirely — there is nothing left to settle late.
                    // (Sum of art+seek+volume rows + separator + the 170px
                    // lyrics viewport + spacing/padding is ~320px; this leaves
                    // real headroom, not a tight fit.)
                    //
                    // Two flat values, not one — "no lyrics found" is a
                    // SETTLED state (the fetch already finished and won't
                    // grow the content further, so there's no async-arrival
                    // race left to protect against for it specifically), and
                    // the full 360 sized for a synced-lyrics viewport left a
                    // large dead empty gap below "No lyrics found" otherwise.
                    height: (mediaCard.lyricsLoading || mediaCard.lyricsData.found) ? barWindow.s(360) : barWindow.s(200)
                    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

                    // Lyrics — fetched from lrclib.net (free, no key) via
                    // lyrics_fetch.py, cached per-track there so re-opening the
                    // card or reopening the same song doesn't re-hit the network.
                    // Fetched once per track (on card open, or immediately if the
                    // card is already open when the track changes), not on a
                    // poll — lyrics for a given track never change mid-playback.
                    property var lyricsData: ({ found: false, synced: [], plain: "" })
                    property string lyricsForTrack: ""
                    // Safe single-quote shell escaping — lifeline.sh takes the
                    // whole command as one string re-parsed by `bash -c`, so
                    // artist/title (real-world, not-our-control metadata) must
                    // be quoted properly rather than just interpolated; a `$`
                    // or backtick in a name would otherwise be shell-expanded.
                    function shQuote(s) {
                        return "'" + String(s).replace(/'/g, "'\\''") + "'"
                    }
                    property bool lyricsLoading: false
                    // Paused (set false) while the user is manually scrolled
                    // away from the current line — see lyricsSyncedList below.
                    property bool lyricsAutoFollow: true
                    // True until the first scroll after a (re)open/track-change —
                    // that one jumps instantly instead of animating; see
                    // lyricsScrollDebounce below for why.
                    property bool lyricsFirstScroll: true
                    function maybeFetchLyrics() {
                        let key = (barWindow.musicData.artist || "") + "|" + (barWindow.musicData.title || "")
                        if (key === "|" || key === mediaCard.lyricsForTrack) return
                        if (!mediaCard.active) return
                        mediaCard.lyricsForTrack = key
                        mediaCard.lyricsAutoFollow = true
                        mediaCard.lyricsFirstScroll = true
                        mediaCard.lyricsData = { found: false, synced: [], plain: "" }
                        mediaCard.lyricsLoading = true
                        let dur = Math.round(parseFloat(barWindow.musicData.length) || 0)
                        lyricsProc.command = ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh",
                            "python3 \"$HOME/.config/hypr/scripts/quickshell/music/lyrics_fetch.py\" " +
                            mediaCard.shQuote(barWindow.musicData.artist || "") + " " +
                            mediaCard.shQuote(barWindow.musicData.title || "") + " " + dur]
                        lyricsProc.running = false
                        lyricsProc.running = true
                    }
                    onActiveChanged: if (active) { maybeFetchLyrics(); resyncPosAnchor(); lyricsAutoFollow = true; lyricsFirstScroll = true }
                    Connections {
                        target: barWindow
                        function onMusicDataChanged() { mediaCard.maybeFetchLyrics(); mediaCard.resyncPosAnchor() }
                    }
                    Process {
                        id: lyricsProc
                        stdout: StdioCollector {
                            onStreamFinished: {
                                mediaCard.lyricsLoading = false
                                try {
                                    let d = JSON.parse(this.text.trim())
                                    if (d && typeof d === "object") mediaCard.lyricsData = d
                                } catch (e) {}
                            }
                        }
                    }
                    // musicData.position only updates on sparse dbus refresh
                    // events (play/pause/seek/track-change), not continuously —
                    // synced lyrics would jump in chunks instead of tracking
                    // playback if driven from it directly. Anchor the last real
                    // position against wall-clock time whenever it refreshes,
                    // then extrapolate every second while playing (same idea as
                    // any player UI's fake-smooth seek bar between metadata ticks).
                    property real posAnchor: 0
                    property real posAnchorWallTime: 0
                    property int posTick: 0
                    function resyncPosAnchor() {
                        mediaCard.posAnchor = parseFloat(barWindow.musicData.position) || 0
                        mediaCard.posAnchorWallTime = Date.now() / 1000
                    }
                    Timer {
                        interval: 1000
                        repeat: true
                        running: mediaCard.active && barWindow.musicData.status === "Playing"
                        onTriggered: mediaCard.posTick++
                    }
                    readonly property real estPosition: {
                        mediaCard.posTick // dependency: forces re-eval every tick
                        if (barWindow.musicData.status !== "Playing") return mediaCard.posAnchor
                        return mediaCard.posAnchor + (Date.now() / 1000 - mediaCard.posAnchorWallTime)
                    }

                    // Current line index for synced lyrics, from the estimated
                    // live playback position (+ the configurable sync offset —
                    // Guide → Settings → Media & Audio — positive = highlight
                    // earlier/ahead of actual playback) — drives highlight and
                    // auto-scroll.
                    property int lyricsCurrentIndex: {
                        let synced = mediaCard.lyricsData.synced
                        if (!synced || synced.length === 0) return -1
                        let pos = mediaCard.estPosition + barWindow.lyricsSyncOffsetSec
                        let idx = -1
                        for (let i = 0; i < synced.length; i++) {
                            if (synced[i].time <= pos) idx = i
                            else break
                        }
                        return idx
                    }

                    Column {
                        id: mediaCol
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: barWindow.s(14); anchors.rightMargin: barWindow.s(14)
                        spacing: barWindow.s(9)

                        Row {
                            width: parent.width
                            spacing: barWindow.s(10)
                            Rectangle {
                                id: mediaCardArt
                                width: barWindow.s(52); height: barWindow.s(52)
                                radius: barWindow.s(9); color: mocha.surface1
                                Item {
                                    id: mediaCardArtMask
                                    anchors.fill: parent
                                    layer.enabled: true
                                    visible: false
                                    Rectangle { anchors.fill: parent; radius: mediaCardArt.radius; color: "white" }
                                }
                                Item {
                                    anchors.fill: parent
                                    layer.enabled: true
                                    layer.effect: MultiEffect { maskEnabled: true; maskSource: mediaCardArtMask }
                                    Image {
                                        anchors.fill: parent
                                        source: barWindow.musicData.artUrl ? "file://" + barWindow.musicData.artUrl : ""
                                        fillMode: Image.PreserveAspectCrop
                                    }
                                }
                            }
                            Column {
                                width: parent.width - barWindow.s(62)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: barWindow.s(2)
                                Text { width: parent.width; text: barWindow.musicData.title || ""; elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(13); font.weight: Font.Black; color: mocha.text }
                                Text { width: parent.width; text: barWindow.musicData.artist || ""; elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); color: mocha.subtext0 }
                                Row {
                                    spacing: barWindow.s(5)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.musicData.deviceIcon || "󰓃"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(11); color: mocha.peach }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.musicData.deviceName || ""; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); color: mocha.overlay1 }
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: barWindow.s(8)
                            Text { id: mediaPosText; anchors.verticalCenter: parent.verticalCenter; width: barWindow.s(34); text: barWindow.musicData.positionStr || "00:00"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); color: mocha.overlay1 }
                            Item {
                                id: mediaSeek
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - barWindow.s(34) * 2 - barWindow.s(16)
                                height: barWindow.s(14)
                                readonly property real frac: mediaSeekMa.pressed
                                    ? Math.max(0, Math.min(1, mediaSeekMa.mouseX / width))
                                    : Math.max(0, Math.min(1, (parseFloat(barWindow.musicData.percent) || 0) / 100))
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: barWindow.s(4); radius: height / 2; color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.12) }
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * mediaSeek.frac; height: barWindow.s(4); radius: height / 2; color: mocha.mauve }
                                Rectangle {
                                    visible: mediaSeekMa.containsMouse || mediaSeekMa.pressed
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: parent.width * mediaSeek.frac - width / 2
                                    width: barWindow.s(10); height: width; radius: width / 2; color: mocha.text
                                }
                                MouseArea {
                                    id: mediaSeekMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onReleased: (m) => {
                                        let len = parseInt(barWindow.musicData.length)
                                        if (isNaN(len) || len <= 0) return
                                        let f = Math.max(0, Math.min(1, m.x / mediaSeek.width))
                                        let secs = Math.round(f * len)
                                        let d = Object.assign({}, barWindow.musicData)
                                        d.percent = f * 100
                                        d.positionStr = (secs < 600 ? "0" : "") + Math.floor(secs / 60) + ":" + (secs % 60 < 10 ? "0" : "") + (secs % 60)
                                        d.timeStr = d.positionStr + " / " + d.lengthStr
                                        barWindow.musicData = d
                                        Quickshell.execDetached(["playerctl", "--player=spotify", "position", String(secs)])
                                        barWindow.requestMusicRefresh()
                                    }
                                }
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; width: barWindow.s(34); horizontalAlignment: Text.AlignRight; text: barWindow.musicData.lengthStr || "00:00"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); color: mocha.overlay1 }
                        }

                        Row {
                            width: parent.width
                            spacing: barWindow.s(8)
                            Text { anchors.verticalCenter: parent.verticalCenter; width: barWindow.s(34); text: mediaBox.playerVol <= 0.001 ? "󰝟" : "󰕾"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(13); color: mocha.subtext0 }
                            Item {
                                id: mediaVolBar
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - barWindow.s(34) * 2 - barWindow.s(16)
                                height: barWindow.s(14)
                                readonly property real frac: mediaVolMa.pressed
                                    ? Math.max(0, Math.min(1, mediaVolMa.mouseX / width))
                                    : Math.max(0, Math.min(1, mediaBox.playerVol))
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: barWindow.s(4); radius: height / 2; color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.12) }
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * mediaVolBar.frac; height: barWindow.s(4); radius: height / 2; color: mocha.peach }
                                Rectangle {
                                    visible: mediaVolMa.containsMouse || mediaVolMa.pressed
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: parent.width * mediaVolBar.frac - width / 2
                                    width: barWindow.s(10); height: width; radius: width / 2; color: mocha.text
                                }
                                MouseArea {
                                    id: mediaVolMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onReleased: (m) => {
                                        let f = Math.max(0, Math.min(1, m.x / mediaVolBar.width))
                                        mediaBox.playerVol = f
                                        Quickshell.execDetached(["playerctl", "--player=spotify", "volume", f.toFixed(2)])
                                    }
                                }
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; width: barWindow.s(34); horizontalAlignment: Text.AlignRight; text: Math.round((mediaVolMa.pressed ? mediaVolBar.frac : mediaBox.playerVol) * 100) + "%"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); color: mocha.overlay1 }
                        }

                        // Lyrics — synced (per-line highlight + auto-scroll,
                        // like Spotify's now-playing lyrics view) when lrclib
                        // has word/line sync data for the track, otherwise a
                        // plain scrollable block, otherwise a quiet not-found
                        // note. Fixed-height clipped viewport (not sized to
                        // content) so a long lyric sheet can't blow the whole
                        // hover card out to screen height.
                        Rectangle { width: parent.width; height: 1; color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08) }
                        Item {
                            id: lyricsViewport
                            width: parent.width
                            height: barWindow.s(170)
                            visible: mediaCard.lyricsLoading || mediaCard.lyricsData.found

                            // Loading: a slow breathing dot instead of static text —
                            // reads as "working", not "stuck".
                            Item {
                                visible: mediaCard.lyricsLoading
                                anchors.centerIn: parent
                                width: loadingRow.implicitWidth; height: loadingRow.implicitHeight
                                Row {
                                    id: loadingRow
                                    spacing: barWindow.s(8)
                                    Rectangle {
                                        width: barWindow.s(7); height: width; radius: width / 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: mocha.mauve
                                        SequentialAnimation on opacity {
                                            loops: Animation.Infinite
                                            running: mediaCard.lyricsLoading
                                            NumberAnimation { to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                                            NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutSine }
                                        }
                                    }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Loading lyrics…"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); color: mocha.overlay1 }
                                }
                            }

                            // Synced: per-line list, current line lifted with a
                            // soft glow pill behind it (colored from the album
                            // art, same mediaBc1/mediaBc2 as the equalizer bars),
                            // auto-scrolled to stay centered — unless the user
                            // has manually scrolled away, in which case
                            // auto-follow pauses until they tap the sync button,
                            // rather than yanking the view back under them.
                            ListView {
                                id: lyricsSyncedList
                                visible: !mediaCard.lyricsLoading && mediaCard.lyricsData.found && mediaCard.lyricsData.synced.length > 0
                                anchors.fill: parent
                                anchors.topMargin: barWindow.s(10)
                                anchors.bottomMargin: barWindow.s(10)
                                clip: true
                                model: mediaCard.lyricsData.synced
                                spacing: barWindow.s(10)
                                // ListView auto-scrolls to follow currentIndex on its
                                // own by default (highlightFollowsCurrentItem),
                                // bypassing lyricsAutoFollow entirely — was the actual
                                // "scrolls back on the next line even though I moved
                                // away" bug. Only scrollToCurrentLine() (which does
                                // check lyricsAutoFollow) is allowed to move this.
                                highlightFollowsCurrentItem: false
                                currentIndex: mediaCard.lyricsCurrentIndex
                                // positionViewAtIndex() jumps instantly — it doesn't go
                                // through contentY as a normal property set, so a
                                // Behavior on contentY never saw it. Scrolling for
                                // real: compute the target contentY from the current
                                // delegate's own position and assign that directly,
                                // which a Behavior does animate.
                                //
                                // Routed through a restartable Timer, not a bare
                                // Qt.callLater — back-to-back index changes (the
                                // position estimator can advance more than one line
                                // between ticks) each queued their own independent
                                // callLater closure, and whichever one's currentItem
                                // read happened to resolve last "won", regardless of
                                // which line was actually current by then. That's what
                                // "goes to the next line, stutters back to the
                                // previous, then forward again" was — two scroll
                                // targets racing. restart() on the same Timer means
                                // only the LAST request in a burst ever actually fires.
                                function scrollToCurrentLine() { lyricsScrollDebounce.restart() }
                                Timer {
                                    id: lyricsScrollDebounce
                                    interval: 30
                                    repeat: false
                                    onTriggered: {
                                        let item = lyricsSyncedList.currentItem
                                        if (!item) return
                                        let target = item.y + item.height / 2 - lyricsSyncedList.height / 2
                                        target = Math.max(0, Math.min(target, Math.max(0, lyricsSyncedList.contentHeight - lyricsSyncedList.height)))
                                        // Opening the card mid-song (or on a track change)
                                        // means jumping straight to whatever line is
                                        // already current — animating THAT glide (which
                                        // can be the whole list's length) reads as a slow,
                                        // pointless scroll-through instead of the lyrics
                                        // just being there. Only line-to-line follows
                                        // while the card stays open should ease.
                                        if (mediaCard.lyricsFirstScroll) {
                                            lyricsScrollBehavior.enabled = false
                                            lyricsSyncedList.contentY = target
                                            lyricsScrollBehavior.enabled = true
                                            mediaCard.lyricsFirstScroll = false
                                        } else {
                                            lyricsSyncedList.contentY = target
                                        }
                                    }
                                }
                                Behavior on contentY { id: lyricsScrollBehavior; NumberAnimation { duration: 550; easing.type: Easing.InOutQuad } }
                                onCurrentIndexChanged: if (currentIndex >= 0 && mediaCard.lyricsAutoFollow) scrollToCurrentLine()
                                onDraggingChanged: if (dragging) mediaCard.lyricsAutoFollow = false
                                delegate: Item {
                                    id: lyricLine
                                    readonly property bool isCurrent: index === lyricsSyncedList.currentIndex
                                    width: lyricsSyncedList.width
                                    height: lyricText.implicitHeight + barWindow.s(10)

                                    // Capsule pill hugging the actual rendered text
                                    // bounds (paintedWidth/Height), not the full
                                    // delegate width. Fixed, constant radius rather
                                    // than a live height/2 computation, and no
                                    // width/height animation — those were animating
                                    // independently with OutBack overshoot while radius
                                    // recomputed off the mid-transition height every
                                    // frame, which is what produced the lopsided corner
                                    // (steady-state was fine, the transition wasn't).
                                    // Opacity is still animated, which is all the pop
                                    // this needs — the pill doesn't need to visibly grow.
                                    // lyricText is inset s(14) from the delegate's own
                                    // left edge (below) specifically so the pill's
                                    // s(10) left overhang lands at x=4, safely inside
                                    // the ListView's clip boundary — it was previously
                                    // computed from lyricText.x, which defaulted to 0,
                                    // putting the pill at x=-10: outside the clipped
                                    // area, so its rounded left edge was cut clean off
                                    // and only ever showed as a flat vertical line.
                                    Rectangle {
                                        x: lyricText.x - barWindow.s(10)
                                        y: lyricText.y - barWindow.s(4)
                                        width: lyricText.paintedWidth + barWindow.s(20)
                                        height: lyricText.paintedHeight + barWindow.s(8)
                                        radius: barWindow.s(16)
                                        color: barWindow.mediaBc1
                                        opacity: lyricLine.isCurrent ? 0.18 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutQuad } }
                                    }

                                    Text {
                                        id: lyricText
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: barWindow.s(14)
                                        width: parent.width - barWindow.s(28)
                                        text: modelData.text
                                        wrapMode: Text.Wrap
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: lyricLine.isCurrent ? barWindow.s(14) : barWindow.s(11)
                                        font.weight: lyricLine.isCurrent ? Font.Black : Font.Normal
                                        color: lyricLine.isCurrent ? mocha.text : mocha.overlay1
                                        opacity: lyricLine.isCurrent ? 1.0 : 0.55
                                        scale: lyricLine.isCurrent ? 1.0 : 0.97
                                        transformOrigin: Item.Left
                                        Behavior on font.pixelSize { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                                        Behavior on opacity { NumberAnimation { duration: 260 } }
                                        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                                    }
                                }
                            }

                            // Soft fade at the top/bottom edges of the scroll
                            // viewport so lines don't hard-clip mid-character —
                            // plain gradient Rectangles, mouse-transparent by
                            // default (no MouseArea), so they can't steal any
                            // input from the list or the sync button below.
                            Rectangle {
                                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                height: barWindow.s(16)
                                visible: lyricsSyncedList.visible
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: barWindow.cardFill }
                                    GradientStop { position: 1.0; color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.0) }
                                }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                                height: barWindow.s(16)
                                visible: lyricsSyncedList.visible
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.0) }
                                    GradientStop { position: 1.0; color: barWindow.cardFill }
                                }
                            }

                            // Sync button — explicit z above everything else in
                            // this Item so it can never lose hover/click to the
                            // list or fade overlays beneath it, and a generous
                            // hit target (own backdrop pill, not just bare text)
                            // so hovering the label is exactly as reliable as
                            // hovering the icon.
                            Rectangle {
                                id: lyricsSyncBtn
                                z: 10
                                visible: lyricsSyncedList.visible && !mediaCard.lyricsAutoFollow
                                opacity: visible ? 1 : 0
                                scale: visible ? 1 : 0.8
                                Behavior on opacity { NumberAnimation { duration: 180 } }
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottomMargin: barWindow.s(6)
                                width: syncBtnRow.implicitWidth + barWindow.s(20)
                                height: barWindow.s(24)
                                radius: height / 2
                                color: Qt.alpha(mocha.mauve, syncBtnMa.containsMouse ? 1.0 : 0.88)
                                border.color: Qt.alpha(mocha.base, 0.25)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Row {
                                    id: syncBtnRow
                                    anchors.centerIn: parent
                                    spacing: barWindow.s(5)
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "󰑖"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(11); color: mocha.base
                                        RotationAnimation on rotation {
                                            running: syncBtnMa.containsMouse
                                            from: 0; to: 360; duration: 700; loops: 1
                                        }
                                    }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Jump to lyric"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: barWindow.s(10); color: mocha.base }
                                }
                                MouseArea {
                                    id: syncBtnMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        mediaCard.lyricsAutoFollow = true
                                        lyricsSyncedList.scrollToCurrentLine()
                                    }
                                }
                            }

                            // Plain: no line timing available, static scrollable text.
                            Flickable {
                                id: lyricsPlainFlick
                                visible: !mediaCard.lyricsLoading && mediaCard.lyricsData.found && mediaCard.lyricsData.synced.length === 0
                                anchors.fill: parent
                                anchors.topMargin: barWindow.s(10)
                                anchors.bottomMargin: barWindow.s(10)
                                clip: true
                                contentWidth: width
                                contentHeight: lyricsPlainText.implicitHeight
                                boundsBehavior: Flickable.StopAtBounds
                                Text {
                                    id: lyricsPlainText
                                    x: barWindow.s(14)
                                    width: lyricsPlainFlick.width - barWindow.s(28)
                                    text: mediaCard.lyricsData.plain || ""
                                    wrapMode: Text.Wrap
                                    lineHeight: 1.4
                                    font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11)
                                    color: mocha.subtext0
                                }
                            }
                            Rectangle {
                                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                height: barWindow.s(16)
                                visible: lyricsPlainFlick.visible
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: barWindow.cardFill }
                                    GradientStop { position: 1.0; color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.0) }
                                }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                                height: barWindow.s(16)
                                visible: lyricsPlainFlick.visible
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.0) }
                                    GradientStop { position: 1.0; color: barWindow.cardFill }
                                }
                            }
                        }
                        Item {
                            width: parent.width
                            height: notFoundRow.implicitHeight + barWindow.s(4)
                            visible: !mediaCard.lyricsLoading && !mediaCard.lyricsData.found
                            Row {
                                id: notFoundRow
                                anchors.centerIn: parent
                                spacing: barWindow.s(6)
                                Text { anchors.verticalCenter: parent.verticalCenter; text: "♪"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(13); color: mocha.overlay0 }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: "No lyrics found"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); color: mocha.overlay1 }
                            }
                        }
                    }
                }

                HoverCard {
                    id: wsCard
                    active: wsGroupBox.cardKeep || wsGroupBox.hoverConfirmed
                    confirmed: wsGroupBox.hoverConfirmed
                    phase: 0.03
                    x: leftLayout.x + wsGroupBox.x
                    y: barRow.height - barWindow.s(1)
                    width: wsGroupBox.width
                    height: wsCol.implicitHeight + barWindow.s(10)

                    Column {
                        id: wsCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: barWindow.s(6); anchors.rightMargin: barWindow.s(6)
                        spacing: barWindow.s(1)
                        Row {
                            id: wsHeaderRow
                            readonly property var sw: barWindow.smartWsAutoNames !== "off" ? barWindow.smartWsWs[String(wsGroupBox.shownIdx + 1)] : undefined
                            width: wsCol.width
                            height: barWindow.s(16)
                            spacing: barWindow.s(5)
                            leftPadding: barWindow.s(4)
                            Text {
                                visible: wsHeaderRow.sw !== undefined
                                anchors.verticalCenter: parent.verticalCenter
                                text: wsHeaderRow.sw !== undefined ? wsHeaderRow.sw.glyph : ""
                                font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(11)
                                color: wsHeaderRow.sw !== undefined ? wsHeaderRow.sw.color : mocha.overlay1
                            }
                            Text {
                                id: wsHeaderName
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, wsCol.width - barWindow.s(54))
                                elide: Text.ElideRight
                                text: wsHeaderRow.sw !== undefined ? wsHeaderRow.sw.name : "workspace " + (wsGroupBox.shownIdx + 1)
                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Bold
                                color: wsHeaderRow.sw !== undefined ? mocha.text : mocha.overlay1
                            }
                            Text {
                                visible: wsHeaderRow.sw !== undefined
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u00b7 " + (wsGroupBox.shownIdx + 1)
                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9)
                                color: mocha.overlay1
                            }
                            Item { visible: wsHeaderRow.sw !== undefined; width: Math.max(0, wsCol.width - barWindow.s(34) - wsHeaderName.width - barWindow.s(30)); height: 1 }
                            Text {
                                visible: wsHeaderRow.sw !== undefined
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\udb81\udc50"
                                font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(10)
                                color: wsCycleMa.containsMouse ? mocha.text : mocha.overlay1
                                MouseArea {
                                    id: wsCycleMa
                                    anchors.fill: parent; anchors.margins: -barWindow.s(3)
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: barWindow.smartWsCmd("cycle " + (wsGroupBox.shownIdx + 1))
                                }
                            }
                        }
                        Text {
                            readonly property var eco: barWindow.ecoShow ? barWindow.ecoByWs[String(wsGroupBox.shownIdx + 1)] : undefined
                            visible: false
                            height: 0
                            text: ""
                            font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9)
                            color: eco !== undefined && eco.level === 2 ? "#74c7ec" : "#89dceb"
                        }
                        Repeater {
                            model: wsGroupBox.shownWins
                            Rectangle {
                                width: wsCol.width; height: barWindow.s(20); radius: barWindow.s(6)
                                color: wsWinMa.containsMouse ? Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left; anchors.right: parent.right
                                    anchors.leftMargin: barWindow.s(6); anchors.rightMargin: barWindow.s(6)
                                    spacing: barWindow.s(7)
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: barWindow.s(14); height: barWindow.s(14); radius: width / 2
                                        color: Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.22)
                                        Text { anchors.centerIn: parent; text: (modelData.c || "?").charAt(0).toUpperCase(); font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(8); font.weight: Font.Bold; color: mocha.text }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - barWindow.s(21) - (wsEcoTag.visible ? wsEcoTag.width + barWindow.s(6) : 0)
                                        text: modelData.t || modelData.c
                                        elide: Text.ElideRight
                                        font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9)
                                        color: wsWinMa.containsMouse ? mocha.text : mocha.subtext1
                                    }
                                }
                                Rectangle {
                                    id: wsEcoTag
                                    readonly property var info: barWindow.ecoShow ? barWindow.ecoByAddr[(modelData.a || "").replace("0x", "").toLowerCase()] : undefined
                                    readonly property bool frozen: info !== undefined && info.level === 2
                                    visible: info !== undefined
                                    anchors.right: parent.right; anchors.rightMargin: barWindow.s(6)
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: barWindow.s(13); width: wsEcoTagText.implicitWidth + barWindow.s(8); radius: height / 2
                                    color: Qt.rgba(frozen ? 0.455 : 0.537, frozen ? 0.78 : 0.863, frozen ? 0.925 : 0.922, 0.16)
                                    border.width: 1
                                    border.color: Qt.rgba(frozen ? 0.455 : 0.537, frozen ? 0.78 : 0.863, frozen ? 0.925 : 0.922, 0.5)
                                    Text {
                                        id: wsEcoTagText
                                        anchors.centerIn: parent
                                        text: wsEcoTag.info === undefined ? "" : (wsEcoTag.frozen ? "\udb81\udf17 " : "\udb80\udf2a ") + barWindow.ecoFmtDur(barWindow.ecoNow - wsEcoTag.info.since)
                                        font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(7); font.weight: Font.Bold
                                        color: wsEcoTag.frozen ? "#74c7ec" : "#89dceb"
                                    }
                                }
                                MouseArea {
                                    id: wsWinMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + modelData.a])
                                }
                            }
                        }
                        Rectangle {
                            visible: barWindow.smartWsLayoutsEnabled
                            width: wsCol.width; height: 1
                            color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08)
                        }
                        Item {
                            visible: barWindow.smartWsLayoutsEnabled
                            width: wsCol.width
                            height: barWindow.s(18)
                            Text {
                                id: wsSaveGlyph
                                x: barWindow.s(6)
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\udb80\udd93"
                                font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(10)
                                color: wsSaveMa.containsMouse ? mocha.text : mocha.overlay1
                            }
                            Text {
                                x: barWindow.s(22)
                                anchors.verticalCenter: parent.verticalCenter
                                text: "save layout"
                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Bold
                                color: wsSaveMa.containsMouse ? mocha.text : mocha.overlay1
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right; anchors.rightMargin: barWindow.s(8)
                                visible: barWindow.smartWsLayouts.length > 3
                                text: "+" + (barWindow.smartWsLayouts.length - 3)
                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(8)
                                color: mocha.overlay1
                            }
                            MouseArea {
                                id: wsSaveMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: barWindow.smartWsCmd("save auto")
                            }
                        }
                        Repeater {
                            model: barWindow.smartWsLayoutsEnabled ? barWindow.smartWsLayouts.slice(0, 3) : []
                            Rectangle {
                                readonly property string lname: modelData
                                readonly property bool armed: barWindow.smartWsPendingRestore === lname
                                readonly property bool delArmed: barWindow.smartWsPendingDelete === lname
                                width: wsCol.width; height: barWindow.s(18); radius: barWindow.s(6)
                                color: wsLayMa.containsMouse ? Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left; anchors.leftMargin: barWindow.s(8)
                                    width: parent.width - barWindow.s(34)
                                    elide: Text.ElideRight
                                    text: parent.delArmed ? "delete " + parent.lname + "?" : (parent.armed ? "restore " + parent.lname + "?" : parent.lname)
                                    font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9)
                                    color: (parent.armed || parent.delArmed) ? "#f9e2af" : (wsLayMa.containsMouse ? mocha.text : mocha.subtext1)
                                }
                                MouseArea {
                                    id: wsLayMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (barWindow.smartWsRestoreConfirm && !parent.armed) {
                                            barWindow.smartWsPendingDelete = ""
                                            barWindow.smartWsPendingRestore = parent.lname
                                            smartWsPendingClear.restart()
                                        } else {
                                            barWindow.smartWsPendingRestore = ""
                                            barWindow.smartWsCmd("restore " + parent.lname)
                                        }
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: parent.right; anchors.rightMargin: barWindow.s(7)
                                    text: "\u00d7"
                                    font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Bold
                                    color: wsDelMa.containsMouse ? "#f38ba8" : mocha.overlay1
                                    MouseArea {
                                        id: wsDelMa
                                        anchors.fill: parent; anchors.margins: -barWindow.s(3)
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (parent.parent.delArmed) {
                                                barWindow.smartWsPendingDelete = ""
                                                barWindow.smartWsCmd("delete " + parent.parent.lname)
                                            } else {
                                                barWindow.smartWsPendingRestore = ""
                                                barWindow.smartWsPendingDelete = parent.parent.lname
                                                smartWsPendingClear.restart()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle {
                            visible: barWindow.ecoShow
                            width: wsCol.width; height: 1
                            color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08)
                        }
                        Row {
                            visible: barWindow.ecoShow
                            width: wsCol.width
                            height: barWindow.s(16)
                            spacing: barWindow.s(5)
                            leftPadding: barWindow.s(4)
                            Text {
                                id: ecoFootIcon
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰌪"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(10)
                                color: barWindow.ecoCount > 0 ? "#89dceb" : mocha.overlay1
                            }
                            Text {
                                id: ecoFootText
                                anchors.verticalCenter: parent.verticalCenter
                                text: "eco on" + (barWindow.ecoCount > 0 ? " \u00b7 " + barWindow.ecoCount + " saving" : " \u00b7 idle")
                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Bold
                                color: mocha.overlay1
                            }
                            Item { width: Math.max(0, wsCol.width - barWindow.s(22) - ecoFootIcon.implicitWidth - ecoFootText.implicitWidth - (ecoProfileChip.visible ? ecoProfileChip.width : 0)); height: 1 }
                            Rectangle {
                                id: ecoProfileChip
                                readonly property string prof: barWindow.ecoPowerProfile
                                readonly property color hex: prof === "performance" ? "#f38ba8" : (prof === "balanced" ? "#89b4fa" : "#a6e3a1")
                                visible: prof !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                height: barWindow.s(13); width: ecoProfileText.implicitWidth + barWindow.s(10); radius: height / 2
                                color: Qt.rgba(hex.r, hex.g, hex.b, 0.16)
                                border.width: 1
                                border.color: Qt.rgba(hex.r, hex.g, hex.b, 0.5)
                                Text {
                                    id: ecoProfileText
                                    anchors.centerIn: parent
                                    text: (ecoProfileChip.prof === "performance" ? "󰓅" : (ecoProfileChip.prof === "balanced" ? "󰾆" : "󰌪"))
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(8); font.weight: Font.Bold
                                    color: ecoProfileChip.hex
                                }
                            }
                        }
                    }
                }

                HoverCard {
                    id: statsCard
                    flush: false
                    active: sysStatsPill.cardKeep || sysStatsPill.hoverConfirmed
                    confirmed: sysStatsPill.hoverConfirmed
                    phase: 0.15
                    width: Math.max(sysStatsPill.width, barWindow.s(240))
                    x: Math.min(barRow.width - width - barWindow.s(6), rightLayout.x + sysStatsPill.x + sysStatsPill.width / 2 - width / 2)
                    y: barRow.height + barWindow.s(2)
                    height: (sysStatsPill.which === 0 ? statsCpuCol.implicitHeight : (sysStatsPill.which === 1 ? statsGpuCol.implicitHeight : (sysStatsPill.which === 2 ? statsNetCol.implicitHeight : statsUpCol.implicitHeight))) + barWindow.s(18)

                    Column {
                        id: statsCpuCol
                        visible: sysStatsPill.which === 0
                        anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: barWindow.s(14); anchors.rightMargin: barWindow.s(14)
                        spacing: barWindow.s(5)
                        Row {
                            spacing: barWindow.s(6)
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "󰘚"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(13); color: mocha.green }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "CPU  " + barWindow.cpuPct + "%" + (sysStatsPill.cpuTemp !== "" ? "  " + sysStatsPill.cpuTemp + "°C" : ""); font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: mocha.text }
                        }
                        Text { visible: sysStatsPill.cpuLoad !== ""; text: "load " + sysStatsPill.cpuLoad; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); color: mocha.subtext0 }
                        Repeater {
                            model: sysStatsPill.cpuProcs
                            Row {
                                width: statsCpuCol.width
                                Text { width: parent.width - barWindow.s(44); text: modelData.name; elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); color: mocha.subtext1 }
                                Text { width: barWindow.s(44); horizontalAlignment: Text.AlignRight; text: modelData.pct + "%"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold; color: mocha.peach }
                            }
                        }
                    }

                    Column {
                        id: statsGpuCol
                        visible: sysStatsPill.which === 1
                        anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: barWindow.s(14); anchors.rightMargin: barWindow.s(14)
                        spacing: barWindow.s(5)
                        Row {
                            spacing: barWindow.s(6)
                            width: parent.width
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "󰢮"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(13); color: mocha.green }
                            Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - barWindow.s(22); text: sysStatsPill.gpuInfo.length > 0 ? sysStatsPill.gpuInfo[0] : "GPU"; elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: mocha.text }
                        }
                        Text { visible: sysStatsPill.gpuInfo.length > 2; text: "VRAM  " + (sysStatsPill.gpuInfo[1] || "-") + " / " + (sysStatsPill.gpuInfo[2] || "-") + " MiB"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); color: mocha.subtext1 }
                        Text { visible: sysStatsPill.gpuInfo.length > 3 && sysStatsPill.gpuInfo[3] !== ""; text: "temp  " + (sysStatsPill.gpuInfo[3] || "-") + "°C" + ((sysStatsPill.gpuInfo[4] || "") !== "" ? "   power  " + sysStatsPill.gpuInfo[4] + " W" : ""); font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); color: mocha.subtext1 }
                    }

                    Column {
                        id: statsNetCol
                        visible: sysStatsPill.which === 2
                        anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: barWindow.s(14); anchors.rightMargin: barWindow.s(14)
                        spacing: barWindow.s(5)
                        Row {
                            spacing: barWindow.s(6)
                            width: parent.width
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "󰖩"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(13); color: mocha.sapphire }
                            Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - barWindow.s(22); text: (sysStatsPill.netInfo[0] || "no link") + "  " + (sysStatsPill.netInfo[1] || ""); elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: mocha.text }
                        }
                        Text { text: "ping 1.1.1.1  " + ((sysStatsPill.netInfo[4] || "") !== "" ? sysStatsPill.netInfo[4] : "timeout"); font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); color: (sysStatsPill.netInfo[4] || "") !== "" ? mocha.green : mocha.red }
                        Text { text: "󰇚 " + sysStatsPill.fmtBytes(sysStatsPill.netInfo[2]) + "   󰕒 " + sysStatsPill.fmtBytes(sysStatsPill.netInfo[3]) + "  (boot)"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); color: mocha.subtext1 }
                    }

                    Column {
                        id: statsUpCol
                        visible: sysStatsPill.which === 3
                        anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: barWindow.s(14); anchors.rightMargin: barWindow.s(14)
                        spacing: barWindow.s(5)
                        Row {
                            spacing: barWindow.s(6)
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "󰥔"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(13); color: mocha.teal }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "up " + barWindow.uptimeStr; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: mocha.text }
                        }
                        Text { text: "booted  " + sysStatsPill.bootTime; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); color: mocha.subtext1 }
                    }
                }

                // ---------------- RIGHT ----------------
                RowLayout {
                    id: rightLayout
                    anchors.right: parent.right
                    anchors.left: centerBox.right // Hard boundary to prevent overlaps
                    anchors.leftMargin: barWindow.s(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: barWindow.s(4)

                    readonly property bool statsCol2On: (barWindow.topBarShowGpu && barWindow.gpuAvailable) || (barWindow.topBarShowUptime && barWindow.uptimeStr !== "")
                    readonly property real col2Save: statsCol2On ? gpuChip.width + barWindow.s(4) : 0
                    readonly property real qsCpuSave: barWindow.topBarShowQuickshellCpu ? qsCpuPill.Layout.preferredWidth + spacing : 0
                    readonly property real timerSave: barWindow.topBarTimerEnabled && barWindow.timerState === "idle" ? timerPill.Layout.preferredWidth + spacing : 0
                    readonly property real statsSave: cpuChip.width + barWindow.s(10) + spacing
                    readonly property real naturalWidth: (trayPill.targetWidth > 0 ? trayPill.targetWidth + spacing : 0)
                        + qsCpuSave + statsSave + col2Save
                        + (barWindow.topBarTimerEnabled ? timerPill.Layout.preferredWidth + spacing : 0)
                        + sysCapsule.targetWidth + barWindow.s(30)
                    readonly property int compactLevel: {
                        let over = naturalWidth - width
                        if (over <= 0) return 0
                        over -= col2Save
                        if (over <= 0) return 1
                        over -= qsCpuSave
                        if (over <= 0) return 2
                        over -= timerSave
                        if (over <= 0) return 3
                        return 4
                    }

                    // Staggered Right Transition
                    property bool showLayout: false
                    // Slide-out drawer (KB / WiFi / Bluetooth)
                    property bool drawerOpen: false
                    opacity: showLayout ? 1 : 0
                    transform: Translate {
                        x: rightLayout.showLayout ? 0 : barWindow.s(30)
                        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                    }
                    
                    Timer {
                        running: barWindow.isStartupReady && barWindow.isDataReady
                        interval: 250
                        onTriggered: rightLayout.showLayout = true
                    }

                    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

                    // Dynamic Spacer to gently push the tray and system pills completely to the right edge
                    Item { Layout.fillWidth: true }

                    // The scrollable calendar events/tasks pill that used to live here was
                    // removed — combined with a wide right-capsule page (wifi/bt toggles),
                    // it could push the bar's total content past the screen's right edge,
                    // clipping the battery pill clean off. Its data now lives in the
                    // weather/clock hover card's "TODAY" section instead (see weatherTip).


                    // Dedicated System Tray Pill
                    Rectangle {
                        id: trayPill
                        Layout.preferredHeight: barWindow.barHeight // THE FIX: Replaced basic "height"
                        radius: barWindow.s(10)
                        // Exact same fill/border formula as the sysStatsPill chips right
                        // next to it (surface0 @ 0.4, border alpha 0.05) — it was using
                        // base @ 0.75 with a heavier 0.08 border, a visibly darker/bolder
                        // box than its neighbors even after matching their radius.
                        // No inherent status meaning — full ambient treatment, phase 0.16.
                        border.color: barWindow.topBarAccentLine
                            ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.16)))
                            : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                        border.width: 1
                        color: Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)

                        // Show at most maxVisible icons' worth of width — extra icons stay
                        // real, fully-clickable delegates, just scrolled into view with the
                        // wheel instead of hidden behind a separate (harder to right-click)
                        // overflow list.
                        property int maxVisible: 4
                        readonly property real iconSlot: barWindow.s(18) + barWindow.s(10)
                        readonly property real viewportW: Math.min(trayRepeater.count, maxVisible) * iconSlot - barWindow.s(10)
                        property var activeMenu: null

                        // Was +s(24) — noticeably more side padding than the text chips
                        // (+s(9)-ish) or the tightened stats/timer pills above, which was
                        // part of the uneven-gap look. Trimmed some (icons still get a
                        // bit more breathing room than plain text, unlike a flat match).
                        property real targetWidth: trayRepeater.count > 0 ? Math.min(trayLayout.implicitWidth, viewportW) + barWindow.s(16) : 0
                        Layout.preferredWidth: targetWidth
                        Behavior on targetWidth { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }

                        visible: targetWidth > 0
                        opacity: targetWidth > 0 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 300 } }

                        Item {
                            id: trayViewport
                            anchors.centerIn: parent
                            width: trayPill.viewportW
                            height: barWindow.s(18)
                            clip: true

                            property real scrollX: 0
                            readonly property real maxScroll: Math.max(0, trayLayout.implicitWidth - width)
                            onMaxScrollChanged: scrollX = Math.max(-maxScroll, Math.min(0, scrollX))

                            Row {
                                id: trayLayout
                                x: trayViewport.scrollX
                                height: parent.height
                                spacing: barWindow.s(10)
                                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                                Repeater {
                                    id: trayRepeater
                                    model: SystemTray.items
                                    delegate: Item {
                                        id: trayIcon
                                        width: barWindow.s(18)
                                        height: barWindow.s(18)
                                        anchors.verticalCenter: parent.verticalCenter

                                        property bool isHovered: trayMouse.containsMouse
                                        property bool initAnimTrigger: false
                                        opacity: initAnimTrigger ? (isHovered ? 1.0 : 0.8) : 0.0
                                        scale: initAnimTrigger ? (isHovered ? 1.15 : 1.0) : 0.0

                                        Image {
                                            id: trayIconImage
                                            anchors.fill: parent
                                            source: modelData.icon || ""
                                            fillMode: Image.PreserveAspectFit
                                            sourceSize: Qt.size(barWindow.s(18), barWindow.s(18))
                                            visible: false
                                        }
                                        ColorOverlay {
                                            anchors.fill: trayIconImage
                                            source: trayIconImage
                                            color: trayIcon.isHovered ? mocha.text : mocha.subtext1
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }

                                        Component.onCompleted: {
                                            if (!barWindow.startupCascadeFinished) {
                                                trayAnimTimer.interval = index * 50;
                                                trayAnimTimer.start();
                                            } else {
                                                initAnimTrigger = true;
                                            }
                                        }
                                        Timer {
                                            id: trayAnimTimer
                                            running: false
                                            repeat: false
                                            onTriggered: trayIcon.initAnimTrigger = true
                                        }

                                        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                                        MouseArea {
                                            id: trayMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                            onClicked: mouse => {
                                                if (mouse.button === Qt.LeftButton) {
                                                    modelData.activate();
                                                } else if (mouse.button === Qt.MiddleButton) {
                                                    modelData.secondaryActivate();
                                                } else if (mouse.button === Qt.RightButton) {
                                                    if (modelData.menu) {
                                                        if (trayMenuPopup.visible && trayPill.activeMenu === modelData.menu) {
                                                            trayMenuPopup.visible = false;
                                                        } else {
                                                            trayPill.activeMenu = modelData.menu;
                                                            trayMenuPopup.visible = true;
                                                        }
                                                    } else if (typeof modelData.contextMenu === "function") {
                                                        modelData.contextMenu(mouse.x, mouse.y);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                onWheel: wheel => {
                                    let delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
                                    trayViewport.scrollX = Math.max(-trayViewport.maxScroll, Math.min(0, trayViewport.scrollX + delta * 0.4))
                                }
                            }
                        }

                        // Themed replacement for the tray app's native right-click menu —
                        // QsMenuAnchor.open() renders an unstyled platform popup, so instead
                        // we pull the raw entries via QsMenuOpener and draw our own.
                        QsMenuOpener { id: trayMenuOpener; menu: trayPill.activeMenu }

                        Rectangle {
                            id: trayMenuPopup
                            visible: false
                            anchors.top: trayPill.bottom
                            anchors.right: trayPill.right
                            anchors.topMargin: 0
                            width: Math.max(barWindow.s(140), trayMenuCol.implicitWidth + barWindow.s(16))
                            height: Math.max(barWindow.s(30), trayMenuCol.implicitHeight + barWindow.s(10))
                            radius: barWindow.s(10)
                            color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.97)
                            border.width: 1
                            border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.1)
                            z: 200

                            // Absorbs clicks on the popup's own blank padding so they don't
                            // fall through to the bar's outside-click closer below.
                            MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

                            ColumnLayout {
                                id: trayMenuCol
                                anchors.centerIn: parent
                                spacing: 0

                                Repeater {
                                    model: trayMenuOpener.children
                                    delegate: Item {
                                        // Width comes from this row's own content, never from
                                        // trayMenuCol — binding it to the Column's implicitWidth
                                        // would be circular (Column derives its width FROM this).
                                        Layout.preferredWidth: menuRow.implicitWidth + barWindow.s(20)
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: modelData.isSeparator ? barWindow.s(7) : barWindow.s(26)

                                        Rectangle {
                                            visible: modelData.isSeparator
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width; height: 1
                                            color: Qt.alpha(mocha.surface1, 0.6)
                                        }

                                        Rectangle {
                                            visible: !modelData.isSeparator
                                            anchors.fill: parent
                                            radius: barWindow.s(6)
                                            color: (!modelData.isSeparator && trayMenuItemMa.containsMouse && modelData.enabled) ? Qt.alpha(mocha.surface1, 0.7) : "transparent"
                                        }

                                        Row {
                                            id: menuRow
                                            visible: !modelData.isSeparator
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.leftMargin: barWindow.s(10)
                                            spacing: barWindow.s(6)

                                            Text {
                                                visible: modelData.checkState === Qt.Checked
                                                text: "✓"
                                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11)
                                                color: mocha.mauve
                                            }
                                            Text {
                                                text: modelData.text || ""
                                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12)
                                                color: modelData.enabled ? mocha.text : mocha.subtext0
                                            }
                                        }

                                        MouseArea {
                                            visible: !modelData.isSeparator
                                            id: trayMenuItemMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: modelData.enabled
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                modelData.triggered();
                                                trayMenuPopup.visible = false;
                                            }
                                        }
                                    }
                                }
                            }

                        }
                    }

                    // Quickshell's own CPU chip — pulled OUT of the 4-chip stats grid
                    // into its own standalone pill (a "standing" pill of its own,
                    // between the stats grid and the tray, not squeezed into the grid
                    // as a 5th cell). Same StatChip visual recipe (radius/fill/border/
                    // glow/PillBg), copied rather than reused because `component
                    // StatChip` is declared inline inside statsGrid's own scope and
                    // isn't a type sibling items outside that Grid can reference.
                    // Fed by scripts/perf_watch.py via barWindow.qsCpuPct/qsCpuHistory.
                    Rectangle {
                        id: qsCpuPill
                        visible: barWindow.topBarShowQuickshellCpu && rightLayout.compactLevel < 2
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredHeight: barWindow.barHeight
                        // Slim on purpose — no icon, just the number, rotated to stand
                        // upright along the pill's height instead of running sideways,
                        // so the pill itself can stay narrow. Width is a fixed slim
                        // padding around the rotated text's line-height (not its
                        // unrotated implicitWidth, which would be the full "NN%" run).
                        Layout.preferredWidth: barWindow.s(11) + barWindow.s(12)
                        radius: barWindow.s(10)
                        width: Layout.preferredWidth
                        color: Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                        border.width: 1
                        border.color: barWindow.topBarAccentLine
                            ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.56)))
                            : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                        clip: true
                        // "areaV" — same history-fill idea as the grid chips' "area"
                        // kind, rotated so the graph reads top-to-bottom instead of
                        // left-to-right, matching this pill's standing shape.
                        PillBg {
                            kind: "areaV"
                            radius: qsCpuPill.radius
                            px: barWindow.s(1)
                            shown: barWindow.pillFxOn(barWindow.topBarCpuAreaMode, barWindow.qsCpuPct >= 35 || qsCpuHoverArea.containsMouse)
                            level: barWindow.qsCpuPct / 100
                            hist: barWindow.qsCpuHistory
                        }
                        Text {
                            id: qsCpuLabel
                            anchors.centerIn: parent
                            rotation: -90
                            text: Math.round(barWindow.qsCpuPct) + "%"
                            font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); font.weight: Font.Black
                            color: barWindow.qsCpuPct >= 35 ? mocha.red : (barWindow.qsCpuPct >= 20 ? mocha.peach : mocha.teal)
                        }
                        MouseArea { id: qsCpuHoverArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                    }

                    // Combined CPU/GPU/Net/Uptime stats module — no outer pill/box
                    // anymore, just the 4 mini-pills floating directly in the bar.
                    // Sits AFTER trayPill (to its right).
                    Item {
                        id: sysStatsPill
                        visible: rightLayout.compactLevel < 4
                        Layout.preferredHeight: barWindow.barHeight

                        // No resize Behavior — text (cpu%/gpu%/net-rate/uptime) can
                        // change digit-count on any 2-30s poll tick, instantly
                        // re-laying out the Row inside. An ANIMATED width lagging
                        // 300ms behind that instant text change is exactly what
                        // showed the text poking out past the pill's edge for that
                        // window — the container hadn't caught up yet. Resizing in
                        // the same frame as the text avoids the mismatch entirely.
                        // Was +s(18) — much more side padding than the individual chips
                        // (+s(9) each) or the qsCpu pill next to it, which made the gap
                        // around this whole group read bigger than the uniform s(4)
                        // rightLayout spacing everywhere else. Tightened to match.
                        property real targetWidth: statsGrid.width + barWindow.s(10)
                        Layout.preferredWidth: targetWidth

                        readonly property int hoverIdx: cpuChip.hovered ? 0 : (gpuChip.hovered ? 1 : (netChip.hovered ? 2 : (uptimeChip.hovered ? 3 : -1)))
                        readonly property bool cardKeep: hoverIdx >= 0 || statsCard.cardHovered
                        property int which: 0
                        property bool hoverConfirmed: false
                        property string cpuTemp: ""
                        property string cpuLoad: ""
                        property var cpuProcs: []
                        property var gpuInfo: []
                        property var netInfo: []
                        property string bootTime: ""
                        onHoverIdxChanged: if (hoverIdx >= 0) { which = hoverIdx; statsTipRun() }
                        onCardKeepChanged: {
                            if (cardKeep) {
                                statsCloseGrace.stop()
                                if (!hoverConfirmed) statsHoverDelay.restart()
                            } else {
                                statsHoverDelay.stop()
                                statsCloseGrace.restart()
                            }
                        }
                        Timer { id: statsHoverDelay; interval: 1000; onTriggered: sysStatsPill.hoverConfirmed = true }
                        Timer { id: statsCloseGrace; interval: 200; onTriggered: { statsHoverDelay.stop(); sysStatsPill.hoverConfirmed = false } }
                        Timer { interval: 1000; repeat: true; running: sysStatsPill.hoverConfirmed; onTriggered: if (!statsTipReader.running) sysStatsPill.statsTipRun() }
                        // Resident pill takeover for the shared cpu/gpu/net/uptime card —
                        // one card, "which" selects the visible page, same idea as the
                        // per-pill open_card force elsewhere in this file.
                        readonly property var residentWhichMap: ({ "cpu": 0, "gpu": 1, "net": 2, "uptime": 3 })
                        Connections {
                            target: barWindow
                            function onResidentPillBurstChanged() {
                                let w = sysStatsPill.residentWhichMap[barWindow.residentPillFlag.pill]
                                if (w === undefined) return
                                if (barWindow.residentPillFlag.open_card) {
                                    statsCloseGrace.stop()
                                    sysStatsPill.which = w
                                    sysStatsPill.statsTipRun()
                                    sysStatsPill.hoverConfirmed = true
                                    statsForceOpenTimer.interval = Math.max(200, ((barWindow.residentPillFlag.expires_ts || 0) - Date.now() / 1000) * 1000)
                                    statsForceOpenTimer.restart()
                                }
                            }
                        }
                        Timer { id: statsForceOpenTimer; onTriggered: if (!sysStatsPill.cardKeep) sysStatsPill.hoverConfirmed = false }
                        function statsTipCmd(w) {
                            if (w === 0) return ["bash", "-c",
                                "export LC_ALL=C; t=''; for h in /sys/class/hwmon/hwmon*; do n=$(cat $h/name 2>/dev/null); case $n in coretemp|k10temp) t=$(( $(cat $h/temp1_input) / 1000 )); break;; esac; done; " +
                                "echo \"T|$t\"; echo \"L|$(cut -d' ' -f1-3 /proc/loadavg)\"; " +
                                "top -bn2 -d 0.4 -o %CPU -w 512 | awk '/^top -/{n++} n==2 && /^ *[0-9]/{print \"P|\"$12\"|\"$9; c++; if(c==3)exit}'"]
                            if (w === 1) return ["bash", "-c",
                                "if nvidia-smi -L >/dev/null 2>&1; then nvidia-smi --query-gpu=name,memory.used,memory.total,temperature.gpu,power.draw --format=csv,noheader,nounits | awk -F', ' '{print \"G|\"$1\"|\"$2\"|\"$3\"|\"$4\"|\"$5}'; " +
                                "else d=$(ls -d /sys/class/drm/card*/device 2>/dev/null | head -1); [ -r \"$d/mem_info_vram_used\" ] && echo \"G|AMD GPU|$(( $(cat $d/mem_info_vram_used) / 1048576 ))|$(( $(cat $d/mem_info_vram_total) / 1048576 ))|$(cat $d/hwmon/hwmon*/temp1_input 2>/dev/null | head -1 | awk '{print $1/1000}')|\"; fi"]
                            if (w === 2) return ["bash", "-c",
                                "i=$(ip route | awk '/^default/{print $5; exit}'); a=$(ip -4 -o addr show dev \"$i\" 2>/dev/null | awk '{print $4; exit}'); " +
                                "rx=$(cat /sys/class/net/$i/statistics/rx_bytes 2>/dev/null); tx=$(cat /sys/class/net/$i/statistics/tx_bytes 2>/dev/null); " +
                                "ms=$(ping -c1 -W1 1.1.1.1 2>/dev/null | awk -F'time=' '/time=/{print $2}'); echo \"N|$i|$a|$rx|$tx|$ms\""]
                            return ["bash", "-c", "echo \"U|$(uptime -s)\""]
                        }
                        function statsTipRun() {
                            statsTipReader.running = false
                            statsTipReader.command = statsTipCmd(sysStatsPill.which)
                            statsTipReader.running = true
                        }
                        function fmtBytes(b) {
                            let n = parseFloat(b)
                            if (isNaN(n)) return "-"
                            if (n >= 1073741824) return (n / 1073741824).toFixed(2) + " GB"
                            if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB"
                            return (n / 1024).toFixed(0) + " KB"
                        }
                        Process {
                            id: statsTipReader
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let procs = []
                                    let lines = this.text.trim().split("\n")
                                    for (let i = 0; i < lines.length; i++) {
                                        let f = lines[i].split("|")
                                        if (f[0] === "T") sysStatsPill.cpuTemp = f[1] || ""
                                        else if (f[0] === "L") sysStatsPill.cpuLoad = f[1] || ""
                                        else if (f[0] === "P") procs.push({ name: f[1], pct: f[2] })
                                        else if (f[0] === "G") sysStatsPill.gpuInfo = f.slice(1)
                                        else if (f[0] === "N") sysStatsPill.netInfo = f.slice(1)
                                        else if (f[0] === "U") sysStatsPill.bootTime = f[1] || ""
                                    }
                                    if (procs.length > 0) sysStatsPill.cpuProcs = procs
                                }
                            }
                        }

                        Grid {
                            id: statsGrid
                            anchors.centerIn: parent
                            columns: rightLayout.compactLevel >= 1 ? 1 : 2
                            rowSpacing: barWindow.s(4)
                            columnSpacing: barWindow.s(4)

                            // Plain flat mini-pills, same family as the rest of the
                            // topbar's pills (surface0 @ 0.4, faint border). Each chip
                            // self-sizes to its own content (see StatChip below) rather
                            // than sharing one Math.max-derived width — that shared-size
                            // approach clipped/overflowed the uptime chip specifically on
                            // two separate rounds, not worth chasing a third time just to
                            // keep the 4 chips pixel-identical width.

                            // Same family as every other small pill in this bar (volume/
                            // wifi/kb): surface0 @ 0.4 fill + the shared ambient-cycling
                            // border, not a bespoke flat color — that mismatch (plus a
                            // different corner radius) was why these read as a separate,
                            // sore-thumb element instead of belonging with the rest.
                            component StatChip: Rectangle {
                                id: chip
                                default property alias content: chipRow.data
                                property alias chipRow: chipRow
                                property real ambientPhase: 0.2
                                // Flourish glow, built INTO the component as real properties
                                // rather than something a caller adds as a plain child Item —
                                // `default property alias content: chipRow.data` redirects
                                // EVERY direct child into chipRow (a Row), so a glow
                                // Rectangle added that way became a Row ITEM whose own
                                // anchors.fill:parent width fed back into chipRow's own
                                // width — a real circular binding that made the whole
                                // uptime chip vanish/misrender. This keeps the glow a true
                                // sibling of chipRow instead.
                                property color glowColor: "transparent"
                                property bool glowActive: false
                                radius: barWindow.s(10)
                                // Self-sized from its OWN content instead of a shared
                                // statsGrid.cellW/H (Math.max across all 4 rows) — that
                                // indirection kept coming out wrong for the uptime chip
                                // specifically (text clipped/poking out repeatedly even
                                // after the resize-Behavior fix), and "same width for all
                                // 4" isn't worth another round of this. Each chip now
                                // guarantees its own fit; they just won't all be identical
                                // width anymore.
                                width: chipRow.width + barWindow.s(9)
                                height: chipRow.height + barWindow.s(6)
                                color: Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                border.width: 1
                                border.color: barWindow.topBarAccentLine
                                    ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(chip.ambientPhase)))
                                    : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                                // Safety net — content should always exactly match cellW/H
                                // now that the resize Behavior is gone, but clip so any
                                // future edge case cuts cleanly at the rounded edge instead
                                // of visibly poking out past it.
                                clip: true
                                // Flourish glow overlay — declared HERE, inside the
                                // component's own definition (a real sibling of chipRow),
                                // not by a caller adding a plain child (which the default
                                // content alias below would silently redirect into chipRow
                                // itself, a Row — that's the exact circular-width bug that
                                // broke the uptime chip).
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: "transparent"
                                    border.width: barWindow.s(1.5)
                                    border.color: chip.glowColor
                                    opacity: chip.glowActive ? 0.9 : 0
                                    Behavior on opacity { NumberAnimation { duration: 220 } }
                                }
                                property string bgKind: ""
                                property bool bgOn: false
                                property real bgLevel: 0
                                property real bgRate: 0
                                property real bgRate2: 0
                                property int bgCount: 0
                                property var bgHist: []
                                PillBg {
                                    kind: chip.bgKind
                                    radius: chip.radius
                                    px: barWindow.s(1)
                                    shown: chip.bgKind !== "" && chip.bgOn
                                    level: chip.bgLevel
                                    rate: chip.bgRate
                                    rate2: chip.bgRate2
                                    count: chip.bgCount
                                    hist: chip.bgHist
                                }
                                // Resident pill takeover — declared inside the component
                                // itself (real sibling of chipRow, not a caller-added
                                // child) so the `default property alias content` above
                                // can't redirect it into chipRow.
                                property string residentKey: ""
                                PillBg {
                                    id: residentChipBg
                                    kind: barWindow.residentPillFlag.style === "border" ? "border" : "pulse"
                                    radius: chip.radius
                                    px: barWindow.s(1)
                                    tint: barWindow.residentPillFlag.tint || "#fab387"
                                    shown: chip.residentKey !== "" && barWindow.residentPillActive(chip.residentKey)
                                }
                                Connections {
                                    target: barWindow
                                    function onResidentPillBurstChanged() { if (chip.residentKey !== "" && barWindow.residentPillFlag.pill === chip.residentKey) residentChipBg.fire() }
                                }
                                readonly property bool hovered: chipHover.hovered
                                HoverHandler { id: chipHover }
                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: barWindow.s(4)
                                }
                            }

                            function sparkPaint(ctx, w, h, hist, lineColor) {
                                ctx.clearRect(0, 0, w, h)
                                if (!hist || hist.length < 2) return
                                var stepX = w / Math.max(1, (hist.length - 1))
                                ctx.strokeStyle = lineColor
                                ctx.lineWidth = Math.max(1, barWindow.s(1.4))
                                ctx.lineJoin = "round"; ctx.lineCap = "round"
                                ctx.beginPath()
                                for (var i = 0; i < hist.length; i++) {
                                    var x = i * stepX
                                    var y = h - (Math.min(100, hist[i]) / 100) * h
                                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                                }
                                ctx.stroke()
                                ctx.lineTo((hist.length - 1) * stepX, h)
                                ctx.lineTo(0, h)
                                ctx.closePath()
                                ctx.fillStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.18)
                                ctx.fill()
                            }

                            // CPU — always shown, no toggle. Sparkline matches the
                            // net/uptime cells' visual weight instead of being plain
                            // icon+number.
                            StatChip {
                                id: cpuChip
                                residentKey: "cpu"
                                ambientPhase: 0.08
                                bgKind: "area"
                                bgHist: barWindow.cpuHistory
                                bgLevel: barWindow.cpuPct / 100
                                bgOn: barWindow.pillFxOn(barWindow.topBarCpuAreaMode, barWindow.cpuPct >= 60 || cpuChip.hovered || barWindow.fxFlash("cpu"))
                                width: Math.max(cpuRow.width, netRow.width) + barWindow.s(9)
                                Row {
                                    id: cpuRow
                                    spacing: barWindow.s(5)
                                    readonly property color loadColor: barWindow.cpuPct >= 85 ? mocha.red : (barWindow.cpuPct >= 60 ? mocha.peach : mocha.green)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "󰘚"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(12); color: parent.loadColor }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.cpuPct + "%"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); font.weight: Font.Black; color: mocha.text; width: barWindow.s(24); horizontalAlignment: Text.AlignRight }
                                    // "Sigh" easter egg — kept, purely decorative.
                                    Repeater {
                                        model: barWindow.cpuSighing ? 3 : 0
                                        delegate: Item {
                                            anchors.centerIn: parent
                                            z: 5
                                            readonly property real xOff: (index - 1) * barWindow.s(10)
                                            Rectangle {
                                                id: sparkDot
                                                width: barWindow.s(2.5); height: barWindow.s(2.5)
                                                radius: width / 2
                                                color: mocha.green
                                                x: parent.xOff
                                                y: 0
                                                opacity: 0
                                                SequentialAnimation {
                                                    running: true
                                                    PauseAnimation { duration: index * 140 }
                                                    ParallelAnimation {
                                                        NumberAnimation { target: sparkDot; property: "opacity"; from: 0; to: 0.85; duration: 260; easing.type: Easing.OutQuad }
                                                        NumberAnimation { target: sparkDot; property: "y"; from: 0; to: -barWindow.s(14); duration: 900; easing.type: Easing.OutCubic }
                                                    }
                                                    NumberAnimation { target: sparkDot; property: "opacity"; to: 0; duration: 400; easing.type: Easing.InQuad }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // GPU — only rendered once gpu_usage.sh produces a value.
                            StatChip {
                                id: gpuChip
                                residentKey: "gpu"
                                ambientPhase: 0.2
                                bgKind: "area"
                                bgHist: barWindow.gpuHistory
                                bgLevel: barWindow.gpuPct / 100
                                bgOn: barWindow.pillFxOn(barWindow.topBarCpuAreaMode, barWindow.gpuPct >= 60 || gpuChip.hovered || barWindow.fxFlash("cpu"))
                                visible: barWindow.topBarShowGpu && barWindow.gpuAvailable && rightLayout.compactLevel < 1
                                width: Math.max(gpuRow.width, uptimeRow.width) + barWindow.s(9)
                                Row {
                                    id: gpuRow
                                    spacing: barWindow.s(5)
                                    readonly property color loadColor: barWindow.gpuPct >= 85 ? mocha.red : (barWindow.gpuPct >= 60 ? mocha.peach : mocha.green)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "󰢮"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(12); color: parent.loadColor }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.gpuPct + "%"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); font.weight: Font.Black; color: mocha.text; width: barWindow.s(24); horizontalAlignment: Text.AlignRight }
                                }
                            }

                            // Net rate — down/up, compact.
                            StatChip {
                                id: netChip
                                residentKey: "net"
                                ambientPhase: 0.32
                                bgKind: "particles"
                                bgRate: Math.min(1, Math.log(1 + barWindow.netDownBps / 1024) / Math.log(10241))
                                bgRate2: Math.min(1, Math.log(1 + barWindow.netUpBps / 1024) / Math.log(10241))
                                bgOn: barWindow.pillFxOn(barWindow.topBarNetParticlesMode, (barWindow.netDownBps + barWindow.netUpBps) > 102400 || netChip.hovered || barWindow.fxFlash("net"))
                                visible: barWindow.topBarShowNet
                                width: Math.max(cpuRow.width, netRow.width) + barWindow.s(9)
                                Row {
                                    id: netRow
                                    spacing: barWindow.s(3)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "󰇚"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(10); color: mocha.sapphire }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.fmtNetRate(barWindow.netDownBps); font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Black; color: mocha.text; width: barWindow.s(32); horizontalAlignment: Text.AlignRight }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "󰕒"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(10); color: mocha.peach }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.fmtNetRate(barWindow.netUpBps); font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Black; color: mocha.text; width: barWindow.s(32); horizontalAlignment: Text.AlignRight }
                                }
                            }

                            // Uptime — pure display.
                            StatChip {
                                id: uptimeChip
                                residentKey: "uptime"
                                ambientPhase: 0.44
                                bgKind: "stars"
                                bgCount: { let m = barWindow.uptimeStr.match(/(\d+)d/); return (m ? parseInt(m[1]) : 0) + 3 }
                                bgOn: barWindow.pillFxOn(barWindow.topBarUptimeStarsMode, uptimeChip.hovered || barWindow.fxFlash("uptime"))
                                visible: barWindow.topBarShowUptime && barWindow.uptimeStr !== "" && rightLayout.compactLevel < 1
                                // Reverted to plain icon+text, same minimal shape as the net
                                // rate chip right next to it — the flourish glow Rectangle
                                // added here was a direct child of the StatChip, which
                                // `default property alias content: chipRow.data` silently
                                // redirects into chipRow (a Row) instead of leaving it as a
                                // real overlay sibling — its own anchors.fill:parent width
                                // fed back into chipRow's width it was supposed to sit on
                                // top of, a real circular binding that broke the whole chip.
                                // Not worth re-fighting right now — plain and reliable wins.
                                glowColor: "#89dceb"
                                glowActive: barWindow.uptimeFlourishActive
                                width: Math.max(gpuRow.width, uptimeRow.width) + barWindow.s(9)
                                Row {
                                    id: uptimeRow
                                    spacing: barWindow.s(4)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "󰥔"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(11); color: mocha.teal }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.uptimeStr; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Black; color: mocha.text }
                                    // Uptime day-milestone flourish — same sparkDot idiom as
                                    // cpuSighing (search sparkDot), fixed-hex cyan, gated on
                                    // topBarFlourishUptimeEnabled. Test: echo uptime > /tmp/qs_topbar_test_flourish
                                    Repeater {
                                        model: barWindow.uptimeFlourishActive ? 3 : 0
                                        delegate: Item {
                                            anchors.centerIn: parent
                                            z: 5
                                            readonly property real xOff: (index - 1) * barWindow.s(10)
                                            Rectangle {
                                                id: uptimeSparkDot
                                                width: barWindow.s(2.5); height: barWindow.s(2.5)
                                                radius: width / 2
                                                color: "#89dceb"
                                                x: parent.xOff
                                                y: 0
                                                opacity: 0
                                                SequentialAnimation {
                                                    running: true
                                                    PauseAnimation { duration: index * 140 }
                                                    ParallelAnimation {
                                                        NumberAnimation { target: uptimeSparkDot; property: "opacity"; from: 0; to: 0.85; duration: 260; easing.type: Easing.OutQuad }
                                                        NumberAnimation { target: uptimeSparkDot; property: "y"; from: 0; to: -barWindow.s(14); duration: 900; easing.type: Easing.OutCubic }
                                                    }
                                                    NumberAnimation { target: uptimeSparkDot; property: "opacity"; to: 0; duration: 400; easing.type: Easing.InQuad }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                        }
                    }

                    Rectangle {
                        id: timerPill
                        visible: barWindow.topBarTimerEnabled && (rightLayout.compactLevel < 3 || barWindow.timerState !== "idle")
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredHeight: barWindow.barHeight
                        // Was +s(18), same oversized-padding inconsistency as the stats
                        // grid wrapper above — tightened to match the rest of the pills.
                        Layout.preferredWidth: timerRoll.width + barWindow.s(10)
                        Behavior on Layout.preferredWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        radius: barWindow.s(10)
                        readonly property bool running: barWindow.timerState === "running"
                        readonly property bool paused: barWindow.timerState === "paused"
                        readonly property bool active: running || paused
                        readonly property bool lastMinute: active && barWindow.timerRemainingNow <= 60
                        readonly property bool confirming: barWindow.timerConfirmStop && active
                        readonly property real fraction: barWindow.timerDurationSecs > 0 ? Math.min(1, barWindow.timerRemainingNow / barWindow.timerDurationSecs) : 0
                        readonly property bool fillVisible: active && barWindow.topBarTimerFillMode !== "never"
                            && (barWindow.topBarTimerFillMode === "always" || timerMouse.containsMouse || lastMinute || confirming)
                        readonly property color stateCol: confirming || lastMinute ? "#f38ba8" : (running ? "#fab387" : (paused ? "#89b4fa" : "#b4befe"))
                        readonly property color stateCol2: confirming || lastMinute ? "#eba0ac" : (running ? "#f9e2af" : (paused ? "#74c7ec" : "#89b4fa"))
                        property real breath: 0
                        property real popScale: 1.0
                        property real pausePulse: 1.0
                        property real wavePhase: 0
                        transformOrigin: Item.Center
                        scale: popScale * (timerMouse.containsMouse ? 1.04 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        onRunningChanged: popAnim.restart()
                        onPausedChanged: popAnim.restart()
                        SequentialAnimation {
                            id: popAnim
                            NumberAnimation { target: timerPill; property: "popScale"; to: 1.12; duration: 110; easing.type: Easing.OutCubic }
                            NumberAnimation { target: timerPill; property: "popScale"; to: 1.0; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                        }
                        SequentialAnimation on breath {
                            running: timerPill.running && timerPill.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: 1; duration: 1400; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0; duration: 1400; easing.type: Easing.InOutSine }
                        }
                        SequentialAnimation on pausePulse {
                            running: timerPill.paused && timerPill.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.6; duration: 1600; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 1600; easing.type: Easing.InOutSine }
                        }
                        Timer {
                            interval: 60; repeat: true
                            running: timerPill.running && timerPill.fillVisible && timerPill.visible
                            onTriggered: timerPill.wavePhase += 0.35
                        }
                        opacity: paused ? pausePulse : 1.0
                        color: Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, timerMouse.containsMouse ? 0.6 : 0.4)
                        Behavior on color { ColorAnimation { duration: 200 } }
                        border.width: 1
                        border.color: Qt.rgba(stateCol.r, stateCol.g, stateCol.b, 0.22 + 0.28 * breath + (confirming ? 0.3 : 0))
                        Behavior on border.color { ColorAnimation { duration: 300 } }

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.rgba(timerPill.stateCol.r, timerPill.stateCol.g, timerPill.stateCol.b, timerPill.active ? 0.20 : 0.12); Behavior on color { ColorAnimation { duration: 400 } } }
                                GradientStop { position: 1.0; color: Qt.rgba(timerPill.stateCol2.r, timerPill.stateCol2.g, timerPill.stateCol2.b, timerPill.active ? 0.08 : 0.04); Behavior on color { ColorAnimation { duration: 400 } } }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.09) }
                                GradientStop { position: 0.5; color: "transparent" }
                            }
                        }

                        Canvas {
                            id: timerFill
                            anchors.fill: parent
                            opacity: timerPill.fillVisible ? 1 : 0
                            visible: opacity > 0.01
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            property real frac: timerPill.fraction
                            property color col: timerPill.stateCol
                            property real alpha: timerPill.paused ? 0.12 : 0.26
                            property real phase: timerPill.wavePhase
                            onFracChanged: requestPaint()
                            onColChanged: requestPaint()
                            onAlphaChanged: requestPaint()
                            onPhaseChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            onPaint: {
                                let ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                if (frac <= 0.001) return
                                let i = 1, w = width, h = height, r = Math.max(1, timerPill.radius - i)
                                ctx.save()
                                ctx.beginPath()
                                ctx.moveTo(i + r, i); ctx.lineTo(w - i - r, i); ctx.arcTo(w - i, i, w - i, i + r, r)
                                ctx.lineTo(w - i, h - i - r); ctx.arcTo(w - i, h - i, w - i - r, h - i, r)
                                ctx.lineTo(i + r, h - i); ctx.arcTo(i, h - i, i, h - i - r, r)
                                ctx.lineTo(i, i + r); ctx.arcTo(i, i, i + r, i, r)
                                ctx.closePath()
                                ctx.clip()
                                let edge = w * frac
                                let amp = Math.min(barWindow.s(2.2), edge * 0.2)
                                let g = ctx.createLinearGradient(0, 0, Math.max(1, edge), 0)
                                g.addColorStop(0, Qt.rgba(col.r, col.g, col.b, alpha * 0.55))
                                g.addColorStop(1, Qt.rgba(col.r, col.g, col.b, alpha))
                                ctx.fillStyle = g
                                ctx.beginPath()
                                ctx.moveTo(0, 0)
                                ctx.lineTo(edge + Math.sin(phase) * amp, 0)
                                let steps = 10
                                for (let k = 1; k <= steps; k++) {
                                    let yy = h * k / steps
                                    ctx.lineTo(edge + Math.sin(phase + k * 0.9) * amp, yy)
                                }
                                ctx.lineTo(0, h)
                                ctx.closePath()
                                ctx.fill()
                                ctx.restore()
                            }
                        }

                        Rectangle {
                            id: timerBurst
                            anchors.centerIn: parent
                            width: parent.width; height: parent.height
                            radius: parent.radius
                            color: "transparent"
                            border.width: barWindow.s(1.5)
                            border.color: "#a6e3a1"
                            opacity: 0
                            scale: 1
                            ParallelAnimation {
                                running: barWindow.timerFlash
                                loops: 2
                                NumberAnimation { target: timerBurst; property: "scale"; from: 1; to: 1.7; duration: 700; easing.type: Easing.OutCubic }
                                SequentialAnimation {
                                    NumberAnimation { target: timerBurst; property: "opacity"; from: 0.9; to: 0.9; duration: 1 }
                                    NumberAnimation { target: timerBurst; property: "opacity"; to: 0; duration: 700; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.width: barWindow.s(1.5)
                            border.color: "#a6e3a1"
                            opacity: 0
                            SequentialAnimation on opacity {
                                running: barWindow.timerFlash
                                loops: 3
                                NumberAnimation { to: 0.95; duration: 180 }
                                NumberAnimation { to: 0; duration: 320 }
                            }
                        }

                        Item {
                            id: timerRoll
                            anchors.centerIn: parent
                            height: barWindow.s(17)
                            width: timerSizer.implicitWidth
                            clip: true
                            opacity: timerPill.paused ? 0.55 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            readonly property string wantText: timerPill.confirming ? "stop?" : barWindow.timerFmt(barWindow.timerRemainingNow, timerPill.active)
                            readonly property color textColor: (timerPill.confirming || timerPill.lastMinute) ? "#f38ba8" : (timerPill.active ? mocha.text : mocha.subtext1)
                            property string shown: ""
                            property int prevRem: 0
                            property int dir: 1
                            Component.onCompleted: { shown = wantText; prevRem = barWindow.timerRemainingNow; timerIn.text = wantText }

                            Text { id: timerSizer; visible: false; text: timerRoll.wantText; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Black }
                            Text {
                                id: timerOut
                                anchors.horizontalCenter: parent.horizontalCenter
                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Black
                                color: timerRoll.textColor
                                opacity: 0
                                y: 0
                            }
                            Text {
                                id: timerIn
                                anchors.horizontalCenter: parent.horizontalCenter
                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Black
                                color: timerRoll.textColor
                                y: 0
                            }
                            onWantTextChanged: {
                                if (wantText === shown) return
                                let rem = barWindow.timerRemainingNow
                                dir = rem >= prevRem ? 1 : -1
                                prevRem = rem
                                timerOut.text = shown
                                timerOut.y = 0; timerOut.opacity = 1
                                timerIn.text = wantText
                                timerIn.y = dir > 0 ? height : -height
                                timerIn.opacity = 0
                                timerRollAnim.restart()
                                shown = wantText
                            }
                            ParallelAnimation {
                                id: timerRollAnim
                                NumberAnimation { target: timerIn; property: "y"; to: 0; duration: 240; easing.type: Easing.OutCubic }
                                NumberAnimation { target: timerOut; property: "y"; to: timerRoll.dir > 0 ? -timerRoll.height : timerRoll.height; duration: 240; easing.type: Easing.OutCubic }
                                NumberAnimation { target: timerIn; property: "opacity"; to: 1; duration: 180 }
                                NumberAnimation { target: timerOut; property: "opacity"; to: 0; duration: 180 }
                            }
                        }

                        property bool ctrlHeld: false
                        Process {
                            id: timerCtrlWatcher
                            running: timerMouse.containsMouse
                            command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "exec sg input -c 'exec python3 /home/czeddaru/.config/hypr/scripts/quickshell/ctrl_watch.py'"]
                            stdout: SplitParser {
                                splitMarker: "\n"
                                onRead: (line) => { timerPill.ctrlHeld = line.trim() === "1" }
                            }
                            onRunningChanged: { if (!running) timerPill.ctrlHeld = false }
                        }
                        MouseArea {
                            id: timerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            property real wheelAcc: 0
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    barWindow.timerConfirmStop = false
                                    barWindow.timerPause()
                                } else if (barWindow.timerConfirmStop && timerPill.active) {
                                    barWindow.timerStop()
                                } else if (barWindow.timerState === "idle") {
                                    barWindow.timerStart()
                                }
                            }
                            onDoubleClicked: (mouse) => {
                                if (mouse.button !== Qt.LeftButton || !timerPill.active) return
                                if (Date.now() - barWindow.timerLastStartMs < 600) return
                                barWindow.timerConfirmStop = true
                                timerConfirmTimer.restart()
                            }
                            onWheel: (wheel) => {
                                let d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
                                wheelAcc += d
                                let step = ((wheel.modifiers & Qt.ControlModifier) || timerPill.ctrlHeld) ? 3600 : 60
                                while (Math.abs(wheelAcc) >= 120) {
                                    barWindow.timerAdjust(wheelAcc > 0 ? step : -step)
                                    wheelAcc += wheelAcc > 0 ? -120 : 120
                                }
                                wheel.accepted = true
                            }
                        }
                    }

                    // Scrollable System Capsule — scroll to page between [Vol+Battery] and [KB/WiFi/BT]
                    Rectangle {
                        id: sysCapsule
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredHeight: barWindow.barHeight
                        radius: barWindow.s(14)
                        border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08)
                        border.width: 1
                        color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                        // Any of the 4 hover cards now spans the WHOLE capsule (not just
                        // its own inner button), so it's the capsule's own bottom corners
                        // that need to square off flush against it, not each inner pill's.
                        bottomLeftRadius: ((volTip.visible && volWrap.hoverConfirmed) || (batTip.visible && batteryStatusPill.hoverConfirmed) || (wifiTip.visible && wifiWrap.hoverConfirmed) || (btTip.visible && btWrap.hoverConfirmed)) ? 0 : radius
                        bottomRightRadius: ((volTip.visible && volWrap.hoverConfirmed) || (batTip.visible && batteryStatusPill.hoverConfirmed) || (wifiTip.visible && wifiWrap.hoverConfirmed) || (btTip.visible && btWrap.hoverConfirmed)) ? 0 : radius
                        clip: true

                        property int pillHeight: barWindow.s(34)
                        property int sysPage: 0          // 0 = vol/battery, 1 = kb/wifi/bt, 2 = quick-toggle directory
                        readonly property int pageCount: 3

                        // Page 2 — read-only "current state" snapshot of the transient-OSD-backed
                        // toggles (wakelock, mic-mute, idle-lock, night-light override, brightness
                        // curve). Polled via sys_toggles.sh, same JSON-poll shape as sys_info.sh.
                        property bool tgWakelock: false
                        property bool tgMicMuted: false
                        property bool tgIdlePaused: false
                        property string tgNlMode: "auto"
                        property bool tgBrightnessCurve: true
                        property bool tgKandorEnabled: false

                        Process {
                            id: togglesPoller
                            running: true
                            command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "exec ~/.config/hypr/scripts/quickshell/sys_toggles_daemon.sh"]
                            stdout: SplitParser {
                                splitMarker: "\n"
                                onRead: (line) => {
                                    if (!line || !line.trim().length) return
                                    try {
                                        let d = JSON.parse(line)
                                        sysCapsule.tgWakelock = !!d.wakelock
                                        sysCapsule.tgMicMuted = !!d.mic_muted
                                        sysCapsule.tgIdlePaused = !!d.idle_paused
                                        sysCapsule.tgNlMode = d.nl_mode || "auto"
                                        sysCapsule.tgBrightnessCurve = !!d.brightness_curve
                                        sysCapsule.tgKandorEnabled = !!d.kandor_enabled
                                    } catch (e) { }
                                }
                            }
                        }

                        // direction-aware page switch: incoming enters from scroll side, outgoing exits opposite
                        function cyclePage(dir) {
                            let np = (sysPage + dir + pageCount) % pageCount
                            if (np === sysPage) return
                            let H = barWindow.barHeight
                            let rows = [page0Row, page1Row, page2Row]
                            let incoming = rows[np]
                            let outgoing = rows[sysPage]
                            incoming.snapTo(dir > 0 ? H : -H)   // down → enter from below
                            incoming.ty = 0
                            outgoing.ty = dir > 0 ? -H : H      // down → exit to top
                            sysPage = np
                            // Always land on page2's first pill rather than wherever a
                            // previous visit's wheel-scroll left off.
                            if (np === 2) page2Viewport.scrollX = 0
                        }

                        // Resident pill takeover can target a pill that's hidden on a
                        // different sysCapsule page (e.g. "wifi" while sysPage is on
                        // vol/battery) — without this, the tint/pulse fires off-screen
                        // and the user never sees it, same root cause as "can't see wifi
                        // if not scrolled onto it". Reuses cyclePage()'s own 380ms
                        // OutCubic per-row animation, just triggered programmatically
                        // instead of by the wheel, so it matches manual scroll exactly.
                        readonly property var pillPageMap: ({
                            "volume": 0, "battery": 0,
                            "wifi": 1, "bt": 1,
                            "wakelock": 2, "mic": 2, "idle": 2, "nl": 2, "brightness": 2, "kandor": 2
                        })
                        function scrollToPillIfNeeded(name) {
                            let target = sysCapsule.pillPageMap[name]
                            if (target === undefined || target === sysCapsule.sysPage) return
                            let diff = (target - sysCapsule.sysPage + sysCapsule.pageCount) % sysCapsule.pageCount
                            sysCapsule.cyclePage(diff === 1 ? 1 : -1)
                        }
                        Connections {
                            target: barWindow
                            function onResidentPillBurstChanged() { sysCapsule.scrollToPillIfNeeded(barWindow.residentPillFlag.pill) }
                        }

                        // Caps how wide page2's 6-pill row is allowed to stretch the
                        // capsule — the rest scrolls into view via mouse wheel instead
                        // of forcing the bar to balloon out (trayPill's maxVisible idiom).
                        property real page2ViewportCap: barWindow.s(260)
                        property real targetWidth: (sysPage === 0 ? page0Row.width : (sysPage === 1 ? page1Row.width : Math.min(page2Row.width, page2ViewportCap))) + barWindow.s(22)
                        Layout.preferredWidth: targetWidth
                        Layout.maximumWidth: targetWidth
                        Behavior on Layout.preferredWidth { NumberAnimation { duration: 420; easing.type: Easing.OutExpo } }

                        // --- PAGE 0: Volume + Battery ---
                        Row {
                            id: page0Row
                            anchors.centerIn: parent
                            spacing: barWindow.s(8)
                            property real ty: 0
                            property bool animEnabled: true
                            function snapTo(v) { animEnabled = false; ty = v; animEnabled = true }
                            transform: Translate { y: page0Row.ty }
                            Behavior on ty { enabled: page0Row.animEnabled; NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

                            // Volume — wrapped in a non-clipping Item so the hover
                            // tooltip (rendered outside the pill's own clipped
                            // bounds) doesn't get cut off by the pill's clip:true.
                            Item {
                                id: volWrap
                                anchors.verticalCenter: parent.verticalCenter
                                width: volPill.width; height: volPill.height

                                // Hover-card data: default sink description + mic mute.
                                // Only fetched while hovered and hover cards are enabled.
                                property string sinkDesc: ""
                                property bool micMuted: false
                                property bool hoverConfirmed: false
                                property var mixSinks: []
                                property var mixApps: []
                                property string defSink: ""
                                readonly property bool cardKeep: volPill.isHovered || volTip.cardHovered
                                Timer { id: volHoverDelay; interval: 1000; onTriggered: volWrap.hoverConfirmed = true }
                                Timer { id: volCloseGrace; interval: 200; onTriggered: { volHoverDelay.stop(); volWrap.hoverConfirmed = false } }
                                Timer { id: volMixPoll; interval: 1000; repeat: true; running: volWrap.hoverConfirmed; onTriggered: { if (!volMixReader.running) volMixReader.running = true; if (!volTipReader.running) volTipReader.running = true } }
                                Connections {
                                    target: barWindow
                                    function onVolPercentChanged() { if (volWrap.hoverConfirmed) volMixSoon.restart() }
                                    function onIsMutedChanged() { if (volWrap.hoverConfirmed) volMixSoon.restart() }
                                }
                                Timer { id: volMixSoon; interval: 250; onTriggered: { volMixReader.running = false; volMixReader.running = true } }
                                Process {
                                    id: volMixReader
                                    command: ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/vol_mix.sh"]
                                    stdout: StdioCollector {
                                        onStreamFinished: {
                                            let lines = this.text.trim().split("\n")
                                            for (let i = 0; i < lines.length; i++) {
                                                let k = lines[i].indexOf("|")
                                                if (k < 0) continue
                                                let tag = lines[i].slice(0, k), val = lines[i].slice(k + 1)
                                                if (tag === "D") volWrap.defSink = val
                                                else if (tag === "S" || tag === "A") {
                                                    try {
                                                        let arr = JSON.parse(val)
                                                        if (tag === "S") volWrap.mixSinks = arr
                                                        else volWrap.mixApps = arr
                                                    } catch (e) {}
                                                }
                                            }
                                        }
                                    }
                                }
                                Process {
                                    id: volTipReader
                                    command: ["bash", "-c",
                                        "sink=$(pactl get-default-sink 2>/dev/null); " +
                                        "desc=$(pactl list sinks 2>/dev/null | awk -v s=\"$sink\" 'BEGIN{f=0} /^Sink #/{f=0} $0 ~ \"Name: \"s{f=1} f && /Description:/{sub(/^[ \\t]*Description: /,\"\");print;exit}'); " +
                                        "mm=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q MUTED && echo 1 || echo 0); " +
                                        "printf '%s\\n%s' \"${desc:-Unknown device}\" \"$mm\""]
                                    stdout: StdioCollector {
                                        onStreamFinished: {
                                            let lines = this.text.trim().split("\n")
                                            volWrap.sinkDesc = lines[0] || "Unknown device"
                                            volWrap.micMuted = lines[1] === "1"
                                        }
                                    }
                                }
                                onVisibleChanged: {}
                                onCardKeepChanged: {
                                    if (cardKeep) {
                                        volCloseGrace.stop()
                                        volTipReader.running = false; volTipReader.running = true
                                        volMixReader.running = false; volMixReader.running = true
                                        if (!hoverConfirmed) volHoverDelay.restart()
                                    } else {
                                        volHoverDelay.stop()
                                        volCloseGrace.restart()
                                    }
                                }

                            Rectangle {
                                id: volPill
                                property bool isHovered: volMouse.containsMouse
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                radius: barWindow.s(10); height: sysCapsule.pillHeight
                                width: volLayoutRow.width + barWindow.s(24)
                                scale: isHovered ? 1.05 : 1.0
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: -barWindow.s(3); radius: barWindow.s(13)
                                    color: Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 1)
                                    opacity: parent.isHovered ? 0.14 : 0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                                Rectangle {
                                    anchors.fill: parent; radius: barWindow.s(10)
                                    opacity: barWindow.isSoundActive ? 0.20 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 300 } }
                                    gradient: Gradient { orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: mocha.peach }
                                        GradientStop { position: 1.0; color: Qt.lighter(mocha.peach, 1.3) } }
                                }
                                Canvas {
                                    id: volFill
                                    anchors.fill: parent
                                    readonly property string mode: barWindow.topBarVolumeFillMode
                                    readonly property bool shown: mode === "always" || (mode === "occasional" && (barWindow.volFillFlash || volPill.isHovered))
                                    opacity: shown ? 1 : 0
                                    visible: opacity > 0.01
                                    Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                                    readonly property real level: Math.max(0, Math.min(1, (parseInt(barWindow.volPercent) || 0) / 100))
                                    property real animLevel: level
                                    Behavior on animLevel { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    property real rippleT: 1
                                    readonly property color tint: barWindow.isMuted ? "#6c7086" : "#fab387"
                                    onAnimLevelChanged: requestPaint()
                                    onRippleTChanged: requestPaint()
                                    onTintChanged: requestPaint()
                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()
                                    Connections {
                                        target: barWindow
                                        function onVolPercentChanged() { if (volFill.shown) volRippleAnim.restart() }
                                    }
                                    NumberAnimation { id: volRippleAnim; target: volFill; property: "rippleT"; from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic }
                                    onPaint: {
                                        let ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        let w = width, h = height, r = volPill.radius
                                        ctx.save()
                                        ctx.beginPath()
                                        ctx.moveTo(r, 0); ctx.lineTo(w - r, 0); ctx.arcTo(w, 0, w, r, r)
                                        ctx.lineTo(w, h - r); ctx.arcTo(w, h, w - r, h, r)
                                        ctx.lineTo(r, h); ctx.arcTo(0, h, 0, h - r, r)
                                        ctx.lineTo(0, r); ctx.arcTo(0, 0, r, 0, r)
                                        ctx.closePath()
                                        ctx.clip()
                                        let t = tint
                                        let bw = w * animLevel
                                        if (bw > 0.5) {
                                            let g = ctx.createLinearGradient(0, 0, bw, 0)
                                            g.addColorStop(0, Qt.rgba(t.r, t.g, t.b, 0.30))
                                            g.addColorStop(0.8, Qt.rgba(t.r, t.g, t.b, 0.30))
                                            g.addColorStop(1, Qt.rgba(t.r, t.g, t.b, 0.0))
                                            ctx.fillStyle = g
                                            ctx.fillRect(0, 0, bw, h)
                                        }
                                        if (rippleT < 1) {
                                            let rr = (barWindow.s(4) + rippleT * barWindow.s(24)) / 2
                                            ctx.strokeStyle = Qt.rgba(t.r, t.g, t.b, (1 - rippleT) * 0.6)
                                            ctx.lineWidth = barWindow.s(1.5)
                                            ctx.beginPath()
                                            ctx.arc(bw, h / 2, rr, 0, Math.PI * 2)
                                            ctx.stroke()
                                        }
                                        ctx.restore()
                                    }
                                }
                                PillBg {
                                    id: residentVolBg
                                    kind: barWindow.residentPillFlag.style === "border" ? "border" : "pulse"
                                    radius: volPill.radius
                                    px: barWindow.s(1)
                                    tint: barWindow.residentPillFlag.tint || "#fab387"
                                    shown: barWindow.residentPillActive("volume")
                                }
                                Connections {
                                    target: barWindow
                                    function onResidentPillBurstChanged() {
                                        if (barWindow.residentPillFlag.pill !== "volume") return
                                        residentVolBg.fire()
                                        if (barWindow.residentPillFlag.open_card) {
                                            volCloseGrace.stop()
                                            volWrap.hoverConfirmed = true
                                            volForceOpenTimer.interval = Math.max(200, ((barWindow.residentPillFlag.expires_ts || 0) - Date.now() / 1000) * 1000)
                                            volForceOpenTimer.restart()
                                        }
                                    }
                                }
                                Timer { id: volForceOpenTimer; onTriggered: if (!volWrap.cardKeep) volWrap.hoverConfirmed = false }
                                Row {
                                    id: volLayoutRow; anchors.centerIn: parent; spacing: barWindow.s(8)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.volIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16); color: barWindow.isSoundActive ? mocha.peach : mocha.subtext0 }
                                    RollText { anchors.verticalCenter: parent.verticalCenter; val: barWindow.volPercent; pixelSize: barWindow.s(13); rollH: barWindow.s(17); color: barWindow.isSoundActive ? mocha.peach : mocha.text }
                                }
                                MouseArea {
                                    id: volMouse; hoverEnabled: true; anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton) {
                                            Quickshell.execDetached(["bash", "-c", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"])
                                        } else {
                                            Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle volume"])
                                        }
                                    }
                                    onWheel: (wheel) => {
                                        // horizontal scroll over volume = change volume; vertical falls through to page-scroll
                                        if (Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y)) {
                                            Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/volume_step.sh", wheel.angleDelta.x > 0 ? "lower" : "raise"])
                                            wheel.accepted = true
                                        } else {
                                            wheel.accepted = false
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                id: volTip
                                readonly property bool cardHovered: volTipHover.hovered
                                HoverHandler { id: volTipHover; enabled: volWrap.hoverConfirmed }
                                visible: barWindow.topBarHoverCardsEnabled && (volWrap.cardKeep || volWrap.hoverConfirmed)
                                opacity: volWrap.hoverConfirmed ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                // Grows out of the pill (flush, scaled from its top edge)
                                // with a capped mouse-follow wiggle — same treatment as
                                // weatherTip above.
                                transformOrigin: Item.Top
                                scale: volWrap.hoverConfirmed ? 1.0 : barWindow.volHoverGrowScale
                                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                                // Reparented onto centerBox to escape sysCapsule's own
                                // clip:true (a small fixed-height paged pill) — a plain
                                // Rectangle ancestor, not a Layout (a Layout overrides a
                                // child's plain width/height, which is what silently
                                // collapsed this to a frameless sliver before).
                                parent: centerBox
                                // Spans the WHOLE sysCapsule (vol+battery together, the
                                // outer rounded container both actually sit inside) rather
                                // than just volPill's own narrow inner button — matching
                                // just the button made it uselessly cramped for any real
                                // content.
                                x: rightLayout.x - centerBox.x + sysCapsule.x
                                y: centerBox.height - barWindow.volHoverOverlap
                                width: sysCapsule.width
                                height: volTipCol.implicitHeight + barWindow.s(14)
                                radius: barWindow.s(14)
                                topLeftRadius: 0
                                topRightRadius: 0
                                color: barWindow.cardFill
                                border.width: 1
                                border.color: barWindow.topBarAccentLine
                                    ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.6)))
                                    : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                                clip: true
                                z: 100
                                Rectangle {
                                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                    height: 1
                                    color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                                }
                                // Narrow pill (icon+percent only), so this has to actually
                                // fit at that width rather than trying to cram the full
                                // sink description in — single-line ellipsis reads far
                                // better here than word-wrap, which was breaking mid-word
                                // ("400 Series..." / "Mic mu[ted]") in anything this tight.
                                Column {
                                    id: volTipCol
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: barWindow.s(14)
                                    width: parent.width - barWindow.s(24)
                                    spacing: barWindow.s(5)
                                    Row {
                                        visible: volWrap.mixSinks.length === 0
                                        spacing: barWindow.s(6)
                                        width: parent.width
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: "󰓃"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(13); color: mocha.peach }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: volWrap.sinkDesc; width: parent.width - barWindow.s(20); elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: mocha.text }
                                    }
                                    Repeater {
                                        model: volWrap.mixSinks
                                        Rectangle {
                                            width: volTipCol.width; height: barWindow.s(22); radius: barWindow.s(6)
                                            readonly property bool isDefault: modelData.n === volWrap.defSink
                                            color: volSinkMa.containsMouse ? Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08) : "transparent"
                                            Row {
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.left: parent.left; anchors.right: parent.right
                                                anchors.leftMargin: barWindow.s(4); anchors.rightMargin: barWindow.s(4)
                                                spacing: barWindow.s(6)
                                                Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.isDefault ? "󰓃" : "󰓄"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(13); color: parent.parent.isDefault ? mocha.peach : mocha.overlay1 }
                                                Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.d; width: parent.width - barWindow.s(20); elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: parent.parent.isDefault ? Font.Bold : Font.Normal; color: parent.parent.isDefault ? mocha.text : mocha.subtext1 }
                                            }
                                            MouseArea {
                                                id: volSinkMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: { Quickshell.execDetached(["pactl", "set-default-sink", modelData.n]); volMixSoon.restart() }
                                            }
                                        }
                                    }
                                    Row {
                                        spacing: barWindow.s(6)
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: volWrap.micMuted ? "󰍭" : "󰍬"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(11); color: volWrap.micMuted ? mocha.red : mocha.green }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: volWrap.micMuted ? "Mic muted" : "Mic live"
                                            font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold
                                            color: volWrap.micMuted ? mocha.red : mocha.green
                                        }
                                    }
                                    Rectangle { visible: volWrap.mixApps.length > 0; width: parent.width; height: 1; color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08) }
                                    Repeater {
                                        model: volWrap.mixApps.slice(0, 4)
                                        Row {
                                            id: appRow
                                            width: volTipCol.width
                                            spacing: barWindow.s(6)
                                            readonly property real pct: appBarMa.pressed ? Math.max(0, Math.min(1, appBarMa.mouseX / appBar.width)) * 100 : (modelData.p ? mediaBox.playerVol * 100 : modelData.v)
                                            Text { anchors.verticalCenter: parent.verticalCenter; width: barWindow.s(52); text: modelData.a; elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); color: modelData.m ? mocha.overlay0 : mocha.subtext1 }
                                            Item {
                                                id: appBar
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - barWindow.s(52) - barWindow.s(30) - barWindow.s(12)
                                                height: barWindow.s(14)
                                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: barWindow.s(4); radius: height / 2; color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.12) }
                                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * Math.min(1, appRow.pct / 100); height: barWindow.s(4); radius: height / 2; color: modelData.m ? mocha.overlay0 : mocha.peach }
                                                MouseArea {
                                                    id: appBarMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    onReleased: (m) => {
                                                        let f = Math.max(0, Math.min(1, m.x / appBar.width))
                                                        if (modelData.p) {
                                                            mediaBox.playerVol = f
                                                            Quickshell.execDetached(["playerctl", "--player=spotify", "volume", f.toFixed(2)])
                                                        } else {
                                                            Quickshell.execDetached(["pactl", "set-sink-input-volume", String(modelData.i), Math.round(f * 100) + "%"])
                                                        }
                                                        volMixSoon.restart()
                                                    }
                                                }
                                            }
                                            Text { anchors.verticalCenter: parent.verticalCenter; width: barWindow.s(30); horizontalAlignment: Text.AlignRight; text: Math.round(appRow.pct) + "%"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); color: mocha.overlay1 }
                                        }
                                    }
                                }

                            }
                            }

                            // Battery / Power
                            Rectangle {
                                id: batteryStatusPill
                                property bool isHovered: batMouse.containsMouse
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                radius: barWindow.s(10); height: sysCapsule.pillHeight
                                width: barWindow.isDesktop ? barWindow.s(34) : batLayoutRow.width + barWindow.s(24)
                                anchors.verticalCenter: parent.verticalCenter
                                clip: false
                                scale: isHovered ? 1.05 : 1.0
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                Behavior on color { ColorAnimation { duration: 200 } }

                                // Status-reactive glow behind the battery pill — soft pulse in
                                // fixed (non-matugen) hex so it stays visually distinct low-batt
                                // red vs charging green regardless of wallpaper palette, per the
                                // "never rely on matugen names for glow semantics" convention.
                                // Lives INSIDE batteryStatusPill (not as a Row sibling) — a Row
                                // silently refuses to position any direct child that uses
                                // anchors.centerIn, which was collapsing every pill in page0Row
                                // to x=0 and cascading into the sysCapsule/rightLayout width
                                // math, cutting the whole right side of the bar off-screen.
                                Item {
                                    id: batteryGlowRoot
                                    anchors.fill: parent
                                    z: -1
                                    visible: !barWindow.isDesktop && (barWindow.isCharging || barWindow.batCap <= 20)

                                    readonly property color glowHex: barWindow.isCharging ? "#a6e3a1" : "#f38ba8"
                                    property real pulse: 0.4
                                    SequentialAnimation on pulse {
                                        loops: Animation.Infinite
                                        running: batteryGlowRoot.visible
                                        NumberAnimation { to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 0.4; duration: 1100; easing.type: Easing.InOutSine }
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width + barWindow.s(14) * batteryGlowRoot.pulse
                                        height: parent.height + barWindow.s(14) * batteryGlowRoot.pulse
                                        radius: height / 2
                                        color: batteryGlowRoot.glowHex
                                        opacity: 0.16 * batteryGlowRoot.pulse
                                        Behavior on color { ColorAnimation { duration: 300 } }
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width + barWindow.s(4)
                                        height: parent.height + barWindow.s(4)
                                        radius: height / 2
                                        color: batteryGlowRoot.glowHex
                                        opacity: 0.28 * batteryGlowRoot.pulse
                                        Behavior on color { ColorAnimation { duration: 300 } }
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent; anchors.margins: -barWindow.s(3); radius: barWindow.s(13)
                                    color: Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 1)
                                    opacity: parent.isHovered ? 0.14 : 0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                                Rectangle {
                                    anchors.fill: parent; radius: barWindow.s(10)
                                    opacity: barWindow.isDesktop ? 0.20 : ((barWindow.isCharging || barWindow.batCap <= 20) ? 0.09 : 0.0)
                                    Behavior on opacity { NumberAnimation { duration: 300 } }
                                    gradient: Gradient { orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: barWindow.isDesktop ? mocha.red : barWindow.batDynamicColor; Behavior on color { ColorAnimation { duration: 300 } } }
                                        GradientStop { position: 1.0; color: barWindow.isDesktop ? Qt.lighter(mocha.red, 1.3) : Qt.lighter(barWindow.batDynamicColor, 1.3); Behavior on color { ColorAnimation { duration: 300 } } } }
                                }
                                Canvas {
                                    id: batFill
                                    anchors.fill: parent
                                    readonly property string mode: barWindow.topBarBatteryLiquidMode
                                    readonly property bool shown: !barWindow.isDesktop && (mode === "always" || (mode === "occasional" && (barWindow.isCharging || barWindow.batCap <= 20 || barWindow.batFillBurst || batteryStatusPill.isHovered)))
                                    opacity: shown ? 1 : 0
                                    visible: opacity > 0.01
                                    Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                                    property real phase: 0
                                    property real level: Math.max(0, Math.min(1, barWindow.batCap / 100))
                                    readonly property color fillColor: barWindow.isCharging ? "#a6e3a1" : (barWindow.batCap <= 20 ? "#f38ba8" : (barWindow.batCap < 30 ? "#f9e2af" : "#89b4fa"))
                                    NumberAnimation on phase { from: 0; to: Math.PI * 2; duration: 3200; loops: Animation.Infinite; running: batFill.visible }
                                    onPhaseChanged: requestPaint()
                                    onLevelChanged: requestPaint()
                                    onFillColorChanged: requestPaint()
                                    onPaint: {
                                        let ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        if (level <= 0.01) return
                                        let w = width, h = height, r = barWindow.s(10)
                                        ctx.save()
                                        ctx.beginPath()
                                        ctx.moveTo(r, 0); ctx.lineTo(w - r, 0); ctx.arcTo(w, 0, w, r, r)
                                        ctx.lineTo(w, h - r); ctx.arcTo(w, h, w - r, h, r)
                                        ctx.lineTo(r, h); ctx.arcTo(0, h, 0, h - r, r)
                                        ctx.lineTo(0, r); ctx.arcTo(0, 0, r, 0, r)
                                        ctx.closePath()
                                        ctx.clip()
                                        let top = h * (1 - level), amp = barWindow.s(1.6)
                                        ctx.beginPath()
                                        ctx.moveTo(0, h)
                                        for (let x = 0; x <= w; x += 2)
                                            ctx.lineTo(x, top + amp * Math.sin(phase + (x / w) * Math.PI * 3))
                                        ctx.lineTo(w, h)
                                        ctx.closePath()
                                        let c = fillColor
                                        let g = ctx.createLinearGradient(0, top, 0, h)
                                        g.addColorStop(0, Qt.rgba(c.r, c.g, c.b, 0.26))
                                        g.addColorStop(1, Qt.rgba(c.r, c.g, c.b, 0.12))
                                        ctx.fillStyle = g
                                        ctx.fill()
                                        if (barWindow.isCharging) {
                                            let bandH = h * 0.5
                                            let by = h - (phase / (Math.PI * 2)) * (h + bandH)
                                            let sg = ctx.createLinearGradient(0, by, 0, by + bandH)
                                            sg.addColorStop(0, "rgba(255,255,255,0)")
                                            sg.addColorStop(0.5, "rgba(255,255,255,0.22)")
                                            sg.addColorStop(1, "rgba(255,255,255,0)")
                                            ctx.globalCompositeOperation = "source-atop"
                                            ctx.fillStyle = sg
                                            ctx.fillRect(0, by, w, bandH)
                                        }
                                        ctx.restore()
                                    }
                                }
                                PillBg {
                                    id: residentBattBg
                                    kind: barWindow.residentPillFlag.style === "border" ? "border" : "pulse"
                                    radius: batteryStatusPill.radius
                                    px: barWindow.s(1)
                                    tint: barWindow.residentPillFlag.tint || "#f38ba8"
                                    shown: barWindow.residentPillActive("battery")
                                }
                                Connections {
                                    target: barWindow
                                    function onResidentPillBurstChanged() {
                                        if (barWindow.residentPillFlag.pill !== "battery") return
                                        residentBattBg.fire()
                                        if (barWindow.residentPillFlag.open_card) {
                                            batCloseGrace.stop()
                                            batteryStatusPill.hoverConfirmed = true
                                            battForceOpenTimer.interval = Math.max(200, ((barWindow.residentPillFlag.expires_ts || 0) - Date.now() / 1000) * 1000)
                                            battForceOpenTimer.restart()
                                        }
                                    }
                                }
                                Timer { id: battForceOpenTimer; onTriggered: if (!batteryStatusPill.cardKeep) batteryStatusPill.hoverConfirmed = false }
                                // Whole-pill glow flash for the 100%-charged flourish — same
                                // reasoning as uptimeChip's glow above: the tiny sparkle dots
                                // alone read as "nothing happened" even when firing correctly.
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: "transparent"
                                    border.width: barWindow.s(1.5)
                                    border.color: mocha.green
                                    opacity: barWindow.batteryFlourishActive ? 0.9 : 0
                                    Behavior on opacity { NumberAnimation { duration: 220 } }
                                }
                                // Integrated battery-alert juice — icon shake at the most
                                // critical (10%) level, percentage bold/grow pulse on any
                                // battery pill-flag burst. Trigger source is BatteryAlarm.qml
                                // (batteryAlertStyle: "integrated"), fired via the same
                                // residentPillBurst mechanism as any other resident finding.
                                property real battPctPulse: 1.0
                                Behavior on battPctPulse { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.7 } }
                                Timer { id: battPctPulseTimer; interval: 280; onTriggered: batteryStatusPill.battPctPulse = 1.0 }
                                Connections {
                                    target: barWindow
                                    function onResidentPillBurstChanged() {
                                        if (barWindow.residentPillFlag.pill !== "battery") return
                                        batteryStatusPill.battPctPulse = 1.32
                                        battPctPulseTimer.restart()
                                        if (barWindow.residentPillFlag.urgency === "high") battIconShakeAnim.restart()
                                    }
                                }
                                Row {
                                    id: batLayoutRow; anchors.centerIn: parent; spacing: barWindow.s(8)
                                    Text {
                                        id: battIconText
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: barWindow.isDesktop ? "" : barWindow.batIcon
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: barWindow.isDesktop ? barWindow.s(18) : barWindow.s(16)
                                        color: barWindow.isDesktop ? barWindow.batDynamicColor : (barWindow.isCharging ? "#a6e3a1" : (barWindow.batCap <= 20 ? "#f38ba8" : (barWindow.batCap < 30 ? "#f9e2af" : "#89b4fa")))
                                        Behavior on color { ColorAnimation { duration: 300 } }
                                        transform: Translate { id: battIconShakeT }
                                        SequentialAnimation {
                                            id: battIconShakeAnim
                                            NumberAnimation { target: battIconShakeT; property: "x"; to: -barWindow.s(2.5); duration: 55 }
                                            NumberAnimation { target: battIconShakeT; property: "x"; to: barWindow.s(2.5); duration: 55 }
                                            NumberAnimation { target: battIconShakeT; property: "x"; to: -barWindow.s(1.5); duration: 55 }
                                            NumberAnimation { target: battIconShakeT; property: "x"; to: barWindow.s(1.5); duration: 55 }
                                            NumberAnimation { target: battIconShakeT; property: "x"; to: 0; duration: 55 }
                                        }
                                    }
                                    RollText { anchors.verticalCenter: parent.verticalCenter; visible: !barWindow.isDesktop; val: barWindow.batPercent; pixelSize: barWindow.s(13); rollH: barWindow.s(17); color: mocha.text; scale: batteryStatusPill.battPctPulse }
                                    // 100%-charged flourish — same sparkDot idiom as cpuSighing
                                    // (search sparkDot), fixed-hex green, gated on
                                    // topBarFlourishBatteryEnabled. Test: echo battery > /tmp/qs_topbar_test_flourish
                                    Repeater {
                                        model: barWindow.batteryFlourishActive ? 3 : 0
                                        delegate: Item {
                                            anchors.centerIn: parent
                                            z: 5
                                            readonly property real xOff: (index - 1) * barWindow.s(10)
                                            Rectangle {
                                                id: batSparkDot
                                                width: barWindow.s(2.5); height: barWindow.s(2.5)
                                                radius: width / 2
                                                color: "#a6e3a1"
                                                x: parent.xOff
                                                y: 0
                                                opacity: 0
                                                SequentialAnimation {
                                                    running: true
                                                    PauseAnimation { duration: index * 140 }
                                                    ParallelAnimation {
                                                        NumberAnimation { target: batSparkDot; property: "opacity"; from: 0; to: 0.85; duration: 260; easing.type: Easing.OutQuad }
                                                        NumberAnimation { target: batSparkDot; property: "y"; from: 0; to: -barWindow.s(14); duration: 900; easing.type: Easing.OutCubic }
                                                    }
                                                    NumberAnimation { target: batSparkDot; property: "opacity"; to: 0; duration: 400; easing.type: Easing.InQuad }
                                                }
                                            }
                                        }
                                    }
                                }
                                MouseArea {
                                    id: batMouse; hoverEnabled: true; anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton) {
                                            let cur = batteryStatusPill.powerProfile
                                            batteryStatusPill.powerProfile = cur === "performance" ? "balanced" : (cur === "balanced" ? "power-saver" : "performance")
                                            if (batProfileCycle.running) batProfileCycle.pending++
                                            else batProfileCycle.running = true
                                        } else {
                                            Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle battery"])
                                        }
                                    }
                                }

                                // Hover card — time-to-empty/time-to-full. Only for laptops
                                // (batteryStatusPill already has clip:false, so this can be
                                // a plain child without the wrapper Item volume needed).
                                property string timeInfo: ""
                                property string powerProfile: ""
                                property string powerW: ""
                                property string battStateStr: ""
                                property bool hoverConfirmed: false
                                readonly property bool cardKeep: isHovered || batTip.cardHovered
                                Timer { id: batHoverDelay; interval: 1000; onTriggered: batteryStatusPill.hoverConfirmed = true }
                                Timer { id: batCloseGrace; interval: 200; onTriggered: { batHoverDelay.stop(); batteryStatusPill.hoverConfirmed = false } }
                                Timer { interval: 1000; repeat: true; running: batteryStatusPill.hoverConfirmed; onTriggered: if (!batTipReader.running) batTipReader.running = true }
                                Process {
                                    id: batProfileCycle
                                    command: ["bash", "-c", "cur=$(powerprofilesctl get); case \"$cur\" in performance) next=balanced;; balanced) next=power-saver;; *) next=performance;; esac; powerprofilesctl set \"$next\"; notify-send -t 1500 'Power Profile' \"$next\""]
                                    property int pending: 0
                                    onExited: {
                                        if (pending > 0) { pending--; running = true }
                                        else { batTipReader.running = false; batTipReader.running = true }
                                    }
                                }
                                Process {
                                    id: batTipReader
                                    command: ["bash", "-c",
                                        "bat=$(upower -e 2>/dev/null | grep -i BAT | head -n1); " +
                                        "[ -z \"$bat\" ] && exit 0; " +
                                        "info=$(upower -i \"$bat\" 2>/dev/null); " +
                                        "st=$(echo \"$info\" | awk -F: '/state:/{gsub(/^ +/,\"\",$2); print $2; exit}'); " +
                                        "tm=$(echo \"$info\" | awk -F: '/time to (empty|full):/{gsub(/^ +/,\"\",$2); print $2; exit}'); " +
                                        "pp=$(powerprofilesctl get 2>/dev/null); " +
                                        "pw=$(awk '{printf \"%.1f\", $1/1000000}' \"$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1)/power_now\" 2>/dev/null); " +
                                        "printf '%s\\n%s\\n%s\\n%s\\nEND' \"${st:-Unknown}\" \"${tm:-}\" \"${pp:-}\" \"${pw:-}\""]
                                    stdout: StdioCollector {
                                        onStreamFinished: {
                                            let lines = this.text.trim().split("\n")
                                            if (lines[lines.length - 1] !== "END") return
                                            batteryStatusPill.battStateStr = lines[0] || ""
                                            batteryStatusPill.timeInfo = lines[1] || ""
                                            batteryStatusPill.powerProfile = lines[2] || ""
                                            batteryStatusPill.powerW = lines[3] || ""
                                        }
                                    }
                                }
                                onCardKeepChanged: {
                                    if (cardKeep) {
                                        batCloseGrace.stop()
                                        batTipReader.running = false; batTipReader.running = true
                                        if (!hoverConfirmed) batHoverDelay.restart()
                                    } else {
                                        batHoverDelay.stop()
                                        batCloseGrace.restart()
                                    }
                                }
                                Rectangle {
                                    id: batTip
                                    readonly property bool cardHovered: batTipHover.hovered
                                    HoverHandler { id: batTipHover; enabled: batteryStatusPill.hoverConfirmed }
                                    visible: !barWindow.isDesktop && barWindow.topBarHoverCardsEnabled && (batteryStatusPill.cardKeep || batteryStatusPill.hoverConfirmed)
                                    opacity: batteryStatusPill.hoverConfirmed ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    transformOrigin: Item.Top
                                    scale: batteryStatusPill.hoverConfirmed ? 1.0 : barWindow.batHoverGrowScale
                                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                                    // Reparented onto centerBox — batteryStatusPill lives
                                    // inside sysCapsule's clip:true, same fix as volTip/
                                    // weatherTip above.
                                    parent: centerBox
                                    // Spans the WHOLE sysCapsule, same reasoning as volTip.
                                    x: rightLayout.x - centerBox.x + sysCapsule.x
                                    y: centerBox.height - barWindow.batHoverOverlap
                                    width: sysCapsule.width
                                    height: batTipCol.implicitHeight + barWindow.s(14)
                                    radius: barWindow.s(14)
                                    topLeftRadius: 0
                                    topRightRadius: 0
                                    color: barWindow.cardFill
                                    border.width: 1
                                    border.color: barWindow.topBarAccentLine
                                        ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.9)))
                                        : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                                    clip: true
                                    z: 100
                                    Rectangle {
                                        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                        height: 1
                                        color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                                    }
                                    Column {
                                        id: batTipCol
                                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: barWindow.s(14)
                                        width: parent.width - barWindow.s(24)
                                        spacing: barWindow.s(5)
                                        Row {
                                            spacing: barWindow.s(6)
                                            width: parent.width
                                            Text { anchors.verticalCenter: parent.verticalCenter; text: /^(charging|full)/.test(batteryStatusPill.battStateStr.toLowerCase()) ? "󰂄" : "󰁹"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(13); color: /^(charging|full)/.test(batteryStatusPill.battStateStr.toLowerCase()) ? mocha.green : mocha.peach }
                                            Text { anchors.verticalCenter: parent.verticalCenter; text: batteryStatusPill.battStateStr; width: parent.width - barWindow.s(20); elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Bold; color: mocha.text }
                                        }
                                        Text {
                                            visible: batteryStatusPill.timeInfo !== ""
                                            text: (/^(charging|full)/.test(batteryStatusPill.battStateStr.toLowerCase()) ? "Full in " : "Empty in ") + batteryStatusPill.timeInfo
                                            width: parent.width; elide: Text.ElideRight
                                            font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); color: mocha.subtext0
                                        }
                                        Row {
                                            visible: batteryStatusPill.powerW !== ""
                                            spacing: barWindow.s(6)
                                            Text { anchors.verticalCenter: parent.verticalCenter; text: "󱐋"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(11); color: mocha.yellow }
                                            Text { anchors.verticalCenter: parent.verticalCenter; text: batteryStatusPill.powerW + " W " + (/^(charging|full)/.test(batteryStatusPill.battStateStr.toLowerCase()) ? "in" : "draw"); font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold; color: mocha.subtext1 }
                                        }
                                        Row {
                                            visible: batteryStatusPill.powerProfile !== ""
                                            spacing: barWindow.s(6)
                                            Text { anchors.verticalCenter: parent.verticalCenter; text: batteryStatusPill.powerProfile === "performance" ? "󰓅" : (batteryStatusPill.powerProfile === "power-saver" ? "󰌪" : "󰾅"); font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(11); color: batteryStatusPill.powerProfile === "performance" ? mocha.red : (batteryStatusPill.powerProfile === "power-saver" ? mocha.green : mocha.blue) }
                                            Text { anchors.verticalCenter: parent.verticalCenter; text: batteryStatusPill.powerProfile; width: Math.min(implicitWidth, batTipCol.width - barWindow.s(40)); elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); color: mocha.subtext1 }
                                            Text { anchors.verticalCenter: parent.verticalCenter; text: "󰍽"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(11); color: mocha.overlay1 }
                                        }
                                    }

                                }
                            }
                        }

                        // --- PAGE 1: KB + WiFi + Bluetooth ---
                        Row {
                            id: page1Row
                            anchors.centerIn: parent
                            spacing: barWindow.s(8)
                            property real ty: barWindow.barHeight
                            property bool animEnabled: true
                            function snapTo(v) { animEnabled = false; ty = v; animEnabled = true }
                            transform: Translate { y: page1Row.ty }
                            Behavior on ty { enabled: page1Row.animEnabled; NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

                            // KB
                            Rectangle {
                                property bool isHovered: kbMouse.containsMouse
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                radius: barWindow.s(10); height: sysCapsule.pillHeight
                                width: kbLayoutRow.width + barWindow.s(24)
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                // No inherent status meaning — full ambient
                                // border treatment, phase 0.24.
                                border.width: 1
                                border.color: barWindow.topBarAccentLine
                                    ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.24)))
                                    : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Row {
                                    id: kbLayoutRow; anchors.centerIn: parent; spacing: barWindow.s(8)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "󰌌"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16); color: parent.parent.isHovered ? mocha.text : mocha.overlay2 }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.kbLayout; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(13); font.weight: Font.Black; color: mocha.text }
                                }
                                MouseArea { id: kbMouse; anchors.fill: parent; hoverEnabled: true; onClicked: Quickshell.execDetached(["hyprctl", "switchxkblayout", "main", "next"]) }
                            }

                            // WiFi / Ethernet — non-clipping wrapper Item so the hover
                            // tooltip (rendered below, outside the pill's own bounds)
                            // survives the pill's own clip:true.
                            Item {
                                id: wifiWrap
                                anchors.verticalCenter: parent.verticalCenter
                                width: wifiPill.width; height: wifiPill.height

                                property string ssid: ""
                                property int dbm: 0
                                property int freq: 0
                                property string rxRate: ""
                                property string txRate: ""
                                property int pct: 0
                                property string sec: ""
                                property bool radioOn: true
                                property string ip: ""
                                property string gw: ""
                                property string pingMs: ""
                                property real rxBps: 0
                                property real txBps: 0
                                property real lastRx: -1
                                property real lastTx: -1
                                property real lastT: 0
                                property var rxHist: []
                                property var txHist: []
                                property var savedNets: []
                                property var others: []
                                readonly property string band: freq <= 0 ? "" : (freq < 3000 ? "2.4 GHz · ch " + Math.round((freq - 2407) / 5) : (freq < 5925 ? "5 GHz · ch " + Math.round((freq - 5000) / 5) : "6 GHz · ch " + Math.round((freq - 5950) / 5)))
                                readonly property int bars: pct >= 80 ? 4 : (pct >= 60 ? 3 : (pct >= 35 ? 2 : (pct > 0 ? 1 : 0)))
                                readonly property color qualColor: bars >= 3 ? mocha.green : (bars === 2 ? mocha.yellow : mocha.red)
                                property bool hoverConfirmed: false
                                readonly property bool cardKeep: wifiPill.isHovered || wifiTip.cardHovered
                                Timer { id: wifiHoverDelay; interval: 1000; onTriggered: wifiWrap.hoverConfirmed = true }
                                Timer { id: wifiCloseGrace; interval: 200; onTriggered: { wifiHoverDelay.stop(); wifiWrap.hoverConfirmed = false } }
                                Timer { interval: 1000; repeat: true; running: wifiWrap.hoverConfirmed; onTriggered: if (!wifiTipReader.running) wifiTipReader.running = true }
                                onCardKeepChanged: {
                                    if (cardKeep) {
                                        wifiCloseGrace.stop()
                                        if (!wifiTipReader.running) wifiTipReader.running = true
                                        if (!hoverConfirmed) wifiHoverDelay.restart()
                                    } else {
                                        wifiHoverDelay.stop()
                                        wifiCloseGrace.restart()
                                    }
                                }
                                function refreshSoon() { wifiRefreshTimer.restart() }
                                Timer { id: wifiRefreshTimer; interval: 700; onTriggered: if (!wifiTipReader.running) wifiTipReader.running = true }
                                function pushHist(arr, v) {
                                    let a = arr.slice()
                                    a.push(v)
                                    if (a.length > 30) a.shift()
                                    return a
                                }
                                Process {
                                    id: wifiTipReader
                                    command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/wifi_tip.sh"]
                                    stdout: StdioCollector {
                                        onStreamFinished: {
                                            let lines = this.text.split("\n")
                                            let got = false
                                            for (let i = 0; i < lines.length; i++) {
                                                let ln = lines[i]
                                                if (ln.length < 2 || ln.charAt(1) !== "|") continue
                                                let t = ln.charAt(0)
                                                let p = ln.substring(2).split("|")
                                                if (t === "L") {
                                                    got = true
                                                    wifiWrap.ssid = p[0] || ""
                                                    wifiWrap.dbm = parseInt(p[1]) || 0
                                                    wifiWrap.freq = parseInt(p[2]) || 0
                                                    wifiWrap.rxRate = p[3] || ""
                                                    wifiWrap.txRate = p[4] || ""
                                                    wifiWrap.pct = parseInt(p[5]) || 0
                                                    wifiWrap.sec = p[6] || ""
                                                    wifiWrap.radioOn = (p[7] || "").trim() !== "disabled"
                                                } else if (t === "N") {
                                                    wifiWrap.ip = p[0] || ""
                                                    wifiWrap.gw = p[1] || ""
                                                    let rx = parseFloat(p[2]), tx = parseFloat(p[3])
                                                    let now = Date.now()
                                                    if (!isNaN(rx) && !isNaN(tx)) {
                                                        if (wifiWrap.lastRx >= 0 && now > wifiWrap.lastT) {
                                                            let dt = (now - wifiWrap.lastT) / 1000
                                                            wifiWrap.rxBps = Math.max(0, (rx - wifiWrap.lastRx) / dt)
                                                            wifiWrap.txBps = Math.max(0, (tx - wifiWrap.lastTx) / dt)
                                                            wifiWrap.rxHist = wifiWrap.pushHist(wifiWrap.rxHist, wifiWrap.rxBps)
                                                            wifiWrap.txHist = wifiWrap.pushHist(wifiWrap.txHist, wifiWrap.txBps)
                                                        }
                                                        wifiWrap.lastRx = rx
                                                        wifiWrap.lastTx = tx
                                                        wifiWrap.lastT = now
                                                    }
                                                    wifiWrap.pingMs = (p[4] || "").trim()
                                                } else if (t === "S") {
                                                    try { wifiWrap.savedNets = JSON.parse(p.join("|")) } catch (e) {}
                                                } else if (t === "O") {
                                                    try { wifiWrap.others = JSON.parse(p.join("|")) } catch (e) {}
                                                }
                                            }
                                        }
                                    }
                                }
                                Process {
                                    id: wifiAct
                                    onExited: wifiWrap.refreshSoon()
                                }

                            Rectangle {
                                id: wifiPill
                                property bool isHovered: wifiMouse.containsMouse
                                radius: barWindow.s(10); height: sysCapsule.pillHeight
                                width: wifiLayoutRow.width + barWindow.s(24)
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                clip: true
                                // No inherent status meaning of its own (the
                                // blue fill overlay below already carries
                                // on/off) — full ambient border treatment,
                                // phase 0.32.
                                border.width: 1
                                border.color: barWindow.topBarAccentLine
                                    ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.32)))
                                    : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Rectangle {
                                    anchors.fill: parent; radius: barWindow.s(10)
                                    opacity: barWindow.isDesktop ? (barWindow.ethStatus === "Connected" ? 0.20 : 0.0) : (barWindow.isWifiOn ? 0.20 : 0.0)
                                    Behavior on opacity { NumberAnimation { duration: 300 } }
                                    gradient: Gradient { orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: mocha.blue }
                                        GradientStop { position: 1.0; color: Qt.lighter(mocha.blue, 1.3) } }
                                }
                                PillBg {
                                    kind: "radar"
                                    radius: wifiPill.radius
                                    px: barWindow.s(1)
                                    tint: "#89dceb"
                                    level: barWindow.wifiIcon === "󰤨" ? 1.0 : (barWindow.wifiIcon === "󰤥" ? 0.7 : (barWindow.wifiIcon === "󰤢" ? 0.4 : 0.2))
                                    rate: Math.min(1, (barWindow.netDownBps + barWindow.netUpBps) / 2000000)
                                    shown: !barWindow.isDesktop && barWindow.isWifiOn && barWindow.pillFxOn(barWindow.topBarWifiRadarMode, wifiPill.isHovered || barWindow.fxFlash("wifi"))
                                }
                                PillBg {
                                    id: residentWifiBg
                                    kind: barWindow.residentPillFlag.style === "border" ? "border" : "pulse"
                                    radius: wifiPill.radius
                                    px: barWindow.s(1)
                                    tint: barWindow.residentPillFlag.tint || "#89dceb"
                                    shown: barWindow.residentPillActive("wifi")
                                }
                                Connections {
                                    target: barWindow
                                    function onResidentPillBurstChanged() {
                                        if (barWindow.residentPillFlag.pill !== "wifi") return
                                        residentWifiBg.fire()
                                        if (barWindow.residentPillFlag.open_card) {
                                            wifiCloseGrace.stop()
                                            wifiWrap.hoverConfirmed = true
                                            wifiForceOpenTimer.interval = Math.max(200, ((barWindow.residentPillFlag.expires_ts || 0) - Date.now() / 1000) * 1000)
                                            wifiForceOpenTimer.restart()
                                        }
                                    }
                                }
                                Timer { id: wifiForceOpenTimer; onTriggered: if (!wifiWrap.cardKeep) wifiWrap.hoverConfirmed = false }
                                Row {
                                    id: wifiLayoutRow; anchors.centerIn: parent; spacing: barWindow.s(8)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.isDesktop ? "󰈀" : barWindow.wifiIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16); color: barWindow.isDesktop ? (barWindow.ethStatus === "Connected" ? mocha.blue : mocha.subtext0) : (barWindow.isWifiOn ? mocha.blue : mocha.subtext0) }
                                    Text {
                                        id: wifiText
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: barWindow.isDesktop ? barWindow.ethStatus : (barWindow.sysPollerLoaded ? (barWindow.isWifiOn ? (barWindow.wifiSsid !== "" ? barWindow.wifiSsid : "On") : "Off") : "")
                                        visible: text !== ""
                                        font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(13); font.weight: Font.Black
                                        color: barWindow.isDesktop ? (barWindow.ethStatus === "Connected" ? mocha.blue : mocha.text) : (barWindow.isWifiOn ? mocha.blue : mocha.text)
                                        width: Math.min(implicitWidth, barWindow.s(120)); elide: Text.ElideRight
                                    }
                                }
                                MouseArea { id: wifiMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle network wifi"]) }
                            }

                            // Hover card — link quality, addressing, live throughput, nearby networks.
                            Rectangle {
                                id: wifiTip
                                readonly property bool cardHovered: wifiTipHover.hovered
                                HoverHandler { id: wifiTipHover; enabled: wifiWrap.hoverConfirmed }
                                visible: barWindow.topBarHoverCardsEnabled && (wifiWrap.cardKeep || wifiWrap.hoverConfirmed) && !barWindow.isDesktop
                                opacity: wifiWrap.hoverConfirmed ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                transformOrigin: Item.Top
                                scale: wifiWrap.hoverConfirmed ? 1.0 : barWindow.wifiHoverGrowScale
                                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                                parent: centerBox
                                width: Math.max(sysCapsule.width, barWindow.s(290))
                                x: rightLayout.x - centerBox.x + sysCapsule.x + sysCapsule.width - width
                                y: centerBox.height - barWindow.wifiHoverOverlap
                                height: wifiTipCol.implicitHeight + barWindow.s(20)
                                radius: barWindow.s(14)
                                topLeftRadius: width > sysCapsule.width + 1 ? radius : 0
                                topRightRadius: 0
                                color: barWindow.cardFill
                                border.width: 1
                                border.color: barWindow.topBarAccentLine
                                    ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.7)))
                                    : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                                clip: true
                                z: 100
                                Rectangle {
                                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                    height: 1
                                    color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                                }
                                Column {
                                    id: wifiTipCol
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: barWindow.s(14)
                                    width: parent.width - barWindow.s(28)
                                    spacing: barWindow.s(7)

                                    Item {
                                        width: parent.width; height: barWindow.s(20)
                                        Text { id: wifiHdrIcon; anchors.verticalCenter: parent.verticalCenter; text: wifiWrap.radioOn ? barWindow.wifiIcon : "󰤭"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(15); color: wifiWrap.radioOn ? mocha.blue : mocha.subtext0 }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: wifiHdrIcon.right; anchors.leftMargin: barWindow.s(8)
                                            anchors.right: wifiToggle.left; anchors.rightMargin: barWindow.s(8)
                                            text: !wifiWrap.radioOn ? "Wi-Fi off" : (wifiWrap.ssid !== "" ? wifiWrap.ssid : "Not connected")
                                            elide: Text.ElideRight
                                            font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Bold; color: mocha.text
                                        }
                                        Rectangle {
                                            id: wifiToggle
                                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                            width: barWindow.s(38); height: barWindow.s(18); radius: height / 2
                                            color: wifiWrap.radioOn ? Qt.rgba(mocha.blue.r, mocha.blue.g, mocha.blue.b, 0.28) : Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.7)
                                            border.width: 1
                                            border.color: wifiWrap.radioOn ? Qt.rgba(mocha.blue.r, mocha.blue.g, mocha.blue.b, 0.6) : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.1)
                                            Text { anchors.centerIn: parent; text: wifiWrap.radioOn ? "ON" : "OFF"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Black; color: wifiWrap.radioOn ? mocha.blue : mocha.subtext0 }
                                            MouseArea {
                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                onClicked: { wifiAct.command = ["nmcli", "radio", "wifi", wifiWrap.radioOn ? "off" : "on"]; wifiAct.running = true }
                                            }
                                        }
                                    }

                                    Row {
                                        visible: wifiWrap.radioOn && wifiWrap.ssid !== ""
                                        spacing: barWindow.s(8)
                                        height: barWindow.s(14)
                                        Item {
                                            width: barWindow.s(22); height: parent.height
                                            Row {
                                                anchors.bottom: parent.bottom; spacing: barWindow.s(2)
                                                Repeater {
                                                    model: 4
                                                    Rectangle {
                                                        width: barWindow.s(4); height: barWindow.s(4 + index * 3); radius: barWindow.s(1)
                                                        anchors.bottom: parent.bottom
                                                        color: index < wifiWrap.bars ? wifiWrap.qualColor : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.15)
                                                    }
                                                }
                                            }
                                        }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: wifiWrap.pct + "%  ·  " + wifiWrap.dbm + " dBm"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold; color: wifiWrap.qualColor }
                                    }

                                    Repeater {
                                        model: (wifiWrap.radioOn && wifiWrap.ssid !== "") ? [
                                            ["Band", wifiWrap.band],
                                            ["Link", "↓ " + wifiWrap.rxRate + "  ↑ " + wifiWrap.txRate + " Mbit/s"],
                                            ["Security", wifiWrap.sec !== "" ? wifiWrap.sec : "Open"],
                                            ["IP", wifiWrap.ip],
                                            ["Gateway", wifiWrap.gw],
                                            ["Ping", wifiWrap.pingMs !== "" ? wifiWrap.pingMs + " ms" : "—"]
                                        ] : []
                                        Row {
                                            spacing: barWindow.s(8)
                                            Text { width: barWindow.s(58); text: modelData[0]; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Bold; color: mocha.overlay0; anchors.verticalCenter: parent.verticalCenter }
                                            Text {
                                                width: wifiTipCol.width - barWindow.s(66); text: modelData[1]; elide: Text.ElideRight
                                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold
                                                color: modelData[0] === "Ping" ? (parseFloat(wifiWrap.pingMs) > 80 ? mocha.red : (parseFloat(wifiWrap.pingMs) > 30 ? mocha.yellow : mocha.green)) : mocha.text
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }

                                    Item {
                                        visible: wifiWrap.radioOn && wifiWrap.ssid !== ""
                                        width: parent.width; height: barWindow.s(34)
                                        Rectangle { anchors.fill: parent; radius: barWindow.s(8); color: Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4) }
                                        Canvas {
                                            id: wifiSpark
                                            anchors.fill: parent; anchors.margins: barWindow.s(2)
                                            property var rxh: wifiWrap.rxHist
                                            property var txh: wifiWrap.txHist
                                            onRxhChanged: requestPaint()
                                            onTxhChanged: requestPaint()
                                            onPaint: {
                                                let ctx = getContext("2d")
                                                ctx.clearRect(0, 0, width, height)
                                                let mx = 1024
                                                for (let i = 0; i < rxh.length; i++) mx = Math.max(mx, rxh[i])
                                                for (let j = 0; j < txh.length; j++) mx = Math.max(mx, txh[j])
                                                let draw = (h, col) => {
                                                    if (h.length < 2) return
                                                    let step = width / 29
                                                    let x0 = width - (h.length - 1) * step
                                                    ctx.beginPath()
                                                    for (let k = 0; k < h.length; k++) {
                                                        let x = x0 + k * step
                                                        let y = height - 1 - (h[k] / mx) * (height - 3)
                                                        if (k === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                                                    }
                                                    ctx.strokeStyle = col
                                                    ctx.lineWidth = 1.4
                                                    ctx.lineJoin = "round"
                                                    ctx.stroke()
                                                }
                                                draw(rxh, mocha.blue)
                                                draw(txh, mocha.peach)
                                            }
                                        }
                                        Text { anchors.left: parent.left; anchors.top: parent.top; anchors.margins: barWindow.s(5); text: "↓ " + barWindow.fmtNetRate(wifiWrap.rxBps); font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Black; color: mocha.blue }
                                        Text { anchors.right: parent.right; anchors.top: parent.top; anchors.margins: barWindow.s(5); text: "↑ " + barWindow.fmtNetRate(wifiWrap.txBps); font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Black; color: mocha.peach }
                                    }

                                    Text { visible: wifiWrap.radioOn && wifiWrap.others.length > 0; text: "NEARBY"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Bold; color: mocha.overlay0 }
                                    Repeater {
                                        model: wifiWrap.radioOn ? wifiWrap.others.slice(0, 4) : []
                                        Item {
                                            id: nearRow
                                            readonly property bool isSaved: wifiWrap.savedNets.indexOf(modelData.n) >= 0
                                            width: wifiTipCol.width; height: barWindow.s(16)
                                            opacity: isSaved ? 1.0 : 0.55
                                            Rectangle { anchors.fill: parent; radius: barWindow.s(6); color: nearMouse.containsMouse && nearRow.isSaved ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : "transparent" }
                                            Text { id: nearIcon; anchors.left: parent.left; anchors.leftMargin: barWindow.s(4); anchors.verticalCenter: parent.verticalCenter; text: modelData.s >= 75 ? "󰤨" : (modelData.s >= 50 ? "󰤥" : (modelData.s >= 25 ? "󰤢" : "󰤟")); font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(11); color: mocha.blue }
                                            Text {
                                                anchors.left: nearIcon.right; anchors.leftMargin: barWindow.s(6)
                                                anchors.right: nearMeta.left; anchors.rightMargin: barWindow.s(6)
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.n; elide: Text.ElideRight
                                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold; color: mocha.text
                                            }
                                            Row {
                                                id: nearMeta
                                                anchors.right: parent.right; anchors.rightMargin: barWindow.s(4); anchors.verticalCenter: parent.verticalCenter
                                                spacing: barWindow.s(5)
                                                Text { visible: modelData.k !== ""; text: "󰌾"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(10); color: mocha.overlay1 }
                                                Text { visible: nearRow.isSaved; text: "󰓎"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(10); color: mocha.yellow }
                                                Text { text: modelData.s + "%"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); color: mocha.subtext0 }
                                            }
                                            MouseArea {
                                                id: nearMouse
                                                anchors.fill: parent; hoverEnabled: true
                                                cursorShape: nearRow.isSaved ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: if (nearRow.isSaved) { wifiAct.command = ["nmcli", "con", "up", "id", modelData.n]; wifiAct.running = true }
                                            }
                                        }
                                    }

                                    Item {
                                        width: parent.width; height: barWindow.s(18)
                                        Text { anchors.centerIn: parent; text: "󰖩  Open network panel"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold; color: footMouse.containsMouse ? mocha.text : mocha.subtext0 }
                                        MouseArea { id: footMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle network wifi"]) }
                                    }
                                }
                            }
                            }

                            // Bluetooth — non-clipping wrapper, same reason as wifi above.
                            Item {
                                id: btWrap
                                anchors.verticalCenter: parent.verticalCenter
                                width: btPill.width; height: btPill.height
                                visible: !barWindow.isDesktop

                                property bool powerOn: true
                                property var connectedDevs: []
                                property var pairedDevs: []
                                property bool hoverConfirmed: false
                                readonly property bool cardKeep: btPill.isHovered || btTip.cardHovered
                                Timer { id: btHoverDelay; interval: 1000; onTriggered: btWrap.hoverConfirmed = true }
                                Timer { id: btCloseGrace; interval: 200; onTriggered: { btHoverDelay.stop(); btWrap.hoverConfirmed = false } }
                                Timer { interval: 1000; repeat: true; running: btWrap.hoverConfirmed; onTriggered: if (!btTipReader.running) btTipReader.running = true }
                                onCardKeepChanged: {
                                    if (cardKeep) {
                                        btCloseGrace.stop()
                                        if (!btTipReader.running) btTipReader.running = true
                                        if (!hoverConfirmed) btHoverDelay.restart()
                                    } else {
                                        btHoverDelay.stop()
                                        btCloseGrace.restart()
                                    }
                                }
                                function refreshSoon() { btRefreshTimer.restart() }
                                Timer { id: btRefreshTimer; interval: 900; onTriggered: if (!btTipReader.running) btTipReader.running = true }
                                Process {
                                    id: btTipReader
                                    command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/network/bluetooth_panel_logic.sh --status"]
                                    stdout: StdioCollector {
                                        onStreamFinished: {
                                            try {
                                                let d = JSON.parse(this.text.trim())
                                                if (d.power === undefined) return
                                                btWrap.powerOn = d.power === "on"
                                                btWrap.connectedDevs = d.connected || []
                                                btWrap.pairedDevs = (d.devices || []).filter(x => x.action === "Connect")
                                            } catch (e) {}
                                        }
                                    }
                                }
                                Process {
                                    id: btAct
                                    onExited: btWrap.refreshSoon()
                                }
                                function act(args) {
                                    btAct.command = ["bash", "-c", "~/.config/hypr/scripts/quickshell/network/bluetooth_panel_logic.sh " + args]
                                    btAct.running = true
                                }

                            Rectangle {
                                id: btPill
                                property bool isHovered: btMouse.containsMouse
                                radius: barWindow.s(10); height: sysCapsule.pillHeight
                                width: barWindow.isDesktop ? 0 : btLayoutRow.width + barWindow.s(24)
                                visible: !barWindow.isDesktop
                                clip: true
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                // No inherent status meaning of its own (the
                                // mauve fill overlay below already carries
                                // on/off) — full ambient border treatment,
                                // phase 0.40.
                                border.width: 1
                                border.color: barWindow.topBarAccentLine
                                    ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.40)))
                                    : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Rectangle {
                                    anchors.fill: parent; radius: barWindow.s(10)
                                    opacity: barWindow.isBtOn ? 0.20 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 300 } }
                                    gradient: Gradient { orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: mocha.mauve }
                                        GradientStop { position: 1.0; color: Qt.lighter(mocha.mauve, 1.3) } }
                                }
                                PillBg {
                                    id: btBg
                                    kind: "pulse"
                                    radius: btPill.radius
                                    px: barWindow.s(1)
                                    tint: barWindow.btTintColor
                                    shown: !barWindow.isDesktop && barWindow.isBtOn && barWindow.pillFxOn(barWindow.topBarBtPulseMode, btPill.isHovered || barWindow.fxFlash("bt"))
                                    Connections {
                                        target: barWindow
                                        function onBtPulseBurstChanged() { btBg.fire() }
                                    }
                                }
                                PillBg {
                                    id: residentBtBg
                                    kind: barWindow.residentPillFlag.style === "border" ? "border" : "pulse"
                                    radius: btPill.radius
                                    px: barWindow.s(1)
                                    tint: barWindow.residentPillFlag.tint || "#cba6f7"
                                    shown: barWindow.residentPillActive("bt")
                                }
                                Connections {
                                    target: barWindow
                                    function onResidentPillBurstChanged() {
                                        if (barWindow.residentPillFlag.pill !== "bt") return
                                        residentBtBg.fire()
                                        if (barWindow.residentPillFlag.open_card) {
                                            btCloseGrace.stop()
                                            btWrap.hoverConfirmed = true
                                            btForceOpenTimer.interval = Math.max(200, ((barWindow.residentPillFlag.expires_ts || 0) - Date.now() / 1000) * 1000)
                                            btForceOpenTimer.restart()
                                        }
                                    }
                                }
                                Timer { id: btForceOpenTimer; onTriggered: if (!btWrap.cardKeep) btWrap.hoverConfirmed = false }
                                Row {
                                    id: btLayoutRow; anchors.centerIn: parent; spacing: barWindow.s(8)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.btIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16); color: barWindow.isBtOn ? mocha.mauve : mocha.subtext0 }
                                    Text {
                                        id: btText
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: barWindow.sysPollerLoaded ? barWindow.btDevice : ""
                                        visible: text !== ""
                                        font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(13); font.weight: Font.Black
                                        color: barWindow.isBtOn ? mocha.mauve : mocha.text
                                        width: Math.min(implicitWidth, barWindow.s(120)); elide: Text.ElideRight
                                    }
                                }
                                MouseArea { id: btMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle network bt"]) }
                            }

                            // Hover card — adapter power, connected devices (click to disconnect), paired devices (click to connect).
                            Rectangle {
                                id: btTip
                                readonly property bool cardHovered: btTipHover.hovered
                                HoverHandler { id: btTipHover; enabled: btWrap.hoverConfirmed }
                                visible: barWindow.topBarHoverCardsEnabled && (btWrap.cardKeep || btWrap.hoverConfirmed) && !barWindow.isDesktop
                                opacity: btWrap.hoverConfirmed ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                transformOrigin: Item.Top
                                scale: btWrap.hoverConfirmed ? 1.0 : barWindow.btHoverGrowScale
                                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                                parent: centerBox
                                width: Math.max(sysCapsule.width, barWindow.s(270))
                                x: rightLayout.x - centerBox.x + sysCapsule.x + sysCapsule.width - width
                                y: centerBox.height - barWindow.btHoverOverlap
                                height: btTipCol.implicitHeight + barWindow.s(20)
                                radius: barWindow.s(14)
                                topLeftRadius: width > sysCapsule.width + 1 ? radius : 0
                                topRightRadius: 0
                                color: barWindow.cardFill
                                border.width: 1
                                border.color: barWindow.topBarAccentLine
                                    ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.8)))
                                    : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                                clip: true
                                z: 100
                                Rectangle {
                                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                    height: 1
                                    color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                                }
                                Column {
                                    id: btTipCol
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: barWindow.s(14)
                                    width: parent.width - barWindow.s(28)
                                    spacing: barWindow.s(7)

                                    Item {
                                        width: parent.width; height: barWindow.s(20)
                                        Text { id: btHdrIcon; anchors.verticalCenter: parent.verticalCenter; text: btWrap.powerOn ? "󰂯" : "󰂲"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(15); color: btWrap.powerOn ? mocha.mauve : mocha.subtext0 }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: btHdrIcon.right; anchors.leftMargin: barWindow.s(8)
                                            anchors.right: btToggle.left; anchors.rightMargin: barWindow.s(8)
                                            text: !btWrap.powerOn ? "Bluetooth off" : (btWrap.connectedDevs.length > 0 ? btWrap.connectedDevs.length + " connected" : "No device connected")
                                            elide: Text.ElideRight
                                            font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Bold; color: mocha.text
                                        }
                                        Rectangle {
                                            id: btToggle
                                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                            width: barWindow.s(38); height: barWindow.s(18); radius: height / 2
                                            color: btWrap.powerOn ? Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.28) : Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.7)
                                            border.width: 1
                                            border.color: btWrap.powerOn ? Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.6) : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.1)
                                            Text { anchors.centerIn: parent; text: btWrap.powerOn ? "ON" : "OFF"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Black; color: btWrap.powerOn ? mocha.mauve : mocha.subtext0 }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: btWrap.act("--toggle") }
                                        }
                                    }

                                    Text { visible: btWrap.powerOn && btWrap.connectedDevs.length > 0; text: "CONNECTED  ·  click to disconnect"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Bold; color: mocha.overlay0 }
                                    Repeater {
                                        model: btWrap.powerOn ? btWrap.connectedDevs : []
                                        Item {
                                            id: connRow
                                            readonly property int batt: parseInt(modelData.battery) || 0
                                            width: btTipCol.width; height: barWindow.s(30)
                                            Rectangle { anchors.fill: parent; radius: barWindow.s(8); color: connMouse.containsMouse ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4) }
                                            Text { id: connIcon; anchors.left: parent.left; anchors.leftMargin: barWindow.s(8); anchors.verticalCenter: parent.verticalCenter; text: modelData.icon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(14); color: mocha.mauve }
                                            Column {
                                                anchors.left: connIcon.right; anchors.leftMargin: barWindow.s(8)
                                                anchors.right: battBox.left; anchors.rightMargin: barWindow.s(8)
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: barWindow.s(1)
                                                Text { width: parent.width; text: modelData.name; elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: mocha.text }
                                                Text { width: parent.width; text: modelData.profile; elide: Text.ElideRight; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); color: mocha.subtext0 }
                                            }
                                            Row {
                                                id: battBox
                                                visible: connRow.batt > 0
                                                anchors.right: parent.right; anchors.rightMargin: barWindow.s(8); anchors.verticalCenter: parent.verticalCenter
                                                spacing: barWindow.s(5)
                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: barWindow.s(22); height: barWindow.s(6); radius: height / 2
                                                    color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.15)
                                                    Rectangle { width: parent.width * Math.min(1, connRow.batt / 100); height: parent.height; radius: parent.radius; color: connRow.batt <= 20 ? mocha.red : (connRow.batt <= 50 ? mocha.yellow : mocha.green) }
                                                }
                                                Text { anchors.verticalCenter: parent.verticalCenter; text: connRow.batt + "%"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Black; color: mocha.text }
                                            }
                                            MouseArea { id: connMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btWrap.act("--disconnect " + modelData.mac) }
                                        }
                                    }

                                    Text { visible: btWrap.powerOn && btWrap.pairedDevs.length > 0; text: "PAIRED  ·  click to connect"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Bold; color: mocha.overlay0 }
                                    Repeater {
                                        model: btWrap.powerOn ? btWrap.pairedDevs.slice(0, 4) : []
                                        Item {
                                            id: pairRow
                                            width: btTipCol.width; height: barWindow.s(20)
                                            opacity: 0.75
                                            Rectangle { anchors.fill: parent; radius: barWindow.s(6); color: pairMouse.containsMouse ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : "transparent" }
                                            Text { id: pairIcon; anchors.left: parent.left; anchors.leftMargin: barWindow.s(6); anchors.verticalCenter: parent.verticalCenter; text: modelData.icon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(12); color: mocha.subtext0 }
                                            Text {
                                                anchors.left: pairIcon.right; anchors.leftMargin: barWindow.s(8)
                                                anchors.right: pairHint.left; anchors.rightMargin: barWindow.s(8)
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.name; elide: Text.ElideRight
                                                font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold; color: mocha.text
                                            }
                                            Text { id: pairHint; anchors.right: parent.right; anchors.rightMargin: barWindow.s(6); anchors.verticalCenter: parent.verticalCenter; text: pairMouse.containsMouse ? "connect" : ""; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); color: mocha.mauve }
                                            MouseArea { id: pairMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btWrap.act("--connect " + modelData.mac) }
                                        }
                                    }

                                    Item {
                                        width: parent.width; height: barWindow.s(18)
                                        Text { anchors.centerIn: parent; text: "󰂯  Open bluetooth panel"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Bold; color: btFootMouse.containsMouse ? mocha.text : mocha.subtext0 }
                                        MouseArea { id: btFootMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle network bt"]) }
                                    }
                                }
                            }
                            }
                        }

                        // --- PAGE 2: read-only state glance (wakelock / mic / idle-lock / night-light / brightness curve) ---
                        // Six pills in one Row used to force the whole capsule to stretch
                        // to fit all of them whenever this page was active. Capped to a
                        // fixed-width viewport + wheel-scroll instead, same idiom as
                        // trayPill's clipped Item + scrollX + Behavior-on-x — page paging
                        // (vertical wheel, cyclePage) still switches between page0/1/2,
                        // horizontal wheel now additionally scrolls through page2's pills
                        // without the capsule ballooning in width.
                        Item {
                            id: page2Viewport
                            anchors.centerIn: parent
                            width: Math.min(page2Row.width, sysCapsule.page2ViewportCap)
                            height: sysCapsule.pillHeight
                            clip: true

                            property real scrollX: 0
                            readonly property real maxScroll: Math.max(0, page2Row.width - width)
                            onMaxScrollChanged: scrollX = Math.max(-maxScroll, Math.min(0, scrollX))

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                // Only live on page2 — page0/page1 occupy this same centered
                                // spot in the carousel and already have their own wheel
                                // handling (e.g. volMouse's horizontal-wheel = volume step),
                                // which this must not shadow while they're the active page.
                                enabled: sysCapsule.sysPage === 2
                                // Horizontal only, and only when it's the dominant axis —
                                // vertical wheel stays exclusively reserved for cyclePage()
                                // (the outer WheelHandler), same disambiguation volMouse
                                // already uses one page over for volume vs page-scroll.
                                onWheel: wheel => {
                                    if (Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y)) {
                                        page2Viewport.scrollX = Math.max(-page2Viewport.maxScroll, Math.min(0, page2Viewport.scrollX + wheel.angleDelta.x * 0.4))
                                        wheel.accepted = true
                                    } else {
                                        wheel.accepted = false
                                    }
                                }
                            }

                        Row {
                            id: page2Row
                            anchors.verticalCenter: parent.verticalCenter
                            x: page2Viewport.scrollX
                            spacing: barWindow.s(8)
                            property real ty: barWindow.barHeight
                            property bool animEnabled: true
                            function snapTo(v) { animEnabled = false; ty = v; animEnabled = true }
                            transform: Translate { y: page2Row.ty }
                            Behavior on ty { enabled: page2Row.animEnabled; NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                            // Wakelock (keep-awake)
                            Rectangle {
                                property bool isHovered: wakelockMouse.containsMouse
                                property bool active: sysCapsule.tgWakelock
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                radius: barWindow.s(10); height: sysCapsule.pillHeight
                                width: wakelockRow.width + barWindow.s(20)
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                // Active/meaningful state (Awake) keeps its own
                                // solid green border, unmixed. At rest there's
                                // no status to protect, so it falls back to the
                                // full ambient treatment, phase 0.48.
                                border.width: 1
                                border.color: active
                                    ? Qt.rgba(mocha.green.r, mocha.green.g, mocha.green.b, 0.7)
                                    : (barWindow.topBarAccentLine
                                        ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.48)))
                                        : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05))
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Rectangle {
                                    anchors.fill: parent; radius: barWindow.s(10)
                                    opacity: parent.active ? 0.42 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 300 } }
                                    gradient: Gradient { orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: mocha.green }
                                        GradientStop { position: 1.0; color: Qt.lighter(mocha.green, 1.3) } }
                                }
                                Row {
                                    id: wakelockRow; anchors.centerIn: parent; spacing: barWindow.s(6)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.active ? "󰛊" : "󰤄"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(15); color: parent.parent.active ? mocha.green : mocha.subtext0 }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.active ? "Awake" : "Sleep OK"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Black; color: parent.parent.active ? mocha.text : mocha.subtext1 }
                                }
                                MouseArea { id: wakelockMouse; hoverEnabled: true; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/toggle_wakelock.sh"]) }
                            }

                            // Mic mute
                            Rectangle {
                                property bool isHovered: micMouse.containsMouse
                                property bool active: sysCapsule.tgMicMuted
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                radius: barWindow.s(10); height: sysCapsule.pillHeight
                                width: micRow.width + barWindow.s(20)
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                // Active/meaningful state (Muted) keeps its own
                                // solid red border, unmixed. At rest, full
                                // ambient treatment, phase 0.56.
                                border.width: 1
                                border.color: active
                                    ? Qt.rgba(mocha.red.r, mocha.red.g, mocha.red.b, 0.7)
                                    : (barWindow.topBarAccentLine
                                        ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.56)))
                                        : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05))
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Rectangle {
                                    anchors.fill: parent; radius: barWindow.s(10)
                                    opacity: parent.active ? 0.42 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 300 } }
                                    gradient: Gradient { orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: mocha.red }
                                        GradientStop { position: 1.0; color: Qt.lighter(mocha.red, 1.3) } }
                                }
                                Row {
                                    id: micRow; anchors.centerIn: parent; spacing: barWindow.s(6)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.active ? "󰍭" : "󰍬"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(15); color: parent.parent.active ? mocha.red : mocha.subtext0 }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.active ? "Muted" : "Mic Live"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Black; color: parent.parent.active ? mocha.text : mocha.subtext1 }
                                }
                                MouseArea { id: micMouse; hoverEnabled: true; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["bash", "-c", "command -v wpctl >/dev/null && wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle || pactl set-source-mute @DEFAULT_SOURCE@ toggle"]) }
                            }

                            // Idle lock
                            Rectangle {
                                property bool isHovered: idleMouse.containsMouse
                                property bool active: sysCapsule.tgIdlePaused
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                radius: barWindow.s(10); height: sysCapsule.pillHeight
                                width: idleRow.width + barWindow.s(20)
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                // Active/meaningful state (Idle Paused) keeps
                                // its own solid maroon border, unmixed. At
                                // rest, full ambient treatment, phase 0.64.
                                border.width: 1
                                border.color: active
                                    ? Qt.rgba(mocha.maroon.r, mocha.maroon.g, mocha.maroon.b, 0.7)
                                    : (barWindow.topBarAccentLine
                                        ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.64)))
                                        : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05))
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Rectangle {
                                    anchors.fill: parent; radius: barWindow.s(10)
                                    opacity: parent.active ? 0.42 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 300 } }
                                    gradient: Gradient { orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: mocha.maroon }
                                        GradientStop { position: 1.0; color: Qt.lighter(mocha.maroon, 1.3) } }
                                }
                                Row {
                                    id: idleRow; anchors.centerIn: parent; spacing: barWindow.s(6)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.active ? "󰒲" : "󰒳"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(15); color: parent.parent.active ? mocha.maroon : mocha.subtext0 }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.active ? "Idle Paused" : "Idle On"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Black; color: parent.parent.active ? mocha.text : mocha.subtext1 }
                                }
                                MouseArea { id: idleMouse; hoverEnabled: true; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/toggle_hypridle.sh"]) }
                            }

                            // Night light override
                            Rectangle {
                                property bool isHovered: nlMouse.containsMouse
                                property bool forced: sysCapsule.tgNlMode !== "auto"
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                radius: barWindow.s(10); height: sysCapsule.pillHeight
                                width: nlRow.width + barWindow.s(20)
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                // Forced/meaningful state keeps its own solid
                                // peach border, unmixed. Auto (rest) state, full
                                // ambient treatment, phase 0.72.
                                border.width: 1
                                border.color: forced
                                    ? Qt.rgba(mocha.peach.r, mocha.peach.g, mocha.peach.b, 0.7)
                                    : (barWindow.topBarAccentLine
                                        ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.72)))
                                        : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05))
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Rectangle {
                                    anchors.fill: parent; radius: barWindow.s(10)
                                    opacity: parent.forced ? 0.42 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 300 } }
                                    gradient: Gradient { orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: mocha.peach }
                                        GradientStop { position: 1.0; color: Qt.lighter(mocha.peach, 1.3) } }
                                }
                                Row {
                                    id: nlRow; anchors.centerIn: parent; spacing: barWindow.s(6)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: sysCapsule.tgNlMode === "on" ? "󰌔" : (sysCapsule.tgNlMode === "off" ? "󰌵" : "󰃞"); font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(15); color: parent.parent.forced ? mocha.peach : mocha.subtext0 }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: sysCapsule.tgNlMode === "on" ? "NL Forced On" : (sysCapsule.tgNlMode === "off" ? "NL Forced Off" : "NL Auto"); font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Black; color: parent.parent.forced ? mocha.text : mocha.subtext1 }
                                }
                                MouseArea { id: nlMouse; hoverEnabled: true; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/toggle_night_light.sh"]) }
                            }

                            // Adaptive brightness curve
                            Rectangle {
                                property bool isHovered: curveMouse.containsMouse
                                property bool active: sysCapsule.tgBrightnessCurve
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                radius: barWindow.s(10); height: sysCapsule.pillHeight
                                width: curveRow.width + barWindow.s(20)
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                // Active/meaningful state keeps its own solid
                                // yellow border, unmixed. At rest, full ambient
                                // treatment, phase 0.80.
                                border.width: 1
                                border.color: active
                                    ? Qt.rgba(mocha.yellow.r, mocha.yellow.g, mocha.yellow.b, 0.7)
                                    : (barWindow.topBarAccentLine
                                        ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.80)))
                                        : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05))
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Rectangle {
                                    anchors.fill: parent; radius: barWindow.s(10)
                                    opacity: parent.active ? 0.42 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 300 } }
                                    gradient: Gradient { orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: mocha.yellow }
                                        GradientStop { position: 1.0; color: Qt.lighter(mocha.yellow, 1.3) } }
                                }
                                Row {
                                    id: curveRow; anchors.centerIn: parent; spacing: barWindow.s(6)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.active ? "󰃟" : "󰃠"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(15); color: parent.parent.active ? mocha.yellow : mocha.subtext0 }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.active ? "Curve" : "Curve Off"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Black; color: parent.parent.active ? mocha.text : mocha.subtext1 }
                                }
                                MouseArea { id: curveMouse; hoverEnabled: true; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/toggle_brightness_curve.sh"]) }
                            }

                            // Kandor wake-word daemon
                            Rectangle {
                                property bool isHovered: kandorMouse.containsMouse
                                property bool active: sysCapsule.tgKandorEnabled
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                radius: barWindow.s(10); height: sysCapsule.pillHeight
                                width: kandorRow.width + barWindow.s(20)
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                // Active/meaningful state keeps its own solid
                                // sapphire border, unmixed. At rest, full
                                // ambient treatment, phase 0.88.
                                border.width: 1
                                border.color: active
                                    ? Qt.rgba(mocha.sapphire.r, mocha.sapphire.g, mocha.sapphire.b, 0.7)
                                    : (barWindow.topBarAccentLine
                                        ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.88)))
                                        : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05))
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Rectangle {
                                    anchors.fill: parent; radius: barWindow.s(10)
                                    opacity: parent.active ? 0.42 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 300 } }
                                    gradient: Gradient { orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: mocha.sapphire }
                                        GradientStop { position: 1.0; color: Qt.lighter(mocha.sapphire, 1.3) } }
                                }
                                Row {
                                    id: kandorRow; anchors.centerIn: parent; spacing: barWindow.s(6)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.active ? "󰍬" : "󰍭"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(15); color: parent.parent.active ? mocha.sapphire : mocha.subtext0 }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.active ? "Kandor On" : "Kandor Off"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Black; color: parent.parent.active ? mocha.text : mocha.subtext1 }
                                }
                                MouseArea { id: kandorMouse; hoverEnabled: true; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/quickshell/claude/voice/kandor_toggle.sh"]) }
                            }

                            Rectangle {
                                property bool isHovered: quietMouse.containsMouse
                                property bool active: barWindow.residentQuiet
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                radius: barWindow.s(10); height: sysCapsule.pillHeight
                                width: quietRow.width + barWindow.s(20)
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                border.width: 1
                                border.color: active
                                    ? Qt.rgba(mocha.teal.r, mocha.teal.g, mocha.teal.b, 0.7)
                                    : (barWindow.topBarAccentLine
                                        ? Qt.tint(Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05), Qt.rgba(barWindow.accentCycleColor.r, barWindow.accentCycleColor.g, barWindow.accentCycleColor.b, 0.10 + 0.22 * barWindow.ambientBreath(0.96)))
                                        : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05))
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Rectangle {
                                    anchors.fill: parent; radius: barWindow.s(10)
                                    opacity: parent.active ? 0.42 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 300 } }
                                    gradient: Gradient { orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: mocha.teal }
                                        GradientStop { position: 1.0; color: Qt.lighter(mocha.teal, 1.3) } }
                                }
                                Row {
                                    id: quietRow; anchors.centerIn: parent; spacing: barWindow.s(6)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.active ? "󰂛" : "󰂚"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(15); color: parent.parent.active ? mocha.teal : mocha.subtext0 }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.active ? "Cards Quiet" : "Cards All"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(12); font.weight: Font.Black; color: parent.parent.active ? mocha.text : mocha.subtext1 }
                                }
                                MouseArea { id: quietMouse; hoverEnabled: true; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: barWindow.residentSetQuiet(!barWindow.residentQuiet) }
                            }
                        }
                        }

                        // Scroll to page (wheel) — debounced so a fast flick = one step
                        Timer { id: sysScrollCooldown; interval: 350 }
                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: (ev) => {
                                // vertical (top-down) only
                                if (Math.abs(ev.angleDelta.y) <= Math.abs(ev.angleDelta.x)) return
                                if (sysScrollCooldown.running) return
                                sysCapsule.cyclePage(ev.angleDelta.y < 0 ? 1 : -1)
                                sysScrollCooldown.restart()
                            }
                        }
                    }
                }

                // ---------------- ACCENT LINE ----------------
                // A slim "rail" pinned to one edge (topBarAccentLinePosition:
                // top/bottom/left/right, Guide → Settings → Top Bar), with one
                // or two brighter highlight blobs drifting along it — like
                // light catching a moving point on a thin wire rather than a
                // single flat gradient sweep.
                //
                // top/bottom render a HORIZONTAL line the width of the bar;
                // left/right render a VERTICAL line running the full screen
                // height — barWindow itself is already Screen.height tall
                // (see the height/exclusiveZone comment near the top of this
                // file), so this reuses the existing window rather than
                // needing a second overlay surface, but that also means the
                // vertical rail can't anchor to barRow (barRow is only
                // barHeight tall) — it positions off barWindow.height/width
                // directly instead.
                //
                // Deliberately two separate Rectangle sets (H/V) rather than
                // one set with ternary anchors/dimensions switching between
                // orientations: this file has twice already shipped a real bug
                // from exactly that pattern (anchoring both edges of an axis
                // via a ternary leaves both bound in practice and stretches
                // the item instead of pinning one edge). Two fully independent,
                // never-simultaneously-visible sets sidesteps the whole bug
                // class instead of trying to be clever about it.
                //
                // Color mode mirrors AmbientGlow.qml's 3-way system (cycle /
                // fixed / album) through its own dedicated color source
                // (accentLineAmbient) and breathing wave (accentLineAnim),
                // separate from the shared accentCycleColor/ambientWave the
                // pill border echoes elsewhere in this file read from — so the
                // accent line's own speed/color-mode settings never leak into
                // those unrelated echoes.
                //
                // Resting state is intentionally understated — the whole point of
                // this pass is "barely there at idle, occasionally breathes with
                // the beat" instead of a constant visible pulse. Real system state
                // takes priority over decoration: an in-progress hold-action
                // (/tmp/qs_holdaction_state.json, same registry PowerMenu uses)
                // takes the line over completely and tracks its progress/color 1:1;
                // low battery nudges it to a calm warning red; sustained high CPU
                // does the same. A fresh notification still gives it one brief,
                // genuine flash. No MouseArea, so it never steals hover/click
                // from pills above it.
                //
                // Everything reads baseColor/hotColor/accentAmp directly off
                // accentLineState every frame (accentLineAmbient/accentLineAnim
                // are both live animations already) — none of it gets a
                // `Behavior` on color/opacity/position. A Behavior chasing a
                // value that's already moving every frame just restarts itself
                // 60x/second and low-pass filters the motion down to
                // near-static — the exact bug class already found and removed
                // from the pill borders elsewhere in this file.
                QtObject {
                    id: accentLineState

                    readonly property bool vertical: barWindow.topBarAccentLinePosition === "left" || barWindow.topBarAccentLinePosition === "right"
                    readonly property real thickness: barWindow.s(Math.max(1, barWindow.topBarAccentLineThickness))

                    readonly property bool musicPlaying: barWindow.musicData.status === "Playing"
                    readonly property bool lowBattery: !barWindow.isDesktop && !barWindow.isCharging && barWindow.batCap > 0 && barWindow.batCap <= 20
                    readonly property bool cpuHot: barWindow.cpuPct >= 85
                    readonly property bool holding: barWindow.holdActionActive
                    readonly property bool calm: !accentLineState.holding && !accentLineState.cpuHot && !accentLineState.lowBattery && !barWindow.accentPulse

                    // Beat influence stays tiny at idle (0.10) so the resting line
                    // just barely breathes; it's only given real presence (0.38)
                    // once music is actually playing.
                    readonly property real beatInfluence: barWindow.beatPulse * (accentLineState.musicPlaying ? 0.38 : 0.10)

                    // accentAmp is the single 0..1 driver for the glow blobs' extra
                    // thickness/opacity below. A hold-action in progress overrides
                    // everything else and maps 1:1 to its own progress; otherwise a
                    // notification flash beats ambient beat influence, never
                    // stacked past 1.0.
                    readonly property real accentAmp: accentLineState.holding
                        ? barWindow.holdActionProgress
                        : Math.min(1.0, Math.max(barWindow.accentPulse ? 1.0 : 0.0, accentLineState.beatInfluence))

                    readonly property real lineOpacity: accentLineState.holding
                        ? (0.18 + 0.25 * barWindow.holdActionProgress)
                        : Math.min(0.55, (barWindow.accentPulse ? 0.4 : (accentLineState.lowBattery ? 0.22 : 0.11)))

                    // "cycle": accentLineAmbient's own mauve→pink→blue cycle. "fixed":
                    // the swatch color. "album": current track's dominant color
                    // (mediaBc1, same quantized album-art parse the media pill border
                    // already uses) while playing, falling back to the cycle when idle.
                    readonly property color renderColor: {
                        if (barWindow.topBarAccentLineColorMode === "fixed") return barWindow.topBarAccentLineFixedColor;
                        if (barWindow.topBarAccentLineColorMode === "album") return accentLineState.musicPlaying ? barWindow.mediaBc1 : accentLineAmbient.cycleColor;
                        return accentLineAmbient.cycleColor;
                    }

                    readonly property color baseColor: accentLineState.holding ? barWindow.holdActionGlow
                        : (accentLineState.cpuHot || accentLineState.lowBattery) ? mocha.red
                        : accentLineState.renderColor
                    readonly property color hotColor: barWindow.accentPulse ? Qt.tint(accentLineState.baseColor, "#80ffffff") : accentLineState.baseColor
                }

                // Dedicated color cycle for the accent line only — separate from
                // accentAmbient/accentCycleColor above so topBarAccentLineSpeedMs
                // never speeds up or slows down the pill border echoes that also
                // read accentCycleColor. Runs whenever color mode is "cycle", or
                // "album" with nothing currently playing (matches AmbientGlow.qml).
                QtObject {
                    id: accentLineAmbient
                    readonly property color cycleColor: barWindow.cyc3(mocha.mauve, mocha.pink, mocha.blue, barWindow.slowT, Math.max(500, barWindow.topBarAccentLineSpeedMs))
                }

                // Dedicated breathing wave for accentGlow2, decoupled from the
                // shared ambientWave the pill echoes use — so the speed setting
                // scales it without touching them. Ratio to duration matches the
                // original fixed 9000ms at the default 5200ms speed.
                QtObject {
                    id: accentLineAnim
                    readonly property real wave: (barWindow.slowT % Math.max(1500, Math.round(barWindow.topBarAccentLineSpeedMs * (9000.0 / 5200.0)))) / Math.max(1500, Math.round(barWindow.topBarAccentLineSpeedMs * (9000.0 / 5200.0)))
                    function breath(phase) {
                        return 0.5 + 0.5 * Math.sin((accentLineAnim.wave + phase) * Math.PI * 2)
                    }
                }

                // Shared by both orientations. Durations scale with the speed
                // setting, ratio matches the original fixed 6000/7400ms at the
                // default 5200ms speed.
                QtObject {
                    id: accentSweep
                    readonly property real pos: barWindow.pingPong(barWindow.slowT, Math.max(1200, Math.round(barWindow.topBarAccentLineSpeedMs * (6000.0 / 5200.0))))
                }
                // Second highlight, deliberately off-tempo (7400ms vs 6000ms at
                // default speed, opposite phase start) so the two never travel
                // in lockstep.
                QtObject {
                    id: accentSweep2
                    readonly property real pos: 1.0 - barWindow.pingPong(barWindow.slowT, Math.max(1200, Math.round(barWindow.topBarAccentLineSpeedMs * (7400.0 / 5200.0))))
                }

                // ---- Horizontal rail (top/bottom) ----
                Rectangle {
                    id: railH
                    visible: barWindow.topBarAccentLine && !accentLineState.vertical
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: accentLineState.thickness
                    y: barWindow.topBarAccentLinePosition === "top" ? 0 : (parent.height - height)
                    color: accentLineState.baseColor
                    opacity: accentLineState.lineOpacity
                }
                Rectangle {
                    id: accentGlow1H
                    visible: barWindow.topBarAccentLine && !accentLineState.vertical
                    width: Math.min(barWindow.s(160), railH.width * 0.22)
                    height: accentLineState.thickness + barWindow.s(1.8) * accentLineState.accentAmp
                    x: accentSweep.pos * (railH.width - width)
                    y: barWindow.topBarAccentLinePosition === "top" ? 0 : (parent.height - height)
                    opacity: accentLineState.holding
                        ? (0.5 + 0.5 * barWindow.holdActionProgress)
                        : Math.min(0.95, (barWindow.accentPulse ? 0.85 : (accentLineState.lowBattery || accentLineState.cpuHot ? 0.5 : 0.4)) + accentLineState.beatInfluence * 0.35)
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: accentLineState.hotColor }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
                Rectangle {
                    id: accentGlow2H
                    visible: barWindow.topBarAccentLine && !accentLineState.vertical && accentLineState.calm
                    width: Math.min(barWindow.s(90), railH.width * 0.13)
                    height: accentLineState.thickness + barWindow.s(0.8) * accentLineAnim.breath(0.96)
                    x: accentSweep2.pos * (railH.width - width)
                    y: barWindow.topBarAccentLinePosition === "top" ? 0 : (parent.height - height)
                    opacity: 0.05 + 0.09 * accentLineAnim.breath(0.96)
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: accentLineState.baseColor }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                // ---- Vertical rail (left/right) ----
                // Positioned entirely off barWindow.width/height (not barRow,
                // and no anchors at all — every dimension set explicitly) since
                // this needs to run the full screen edge, not just the bar strip.
                Rectangle {
                    id: railV
                    visible: barWindow.topBarAccentLine && accentLineState.vertical
                    y: 0
                    height: barWindow.height
                    width: accentLineState.thickness
                    x: barWindow.topBarAccentLinePosition === "left" ? 0 : (barWindow.width - width)
                    color: accentLineState.baseColor
                    opacity: accentLineState.lineOpacity
                }
                Rectangle {
                    id: accentGlow1V
                    visible: barWindow.topBarAccentLine && accentLineState.vertical
                    height: Math.min(barWindow.s(160), railV.height * 0.22)
                    width: accentLineState.thickness + barWindow.s(1.8) * accentLineState.accentAmp
                    y: accentSweep.pos * (railV.height - height)
                    x: barWindow.topBarAccentLinePosition === "left" ? 0 : (barWindow.width - width)
                    opacity: accentLineState.holding
                        ? (0.5 + 0.5 * barWindow.holdActionProgress)
                        : Math.min(0.95, (barWindow.accentPulse ? 0.85 : (accentLineState.lowBattery || accentLineState.cpuHot ? 0.5 : 0.4)) + accentLineState.beatInfluence * 0.35)
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: accentLineState.hotColor }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
                Rectangle {
                    id: accentGlow2V
                    visible: barWindow.topBarAccentLine && accentLineState.vertical && accentLineState.calm
                    height: Math.min(barWindow.s(90), railV.height * 0.13)
                    width: accentLineState.thickness + barWindow.s(0.8) * accentLineAnim.breath(0.96)
                    y: accentSweep2.pos * (railV.height - height)
                    x: barWindow.topBarAccentLinePosition === "left" ? 0 : (barWindow.width - width)
                    opacity: 0.05 + 0.09 * accentLineAnim.breath(0.96)
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: accentLineState.baseColor }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                // ---------------- WALLPAPER-COLOR SWEEP (outer bar border) ----------------
                // Settings-driven: topBarWallpaperSweepEnabled (default true). A slow
                // (10s loop), ambient gradient traveling along the OUTERMOST edge of the
                // whole bar strip (barRow's own bounding rect) — distinct from
                // topBarAccentLine above (a single-edge "rail", user-picks-one-edge,
                // beat/hold-action reactive) — this one always traces all 4 edges and is
                // purely a subtle "matches my wallpaper" ambient wash. Built from REAL
                // matugen palette roles (mocha.blue/peach/green/pink — 4 visually
                // distinct hues) — the one deliberate exception to "never use matugen
                // names for glow semantics" in CLAUDE.md, since the entire point here is
                // "reacts to my actual wallpaper". QtQuick has no native conic/moving
                // gradient primitive, so this uses the documented acceptable fallback: a
                // Canvas repainted on a ~30fps Timer (not a per-frame binding) drawing a
                // diagonal linear gradient whose stop offsets rotate over time. Kept
                // deliberately subtle (opacity ~0.2) — ambient chrome, not a strobe.
                Canvas {
                    id: wallpaperSweepCanvas
                    anchors.fill: parent
                    z: 999
                    visible: barWindow.topBarWallpaperSweepEnabled

                    property real phase: 0.0
                    NumberAnimation on phase {
                        from: 0; to: 1
                        duration: 10000
                        loops: Animation.Infinite
                        running: barWindow.topBarWallpaperSweepEnabled
                    }

                    Timer {
                        interval: 33
                        running: barWindow.topBarWallpaperSweepEnabled
                        repeat: true
                        onTriggered: wallpaperSweepCanvas.requestPaint()
                    }

                    onPaint: {
                        let ctx = getContext("2d")
                        let w = width, h = height
                        ctx.clearRect(0, 0, w, h)
                        if (w <= 0 || h <= 0) return

                        let colors = [mocha.blue, mocha.peach, mocha.green, mocha.pink]
                        let n = colors.length
                        let stops = []
                        for (let i = 0; i < n; i++) {
                            stops.push({ off: (i / n + wallpaperSweepCanvas.phase) % 1.0, col: colors[i] })
                        }
                        stops.sort((a, b) => a.off - b.off)

                        let grad = ctx.createLinearGradient(0, 0, w, h)
                        for (let s of stops) grad.addColorStop(s.off, s.col)

                        // Was a single 1.6px stroke at opacity 0.2 — reads as an inert
                        // static line at a glance, not a "sweep". Two passes now: a
                        // wide, faint glow underneath (fakes a soft blur QtQuick has no
                        // cheap primitive for) plus a brighter, tighter core line on top,
                        // both noticeably bolder than before.
                        let lw = barWindow.s(2.5)
                        ctx.strokeStyle = grad
                        ctx.lineWidth = lw * 3
                        ctx.globalAlpha = 0.18
                        ctx.strokeRect(lw * 1.5, lw * 1.5, w - lw * 3, h - lw * 3)
                        ctx.lineWidth = lw
                        ctx.globalAlpha = 0.55
                        ctx.strokeRect(lw / 2, lw / 2, w - lw, h - lw)
                    }
                }
            }
        }
    }
}
