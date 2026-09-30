import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
Item {
    id: root
    focus: true

    // --- Responsive Scaling Logic ---
    Scaler {
        id: scaler
        currentWidth: Screen.width
    }
    
    function s(val) { 
        return scaler.s(val); 
    }

    // --- Helper Functions ---
    function formatBytes(bytes) {
        if (bytes === 0 || isNaN(bytes)) return '0 B';
        var k = 1024;
        var sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        var i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
    }

    // -------------------------------------------------------------------------
    // KEYBOARD SHORTCUTS & NAVIGATION
    // -------------------------------------------------------------------------
    Keys.onEscapePressed: {
        closeSequence.start();
        event.accepted = true;
    }
    Keys.onTabPressed: {
        currentTab = (currentTab + 1) % tabNames.length;
        event.accepted = true;
    }
    Keys.onBacktabPressed: {
        currentTab = (currentTab - 1 + tabNames.length) % tabNames.length;
        event.accepted = true;
    }
    Keys.onLeftPressed: {
        if (currentTab === 3) { 
            if (selectedModuleIndex > 0) {
                selectedModuleIndex--;
                if (tab3Loader.item) tab3Loader.item.x_modulesList.positionViewAtIndex(selectedModuleIndex, ListView.Contain);
            }
            event.accepted = true;
        }
    }
    Keys.onRightPressed: {
        if (currentTab === 3) { 
            if (selectedModuleIndex < modulesDataModel.count - 1) {
                selectedModuleIndex++;
                if (tab3Loader.item) tab3Loader.item.x_modulesList.positionViewAtIndex(selectedModuleIndex, ListView.Contain);
            }
            event.accepted = true;
        }
    }
    Keys.onReturnPressed: {
        if (currentTab === 3) { 
            let target = modulesDataModel.get(selectedModuleIndex).target;
            Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "toggle", target]);
            event.accepted = true;
        }
    }
    Keys.onEnterPressed: { Keys.onReturnPressed(event); }

    MatugenColors { id: _theme }
    // -------------------------------------------------------------------------
    // COLORS
    // -------------------------------------------------------------------------
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color subtext1: _theme.subtext1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color overlay0: _theme.overlay0
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color blue: _theme.blue
    readonly property color sapphire: _theme.sapphire
    readonly property color green: _theme.green
    readonly property color peach: _theme.peach
    readonly property color yellow: _theme.yellow
    readonly property color red: _theme.red
    readonly property color teal: _theme.teal || "#94e2d5"

    property real colorBlend: 0.0
    SequentialAnimation on colorBlend {
        loops: Animation.Infinite
        running: true
        NumberAnimation { to: 1.0; duration: 15000; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.0; duration: 15000; easing.type: Easing.InOutSine }
    }
    
    property color ambientPurple: Qt.tint(root.mauve, Qt.rgba(root.pink.r, root.pink.g, root.pink.b, colorBlend))
    property color ambientBlue: Qt.tint(root.blue, Qt.rgba(root.sapphire.r, root.sapphire.g, root.sapphire.b, colorBlend))

    // -------------------------------------------------------------------------
    // SSOT GLOBAL SETTINGS
    // -------------------------------------------------------------------------
    property real setUiScale: 1.0
    property bool setOpenGuideAtStartup: true
    property bool setClaudeDebug: false
    property bool setDiscordProfiler: false
    property int  setCalendarRefreshMinutes: 5
    property bool setShowCalendarPill: true
    property bool setTopBarAccentLine: true
    property string setTopBarAccentLinePosition: "bottom" // "top" | "bottom" | "left" | "right"
    property real setTopBarAccentLineThickness: 1
    property int setTopBarAccentLineSpeedMs: 5200
    property string setTopBarAccentLineColorMode: "cycle" // "cycle" | "fixed" | "album"
    property string setTopBarAccentLineFixedColor: "#cba6f7"
    // Ambient Glow — full-screen per-monitor edge bezel (AmbientGlow.qml). Deliberately
    // its own master toggle rather than reusing topBarAccentLine: related feature, same
    // palette, but a materially different surface (full-screen overlay vs. a slim bar line),
    // so a user may want one without the other.
    property bool setAmbientGlowEnabled: true
    property real setAmbientGlowIntensity: 1.0
    property int  setAmbientGlowSpread: 140
    property bool setAmbientGlowEdgeTop: true
    property bool setAmbientGlowEdgeBottom: true
    property bool setAmbientGlowEdgeLeft: true
    property bool setAmbientGlowEdgeRight: true
    property string setAmbientGlowColorMode: "cycle"
    property string setAmbientGlowFixedColor: "#cba6f7"
    property bool setAmbientGlowBeatReactive: true
    property int  setAmbientGlowCycleSpeedMs: 5200
    property string setAmbientGlowIdleBehavior: "dim"
    // consumed by TopBar.qml's media pill (audio-reactive equalizer visualizer) — not wired here,
    // that file is owned by another agent right now. This only persists the setting itself.
    property bool setMediaVisualizerEnabled: true
    // "pulse" (single overall RMS scalar) | "fft" (real per-band spectrum,
    // audio_spectrum.py) — consumed by TopBar.qml's media pill visualizer.
    property string setMediaVisualizerMode: "pulse"
    // The fft mode's peak-hold line: snaps up with the bar, decays slowly
    // back down on its own. Independent toggle from the visualizer itself.
    property bool setMediaVisualizerPeakHoldEnabled: true
    // FFT gain multiplier — hot-read directly from settings.json by
    // audio_spectrum.py itself (it's a long-lived process; a launch-arg
    // would mean restarting audio capture on every slider drag).
    property real setTopBarFftIntensity: 1.0
    // "dominant" = most-frequent album-art pixel colors. "vibrant" = most
    // saturated candidates from the same quantize pass — often more legible
    // on a mostly-dark/mostly-black cover with one small vivid element.
    property string setTopBarVisualizerColorSource: "dominant"
    // Seconds to shift the synced-lyrics highlight — positive = ahead of
    // (earlier than) the estimated playback position.
    property real setLyricsSyncOffsetSec: 1.0
    // consumed by media_seek.sh / media_control.sh — gates the Hyprland border pulse
    // triggered by Spotify seek/pause, read directly from settings.json via jq
    property bool setHyprlandBorderPulseEnabled: true
    // TopBar feature toggles — consumed directly by TopBar.qml (its own
    // settings.json reader), each independently flippable, default on.
    property bool setTopBarHoverCardsEnabled: true
    property string setTopBarBatteryLiquidMode: "occasional"
    property string setTopBarPillBgMaster: "occasional"
    property string setTopBarSkyMode: "occasional"
    property string setTopBarWifiRadarMode: "occasional"
    property string setTopBarBtPulseMode: "occasional"
    property string setTopBarCpuAreaMode: "occasional"
    property string setTopBarNetParticlesMode: "occasional"
    property string setTopBarUptimeStarsMode: "occasional"
    property string setTopBarWorkspaceTintMode: "occasional"
    property string setTopBarClaudeAuroraMode: "occasional"
    property string setTopBarEcoIndicatorMode: "occasional"
    property string setSmartWsAutoNames: "hover"
    property bool setSmartWsLayoutsEnabled: true
    property bool setSmartWsRestoreConfirm: true
    property bool setLockStyleEnabled: true
    property bool setLockShowMusic: true
    property bool setLockShowWeather: true
    property string setLockShowNotifs: "count"
    property bool setLockShowBrief: true
    property real setLockBlurStrength: 0.8
    property bool setLockParallax: true
    property string setLockAmbientFx: "occasional"
    property string setLockClockStyle: "big"
    property bool setLockShowQuickActions: true
    property string setHyprPolishAnimations: "subtle"
    property string setHyprPolishDimInactive: "off"
    property string setHyprPolishWsAccent: "palette"
    property string setHyprPolishWsAccentSpeed: "normal"
    property string setTopBarVolumeFillMode: "occasional"
    property bool setTopBarShowGpu: true
    property bool setTopBarShowNet: true
    property bool setTopBarShowUptime: true
    property bool setTopBarShowQuickshellCpu: true
    property bool setTopBarBpmRingEnabled: true
    property bool setTopBarWorkspaceIconsEnabled: true
    property bool setEcoModeEnabled: true
    property real setEcoThrottleSecs: 20
    property real setEcoFreezeSecs: 300
    property bool setTopBarTimerEnabled: true
    property string setTopBarTimerFillMode: "always"
    property bool setResidentCardsEnabled: true
    property string setResidentCardPosition: "under-middle-pill"
    property string setResidentCardMaxHeight: "medium"
    property string setResidentCardHoldMode: "auto"
    property string setResidentCardSound: "on"
    property string setResidentCardSoundFile: "complete"
    property string setScreenshotAnswerOutput: "card"
    property bool setResidentNowPlayingEnabled: true
    property bool setResidentCalendarNudgeEnabled: true
    property bool setResidentBatteryHealthEnabled: true
    property bool setResidentUptimeGuiltEnabled: true
    property bool setResidentFocusDoneEnabled: true
    property string setResidentAfternoonBrief: "text"
    property string setResidentAfternoonBriefTime: "13:00-16:00"
    property string setResidentNightBrief: "text"
    property string setResidentNightBriefTime: "20:30-23:59"
    property string setResidentShotAnswerPrompt: ""
    property string setResidentShotClassifyPrompt: ""
    property bool setTopBarWallpaperSweepEnabled: true
    property bool setTopBarFlourishesEnabled: true
    property bool setTopBarFlourishUptimeEnabled: true
    property bool setTopBarFlourishBatteryEnabled: true
    property bool setTopBarFlourishCpuCalmEnabled: true
    property string setWallpaperDir: {
        const dir = Quickshell.env("WALLPAPER_DIR")
        return (dir && dir !== "") 
        ? dir 
        : Quickshell.env("HOME") + "/Pictures/Wallpapers"
    }
    property string setLanguage: ""
    property bool setResidentVoiceNudges: true
    property string setResidentStrictness: "balanced"
    property string setResidentMorningBrief: "text"
    property string setResidentBriefTime: "05:00-11:00"
    property bool setResidentCatchUp: true
    property string setResidentProactiveFixes: "suggest"
    property bool setResidentClipboardAware: true
    property bool setResidentEcoNotice: true
    property bool setResidentDeviceAlerts: true
    property real setResidentSongReactChance: 0.3
    property int  setResidentPassiveExpireSecs: 30
    property bool setResidentPillTakeoverEnabled: true
    property bool setResidentLayoutSuggestions: true
    property string setBatteryAlertStyle: "integrated"
    property string setNightLightStart: "18:00"
    property string setNightLightEnd: "07:00"
    property int  setNightLightTemp: 4000
    property int  setPinGridSize: 12
    property bool setPinClutterCap: true
    property bool setPinCompactMode: true
    property string setChatThinkingStyle: "shimmer"
    property bool setCardAnimations: true
    property bool setCardDepth: true
    property string setCardAccent: "blue"
    property string setAgendaDefaultFilter: "all"

    // live-apply the card accent the moment it's clicked — patch just the cardAccent
    // key in settings.json (jq) so CardRenderer's settings watcher recolors instantly,
    // without waiting for a full Apply. debounced to coalesce rapid clicks. _accentReady
    // is set in the root Component.onCompleted below (a second one here would be ignored).
    property bool _accentReady: false
    onSetCardAccentChanged: if (_accentReady) accentSaveTimer.restart()
    Timer {
        id: accentSaveTimer
        interval: 120
        onTriggered: { accentWriter.running = false; accentWriter.running = true; }
    }
    Process {
        id: accentWriter
        running: false
        command: ["bash", "-c",
            "f=~/.config/hypr/settings.json; [ -f \"$f\" ] || echo '{}' > \"$f\"; " +
            "tmp=$(mktemp); jq --arg a \"$1\" '.cardAccent=$a' \"$f\" > \"$tmp\" 2>/dev/null " +
            "&& mv \"$tmp\" \"$f\" || rm -f \"$tmp\"",
            "_", root.setCardAccent]
    }
    property string setStyleMonitors: "legacy"
    property string setStyleFocustime: "legacy"
    property string setStyleNotifications: "legacy"
    property string setStyleWallpaper: "legacy"
    property string setStyleNotificationsCenter: "legacy"
    property string setStyleVolume: "legacy"
    property string setStyleWorkspaces: "legacy"

    function styleFor(key) {
        if (key === "monitors") return root.setStyleMonitors;
        if (key === "focustime") return root.setStyleFocustime;
        if (key === "notifications_popup") return root.setStyleNotifications;
        if (key === "wallpaper") return root.setStyleWallpaper;
        if (key === "notifications_center") return root.setStyleNotificationsCenter;
        if (key === "volume") return root.setStyleVolume;
        if (key === "workspaces") return root.setStyleWorkspaces;
        return "legacy";
    }

    function writeWidgetStyle(key, value) {
        let cmd = "jq '.widgetStyles." + key + " = \"" + value + "\"' ~/.config/hypr/settings.json > /tmp/qs_settings_tmp && mv /tmp/qs_settings_tmp ~/.config/hypr/settings.json";
        Quickshell.execDetached(["bash", "-c", cmd]);
    }

    function setStyleFor(key, value) {
        if (key === "monitors") root.setStyleMonitors = value;
        else if (key === "focustime") root.setStyleFocustime = value;
        else if (key === "notifications_popup") root.setStyleNotifications = value;
        else if (key === "wallpaper") root.setStyleWallpaper = value;
        else if (key === "notifications_center") root.setStyleNotificationsCenter = value;
        else if (key === "volume") root.setStyleVolume = value;
        else if (key === "workspaces") root.setStyleWorkspaces = value;
        root.writeWidgetStyle(key, value);
    }

    function saveAppSettings() {
        let config = {
            "uiScale": root.setUiScale,
            "openGuideAtStartup": root.setOpenGuideAtStartup,
            "wallpaperDir": root.setWallpaperDir,
            "language": root.setLanguage,
            "calendarRefreshMinutes": root.setCalendarRefreshMinutes,
            "showCalendarPill": root.setShowCalendarPill,
            "topBarAccentLine": root.setTopBarAccentLine,
            "topBarAccentLinePosition": root.setTopBarAccentLinePosition,
            "topBarAccentLineThickness": root.setTopBarAccentLineThickness,
            "topBarAccentLineSpeedMs": root.setTopBarAccentLineSpeedMs,
            "topBarAccentLineColorMode": root.setTopBarAccentLineColorMode,
            "topBarAccentLineFixedColor": root.setTopBarAccentLineFixedColor,
            "ambientGlowEnabled": root.setAmbientGlowEnabled,
            "ambientGlowIntensity": root.setAmbientGlowIntensity,
            "ambientGlowSpread": root.setAmbientGlowSpread,
            "ambientGlowEdgeTop": root.setAmbientGlowEdgeTop,
            "ambientGlowEdgeBottom": root.setAmbientGlowEdgeBottom,
            "ambientGlowEdgeLeft": root.setAmbientGlowEdgeLeft,
            "ambientGlowEdgeRight": root.setAmbientGlowEdgeRight,
            "ambientGlowColorMode": root.setAmbientGlowColorMode,
            "ambientGlowFixedColor": root.setAmbientGlowFixedColor,
            "ambientGlowBeatReactive": root.setAmbientGlowBeatReactive,
            "ambientGlowCycleSpeedMs": root.setAmbientGlowCycleSpeedMs,
            "ambientGlowIdleBehavior": root.setAmbientGlowIdleBehavior,
            "mediaVisualizerEnabled": root.setMediaVisualizerEnabled,
            "mediaVisualizerMode": root.setMediaVisualizerMode,
            "mediaVisualizerPeakHoldEnabled": root.setMediaVisualizerPeakHoldEnabled,
            "topBarFftIntensity": root.setTopBarFftIntensity,
            "topBarVisualizerColorSource": root.setTopBarVisualizerColorSource,
            "lyricsSyncOffsetSec": root.setLyricsSyncOffsetSec,
            "hyprlandBorderPulseEnabled": root.setHyprlandBorderPulseEnabled,
            "topBarHoverCardsEnabled": root.setTopBarHoverCardsEnabled,
            "topBarBatteryLiquidMode": root.setTopBarBatteryLiquidMode,
            "topBarPillBgMaster": root.setTopBarPillBgMaster,
            "topBarSkyMode": root.setTopBarSkyMode,
            "topBarWifiRadarMode": root.setTopBarWifiRadarMode,
            "topBarBtPulseMode": root.setTopBarBtPulseMode,
            "topBarCpuAreaMode": root.setTopBarCpuAreaMode,
            "topBarNetParticlesMode": root.setTopBarNetParticlesMode,
            "topBarUptimeStarsMode": root.setTopBarUptimeStarsMode,
            "topBarWorkspaceTintMode": root.setTopBarWorkspaceTintMode,
            "topBarClaudeAuroraMode": root.setTopBarClaudeAuroraMode,
            "topBarEcoIndicatorMode": root.setTopBarEcoIndicatorMode,
            "smartWsAutoNames": root.setSmartWsAutoNames,
            "smartWsLayoutsEnabled": root.setSmartWsLayoutsEnabled,
            "smartWsRestoreConfirm": root.setSmartWsRestoreConfirm,
            "lockStyleEnabled": root.setLockStyleEnabled,
            "lockShowMusic": root.setLockShowMusic,
            "lockShowWeather": root.setLockShowWeather,
            "lockShowNotifs": root.setLockShowNotifs,
            "lockShowBrief": root.setLockShowBrief,
            "lockBlurStrength": root.setLockBlurStrength,
            "lockParallax": root.setLockParallax,
            "lockAmbientFx": root.setLockAmbientFx,
            "lockClockStyle": root.setLockClockStyle,
            "lockShowQuickActions": root.setLockShowQuickActions,
            "hyprPolishAnimations": root.setHyprPolishAnimations,
            "hyprPolishDimInactive": root.setHyprPolishDimInactive,
            "hyprPolishWsAccent": root.setHyprPolishWsAccent,
            "hyprPolishWsAccentSpeed": root.setHyprPolishWsAccentSpeed,
            "topBarVolumeFillMode": root.setTopBarVolumeFillMode,
            "topBarShowGpu": root.setTopBarShowGpu,
            "topBarShowNet": root.setTopBarShowNet,
            "topBarShowUptime": root.setTopBarShowUptime,
            "topBarShowQuickshellCpu": root.setTopBarShowQuickshellCpu,
            "topBarBpmRingEnabled": root.setTopBarBpmRingEnabled,
            "topBarWorkspaceIconsEnabled": root.setTopBarWorkspaceIconsEnabled,
            "ecoModeEnabled": root.setEcoModeEnabled,
            "ecoThrottleSecs": root.setEcoThrottleSecs,
            "ecoFreezeSecs": root.setEcoFreezeSecs,
            "topBarTimerEnabled": root.setTopBarTimerEnabled,
            "topBarTimerFillMode": root.setTopBarTimerFillMode,
            "residentCardsEnabled": root.setResidentCardsEnabled,
            "residentCardPosition": root.setResidentCardPosition,
            "residentCardMaxHeight": root.setResidentCardMaxHeight,
            "residentCardHoldMode": root.setResidentCardHoldMode,
            "residentCardSound": root.setResidentCardSound,
            "residentCardSoundFile": root.setResidentCardSoundFile,
            "screenshotAnswerOutput": root.setScreenshotAnswerOutput,
            "residentNowPlayingEnabled": root.setResidentNowPlayingEnabled,
            "residentCalendarNudgeEnabled": root.setResidentCalendarNudgeEnabled,
            "residentBatteryHealthEnabled": root.setResidentBatteryHealthEnabled,
            "residentUptimeGuiltEnabled": root.setResidentUptimeGuiltEnabled,
            "residentFocusDoneEnabled": root.setResidentFocusDoneEnabled,
            "residentAfternoonBrief": root.setResidentAfternoonBrief,
            "residentAfternoonBriefTime": root.setResidentAfternoonBriefTime,
            "residentNightBrief": root.setResidentNightBrief,
            "residentNightBriefTime": root.setResidentNightBriefTime,
            "residentShotAnswerPrompt": root.setResidentShotAnswerPrompt,
            "residentShotClassifyPrompt": root.setResidentShotClassifyPrompt,
            "topBarWallpaperSweepEnabled": root.setTopBarWallpaperSweepEnabled,
            "topBarFlourishesEnabled": root.setTopBarFlourishesEnabled,
            "topBarFlourishUptimeEnabled": root.setTopBarFlourishUptimeEnabled,
            "topBarFlourishBatteryEnabled": root.setTopBarFlourishBatteryEnabled,
            "topBarFlourishCpuCalmEnabled": root.setTopBarFlourishCpuCalmEnabled,
            "claudeDebug": root.setClaudeDebug,
            "discordProfiler": root.setDiscordProfiler,
            "residentVoiceNudges": root.setResidentVoiceNudges,
            "residentStrictness": root.setResidentStrictness,
            "residentMorningBrief": root.setResidentMorningBrief,
            "residentBriefTime": root.setResidentBriefTime,
            "residentCatchUp": root.setResidentCatchUp,
            "residentProactiveFixes": root.setResidentProactiveFixes,
            "residentClipboardAware": root.setResidentClipboardAware,
            "residentEcoNotice": root.setResidentEcoNotice,
            "residentDeviceAlerts": root.setResidentDeviceAlerts,
            "residentSongReactChance": root.setResidentSongReactChance,
            "residentPassiveExpireSecs": root.setResidentPassiveExpireSecs,
            "residentPillTakeoverEnabled": root.setResidentPillTakeoverEnabled,
            "residentLayoutSuggestions": root.setResidentLayoutSuggestions,
            "batteryAlertStyle": root.setBatteryAlertStyle,
            "nightLightStart": root.setNightLightStart,
            "nightLightEnd": root.setNightLightEnd,
            "nightLightTemp": root.setNightLightTemp,
            "pinGridSize": root.setPinGridSize,
            "pinClutterCap": root.setPinClutterCap,
            "pinCompactMode": root.setPinCompactMode,
            "chatThinkingStyle": root.setChatThinkingStyle,
            "cardAnimations": root.setCardAnimations,
            "cardDepth": root.setCardDepth,
            "cardAccent": root.setCardAccent,
            "agendaDefaultFilter": root.setAgendaDefaultFilter,
            "widgetStyles": {
                "monitors": root.setStyleMonitors,
                "focustime": root.setStyleFocustime,
                "notifications_popup": root.setStyleNotifications,
                "wallpaper": root.setStyleWallpaper,
                "notifications_center": root.setStyleNotificationsCenter,
                "volume": root.setStyleVolume,
                "workspaces": root.setStyleWorkspaces
            }
        };
        let jsonString = JSON.stringify(config, null, 2);
        
        let cmd = "mkdir -p ~/.config/hypr/ && echo '" + jsonString + "' > ~/.config/hypr/settings.json";
                  
        Quickshell.execDetached(["bash", "-c", cmd]);
    }


    Process {
        id: hyprLangReader
        command: ["bash", "-c", "grep -m1 '^ *kb_layout *=' ~/.config/hypr/hyprland.conf | cut -d'=' -f2 | tr -d ' '"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text ? this.text.trim() : "";
                if (out.length > 0 && root.setLanguage === "") {
                    root.setLanguage = out;
                }
            }
        }
    }

    Process {
        id: settingsReader
        command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (this.text && this.text.trim().length > 0 && this.text.trim() !== "{}") {
                        let parsed = JSON.parse(this.text);
                        if (parsed.uiScale !== undefined) root.setUiScale = parsed.uiScale;
                        if (parsed.openGuideAtStartup !== undefined) root.setOpenGuideAtStartup = parsed.openGuideAtStartup;
                        if (parsed.wallpaperDir !== undefined) root.setWallpaperDir = parsed.wallpaperDir;
                        if (parsed.language !== undefined && parsed.language !== "") root.setLanguage = parsed.language;
                        if (parsed.calendarRefreshMinutes !== undefined) root.setCalendarRefreshMinutes = parsed.calendarRefreshMinutes;
                        if (parsed.showCalendarPill !== undefined) root.setShowCalendarPill = parsed.showCalendarPill;
                        if (parsed.topBarAccentLine !== undefined) root.setTopBarAccentLine = parsed.topBarAccentLine;
                        if (parsed.topBarAccentLinePosition !== undefined) root.setTopBarAccentLinePosition = parsed.topBarAccentLinePosition;
                        if (parsed.topBarAccentLineThickness !== undefined) root.setTopBarAccentLineThickness = parsed.topBarAccentLineThickness;
                        if (parsed.topBarAccentLineSpeedMs !== undefined) root.setTopBarAccentLineSpeedMs = parsed.topBarAccentLineSpeedMs;
                        if (parsed.topBarAccentLineColorMode !== undefined) root.setTopBarAccentLineColorMode = parsed.topBarAccentLineColorMode;
                        if (parsed.topBarAccentLineFixedColor !== undefined) root.setTopBarAccentLineFixedColor = parsed.topBarAccentLineFixedColor;
                        if (parsed.ambientGlowEnabled !== undefined) root.setAmbientGlowEnabled = parsed.ambientGlowEnabled;
                        if (parsed.ambientGlowIntensity !== undefined) root.setAmbientGlowIntensity = parsed.ambientGlowIntensity;
                        if (parsed.ambientGlowSpread !== undefined) root.setAmbientGlowSpread = parsed.ambientGlowSpread;
                        if (parsed.ambientGlowEdgeTop !== undefined) root.setAmbientGlowEdgeTop = parsed.ambientGlowEdgeTop;
                        if (parsed.ambientGlowEdgeBottom !== undefined) root.setAmbientGlowEdgeBottom = parsed.ambientGlowEdgeBottom;
                        if (parsed.ambientGlowEdgeLeft !== undefined) root.setAmbientGlowEdgeLeft = parsed.ambientGlowEdgeLeft;
                        if (parsed.ambientGlowEdgeRight !== undefined) root.setAmbientGlowEdgeRight = parsed.ambientGlowEdgeRight;
                        if (parsed.ambientGlowColorMode !== undefined) root.setAmbientGlowColorMode = parsed.ambientGlowColorMode;
                        if (parsed.ambientGlowFixedColor !== undefined) root.setAmbientGlowFixedColor = parsed.ambientGlowFixedColor;
                        if (parsed.ambientGlowBeatReactive !== undefined) root.setAmbientGlowBeatReactive = parsed.ambientGlowBeatReactive;
                        if (parsed.ambientGlowCycleSpeedMs !== undefined) root.setAmbientGlowCycleSpeedMs = parsed.ambientGlowCycleSpeedMs;
                        if (parsed.ambientGlowIdleBehavior !== undefined) root.setAmbientGlowIdleBehavior = parsed.ambientGlowIdleBehavior;
                        if (parsed.mediaVisualizerEnabled !== undefined) root.setMediaVisualizerEnabled = parsed.mediaVisualizerEnabled;
                        if (parsed.mediaVisualizerMode !== undefined) root.setMediaVisualizerMode = parsed.mediaVisualizerMode;
                        if (parsed.mediaVisualizerPeakHoldEnabled !== undefined) root.setMediaVisualizerPeakHoldEnabled = parsed.mediaVisualizerPeakHoldEnabled;
                        if (parsed.topBarFftIntensity !== undefined) root.setTopBarFftIntensity = parsed.topBarFftIntensity;
                        if (parsed.topBarVisualizerColorSource !== undefined) root.setTopBarVisualizerColorSource = parsed.topBarVisualizerColorSource;
                        if (parsed.lyricsSyncOffsetSec !== undefined) root.setLyricsSyncOffsetSec = parsed.lyricsSyncOffsetSec;
                        if (parsed.hyprlandBorderPulseEnabled !== undefined) root.setHyprlandBorderPulseEnabled = parsed.hyprlandBorderPulseEnabled;
                        if (parsed.topBarHoverCardsEnabled !== undefined) root.setTopBarHoverCardsEnabled = parsed.topBarHoverCardsEnabled;
                        if (parsed.topBarBatteryLiquidMode !== undefined) root.setTopBarBatteryLiquidMode = parsed.topBarBatteryLiquidMode;
                        if (parsed.topBarPillBgMaster !== undefined) root.setTopBarPillBgMaster = parsed.topBarPillBgMaster;
                        if (parsed.topBarSkyMode !== undefined) root.setTopBarSkyMode = parsed.topBarSkyMode;
                        if (parsed.topBarWifiRadarMode !== undefined) root.setTopBarWifiRadarMode = parsed.topBarWifiRadarMode;
                        if (parsed.topBarBtPulseMode !== undefined) root.setTopBarBtPulseMode = parsed.topBarBtPulseMode;
                        if (parsed.topBarCpuAreaMode !== undefined) root.setTopBarCpuAreaMode = parsed.topBarCpuAreaMode;
                        if (parsed.topBarNetParticlesMode !== undefined) root.setTopBarNetParticlesMode = parsed.topBarNetParticlesMode;
                        if (parsed.topBarUptimeStarsMode !== undefined) root.setTopBarUptimeStarsMode = parsed.topBarUptimeStarsMode;
                        if (parsed.topBarWorkspaceTintMode !== undefined) root.setTopBarWorkspaceTintMode = parsed.topBarWorkspaceTintMode;
                        if (parsed.topBarClaudeAuroraMode !== undefined) root.setTopBarClaudeAuroraMode = parsed.topBarClaudeAuroraMode;
                        if (parsed.topBarEcoIndicatorMode !== undefined) root.setTopBarEcoIndicatorMode = parsed.topBarEcoIndicatorMode;
                        if (parsed.smartWsAutoNames !== undefined) root.setSmartWsAutoNames = parsed.smartWsAutoNames;
                        if (parsed.smartWsLayoutsEnabled !== undefined) root.setSmartWsLayoutsEnabled = parsed.smartWsLayoutsEnabled;
                        if (parsed.smartWsRestoreConfirm !== undefined) root.setSmartWsRestoreConfirm = parsed.smartWsRestoreConfirm;
                        if (parsed.lockStyleEnabled !== undefined) root.setLockStyleEnabled = parsed.lockStyleEnabled;
                        if (parsed.lockShowMusic !== undefined) root.setLockShowMusic = parsed.lockShowMusic;
                        if (parsed.lockShowWeather !== undefined) root.setLockShowWeather = parsed.lockShowWeather;
                        if (parsed.lockShowNotifs !== undefined) root.setLockShowNotifs = parsed.lockShowNotifs;
                        if (parsed.lockShowBrief !== undefined) root.setLockShowBrief = parsed.lockShowBrief;
                        if (parsed.lockBlurStrength !== undefined) root.setLockBlurStrength = parsed.lockBlurStrength;
                        if (parsed.lockParallax !== undefined) root.setLockParallax = parsed.lockParallax;
                        if (parsed.lockAmbientFx !== undefined) root.setLockAmbientFx = parsed.lockAmbientFx;
                        if (parsed.lockClockStyle !== undefined) root.setLockClockStyle = parsed.lockClockStyle;
                        if (parsed.lockShowQuickActions !== undefined) root.setLockShowQuickActions = parsed.lockShowQuickActions;
                        if (parsed.hyprPolishAnimations !== undefined) root.setHyprPolishAnimations = parsed.hyprPolishAnimations;
                        if (parsed.hyprPolishDimInactive !== undefined) root.setHyprPolishDimInactive = parsed.hyprPolishDimInactive;
                        if (parsed.hyprPolishWsAccent !== undefined) root.setHyprPolishWsAccent = parsed.hyprPolishWsAccent;
                        if (parsed.hyprPolishWsAccentSpeed !== undefined) root.setHyprPolishWsAccentSpeed = parsed.hyprPolishWsAccentSpeed;
                        if (parsed.topBarVolumeFillMode !== undefined) root.setTopBarVolumeFillMode = parsed.topBarVolumeFillMode;
                        if (parsed.topBarShowGpu !== undefined) root.setTopBarShowGpu = parsed.topBarShowGpu;
                        if (parsed.topBarShowNet !== undefined) root.setTopBarShowNet = parsed.topBarShowNet;
                        if (parsed.topBarShowUptime !== undefined) root.setTopBarShowUptime = parsed.topBarShowUptime;
                        if (parsed.topBarShowQuickshellCpu !== undefined) root.setTopBarShowQuickshellCpu = parsed.topBarShowQuickshellCpu;
                        if (parsed.topBarBpmRingEnabled !== undefined) root.setTopBarBpmRingEnabled = parsed.topBarBpmRingEnabled;
                        if (parsed.topBarWorkspaceIconsEnabled !== undefined) root.setTopBarWorkspaceIconsEnabled = parsed.topBarWorkspaceIconsEnabled;
                        if (parsed.ecoModeEnabled !== undefined) root.setEcoModeEnabled = parsed.ecoModeEnabled;
                        if (parsed.ecoThrottleSecs !== undefined) root.setEcoThrottleSecs = parsed.ecoThrottleSecs;
                        if (parsed.ecoFreezeSecs !== undefined) root.setEcoFreezeSecs = parsed.ecoFreezeSecs;
                        if (parsed.topBarTimerEnabled !== undefined) root.setTopBarTimerEnabled = parsed.topBarTimerEnabled;
                        if (parsed.topBarTimerFillMode !== undefined) root.setTopBarTimerFillMode = parsed.topBarTimerFillMode;
                        if (parsed.residentCardsEnabled !== undefined) root.setResidentCardsEnabled = parsed.residentCardsEnabled;
                        if (parsed.residentCardPosition !== undefined) root.setResidentCardPosition = parsed.residentCardPosition;
                        if (parsed.residentCardMaxHeight !== undefined) root.setResidentCardMaxHeight = parsed.residentCardMaxHeight;
                        if (parsed.residentCardHoldMode !== undefined) root.setResidentCardHoldMode = parsed.residentCardHoldMode;
                        if (parsed.residentCardSound !== undefined) root.setResidentCardSound = parsed.residentCardSound;
                        if (parsed.residentCardSoundFile !== undefined) root.setResidentCardSoundFile = parsed.residentCardSoundFile;
                        if (parsed.screenshotAnswerOutput !== undefined) root.setScreenshotAnswerOutput = parsed.screenshotAnswerOutput;
                        if (parsed.residentNowPlayingEnabled !== undefined) root.setResidentNowPlayingEnabled = parsed.residentNowPlayingEnabled;
                        if (parsed.residentCalendarNudgeEnabled !== undefined) root.setResidentCalendarNudgeEnabled = parsed.residentCalendarNudgeEnabled;
                        if (parsed.residentBatteryHealthEnabled !== undefined) root.setResidentBatteryHealthEnabled = parsed.residentBatteryHealthEnabled;
                        if (parsed.residentUptimeGuiltEnabled !== undefined) root.setResidentUptimeGuiltEnabled = parsed.residentUptimeGuiltEnabled;
                        if (parsed.residentFocusDoneEnabled !== undefined) root.setResidentFocusDoneEnabled = parsed.residentFocusDoneEnabled;
                        if (parsed.residentAfternoonBrief !== undefined) root.setResidentAfternoonBrief = parsed.residentAfternoonBrief;
                        if (parsed.residentAfternoonBriefTime !== undefined) root.setResidentAfternoonBriefTime = parsed.residentAfternoonBriefTime;
                        if (parsed.residentNightBrief !== undefined) root.setResidentNightBrief = parsed.residentNightBrief;
                        if (parsed.residentNightBriefTime !== undefined) root.setResidentNightBriefTime = parsed.residentNightBriefTime;
                        if (parsed.residentShotAnswerPrompt !== undefined) root.setResidentShotAnswerPrompt = parsed.residentShotAnswerPrompt;
                        if (parsed.residentShotClassifyPrompt !== undefined) root.setResidentShotClassifyPrompt = parsed.residentShotClassifyPrompt;
                        if (parsed.topBarWallpaperSweepEnabled !== undefined) root.setTopBarWallpaperSweepEnabled = parsed.topBarWallpaperSweepEnabled;
                        if (parsed.topBarFlourishesEnabled !== undefined) root.setTopBarFlourishesEnabled = parsed.topBarFlourishesEnabled;
                        if (parsed.topBarFlourishUptimeEnabled !== undefined) root.setTopBarFlourishUptimeEnabled = parsed.topBarFlourishUptimeEnabled;
                        if (parsed.topBarFlourishBatteryEnabled !== undefined) root.setTopBarFlourishBatteryEnabled = parsed.topBarFlourishBatteryEnabled;
                        if (parsed.topBarFlourishCpuCalmEnabled !== undefined) root.setTopBarFlourishCpuCalmEnabled = parsed.topBarFlourishCpuCalmEnabled;
                        if (parsed.claudeDebug !== undefined) root.setClaudeDebug = parsed.claudeDebug;
                        if (parsed.discordProfiler !== undefined) root.setDiscordProfiler = parsed.discordProfiler;
                        if (parsed.residentVoiceNudges !== undefined) root.setResidentVoiceNudges = parsed.residentVoiceNudges;
                        if (parsed.residentStrictness !== undefined) root.setResidentStrictness = parsed.residentStrictness;
                        if (parsed.residentMorningBrief !== undefined) root.setResidentMorningBrief = parsed.residentMorningBrief;
                        if (parsed.residentBriefTime !== undefined) root.setResidentBriefTime = parsed.residentBriefTime;
                        if (parsed.residentCatchUp !== undefined) root.setResidentCatchUp = parsed.residentCatchUp;
                        if (parsed.residentProactiveFixes !== undefined) root.setResidentProactiveFixes = parsed.residentProactiveFixes;
                        if (parsed.residentClipboardAware !== undefined) root.setResidentClipboardAware = parsed.residentClipboardAware;
                        if (parsed.residentEcoNotice !== undefined) root.setResidentEcoNotice = parsed.residentEcoNotice;
                        if (parsed.residentDeviceAlerts !== undefined) root.setResidentDeviceAlerts = parsed.residentDeviceAlerts;
                        if (parsed.residentSongReactChance !== undefined) root.setResidentSongReactChance = parsed.residentSongReactChance;
                        if (parsed.residentPassiveExpireSecs !== undefined) root.setResidentPassiveExpireSecs = parsed.residentPassiveExpireSecs;
                        if (parsed.residentPillTakeoverEnabled !== undefined) root.setResidentPillTakeoverEnabled = parsed.residentPillTakeoverEnabled;
                        if (parsed.residentLayoutSuggestions !== undefined) root.setResidentLayoutSuggestions = parsed.residentLayoutSuggestions;
                        if (parsed.batteryAlertStyle !== undefined) root.setBatteryAlertStyle = parsed.batteryAlertStyle;
                        if (parsed.nightLightStart !== undefined) root.setNightLightStart = parsed.nightLightStart;
                        if (parsed.nightLightEnd !== undefined) root.setNightLightEnd = parsed.nightLightEnd;
                        if (parsed.nightLightTemp !== undefined) root.setNightLightTemp = parsed.nightLightTemp;
                        if (parsed.pinGridSize !== undefined) root.setPinGridSize = parsed.pinGridSize;
                        if (parsed.pinClutterCap !== undefined) root.setPinClutterCap = parsed.pinClutterCap;
                        if (parsed.pinCompactMode !== undefined) root.setPinCompactMode = parsed.pinCompactMode;
                        if (parsed.chatThinkingStyle !== undefined) root.setChatThinkingStyle = parsed.chatThinkingStyle;
                        if (parsed.cardAnimations !== undefined) root.setCardAnimations = parsed.cardAnimations;
                        if (parsed.cardDepth !== undefined) root.setCardDepth = parsed.cardDepth;
                        if (parsed.cardAccent !== undefined) root.setCardAccent = parsed.cardAccent;
                        if (parsed.agendaDefaultFilter !== undefined) root.setAgendaDefaultFilter = parsed.agendaDefaultFilter;
                        if (parsed.widgetStyles !== undefined) {
                            if (parsed.widgetStyles.monitors !== undefined) root.setStyleMonitors = parsed.widgetStyles.monitors;
                            if (parsed.widgetStyles.focustime !== undefined) root.setStyleFocustime = parsed.widgetStyles.focustime;
                            if (parsed.widgetStyles.notifications_popup !== undefined) root.setStyleNotifications = parsed.widgetStyles.notifications_popup;
                            if (parsed.widgetStyles.wallpaper !== undefined) root.setStyleWallpaper = parsed.widgetStyles.wallpaper;
                            if (parsed.widgetStyles.notifications_center !== undefined) root.setStyleNotificationsCenter = parsed.widgetStyles.notifications_center;
                            if (parsed.widgetStyles.volume !== undefined) root.setStyleVolume = parsed.widgetStyles.volume;
                            if (parsed.widgetStyles.workspaces !== undefined) root.setStyleWorkspaces = parsed.widgetStyles.workspaces;
                        }
                    } else {
                        root.saveAppSettings();
                    }
                } catch (e) {
                    console.log("Error parsing global settings:", e);
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // SYSTEM INFO PROPERTIES & FETCHER (CACHED)
    // -------------------------------------------------------------------------
    property string sysUser: "Loading..."
    property string sysHost: "Loading..."
    property string sysOS: "Loading..."
    property string sysKernel: "Loading..."
    property string sysCPU: "Loading..."
    property string sysGPU: "Loading..."
    property string faceIconPath: ""
    property string sysUptime: "Loading..."

    Process {
        id: sysInfoProc
        running: true
        command: [
            "bash", "-c",
            "CACHE=\"$HOME/.cache/qs_sysinfo.txt\"; " +
            "if [ ! -f \"$CACHE\" ]; then " +
            "  ICON=\"\"; if [ -f ~/.face.icon ]; then ICON=$(readlink -f ~/.face.icon); elif [ -f ~/.face ]; then ICON=$(readlink -f ~/.face); fi; " +
            "  echo \"$(whoami)|$(hostname)|$(uname -r)|$(cat /etc/os-release | grep '^PRETTY_NAME=' | cut -d'=' -f2 | tr -d '\\\"')|$(grep -m1 'model name' /proc/cpuinfo | cut -d':' -f2 | xargs)|$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | tail -n1 | cut -d':' -f3 | xargs)|$ICON\" > \"$CACHE\"; " +
            "fi; " +
            "cat \"$CACHE\""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let line = this.text ? this.text.trim() : "";
                let parts = line.split("|");
                if (parts.length >= 6) {
                    root.sysUser = parts[0];
                    root.sysHost = parts[1];
                    root.sysKernel = parts[2];
                    root.sysOS = parts[3];
                    root.sysCPU = parts[4];
                    root.sysGPU = parts[5] ? parts[5] : "Integrated Graphics";
                    if (parts.length >= 7 && parts[6].trim() !== "") root.faceIconPath = parts[6].trim();
                }
            }
        }
    }

    Process {
        id: envReader
        command: ["bash", "-c", "cat ~/.config/hypr/scripts/quickshell/calendar/.env 2>/dev/null || echo ''"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text ? this.text.trim().split('\n') : [];
                for (let line of lines) {
                    line = line.trim();
                    let t6 = tab6Loader.item
                    if (!t6) continue;
                    if (line.startsWith("OPENWEATHER_KEY=")) t6.x_apiKeyInput.text = line.substring(16).trim();
                    else if (line.startsWith("OPENWEATHER_CITY_ID=")) t6.x_cityIdInput.text = line.substring(20).trim();
                    else if (line.startsWith("OPENWEATHER_UNIT=")) t6.x_weatherTab.selectedUnit = line.substring(17).trim();
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // LIVE RESOURCE TELEMETRY (OPTIMIZED POLLING)
    // -------------------------------------------------------------------------
    property int cpuUsage: 0
    property int memUsage: 0
    property int sysTemp: 0
    property real globalTotalDisk: 1
    property real globalUsedDisk: 0

    Timer {
        id: resTimer
        interval: 2000
        running: root.currentTab === 2
        repeat: true
        triggeredOnStart: true
        onTriggered: { 
            resProc.running = false; 
            resProc.running = true; 
        }
    }

    Process {
        id: resProc
        command: [
            "bash", "-c", 
            "c1=($(awk '/^cpu / {print $2+$3+$4+$6+$7+$8, $5}' /proc/stat)); sleep 0.2; " +
            "c2=($(awk '/^cpu / {print $2+$3+$4+$6+$7+$8, $5}' /proc/stat)); act=$((c2[0] - c1[0])); tot=$((act + c2[1] - c1[1])); " +
            "cpu=$((tot > 0 ? act * 100 / tot : 0)); mem=$(awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {print int((t-a)/t*100)}' /proc/meminfo); " +
            "temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -n1 || echo 0); up=$(awk '{print int($1/3600)\"h \"int(($1%3600)/60)\"m\"}' /proc/uptime 2>/dev/null || echo '0h 0m'); " +
            "echo \"$cpu|$mem|$((temp / 1000))|$up\""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = this.text ? this.text.trim().split("|") : [];
                if (parts.length >= 4) {
                    root.cpuUsage = parseInt(parts[0]) || 0;
                    root.memUsage = parseInt(parts[1]) || 0;
                    root.sysTemp = parseInt(parts[2]) || 0;
                    root.sysUptime = parts[3];
                }
            }
        }
    }

    Timer {
        id: diskTimer
        interval: 60000
        running: root.currentTab === 2
        repeat: true
        triggeredOnStart: true
        onTriggered: diskProc.running = true
    }

    Process {
        id: diskProc
        command: ["bash", "-c", "df -B1 -x tmpfs -x devtmpfs -x efivarfs -x squashfs | awk 'NR>1 && !seen[$1]++ {tot+=$2; use+=$3} END {print tot\"|\"use}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = this.text ? this.text.trim().split("|") : [];
                if(p.length >= 2) {
                    root.globalTotalDisk = parseFloat(p[0]) || 0;
                    root.globalUsedDisk = parseFloat(p[1]) || 0;
                }
            }
        }
    }
    // -------------------------------------------------------------------------
    // NETWORK SPEEDTEST PIPELINE
    // -------------------------------------------------------------------------
    property int netState: 0
    property real finalPing: 0
    property real finalDown: 0
    property real finalUp: 0
    property real displayPing: 0
    property real displayDown: 0
    property real displayUp: 0

    NumberAnimation { 
        id: pingAnim
        target: root
        property: "displayPing"
        from: 0
        to: root.finalPing
        duration: 1000
        easing.type: Easing.OutQuart 
    }
    
    NumberAnimation { 
        id: downAnim
        target: root
        property: "displayDown"
        from: 0
        to: root.finalDown
        duration: 1500
        easing.type: Easing.OutQuart 
    }
    
    NumberAnimation { 
        id: upAnim
        target: root
        property: "displayUp"
        from: 0
        to: root.finalUp
        duration: 1500
        easing.type: Easing.OutQuart 
    }

    Process {
        id: pingProc
        command: ["bash", "-c", "ping -c 1 1.1.1.1 | awk -F'/' 'END{printf \"%.0f\", $5}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.finalPing = parseFloat(this.text ? this.text.trim() : "0") || 0;
                pingAnim.restart(); 
                root.netState = 2; 
                downProc.running = false; 
                downProc.running = true;
            }
        }
    }
    
    Process {
        id: downProc
        command: ["bash", "-c", "curl -m 5 -s -w '%{speed_download}' -o /dev/null https://speed.cloudflare.com/__down?bytes=50000000 | awk '{printf \"%.1f\", ($1 * 8) / 1000000}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.finalDown = parseFloat(this.text ? this.text.trim() : "0") || 0;
                downAnim.restart(); 
                root.netState = 3; 
                upProc.running = false; 
                upProc.running = true;
            }
        }
    }
    
    Process {
        id: upProc
        command: ["bash", "-c", "dd if=/dev/zero bs=1M count=10 2>/dev/null | curl -m 5 -s -w '%{speed_upload}' --data-binary @- -o /dev/null https://speed.cloudflare.com/__up | awk '{printf \"%.1f\", ($1 * 8) / 1000000}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.finalUp = parseFloat(this.text ? this.text.trim() : "0") || 0;
                upAnim.restart(); 
                root.netState = 4;
            }
        }
    }

    // -------------------------------------------------------------------------
    // STATE MANAGEMENT & DATA
    // -------------------------------------------------------------------------
    property int currentTab: 0
    property int selectedModuleIndex: 0

    // Deep-link support — passed through Main.qml's buildProps() as
    // widgetArg when opened via `qs_manager.sh open guide:<arg>`. Used by
    // the resident's "check your Wrapped" nudge to jump straight to the
    // Music Stats tab instead of landing on whatever tab was last open.
    property string widgetArg: ""
    property int musicSubTabRequest: -1
    onWidgetArgChanged: {
        if (widgetArg.indexOf("musicstats") === 0) {
            root.musicSubTabRequest = widgetArg === "musicstats-week" ? 1 : (widgetArg === "musicstats-month" ? 2 : (widgetArg === "musicstats-vibe" ? 3 : 0))
            root.markTabLoaded(10)
            root.currentTab = 10
        }
    }

    property var savedScrollY: [0, 0, 0, 0, 0, 0, 0, 0, 0]

    property var loadedTabs: ({ "0": true })
    function markTabLoaded(n) {
        if (root.loadedTabs[String(n)] === true) return
        let c = Object.assign({}, root.loadedTabs)
        c[String(n)] = true
        root.loadedTabs = c
    }
    function tabReady(n) {
        if (n === 1) root.applySettingsFilter()
        else if (n === 6) envReader.running = true
    }
    Timer { interval: 700; running: true; onTriggered: root.markTabLoaded(1) }
    onCurrentTabChanged: {
        root.markTabLoaded(currentTab)
        Quickshell.execDetached(["bash", "-c", "printf '%s' '" + currentTab + "' > /tmp/qs_guide_tab"])
    }

    Timer {
        id: scrollSaveTimer
        interval: 400
        onTriggered: Quickshell.execDetached(["bash", "-c",
            "printf '%s' '" + JSON.stringify(root.savedScrollY) + "' > /tmp/qs_guide_scroll"])
    }

    Process {
        id: tabRestorer
        running: true
        command: ["bash", "-c", "cat /tmp/qs_guide_tab 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let t = parseInt(this.text.trim())
                if (!isNaN(t) && t >= 0 && t < root.tabNames.length) root.currentTab = t
            }
        }
    }

    Process {
        id: scrollRestorer
        running: true
        command: ["bash", "-c", "cat /tmp/qs_guide_scroll 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let arr = JSON.parse(this.text.trim())
                    if (Array.isArray(arr) && arr.length >= 5) root.savedScrollY = arr
                } catch(e) {}
            }
        }
    }
    property string settingsSearchQuery: ""
    onSettingsSearchQueryChanged: root.applySettingsFilter()

    // --- Settings tab: collapsible section state + search filtering ---
    // (plain properties/JS instead of a reusable component type — guide/ is loaded
    // dynamically via Loader.source and Quickshell doesn't support the inline `component`
    // keyword for documents loaded that way, so each section below is hand-expanded.)
    property bool secGeneralExpanded: true
    property bool secAmbientExpanded: false
    property bool secMediaExpanded: false
    property bool secCalendarExpanded: false
    property bool secClaudeExpanded: false
    property bool secPinnedExpanded: false
    property bool secWidgetExpanded: false
    property bool secDisplayExpanded: false
    property bool secAccountsExpanded: false
    property bool secPillBgExpanded: false
    property bool secSmartWsExpanded: false
    property bool secResidentExpanded: false
    property bool secNudgesExpanded: false
    property bool secHyprPolishExpanded: false
    property bool secLockExpanded: false

    property bool secGeneralHasMatch: true
    property bool secAmbientHasMatch: true
    property bool secMediaHasMatch: true
    property bool secCalendarHasMatch: true
    property bool secClaudeHasMatch: true
    property bool secPinnedHasMatch: true
    property bool secWidgetHasMatch: true
    property bool secDisplayHasMatch: true
    property bool secAccountsHasMatch: true
    property bool secPillBgHasMatch: true
    property bool secSmartWsHasMatch: true
    property bool secResidentHasMatch: true
    property bool secNudgesHasMatch: true
    property bool secHyprPolishHasMatch: true
    property bool secLockHasMatch: true

    function normalizeSearch(str) { return (str || "").toString().toLowerCase(); }

    function nodeTextMatches(item, q) {
        if (!item) return false;
        try {
            if (item.text !== undefined && typeof item.text === "string" && root.normalizeSearch(item.text).indexOf(q) >= 0) return true;
        } catch (e) {}
        if (item.children) {
            for (let i = 0; i < item.children.length; i++) {
                if (root.nodeTextMatches(item.children[i], q)) return true;
            }
        }
        return false;
    }

    // Hides non-matching cards in one section's content column, reports whether the
    // section has any visible content, and auto-expands the section if the query matched.
    function applySectionFilter(contentColumn, expandedProp, hasMatchProp) {
        let q = root.normalizeSearch(root.settingsSearchQuery);
        let any = false;
        for (let i = 0; i < contentColumn.children.length; i++) {
            let child = contentColumn.children[i];
            if (q === "") {
                child.visible = true;
                any = true;
                continue;
            }
            let m = root.nodeTextMatches(child, q);
            child.visible = m;
            if (m) any = true;
        }
        root[hasMatchProp] = any;
        if (q !== "" && any) root[expandedProp] = true;
    }

    function applySettingsFilter() {
        let t1 = tab1Loader.item
        if (!t1) return
        root.applySectionFilter(t1.x_secGeneralContent, "secGeneralExpanded", "secGeneralHasMatch");
        root.applySectionFilter(t1.x_secAmbientContent, "secAmbientExpanded", "secAmbientHasMatch");
        root.applySectionFilter(t1.x_secMediaContent, "secMediaExpanded", "secMediaHasMatch");
        root.applySectionFilter(t1.x_secPillBgContent, "secPillBgExpanded", "secPillBgHasMatch");
        root.applySectionFilter(t1.x_secSmartWsContent, "secSmartWsExpanded", "secSmartWsHasMatch");
        root.applySectionFilter(t1.x_secResidentContent, "secResidentExpanded", "secResidentHasMatch");
        root.applySectionFilter(t1.x_secNudgesContent, "secNudgesExpanded", "secNudgesHasMatch");
        root.applySectionFilter(t1.x_secHyprPolishContent, "secHyprPolishExpanded", "secHyprPolishHasMatch");
        root.applySectionFilter(t1.x_secLockContent, "secLockExpanded", "secLockHasMatch");
        root.applySectionFilter(t1.x_secCalendarContent, "secCalendarExpanded", "secCalendarHasMatch");
        root.applySectionFilter(t1.x_secClaudeContent, "secClaudeExpanded", "secClaudeHasMatch");
        root.applySectionFilter(t1.x_secPinnedContent, "secPinnedExpanded", "secPinnedHasMatch");
        root.applySectionFilter(t1.x_secWidgetContent, "secWidgetExpanded", "secWidgetHasMatch");
        root.applySectionFilter(t1.x_secDisplayContent, "secDisplayExpanded", "secDisplayHasMatch");
        root.applySectionFilter(t1.x_secAccountsContent, "secAccountsExpanded", "secAccountsHasMatch");
    }

    property var tabNames: ["System", "Settings", "Resources", "Modules", "Keybinds", "Matugen", "Weather", "Startup", "Mailbox", "Resident", "Music Stats"]
    property var tabIcons: ["", "", "󰣖", "󰣆", "󰌌", "󰏘", "󰖐", "", "", "󰚩", "♫"]

    property real introBase: 0.0
    property real introSidebar: 0.0
    property real introContent: 0.0

    ListModel { id: dynamicKeybindsModel }
    ListModel {
        id: modulesDataModel
        ListElement { title: "Calendar & Weather"; target: "calendar"; icon: ""; desc: "Dual-sync calendar with live \nOpenWeatherMap integration."; preview: "previews/preview_calendar.png" }
        ListElement { title: "Media & Lyrics"; target: "music"; icon: "󰎆"; desc: "PlayerCtl integration, Cava \nvisualizer, and live lyrics."; preview: "previews/preview_music.png" }
        ListElement { title: "Battery & Power"; target: "battery"; icon: "󰁹"; desc: "Uptime tracking, power profiles, \nand battery health metrics."; preview: "previews/preview_battery.png" }
        ListElement { title: "Network Hub"; target: "network"; icon: "󰤨"; desc: "Wi-Fi and Bluetooth connection \nmanagement via nmcli/bluez."; preview: "previews/preview_network.png" }
        ListElement { title: "FocusTime"; target: "focustime"; icon: "󰄉"; desc: "Built-in Pomodoro timer daemon \nwith session tracking."; preview: "previews/preview_focustime.png" }
        ListElement { title: "Volume Mixer"; target: "volume"; icon: "󰕾"; desc: "Pipewire integration for I/O \nvolume and stream routing."; preview: "previews/preview_volume.png" }
        ListElement { title: "Wallpaper Picker"; target: "wallpaper"; icon: ""; desc: "Live awww backend rendering \nwith Matugen color generation."; preview: "previews/preview_wallpaper.png" }
        ListElement { title: "Monitors"; target: "monitors"; icon: "󰍹"; desc: "Quick display management."; preview: "previews/preview_monitors.png" }
        ListElement { title: "Stewart AI"; target: "stewart"; icon: "󰚩"; desc: "Voice assistant integration.\n(Reserved for future, currently disabled)"; preview: "previews/preview_stewart.png" }
    }

    Process {
        id: keybindsParser
        command: ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/parse_keybinds.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let binds = JSON.parse(this.text.trim())
                    dynamicKeybindsModel.clear()
                    for (let item of binds) dynamicKeybindsModel.append(item)
                } catch(e) { console.log("keybinds parse error:", e) }
            }
        }
    }

    function buildKeybinds() {
        keybindsParser.running = true
    }

    Component.onCompleted: {
        startupSequence.start();
        buildKeybinds();
        _accentReady = true;
        root.applySettingsFilter();
    }

    ParallelAnimation {
        id: startupSequence
        NumberAnimation { 
            target: root
            property: "introBase"
            from: 0.0
            to: 1.0
            duration: 900
            easing.type: Easing.OutExpo 
        }
        SequentialAnimation { 
            PauseAnimation { duration: 150 }
            NumberAnimation { 
                target: root
                property: "introSidebar"
                from: 0.0
                to: 1.0
                duration: 1000
                easing.type: Easing.OutBack
                easing.overshoot: 1.05 
            } 
        }
        SequentialAnimation { 
            PauseAnimation { duration: 250 }
            NumberAnimation { 
                target: root
                property: "introContent"
                from: 0.0
                to: 1.0
                duration: 1100
                easing.type: Easing.OutBack
                easing.overshoot: 1.02 
            } 
        }
    }

    SequentialAnimation {
        id: closeSequence
        ParallelAnimation { 
            NumberAnimation { 
                target: root
                property: "introContent"
                to: 0.0
                duration: 150
                easing.type: Easing.InExpo 
            }
            NumberAnimation { 
                target: root
                property: "introSidebar"
                to: 0.0
                duration: 150
                easing.type: Easing.InExpo 
            } 
        }
        NumberAnimation { 
            target: root
            property: "introBase"
            to: 0.0
            duration: 200
            easing.type: Easing.InQuart 
        }
        ScriptAction { 
            script: Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]) 
        }
    }

    // -------------------------------------------------------------------------
    // BACKGROUND AMBIENCE
    // -------------------------------------------------------------------------
    Item {
        anchors.fill: parent
        opacity: introBase
        scale: 0.95 + (0.05 * introBase)
        
        Rectangle {
            anchors.fill: parent
            radius: root.s(16)
            color: root.base
            border.color: root.surface0
            border.width: 1
            clip: true
            
            property real time: 0
            NumberAnimation on time { 
                from: 0
                to: Math.PI * 2
                duration: 20000
                loops: Animation.Infinite
                running: true 
            }
            
            Rectangle {
                width: root.s(600)
                height: root.s(600)
                radius: root.s(300)
                x: parent.width * 0.6 + Math.cos(parent.time) * root.s(100)
                y: parent.height * 0.1 + Math.sin(parent.time * 1.5) * root.s(100)
                color: root.ambientPurple
                opacity: 0.04
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blurMax: 80; blur: 1.0 }
            }
            
            Rectangle {
                width: root.s(700)
                height: root.s(700)
                radius: root.s(350)
                x: parent.width * 0.1 + Math.sin(parent.time * 0.8) * root.s(150)
                y: parent.height * 0.4 + Math.cos(parent.time * 1.2) * root.s(100)
                color: root.ambientBlue
                opacity: 0.03
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blurMax: 90; blur: 1.0 }
            }
        }
    }

    // -------------------------------------------------------------------------
    // MAIN LAYOUT
    // -------------------------------------------------------------------------
    RowLayout {
        anchors.fill: parent
        anchors.margins: root.s(20)
        spacing: root.s(20)

        // ==========================================
        // SIDEBAR
        // ==========================================
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: root.s(220)
            radius: root.s(12)
            color: Qt.alpha(root.surface0, 0.4)
            border.color: root.surface1
            border.width: 1
            opacity: introSidebar
            transform: Translate { x: root.s(-30) * (1.0 - introSidebar) }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.s(15)
                spacing: root.s(10)
                
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(60)
                    
                    RowLayout {
                        anchors.fill: parent
                        spacing: root.s(12)
                        
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: root.s(36)
                            height: root.s(36)
                            radius: root.s(10)
                            color: root.ambientPurple
                            Text { 
                                anchors.centerIn: parent
                                text: "󰣇"
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: root.s(20)
                                color: root.base 
                            }
                        }
                        
                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: root.s(2)
                            Text { 
                                text: "Imperative"
                                font.family: "JetBrains Mono"
                                font.weight: Font.Black
                                font.pixelSize: root.s(15)
                                color: root.text
                                Layout.alignment: Qt.AlignLeft 
                            }
                            Text { 
                                text: "v1.0.25"
                                font.family: "JetBrains Mono"
                                font.pixelSize: root.s(11)
                                color: root.subtext0
                                Layout.alignment: Qt.AlignLeft 
                            }
                        }
                    }
                }

                Rectangle { 
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.alpha(root.surface1, 0.5)
                    Layout.bottomMargin: root.s(10) 
                }

                Repeater {
                    model: root.tabNames.length
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(44)
                        radius: root.s(8)
                        property bool isActive: root.currentTab === index
                        color: isActive ? root.surface1 : (tabMa.containsMouse ? Qt.alpha(root.surface1, 0.5) : "transparent")
                        
                        Behavior on color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: root.s(15)
                            spacing: root.s(12)
                            
                            Item {
                                Layout.preferredWidth: root.s(24)
                                Layout.alignment: Qt.AlignVCenter
                                Text { 
                                    anchors.centerIn: parent
                                    text: root.tabIcons[index]
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: root.s(18)
                                    color: parent.parent.parent.isActive ? root.ambientPurple : root.subtext0
                                    Behavior on color { ColorAnimation { duration: 150 } } 
                                }
                            }
                            
                            Text { 
                                text: root.tabNames[index]
                                font.family: "JetBrains Mono"
                                font.weight: parent.parent.isActive ? Font.Bold : Font.Medium
                                font.pixelSize: root.s(13)
                                color: parent.parent.isActive ? root.text : root.subtext0
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                Behavior on color { ColorAnimation { duration: 150 } } 
                            }
                        }
                        
                        Rectangle { 
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.s(3)
                            height: parent.isActive ? root.s(20) : 0
                            radius: root.s(2)
                            color: root.ambientPurple
                            Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutBack } } 
                        }
                        
                        MouseArea { 
                            id: tabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentTab = index 
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(44)
                    radius: root.s(8)
                    color: closeHover.containsMouse ? Qt.alpha(root.red, 0.1) : "transparent"
                    border.color: closeHover.containsMouse ? root.red : root.surface1
                    border.width: 1
                    scale: closeHover.pressed ? 0.95 : (closeHover.containsMouse ? 1.02 : 1.0)
                    
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Item {
                        anchors.centerIn: parent
                        width: arrowText.implicitWidth
                        height: arrowText.implicitHeight
                        Text { 
                            id: arrowText
                            text: ""
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: root.s(16)
                            color: closeHover.containsMouse ? root.red : root.subtext0
                            Behavior on color { ColorAnimation { duration: 150 } } 
                        }
                    }
                    MouseArea { 
                        id: closeHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: closeSequence.start() 
                    }
                }
            }
        }

        // ==========================================
        // CONTENT AREA
        // ==========================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            opacity: introContent
            scale: 0.95 + (0.05 * introContent)
            transform: Translate { y: root.s(20) * (1.0 - introContent) }

            // ------------------------------------------
            // TAB 0: SYSTEM OVERVIEW
            // ------------------------------------------
            Loader {
                id: tab0Loader
                anchors.fill: parent
                active: root.loadedTabs["0"] === true
                asynchronous: true
                onLoaded: root.tabReady(0)
                sourceComponent: Component {
            Item {
                anchors.fill: parent
                visible: root.currentTab === 0
                opacity: visible ? 1.0 : 0.0
                property real slideY: visible ? 0 : root.s(10)
                
                Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                transform: Translate { y: slideY }
                Behavior on opacity { NumberAnimation { duration: 250 } }

                ListModel {
                    id: systemDataModel
                    ListElement { pkg: "Hyprland"; role: "Wayland Compositor"; icon: ""; clr: "blue"; link: "https://hyprland.org/" }
                    ListElement { pkg: "Quickshell"; role: "UI Framework"; icon: "󰣆"; clr: "mauve"; link: "https://git.outfoxxed.me/outfoxxed/quickshell" }
                    ListElement { pkg: "Matugen"; role: "Theme Engine"; icon: "󰏘"; clr: "peach"; link: "https://github.com/InioX/matugen" }
                    ListElement { pkg: "Rofi Wayland"; role: "App Launcher"; icon: ""; clr: "green"; link: "https://github.com/lbonn/rofi" }
                    ListElement { pkg: "Kitty"; role: "Terminal Emulator"; icon: "󰄛"; clr: "yellow"; link: "https://sw.kovidgoyal.net/kitty/" }
                    ListElement { pkg: "SwayOSD / NC"; role: "Overlays & Notifs"; icon: "󰂚"; clr: "pink"; link: "https://github.com/ErikReider/SwayOSD" }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(20)
                    spacing: root.s(20)

                    // ENHANCED DEVICE INFO BLOCK
                    Rectangle {
                        id: sysBox
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(180)
                        radius: root.s(16)
                        color: sysBoxMa.containsMouse ? Qt.alpha(root.surface0, 0.7) : Qt.alpha(root.surface0, 0.4)
                        border.color: sysBoxMa.containsMouse ? root.ambientBlue : root.surface1
                        border.width: 1
                        clip: true
                        
                        Behavior on color { ColorAnimation { duration: 300 } }
                        Behavior on border.color { ColorAnimation { duration: 300 } }

                        Rectangle {
                            width: root.s(250)
                            height: root.s(250)
                            radius: root.s(125)
                            color: root.ambientBlue
                            opacity: 0.15
                            x: sysBoxMa.containsMouse ? parent.width * 0.7 : parent.width * 0.8
                            y: -root.s(50)
                            layer.enabled: true
                            layer.effect: MultiEffect { blurEnabled: true; blurMax: 80; blur: 1.0 }
                            Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutExpo } }
                        }
                        
                        Rectangle {
                            width: root.s(200)
                            height: root.s(200)
                            radius: root.s(100)
                            color: root.ambientPurple
                            opacity: 0.15
                            x: sysBoxMa.containsMouse ? root.s(50) : -root.s(50)
                            y: root.s(20)
                            layer.enabled: true
                            layer.effect: MultiEffect { blurEnabled: true; blurMax: 80; blur: 1.0 }
                            Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutExpo } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(20)
                            spacing: root.s(30)

                            Item {
                                Layout.preferredWidth: root.s(100)
                                Layout.preferredHeight: root.s(100)
                                
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: root.s(100)
                                    height: root.s(100)
                                    radius: root.s(50)
                                    color: "transparent"
                                    border.color: Qt.alpha(root.ambientPurple, sysBoxMa.containsMouse ? 0.8 : 0.3)
                                    border.width: root.s(3)
                                    scale: sysBoxMa.containsMouse ? 1.05 : 1.0
                                    
                                    Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack } }
                                    Behavior on border.color { ColorAnimation { duration: 300 } }
                                    
                                    RotationAnimation on rotation { 
                                        from: 0
                                        to: 360
                                        duration: 15000
                                        loops: Animation.Infinite
                                        running: true 
                                    }
                                }
                                
                                Item {
                                    anchors.centerIn: parent
                                    width: root.s(84)
                                    height: root.s(84)
                                    
                                    Rectangle { 
                                        id: avatarMaskTab0
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: "black"
                                        visible: false
                                        layer.enabled: true 
                                    }
                                    
                                    Image {
                                        id: userAvatarImg
                                        anchors.fill: parent
                                        source: root.faceIconPath !== "" ? "file://" + root.faceIconPath.replace("file://", "") : ""
                                        fillMode: Image.PreserveAspectCrop
                                        visible: false
                                        asynchronous: true
                                        smooth: true
                                        mipmap: true
                                    }
                                    
                                    MultiEffect { 
                                        source: userAvatarImg
                                        anchors.fill: userAvatarImg
                                        maskEnabled: true
                                        maskSource: avatarMaskTab0
                                        visible: root.faceIconPath !== "" 
                                    }
                                    
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: root.faceIconPath === "" ? root.surface0 : "transparent"
                                        border.color: root.surface2
                                        border.width: 1
                                        Text { 
                                            anchors.centerIn: parent
                                            text: ""
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: root.s(42)
                                            color: root.text
                                            visible: root.faceIconPath === ""
                                            scale: sysBoxMa.containsMouse ? 1.1 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(8)
                                
                                Text { 
                                    text: root.sysUser
                                    font.family: "JetBrains Mono"
                                    font.weight: Font.Black
                                    font.pixelSize: root.s(24)
                                    color: root.text 
                                }
                                
                                Text { 
                                    text: "@" + root.sysHost
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: root.s(14)
                                    color: root.subtext0 
                                }
                                
                                Rectangle { 
                                    Layout.fillWidth: true
                                    height: 1
                                    color: Qt.alpha(root.surface1, 0.5)
                                    Layout.topMargin: root.s(5)
                                    Layout.bottomMargin: root.s(5) 
                                }

                                RowLayout {
                                    spacing: root.s(15)
                                    RowLayout { 
                                        spacing: root.s(6)
                                        Text { text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(16); color: root.blue } 
                                        Text { text: root.sysOS; font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: root.s(12); color: root.subtext0 } 
                                    }
                                    RowLayout { 
                                        spacing: root.s(6)
                                        Text { text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(16); color: root.peach } 
                                        Text { text: root.sysKernel; font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: root.s(12); color: root.subtext0 } 
                                    }
                                }
                                
                                RowLayout {
                                    spacing: root.s(15)
                                    RowLayout { 
                                        spacing: root.s(6)
                                        Text { text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(16); color: root.green } 
                                        Text { 
                                            text: root.sysCPU
                                            font.family: "JetBrains Mono"
                                            font.weight: Font.Medium
                                            font.pixelSize: root.s(12)
                                            color: root.subtext0
                                            elide: Text.ElideRight
                                            Layout.maximumWidth: root.s(220) 
                                        } 
                                    }
                                    RowLayout { 
                                        spacing: root.s(6)
                                        Text { text: "󰢮"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(16); color: root.yellow } 
                                        Text { 
                                            text: root.sysGPU
                                            font.family: "JetBrains Mono"
                                            font.weight: Font.Medium
                                            font.pixelSize: root.s(12)
                                            color: root.subtext0
                                            elide: Text.ElideRight
                                            Layout.maximumWidth: root.s(220) 
                                        } 
                                    }
                                }
                            }
                        }
                        MouseArea { id: sysBoxMa; anchors.fill: parent; hoverEnabled: true }
                    }

                    // AUTHOR BLOCK
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(50)
                        radius: root.s(10)
                        color: authorMa.containsMouse ? Qt.alpha(root.surface1, 0.6) : Qt.alpha(root.surface0, 0.4)
                        border.color: authorMa.containsMouse ? root.mauve : root.surface1
                        border.width: 1
                        scale: authorMa.pressed ? 0.98 : (authorMa.containsMouse ? 1.01 : 1.0)
                        
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Behavior on border.color { ColorAnimation { duration: 200 } }

                        RowLayout {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: root.s(12)
                            spacing: root.s(15)
                            
                            Rectangle { 
                                Layout.alignment: Qt.AlignVCenter
                                width: root.s(32)
                                height: root.s(32)
                                radius: root.s(8)
                                color: root.surface0
                                border.color: root.surface2
                                border.width: 1
                                Text { anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.text } 
                            }
                            
                            Row {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(1)
                                Repeater {
                                    model: [ { l: "i", c: root.red }, { l: "l", c: root.peach }, { l: "y", c: root.yellow }, { l: "a", c: root.green }, { l: "m", c: root.sapphire }, { l: "i", c: root.blue }, { l: "r", c: root.mauve }, { l: "o", c: root.pink } ]
                                    Text { 
                                        text: modelData.l
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Black
                                        font.pixelSize: root.s(14)
                                        color: modelData.c
                                        property real hoverOffset: authorMa.containsMouse ? root.s(-3) : 0
                                        transform: Translate { y: hoverOffset }
                                        Behavior on hoverOffset { NumberAnimation { duration: 300 + (index * 35); easing.type: Easing.OutBack } } 
                                    }
                                }
                            }
                            
                            Item { Layout.fillWidth: true }
                            
                            Rectangle { 
                                Layout.alignment: Qt.AlignVCenter
                                width: root.s(28)
                                height: root.s(28)
                                radius: root.s(6)
                                color: authorMa.containsMouse ? root.surface1 : "transparent"
                                Text { 
                                    anchors.centerIn: parent
                                    text: ""
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: root.s(14)
                                    color: authorMa.containsMouse ? root.mauve : root.subtext0
                                    Behavior on color { ColorAnimation { duration: 150 } } 
                                } 
                            }
                        }
                        MouseArea { 
                            id: authorMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["xdg-open", "https://github.com/ilyamiro/nixos-configuration"]) 
                        }
                    }

                    // MODULES AND QUICK LINKS ROW
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.s(15)
                        
                        Repeater {
                            model: [ 
                                { name: "Settings", icon: "", color: "mauve", targetTab: 1 }, 
                                { name: "Resources", icon: "󰣖", color: "green", targetTab: 2 }, 
                                { name: "Modules", icon: "󰣆", color: "blue", targetTab: 3 } 
                            ]
                            
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(44)
                                radius: root.s(8)
                                color: navBtnMa.containsMouse ? Qt.alpha(root[modelData.color], 0.15) : Qt.alpha(root.surface0, 0.4)
                                border.color: navBtnMa.containsMouse ? root[modelData.color] : root.surface1
                                border.width: 1
                                scale: navBtnMa.pressed ? 0.95 : 1.0
                                
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuart } }
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Behavior on border.color { ColorAnimation { duration: 200 } }
                                
                                RowLayout { 
                                    anchors.centerIn: parent
                                    spacing: root.s(10)
                                    Text { text: modelData.icon; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(16); color: root[modelData.color] } 
                                    Text { text: modelData.name; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text } 
                                }
                                
                                MouseArea { 
                                    id: navBtnMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.currentTab = modelData.targetTab 
                                }
                            }
                        }
                    }

                    Text { 
                        text: "System Architecture"
                        font.family: "JetBrains Mono"
                        font.weight: Font.Black
                        font.pixelSize: root.s(24)
                        color: root.text
                        Layout.alignment: Qt.AlignVCenter
                        Layout.topMargin: root.s(5) 
                    }
                    
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: root.s(15)
                        columnSpacing: root.s(15)
                        
                        Repeater {
                            model: systemDataModel
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(60)
                                radius: root.s(10)
                                color: sysCardMa.containsMouse ? Qt.alpha(root[model.clr], 0.1) : Qt.alpha(root.surface0, 0.4)
                                border.color: sysCardMa.containsMouse ? root[model.clr] : root.surface1
                                border.width: 1
                                scale: sysCardMa.pressed ? 0.98 : 1.0
                                
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuart } }
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Behavior on border.color { ColorAnimation { duration: 200 } }
                                
                                Item {
                                    anchors.fill: parent
                                    anchors.margins: root.s(10)
                                    
                                    Item { 
                                        id: sysIconBox
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: root.s(36)
                                        height: root.s(36)
                                        Text { anchors.centerIn: parent; text: model.icon; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(22); color: root[model.clr] } 
                                    }
                                    
                                    Column { 
                                        anchors.left: sysIconBox.right
                                        anchors.leftMargin: root.s(15)
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: root.s(2)
                                        Text { text: model.pkg; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.text } 
                                        Text { text: model.role; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 } 
                                    }
                                }
                                
                                MouseArea { 
                                    id: sysCardMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.execDetached(["xdg-open", model.link]) 
                                }
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
            }
        }

            // ------------------------------------------
            // TAB 1: SETTINGS (SSOT Implementation)
            // ------------------------------------------
            Loader {
                id: tab1Loader
                anchors.fill: parent
                active: root.loadedTabs["1"] === true
                asynchronous: true
                onLoaded: root.tabReady(1)
                sourceComponent: Component {
            Item {
                readonly property var x_secGeneralContent: secGeneralContent
                readonly property var x_secAmbientContent: secAmbientContent
                readonly property var x_secMediaContent: secMediaContent
                readonly property var x_secPillBgContent: secPillBgContent
                readonly property var x_secSmartWsContent: secSmartWsContent
                readonly property var x_secResidentContent: secResidentContent
                readonly property var x_secNudgesContent: secNudgesContent
                readonly property var x_secHyprPolishContent: secHyprPolishContent
                readonly property var x_secLockContent: secLockContent
                readonly property var x_secCalendarContent: secCalendarContent
                readonly property var x_secClaudeContent: secClaudeContent
                readonly property var x_secPinnedContent: secPinnedContent
                readonly property var x_secWidgetContent: secWidgetContent
                readonly property var x_secDisplayContent: secDisplayContent
                readonly property var x_secAccountsContent: secAccountsContent
                anchors.fill: parent
                visible: root.currentTab === 1
                opacity: visible ? 1.0 : 0.0
                property real slideY: visible ? 0 : root.s(10)
                
                Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                transform: Translate { y: slideY }
                Behavior on opacity { NumberAnimation { duration: 250 } }

                ListModel {
                    id: langModel
                    ListElement { code: "us"; name: "English (US)" }
                    ListElement { code: "gb"; name: "English (UK)" }
                    ListElement { code: "au"; name: "English (Australia)" }
                    ListElement { code: "ca"; name: "English/French (Canada)" }
                    ListElement { code: "ie"; name: "English (Ireland)" }
                    ListElement { code: "nz"; name: "English (New Zealand)" }
                    ListElement { code: "za"; name: "English (South Africa)" }
                    ListElement { code: "fr"; name: "French" }
                    ListElement { code: "be"; name: "Belgian" }
                    ListElement { code: "ch"; name: "Swiss" }
                    ListElement { code: "de"; name: "German" }
                    ListElement { code: "at"; name: "Austrian" }
                    ListElement { code: "nl"; name: "Dutch" }
                    ListElement { code: "lu"; name: "Luxembourgish" }
                    ListElement { code: "es"; name: "Spanish" }
                    ListElement { code: "pt"; name: "Portuguese" }
                    ListElement { code: "br"; name: "Portuguese (Brazil)" }
                    ListElement { code: "it"; name: "Italian" }
                    ListElement { code: "gr"; name: "Greek" }
                    ListElement { code: "mt"; name: "Maltese" }
                    ListElement { code: "se"; name: "Swedish" }
                    ListElement { code: "no"; name: "Norwegian" }
                    ListElement { code: "dk"; name: "Danish" }
                    ListElement { code: "fi"; name: "Finnish" }
                    ListElement { code: "is"; name: "Icelandic" }
                    ListElement { code: "pl"; name: "Polish" }
                    ListElement { code: "cz"; name: "Czech" }
                    ListElement { code: "sk"; name: "Slovak" }
                    ListElement { code: "hu"; name: "Hungarian" }
                    ListElement { code: "ro"; name: "Romanian" }
                    ListElement { code: "bg"; name: "Bulgarian" }
                    ListElement { code: "ru"; name: "Russian" }
                    ListElement { code: "ua"; name: "Ukrainian" }
                    ListElement { code: "by"; name: "Belarusian" }
                    ListElement { code: "rs"; name: "Serbian" }
                    ListElement { code: "hr"; name: "Croatian" }
                    ListElement { code: "si"; name: "Slovenian" }
                    ListElement { code: "mk"; name: "Macedonian" }
                    ListElement { code: "ba"; name: "Bosnian" }
                    ListElement { code: "me"; name: "Montenegrin" }
                    ListElement { code: "lt"; name: "Lithuanian" }
                    ListElement { code: "lv"; name: "Latvian" }
                    ListElement { code: "ee"; name: "Estonian" }
                    ListElement { code: "am"; name: "Armenian" }
                    ListElement { code: "ge"; name: "Georgian" }
                    ListElement { code: "kz"; name: "Kazakh" }
                    ListElement { code: "kg"; name: "Kyrgyz" }
                    ListElement { code: "tj"; name: "Tajik" }
                    ListElement { code: "tm"; name: "Turkmen" }
                    ListElement { code: "uz"; name: "Uzbek" }
                    ListElement { code: "mn"; name: "Mongolian" }
                    ListElement { code: "il"; name: "Hebrew" }
                    ListElement { code: "ara"; name: "Arabic" }
                    ListElement { code: "ir"; name: "Persian (Farsi)" }
                    ListElement { code: "iq"; name: "Iraqi" }
                    ListElement { code: "sy"; name: "Syrian" }
                    ListElement { code: "in"; name: "Indian" }
                    ListElement { code: "pk"; name: "Pakistani" }
                    ListElement { code: "bd"; name: "Bangla" }
                    ListElement { code: "th"; name: "Thai" }
                    ListElement { code: "vn"; name: "Vietnamese" }
                    ListElement { code: "la"; name: "Lao" }
                    ListElement { code: "mm"; name: "Burmese" }
                    ListElement { code: "kh"; name: "Khmer" }
                    ListElement { code: "cn"; name: "Chinese" }
                    ListElement { code: "jp"; name: "Japanese" }
                    ListElement { code: "kr"; name: "Korean" }
                    ListElement { code: "tw"; name: "Taiwanese" }
                    ListElement { code: "ng"; name: "Nigerian" }
                    ListElement { code: "ma"; name: "Moroccan" }
                    ListElement { code: "dz"; name: "Algerian" }
                    ListElement { code: "et"; name: "Ethiopian" }
                    ListElement { code: "latam"; name: "Spanish (Latin America)" }
                    ListElement { code: "al"; name: "Albanian" }
                    ListElement { code: "fo"; name: "Faroese" }
                }

                ListModel { id: pathSuggestModel }
                ListModel { id: langSearchModel }

                function updateLangSearch(query) {
                    langSearchModel.clear();
                    let q = query.trim().toLowerCase();
                    if (q === "") return;
                    for (let i = 0; i < langModel.count; i++) {
                        let item = langModel.get(i);
                        if (item.code.toLowerCase().includes(q) || item.name.toLowerCase().includes(q)) {
                            langSearchModel.append({ code: item.code, name: item.name });
                        }
                    }
                }

                Process {
                    id: pathSuggestProc
                    property string query: ""
                    command: ["bash", "-c", "eval ls -dp " + query + "* 2>/dev/null | grep '/$' | head -n 5 || true"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            pathSuggestModel.clear();
                            if (this.text) {
                                let lines = this.text.trim().split('\n');
                                for (let i = 0; i < lines.length; i++) {
                                    if (lines[i].length > 0) {
                                        pathSuggestModel.append({ path: lines[i] });
                                    }
                                }
                            }
                        }
                    }
                }

                Flickable {
                    id: settingsFlick
                    anchors.fill: parent
                    anchors.margins: root.s(20)
                    contentWidth: width
                    contentHeight: settingsCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    onContentYChanged: { root.savedScrollY[1] = contentY; scrollSaveTimer.restart() }
                    Component.onCompleted: scrollRestoreTimer1.start()
                    Timer { id: scrollRestoreTimer1; interval: 120; onTriggered: settingsFlick.contentY = root.savedScrollY[1] || 0 }

                ColumnLayout {
                    id: settingsCol
                    width: parent.width
                    spacing: root.s(15)

                    property real iconColWidth: root.s(32)
                    property real controlColWidth: root.s(240)

                    // --- HEADER & APPLY BUTTON ---
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Settings"
                            font.family: "JetBrains Mono"
                            font.weight: Font.Black
                            font.pixelSize: root.s(28)
                            color: root.text
                            Layout.alignment: Qt.AlignVCenter 
                        }
                        
                        Item { Layout.fillWidth: true } 

                        Rectangle {
                            Layout.preferredWidth: root.s(110)
                            Layout.preferredHeight: root.s(44)
                            radius: root.s(22)
                            color: mainSaveMa.containsMouse ? Qt.alpha(root.green, 0.9) : Qt.alpha(root.green, 0.7)
                            border.color: root.green
                            border.width: 1
                            scale: mainSaveMa.pressed ? 0.95 : (mainSaveMa.containsMouse ? 1.05 : 1.0)
                            
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: root.s(8)
                                Text { text: "󰆓"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.base }
                                Text { text: "APPLY"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(14); color: root.base }
                            }
                            
                            MouseArea { 
                                id: mainSaveMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.saveAppSettings() 
                            }
                        }
                    }

                    // --- SEARCH ---
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(40)
                        radius: root.s(8)
                        color: root.surface0
                        border.color: settingsSearchInput.activeFocus ? root.mauve : root.surface1
                        border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: root.s(14)
                            anchors.rightMargin: root.s(10)
                            spacing: root.s(10)

                            Text { text: "󰍉"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }

                            TextInput {
                                id: settingsSearchInput
                                Layout.fillWidth: true
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: "JetBrains Mono"
                                font.pixelSize: root.s(12)
                                color: root.text
                                clip: true
                                selectByMouse: true
                                text: root.settingsSearchQuery
                                onTextChanged: root.settingsSearchQuery = text
                                Text { text: "Search settings..."; color: root.subtext0; visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter }
                            }

                            Text {
                                visible: settingsSearchInput.text.length > 0
                                text: "✖"
                                font.family: "JetBrains Mono"
                                font.pixelSize: root.s(12)
                                color: clearSearchMa.containsMouse ? root.red : root.subtext0
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Layout.alignment: Qt.AlignVCenter
                                MouseArea { id: clearSearchMa; anchors.fill: parent; anchors.margins: root.s(-6); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: settingsSearchInput.text = "" }
                            }
                        }
                    }

                    // --- SETTINGS LIST (STRICTLY ALIGNED) ---

                    // --- section: general & system ---
                    Item {
                        id: secGeneral
                        Layout.fillWidth: true
                        implicitHeight: secGeneralHeader.height + secGeneralBody.height
                        visible: root.secGeneralHasMatch

                        ColumnLayout {
                            width: parent.width
                            spacing: 0

                            Item {
                                id: secGeneralHeader
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(30)

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: root.s(10)

                                    Text {
                                        text: "▸"
                                        rotation: root.secGeneralExpanded ? 90 : 0
                                        font.pixelSize: root.s(11)
                                        color: root.subtext0
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                                    }
                                    Text { text: "󰒓"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: root.mauve; Layout.alignment: Qt.AlignVCenter }
                                    Text { text: "GENERAL & SYSTEM"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.surface1; Layout.alignment: Qt.AlignVCenter }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.secGeneralExpanded = !root.secGeneralExpanded
                                }
                            }

                            Item {
                                id: secGeneralBody
                                Layout.fillWidth: true
                                clip: true
                                Layout.preferredHeight: root.secGeneralExpanded ? (secGeneralContent.implicitHeight + root.s(15)) : 0
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

                                ColumnLayout {
                                    id: secGeneralContent
                                    y: root.s(15)
                                    width: parent.width
                                    spacing: root.s(15)

                    // Setting 1: Open Guide
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)
                            
                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.peach }
                            }
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Open Guide at Startup"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Automatically launch this configuration guide when logging in."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            
                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true
                                
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46)
                                    height: root.s(26)
                                    radius: root.s(13)
                                    color: root.setOpenGuideAtStartup ? root.peach : root.surface2
                                    
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    
                                    Rectangle {
                                        width: root.s(20)
                                        height: root.s(20)
                                        radius: root.s(10)
                                        color: root.base
                                        y: root.s(3)
                                        x: root.setOpenGuideAtStartup ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    
                                    MouseArea { 
                                        anchors.fill: parent
                                        onClicked: root.setOpenGuideAtStartup = !root.setOpenGuideAtStartup
                                        cursorShape: Qt.PointingHandCursor 
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Top Bar Accent Line
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰝤"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Top Bar Accent Line"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Slim gradient underline beneath the bar — reacts to notifications and CPU load."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setTopBarAccentLine ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setTopBarAccentLine ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setTopBarAccentLine = !root.setTopBarAccentLine; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Top Bar Accent Line Position
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰹹"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Accent Line Position"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Which edge of the bar the accent line sits on."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: root.s(220)
                                Layout.fillHeight: true
                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(6)
                                    Repeater {
                                        model: [
                                            { label: "Top", val: "top" },
                                            { label: "Bottom", val: "bottom" },
                                            { label: "Left", val: "left" },
                                            { label: "Right", val: "right" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            property bool sel: root.setTopBarAccentLinePosition === modelData.val
                                            width: root.s(48); height: root.s(28); radius: root.s(6)
                                            color: sel ? root.mauve : root.surface2
                                            border.color: root.surface1
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Text { anchors.centerIn: parent; text: modelData.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: sel ? root.base : root.subtext0 }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setTopBarAccentLinePosition = modelData.val }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Top Bar Accent Line Thickness
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(70)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰤺"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Accent Line Thickness"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Base thickness of the line, before the drifting highlight blobs."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: root.s(160)
                                spacing: root.s(2)
                                Slider {
                                    id: accentThicknessSlider
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(18)
                                    from: 1; to: 6; stepSize: 1
                                    value: root.setTopBarAccentLineThickness
                                    onMoved: root.setTopBarAccentLineThickness = Math.round(value)
                                    background: Rectangle {
                                        x: accentThicknessSlider.leftPadding
                                        y: accentThicknessSlider.topPadding + accentThicknessSlider.availableHeight / 2 - height / 2
                                        width: accentThicknessSlider.availableWidth
                                        height: root.s(6)
                                        radius: root.s(3)
                                        color: root.surface2
                                        Rectangle {
                                            width: accentThicknessSlider.visualPosition * parent.width
                                            height: parent.height
                                            radius: root.s(3)
                                            color: root.mauve
                                        }
                                    }
                                    handle: Rectangle {
                                        x: accentThicknessSlider.leftPadding + accentThicknessSlider.visualPosition * (accentThicknessSlider.availableWidth - width)
                                        y: accentThicknessSlider.topPadding + accentThicknessSlider.availableHeight / 2 - height / 2
                                        width: root.s(14); height: root.s(14); radius: root.s(7)
                                        color: root.text
                                        scale: accentThicknessSlider.pressed ? 1.25 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                    }
                                }
                                Text { text: root.setTopBarAccentLineThickness + "px"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0; Layout.alignment: Qt.AlignRight }
                            }
                        }
                    }

                    // Setting: Top Bar Accent Line Speed
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰓅"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.blue }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Accent Line Speed"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "How fast the color cycle and highlight drift run."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: root.s(220)
                                Layout.fillHeight: true
                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(6)
                                    Repeater {
                                        model: [
                                            { label: "Slow", ms: 8000 },
                                            { label: "Normal", ms: 5200 },
                                            { label: "Fast", ms: 3000 },
                                            { label: "Very Fast", ms: 1500 }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            property bool sel: root.setTopBarAccentLineSpeedMs === modelData.ms
                                            width: modelData.label === "Very Fast" ? root.s(64) : root.s(48)
                                            height: root.s(28); radius: root.s(6)
                                            color: sel ? root.blue : root.surface2
                                            border.color: root.surface1
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Text { anchors.centerIn: parent; text: modelData.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(8); color: sel ? root.base : root.subtext0 }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setTopBarAccentLineSpeedMs = modelData.ms }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Top Bar Accent Line Color Mode
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰏘"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.pink }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Accent Line Color Mode"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Cycle: mauve→pink→blue. Fixed: one accent. Album Art: pulls the track's dominant color."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: root.s(180)
                                Layout.fillHeight: true

                                Rectangle {
                                    id: accentColorModeSeg
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(180); height: root.s(26); radius: root.s(13)
                                    color: root.surface2
                                    border.color: root.surface1
                                    border.width: 1

                                    property int selIndex: root.setTopBarAccentLineColorMode === "fixed" ? 1 : (root.setTopBarAccentLineColorMode === "album" ? 2 : 0)

                                    Rectangle {
                                        width: parent.width / 3; height: parent.height; radius: root.s(13)
                                        color: root.pink
                                        x: accentColorModeSeg.selIndex * (parent.width / 3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 0
                                        Item {
                                            Layout.preferredWidth: accentColorModeSeg.width / 3
                                            Layout.fillHeight: true
                                            Text { anchors.centerIn: parent; text: "Cycle"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setTopBarAccentLineColorMode === "cycle" ? root.base : root.subtext0 }
                                            MouseArea { anchors.fill: parent; onClicked: root.setTopBarAccentLineColorMode = "cycle"; cursorShape: Qt.PointingHandCursor }
                                        }
                                        Item {
                                            Layout.preferredWidth: accentColorModeSeg.width / 3
                                            Layout.fillHeight: true
                                            Text { anchors.centerIn: parent; text: "Fixed"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setTopBarAccentLineColorMode === "fixed" ? root.base : root.subtext0 }
                                            MouseArea { anchors.fill: parent; onClicked: root.setTopBarAccentLineColorMode = "fixed"; cursorShape: Qt.PointingHandCursor }
                                        }
                                        Item {
                                            Layout.preferredWidth: accentColorModeSeg.width / 3
                                            Layout.fillHeight: true
                                            Text { anchors.centerIn: parent; text: "Album"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setTopBarAccentLineColorMode === "album" ? root.base : root.subtext0 }
                                            MouseArea { anchors.fill: parent; onClicked: root.setTopBarAccentLineColorMode = "album"; cursorShape: Qt.PointingHandCursor }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Top Bar Accent Line Fixed Color Swatch (only relevant in "fixed" color mode)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1
                        opacity: root.setTopBarAccentLineColorMode === "fixed" ? 1.0 : 0.4
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰝤"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.setTopBarAccentLineFixedColor }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Fixed Accent Line Color"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                // Fixed hex swatches, not matugen names — see CLAUDE.md: matugen color
                                // names don't map to consistent hues across wallpapers, so glow/accent
                                // pickers use fixed hex values for predictable visual choice.
                                Text { text: "Fixed hex values — stay predictable regardless of wallpaper."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true
                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(8)
                                    Repeater {
                                        model: ["#b4befe", "#89dceb", "#fab387", "#f38ba8", "#cba6f7", "#a6e3a1"]
                                        delegate: Rectangle {
                                            required property string modelData
                                            property bool sel: root.setTopBarAccentLineFixedColor.toLowerCase() === modelData
                                            width: root.s(24); height: root.s(24); radius: root.s(12)
                                            color: modelData
                                            border.width: sel ? root.s(3) : 0
                                            border.color: root.text
                                            scale: sel ? 1.0 : 0.82
                                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setTopBarAccentLineFixedColor = modelData }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Top Bar Hover Cards
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰋼"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Top Bar Hover Cards"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Detail popups on hover — sink name, battery time, wifi signal, bluetooth devices, hourly forecast."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setTopBarHoverCardsEnabled ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setTopBarHoverCardsEnabled ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setTopBarHoverCardsEnabled = !root.setTopBarHoverCardsEnabled; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Battery Liquid Fill
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰁹"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Battery Liquid Fill"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Animated liquid level behind the battery pill. Occasional: charging, low, on change, or hover."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: root.s(210)
                                Layout.fillHeight: true

                                Rectangle {
                                    id: batLiquidSeg
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(210); height: root.s(26); radius: root.s(13)
                                    color: root.surface2
                                    border.color: root.surface1
                                    border.width: 1

                                    Rectangle {
                                        width: parent.width / 3; height: parent.height; radius: root.s(13)
                                        color: root.mauve
                                        x: root.setTopBarBatteryLiquidMode === "always" ? 0 : (root.setTopBarBatteryLiquidMode === "occasional" ? parent.width / 3 : parent.width * 2 / 3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 0
                                            Item {
                                                Layout.preferredWidth: batLiquidSeg.width / 3
                                                Layout.fillHeight: true
                                                Text { anchors.centerIn: parent; text: "Always"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setTopBarBatteryLiquidMode === "always" ? root.base : root.subtext0 }
                                                MouseArea { anchors.fill: parent; onClicked: root.setTopBarBatteryLiquidMode = "always"; cursorShape: Qt.PointingHandCursor }
                                            }
                                            Item {
                                                Layout.preferredWidth: batLiquidSeg.width / 3
                                                Layout.fillHeight: true
                                                Text { anchors.centerIn: parent; text: "Occasional"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setTopBarBatteryLiquidMode === "occasional" ? root.base : root.subtext0 }
                                                MouseArea { anchors.fill: parent; onClicked: root.setTopBarBatteryLiquidMode = "occasional"; cursorShape: Qt.PointingHandCursor }
                                            }
                                            Item {
                                                Layout.preferredWidth: batLiquidSeg.width / 3
                                                Layout.fillHeight: true
                                                Text { anchors.centerIn: parent; text: "Never"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setTopBarBatteryLiquidMode === "never" ? root.base : root.subtext0 }
                                                MouseArea { anchors.fill: parent; onClicked: root.setTopBarBatteryLiquidMode = "never"; cursorShape: Qt.PointingHandCursor }
                                            }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Eco Indicator
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰌪"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Eco Indicator"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Eco-mode badges on workspace pills. Occasional: only while an app is throttled or frozen."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: root.s(210)
                                Layout.fillHeight: true

                                Rectangle {
                                    id: ecoIndSeg
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(210); height: root.s(26); radius: root.s(13)
                                    color: root.surface2
                                    border.color: root.surface1
                                    border.width: 1

                                    Rectangle {
                                        width: parent.width / 3; height: parent.height; radius: root.s(13)
                                        color: root.mauve
                                        x: root.setTopBarEcoIndicatorMode === "always" ? 0 : (root.setTopBarEcoIndicatorMode === "occasional" ? parent.width / 3 : parent.width * 2 / 3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 0
                                            Item {
                                                Layout.preferredWidth: ecoIndSeg.width / 3
                                                Layout.fillHeight: true
                                                Text { anchors.centerIn: parent; text: "Always"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setTopBarEcoIndicatorMode === "always" ? root.base : root.subtext0 }
                                                MouseArea { anchors.fill: parent; onClicked: root.setTopBarEcoIndicatorMode = "always"; cursorShape: Qt.PointingHandCursor }
                                            }
                                            Item {
                                                Layout.preferredWidth: ecoIndSeg.width / 3
                                                Layout.fillHeight: true
                                                Text { anchors.centerIn: parent; text: "Occasional"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setTopBarEcoIndicatorMode === "occasional" ? root.base : root.subtext0 }
                                                MouseArea { anchors.fill: parent; onClicked: root.setTopBarEcoIndicatorMode = "occasional"; cursorShape: Qt.PointingHandCursor }
                                            }
                                            Item {
                                                Layout.preferredWidth: ecoIndSeg.width / 3
                                                Layout.fillHeight: true
                                                Text { anchors.centerIn: parent; text: "Never"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setTopBarEcoIndicatorMode === "never" ? root.base : root.subtext0 }
                                                MouseArea { anchors.fill: parent; onClicked: root.setTopBarEcoIndicatorMode = "never"; cursorShape: Qt.PointingHandCursor }
                                            }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Volume Fill Bar
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰕾"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Volume Fill Bar"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Fill behind the volume pill. Occasional: briefly on change, or on hover."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: root.s(210)
                                Layout.fillHeight: true

                                Rectangle {
                                    id: volFillSeg
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(210); height: root.s(26); radius: root.s(13)
                                    color: root.surface2
                                    border.color: root.surface1
                                    border.width: 1

                                    Rectangle {
                                        width: parent.width / 3; height: parent.height; radius: root.s(13)
                                        color: root.mauve
                                        x: root.setTopBarVolumeFillMode === "always" ? 0 : (root.setTopBarVolumeFillMode === "occasional" ? parent.width / 3 : parent.width * 2 / 3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 0
                                            Item {
                                                Layout.preferredWidth: volFillSeg.width / 3
                                                Layout.fillHeight: true
                                                Text { anchors.centerIn: parent; text: "Always"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setTopBarVolumeFillMode === "always" ? root.base : root.subtext0 }
                                                MouseArea { anchors.fill: parent; onClicked: root.setTopBarVolumeFillMode = "always"; cursorShape: Qt.PointingHandCursor }
                                            }
                                            Item {
                                                Layout.preferredWidth: volFillSeg.width / 3
                                                Layout.fillHeight: true
                                                Text { anchors.centerIn: parent; text: "Occasional"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setTopBarVolumeFillMode === "occasional" ? root.base : root.subtext0 }
                                                MouseArea { anchors.fill: parent; onClicked: root.setTopBarVolumeFillMode = "occasional"; cursorShape: Qt.PointingHandCursor }
                                            }
                                            Item {
                                                Layout.preferredWidth: volFillSeg.width / 3
                                                Layout.fillHeight: true
                                                Text { anchors.centerIn: parent; text: "Never"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setTopBarVolumeFillMode === "never" ? root.base : root.subtext0 }
                                                MouseArea { anchors.fill: parent; onClicked: root.setTopBarVolumeFillMode = "never"; cursorShape: Qt.PointingHandCursor }
                                            }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Top Bar GPU Pill
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰢮"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Top Bar GPU Usage Pill"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "GPU load sparkline pill next to CPU. Auto-detects nvidia/amd, hides itself if no GPU is found."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setTopBarShowGpu ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setTopBarShowGpu ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setTopBarShowGpu = !root.setTopBarShowGpu; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Top Bar Net Speed Pill
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰇚"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Top Bar Net Speed Pill"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Live upload/download rate pill, sampled from the active network interface."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setTopBarShowNet ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setTopBarShowNet ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setTopBarShowNet = !root.setTopBarShowNet; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Top Bar Uptime Pill
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰥔"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Top Bar Uptime Pill"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "System uptime pill, refreshed every 30 seconds."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setTopBarShowUptime ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setTopBarShowUptime ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setTopBarShowUptime = !root.setTopBarShowUptime; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Quickshell CPU Chip
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(12)
                            spacing: root.s(12)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰆧"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Quickshell CPU Chip"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Shows quickshell's own CPU use, not your apps' — tells you when the bar itself is running hot."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setTopBarShowQuickshellCpu ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setTopBarShowQuickshellCpu ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setTopBarShowQuickshellCpu = !root.setTopBarShowQuickshellCpu; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Top Bar Workspace Icon Previews
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰕰"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Workspace Icon Previews"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Tiny app-letter icons inside occupied workspace pills, up to 3 per workspace."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setTopBarWorkspaceIconsEnabled ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setTopBarWorkspaceIconsEnabled ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setTopBarWorkspaceIconsEnabled = !root.setTopBarWorkspaceIconsEnabled; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Eco Mode
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰌪"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.green }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Eco Mode"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Caps CPU of unfocused apps and freezes ones hidden on other workspaces. Never touches anything playing audio, on a call, or recording."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setEcoModeEnabled ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setEcoModeEnabled ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setEcoModeEnabled = !root.setEcoModeEnabled; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Timer Pill
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󱎫"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Timer Pill"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Scroll to set minutes (Ctrl = hours), click to start, double-click to stop, right-click to pause."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setTopBarTimerEnabled ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setTopBarTimerEnabled ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setTopBarTimerEnabled = !root.setTopBarTimerEnabled; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Timer Progress Fill
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰔛"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Timer Progress Fill"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Draining fill behind the timer while it runs. Occasional: only while hovered or in the last minute."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: root.s(210)
                                Layout.fillHeight: true

                                Rectangle {
                                    id: timerFillSeg
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(210); height: root.s(26); radius: root.s(13)
                                    color: root.surface2
                                    border.color: root.surface1
                                    border.width: 1

                                    Rectangle {
                                        width: parent.width / 3; height: parent.height; radius: root.s(13)
                                        color: root.mauve
                                        x: root.setTopBarTimerFillMode === "always" ? 0 : (root.setTopBarTimerFillMode === "occasional" ? parent.width / 3 : parent.width * 2 / 3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 0
                                        Item {
                                            Layout.preferredWidth: timerFillSeg.width / 3
                                            Layout.fillHeight: true
                                            Text { anchors.centerIn: parent; text: "Always"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setTopBarTimerFillMode === "always" ? root.base : root.subtext0 }
                                            MouseArea { anchors.fill: parent; onClicked: root.setTopBarTimerFillMode = "always"; cursorShape: Qt.PointingHandCursor }
                                        }
                                        Item {
                                            Layout.preferredWidth: timerFillSeg.width / 3
                                            Layout.fillHeight: true
                                            Text { anchors.centerIn: parent; text: "Occasional"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setTopBarTimerFillMode === "occasional" ? root.base : root.subtext0 }
                                            MouseArea { anchors.fill: parent; onClicked: root.setTopBarTimerFillMode = "occasional"; cursorShape: Qt.PointingHandCursor }
                                        }
                                        Item {
                                            Layout.preferredWidth: timerFillSeg.width / 3
                                            Layout.fillHeight: true
                                            Text { anchors.centerIn: parent; text: "Never"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setTopBarTimerFillMode === "never" ? root.base : root.subtext0 }
                                            MouseArea { anchors.fill: parent; onClicked: root.setTopBarTimerFillMode = "never"; cursorShape: Qt.PointingHandCursor }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Wallpaper-Color Sweep (outer bar border)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰸣"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Wallpaper-Color Sweep"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Slow ambient gradient tracing the bar's outer edge, built from your live matugen palette."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setTopBarWallpaperSweepEnabled ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setTopBarWallpaperSweepEnabled ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setTopBarWallpaperSweepEnabled = !root.setTopBarWallpaperSweepEnabled; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Idle/Achievement Flourishes (umbrella)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰐕"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Idle/Achievement Flourishes"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Master toggle for rare celebratory sparkles on uptime, battery, and CPU milestones."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setTopBarFlourishesEnabled ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setTopBarFlourishesEnabled ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setTopBarFlourishesEnabled = !root.setTopBarFlourishesEnabled; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Flourish — Uptime Milestone
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰥔"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Flourish: Uptime Milestone"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "One-shot sparkle on the uptime chip each time uptime crosses a new full day."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setTopBarFlourishUptimeEnabled ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setTopBarFlourishUptimeEnabled ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setTopBarFlourishUptimeEnabled = !root.setTopBarFlourishUptimeEnabled; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Flourish — Battery Full
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰂅"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Flourish: Battery Full"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "One-shot sparkle on the battery pill the moment it hits exactly 100%."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setTopBarFlourishBatteryEnabled ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setTopBarFlourishBatteryEnabled ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setTopBarFlourishBatteryEnabled = !root.setTopBarFlourishBatteryEnabled; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Flourish — CPU Calm-Down
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰘚"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Flourish: CPU Calm-Down"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "The existing CPU-chip \"sigh\" sparkle when a load spike drops back to idle."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setTopBarFlourishCpuCalmEnabled ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setTopBarFlourishCpuCalmEnabled ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setTopBarFlourishCpuCalmEnabled = !root.setTopBarFlourishCpuCalmEnabled; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Claude debug logging
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Claude Debug Logging"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Log the Claude agent daemon to /tmp/qs_claude_debug.log (tail -f to watch)."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46)
                                    height: root.s(26)
                                    radius: root.s(13)
                                    color: root.setClaudeDebug ? root.mauve : root.surface2

                                    Behavior on color { ColorAnimation { duration: 200 } }

                                    Rectangle {
                                        width: root.s(20)
                                        height: root.s(20)
                                        radius: root.s(10)
                                        color: root.base
                                        y: root.s(3)
                                        x: root.setClaudeDebug ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.setClaudeDebug = !root.setClaudeDebug
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Discord contact profiler
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰙅"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.blue }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Discord Contact Profiler"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Resident watches Discord messages and updates profiles for known contacts in the background."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46)
                                    height: root.s(26)
                                    radius: root.s(13)
                                    color: root.setDiscordProfiler ? root.blue : root.surface2

                                    Behavior on color { ColorAnimation { duration: 200 } }

                                    Rectangle {
                                        width: root.s(20)
                                        height: root.s(20)
                                        radius: root.s(10)
                                        color: root.base
                                        y: root.s(3)
                                        x: root.setDiscordProfiler ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.setDiscordProfiler = !root.setDiscordProfiler
                                            Quickshell.execDetached(["bash", "-c",
                                                root.setDiscordProfiler
                                                    ? "bash ~/.config/hypr/scripts/quickshell/claude/discord_profiler.sh start"
                                                    : "bash ~/.config/hypr/scripts/quickshell/claude/discord_profiler.sh stop"
                                            ])
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Setting 2: UI Scale
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)
                            
                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰁦"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.blue }
                            }
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Global UI Scale Factor"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Adjust the base sizing scalar for all quickshell components."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            
                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true
                                
                                RowLayout {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(10)
                                    
                                    Rectangle {
                                        width: root.s(30)
                                        height: root.s(30)
                                        radius: root.s(6)
                                        color: sMinusMa.pressed ? root.surface2 : root.surface1
                                        Text { anchors.centerIn: parent; text: "-"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.text }
                                        MouseArea { id: sMinusMa; anchors.fill: parent; onClicked: root.setUiScale = Math.max(0.5, (root.setUiScale - 0.1).toFixed(1)) }
                                    }
                                    
                                    Text { 
                                        text: root.setUiScale.toFixed(1) + "x"
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Black
                                        font.pixelSize: root.s(14)
                                        color: root.text
                                        Layout.minimumWidth: root.s(40)
                                        horizontalAlignment: Text.AlignHCenter 
                                    }
                                    
                                    Rectangle {
                                        width: root.s(30)
                                        height: root.s(30)
                                        radius: root.s(6)
                                        color: sPlusMa.pressed ? root.surface2 : root.surface1
                                        Text { anchors.centerIn: parent; text: "+"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.text }
                                        MouseArea { id: sPlusMa; anchors.fill: parent; onClicked: root.setUiScale = Math.min(2.0, (root.setUiScale + 0.1).toFixed(1)) }
                                    }
                                }
                            }
                        }
                    }

                    // Setting 3: Keyboard Language 
                    Rectangle {
                        z: 10
                        Layout.fillWidth: true
                        Layout.minimumHeight: root.s(80)
                        implicitHeight: langBoxContent.implicitHeight + root.s(30)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1
                        
                        RowLayout {
                            id: langBoxContent
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: root.s(15)
                            spacing: root.s(20)
                            
                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: root.s(5)
                                Text { anchors.centerIn: parent; text: "󰌌"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.green }
                            }
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: root.s(4)
                                Text { text: "System Keyboard Layouts"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Active layouts matched directly to hyprland.conf. Click ✖ to remove."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: root.s(8)
                                    Layout.topMargin: root.s(5)
                                    
                                    Repeater {
                                        model: root.setLanguage ? root.setLanguage.split(",").filter(x => x.trim() !== "") : []
                                        
                                        Rectangle {
                                            width: langChipLayout.implicitWidth + root.s(24)
                                            height: root.s(30)
                                            radius: root.s(15)
                                            color: root.surface1
                                            border.color: root.surface2
                                            border.width: 1
                                            
                                            RowLayout {
                                                id: langChipLayout
                                                anchors.centerIn: parent
                                                spacing: root.s(8)
                                                
                                                Text { 
                                                    text: modelData
                                                    font.family: "JetBrains Mono"
                                                    font.weight: Font.Bold
                                                    font.pixelSize: root.s(13)
                                                    color: root.text 
                                                }
                                                
                                                Text { 
                                                    text: "✖"
                                                    font.family: "JetBrains Mono"
                                                    font.pixelSize: root.s(14)
                                                    color: chipMa.containsMouse ? root.red : root.subtext0
                                                    Behavior on color { ColorAnimation { duration: 150 } } 
                                                }
                                            }
                                            
                                            MouseArea {
                                                id: chipMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    let arr = root.setLanguage.split(",").filter(x => x.trim() !== "");
                                                    arr.splice(index, 1);
                                                    root.setLanguage = arr.join(",");
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true
                                Layout.alignment: Qt.AlignTop
                                
                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.topMargin: root.s(5)
                                    width: parent.width
                                    height: root.s(32)
                                    radius: root.s(6)
                                    color: root.surface0
                                    border.color: langInput.activeFocus ? root.green : root.surface2
                                    border.width: 1
                                    
                                    TextInput {
                                        id: langInput
                                        anchors.fill: parent
                                        anchors.margins: root.s(8)
                                        verticalAlignment: TextInput.AlignVCenter
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: root.s(12)
                                        color: root.text
                                        clip: true
                                        selectByMouse: true
                                        onTextChanged: { parent.parent.parent.parent.parent.parent.updateLangSearch(text); }
                                        Text { text: "Search to add..."; color: root.subtext0; visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                    
                                    Rectangle {
                                        width: parent.width
                                        height: Math.min(root.s(150), langSearchModel.count * root.s(30))
                                        y: parent.height + root.s(4)
                                        radius: root.s(6)
                                        color: root.surface0
                                        border.color: root.green
                                        border.width: 1
                                        visible: langInput.activeFocus && langSearchModel.count > 0 && langInput.text.trim() !== ""
                                        clip: true
                                        
                                        ListView {
                                            anchors.fill: parent
                                            model: langSearchModel
                                            interactive: true
                                            ScrollBar.vertical: ScrollBar { active: true; policy: ScrollBar.AsNeeded }
                                            delegate: Rectangle {
                                                width: parent.width
                                                height: root.s(30)
                                                color: sMaLang.containsMouse ? root.surface2 : "transparent"
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: root.s(10)
                                                    anchors.rightMargin: root.s(10)
                                                    spacing: root.s(8)
                                                    Text { text: model.code; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12); color: root.text }
                                                    Text { text: model.name; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                                }
                                                MouseArea {
                                                    id: sMaLang
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        let arr = root.setLanguage ? root.setLanguage.split(",").filter(x => x.trim() !== "") : [];
                                                        if (!arr.includes(model.code)) {
                                                            arr.push(model.code);
                                                            root.setLanguage = arr.join(",");
                                                        }
                                                        langInput.text = "";
                                                        langInput.focus = false;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Setting 4: Wallpaper Directory
                    Rectangle {
                        z: 5 
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: wpDirInput.activeFocus ? root.mauve : root.surface1
                        border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)
                            
                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Wallpaper Directory"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Set source path for the background engine. Use absolute paths."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            
                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true
                                
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: root.s(32)
                                    radius: root.s(6)
                                    color: root.surface0
                                    border.color: root.surface2
                                    border.width: 1
                                    
                                    TextInput {
                                        id: wpDirInput
                                        anchors.fill: parent
                                        anchors.margins: root.s(8)
                                        verticalAlignment: TextInput.AlignVCenter
                                        text: root.setWallpaperDir
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: root.s(12)
                                        color: root.text
                                        clip: true
                                        selectByMouse: true
                                        onTextChanged: { 
                                            root.setWallpaperDir = text; 
                                            if (activeFocus) { 
                                                pathSuggestProc.query = text; 
                                                pathSuggestProc.running = false; 
                                                pathSuggestProc.running = true; 
                                            } 
                                        }
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: pathSuggestModel.count * root.s(28)
                                        y: parent.height + root.s(4)
                                        radius: root.s(6)
                                        color: root.surface0
                                        border.color: root.mauve
                                        border.width: 1
                                        visible: pathSuggestModel.count > 0 && wpDirInput.activeFocus
                                        clip: true
                                        
                                        ListView {
                                            anchors.fill: parent
                                            model: pathSuggestModel
                                            interactive: false
                                            delegate: Rectangle {
                                                width: parent.width
                                                height: root.s(28)
                                                color: suggestMa.containsMouse ? root.surface2 : "transparent"
                                                Text { 
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    x: root.s(8)
                                                    text: model.path
                                                    font.family: "JetBrains Mono"
                                                    font.pixelSize: root.s(11)
                                                    color: root.text
                                                    elide: Text.ElideMiddle
                                                    width: parent.width - root.s(16) 
                                                }
                                                MouseArea {
                                                    id: suggestMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: { 
                                                        wpDirInput.text = model.path; 
                                                        pathSuggestModel.clear(); 
                                                        wpDirInput.focus = false; 
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
                            }
                        }
                    } // end section: general & system


                    // --- section: ambient glow ---
                    Item {
                        id: secAmbient
                        Layout.fillWidth: true
                        implicitHeight: secAmbientHeader.height + secAmbientBody.height
                        visible: root.secAmbientHasMatch

                        ColumnLayout {
                            width: parent.width
                            spacing: 0

                            Item {
                                id: secAmbientHeader
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(30)

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: root.s(10)

                                    Text {
                                        text: "▸"
                                        rotation: root.secAmbientExpanded ? 90 : 0
                                        font.pixelSize: root.s(11)
                                        color: root.subtext0
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                                    }
                                    Text { text: "󰛨"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: root.mauve; Layout.alignment: Qt.AlignVCenter }
                                    Text { text: "AMBIENT GLOW"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.surface1; Layout.alignment: Qt.AlignVCenter }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.secAmbientExpanded = !root.secAmbientExpanded
                                }
                            }

                            Item {
                                id: secAmbientBody
                                Layout.fillWidth: true
                                clip: true
                                Layout.preferredHeight: root.secAmbientExpanded ? (secAmbientContent.implicitHeight + root.s(15)) : 0
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

                                ColumnLayout {
                                    id: secAmbientContent
                                    y: root.s(15)
                                    width: parent.width
                                    spacing: root.s(15)

                    // Setting: Ambient Glow Enabled (master toggle)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰝤"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Ambient Glow"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Full-screen edge bezel on every monitor. Separate from the Top Bar's own accent line."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setAmbientGlowEnabled ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setAmbientGlowEnabled ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setAmbientGlowEnabled = !root.setAmbientGlowEnabled; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Intensity
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(70)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰃚"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.peach }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Intensity"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Opacity multiplier on the glow — how strong the bezel reads."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: root.s(160)
                                spacing: root.s(2)
                                Slider {
                                    id: intensitySlider
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(18)
                                    from: 0.3; to: 2.5
                                    value: root.setAmbientGlowIntensity
                                    onMoved: root.setAmbientGlowIntensity = Number(value.toFixed(2))
                                    background: Rectangle {
                                        x: intensitySlider.leftPadding
                                        y: intensitySlider.topPadding + intensitySlider.availableHeight / 2 - height / 2
                                        width: intensitySlider.availableWidth
                                        height: root.s(6)
                                        radius: root.s(3)
                                        color: root.surface2
                                        Rectangle {
                                            width: intensitySlider.visualPosition * parent.width
                                            height: parent.height
                                            radius: root.s(3)
                                            color: root.mauve
                                        }
                                    }
                                    handle: Rectangle {
                                        x: intensitySlider.leftPadding + intensitySlider.visualPosition * (intensitySlider.availableWidth - width)
                                        y: intensitySlider.topPadding + intensitySlider.availableHeight / 2 - height / 2
                                        width: root.s(14); height: root.s(14); radius: root.s(7)
                                        color: root.text
                                        scale: intensitySlider.pressed ? 1.25 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                    }
                                }
                                Text { text: Math.round(root.setAmbientGlowIntensity * 100) + "%"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0; Layout.alignment: Qt.AlignRight }
                            }
                        }
                    }

                    // Setting: Glow Spread
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(70)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰡷"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.blue }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Glow Spread"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "How far the bleed extends inward from each active edge."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: root.s(160)
                                spacing: root.s(2)
                                Slider {
                                    id: spreadSlider
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(18)
                                    from: 60; to: 280; stepSize: 10
                                    value: root.setAmbientGlowSpread
                                    onMoved: root.setAmbientGlowSpread = Math.round(value)
                                    background: Rectangle {
                                        x: spreadSlider.leftPadding
                                        y: spreadSlider.topPadding + spreadSlider.availableHeight / 2 - height / 2
                                        width: spreadSlider.availableWidth
                                        height: root.s(6)
                                        radius: root.s(3)
                                        color: root.surface2
                                        Rectangle {
                                            width: spreadSlider.visualPosition * parent.width
                                            height: parent.height
                                            radius: root.s(3)
                                            color: root.blue
                                        }
                                    }
                                    handle: Rectangle {
                                        x: spreadSlider.leftPadding + spreadSlider.visualPosition * (spreadSlider.availableWidth - width)
                                        y: spreadSlider.topPadding + spreadSlider.availableHeight / 2 - height / 2
                                        width: root.s(14); height: root.s(14); radius: root.s(7)
                                        color: root.text
                                        scale: spreadSlider.pressed ? 1.25 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                    }
                                }
                                Text { text: root.setAmbientGlowSpread + "px"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0; Layout.alignment: Qt.AlignRight }
                            }
                        }
                    }

                    // Setting: Active Edges
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰙌"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.green }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Active Edges"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Which screen edges the glow bleeds in from."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true
                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(6)
                                    Repeater {
                                        model: [
                                            { label: "Top", prop: "setAmbientGlowEdgeTop" },
                                            { label: "Bot", prop: "setAmbientGlowEdgeBottom" },
                                            { label: "Left", prop: "setAmbientGlowEdgeLeft" },
                                            { label: "Right", prop: "setAmbientGlowEdgeRight" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            property bool on: root[modelData.prop]
                                            width: root.s(46); height: root.s(28); radius: root.s(6)
                                            color: on ? root.green : root.surface2
                                            border.color: root.surface1
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Text { anchors.centerIn: parent; text: modelData.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: on ? root.base : root.subtext0 }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root[modelData.prop] = !root[modelData.prop] }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Color Mode
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰏘"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.pink }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Color Mode"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Cycle: mauve→pink→blue. Fixed: one accent. Album Art: pulls the track's dominant color."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: root.s(180)
                                Layout.fillHeight: true

                                Rectangle {
                                    id: colorModeSeg
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(180); height: root.s(26); radius: root.s(13)
                                    color: root.surface2
                                    border.color: root.surface1
                                    border.width: 1

                                    property int selIndex: root.setAmbientGlowColorMode === "fixed" ? 1 : (root.setAmbientGlowColorMode === "album" ? 2 : 0)

                                    Rectangle {
                                        width: parent.width / 3; height: parent.height; radius: root.s(13)
                                        color: root.pink
                                        x: colorModeSeg.selIndex * (parent.width / 3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 0
                                        Item {
                                            Layout.preferredWidth: colorModeSeg.width / 3
                                            Layout.fillHeight: true
                                            Text { anchors.centerIn: parent; text: "Cycle"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setAmbientGlowColorMode === "cycle" ? root.base : root.subtext0 }
                                            MouseArea { anchors.fill: parent; onClicked: root.setAmbientGlowColorMode = "cycle"; cursorShape: Qt.PointingHandCursor }
                                        }
                                        Item {
                                            Layout.preferredWidth: colorModeSeg.width / 3
                                            Layout.fillHeight: true
                                            Text { anchors.centerIn: parent; text: "Fixed"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setAmbientGlowColorMode === "fixed" ? root.base : root.subtext0 }
                                            MouseArea { anchors.fill: parent; onClicked: root.setAmbientGlowColorMode = "fixed"; cursorShape: Qt.PointingHandCursor }
                                        }
                                        Item {
                                            Layout.preferredWidth: colorModeSeg.width / 3
                                            Layout.fillHeight: true
                                            Text { anchors.centerIn: parent; text: "Album"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setAmbientGlowColorMode === "album" ? root.base : root.subtext0 }
                                            MouseArea { anchors.fill: parent; onClicked: root.setAmbientGlowColorMode = "album"; cursorShape: Qt.PointingHandCursor }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Fixed Color Swatch (only relevant in "fixed" color mode)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1
                        opacity: root.setAmbientGlowColorMode === "fixed" ? 1.0 : 0.4
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰝤"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.setAmbientGlowFixedColor }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Fixed Accent Color"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                // Fixed hex swatches, not matugen names — see CLAUDE.md: matugen color
                                // names don't map to consistent hues across wallpapers, so glow/accent
                                // pickers use fixed hex values for predictable visual choice.
                                Text { text: "Fixed hex values — stay predictable regardless of wallpaper."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true
                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(8)
                                    Repeater {
                                        model: ["#b4befe", "#89dceb", "#fab387", "#f38ba8", "#cba6f7", "#a6e3a1"]
                                        delegate: Rectangle {
                                            required property string modelData
                                            property bool sel: root.setAmbientGlowFixedColor.toLowerCase() === modelData
                                            width: root.s(24); height: root.s(24); radius: root.s(12)
                                            color: modelData
                                            border.width: sel ? root.s(3) : 0
                                            border.color: root.text
                                            scale: sel ? 1.0 : 0.82
                                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setAmbientGlowFixedColor = modelData }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Beat Reactivity
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰽲"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Beat Reactivity"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Pulse the glow to the current track's BPM. Off = flat, unpulsed bezel."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setAmbientGlowBeatReactive ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setAmbientGlowBeatReactive ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setAmbientGlowBeatReactive = !root.setAmbientGlowBeatReactive; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Cycle Speed
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰓅"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.blue }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Cycle Speed"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "How fast the color cycle/breathing runs between colors."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: root.s(220)
                                Layout.fillHeight: true
                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(6)
                                    Repeater {
                                        model: [
                                            { label: "Slow", ms: 8000 },
                                            { label: "Normal", ms: 5200 },
                                            { label: "Fast", ms: 3000 },
                                            { label: "Very Fast", ms: 1500 }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            property bool sel: root.setAmbientGlowCycleSpeedMs === modelData.ms
                                            width: modelData.label === "Very Fast" ? root.s(64) : root.s(48)
                                            height: root.s(28); radius: root.s(6)
                                            color: sel ? root.blue : root.surface2
                                            border.color: root.surface1
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Text { anchors.centerIn: parent; text: modelData.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(8); color: sel ? root.base : root.subtext0 }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setAmbientGlowCycleSpeedMs = modelData.ms }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Idle Behavior
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰒲"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.subtext0 }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Idle Behavior"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "What the glow does when nothing is playing."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: root.s(160)
                                Layout.fillHeight: true

                                Rectangle {
                                    id: idleSeg
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(160); height: root.s(26); radius: root.s(13)
                                    color: root.surface2
                                    border.color: root.surface1
                                    border.width: 1

                                    Rectangle {
                                        width: parent.width / 2; height: parent.height; radius: root.s(13)
                                        color: root.subtext0
                                        x: root.setAmbientGlowIdleBehavior === "dim" ? 0 : parent.width / 2
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 0
                                        Item {
                                            Layout.preferredWidth: idleSeg.width / 2
                                            Layout.fillHeight: true
                                            Text { anchors.centerIn: parent; text: "Keep Cycling"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setAmbientGlowIdleBehavior === "dim" ? root.base : root.subtext0 }
                                            MouseArea { anchors.fill: parent; onClicked: root.setAmbientGlowIdleBehavior = "dim"; cursorShape: Qt.PointingHandCursor }
                                        }
                                        Item {
                                            Layout.preferredWidth: idleSeg.width / 2
                                            Layout.fillHeight: true
                                            Text { anchors.centerIn: parent; text: "Fade Out"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.setAmbientGlowIdleBehavior === "fadeOut" ? root.base : root.subtext0 }
                                            MouseArea { anchors.fill: parent; onClicked: root.setAmbientGlowIdleBehavior = "fadeOut"; cursorShape: Qt.PointingHandCursor }
                                        }
                                    }
                                }
                            }
                        }
                    }

                                }
                            }
                        }
                    } // end section: ambient glow


                    // --- section: resident cards ---
                    Item {
                        id: secResident
                        Layout.fillWidth: true
                        implicitHeight: secResidentHeader.height + secResidentBody.height
                        visible: root.secResidentHasMatch

                        ColumnLayout {
                            width: parent.width
                            spacing: 0

                            Item {
                                id: secResidentHeader
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(30)

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: root.s(10)

                                    Text {
                                        text: "▸"
                                        rotation: root.secResidentExpanded ? 90 : 0
                                        font.pixelSize: root.s(11)
                                        color: root.subtext0
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                                    }
                                    Text { text: "󰚩"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: root.mauve; Layout.alignment: Qt.AlignVCenter }
                                    Text { text: "RESIDENT CARDS"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.surface1; Layout.alignment: Qt.AlignVCenter }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.secResidentExpanded = !root.secResidentExpanded
                                }
                            }

                            Item {
                                id: secResidentBody
                                Layout.fillWidth: true
                                clip: true
                                Layout.preferredHeight: root.secResidentExpanded ? (secResidentContent.implicitHeight + root.s(15)) : 0
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

                                ColumnLayout {
                                    id: secResidentContent
                                    y: root.s(15)
                                    width: parent.width
                                    spacing: root.s(15)

                                    component RcChoiceRow: Rectangle {
                                        id: rcr
                                        property string glyph: ""
                                        property string title: ""
                                        property string sub: ""
                                        property string mode: ""
                                        property var options: []
                                        signal picked(string v)
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(60)
                                        radius: root.s(8)
                                        color: Qt.alpha(root.surface0, 0.4)
                                        border.color: root.surface1
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: root.s(15)
                                            spacing: root.s(20)

                                            Item {
                                                Layout.preferredWidth: root.s(30)
                                                Layout.alignment: Qt.AlignVCenter
                                                Text { anchors.centerIn: parent; text: rcr.glyph; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: root.s(4)
                                                Text { text: rcr.title; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                                Text { text: rcr.sub; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                            }

                                            Item {
                                                Layout.preferredWidth: root.s(70) * Math.max(2, rcr.options.length)
                                                Layout.fillHeight: true

                                                Rectangle {
                                                    id: rcrSeg
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width; height: root.s(26); radius: root.s(13)
                                                    color: root.surface2
                                                    border.color: root.surface1
                                                    border.width: 1

                                                    Rectangle {
                                                        readonly property int idx: { for (let i = 0; i < rcr.options.length; i++) if (rcr.options[i].v === rcr.mode) return i; return 0 }
                                                        width: parent.width / Math.max(1, rcr.options.length); height: parent.height; radius: root.s(13)
                                                        color: root.mauve
                                                        x: idx * width
                                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        spacing: 0
                                                        Repeater {
                                                            model: rcr.options
                                                            delegate: Item {
                                                                Layout.preferredWidth: rcrSeg.width / Math.max(1, rcr.options.length)
                                                                Layout.fillHeight: true
                                                                Text { anchors.centerIn: parent; text: modelData.l; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: rcr.mode === modelData.v ? root.base : root.subtext0 }
                                                                MouseArea { anchors.fill: parent; onClicked: rcr.picked(modelData.v); cursorShape: Qt.PointingHandCursor }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    RcChoiceRow {
                                        glyph: "󰚩"; title: "Resident cards"; sub: "Cards that drop down under the clock pill for Claude answers, screenshot results and timer alerts."
                                        options: [ { v: "on", l: "On" }, { v: "off", l: "Off" } ]
                                        mode: root.setResidentCardsEnabled ? "on" : "off"
                                        onPicked: (v) => root.setResidentCardsEnabled = (v === "on")
                                    }

                                    RcChoiceRow {
                                        glyph: "󰍉"; title: "Card position"; sub: "Where the card appears. Only under the middle pill for now."
                                        options: [ { v: "under-middle-pill", l: "Under pill" } ]
                                        mode: root.setResidentCardPosition
                                        onPicked: (v) => root.setResidentCardPosition = v
                                    }

                                    RcChoiceRow {
                                        glyph: "󰘖"; title: "Max card height"; sub: "How tall the card grows before a long answer scrolls."
                                        options: [ { v: "small", l: "Small" }, { v: "medium", l: "Medium" }, { v: "large", l: "Large" } ]
                                        mode: root.setResidentCardMaxHeight
                                        onPicked: (v) => root.setResidentCardMaxHeight = v
                                    }

                                    RcChoiceRow {
                                        glyph: "󰔛"; title: "Hold time"; sub: "Auto = each card decides (long answers stay longer). Short = 8s. Until dismissed = never auto-hide."
                                        options: [ { v: "auto", l: "Auto" }, { v: "short", l: "Short" }, { v: "until-dismissed", l: "Manual" } ]
                                        mode: root.setResidentCardHoldMode
                                        onPicked: (v) => root.setResidentCardHoldMode = v
                                    }

                                    RcChoiceRow {
                                        glyph: "󰕾"; title: "Card sound"; sub: "Play a short chime when a card arrives (not for low-urgency cards)."
                                        options: [ { v: "on", l: "On" }, { v: "off", l: "Off" } ]
                                        mode: root.setResidentCardSound
                                        onPicked: (v) => root.setResidentCardSound = v
                                    }

                                    Rectangle {
                                        id: rcSndRow
                                        readonly property var tones: [
                                            { v: "complete", l: "Complete" },
                                            { v: "message", l: "Message" },
                                            { v: "message-new-instant", l: "Instant" },
                                            { v: "bell", l: "Bell" },
                                            { v: "dialog-information", l: "Info" },
                                            { v: "window-attention", l: "Attention" },
                                            { v: "service-login", l: "Login" },
                                            { v: "device-added", l: "Device" },
                                            { v: "audio-volume-change", l: "Tick" }
                                        ]
                                        readonly property int idx: { for (let i = 0; i < tones.length; i++) if (tones[i].v === root.setResidentCardSoundFile) return i; return -1 }
                                        readonly property string label: idx >= 0 ? tones[idx].l : String(root.setResidentCardSoundFile).split("/").pop()
                                        function path(v) { return String(v).charAt(0) === "/" ? v : "/usr/share/sounds/freedesktop/stereo/" + v + ".oga" }
                                        function preview() { Quickshell.execDetached(["paplay", rcSndRow.path(root.setResidentCardSoundFile)]) }
                                        function step(d) {
                                            let n = tones.length
                                            let i = idx < 0 ? 0 : (idx + d + n) % n
                                            root.setResidentCardSoundFile = tones[i].v
                                            preview()
                                        }
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(60)
                                        radius: root.s(8)
                                        color: Qt.alpha(root.surface0, 0.4)
                                        border.color: root.surface1
                                        border.width: 1
                                        opacity: root.setResidentCardSound === "on" ? 1.0 : 0.5
                                        Behavior on opacity { NumberAnimation { duration: 200 } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: root.s(15)
                                            spacing: root.s(20)

                                            Item {
                                                Layout.preferredWidth: root.s(30)
                                                Layout.alignment: Qt.AlignVCenter
                                                Text { anchors.centerIn: parent; text: "󰂞"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: root.s(4)
                                                Text { text: "Card ping"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                                Text { text: "Tone for nudge cards. Arrows cycle and preview."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                            }

                                            Item {
                                                Layout.preferredWidth: root.s(210)
                                                Layout.fillHeight: true

                                                Rectangle {
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width; height: root.s(26); radius: root.s(13)
                                                    color: root.surface2
                                                    border.color: root.surface1
                                                    border.width: 1

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        spacing: 0
                                                        Item {
                                                            Layout.preferredWidth: root.s(32); Layout.fillHeight: true
                                                            Text { anchors.centerIn: parent; text: "󰅁"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(13); color: rcSndPrev.containsMouse ? root.mauve : root.subtext0 }
                                                            MouseArea { id: rcSndPrev; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rcSndRow.step(-1) }
                                                        }
                                                        Rectangle {
                                                            Layout.fillWidth: true; Layout.fillHeight: true
                                                            radius: root.s(13)
                                                            color: rcSndPlay.containsMouse ? Qt.alpha(root.mauve, 0.85) : root.mauve
                                                            Row {
                                                                anchors.centerIn: parent; spacing: root.s(6)
                                                                Text { anchors.verticalCenter: parent.verticalCenter; text: "󰐊"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(11); color: root.base }
                                                                Text { anchors.verticalCenter: parent.verticalCenter; text: rcSndRow.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(10); color: root.base }
                                                            }
                                                            MouseArea { id: rcSndPlay; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rcSndRow.preview() }
                                                        }
                                                        Item {
                                                            Layout.preferredWidth: root.s(32); Layout.fillHeight: true
                                                            Text { anchors.centerIn: parent; text: "󰅂"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(13); color: rcSndNext.containsMouse ? root.mauve : root.subtext0 }
                                                            MouseArea { id: rcSndNext; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rcSndRow.step(1) }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    RcChoiceRow {
                                        glyph: "󰄀"; title: "Screenshot answer output"; sub: "Where the SUPER+CTRL+Z answer goes: a card, a notification, or both."
                                        options: [ { v: "card", l: "Card" }, { v: "notification", l: "Notif" }, { v: "both", l: "Both" } ]
                                        mode: root.setScreenshotAnswerOutput
                                        onPicked: (v) => root.setScreenshotAnswerOutput = v
                                    }

                                    component RcPromptRow: Rectangle {
                                        id: rpr
                                        property string glyph: ""
                                        property string title: ""
                                        property string sub: ""
                                        property string value: ""
                                        property string defaultText: ""
                                        signal edited(string v)
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(150)
                                        radius: root.s(8)
                                        color: Qt.alpha(root.surface0, 0.4)
                                        border.color: rprEdit.activeFocus ? root.mauve : root.surface1
                                        border.width: 1
                                        Behavior on border.color { ColorAnimation { duration: 150 } }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: root.s(15)
                                            spacing: root.s(8)

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: root.s(20)
                                                Item {
                                                    Layout.preferredWidth: root.s(30)
                                                    Layout.alignment: Qt.AlignVCenter
                                                    Text { anchors.centerIn: parent; text: rpr.glyph; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: root.s(4)
                                                    Text { text: rpr.title; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                                    Text { text: rpr.sub; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                                }
                                                Rectangle {
                                                    Layout.preferredWidth: root.s(50); Layout.preferredHeight: root.s(20); radius: root.s(10)
                                                    visible: rpr.value !== ""
                                                    color: resetMa.containsMouse ? root.surface2 : "transparent"
                                                    border.color: root.surface1; border.width: 1
                                                    Text { anchors.centerIn: parent; text: "reset"; font.family: "JetBrains Mono"; font.pixelSize: root.s(9); color: root.subtext0 }
                                                    MouseArea { id: resetMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { rprEdit.text = ""; rpr.edited(""); } }
                                                }
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                radius: root.s(6)
                                                color: root.surface0
                                                border.color: root.surface2
                                                border.width: 1
                                                clip: true

                                                Flickable {
                                                    anchors.fill: parent
                                                    anchors.margins: root.s(8)
                                                    contentWidth: width
                                                    contentHeight: Math.max(height, rprEdit.implicitHeight)
                                                    clip: true
                                                    interactive: rprEdit.implicitHeight > height

                                                    TextEdit {
                                                        id: rprEdit
                                                        width: parent.width
                                                        text: rpr.value
                                                        wrapMode: TextEdit.Wrap
                                                        font.family: "JetBrains Mono"
                                                        font.pixelSize: root.s(11)
                                                        color: root.text
                                                        selectByMouse: true
                                                        selectionColor: Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.3)
                                                        onTextChanged: rpr.edited(text)

                                                        Text {
                                                            visible: rprEdit.text === "" && !rprEdit.activeFocus
                                                            width: parent.width
                                                            text: rpr.defaultText
                                                            wrapMode: Text.Wrap
                                                            font.family: "JetBrains Mono"
                                                            font.pixelSize: root.s(11)
                                                            color: root.overlay0
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    RcPromptRow {
                                        glyph: "󰄀"; title: "Screenshot answer prompt"; sub: "System prompt for SUPER+CTRL+Z auto-solve. Empty = built-in default."
                                        value: root.setResidentShotAnswerPrompt
                                        defaultText: "Solve what's in this screenshot correctly. First reason briefly (max 4 short sentences) about which answer is actually right, checking each option against real domain knowledge. Then end with a final line starting with 'ANSWER:' followed by only the answer, max 15 words. Multiple choice: option number plus at most 6 words of that option (in the question's language). Problem: just the result. Error: the one-line fix."
                                        onEdited: (v) => root.setResidentShotAnswerPrompt = v
                                    }

                                    RcPromptRow {
                                        glyph: "󰋙"; title: "Screenshot classify prompt"; sub: "System prompt for the passive screenshot classifier. Empty = built-in default."
                                        value: root.setResidentShotClassifyPrompt
                                        defaultText: "Classify this screenshot into exactly one category: 'error' (visible error message, stacktrace, crash dialog, failed command), 'text' (mostly readable text worth extracting — a document, chat, code, terminal output), 'ui' (a UI/design worth annotating or discussing), or 'none' (nothing actionable — a game, a video, a blank desktop, etc). Reply with ONLY compact JSON, no markdown fence: {\"category\":\"error|text|ui|none\",\"summary\":\"one short line\",\"text_content\":\"transcribed text if category is text, else empty string\"}"
                                        onEdited: (v) => root.setResidentShotClassifyPrompt = v
                                    }
                                }
                            }
                        }
                    }

                    // --- section: resident nudges ---
                    Item {
                        id: secNudges
                        Layout.fillWidth: true
                        implicitHeight: secNudgesHeader.height + secNudgesBody.height
                        visible: root.secNudgesHasMatch

                        ColumnLayout {
                            width: parent.width
                            spacing: 0

                            Item {
                                id: secNudgesHeader
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(30)

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: root.s(10)

                                    Text {
                                        text: "▸"
                                        rotation: root.secNudgesExpanded ? 90 : 0
                                        font.pixelSize: root.s(11)
                                        color: root.subtext0
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                                    }
                                    Text { text: "󰂚"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: root.mauve; Layout.alignment: Qt.AlignVCenter }
                                    Text { text: "RESIDENT NUDGES"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.surface1; Layout.alignment: Qt.AlignVCenter }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.secNudgesExpanded = !root.secNudgesExpanded
                                }
                            }

                            Item {
                                id: secNudgesBody
                                Layout.fillWidth: true
                                clip: true
                                Layout.preferredHeight: root.secNudgesExpanded ? (secNudgesContent.implicitHeight + root.s(15)) : 0
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

                                ColumnLayout {
                                    id: secNudgesContent
                                    y: root.s(15)
                                    width: parent.width
                                    spacing: root.s(15)

                                    RcChoiceRow {
                                        glyph: "󰝚"; title: "Replay milestones"; sub: "Wrapped-style card when a track hits every 20th play."
                                        options: [ { v: "on", l: "On" }, { v: "off", l: "Off" } ]
                                        mode: root.setResidentNowPlayingEnabled ? "on" : "off"
                                        onPicked: (v) => root.setResidentNowPlayingEnabled = (v === "on")
                                    }

                                    RcChoiceRow {
                                        glyph: "󰃭"; title: "Event reminders"; sub: "Card ~15 min before a calendar event starts, with a live countdown."
                                        options: [ { v: "on", l: "On" }, { v: "off", l: "Off" } ]
                                        mode: root.setResidentCalendarNudgeEnabled ? "on" : "off"
                                        onPicked: (v) => root.setResidentCalendarNudgeEnabled = (v === "on")
                                    }

                                    RcChoiceRow {
                                        glyph: "󰂄"; title: "Battery health"; sub: "Weekly card with cycle count, wear and capacity vs design."
                                        options: [ { v: "on", l: "On" }, { v: "off", l: "Off" } ]
                                        mode: root.setResidentBatteryHealthEnabled ? "on" : "off"
                                        onPicked: (v) => root.setResidentBatteryHealthEnabled = (v === "on")
                                    }

                                    RcChoiceRow {
                                        glyph: "󰥔"; title: "Uptime guilt"; sub: "Cheeky nudge when the machine has been up 3+ days."
                                        options: [ { v: "on", l: "On" }, { v: "off", l: "Off" } ]
                                        mode: root.setResidentUptimeGuiltEnabled ? "on" : "off"
                                        onPicked: (v) => root.setResidentUptimeGuiltEnabled = (v === "on")
                                    }

                                    RcChoiceRow {
                                        glyph: "󰔟"; title: "Focus session done"; sub: "Timer-done card with a focus ring, app breakdown and start another. Off = plain timer card."
                                        options: [ { v: "on", l: "On" }, { v: "off", l: "Off" } ]
                                        mode: root.setResidentFocusDoneEnabled ? "on" : "off"
                                        onPicked: (v) => root.setResidentFocusDoneEnabled = (v === "on")
                                    }

                                    RcChoiceRow {
                                        glyph: "󰖨"; title: "Afternoon brief"; sub: "What's left today, screen time so far, next event. Off, a card, or card plus spoken."
                                        options: [ { v: "off", l: "Off" }, { v: "text", l: "Card" }, { v: "spoken", l: "Spoken" } ]
                                        mode: root.setResidentAfternoonBrief
                                        onPicked: (v) => root.setResidentAfternoonBrief = v
                                    }

                                    RcChoiceRow {
                                        glyph: "󰥔"; title: "Afternoon brief window"; sub: "When the afternoon brief may fire (once a day)."
                                        options: [ { v: "12:00-15:00", l: "12-15" }, { v: "13:00-16:00", l: "13-16" }, { v: "14:00-18:00", l: "14-18" } ]
                                        mode: root.setResidentAfternoonBriefTime
                                        onPicked: (v) => root.setResidentAfternoonBriefTime = v
                                    }

                                    RcChoiceRow {
                                        glyph: "󰽥"; title: "Night brief"; sub: "Wind-down: tomorrow's first event and weather, today's screen time."
                                        options: [ { v: "off", l: "Off" }, { v: "text", l: "Card" }, { v: "spoken", l: "Spoken" } ]
                                        mode: root.setResidentNightBrief
                                        onPicked: (v) => root.setResidentNightBrief = v
                                    }

                                    RcChoiceRow {
                                        glyph: "󰥔"; title: "Night brief window"; sub: "When the night brief may fire (once a day)."
                                        options: [ { v: "19:00-22:00", l: "19-22" }, { v: "20:30-23:59", l: "20:30+" }, { v: "22:00-23:59", l: "22+" } ]
                                        mode: root.setResidentNightBriefTime
                                        onPicked: (v) => root.setResidentNightBriefTime = v
                                    }
                                }
                            }
                        }
                    }

                    // --- section: pill backgrounds ---
                    Item {
                        id: secPillBg
                        Layout.fillWidth: true
                        implicitHeight: secPillBgHeader.height + secPillBgBody.height
                        visible: root.secPillBgHasMatch

                        ColumnLayout {
                            width: parent.width
                            spacing: 0

                            Item {
                                id: secPillBgHeader
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(30)

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: root.s(10)

                                    Text {
                                        text: "▸"
                                        rotation: root.secPillBgExpanded ? 90 : 0
                                        font.pixelSize: root.s(11)
                                        color: root.subtext0
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                                    }
                                    Text { text: "󰏘"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: root.mauve; Layout.alignment: Qt.AlignVCenter }
                                    Text { text: "PILL BACKGROUNDS"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.surface1; Layout.alignment: Qt.AlignVCenter }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.secPillBgExpanded = !root.secPillBgExpanded
                                }
                            }

                            Item {
                                id: secPillBgBody
                                Layout.fillWidth: true
                                clip: true
                                Layout.preferredHeight: root.secPillBgExpanded ? (secPillBgContent.implicitHeight + root.s(15)) : 0
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

                                ColumnLayout {
                                    id: secPillBgContent
                                    y: root.s(15)
                                    width: parent.width
                                    spacing: root.s(15)

                                    component PillModeRow: Rectangle {
                                        id: pmr
                                        property string glyph: ""
                                        property string title: ""
                                        property string sub: ""
                                        property string mode: "occasional"
                                        signal picked(string v)
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(60)
                                        radius: root.s(8)
                                        color: Qt.alpha(root.surface0, 0.4)
                                        border.color: root.surface1
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: root.s(15)
                                            spacing: root.s(20)

                                            Item {
                                                Layout.preferredWidth: root.s(30)
                                                Layout.alignment: Qt.AlignVCenter
                                                Text { anchors.centerIn: parent; text: pmr.glyph; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: root.s(4)
                                                Text { text: pmr.title; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                                Text { text: pmr.sub; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                            }

                                            Item {
                                                Layout.preferredWidth: root.s(210)
                                                Layout.fillHeight: true

                                                Rectangle {
                                                    id: pmrSeg
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: root.s(210); height: root.s(26); radius: root.s(13)
                                                    color: root.surface2
                                                    border.color: root.surface1
                                                    border.width: 1

                                                    Rectangle {
                                                        width: parent.width / 3; height: parent.height; radius: root.s(13)
                                                        color: root.mauve
                                                        x: pmr.mode === "always" ? 0 : (pmr.mode === "occasional" ? parent.width / 3 : parent.width * 2 / 3)
                                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        spacing: 0
                                                        Repeater {
                                                            model: [ { v: "always", l: "Always" }, { v: "occasional", l: "Occasional" }, { v: "never", l: "Never" } ]
                                                            delegate: Item {
                                                                Layout.preferredWidth: pmrSeg.width / 3
                                                                Layout.fillHeight: true
                                                                Text { anchors.centerIn: parent; text: modelData.l; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: pmr.mode === modelData.v ? root.base : root.subtext0 }
                                                                MouseArea { anchors.fill: parent; onClicked: pmr.picked(modelData.v); cursorShape: Qt.PointingHandCursor }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    PillModeRow {
                                        glyph: "󰏘"; title: "All pill backgrounds"; sub: "Master switch. Never = every effect off; Always = every non-Never effect on all the time; Occasional = each effect follows its own rule."
                                        mode: root.setTopBarPillBgMaster
                                        onPicked: (v) => root.setTopBarPillBgMaster = v
                                    }

                                    PillModeRow {
                                        glyph: "󰁹"; title: "Battery Liquid Fill"; sub: "Liquid level behind the battery pill. Occasional: charging, low, on change, hover."
                                        mode: root.setTopBarBatteryLiquidMode
                                        onPicked: (v) => root.setTopBarBatteryLiquidMode = v
                                    }

                                    PillModeRow {
                                        glyph: "󰕾"; title: "Volume Fill"; sub: "Level fill behind the volume pill. Occasional: 3s after a change, hover."
                                        mode: root.setTopBarVolumeFillMode
                                        onPicked: (v) => root.setTopBarVolumeFillMode = v
                                    }

                                    PillModeRow {
                                        glyph: "󰖙"; title: "Weather Sky"; sub: "Sky behind the clock: time of day, rain, clouds, stars. Occasional: hover, 8s after weather/phase change."
                                        mode: root.setTopBarSkyMode
                                        onPicked: (v) => root.setTopBarSkyMode = v
                                    }

                                    PillModeRow {
                                        glyph: "󰤨"; title: "Wifi Radar"; sub: "Radar rings from signal and traffic. Occasional: hover or on signal/connection change."
                                        mode: root.setTopBarWifiRadarMode
                                        onPicked: (v) => root.setTopBarWifiRadarMode = v
                                    }

                                    PillModeRow {
                                        glyph: "󰂯"; title: "Bluetooth Pulse"; sub: "Ring pulse tinted by device type. Occasional: on connect/disconnect, hover."
                                        mode: root.setTopBarBtPulseMode
                                        onPicked: (v) => root.setTopBarBtPulseMode = v
                                    }

                                    PillModeRow {
                                        glyph: "󰘚"; title: "CPU / GPU Area Fill"; sub: "Load sparkline as a soft area behind the chip. Occasional: load 60%+ or hover."
                                        mode: root.setTopBarCpuAreaMode
                                        onPicked: (v) => root.setTopBarCpuAreaMode = v
                                    }

                                    PillModeRow {
                                        glyph: "󰇚"; title: "Net Particles"; sub: "Particles flowing down/up with traffic. Occasional: traffic over 100KB/s or hover."
                                        mode: root.setTopBarNetParticlesMode
                                        onPicked: (v) => root.setTopBarNetParticlesMode = v
                                    }

                                    PillModeRow {
                                        glyph: "󰥔"; title: "Uptime Constellation"; sub: "A star per day of uptime behind the uptime chip. Occasional: hover only."
                                        mode: root.setTopBarUptimeStarsMode
                                        onPicked: (v) => root.setTopBarUptimeStarsMode = v
                                    }

                                    PillModeRow {
                                        glyph: "󰕰"; title: "Workspace Tint"; sub: "Active workspace pill takes the focused app color. Occasional: 3s after switching."
                                        mode: root.setTopBarWorkspaceTintMode
                                        onPicked: (v) => root.setTopBarWorkspaceTintMode = v
                                    }

                                    PillModeRow {
                                        glyph: "󰧑"; title: "Claude Aurora"; sub: "Aurora shimmer on the Claude pill. Occasional: while Claude is working."
                                        mode: root.setTopBarClaudeAuroraMode
                                        onPicked: (v) => root.setTopBarClaudeAuroraMode = v
                                    }
                                }
                            }
                        }
                    } // end section: pill backgrounds

                    // --- section: smart workspaces ---
                    Item {
                        id: secSmartWs
                        Layout.fillWidth: true
                        implicitHeight: secSmartWsHeader.height + secSmartWsBody.height
                        visible: root.secSmartWsHasMatch

                        ColumnLayout {
                            width: parent.width
                            spacing: 0

                            Item {
                                id: secSmartWsHeader
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(30)

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: root.s(10)

                                    Text {
                                        text: "▸"
                                        rotation: root.secSmartWsExpanded ? 90 : 0
                                        font.pixelSize: root.s(11)
                                        color: root.subtext0
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                                    }
                                    Text { text: "󰍹"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: root.mauve; Layout.alignment: Qt.AlignVCenter }
                                    Text { text: "SMART WORKSPACES"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.surface1; Layout.alignment: Qt.AlignVCenter }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.secSmartWsExpanded = !root.secSmartWsExpanded
                                }
                            }

                            Item {
                                id: secSmartWsBody
                                Layout.fillWidth: true
                                clip: true
                                Layout.preferredHeight: root.secSmartWsExpanded ? (secSmartWsContent.implicitHeight + root.s(15)) : 0
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

                                ColumnLayout {
                                    id: secSmartWsContent
                                    y: root.s(15)
                                    width: parent.width
                                    spacing: root.s(15)

                                    component SwsOptRow: Rectangle {
                                        id: sor
                                        property string glyph: ""
                                        property string title: ""
                                        property string sub: ""
                                        property var value
                                        property var options: []
                                        signal picked(var v)
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(60)
                                        radius: root.s(8)
                                        color: Qt.alpha(root.surface0, 0.4)
                                        border.color: root.surface1
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: root.s(15)
                                            spacing: root.s(20)

                                            Item {
                                                Layout.preferredWidth: root.s(30)
                                                Layout.alignment: Qt.AlignVCenter
                                                Text { anchors.centerIn: parent; text: sor.glyph; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: root.s(4)
                                                Text { text: sor.title; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                                Text { text: sor.sub; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                            }

                                            Item {
                                                Layout.preferredWidth: root.s(70) * Math.max(2, sor.options.length)
                                                Layout.fillHeight: true

                                                Rectangle {
                                                    id: sorSeg
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: root.s(70) * Math.max(2, sor.options.length); height: root.s(26); radius: root.s(13)
                                                    color: root.surface2
                                                    border.color: root.surface1
                                                    border.width: 1

                                                    Rectangle {
                                                        readonly property int idx: { for (let i = 0; i < sor.options.length; i++) if (sor.options[i].v === sor.value) return i; return 0 }
                                                        width: parent.width / Math.max(2, sor.options.length); height: parent.height; radius: root.s(13)
                                                        color: root.mauve
                                                        x: idx * width
                                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        spacing: 0
                                                        Repeater {
                                                            model: sor.options
                                                            delegate: Item {
                                                                Layout.preferredWidth: sorSeg.width / Math.max(2, sor.options.length)
                                                                Layout.fillHeight: true
                                                                Text { anchors.centerIn: parent; text: modelData.l; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: sor.value === modelData.v ? root.base : root.subtext0 }
                                                                MouseArea { anchors.fill: parent; onClicked: sor.picked(modelData.v); cursorShape: Qt.PointingHandCursor }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    SwsOptRow {
                                        glyph: "󰍹"; title: "Auto workspace names"; sub: "Name + icon from the apps on each workspace. Hover: in the hover card. Always: active pill shows its name."
                                        value: root.setSmartWsAutoNames
                                        options: [ { v: "off", l: "Off" }, { v: "hover", l: "Hover" }, { v: "always", l: "Always" } ]
                                        onPicked: (v) => root.setSmartWsAutoNames = v
                                    }

                                    SwsOptRow {
                                        glyph: "󰆓"; title: "Layouts"; sub: "Save / restore window layouts from the workspace hover card. CLI: scripts/smartws.sh"
                                        value: root.setSmartWsLayoutsEnabled
                                        options: [ { v: true, l: "On" }, { v: false, l: "Off" } ]
                                        onPicked: (v) => root.setSmartWsLayoutsEnabled = v
                                    }

                                    SwsOptRow {
                                        glyph: "󰄬"; title: "Confirm restore"; sub: "Ask for a second click before restoring or deleting a layout."
                                        value: root.setSmartWsRestoreConfirm
                                        options: [ { v: true, l: "On" }, { v: false, l: "Off" } ]
                                        onPicked: (v) => root.setSmartWsRestoreConfirm = v
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(44)
                                        radius: root.s(8)
                                        color: Qt.alpha(root.surface0, 0.25)
                                        border.color: root.surface1
                                        border.width: 1
                                        Text {
                                            anchors.fill: parent; anchors.margins: root.s(12)
                                            verticalAlignment: Text.AlignVCenter
                                            wrapMode: Text.WordWrap
                                            text: "Rules (app class → category, names, colors) live in ~/.config/hypr/smartws/rules.json and hot-reload. Rename via: scripts/smartws.sh rename <ws> <name>"
                                            font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0
                                        }
                                    }
                                }
                            }
                        }
                    } // end section: smart workspaces


                    // --- section: hyprland polish ---
                    Item {
                        id: secHyprPolish
                        Layout.fillWidth: true
                        implicitHeight: secHyprPolishHeader.height + secHyprPolishBody.height
                        visible: root.secHyprPolishHasMatch

                        ColumnLayout {
                            width: parent.width
                            spacing: 0

                            Item {
                                id: secHyprPolishHeader
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(30)

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: root.s(10)

                                    Text {
                                        text: "▸"
                                        rotation: root.secHyprPolishExpanded ? 90 : 0
                                        font.pixelSize: root.s(11)
                                        color: root.subtext0
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                                    }
                                    Text { text: "󰖲"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: root.blue; Layout.alignment: Qt.AlignVCenter }
                                    Text { text: "HYPRLAND POLISH"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.surface1; Layout.alignment: Qt.AlignVCenter }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.secHyprPolishExpanded = !root.secHyprPolishExpanded
                                }
                            }

                            Item {
                                id: secHyprPolishBody
                                Layout.fillWidth: true
                                clip: true
                                Layout.preferredHeight: root.secHyprPolishExpanded ? (secHyprPolishContent.implicitHeight + root.s(15)) : 0
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

                                ColumnLayout {
                                    id: secHyprPolishContent
                                    y: root.s(15)
                                    width: parent.width
                                    spacing: root.s(15)

                                    component HyprChoiceRow: Rectangle {
                                        id: hcr
                                        property string glyph: ""
                                        property string title: ""
                                        property string sub: ""
                                        property string value: ""
                                        property var choices: []
                                        signal picked(string v)
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(60)
                                        radius: root.s(8)
                                        color: Qt.alpha(root.surface0, 0.4)
                                        border.color: root.surface1
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: root.s(15)
                                            spacing: root.s(20)

                                            Item {
                                                Layout.preferredWidth: root.s(30)
                                                Layout.alignment: Qt.AlignVCenter
                                                Text { anchors.centerIn: parent; text: hcr.glyph; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.blue }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: root.s(4)
                                                Text { text: hcr.title; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                                Text { text: hcr.sub; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                            }

                                            Item {
                                                Layout.preferredWidth: root.s(230)
                                                Layout.fillHeight: true

                                                Rectangle {
                                                    id: hcrSeg
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: root.s(230); height: root.s(26); radius: root.s(13)
                                                    color: root.surface2
                                                    border.color: root.surface1
                                                    border.width: 1

                                                    Rectangle {
                                                        property int idx: Math.max(0, hcr.choices.findIndex(c => c.v === hcr.value))
                                                        width: parent.width / Math.max(1, hcr.choices.length); height: parent.height; radius: root.s(13)
                                                        color: root.blue
                                                        x: idx * width
                                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        spacing: 0
                                                        Repeater {
                                                            model: hcr.choices
                                                            delegate: Item {
                                                                Layout.preferredWidth: hcrSeg.width / Math.max(1, hcr.choices.length)
                                                                Layout.fillHeight: true
                                                                Text { anchors.centerIn: parent; text: modelData.l; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: hcr.value === modelData.v ? root.base : root.subtext0 }
                                                                MouseArea { anchors.fill: parent; onClicked: hcr.picked(modelData.v); cursorShape: Qt.PointingHandCursor }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    HyprChoiceRow {
                                        glyph: "󰑮"; title: "Animations"; sub: "Window, workspace and layer motion. Subtle = quick and clean; Juicy = bouncier."
                                        choices: [ { v: "off", l: "Off" }, { v: "subtle", l: "Subtle" }, { v: "juicy", l: "Juicy" } ]
                                        value: root.setHyprPolishAnimations
                                        onPicked: (v) => root.setHyprPolishAnimations = v
                                    }

                                    HyprChoiceRow {
                                        glyph: "󰃟"; title: "Dim inactive windows"; sub: "Slightly darkens windows that aren't focused so the active one pops."
                                        choices: [ { v: "off", l: "Off" }, { v: "subtle", l: "Subtle" }, { v: "strong", l: "Strong" } ]
                                        value: root.setHyprPolishDimInactive
                                        onPicked: (v) => root.setHyprPolishDimInactive = v
                                    }

                                    HyprChoiceRow {
                                        glyph: "󰏘"; title: "Per-workspace border accent"; sub: "Active window border changes colour with the workspace. Smart WS = colour of the workspace's category."
                                        choices: [ { v: "off", l: "Off" }, { v: "palette", l: "Palette" }, { v: "smartws", l: "Smart WS" } ]
                                        value: root.setHyprPolishWsAccent
                                        onPicked: (v) => root.setHyprPolishWsAccent = v
                                    }

                                    HyprChoiceRow {
                                        glyph: "󰓅"; title: "Accent fade speed"; sub: "How fast the border colour cross-fades when you switch workspace."
                                        choices: [ { v: "fast", l: "Fast" }, { v: "normal", l: "Normal" }, { v: "slow", l: "Slow" } ]
                                        value: root.setHyprPolishWsAccentSpeed
                                        onPicked: (v) => root.setHyprPolishWsAccentSpeed = v
                                    }
                                }
                            }
                        }
                    } // end section: hyprland polish

                    // --- section: lock screen ---
                    Item {
                        id: secLock
                        Layout.fillWidth: true
                        implicitHeight: secLockHeader.height + secLockBody.height
                        visible: root.secLockHasMatch

                        ColumnLayout {
                            width: parent.width
                            spacing: 0

                            Item {
                                id: secLockHeader
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(30)

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: root.s(10)

                                    Text {
                                        text: "▸"
                                        rotation: root.secLockExpanded ? 90 : 0
                                        font.pixelSize: root.s(11)
                                        color: root.subtext0
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                                    }
                                    Text { text: "󰖲"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: root.blue; Layout.alignment: Qt.AlignVCenter }
                                    Text { text: "LOCK SCREEN"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.surface1; Layout.alignment: Qt.AlignVCenter }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.secLockExpanded = !root.secLockExpanded
                                }
                            }

                            Item {
                                id: secLockBody
                                Layout.fillWidth: true
                                clip: true
                                Layout.preferredHeight: root.secLockExpanded ? (secLockContent.implicitHeight + root.s(15)) : 0
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

                                ColumnLayout {
                                    id: secLockContent
                                    y: root.s(15)
                                    width: parent.width
                                    spacing: root.s(15)

                                    component LockChoiceRow: Rectangle {
                                        id: lcr
                                        property string glyph: ""
                                        property string title: ""
                                        property string sub: ""
                                        property string value: ""
                                        property var choices: []
                                        signal picked(string v)
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(60)
                                        radius: root.s(8)
                                        color: Qt.alpha(root.surface0, 0.4)
                                        border.color: root.surface1
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: root.s(15)
                                            spacing: root.s(20)

                                            Item {
                                                Layout.preferredWidth: root.s(30)
                                                Layout.alignment: Qt.AlignVCenter
                                                Text { anchors.centerIn: parent; text: lcr.glyph; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.blue }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: root.s(4)
                                                Text { text: lcr.title; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                                Text { text: lcr.sub; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                            }

                                            Item {
                                                Layout.preferredWidth: root.s(230)
                                                Layout.fillHeight: true

                                                Rectangle {
                                                    id: lcrSeg
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: root.s(230); height: root.s(26); radius: root.s(13)
                                                    color: root.surface2
                                                    border.color: root.surface1
                                                    border.width: 1

                                                    Rectangle {
                                                        property int idx: Math.max(0, lcr.choices.findIndex(c => c.v === lcr.value))
                                                        width: parent.width / Math.max(1, lcr.choices.length); height: parent.height; radius: root.s(13)
                                                        color: root.blue
                                                        x: idx * width
                                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        spacing: 0
                                                        Repeater {
                                                            model: lcr.choices
                                                            delegate: Item {
                                                                Layout.preferredWidth: lcrSeg.width / Math.max(1, lcr.choices.length)
                                                                Layout.fillHeight: true
                                                                Text { anchors.centerIn: parent; text: modelData.l; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(9); color: lcr.value === modelData.v ? root.base : root.subtext0 }
                                                                MouseArea { anchors.fill: parent; onClicked: lcr.picked(modelData.v); cursorShape: Qt.PointingHandCursor }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    LockChoiceRow {
                                        glyph: "󰌾"; title: "New lock screen"; sub: "Use the revamped lock screen. Off falls back to the classic one."
                                        choices: [ { v: "on", l: "On" }, { v: "off", l: "Off" } ]
                                        value: root.setLockStyleEnabled ? "on" : "off"
                                        onPicked: (v) => root.setLockStyleEnabled = (v === "on")
                                    }

                                    LockChoiceRow {
                                        glyph: "󰝚"; title: "Now playing card"; sub: "Album art, title and prev/play/next on the lock screen."
                                        choices: [ { v: "on", l: "On" }, { v: "off", l: "Off" } ]
                                        value: root.setLockShowMusic ? "on" : "off"
                                        onPicked: (v) => root.setLockShowMusic = (v === "on")
                                    }

                                    LockChoiceRow {
                                        glyph: "󰖐"; title: "Weather chip"; sub: "Current temperature and conditions under the clock."
                                        choices: [ { v: "on", l: "On" }, { v: "off", l: "Off" } ]
                                        value: root.setLockShowWeather ? "on" : "off"
                                        onPicked: (v) => root.setLockShowWeather = (v === "on")
                                    }

                                    LockChoiceRow {
                                        glyph: "󰂚"; title: "Notifications"; sub: "Off = hidden. Count = only how many. Full = app and message previews."
                                        choices: [ { v: "off", l: "Off" }, { v: "count", l: "Count" }, { v: "full", l: "Full" } ]
                                        value: root.setLockShowNotifs
                                        onPicked: (v) => root.setLockShowNotifs = v
                                    }

                                    LockChoiceRow {
                                        glyph: "󰚩"; title: "Claude welcome-back line"; sub: "What changed while you were away, from the resident."
                                        choices: [ { v: "on", l: "On" }, { v: "off", l: "Off" } ]
                                        value: root.setLockShowBrief ? "on" : "off"
                                        onPicked: (v) => root.setLockShowBrief = (v === "on")
                                    }

                                    LockChoiceRow {
                                        glyph: "󰂵"; title: "Wallpaper blur"; sub: "How blurred the backdrop wallpaper is."
                                        choices: [ { v: "low", l: "Low" }, { v: "mid", l: "Medium" }, { v: "high", l: "High" } ]
                                        value: root.setLockBlurStrength < 0.6 ? "low" : (root.setLockBlurStrength < 0.9 ? "mid" : "high")
                                        onPicked: (v) => root.setLockBlurStrength = (v === "low" ? 0.4 : (v === "mid" ? 0.8 : 1.0))
                                    }

                                    LockChoiceRow {
                                        glyph: "󰆾"; title: "Parallax drift"; sub: "Slow drifting motion of the backdrop."
                                        choices: [ { v: "on", l: "On" }, { v: "off", l: "Off" } ]
                                        value: root.setLockParallax ? "on" : "off"
                                        onPicked: (v) => root.setLockParallax = (v === "on")
                                    }

                                    LockChoiceRow {
                                        glyph: "󰸉"; title: "Ambient aurora"; sub: "Breathing glow and drifting motes. Occasional = only while idle on the clock view."
                                        choices: [ { v: "always", l: "Always" }, { v: "occasional", l: "Occasional" }, { v: "never", l: "Never" } ]
                                        value: root.setLockAmbientFx
                                        onPicked: (v) => root.setLockAmbientFx = v
                                    }

                                    LockChoiceRow {
                                        glyph: "󰥔"; title: "Clock style"; sub: "Big centered clock or a compact one."
                                        choices: [ { v: "big", l: "Big" }, { v: "compact", l: "Compact" } ]
                                        value: root.setLockClockStyle
                                        onPicked: (v) => root.setLockClockStyle = v
                                    }

                                    LockChoiceRow {
                                        glyph: "󰐥"; title: "Quick actions"; sub: "Mute, DND and brightness controls on the lock screen, usable without unlocking."
                                        choices: [ { v: "on", l: "On" }, { v: "off", l: "Off" } ]
                                        value: root.setLockShowQuickActions ? "on" : "off"
                                        onPicked: (v) => root.setLockShowQuickActions = (v === "on")
                                    }
                                }
                            }
                        }
                    } // end section: lock screen


                    // --- section: media & audio ---
                    Item {
                        id: secMedia
                        Layout.fillWidth: true
                        implicitHeight: secMediaHeader.height + secMediaBody.height
                        visible: root.secMediaHasMatch

                        ColumnLayout {
                            width: parent.width
                            spacing: 0

                            Item {
                                id: secMediaHeader
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(30)

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: root.s(10)

                                    Text {
                                        text: "▸"
                                        rotation: root.secMediaExpanded ? 90 : 0
                                        font.pixelSize: root.s(11)
                                        color: root.subtext0
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                                    }
                                    Text { text: "󰝚"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: root.mauve; Layout.alignment: Qt.AlignVCenter }
                                    Text { text: "MEDIA & AUDIO"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.surface1; Layout.alignment: Qt.AlignVCenter }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.secMediaExpanded = !root.secMediaExpanded
                                }
                            }

                            Item {
                                id: secMediaBody
                                Layout.fillWidth: true
                                clip: true
                                Layout.preferredHeight: root.secMediaExpanded ? (secMediaContent.implicitHeight + root.s(15)) : 0
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

                                ColumnLayout {
                                    id: secMediaContent
                                    y: root.s(15)
                                    width: parent.width
                                    spacing: root.s(15)

                        // Setting: Media Pill Visualizer
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(60)
                            radius: root.s(8)
                            color: Qt.alpha(root.surface0, 0.4)
                            border.color: root.surface1
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: root.s(15)
                                spacing: root.s(20)

                                Item {
                                    Layout.preferredWidth: settingsCol.iconColWidth
                                    Layout.alignment: Qt.AlignVCenter
                                    Text { anchors.centerIn: parent; text: "󰺸"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(4)
                                    Text { text: "Media Pill Visualizer"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                    Text { text: "Audio-reactive equalizer bars on the top bar's media pill."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                }

                                Item {
                                    Layout.preferredWidth: settingsCol.controlColWidth
                                    Layout.fillHeight: true

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: root.s(46); height: root.s(26); radius: root.s(13)
                                        color: root.setMediaVisualizerEnabled ? root.mauve : root.surface2
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        Rectangle {
                                            width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                            y: root.s(3)
                                            x: root.setMediaVisualizerEnabled ? root.s(23) : root.s(3)
                                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: root.setMediaVisualizerEnabled = !root.setMediaVisualizerEnabled; cursorShape: Qt.PointingHandCursor }
                                    }
                                }
                            }
                        }

                        // Setting: Media Pill Visualizer Mode
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(60)
                            radius: root.s(8)
                            color: Qt.alpha(root.surface0, 0.4)
                            border.color: root.surface1
                            border.width: 1
                            opacity: root.setMediaVisualizerEnabled ? 1.0 : 0.4
                            Behavior on opacity { NumberAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: root.s(15)
                                spacing: root.s(20)

                                Item {
                                    Layout.preferredWidth: settingsCol.iconColWidth
                                    Layout.alignment: Qt.AlignVCenter
                                    Text { anchors.centerIn: parent; text: "󰽉"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(4)
                                    Text { text: "Visualizer Mode"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                    Text { text: "Pulse: one overall level, faked per-bar spread. FFT: real per-band frequency spectrum."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                }

                                Item {
                                    Layout.preferredWidth: root.s(140)
                                    Layout.fillHeight: true

                                    Rectangle {
                                        id: vizModeSeg
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: root.s(140); height: root.s(26); radius: root.s(13)
                                        color: root.surface2
                                        border.color: root.surface1
                                        border.width: 1

                                        Rectangle {
                                            width: parent.width / 2; height: parent.height; radius: root.s(13)
                                            color: root.mauve
                                            x: root.setMediaVisualizerMode === "fft" ? parent.width / 2 : 0
                                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            spacing: 0
                                            Item {
                                                Layout.preferredWidth: vizModeSeg.width / 2
                                                Layout.fillHeight: true
                                                Text { anchors.centerIn: parent; text: "Pulse"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(10); color: root.setMediaVisualizerMode === "pulse" ? root.base : root.subtext0 }
                                                MouseArea { anchors.fill: parent; onClicked: root.setMediaVisualizerMode = "pulse"; cursorShape: Qt.PointingHandCursor }
                                            }
                                            Item {
                                                Layout.preferredWidth: vizModeSeg.width / 2
                                                Layout.fillHeight: true
                                                Text { anchors.centerIn: parent; text: "FFT"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(10); color: root.setMediaVisualizerMode === "fft" ? root.base : root.subtext0 }
                                                MouseArea { anchors.fill: parent; onClicked: root.setMediaVisualizerMode = "fft"; cursorShape: Qt.PointingHandCursor }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Setting: FFT Peak-Hold Line
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(60)
                            radius: root.s(8)
                            color: Qt.alpha(root.surface0, 0.4)
                            border.color: root.surface1
                            border.width: 1
                            opacity: (root.setMediaVisualizerEnabled && root.setMediaVisualizerMode === "fft") ? 1.0 : 0.4
                            Behavior on opacity { NumberAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: root.s(15)
                                spacing: root.s(20)

                                Item {
                                    Layout.preferredWidth: settingsCol.iconColWidth
                                    Layout.alignment: Qt.AlignVCenter
                                    Text { anchors.centerIn: parent; text: "󰽵"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(4)
                                    Text { text: "Peak-Hold Line"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                    Text { text: "The thin line above each FFT bar that snaps up and slowly falls back down."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                }

                                Item {
                                    Layout.preferredWidth: settingsCol.controlColWidth
                                    Layout.fillHeight: true

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: root.s(46); height: root.s(26); radius: root.s(13)
                                        color: root.setMediaVisualizerPeakHoldEnabled ? root.mauve : root.surface2
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        Rectangle {
                                            width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                            y: root.s(3)
                                            x: root.setMediaVisualizerPeakHoldEnabled ? root.s(23) : root.s(3)
                                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: root.setMediaVisualizerPeakHoldEnabled = !root.setMediaVisualizerPeakHoldEnabled; cursorShape: Qt.PointingHandCursor }
                                    }
                                }
                            }
                        }

                        // Setting: FFT Intensity (only meaningful in "fft" mode)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(60)
                            radius: root.s(8)
                            color: Qt.alpha(root.surface0, 0.4)
                            border.color: root.surface1
                            border.width: 1
                            opacity: (root.setMediaVisualizerEnabled && root.setMediaVisualizerMode === "fft") ? 1.0 : 0.4
                            Behavior on opacity { NumberAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: root.s(15)
                                spacing: root.s(20)

                                Item {
                                    Layout.preferredWidth: settingsCol.iconColWidth
                                    Layout.alignment: Qt.AlignVCenter
                                    Text { anchors.centerIn: parent; text: "󰥔"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(4)
                                    Text { text: "FFT Intensity"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                    Text { text: "Gain applied to the spectrum bars — turn up if quiet passages barely move, down if it's clipping flat."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                }

                                ColumnLayout {
                                    Layout.preferredWidth: root.s(160)
                                    spacing: root.s(2)
                                    Slider {
                                        id: fftIntensitySlider
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(18)
                                        from: 0.3; to: 2.5; stepSize: 0.1
                                        value: root.setTopBarFftIntensity
                                        onMoved: root.setTopBarFftIntensity = Math.round(value * 10) / 10
                                        background: Rectangle {
                                            x: fftIntensitySlider.leftPadding
                                            y: fftIntensitySlider.topPadding + fftIntensitySlider.availableHeight / 2 - height / 2
                                            width: fftIntensitySlider.availableWidth
                                            height: root.s(6)
                                            radius: root.s(3)
                                            color: root.surface2
                                            Rectangle {
                                                width: fftIntensitySlider.visualPosition * parent.width
                                                height: parent.height
                                                radius: root.s(3)
                                                color: root.mauve
                                            }
                                        }
                                        handle: Rectangle {
                                            x: fftIntensitySlider.leftPadding + fftIntensitySlider.visualPosition * (fftIntensitySlider.availableWidth - width)
                                            y: fftIntensitySlider.topPadding + fftIntensitySlider.availableHeight / 2 - height / 2
                                            width: root.s(14); height: root.s(14); radius: root.s(7)
                                            color: root.text
                                            scale: fftIntensitySlider.pressed ? 1.25 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                        }
                                    }
                                    Text { text: root.setTopBarFftIntensity.toFixed(1) + "x"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0; Layout.alignment: Qt.AlignRight }
                                }
                            }
                        }

                        // Setting: Visualizer Color Source
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(60)
                            radius: root.s(8)
                            color: Qt.alpha(root.surface0, 0.4)
                            border.color: root.surface1
                            border.width: 1
                            opacity: root.setMediaVisualizerEnabled ? 1.0 : 0.4
                            Behavior on opacity { NumberAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: root.s(15)
                                spacing: root.s(20)

                                Item {
                                    Layout.preferredWidth: settingsCol.iconColWidth
                                    Layout.alignment: Qt.AlignVCenter
                                    Text { anchors.centerIn: parent; text: "󰸌"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(4)
                                    Text { text: "Visualizer Color Source"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                    Text { text: "Which album-art colors drive the bars, BPM ring, and accent line. Always boosted for visibility on dark/muted covers."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                }

                                Item {
                                    Layout.preferredWidth: root.s(160)
                                    Layout.fillHeight: true

                                    Rectangle {
                                        id: colorSrcSeg
                                        // GuidePopup runs in Main.qml, a separate process from
                                        // TopBar.qml — no direct access to barWindow.musicData,
                                        // so this reads music_info.sh's own output file once to
                                        // show what "Dominant" vs "Vibrant" actually look like
                                        // for the currently playing track, instead of asking the
                                        // user to guess from two plain-text labels.
                                        property var previewColors: ({dominant: "", vibrant: ""})
                                        Component.onCompleted: colorPreviewProc.running = true
                                        Process {
                                            id: colorPreviewProc
                                            command: ["cat", "/tmp/music_info.json"]
                                            stdout: StdioCollector {
                                                onStreamFinished: {
                                                    try {
                                                        let d = JSON.parse(this.text.trim())
                                                        let dm = (d.grad || "").match(/#[0-9a-fA-F]{6}/)
                                                        let vb = (d.vibrantGrad || "").match(/#[0-9a-fA-F]{6}/)
                                                        colorSrcSeg.previewColors = {dominant: dm ? dm[0] : "", vibrant: vb ? vb[0] : ""}
                                                    } catch (e) {}
                                                }
                                            }
                                        }
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: root.s(160); height: root.s(26); radius: root.s(13)
                                        color: root.surface2
                                        border.color: root.surface1
                                        border.width: 1

                                        Rectangle {
                                            width: parent.width / 2; height: parent.height; radius: root.s(13)
                                            color: root.mauve
                                            x: root.setTopBarVisualizerColorSource === "vibrant" ? parent.width / 2 : 0
                                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            spacing: 0
                                            Item {
                                                Layout.preferredWidth: colorSrcSeg.width / 2
                                                Layout.fillHeight: true
                                                Row {
                                                    anchors.centerIn: parent
                                                    spacing: root.s(5)
                                                    Rectangle {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        visible: colorSrcSeg.previewColors.dominant !== ""
                                                        width: root.s(9); height: root.s(9); radius: root.s(4.5)
                                                        color: colorSrcSeg.previewColors.dominant || "transparent"
                                                        border.color: Qt.alpha(root.base, 0.4); border.width: 1
                                                    }
                                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Dominant"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(10); color: root.setTopBarVisualizerColorSource === "dominant" ? root.base : root.subtext0 }
                                                }
                                                MouseArea { anchors.fill: parent; onClicked: root.setTopBarVisualizerColorSource = "dominant"; cursorShape: Qt.PointingHandCursor }
                                            }
                                            Item {
                                                Layout.preferredWidth: colorSrcSeg.width / 2
                                                Layout.fillHeight: true
                                                Row {
                                                    anchors.centerIn: parent
                                                    spacing: root.s(5)
                                                    Rectangle {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        visible: colorSrcSeg.previewColors.vibrant !== ""
                                                        width: root.s(9); height: root.s(9); radius: root.s(4.5)
                                                        color: colorSrcSeg.previewColors.vibrant || "transparent"
                                                        border.color: Qt.alpha(root.base, 0.4); border.width: 1
                                                    }
                                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Vibrant"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(10); color: root.setTopBarVisualizerColorSource === "vibrant" ? root.base : root.subtext0 }
                                                }
                                                MouseArea { anchors.fill: parent; onClicked: root.setTopBarVisualizerColorSource = "vibrant"; cursorShape: Qt.PointingHandCursor }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Setting: Lyric Sync Offset
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(60)
                            radius: root.s(8)
                            color: Qt.alpha(root.surface0, 0.4)
                            border.color: root.surface1
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: root.s(15)
                                spacing: root.s(20)

                                Item {
                                    Layout.preferredWidth: settingsCol.iconColWidth
                                    Layout.alignment: Qt.AlignVCenter
                                    Text { anchors.centerIn: parent; text: "󰃭"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(4)
                                    Text { text: "Lyric Sync Offset"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                    Text { text: "Shifts the synced-lyrics highlight earlier (+) or later (-) relative to playback."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                }

                                ColumnLayout {
                                    Layout.preferredWidth: root.s(160)
                                    spacing: root.s(2)
                                    Slider {
                                        id: lyricsSyncOffsetSlider
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(18)
                                        from: -3.0; to: 3.0; stepSize: 0.1
                                        value: root.setLyricsSyncOffsetSec
                                        onMoved: root.setLyricsSyncOffsetSec = Math.round(value * 10) / 10
                                        background: Rectangle {
                                            x: lyricsSyncOffsetSlider.leftPadding
                                            y: lyricsSyncOffsetSlider.topPadding + lyricsSyncOffsetSlider.availableHeight / 2 - height / 2
                                            width: lyricsSyncOffsetSlider.availableWidth
                                            height: root.s(6)
                                            radius: root.s(3)
                                            color: root.surface2
                                            Rectangle {
                                                width: lyricsSyncOffsetSlider.visualPosition * parent.width
                                                height: parent.height
                                                radius: root.s(3)
                                                color: root.mauve
                                            }
                                        }
                                        handle: Rectangle {
                                            x: lyricsSyncOffsetSlider.leftPadding + lyricsSyncOffsetSlider.visualPosition * (lyricsSyncOffsetSlider.availableWidth - width)
                                            y: lyricsSyncOffsetSlider.topPadding + lyricsSyncOffsetSlider.availableHeight / 2 - height / 2
                                            width: root.s(14); height: root.s(14); radius: root.s(7)
                                            color: root.text
                                            scale: lyricsSyncOffsetSlider.pressed ? 1.25 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                        }
                                    }
                                    Text { text: (root.setLyricsSyncOffsetSec >= 0 ? "+" : "") + root.setLyricsSyncOffsetSec.toFixed(1) + "s"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0; Layout.alignment: Qt.AlignRight }
                                }
                            }
                        }

                        // Setting: BPM-Reactive Album Art Ring
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(60)
                            radius: root.s(8)
                            color: Qt.alpha(root.surface0, 0.4)
                            border.color: root.surface1
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: root.s(15)
                                spacing: root.s(20)

                                Item {
                                    Layout.preferredWidth: settingsCol.iconColWidth
                                    Layout.alignment: Qt.AlignVCenter
                                    Text { anchors.centerIn: parent; text: "󰸡"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(4)
                                    Text { text: "BPM-Reactive Album Art Ring"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                    Text { text: "Thin glow ring around the media pill's album art, pulsing in sync with the song's real BPM."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                }

                                Item {
                                    Layout.preferredWidth: settingsCol.controlColWidth
                                    Layout.fillHeight: true

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: root.s(46); height: root.s(26); radius: root.s(13)
                                        color: root.setTopBarBpmRingEnabled ? root.mauve : root.surface2
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        Rectangle {
                                            width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                            y: root.s(3)
                                            x: root.setTopBarBpmRingEnabled ? root.s(23) : root.s(3)
                                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: root.setTopBarBpmRingEnabled = !root.setTopBarBpmRingEnabled; cursorShape: Qt.PointingHandCursor }
                                    }
                                }
                            }
                        }

                        // Setting: Hyprland Border Pulse
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(60)
                            radius: root.s(8)
                            color: Qt.alpha(root.surface0, 0.4)
                            border.color: root.surface1
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: root.s(15)
                                spacing: root.s(20)

                                Item {
                                    Layout.preferredWidth: settingsCol.iconColWidth
                                    Layout.alignment: Qt.AlignVCenter
                                    Text { anchors.centerIn: parent; text: "󰉼"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(4)
                                    Text { text: "Hyprland Border Pulse"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                    Text { text: "Pulse the active window's border color when seeking or pausing Spotify. Doesn't affect the OSD."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                }

                                Item {
                                    Layout.preferredWidth: settingsCol.controlColWidth
                                    Layout.fillHeight: true

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: root.s(46); height: root.s(26); radius: root.s(13)
                                        color: root.setHyprlandBorderPulseEnabled ? root.mauve : root.surface2
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        Rectangle {
                                            width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                            y: root.s(3)
                                            x: root.setHyprlandBorderPulseEnabled ? root.s(23) : root.s(3)
                                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: root.setHyprlandBorderPulseEnabled = !root.setHyprlandBorderPulseEnabled; cursorShape: Qt.PointingHandCursor }
                                    }
                                }
                            }
                        }
                                }
                            }
                        }
                    } // end section: media & audio


                    // --- section: calendar & schedule ---
                    Item {
                        id: secCalendar
                        Layout.fillWidth: true
                        implicitHeight: secCalendarHeader.height + secCalendarBody.height
                        visible: root.secCalendarHasMatch

                        ColumnLayout {
                            width: parent.width
                            spacing: 0

                            Item {
                                id: secCalendarHeader
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(30)

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: root.s(10)

                                    Text {
                                        text: "▸"
                                        rotation: root.secCalendarExpanded ? 90 : 0
                                        font.pixelSize: root.s(11)
                                        color: root.subtext0
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                                    }
                                    Text { text: "󰃭"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: root.mauve; Layout.alignment: Qt.AlignVCenter }
                                    Text { text: "CALENDAR & SCHEDULE"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.surface1; Layout.alignment: Qt.AlignVCenter }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.secCalendarExpanded = !root.secCalendarExpanded
                                }
                            }

                            Item {
                                id: secCalendarBody
                                Layout.fillWidth: true
                                clip: true
                                Layout.preferredHeight: root.secCalendarExpanded ? (secCalendarContent.implicitHeight + root.s(15)) : 0
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

                                ColumnLayout {
                                    id: secCalendarContent
                                    y: root.s(15)
                                    width: parent.width
                                    spacing: root.s(15)

                    // Setting: Show Calendar Pill
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Show Calendar Pill in Top Bar"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Display current or upcoming event next to the clock."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setShowCalendarPill ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setShowCalendarPill ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setShowCalendarPill = !root.setShowCalendarPill; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Calendar Refresh Interval
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰔟"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.blue }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Calendar Refresh Interval"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "How often the calendar daemon polls Google Calendar (minutes)."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                RowLayout {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(10)

                                    Rectangle {
                                        width: root.s(30); height: root.s(30); radius: root.s(6)
                                        color: calMinusMa.pressed ? root.surface2 : root.surface1
                                        Text { anchors.centerIn: parent; text: "-"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.text }
                                        MouseArea { id: calMinusMa; anchors.fill: parent; onClicked: root.setCalendarRefreshMinutes = Math.max(1, root.setCalendarRefreshMinutes - 1) }
                                    }

                                    Text {
                                        text: root.setCalendarRefreshMinutes + "m"
                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(14)
                                        color: root.text
                                        Layout.minimumWidth: root.s(40)
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    Rectangle {
                                        width: root.s(30); height: root.s(30); radius: root.s(6)
                                        color: calPlusMa.pressed ? root.surface2 : root.surface1
                                        Text { anchors.centerIn: parent; text: "+"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.text }
                                        MouseArea { id: calPlusMa; anchors.fill: parent; onClicked: root.setCalendarRefreshMinutes = Math.min(60, root.setCalendarRefreshMinutes + 1) }
                                    }
                                }
                            }
                        }
                    }

                                }
                            }
                        }
                    } // end section: calendar & schedule


                    // --- section: claude agent ---
                    Item {
                        id: secClaude
                        Layout.fillWidth: true
                        implicitHeight: secClaudeHeader.height + secClaudeBody.height
                        visible: root.secClaudeHasMatch

                        ColumnLayout {
                            width: parent.width
                            spacing: 0

                            Item {
                                id: secClaudeHeader
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(30)

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: root.s(10)

                                    Text {
                                        text: "▸"
                                        rotation: root.secClaudeExpanded ? 90 : 0
                                        font.pixelSize: root.s(11)
                                        color: root.subtext0
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                                    }
                                    Text { text: "󰚩"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: root.mauve; Layout.alignment: Qt.AlignVCenter }
                                    Text { text: "CLAUDE AGENT"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.surface1; Layout.alignment: Qt.AlignVCenter }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.secClaudeExpanded = !root.secClaudeExpanded
                                }
                            }

                            Item {
                                id: secClaudeBody
                                Layout.fillWidth: true
                                clip: true
                                Layout.preferredHeight: root.secClaudeExpanded ? (secClaudeContent.implicitHeight + root.s(15)) : 0
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

                                ColumnLayout {
                                    id: secClaudeContent
                                    y: root.s(15)
                                    width: parent.width
                                    spacing: root.s(15)

                    // Setting: Resident Voice Nudges
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰭹"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.pink }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Resident Voice Nudges"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Phrase ambient nudges with Haiku. Off falls back to raw template text."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setResidentVoiceNudges ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setResidentVoiceNudges ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setResidentVoiceNudges = !root.setResidentVoiceNudges; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Resident Notification Strictness
                    Rectangle {
                        id: strictnessCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        property var opts: [
                            { id: "quiet",     label: "quiet" },
                            { id: "balanced",  label: "balanced" },
                            { id: "proactive", label: "proactive" }
                        ]

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰂚"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.peach }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Resident Notification Strictness"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "How readily the resident proposes a task card from a desktop notification."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(6)
                                Repeater {
                                    model: strictnessCard.opts
                                    delegate: Rectangle {
                                        required property var modelData
                                        property bool sel: modelData.id === root.setResidentStrictness
                                        Layout.preferredHeight: root.s(28)
                                        Layout.preferredWidth: slbl.implicitWidth + root.s(18)
                                        radius: root.s(7)
                                        color: sel ? root.peach : (sMa.containsMouse ? root.surface2 : root.surface1)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text { id: slbl; anchors.centerIn: parent; text: modelData.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: parent.sel ? root.base : root.subtext0 }
                                        MouseArea { id: sMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setResidentStrictness = modelData.id }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Morning Brief
                    Rectangle {
                        id: briefCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        property var opts: [
                            { id: "off", label: "off" },
                            { id: "text", label: "card" },
                            { id: "spoken", label: "spoken" }
                        ]

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰃭"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.yellow }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Morning Brief"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Daily brief when you first sit down: off, a card, or a card plus spoken."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(6)
                                Repeater {
                                    model: briefCard.opts
                                    delegate: Rectangle {
                                        required property var modelData
                                        property bool sel: modelData.id === root.setResidentMorningBrief
                                        Layout.preferredHeight: root.s(28)
                                        Layout.preferredWidth: l_briefCard.implicitWidth + root.s(18)
                                        radius: root.s(7)
                                        color: sel ? root.peach : (m_briefCard.containsMouse ? root.surface2 : root.surface1)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text { id: l_briefCard; anchors.centerIn: parent; text: modelData.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: parent.sel ? root.base : root.subtext0 }
                                        MouseArea { id: m_briefCard; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setResidentMorningBrief = modelData.id }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Brief Time Window
                    Rectangle {
                        id: briefTimeCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        property var opts: [
                            { id: "05:00-11:00", label: "morning" },
                            { id: "05:00-14:00", label: "till 2pm" },
                            { id: "00:00-23:59", label: "any time" }
                        ]

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰥔"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.teal }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Brief Time Window"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "When the morning brief may fire."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(6)
                                Repeater {
                                    model: briefTimeCard.opts
                                    delegate: Rectangle {
                                        required property var modelData
                                        property bool sel: modelData.id === root.setResidentBriefTime
                                        Layout.preferredHeight: root.s(28)
                                        Layout.preferredWidth: l_briefTimeCard.implicitWidth + root.s(18)
                                        radius: root.s(7)
                                        color: sel ? root.peach : (m_briefTimeCard.containsMouse ? root.surface2 : root.surface1)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text { id: l_briefTimeCard; anchors.centerIn: parent; text: modelData.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: parent.sel ? root.base : root.subtext0 }
                                        MouseArea { id: m_briefTimeCard; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setResidentBriefTime = modelData.id }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Catch-up On Return
                    Rectangle {
                        id: catchUpCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        property var opts: [
                            { id: true, label: "on" },
                            { id: false, label: "off" }
                        ]

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰑐"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.blue }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Catch-up On Return"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Summarize what happened while you were away or locked (also feeds the lock screen)."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(6)
                                Repeater {
                                    model: catchUpCard.opts
                                    delegate: Rectangle {
                                        required property var modelData
                                        property bool sel: modelData.id === root.setResidentCatchUp
                                        Layout.preferredHeight: root.s(28)
                                        Layout.preferredWidth: l_catchUpCard.implicitWidth + root.s(18)
                                        radius: root.s(7)
                                        color: sel ? root.peach : (m_catchUpCard.containsMouse ? root.surface2 : root.surface1)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text { id: l_catchUpCard; anchors.centerIn: parent; text: modelData.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: parent.sel ? root.base : root.subtext0 }
                                        MouseArea { id: m_catchUpCard; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setResidentCatchUp = modelData.id }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Proactive Fixes
                    Rectangle {
                        id: fixesCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        property var opts: [
                            { id: "suggest", label: "suggest" },
                            { id: "off", label: "off" }
                        ]

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰁨"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.green }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Proactive Fixes"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Offer one-click fixes for full disks, memory hogs, failed services and updates. Nothing runs until you click."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(6)
                                Repeater {
                                    model: fixesCard.opts
                                    delegate: Rectangle {
                                        required property var modelData
                                        property bool sel: modelData.id === root.setResidentProactiveFixes
                                        Layout.preferredHeight: root.s(28)
                                        Layout.preferredWidth: l_fixesCard.implicitWidth + root.s(18)
                                        radius: root.s(7)
                                        color: sel ? root.peach : (m_fixesCard.containsMouse ? root.surface2 : root.surface1)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text { id: l_fixesCard; anchors.centerIn: parent; text: modelData.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: parent.sel ? root.base : root.subtext0 }
                                        MouseArea { id: m_fixesCard; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setResidentProactiveFixes = modelData.id }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Clipboard Aware
                    Rectangle {
                        id: clipAwareCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        property var opts: [
                            { id: true, label: "on" },
                            { id: false, label: "off" }
                        ]

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰅍"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Clipboard Aware"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Offer to explain a copied error, or open/copy-as-link a copied URL. Rate-limited, never more than one card every ~12 minutes."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(6)
                                Repeater {
                                    model: clipAwareCard.opts
                                    delegate: Rectangle {
                                        required property var modelData
                                        property bool sel: modelData.id === root.setResidentClipboardAware
                                        Layout.preferredHeight: root.s(28)
                                        Layout.preferredWidth: l_clipAwareCard.implicitWidth + root.s(18)
                                        radius: root.s(7)
                                        color: sel ? root.peach : (m_clipAwareCard.containsMouse ? root.surface2 : root.surface1)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text { id: l_clipAwareCard; anchors.centerIn: parent; text: modelData.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: parent.sel ? root.base : root.subtext0 }
                                        MouseArea { id: m_clipAwareCard; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setResidentClipboardAware = modelData.id }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Eco Notice
                    Rectangle {
                        id: ecoNoticeCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        property var opts: [
                            { id: true, label: "on" },
                            { id: false, label: "off" }
                        ]

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰤄"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.sapphire }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Eco Freeze Notice"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Card when eco mode freezes an app, with a jump-to-workspace / thaw-all action. Throttling stays silent, only freezes surface."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(6)
                                Repeater {
                                    model: ecoNoticeCard.opts
                                    delegate: Rectangle {
                                        required property var modelData
                                        property bool sel: modelData.id === root.setResidentEcoNotice
                                        Layout.preferredHeight: root.s(28)
                                        Layout.preferredWidth: l_ecoNoticeCard.implicitWidth + root.s(18)
                                        radius: root.s(7)
                                        color: sel ? root.peach : (m_ecoNoticeCard.containsMouse ? root.surface2 : root.surface1)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text { id: l_ecoNoticeCard; anchors.centerIn: parent; text: modelData.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: parent.sel ? root.base : root.subtext0 }
                                        MouseArea { id: m_ecoNoticeCard; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setResidentEcoNotice = modelData.id }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Device Alerts
                    Rectangle {
                        id: deviceAlertsCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        property var opts: [
                            { id: true, label: "on" },
                            { id: false, label: "off" }
                        ]

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰇖"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.teal }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Device Alerts"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Low-key card when a USB device or Bluetooth device connects, or wifi switches networks."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(6)
                                Repeater {
                                    model: deviceAlertsCard.opts
                                    delegate: Rectangle {
                                        required property var modelData
                                        property bool sel: modelData.id === root.setResidentDeviceAlerts
                                        Layout.preferredHeight: root.s(28)
                                        Layout.preferredWidth: l_deviceAlertsCard.implicitWidth + root.s(18)
                                        radius: root.s(7)
                                        color: sel ? root.peach : (m_deviceAlertsCard.containsMouse ? root.surface2 : root.surface1)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text { id: l_deviceAlertsCard; anchors.centerIn: parent; text: modelData.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: parent.sel ? root.base : root.subtext0 }
                                        MouseArea { id: m_deviceAlertsCard; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setResidentDeviceAlerts = modelData.id }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Battery Alert Style
                    Rectangle {
                        id: batteryAlertStyleCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        property var opts: [
                            { id: "integrated", label: "integrated" },
                            { id: "popup", label: "popup" }
                        ]

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰁹"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.peach }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Battery Alert Style"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Integrated flashes the topbar battery pill at 30/20/10%; popup shows the old full-screen alert card."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(6)
                                Repeater {
                                    model: batteryAlertStyleCard.opts
                                    delegate: Rectangle {
                                        required property var modelData
                                        property bool sel: modelData.id === root.setBatteryAlertStyle
                                        Layout.preferredHeight: root.s(28)
                                        Layout.preferredWidth: l_batteryAlertStyleCard.implicitWidth + root.s(18)
                                        radius: root.s(7)
                                        color: sel ? root.peach : (m_batteryAlertStyleCard.containsMouse ? root.surface2 : root.surface1)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text { id: l_batteryAlertStyleCard; anchors.centerIn: parent; text: modelData.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: parent.sel ? root.base : root.subtext0 }
                                        MouseArea { id: m_batteryAlertStyleCard; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setBatteryAlertStyle = modelData.id }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Resident Card Hold
                    Rectangle {
                        id: cardHoldCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        property var opts: [
                            { id: "auto", label: "auto" },
                            { id: "short", label: "short" },
                            { id: "until-dismissed", label: "until dismissed" }
                        ]

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰔟"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Resident Card Hold"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "How long resident cards stay under the middle pill."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(6)
                                Repeater {
                                    model: cardHoldCard.opts
                                    delegate: Rectangle {
                                        required property var modelData
                                        property bool sel: modelData.id === root.setResidentCardHoldMode
                                        Layout.preferredHeight: root.s(28)
                                        Layout.preferredWidth: l_cardHoldCard.implicitWidth + root.s(18)
                                        radius: root.s(7)
                                        color: sel ? root.peach : (m_cardHoldCard.containsMouse ? root.surface2 : root.surface1)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text { id: l_cardHoldCard; anchors.centerIn: parent; text: modelData.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: parent.sel ? root.base : root.subtext0 }
                                        MouseArea { id: m_cardHoldCard; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setResidentCardHoldMode = modelData.id }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Resident Song Reaction Chance
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰝚"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.green }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Song Reaction Chance"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Odds the resident comments on a track change. It can still skip if it has nothing to say."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                RowLayout {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(10)

                                    Rectangle {
                                        width: root.s(30); height: root.s(30); radius: root.s(6)
                                        color: songMinusMa.pressed ? root.surface2 : root.surface1
                                        Text { anchors.centerIn: parent; text: "-"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.text }
                                        MouseArea { id: songMinusMa; anchors.fill: parent; onClicked: root.setResidentSongReactChance = Math.max(0, (root.setResidentSongReactChance - 0.05).toFixed(2)) }
                                    }

                                    Text {
                                        text: Math.round(root.setResidentSongReactChance * 100) + "%"
                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(14)
                                        color: root.text
                                        Layout.minimumWidth: root.s(40)
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    Rectangle {
                                        width: root.s(30); height: root.s(30); radius: root.s(6)
                                        color: songPlusMa.pressed ? root.surface2 : root.surface1
                                        Text { anchors.centerIn: parent; text: "+"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.text }
                                        MouseArea { id: songPlusMa; anchors.fill: parent; onClicked: root.setResidentSongReactChance = Math.min(1, (root.setResidentSongReactChance + 0.05).toFixed(2)) }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Passive Nudge Auto-Dismiss
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰦒"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.peach }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Passive Nudge Auto-Dismiss"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Seconds before action-less dot nudges (wallpaper/song musings) clear themselves."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                RowLayout {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(10)

                                    Rectangle {
                                        width: root.s(30); height: root.s(30); radius: root.s(6)
                                        color: expireMinusMa.pressed ? root.surface2 : root.surface1
                                        Text { anchors.centerIn: parent; text: "-"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.text }
                                        MouseArea { id: expireMinusMa; anchors.fill: parent; onClicked: root.setResidentPassiveExpireSecs = Math.max(10, root.setResidentPassiveExpireSecs - 10) }
                                    }

                                    Text {
                                        text: root.setResidentPassiveExpireSecs + "s"
                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(14)
                                        color: root.text
                                        Layout.minimumWidth: root.s(40)
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    Rectangle {
                                        width: root.s(30); height: root.s(30); radius: root.s(6)
                                        color: expirePlusMa.pressed ? root.surface2 : root.surface1
                                        Text { anchors.centerIn: parent; text: "+"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.text }
                                        MouseArea { id: expirePlusMa; anchors.fill: parent; onClicked: root.setResidentPassiveExpireSecs = Math.min(300, root.setResidentPassiveExpireSecs + 10) }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Pill Takeover
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰦕"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Pill Takeover"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Let resident findings briefly tint the relevant bar pill (battery, wifi, cpu, net, uptime, volume) instead of only a card."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setResidentPillTakeoverEnabled ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setResidentPillTakeoverEnabled ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setResidentPillTakeoverEnabled = !root.setResidentPillTakeoverEnabled; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Layout Suggestions
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰕮"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.blue }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Layout Suggestions"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Notice recurring manual smart-workspace layout restores and propose restoring them (never auto-applies)."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setResidentLayoutSuggestions ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setResidentLayoutSuggestions ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setResidentLayoutSuggestions = !root.setResidentLayoutSuggestions; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                                }
                            }
                        }
                    } // end section: claude agent


                    // --- section: pinned cards & chat ---
                    Item {
                        id: secPinned
                        Layout.fillWidth: true
                        implicitHeight: secPinnedHeader.height + secPinnedBody.height
                        visible: root.secPinnedHasMatch

                        ColumnLayout {
                            width: parent.width
                            spacing: 0

                            Item {
                                id: secPinnedHeader
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(30)

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: root.s(10)

                                    Text {
                                        text: "▸"
                                        rotation: root.secPinnedExpanded ? 90 : 0
                                        font.pixelSize: root.s(11)
                                        color: root.subtext0
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                                    }
                                    Text { text: "󰮯"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: root.mauve; Layout.alignment: Qt.AlignVCenter }
                                    Text { text: "PINNED CARDS & CHAT"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.surface1; Layout.alignment: Qt.AlignVCenter }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.secPinnedExpanded = !root.secPinnedExpanded
                                }
                            }

                            Item {
                                id: secPinnedBody
                                Layout.fillWidth: true
                                clip: true
                                Layout.preferredHeight: root.secPinnedExpanded ? (secPinnedContent.implicitHeight + root.s(15)) : 0
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

                                ColumnLayout {
                                    id: secPinnedContent
                                    y: root.s(15)
                                    width: parent.width
                                    spacing: root.s(15)

                    // Setting: Pinned Card Snap Grid
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰗀"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.blue }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Pinned Card Snap Grid"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Pixel grid pinned cards snap to when dragged or resized on the side panel."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                RowLayout {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(10)

                                    Rectangle {
                                        width: root.s(30); height: root.s(30); radius: root.s(6)
                                        color: gridMinusMa.pressed ? root.surface2 : root.surface1
                                        Text { anchors.centerIn: parent; text: "-"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.text }
                                        MouseArea { id: gridMinusMa; anchors.fill: parent; onClicked: root.setPinGridSize = Math.max(4, root.setPinGridSize - 4) }
                                    }

                                    Text {
                                        text: root.setPinGridSize + "px"
                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(14)
                                        color: root.text
                                        Layout.minimumWidth: root.s(40)
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    Rectangle {
                                        width: root.s(30); height: root.s(30); radius: root.s(6)
                                        color: gridPlusMa.pressed ? root.surface2 : root.surface1
                                        Text { anchors.centerIn: parent; text: "+"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.text }
                                        MouseArea { id: gridPlusMa; anchors.fill: parent; onClicked: root.setPinGridSize = Math.min(64, root.setPinGridSize + 4) }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Pinned Card Clutter Cap
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰕰"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.green }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Pinned Card Clutter Cap"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Auto-shrinks older pinned cards to chips once a board has too many to stay glanceable."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setPinClutterCap ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setPinClutterCap ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setPinClutterCap = !root.setPinClutterCap; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Pinned Card Compact Default
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰮯"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.sapphire }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Pinned Card Compact Default"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "New pins start as a small glance chip instead of the full card. Click a chip to expand it."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setPinCompactMode ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setPinCompactMode ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setPinCompactMode = !root.setPinCompactMode; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Chat Thinking Style
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰚩"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Chat Thinking Style"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "While Claude thinks: a sweeping shimmer line, or three pulsing dots."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(6)
                                    Repeater {
                                        model: [ { v: "shimmer", t: "Shimmer" }, { v: "dots", t: "Dots" } ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            property bool sel: root.setChatThinkingStyle === modelData.v
                                            width: segLbl.implicitWidth + root.s(18); height: root.s(26)
                                            radius: root.s(8)
                                            color: sel ? root.mauve : root.surface2
                                            Behavior on color { ColorAnimation { duration: 160 } }
                                            Text {
                                                id: segLbl
                                                anchors.centerIn: parent
                                                text: modelData.t
                                                font.family: "JetBrains Mono"; font.pixelSize: root.s(11); font.weight: Font.Bold
                                                color: sel ? root.base : root.subtext0
                                            }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setChatThinkingStyle = modelData.v }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Card Entrance Animations
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󱥚"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.green }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Card Animations"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Entrance fades, count-ups, bar fills, hover lift and tap feedback on cards. Turn off for instant, static cards."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setCardAnimations ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setCardAnimations ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setCardAnimations = !root.setCardAnimations; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Card Depth & Shadows
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰕪"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.sapphire }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Card Depth & Shadows"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Layered drop shadow and accent glow that lift cards off the background. Off for a flat look."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(46); height: root.s(26); radius: root.s(13)
                                    color: root.setCardDepth ? root.mauve : root.surface2
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Rectangle {
                                        width: root.s(20); height: root.s(20); radius: root.s(10); color: root.base
                                        y: root.s(3)
                                        x: root.setCardDepth ? root.s(23) : root.s(3)
                                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.setCardDepth = !root.setCardDepth; cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }

                    // Setting: Card Accent Color
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰉦"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.peach }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Card Accent Color"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Border, glow and chip tint for cards and pins."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true
                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(8)
                                    Repeater {
                                        model: [ { v: "blue", c: root.blue }, { v: "mauve", c: root.mauve }, { v: "green", c: root.green }, { v: "peach", c: root.peach }, { v: "teal", c: root.teal } ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            property bool sel: root.setCardAccent === modelData.v
                                            width: root.s(26); height: root.s(26); radius: root.s(13)
                                            color: modelData.c
                                            border.width: sel ? root.s(3) : 0
                                            border.color: root.text
                                            scale: sel ? 1.0 : 0.82
                                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setCardAccent = modelData.v }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Agenda Card Default Filter
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰃭"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.green }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Agenda Card Default"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "What an agenda card shows when Claude doesn't specify: calendar events, tasks, or both."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true
                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(6)
                                    Repeater {
                                        model: [ { v: "all", t: "All" }, { v: "events", t: "Events" }, { v: "tasks", t: "Tasks" } ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            property bool sel: root.setAgendaDefaultFilter === modelData.v
                                            width: agLbl.implicitWidth + root.s(18); height: root.s(26)
                                            radius: root.s(8)
                                            color: sel ? root.mauve : root.surface2
                                            Behavior on color { ColorAnimation { duration: 160 } }
                                            Text {
                                                id: agLbl
                                                anchors.centerIn: parent
                                                text: modelData.t
                                                font.family: "JetBrains Mono"; font.pixelSize: root.s(11); font.weight: Font.Bold
                                                color: sel ? root.base : root.subtext0
                                            }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setAgendaDefaultFilter = modelData.v }
                                        }
                                    }
                                }
                            }
                        }
                    }

                                }
                            }
                        }
                    } // end section: pinned cards & chat


                    // --- section: widget style ---
                    Item {
                        id: secWidget
                        Layout.fillWidth: true
                        implicitHeight: secWidgetHeader.height + secWidgetBody.height
                        visible: root.secWidgetHasMatch

                        ColumnLayout {
                            width: parent.width
                            spacing: 0

                            Item {
                                id: secWidgetHeader
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(30)

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: root.s(10)

                                    Text {
                                        text: "▸"
                                        rotation: root.secWidgetExpanded ? 90 : 0
                                        font.pixelSize: root.s(11)
                                        color: root.subtext0
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                                    }
                                    Text { text: "󰉦"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: root.mauve; Layout.alignment: Qt.AlignVCenter }
                                    Text { text: "WIDGET STYLE"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.surface1; Layout.alignment: Qt.AlignVCenter }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.secWidgetExpanded = !root.secWidgetExpanded
                                }
                            }

                            Item {
                                id: secWidgetBody
                                Layout.fillWidth: true
                                clip: true
                                Layout.preferredHeight: root.secWidgetExpanded ? (secWidgetContent.implicitHeight + root.s(15)) : 0
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

                                ColumnLayout {
                                    id: secWidgetContent
                                    y: root.s(15)
                                    width: parent.width
                                    spacing: root.s(15)

                    Repeater {
                        model: [
                            { key: "monitors",            name: "MONITORS",      icon: "󰍹", desc: "Choose the legacy or revamped monitors widget." },
                            { key: "focustime",           name: "FOCUS TIME",    icon: "󰔟", desc: "Choose the legacy or revamped focus timer widget." },
                            { key: "wallpaper",           name: "WALLPAPER",     icon: "󰉦", desc: "Choose the legacy or revamped wallpaper picker." },
                            { key: "notifications_center", name: "NOTIF CENTER", icon: "󰂚", desc: "Legacy or revamped notification center panel." },
                            { key: "volume",               name: "VOLUME",       icon: "󰕾", desc: "Legacy or revamped volume mixer." },
                            { key: "workspaces",           name: "WORKSPACES",   icon: "󰍺", desc: "Legacy or revamped workspace overview." }
                        ]
                        delegate: Rectangle {
                            id: wCard
                            required property var modelData
                            property string wkey: modelData.key
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(60)
                            radius: root.s(8)
                            color: Qt.alpha(root.surface0, 0.4)
                            border.color: root.surface1
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: root.s(15)
                                spacing: root.s(20)

                                Item {
                                    Layout.preferredWidth: settingsCol.iconColWidth
                                    Layout.alignment: Qt.AlignVCenter
                                    Text { anchors.centerIn: parent; text: wCard.modelData.icon; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(4)
                                    Text { text: wCard.modelData.name; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.subtext1 }
                                    Text { text: wCard.modelData.desc; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                }

                                RowLayout {
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: root.s(10)
                                    Repeater {
                                        model: [ { v: "legacy", t: "Legacy" }, { v: "revamp", t: "Revamp" } ]
                                        delegate: Item {
                                            id: pillItem
                                            required property var modelData
                                            property bool sel: root.styleFor(wCard.wkey) === modelData.v
                                            property bool isRevamp: modelData.v === "revamp"
                                            Layout.preferredHeight: root.s(30)
                                            Layout.preferredWidth: pillRect.width

                                            Rectangle {
                                                anchors.fill: pillRect
                                                anchors.margins: -root.s(3)
                                                radius: root.s(11)
                                                color: root.mauve
                                                opacity: pillItem.sel ? 0.18 : 0.0
                                                Behavior on opacity { NumberAnimation { duration: 220 } }
                                            }

                                            Rectangle {
                                                id: pillRect
                                                anchors.centerIn: parent
                                                height: root.s(30)
                                                width: pillLbl.implicitWidth + root.s(24)
                                                radius: root.s(8)
                                                scale: pillMa.pressed ? 0.93 : 1.0
                                                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }
                                                color: pillItem.sel ? root.mauve : (pillMa.containsMouse ? Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.1) : "transparent")
                                                border.width: pillItem.sel ? 0 : 1
                                                border.color: root.surface2
                                                Behavior on color { ColorAnimation { duration: 150 } }

                                                Text {
                                                    id: pillLbl
                                                    anchors.centerIn: parent
                                                    text: pillItem.modelData.t
                                                    font.family: "JetBrains Mono"
                                                    font.weight: pillItem.sel ? Font.Bold : Font.Medium
                                                    font.pixelSize: root.s(11)
                                                    color: pillItem.sel ? root.base : root.subtext1
                                                }

                                                MouseArea {
                                                    id: pillMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setStyleFor(wCard.wkey, pillItem.modelData.v)
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
                        }
                    } // end section: widget style


                    // --- section: display ---
                    Item {
                        id: secDisplay
                        Layout.fillWidth: true
                        implicitHeight: secDisplayHeader.height + secDisplayBody.height
                        visible: root.secDisplayHasMatch

                        ColumnLayout {
                            width: parent.width
                            spacing: 0

                            Item {
                                id: secDisplayHeader
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(30)

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: root.s(10)

                                    Text {
                                        text: "▸"
                                        rotation: root.secDisplayExpanded ? 90 : 0
                                        font.pixelSize: root.s(11)
                                        color: root.subtext0
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                                    }
                                    Text { text: "󰍹"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: root.mauve; Layout.alignment: Qt.AlignVCenter }
                                    Text { text: "DISPLAY"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.surface1; Layout.alignment: Qt.AlignVCenter }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.secDisplayExpanded = !root.secDisplayExpanded
                                }
                            }

                            Item {
                                id: secDisplayBody
                                Layout.fillWidth: true
                                clip: true
                                Layout.preferredHeight: root.secDisplayExpanded ? (secDisplayContent.implicitHeight + root.s(15)) : 0
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

                                ColumnLayout {
                                    id: secDisplayContent
                                    y: root.s(15)
                                    width: parent.width
                                    spacing: root.s(15)

                    // Setting: Night Light Schedule
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰖔"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.sapphire }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Night Light Schedule"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Warm-filter window (24h HH:MM) used when night_light is turned on."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                RowLayout {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(8)

                                    Rectangle {
                                        width: root.s(56); height: root.s(28); radius: root.s(6)
                                        color: root.surface0; border.color: root.surface2; border.width: 1
                                        TextInput {
                                            anchors.fill: parent; anchors.margins: root.s(6)
                                            verticalAlignment: TextInput.AlignVCenter; horizontalAlignment: TextInput.AlignHCenter
                                            text: root.setNightLightStart
                                            font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.text
                                            selectByMouse: true
                                            onTextChanged: root.setNightLightStart = text
                                        }
                                    }
                                    Text { text: "→"; font.family: "JetBrains Mono"; color: root.subtext0; font.pixelSize: root.s(12) }
                                    Rectangle {
                                        width: root.s(56); height: root.s(28); radius: root.s(6)
                                        color: root.surface0; border.color: root.surface2; border.width: 1
                                        TextInput {
                                            anchors.fill: parent; anchors.margins: root.s(6)
                                            verticalAlignment: TextInput.AlignVCenter; horizontalAlignment: TextInput.AlignHCenter
                                            text: root.setNightLightEnd
                                            font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.text
                                            selectByMouse: true
                                            onTextChanged: root.setNightLightEnd = text
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Night Light Temperature
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰜭"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.yellow }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Night Light Warm Temp"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Color temperature (Kelvin) used during the warm window. Lower = warmer."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: settingsCol.controlColWidth
                                Layout.fillHeight: true

                                RowLayout {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(10)

                                    Rectangle {
                                        width: root.s(30); height: root.s(30); radius: root.s(6)
                                        color: tempMinusMa.pressed ? root.surface2 : root.surface1
                                        Text { anchors.centerIn: parent; text: "-"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.text }
                                        MouseArea { id: tempMinusMa; anchors.fill: parent; onClicked: root.setNightLightTemp = Math.max(2500, root.setNightLightTemp - 250) }
                                    }

                                    Text {
                                        text: root.setNightLightTemp + "K"
                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(14)
                                        color: root.text
                                        Layout.minimumWidth: root.s(50)
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    Rectangle {
                                        width: root.s(30); height: root.s(30); radius: root.s(6)
                                        color: tempPlusMa.pressed ? root.surface2 : root.surface1
                                        Text { anchors.centerIn: parent; text: "+"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.text }
                                        MouseArea { id: tempPlusMa; anchors.fill: parent; onClicked: root.setNightLightTemp = Math.min(6500, root.setNightLightTemp + 250) }
                                    }
                                }
                            }
                        }
                    }

                                }
                            }
                        }
                    } // end section: display


                    // --- section: accounts ---
                    Item {
                        id: secAccounts
                        Layout.fillWidth: true
                        implicitHeight: secAccountsHeader.height + secAccountsBody.height
                        visible: root.secAccountsHasMatch

                        ColumnLayout {
                            width: parent.width
                            spacing: 0

                            Item {
                                id: secAccountsHeader
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(30)

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: root.s(10)

                                    Text {
                                        text: "▸"
                                        rotation: root.secAccountsExpanded ? 90 : 0
                                        font.pixelSize: root.s(11)
                                        color: root.subtext0
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                                    }
                                    Text { text: "󰌋"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: root.mauve; Layout.alignment: Qt.AlignVCenter }
                                    Text { text: "ACCOUNTS & MODEL"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.surface1; Layout.alignment: Qt.AlignVCenter }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.secAccountsExpanded = !root.secAccountsExpanded
                                }
                            }

                            Item {
                                id: secAccountsBody
                                Layout.fillWidth: true
                                clip: true
                                Layout.preferredHeight: root.secAccountsExpanded ? (secAccountsContent.implicitHeight + root.s(15)) : 0
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

                                ColumnLayout {
                                    id: secAccountsContent
                                    y: root.s(15)
                                    width: parent.width
                                    spacing: root.s(15)

                    // Setting: Claude Accounts & API Keys
                    Rectangle {
                        id: acctCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: acctInner.implicitHeight + root.s(30)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        property string activeId: ""

                        ListModel { id: acctModel }

                        Process {
                            id: acctListProc
                            command: ["bash", "-c", "~/.config/hypr/scripts/anthropic_acct.sh list; echo '@@@'; ~/.config/hypr/scripts/anthropic_acct.sh active"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    acctModel.clear();
                                    let parts = this.text.split("@@@");
                                    let lines = (parts[0] || "").trim().split("\n");
                                    for (let i = 0; i < lines.length; i++) {
                                        if (!lines[i].trim()) continue;
                                        try {
                                            let e = JSON.parse(lines[i]);
                                            acctModel.append({ eid: e.id, elabel: e.label || e.id, etype: e.type || "account", eemail: e.email || "", edisabled: e.disabled === true });
                                        } catch (err) {}
                                    }
                                    acctCard.activeId = (parts[1] || "").trim();
                                }
                            }
                        }
                        Process { id: acctActionProc; onExited: acctListProc.running = true }
                        Component.onCompleted: acctListProc.running = true
                        function action(a) { acctActionProc.command = ["bash", "-c", "~/.config/hypr/scripts/anthropic_acct.sh " + a]; acctActionProc.running = false; acctActionProc.running = true; }

                        ColumnLayout {
                            id: acctInner
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(10)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(12)
                                Text { text: "󰀄"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(2)
                                    Text { text: "Claude Accounts & API Keys"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                    Text { text: "Cycle with SUPER+ALT+A. Account = subscription billing · key = API / proxy."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; Layout.fillWidth: true; elide: Text.ElideRight }
                                }
                                Rectangle {
                                    Layout.preferredWidth: saveRow.width + root.s(20); Layout.preferredHeight: root.s(30)
                                    radius: root.s(7)
                                    color: acctSaveMa.containsMouse ? root.green : Qt.alpha(root.green, 0.22)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Row {
                                        id: saveRow; anchors.centerIn: parent; spacing: root.s(6)
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: "󰆓"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(13); color: acctSaveMa.containsMouse ? root.base : root.green }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Save current"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: acctSaveMa.containsMouse ? root.base : root.green }
                                    }
                                    MouseArea { id: acctSaveMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: acctCard.action("save-current") }
                                }
                            }

                            Repeater {
                                model: acctModel
                                delegate: Rectangle {
                                    required property string eid
                                    required property string elabel
                                    required property string etype
                                    required property string eemail
                                    required property bool edisabled
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(40)
                                    radius: root.s(6)
                                    property bool isActive: eid === acctCard.activeId
                                    opacity: edisabled ? 0.45 : 1.0
                                    color: isActive ? Qt.alpha(root.mauve, 0.14) : Qt.alpha(root.surface0, 0.5)
                                    border.width: 1
                                    border.color: isActive ? Qt.alpha(root.mauve, 0.4) : root.surface1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: root.s(12); anchors.rightMargin: root.s(8)
                                        spacing: root.s(10)
                                        Text { text: etype === "key" ? "󰌆" : "󰀄"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15); color: isActive ? root.mauve : root.subtext0 }
                                        Text { text: elabel; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12); color: root.text }
                                        Text { text: eemail; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0; Layout.fillWidth: true; elide: Text.ElideRight }
                                        Text { visible: isActive; text: "active"; font.family: "JetBrains Mono"; font.pixelSize: root.s(9); color: root.mauve }
                                        Rectangle {
                                            visible: !edisabled
                                            Layout.preferredWidth: root.s(42); Layout.preferredHeight: root.s(24); radius: root.s(6)
                                            color: useMa.containsMouse ? root.surface2 : root.surface1
                                            Text { anchors.centerIn: parent; text: "use"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.text }
                                            MouseArea { id: useMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: acctCard.action("set " + eid) }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: root.s(24); Layout.preferredHeight: root.s(24); radius: root.s(6)
                                            color: disMa.containsMouse ? Qt.alpha(root.peach, 0.25) : "transparent"
                                            Text { anchors.centerIn: parent; text: edisabled ? "󰈉" : "󰈈"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(12); color: root.peach }
                                            MouseArea { id: disMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: acctCard.action((edisabled ? "enable " : "disable ") + eid) }
                                        }
                                        Rectangle {
                                            visible: etype !== "key"
                                            Layout.preferredWidth: root.s(24); Layout.preferredHeight: root.s(24); radius: root.s(6)
                                            color: upMa.containsMouse ? Qt.alpha(root.blue, 0.25) : "transparent"
                                            Text { anchors.centerIn: parent; text: "󰑐"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(12); color: root.blue }
                                            MouseArea { id: upMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: acctCard.action("update " + eid) }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: root.s(24); Layout.preferredHeight: root.s(24); radius: root.s(6)
                                            color: rmMa.containsMouse ? Qt.alpha(root.red, 0.25) : "transparent"
                                            Text { anchors.centerIn: parent; text: "✕"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.red }
                                            MouseArea { id: rmMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: acctCard.action("remove " + eid) }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: root.s(4)
                                spacing: root.s(8)
                                Rectangle {
                                    Layout.preferredWidth: root.s(110); Layout.preferredHeight: root.s(38)
                                    radius: root.s(6); color: root.surface0
                                    border.width: 1; border.color: keyLabelIn.activeFocus ? root.blue : root.surface2
                                    Behavior on border.color { ColorAnimation { duration: 150 } }
                                    TextInput {
                                        id: keyLabelIn; anchors.fill: parent; anchors.margins: root.s(10)
                                        verticalAlignment: TextInput.AlignVCenter; font.family: "JetBrains Mono"; font.pixelSize: root.s(12)
                                        color: root.text; clip: true; selectByMouse: true
                                        Text { text: "Label"; color: root.subtext0; visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true; Layout.preferredHeight: root.s(38)
                                    radius: root.s(6); color: root.surface0
                                    border.width: 1; border.color: keyValIn.activeFocus ? root.blue : root.surface2
                                    Behavior on border.color { ColorAnimation { duration: 150 } }
                                    TextInput {
                                        id: keyValIn; anchors.fill: parent; anchors.margins: root.s(10)
                                        verticalAlignment: TextInput.AlignVCenter; font.family: "JetBrains Mono"; font.pixelSize: root.s(12)
                                        color: root.text; clip: true; selectByMouse: true; echoMode: TextInput.Password; passwordCharacter: "•"
                                        Text { text: "API key (sk-… / fe_…)"; color: root.subtext0; visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                }
                                Rectangle {
                                    Layout.preferredWidth: root.s(150); Layout.preferredHeight: root.s(38)
                                    radius: root.s(6); color: root.surface0
                                    border.width: 1; border.color: keyUrlIn.activeFocus ? root.blue : root.surface2
                                    Behavior on border.color { ColorAnimation { duration: 150 } }
                                    TextInput {
                                        id: keyUrlIn; anchors.fill: parent; anchors.margins: root.s(10)
                                        verticalAlignment: TextInput.AlignVCenter; font.family: "JetBrains Mono"; font.pixelSize: root.s(11)
                                        color: root.text; clip: true; selectByMouse: true
                                        Text { text: "base url (optional)"; color: root.subtext0; visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                }
                                Rectangle {
                                    Layout.preferredWidth: root.s(56); Layout.preferredHeight: root.s(38); radius: root.s(6)
                                    color: addMa.containsMouse ? root.blue : Qt.alpha(root.blue, 0.22)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text { anchors.centerIn: parent; text: "Add"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12); color: addMa.containsMouse ? root.base : root.blue }
                                    MouseArea {
                                        id: addMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (keyValIn.text.trim() === "") return;
                                            let lbl = keyLabelIn.text.trim() || "Key";
                                            let id = "key" + Date.now();
                                            acctCard.action("add-key-b64 " + id + " " + Qt.btoa(lbl) + " " + Qt.btoa(keyValIn.text.trim()) + " " + Qt.btoa(keyUrlIn.text.trim()));
                                            keyLabelIn.text = ""; keyValIn.text = ""; keyUrlIn.text = "";
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Setting: Default Claude Model (widget)
                    Rectangle {
                        id: modelCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(60)
                        radius: root.s(8)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.surface1
                        border.width: 1

                        property string current: ""
                        // mirror the widget: z.ai (GLM) source swaps the model list to GLM ids
                        property bool isGlm: false
                        property var opts: isGlm ? [
                            { id: "",            label: "default" },
                            { id: "glm-5.2",     label: "glm-5.2" },
                            { id: "glm-4.6",     label: "glm-4.6" },
                            { id: "glm-4.5-air", label: "air" }
                        ] : [
                            { id: "",       label: "default" },
                            { id: "opus",   label: "opus" },
                            { id: "sonnet", label: "sonnet" },
                            { id: "haiku",  label: "haiku" },
                            { id: "fable",  label: "fable" }
                        ]

                        Process {
                            id: modelReadProc
                            command: ["bash", "-c", "cat ~/.cache/quickshell/claude/model 2>/dev/null"]
                            stdout: StdioCollector { onStreamFinished: modelCard.current = this.text.trim() }
                        }
                        Process {
                            id: glmDetectProc
                            command: ["bash", "-c", "id=$(cat ~/.cache/quickshell/claude/auth 2>/dev/null || echo auto); jq -r --arg id \"$id\" '.entries[]|select(.id==$id)|.base_url' ~/.config/anthropic/accounts.json 2>/dev/null"]
                            stdout: StdioCollector { onStreamFinished: modelCard.isGlm = this.text.indexOf("z.ai") >= 0 }
                        }
                        Process { id: modelWriteProc }

                        // disabled models: kept in the list but greyed + unselectable.
                        // Stored as a JSON array of ids; right-click a pill to toggle.
                        property var disabledModels: []
                        Process {
                            id: disModelReadProc
                            command: ["bash", "-c", "cat ~/.cache/quickshell/claude/disabled_models.json 2>/dev/null || echo '[]'"]
                            stdout: StdioCollector { onStreamFinished: { try { modelCard.disabledModels = JSON.parse(this.text.trim() || "[]"); } catch (e) { modelCard.disabledModels = []; } } }
                        }
                        Process { id: disModelWriteProc }
                        function isModelDisabled(id) { return modelCard.disabledModels.indexOf(id) >= 0; }
                        function toggleModelDisabled(id) {
                            if (id === "") return; // never disable 'default'
                            let arr = modelCard.disabledModels.slice();
                            let i = arr.indexOf(id);
                            if (i >= 0) arr.splice(i, 1); else arr.push(id);
                            modelCard.disabledModels = arr;
                            disModelWriteProc.command = ["python3", "-c",
                                "import sys,os,json; os.makedirs(os.path.dirname(sys.argv[1]),exist_ok=True); open(sys.argv[1],'w').write(sys.argv[2])",
                                Quickshell.env("HOME") + "/.cache/quickshell/claude/disabled_models.json", JSON.stringify(arr)];
                            disModelWriteProc.running = false; disModelWriteProc.running = true;
                            if (modelCard.current === id) modelCard.setModel("");
                        }

                        Component.onCompleted: { modelReadProc.running = true; glmDetectProc.running = true; disModelReadProc.running = true }
                        function setModel(id) {
                            if (modelCard.isModelDisabled(id)) return;
                            modelCard.current = id;
                            modelWriteProc.command = ["python3", "-c",
                                "import sys,os; os.makedirs(os.path.dirname(sys.argv[1]),exist_ok=True); open(sys.argv[1],'w').write(sys.argv[2])",
                                Quickshell.env("HOME") + "/.cache/quickshell/claude/model", id];
                            modelWriteProc.running = false; modelWriteProc.running = true;
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(15)
                            spacing: root.s(20)

                            Item {
                                Layout.preferredWidth: settingsCol.iconColWidth
                                Layout.alignment: Qt.AlignVCenter
                                Text { anchors.centerIn: parent; text: "󰚩"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.blue }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(4)
                                Text { text: "Default Claude Model"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Text { text: "Model the query widget launches with. Override per-chat with /model."; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(6)
                                Repeater {
                                    model: modelCard.opts
                                    delegate: Rectangle {
                                        required property var modelData
                                        property bool sel: modelData.id === modelCard.current
                                        property bool disabledModel: modelCard.isModelDisabled(modelData.id)
                                        Layout.preferredHeight: root.s(28)
                                        Layout.preferredWidth: mlbl.implicitWidth + root.s(18)
                                        radius: root.s(7)
                                        opacity: disabledModel ? 0.4 : 1.0
                                        color: sel ? root.blue : (mMa.containsMouse ? root.surface2 : root.surface1)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text { id: mlbl; anchors.centerIn: parent; text: modelData.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: parent.sel ? root.base : root.subtext0; font.strikeout: parent.disabledModel }
                                        MouseArea {
                                            id: mMa; anchors.fill: parent; hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            cursorShape: Qt.PointingHandCursor
                                            ToolTip.visible: containsMouse && modelData.id !== ""
                                            ToolTip.delay: 600
                                            ToolTip.text: parent.disabledModel ? "right-click to enable" : "right-click to disable"
                                            onClicked: (mouse) => {
                                                if (mouse.button === Qt.RightButton) modelCard.toggleModelDisabled(modelData.id);
                                                else modelCard.setModel(modelData.id);
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
                    } // end section: accounts


                }
                }
            }
            }
        }

            // ------------------------------------------
            // TAB 2: RESOURCES
            // ------------------------------------------
            Loader {
                id: tab2Loader
                anchors.fill: parent
                active: root.loadedTabs["2"] === true
                asynchronous: true
                onLoaded: root.tabReady(2)
                sourceComponent: Component {
            Item {
                anchors.fill: parent
                visible: root.currentTab === 2
                opacity: visible ? 1.0 : 0.0
                property real slideY: visible ? 0 : root.s(10)
                
                Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                transform: Translate { y: slideY }
                Behavior on opacity { NumberAnimation { duration: 250 } }

                ScrollView {
                    id: resourcesScroll
                    anchors.fill: parent
                    contentWidth: availableWidth
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    Component.onCompleted: scrollRestoreTimer2.start()
                    Timer { id: scrollRestoreTimer2; interval: 120; onTriggered: resourcesScroll.contentItem.contentY = root.savedScrollY[2] || 0 }
                    Connections {
                        target: resourcesScroll.contentItem
                        function onContentYChanged() { root.savedScrollY[2] = resourcesScroll.contentItem.contentY; scrollSaveTimer.restart() }
                    }

                    ColumnLayout {
                        width: parent.width
                        spacing: root.s(15)

                        // --- Integrated System Info Grid ---
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: sysInfoCol.implicitHeight + root.s(40)
                            radius: root.s(16)
                            color: Qt.alpha(root.surface0, 0.4)
                            border.color: root.surface1
                            border.width: 1

                            ColumnLayout {
                                id: sysInfoCol
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: root.s(20)
                                spacing: root.s(15)

                                RowLayout {
                                    Text { text: "󰇄"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18); color: root.mauve }
                                    Text { text: "System Specifications"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.text }
                                }
                                Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.surface1, 0.5) }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 2
                                    rowSpacing: root.s(15)
                                    columnSpacing: root.s(30)
                                    
                                    RowLayout { 
                                        spacing: root.s(12)
                                        Rectangle { width: root.s(36); height: root.s(36); radius: root.s(8); color: Qt.alpha(root.blue, 0.15); Text { anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18); color: root.blue } } 
                                        ColumnLayout { spacing: root.s(2); Text { text: "Operating System"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 } Text { text: root.sysOS; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text } } 
                                    }
                                    RowLayout { 
                                        spacing: root.s(12)
                                        Rectangle { width: root.s(36); height: root.s(36); radius: root.s(8); color: Qt.alpha(root.peach, 0.15); Text { anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18); color: root.peach } } 
                                        ColumnLayout { spacing: root.s(2); Text { text: "Kernel Version"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 } Text { text: root.sysKernel; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text } } 
                                    }
                                    RowLayout { 
                                        spacing: root.s(12)
                                        Rectangle { width: root.s(36); height: root.s(36); radius: root.s(8); color: Qt.alpha(root.green, 0.15); Text { anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18); color: root.green } } 
                                        ColumnLayout { spacing: root.s(2); Text { text: "Active User"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 } Text { text: root.sysUser + "@" + root.sysHost; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text } } 
                                    }
                                    RowLayout { 
                                        spacing: root.s(12)
                                        Rectangle { width: root.s(36); height: root.s(36); radius: root.s(8); color: Qt.alpha(root.yellow, 0.15); Text { anchors.centerIn: parent; text: "󰔟"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18); color: root.yellow } } 
                                        ColumnLayout { spacing: root.s(2); Text { text: "System Uptime"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 } Text { text: root.sysUptime; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text } } 
                                    }
                                    RowLayout { 
                                        Layout.columnSpan: 2
                                        spacing: root.s(12)
                                        Rectangle { width: root.s(36); height: root.s(36); radius: root.s(8); color: Qt.alpha(root.sapphire, 0.15); Text { anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18); color: root.sapphire } } 
                                        ColumnLayout { spacing: root.s(2); Text { text: "Processor (CPU)"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 } Text { text: root.sysCPU; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text; elide: Text.ElideRight; Layout.maximumWidth: root.s(450) } } 
                                    }
                                    RowLayout { 
                                        Layout.columnSpan: 2
                                        spacing: root.s(12)
                                        Rectangle { width: root.s(36); height: root.s(36); radius: root.s(8); color: Qt.alpha(root.red, 0.15); Text { anchors.centerIn: parent; text: "󰢮"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18); color: root.red } } 
                                        ColumnLayout { spacing: root.s(2); Text { text: "Graphics (GPU)"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 } Text { text: root.sysGPU; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text; elide: Text.ElideRight; Layout.maximumWidth: root.s(450) } } 
                                    }
                                }
                            }
                        }

                        // --- Circular Gauges ---
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 3
                            columnSpacing: root.s(15)
                            
                            Repeater {
                                model: 3
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(200)
                                    radius: root.s(16)
                                    property real targetValue: index === 0 ? root.cpuUsage : (index === 1 ? root.memUsage : Math.min(root.sysTemp, 100))
                                    property string txtValue: index === 0 ? root.cpuUsage + "%" : (index === 1 ? root.memUsage + "%" : (root.sysTemp > 0 ? root.sysTemp + "°C" : "N/A"))
                                    property string cKey: index === 0 ? "sapphire" : (index === 1 ? "peach" : "red")
                                    property string tTitle: index === 0 ? "CPU LOAD" : (index === 1 ? "MEMORY" : "THERMALS")
                                    property string iIcon: index === 0 ? "" : (index === 1 ? "󰍛" : "")

                                    color: Qt.alpha(root.surface0, 0.4)
                                    border.color: Qt.alpha(root[cKey], 0.2)
                                    border.width: 1
                                    clip: true

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: root.s(15)
                                        Item {
                                            Layout.alignment: Qt.AlignHCenter
                                            width: root.s(130)
                                            height: root.s(130)
                                            Canvas {
                                                id: gaugeCanvas
                                                anchors.fill: parent
                                                property real animatedValue: targetValue
                                                Behavior on animatedValue { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }
                                                onAnimatedValueChanged: requestPaint()
                                                onPaint: {
                                                    var ctx = getContext("2d"); 
                                                    ctx.clearRect(0, 0, width, height);
                                                    var cx = width / 2; 
                                                    var cy = height / 2; 
                                                    var r = width / 2 - root.s(8);
                                                    
                                                    ctx.beginPath(); 
                                                    ctx.arc(cx, cy, r, 0, 2 * Math.PI); 
                                                    ctx.lineWidth = root.s(12); 
                                                    ctx.strokeStyle = Qt.alpha(root.surface1, 0.4); 
                                                    ctx.stroke();
                                                    
                                                    var start = -Math.PI / 2; 
                                                    var end = start + (animatedValue / 100) * 2 * Math.PI;
                                                    
                                                    ctx.beginPath(); 
                                                    ctx.arc(cx, cy, r, start, end); 
                                                    ctx.lineWidth = root.s(12); 
                                                    ctx.strokeStyle = root[cKey]; 
                                                    ctx.lineCap = "round"; 
                                                    ctx.stroke();
                                                }
                                            }
                                            ColumnLayout { 
                                                anchors.centerIn: parent
                                                spacing: root.s(2)
                                                Text { text: iIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(26); color: root[cKey]; Layout.alignment: Qt.AlignHCenter } 
                                                Text { text: txtValue; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(18); color: root.text; Layout.alignment: Qt.AlignHCenter } 
                                            }
                                        }
                                        Text { text: tTitle; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignHCenter }
                                    }
                                }
                            }
                        }

                        // --- Consolidated Storage Block ---
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(80)
                            radius: root.s(16)
                            color: Qt.alpha(root.surface0, 0.4)
                            border.color: root.surface1
                            border.width: 1
                            
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: root.s(20)
                                spacing: root.s(10)
                                
                                RowLayout {
                                    Text { text: "󰋊"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(16); color: root.mauve }
                                    Text { text: "Storage"; font.family: "JetBrains Mono"; font.weight: Font.Bold; color: root.text; font.pixelSize: root.s(14) }
                                    Item { Layout.fillWidth: true }
                                    Text { 
                                        text: root.formatBytes(root.globalUsedDisk) + " / " + root.formatBytes(root.globalTotalDisk) + " (" + (root.globalTotalDisk > 0 ? Math.round((root.globalUsedDisk / root.globalTotalDisk) * 100) : 0) + "%)"
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: root.s(12)
                                        color: root.subtext0 
                                    }
                                }
                                
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(8)
                                    radius: root.s(4)
                                    color: Qt.alpha(root.surface1, 0.4)
                                    clip: true
                                    
                                    Rectangle { 
                                        height: parent.height
                                        radius: root.s(4)
                                        width: root.globalTotalDisk > 0 ? parent.width * (root.globalUsedDisk / root.globalTotalDisk) : 0
                                        color: root.mauve
                                        Behavior on width { NumberAnimation { duration: 1000; easing.type: Easing.OutQuart } } 
                                    }
                                }
                            }
                        }

                        // --- OOKLA Inspired Network Dashboard ---
                        Rectangle {
                            id: netContainer
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(160)
                            radius: root.s(16)
                            color: Qt.alpha(root.surface0, 0.4)
                            border.color: root.surface1
                            border.width: 1
                            clip: true

                            Rectangle {
                                id: goBtn
                                width: root.s(90)
                                height: root.s(90)
                                radius: root.s(45)
                                x: root.netState === 0 ? (parent.width - width) / 2 : root.s(30)
                                y: (parent.height - height) / 2
                                color: Qt.alpha(root.blue, 0.15)
                                border.color: (root.netState > 0 && root.netState < 4) ? root.blue : root.surface2
                                border.width: root.s(2)
                                Behavior on x { NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width
                                    height: parent.height
                                    radius: parent.radius
                                    color: "transparent"
                                    border.color: root.sapphire
                                    border.width: root.s(2)
                                    opacity: 0
                                    SequentialAnimation on opacity { 
                                        running: root.netState > 0 && root.netState < 4
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1; to: 0; duration: 1000 } 
                                    }
                                    SequentialAnimation on scale { 
                                        running: root.netState > 0 && root.netState < 4
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1.0; to: 1.5; duration: 1000 } 
                                    }
                                }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: root.s(2)
                                    Item {
                                        Layout.alignment: Qt.AlignHCenter
                                        width: root.s(32)
                                        height: root.s(32)
                                        Text { 
                                            anchors.centerIn: parent
                                            text: root.netState === 0 ? "GO" : (root.netState === 4 ? "󰑐" : "󰑮")
                                            font.family: root.netState === 0 ? "JetBrains Mono" : "Iosevka Nerd Font"
                                            font.weight: Font.Black
                                            font.pixelSize: root.netState === 0 ? root.s(28) : root.s(32)
                                            color: (root.netState > 0 && root.netState < 4) ? root.blue : root.text
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            transformOrigin: Item.Center
                                            RotationAnimation on rotation { 
                                                running: root.netState > 0 && root.netState < 4
                                                loops: Animation.Infinite
                                                from: 0
                                                to: 360
                                                duration: 1000 
                                            } 
                                        }
                                    }
                                    Text { 
                                        text: "SPEEDTEST"
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Bold
                                        font.pixelSize: root.s(9)
                                        color: root.subtext0
                                        visible: root.netState === 0
                                        Layout.alignment: Qt.AlignHCenter 
                                    }
                                }
                                MouseArea { 
                                    anchors.fill: parent
                                    hoverEnabled: root.netState === 0 || root.netState === 4
                                    cursorShape: (root.netState === 0 || root.netState === 4) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: { 
                                        if (root.netState === 0 || root.netState === 4) { 
                                            root.netState = 1; 
                                            root.displayPing = 0; 
                                            root.finalPing = 0; 
                                            root.displayDown = 0; 
                                            root.finalDown = 0; 
                                            root.displayUp = 0; 
                                            root.finalUp = 0; 
                                            pingProc.running = false; 
                                            pingProc.running = true; 
                                        } 
                                    } 
                                }
                            }

                            RowLayout {
                                id: netResults
                                x: root.netState === 0 ? parent.width : root.s(150)
                                y: (parent.height - height) / 2
                                opacity: root.netState === 0 ? 0 : 1
                                spacing: root.s(40)
                                Behavior on x { NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 1.05 } }
                                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }

                                ColumnLayout {
                                    spacing: root.s(4)
                                    opacity: root.netState >= 1 ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 400 } }
                                    RowLayout { 
                                        spacing: root.s(6)
                                        Item { 
                                            Layout.preferredWidth: root.s(16)
                                            Layout.preferredHeight: root.s(16)
                                            Text { anchors.centerIn: parent; text: "󰅸"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(16); color: root.peach } 
                                        } 
                                        Text { text: "PING"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12); color: root.subtext0 } 
                                    }
                                    RowLayout { 
                                        spacing: root.s(4)
                                        Text { text: root.netState >= 2 ? root.displayPing.toFixed(0) : "..."; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(28); color: root.text } 
                                        Text { text: "ms"; font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: root.s(5); visible: root.netState >= 2 } 
                                    }
                                }
                                
                                ColumnLayout {
                                    spacing: root.s(4)
                                    opacity: root.netState >= 2 ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 400 } }
                                    RowLayout { 
                                        spacing: root.s(6)
                                        Item { 
                                            Layout.preferredWidth: root.s(16)
                                            Layout.preferredHeight: root.s(16)
                                            Text { anchors.centerIn: parent; text: "󰇚"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(16); color: root.green } 
                                        } 
                                        Text { text: "DOWNLOAD"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12); color: root.subtext0 } 
                                    }
                                    RowLayout { 
                                        spacing: root.s(4)
                                        Text { text: root.netState >= 3 ? root.displayDown.toFixed(1) : "..."; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(28); color: root.green } 
                                        Text { text: "Mbps"; font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: root.s(5); visible: root.netState >= 3 } 
                                    }
                                }
                                
                                ColumnLayout {
                                    spacing: root.s(4)
                                    opacity: root.netState >= 3 ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 400 } }
                                    RowLayout { 
                                        spacing: root.s(6)
                                        Item { 
                                            Layout.preferredWidth: root.s(16)
                                            Layout.preferredHeight: root.s(16)
                                            Text { anchors.centerIn: parent; text: "󰕒"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(16); color: root.mauve } 
                                        } 
                                        Text { text: "UPLOAD"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12); color: root.subtext0 } 
                                    }
                                    RowLayout { 
                                        spacing: root.s(4)
                                        Text { text: root.netState >= 4 ? root.displayUp.toFixed(1) : "..."; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(28); color: root.mauve } 
                                        Text { text: "Mbps"; font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: root.subtext0; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: root.s(5); visible: root.netState >= 4 } 
                                    }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }
            }
        }

            // ------------------------------------------
            // TAB 3: MODULES
            // ------------------------------------------
            Loader {
                id: tab3Loader
                anchors.fill: parent
                active: root.loadedTabs["3"] === true
                asynchronous: true
                onLoaded: root.tabReady(3)
                sourceComponent: Component {
            Item {
                readonly property var x_modulesList: modulesList
                anchors.fill: parent
                visible: root.currentTab === 3
                opacity: visible ? 1.0 : 0.0
                property real slideY: visible ? 0 : root.s(10)
                
                Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                transform: Translate { y: slideY }
                Behavior on opacity { NumberAnimation { duration: 250 } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(20)
                    spacing: root.s(20)

                    RowLayout {
                        Layout.fillWidth: true
                        
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: root.s(4)
                            Text { text: "Interactive Modules"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(28); color: root.text }
                            Text { text: "Use arrow keys or select below to preview. Double-click or press Enter to toggle."; font.family: "JetBrains Mono"; font.pixelSize: root.s(13); color: root.subtext0 }
                        }
                        
                        Item { Layout.fillWidth: true } 
                        
                        Rectangle {
                            Layout.preferredWidth: root.s(110)
                            Layout.preferredHeight: root.s(44)
                            radius: root.s(22)
                            color: launchMa.containsMouse ? Qt.alpha(root.ambientBlue, 0.9) : Qt.alpha(root.ambientBlue, 0.7)
                            border.color: root.ambientBlue
                            border.width: 1
                            scale: launchMa.pressed ? 0.95 : (launchMa.containsMouse ? 1.05 : 1.0)
                            
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            
                            RowLayout { 
                                anchors.centerIn: parent
                                spacing: root.s(8)
                                Text { text: "󰐊"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.base } 
                                Text { text: "PLAY"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(14); color: root.base } 
                            }
                            
                            MouseArea { 
                                id: launchMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "toggle", modulesDataModel.get(root.selectedModuleIndex).target]) 
                            }
                        }
                    }

                    Rectangle {
                        id: previewContainer
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: root.s(12)
                        color: root.surface0
                        border.color: root.surface2
                        border.width: 1
                        clip: true
                        
                        property string targetSource: modulesDataModel.get(root.selectedModuleIndex).preview ? Qt.resolvedUrl(modulesDataModel.get(root.selectedModuleIndex).preview) : ""
                        
                        onTargetSourceChanged: { 
                            baseImage.source = overlayImage.source; 
                            overlayImage.opacity = 0.0; 
                            overlayImage.source = targetSource; 
                            fadeAnim.restart(); 
                        }
                        
                        Image { 
                            id: baseImage
                            anchors.fill: parent
                            anchors.margins: 0
                            fillMode: Image.PreserveAspectCrop
                            verticalAlignment: Image.AlignTop
                            horizontalAlignment: Image.AlignHCenter
                            smooth: true
                            mipmap: true
                            asynchronous: true 
                        }
                        
                        Image { 
                            id: overlayImage
                            anchors.fill: parent
                            anchors.margins: 0
                            fillMode: Image.PreserveAspectCrop
                            verticalAlignment: Image.AlignTop
                            horizontalAlignment: Image.AlignHCenter
                            smooth: true
                            mipmap: true
                            asynchronous: true
                            NumberAnimation on opacity { 
                                id: fadeAnim
                                to: 1.0
                                duration: 350
                                easing.type: Easing.InOutQuad 
                            } 
                        }
                    }

                    ListView {
                        id: modulesList
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(90)
                        orientation: ListView.Horizontal
                        spacing: root.s(15)
                        clip: true
                        model: modulesDataModel
                        currentIndex: root.selectedModuleIndex
                        highlightMoveDuration: 250
                        
                        delegate: Rectangle {
                            width: root.s(220)
                            height: root.s(90)
                            radius: root.s(12)
                            property bool isSelected: index === root.selectedModuleIndex
                            color: isSelected ? root.surface1 : (modMa.containsMouse ? Qt.alpha(root.surface1, 0.5) : Qt.alpha(root.surface0, 0.4))
                            border.color: isSelected ? root.ambientBlue : (modMa.containsMouse ? root.surface2 : root.surface1)
                            border.width: isSelected ? 2 : 1
                            scale: isSelected ? 1.0 : (modMa.pressed ? 0.96 : (modMa.containsMouse ? 1.02 : 1.0))
                            
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }
                            
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: root.s(12)
                                spacing: root.s(5)
                                RowLayout { 
                                    spacing: root.s(10)
                                    Rectangle { 
                                        Layout.alignment: Qt.AlignVCenter
                                        width: root.s(28)
                                        height: root.s(28)
                                        radius: root.s(6)
                                        color: Qt.alpha(root.base, 0.5)
                                        Text { anchors.centerIn: parent; text: model.icon; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(14); color: isSelected ? root.ambientBlue : root.text } 
                                    } 
                                    Text { 
                                        text: model.title
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Bold
                                        font.pixelSize: root.s(12)
                                        color: root.text
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        elide: Text.ElideRight 
                                    } 
                                }
                                Text { 
                                    text: model.desc
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: root.s(10)
                                    color: root.subtext0
                                    Layout.alignment: Qt.AlignLeft
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    wrapMode: Text.WordWrap
                                    elide: Text.ElideRight 
                                }
                            }
                            
                            MouseArea { 
                                id: modMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { 
                                    root.selectedModuleIndex = index; 
                                    modulesList.positionViewAtIndex(index, ListView.Contain); 
                                }
                                onDoubleClicked: { 
                                    root.selectedModuleIndex = index; 
                                    Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "toggle", model.target]) 
                                } 
                            }
                        }
                    }
                }
            }
            }
        }

            // ------------------------------------------
            // TAB 4: KEYBINDS
            // ------------------------------------------
            Loader {
                id: tab4Loader
                anchors.fill: parent
                active: root.loadedTabs["4"] === true
                asynchronous: true
                onLoaded: root.tabReady(4)
                sourceComponent: Component {
            Item {
                anchors.fill: parent
                visible: root.currentTab === 4
                opacity: visible ? 1.0 : 0.0
                property real slideY: visible ? 0 : root.s(10)
                
                Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                transform: Translate { y: slideY }
                Behavior on opacity { NumberAnimation { duration: 250 } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(20)
                    spacing: root.s(20)

                    Text { text: "Navigation & Control"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(28); color: root.text; Layout.alignment: Qt.AlignVCenter }
                    Text { text: "Click any row below to instantly execute the keybind command."; font.family: "JetBrains Mono"; font.pixelSize: root.s(14); color: root.subtext0; Layout.alignment: Qt.AlignVCenter }
                    
                    ScrollView {
                        id: keybindsScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: availableWidth
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        Component.onCompleted: scrollRestoreTimer4.start()
                        Timer { id: scrollRestoreTimer4; interval: 120; onTriggered: keybindsScroll.contentItem.contentY = root.savedScrollY[4] || 0 }
                        Connections {
                            target: keybindsScroll.contentItem
                            function onContentYChanged() { root.savedScrollY[4] = keybindsScroll.contentItem.contentY; scrollSaveTimer.restart() }
                        }

                        GridLayout {
                            width: parent.width
                            columns: 2
                            rowSpacing: root.s(10)
                            columnSpacing: root.s(15)
                            
                            Rectangle {
                                Layout.columnSpan: 2
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(60)
                                radius: root.s(8)
                                color: Qt.alpha(root.surface0, 0.4)
                                border.color: root.surface1
                                border.width: 1
                                
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: root.s(10)
                                    spacing: root.s(10)
                                    
                                    Text { text: "Workspaces (SUPER + 1-9)"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text; Layout.alignment: Qt.AlignVCenter }
                                    Item { Layout.fillWidth: true }
                                    
                                    Repeater {
                                        model: 9
                                        Rectangle {
                                            property int wsNum: index + 1
                                            Layout.preferredWidth: root.s(32)
                                            Layout.preferredHeight: root.s(32)
                                            radius: root.s(6)
                                            color: wsMa.containsMouse ? root.surface1 : root.surface0
                                            border.color: wsMa.containsMouse ? root.peach : "transparent"
                                            border.width: 1
                                            Text { anchors.centerIn: parent; text: parent.wsNum; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12); color: root.peach }
                                            MouseArea { id: wsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", wsNum.toString()]) }
                                        }
                                    }
                                }
                            }
                            
                            Repeater {
                                model: dynamicKeybindsModel
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(46)
                                    radius: root.s(8)
                                    color: bindMa.containsMouse ? root.surface1 : Qt.alpha(root.surface0, 0.4)
                                    border.color: bindMa.containsMouse ? root.peach : "transparent"
                                    border.width: 1
                                    scale: bindMa.pressed ? 0.98 : 1.0
                                    
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuart } }
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: root.s(10)
                                        spacing: root.s(15)
                                        
                                        Item {
                                            Layout.preferredWidth: root.s(220)
                                            Layout.minimumWidth: root.s(220)
                                            Layout.maximumWidth: root.s(220)
                                            Layout.fillHeight: true
                                            
                                            Row { 
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: root.s(8)
                                                
                                                Rectangle { 
                                                    width: k1Text.implicitWidth + root.s(16)
                                                    height: root.s(26)
                                                    radius: root.s(4)
                                                    color: root.surface0
                                                    border.color: root.surface2
                                                    border.width: 1
                                                    Text { id: k1Text; anchors.centerIn: parent; text: model.k1; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: root.peach } 
                                                } 
                                                
                                                Text { text: "+"; font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: root.overlay0; visible: model.k2 !== ""; anchors.verticalCenter: parent.verticalCenter } 
                                                
                                                Rectangle { 
                                                    width: k2Text.implicitWidth + root.s(16)
                                                    height: root.s(26)
                                                    radius: root.s(4)
                                                    color: root.surface0
                                                    border.color: root.surface2
                                                    border.width: 1
                                                    visible: model.k2 !== ""
                                                    Text { id: k2Text; anchors.centerIn: parent; text: model.k2; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: root.peach } 
                                                } 
                                            }
                                        }
                                        
                                        Text { 
                                            text: model.action
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: root.s(13)
                                            color: root.text
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            horizontalAlignment: Text.AlignLeft
                                            elide: Text.ElideRight
                                            clip: true 
                                        }
                                    }
                                    
                                    MouseArea { 
                                        id: bindMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Quickshell.execDetached(["bash", "-c", model.cmd]) 
                                    }
                                }
                            }
                        }
                    }
                }
            }
            }
        }

            // ------------------------------------------
            // TAB 5: MATUGEN ENGINE
            // ------------------------------------------
            Loader {
                id: tab5Loader
                anchors.fill: parent
                active: root.loadedTabs["5"] === true
                asynchronous: true
                onLoaded: root.tabReady(5)
                sourceComponent: Component {
            Item {
                anchors.fill: parent
                visible: root.currentTab === 5
                opacity: visible ? 1.0 : 0.0
                property real slideY: visible ? 0 : root.s(10)
                
                Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                transform: Translate { y: slideY }
                Behavior on opacity { NumberAnimation { duration: 250 } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(20)
                    spacing: root.s(20)

                    Text { text: "Theming Engine"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(28); color: root.text; Layout.alignment: Qt.AlignVCenter }
                    
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(160)
                        radius: root.s(12)
                        color: Qt.alpha(root.surface0, 0.4)
                        border.color: root.ambientPurple
                        border.width: 1
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(20)
                            spacing: root.s(20)
                            
                            Item { Layout.fillWidth: true } 
                            
                            ColumnLayout { 
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(8)
                                Rectangle { 
                                    Layout.alignment: Qt.AlignHCenter
                                    width: root.s(60)
                                    height: root.s(60)
                                    radius: root.s(10)
                                    color: root.surface1
                                    Text { anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(28); color: root.text } 
                                } 
                                Text { text: "Wallpaper"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12); color: root.text; Layout.alignment: Qt.AlignHCenter } 
                            }
                            
                            Item { 
                                Layout.preferredWidth: root.s(60)
                                Layout.preferredHeight: root.s(20)
                                Layout.alignment: Qt.AlignVCenter
                                Repeater { 
                                    model: 3
                                    Item { 
                                        width: parent.width
                                        height: parent.height
                                        Rectangle { 
                                            width: root.s(6)
                                            height: root.s(6)
                                            radius: root.s(3)
                                            color: [root.mauve, root.peach, root.blue][index]
                                            y: parent.height / 2 - root.s(3)
                                            SequentialAnimation on x { 
                                                loops: Animation.Infinite
                                                running: root.currentTab === 5
                                                PauseAnimation { duration: index * 400 }
                                                NumberAnimation { from: 0; to: parent.width; duration: 1200; easing.type: Easing.InOutSine } 
                                            } 
                                            SequentialAnimation on opacity { 
                                                loops: Animation.Infinite
                                                running: root.currentTab === 5
                                                PauseAnimation { duration: index * 400 }
                                                NumberAnimation { from: 0; to: 1; duration: 300 }
                                                PauseAnimation { duration: 600 }
                                                NumberAnimation { from: 1; to: 0; duration: 300 } 
                                            } 
                                        } 
                                    } 
                                } 
                            }
                            
                            Rectangle {
                                width: root.s(180)
                                height: root.s(90)
                                radius: root.s(12)
                                color: root.base
                                border.color: root.ambientPurple
                                Layout.alignment: Qt.AlignVCenter
                                
                                SequentialAnimation on border.width { 
                                    loops: Animation.Infinite
                                    running: root.currentTab === 5
                                    NumberAnimation { from: root.s(1); to: root.s(4); duration: 1000; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: root.s(4); to: root.s(1); duration: 1000; easing.type: Easing.InOutSine } 
                                }
                                
                                ColumnLayout { 
                                    anchors.centerIn: parent
                                    spacing: root.s(8)
                                    Text { text: "Matugen Core"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(15); color: root.ambientPurple; Layout.alignment: Qt.AlignHCenter } 
                                    RowLayout { 
                                        spacing: root.s(4)
                                        Layout.alignment: Qt.AlignHCenter
                                        Repeater { 
                                            model: [root.red, root.peach, root.yellow, root.green, root.blue, root.mauve]
                                            Rectangle { 
                                                Layout.alignment: Qt.AlignVCenter
                                                width: root.s(12)
                                                height: root.s(12)
                                                radius: root.s(6)
                                                color: modelData
                                                SequentialAnimation on scale { 
                                                    loops: Animation.Infinite
                                                    running: root.currentTab === 5
                                                    PauseAnimation { duration: index * 150 }
                                                    NumberAnimation { to: 1.3; duration: 300; easing.type: Easing.OutQuart }
                                                    NumberAnimation { to: 1.0; duration: 400; easing.type: Easing.OutQuart }
                                                    PauseAnimation { duration: 1000 } 
                                                } 
                                            } 
                                        } 
                                    } 
                                } 
                            }
                            
                            Item { 
                                Layout.preferredWidth: root.s(60)
                                Layout.preferredHeight: root.s(20)
                                Layout.alignment: Qt.AlignVCenter
                                Repeater { 
                                    model: 3
                                    Item { 
                                        width: parent.width
                                        height: parent.height
                                        Rectangle { 
                                            width: root.s(6)
                                            height: root.s(6)
                                            radius: root.s(3)
                                            color: [root.green, root.yellow, root.pink][index]
                                            y: parent.height / 2 - root.s(3)
                                            SequentialAnimation on x { 
                                                loops: Animation.Infinite
                                                running: root.currentTab === 5
                                                PauseAnimation { duration: index * 400 }
                                                NumberAnimation { from: 0; to: parent.width; duration: 1200; easing.type: Easing.InOutSine } 
                                            } 
                                            SequentialAnimation on opacity { 
                                                loops: Animation.Infinite
                                                running: root.currentTab === 5
                                                PauseAnimation { duration: index * 400 }
                                                NumberAnimation { from: 0; to: 1; duration: 300 }
                                                PauseAnimation { duration: 600 }
                                                NumberAnimation { from: 1; to: 0; duration: 300 } 
                                            } 
                                        } 
                                    } 
                                } 
                            }
                            
                            ColumnLayout { 
                                Layout.alignment: Qt.AlignVCenter
                                spacing: root.s(8)
                                Rectangle { 
                                    Layout.alignment: Qt.AlignHCenter
                                    width: root.s(60)
                                    height: root.s(60)
                                    radius: root.s(10)
                                    color: root.surface1
                                    Text { anchors.centerIn: parent; text: "󰏘"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(28); color: root.text } 
                                } 
                                Text { text: "Templates"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12); color: root.text; Layout.alignment: Qt.AlignHCenter } 
                            }
                            Item { Layout.fillWidth: true } 
                        }
                    }

                    Text { text: "When you change wallpapers, Matugen extracts the dominant colors and injects them directly into these configuration files in real-time:"; font.family: "JetBrains Mono"; font.pixelSize: root.s(13); color: root.subtext0; Layout.fillWidth: true; wrapMode: Text.WordWrap; Layout.alignment: Qt.AlignVCenter }

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        columns: 3
                        rowSpacing: root.s(10)
                        columnSpacing: root.s(10)
                        
                        Repeater {
                            model: [ 
                                { f: "kitty-colors.conf", i: "󰄛", c: "yellow" }, 
                                { f: "nvim-colors.lua", i: "", c: "green" }, 
                                { f: "rofi.rasi", i: "", c: "blue" }, 
                                { f: "cava-colors.ini", i: "󰎆", c: "mauve" }, 
                                { f: "sddm-colors.qml", i: "󰍃", c: "peach" }, 
                                { f: "swaync/osd.css", i: "󰂚", c: "pink" } 
                            ]
                            
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(45)
                                radius: root.s(8)
                                color: tplMa.containsMouse ? Qt.alpha(root[modelData.c], 0.1) : root.surface0
                                border.color: tplMa.containsMouse ? root[modelData.c] : "transparent"
                                border.width: 1
                                
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                
                                RowLayout { 
                                    anchors.fill: parent
                                    anchors.margins: root.s(10)
                                    spacing: root.s(10)
                                    Item { 
                                        Layout.preferredWidth: root.s(24)
                                        Layout.alignment: Qt.AlignVCenter
                                        Text { anchors.centerIn: parent; text: modelData.i; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(16); color: root[modelData.c] } 
                                    } 
                                    Text { text: modelData.f; font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: root.s(12); color: root.text; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter } 
                                }
                                MouseArea { id: tplMa; anchors.fill: parent; hoverEnabled: true }
                            }
                        }
                    }
                }
            }
            }
        }

            // ------------------------------------------
            // TAB 6: WEATHER API
            // ------------------------------------------
            Loader {
                id: tab6Loader
                anchors.fill: parent
                active: root.loadedTabs["6"] === true
                asynchronous: true
                onLoaded: root.tabReady(6)
                sourceComponent: Component {
            Item {
                readonly property var x_weatherTab: weatherTab
                readonly property var x_apiKeyInput: apiKeyInput
                readonly property var x_cityIdInput: cityIdInput
                id: weatherTab
                anchors.fill: parent
                visible: root.currentTab === 6
                opacity: visible ? 1.0 : 0.0
                property real slideY: visible ? 0 : root.s(10)
                
                Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                transform: Translate { y: slideY }
                Behavior on opacity { NumberAnimation { duration: 250 } }

                property string selectedUnit: "metric"
                property bool apiKeyVisible: false

                function saveWeatherConfig() {
                    var file = Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/calendar/.env";
                    var cmds = [
                        "mkdir -p $(dirname " + file + ")",
                        "echo '# OpenWeather API Configuration (OVERWRITE, not add)' > " + file,
                        "echo 'OPENWEATHER_KEY=" + apiKeyInput.text + "' >> " + file,
                        "echo 'OPENWEATHER_CITY_ID=" + cityIdInput.text + "' >> " + file,
                        "echo 'OPENWEATHER_UNIT=" + weatherTab.selectedUnit + "' >> " + file,
                        "notify-send 'Weather' 'API configuration saved successfully!'"
                    ];
                    var finalCmd = cmds.join(" && ");
                    Quickshell.execDetached(["bash", "-c", finalCmd]);
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(20)
                    spacing: root.s(15)

                    Text { text: "Weather Configuration"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(28); color: root.text; Layout.alignment: Qt.AlignVCenter }
                    Text { text: "To use the weather widget, please enter your OpenWeatherMap API Key.\nThen, search for your city's exact City ID on OpenWeatherMap and enter it below."; font.family: "JetBrains Mono"; font.pixelSize: root.s(13); color: root.subtext0; Layout.fillWidth: true; wrapMode: Text.WordWrap; Layout.alignment: Qt.AlignVCenter }
                    
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(46)
                        radius: root.s(8)
                        color: root.surface0
                        border.color: apiKeyInput.activeFocus ? root.blue : root.surface2
                        border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(10)
                            spacing: root.s(10)
                            Text { text: "󰌆"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18); color: root.subtext0 }
                            TextInput { 
                                id: apiKeyInput
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: "JetBrains Mono"
                                font.pixelSize: root.s(13)
                                color: root.text
                                clip: true
                                selectByMouse: true
                                echoMode: weatherTab.apiKeyVisible ? TextInput.Normal : TextInput.Password
                                passwordCharacter: "•"
                                Text { text: "Enter OpenWeather API Key..."; color: root.subtext0; visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter } 
                            }
                            Rectangle { 
                                width: root.s(26)
                                height: root.s(26)
                                radius: root.s(4)
                                color: "transparent"
                                Text { 
                                    anchors.centerIn: parent
                                    text: weatherTab.apiKeyVisible ? "󰈈" : "󰈉"
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: root.s(18)
                                    color: eyeMa.containsMouse ? root.blue : root.subtext0
                                    Behavior on color { ColorAnimation { duration: 150 } } 
                                } 
                                MouseArea { id: eyeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: weatherTab.apiKeyVisible = !weatherTab.apiKeyVisible } 
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(46)
                        radius: root.s(8)
                        Layout.topMargin: root.s(10)
                        color: root.surface0
                        border.color: cityIdInput.activeFocus ? root.peach : root.surface2
                        border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        
                        TextInput { 
                            id: cityIdInput
                            anchors.fill: parent
                            anchors.margins: root.s(10)
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: "JetBrains Mono"
                            font.pixelSize: root.s(13)
                            color: root.text
                            clip: true
                            selectByMouse: true
                            Text { text: "City ID (e.g. 2624652)"; color: root.subtext0; visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter } 
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.s(15)
                        Layout.topMargin: root.s(10)
                        Text { text: "Units:"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                        
                        RowLayout {
                            spacing: root.s(5)
                            Repeater {
                                model: ["metric", "imperial", "standard"]
                                Rectangle {
                                    Layout.preferredWidth: root.s(80)
                                    Layout.preferredHeight: root.s(32)
                                    radius: root.s(6)
                                    color: weatherTab.selectedUnit === modelData ? Qt.alpha(root.mauve, 0.2) : "transparent"
                                    border.color: weatherTab.selectedUnit === modelData ? root.mauve : root.surface1
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    Text { 
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: root.s(11)
                                        font.capitalization: Font.Capitalize
                                        color: weatherTab.selectedUnit === modelData ? root.mauve : root.subtext0 
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: weatherTab.selectedUnit = modelData }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true; Layout.fillWidth: true }

                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        
                        Rectangle {
                            Layout.preferredWidth: root.s(160)
                            Layout.preferredHeight: root.s(46)
                            radius: root.s(8)
                            color: saveMa.containsMouse ? Qt.alpha(root.green, 0.8) : root.green
                            scale: saveMa.pressed ? 0.95 : (saveMa.containsMouse ? 1.02 : 1.0)
                            
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            
                            RowLayout { 
                                anchors.centerIn: parent
                                spacing: root.s(8)
                                Text { text: "󰆓"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18); color: root.base } 
                                Text { text: "Save Config"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(14); color: root.base } 
                            }
                            
                            MouseArea {
                                id: saveMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: weatherTab.saveWeatherConfig()
                            }
                        }
                    }
                }
            }
            }
        }

            // ------------------------------------------
            // TAB 7: STARTUP APPS
            // ------------------------------------------
            Loader {
                id: tab7Loader
                anchors.fill: parent
                active: root.loadedTabs["7"] === true
                asynchronous: true
                onLoaded: root.tabReady(7)
                sourceComponent: Component {
            Item {
                id: startupTab
                anchors.fill: parent
                visible: root.currentTab === 7
                opacity: visible ? 1.0 : 0.0
                property real slideY: visible ? 0 : root.s(10)

                Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                transform: Translate { y: slideY }
                Behavior on opacity { NumberAnimation { duration: 250 } }

                readonly property string confPath: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/startup_apps.json"

                ListModel { id: startupModel }

                function loadStartup() { startupLoader.running = false; startupLoader.running = true }

                function saveStartup(thenNotify) {
                    let arr = [];
                    for (let i = 0; i < startupModel.count; i++) {
                        let e = startupModel.get(i);
                        if (e.cmd.trim() === "") continue;
                        arr.push({ name: e.name, cmd: e.cmd, class: e.class, workspace: e.workspace, silent: e.silent });
                    }
                    startupWriter.jsonText = JSON.stringify(arr, null, 2);
                    startupWriter.notifyAfter = !!thenNotify;
                    startupWriter.running = false; startupWriter.running = true;
                }

                Process {
                    id: startupLoader
                    command: ["bash", "-c", "cat '" + startupTab.confPath + "' 2>/dev/null || echo '[]'"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            startupModel.clear();
                            try {
                                let arr = JSON.parse(this.text.trim() || "[]");
                                for (let i = 0; i < arr.length; i++) {
                                    let e = arr[i];
                                    startupModel.append({
                                        name: e.name || "", cmd: e.cmd || "", class: e.class || "",
                                        workspace: e.workspace || "", silent: !!e.silent
                                    });
                                }
                            } catch (e) {}
                        }
                    }
                }

                Process {
                    id: startupWriter
                    property string jsonText: ""
                    property bool notifyAfter: false
                    command: ["python3", "-c",
                        "import sys; open(sys.argv[1], 'w').write(sys.argv[2])",
                        startupTab.confPath, jsonText]
                    onExited: if (notifyAfter) Quickshell.execDetached(["notify-send", "Startup", "Saved — takes effect next login."])
                }

                Component.onCompleted: loadStartup()

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(20)
                    spacing: root.s(12)

                    Text { text: "Startup Apps"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(28); color: root.text }
                    Text {
                        text: "What launches on login, and which workspace it lands on. \"silent\" opens it without stealing focus or switching you to its workspace. Set the window class to skip re-launching if it's already running (safe to re-trigger startup mid-session). If hyprland.conf already has a windowrule for that class it just launches plainly and lets the rule place it; otherwise it polls for the new window and moves it by address — for an app that needs a one-shot placement rather than a permanent home for its whole class (e.g. a terminal into a scratchpad workspace, where a windowrule would wrongly pin every future window of that app too)."
                        font.family: "JetBrains Mono"; font.pixelSize: root.s(13); color: root.subtext0
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.surface1, 0.5) }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.s(10)
                        Text { text: "App / command"; Layout.preferredWidth: root.s(220); font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 }
                        Text { text: "Window class"; Layout.preferredWidth: root.s(120); font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 }
                        Text { text: "Workspace"; Layout.preferredWidth: root.s(140); font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 }
                        Text { text: "Silent"; Layout.preferredWidth: root.s(60); font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 }
                        Item { Layout.fillWidth: true }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: startupModel
                        spacing: root.s(8)
                        delegate: Rectangle {
                            width: ListView.view.width
                            height: root.s(46)
                            radius: root.s(8)
                            color: root.surface0
                            border.width: 1; border.color: root.surface2

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: root.s(8)
                                spacing: root.s(10)

                                TextInput {
                                    Layout.preferredWidth: root.s(220)
                                    text: model.cmd
                                    font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: root.text
                                    selectByMouse: true
                                    onTextEdited: startupModel.setProperty(index, "cmd", text)
                                }
                                TextInput {
                                    Layout.preferredWidth: root.s(120)
                                    text: model.class
                                    font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: root.text
                                    selectByMouse: true
                                    onTextEdited: startupModel.setProperty(index, "class", text)
                                }
                                TextInput {
                                    Layout.preferredWidth: root.s(140)
                                    text: model.workspace
                                    font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: root.text
                                    selectByMouse: true
                                    onTextEdited: startupModel.setProperty(index, "workspace", text)
                                }
                                Rectangle {
                                    Layout.preferredWidth: root.s(22); Layout.preferredHeight: root.s(22)
                                    radius: root.s(5)
                                    color: model.silent ? root.green : root.surface1
                                    border.width: 1; border.color: root.surface2
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: startupModel.setProperty(index, "silent", !model.silent)
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                // Test an entry right now instead of needing to log out to
                                // find out if it actually launches where you expect — the
                                // same plain hyprctl exec-tag path startup_apps.sh itself
                                // falls back to for entries without a windowrule-owned
                                // class (see that script's own comment for the split).
                                Rectangle {
                                    Layout.preferredWidth: root.s(80); Layout.preferredHeight: root.s(28)
                                    radius: root.s(6)
                                    color: stuLaunchMa.containsMouse ? root.surface2 : root.surface1
                                    border.width: 1; border.color: root.surface2
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text { anchors.centerIn: parent; text: stuLaunchProc.running ? "…" : "Launch now"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0 }
                                    Process { id: stuLaunchProc }
                                    MouseArea {
                                        id: stuLaunchMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            let ws = model.workspace || ""
                                            let silent = model.silent ? "silent" : ""
                                            let flags = [ws ? ("workspace " + ws) : "", silent].filter(f => f).join(" ")
                                            let full = flags ? ("[" + flags + "] " + model.cmd) : model.cmd
                                            stuLaunchProc.command = ["hyprctl", "dispatch", "exec", full]
                                            stuLaunchProc.running = false
                                            stuLaunchProc.running = true
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.preferredWidth: root.s(28); Layout.preferredHeight: root.s(28)
                                    radius: root.s(6)
                                    color: stuRmMa.containsMouse ? Qt.alpha(root.red, 0.8) : root.surface1
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text { anchors.centerIn: parent; text: "✕"; color: root.text; font.pixelSize: root.s(12) }
                                    MouseArea {
                                        id: stuRmMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: startupModel.remove(index)
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.s(10)

                        Rectangle {
                            Layout.preferredWidth: root.s(120); Layout.preferredHeight: root.s(40)
                            radius: root.s(8)
                            color: stuAddMa.containsMouse ? Qt.alpha(root.surface1, 0.8) : root.surface1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: "+ Add app"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12); color: root.text }
                            MouseArea {
                                id: stuAddMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: startupModel.append({ name: "", cmd: "", class: "", workspace: "", silent: false })
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            Layout.preferredWidth: root.s(160); Layout.preferredHeight: root.s(46)
                            radius: root.s(8)
                            color: saveStartupMa.containsMouse ? Qt.alpha(root.green, 0.8) : root.green
                            scale: saveStartupMa.pressed ? 0.95 : (saveStartupMa.containsMouse ? 1.02 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: root.s(8)
                                Text { text: "󰆓"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(18); color: root.base }
                                Text { text: "Save"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(14); color: root.base }
                            }
                            MouseArea {
                                id: saveStartupMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: startupTab.saveStartup(true)
                            }
                        }
                    }
                }
            }
            }
        }

            // ------------------------------------------
            // TAB 8: MAILBOX
            // ------------------------------------------
            Loader {
                id: tab8Loader
                anchors.fill: parent
                active: root.loadedTabs["8"] === true
                asynchronous: true
                onLoaded: root.tabReady(8)
                sourceComponent: Component {
            Item {
                id: mailboxTab
                anchors.fill: parent
                visible: root.currentTab === 8
                opacity: visible ? 1.0 : 0.0
                property real slideY: visible ? 0 : root.s(10)

                Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                transform: Translate { y: slideY }
                Behavior on opacity { NumberAnimation { duration: 250 } }

                readonly property string mailPath: "/tmp/qs_claude_mailbox.json"

                ListModel { id: mailboxModel }

                function loadMailbox() { mailboxLoader.running = false; mailboxLoader.running = true }

                Timer { interval: 2000; running: mailboxTab.visible; repeat: true; onTriggered: mailboxTab.loadMailbox() }

                Process {
                    id: mailboxLoader
                    command: ["bash", "-c", "cat '" + mailboxTab.mailPath + "' 2>/dev/null || echo '[]'"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            mailboxModel.clear();
                            try {
                                let arr = JSON.parse(this.text.trim() || "[]");
                                for (let i = arr.length - 1; i >= 0; i--) {
                                    let m = arr[i];
                                    mailboxModel.append({
                                        from: m.from || "?", to: m.to || "?", msg: m.msg || "",
                                        ts: m.ts || 0, read: !!m.read
                                    });
                                }
                            } catch (e) {}
                        }
                    }
                }

                Component.onCompleted: loadMailbox()

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(20)
                    spacing: root.s(12)

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Mailbox"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(28); color: root.text }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            Layout.preferredWidth: root.s(80); Layout.preferredHeight: root.s(32)
                            radius: root.s(8)
                            color: mailRefreshMa.containsMouse ? root.surface1 : root.surface0
                            border.color: root.surface2; border.width: 1
                            Text { anchors.centerIn: parent; text: "Refresh"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.text }
                            MouseArea { id: mailRefreshMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mailboxTab.loadMailbox() }
                        }
                    }
                    Text {
                        text: "Notes passed between 'me' (this chat), 'resident' (the ambient daemon), and 'agent' (one-shot runs) via mailbox_post/mailbox_read. Newest first."
                        font.family: "JetBrains Mono"; font.pixelSize: root.s(13); color: root.subtext0
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.surface1, 0.5) }

                    Text {
                        visible: mailboxModel.count === 0
                        text: "Mailbox is empty."
                        font.family: "JetBrains Mono"; font.pixelSize: root.s(13); color: root.subtext0
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: root.s(8)
                        model: mailboxModel
                        delegate: Rectangle {
                            width: ListView.view.width
                            height: msgCol.implicitHeight + root.s(20)
                            radius: root.s(8)
                            color: Qt.alpha(root.surface0, 0.4)
                            border.color: model.read ? root.surface1 : root.mauve
                            border.width: 1

                            ColumnLayout {
                                id: msgCol
                                anchors.fill: parent
                                anchors.margins: root.s(12)
                                spacing: root.s(4)

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: model.from + " → " + model.to
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12)
                                        color: model.read ? root.subtext0 : root.mauve
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: new Date(model.ts * 1000).toLocaleTimeString(Qt.locale(), "HH:mm:ss")
                                        font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0
                                    }
                                }
                                Text {
                                    text: model.msg
                                    font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: root.text
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
            }
            }
            }

            // ------------------------------------------
            // TAB 9: RESIDENT — stats + screenshot history
            // ------------------------------------------
            Loader {
                id: tab9Loader
                anchors.fill: parent
                active: root.loadedTabs["9"] === true
                asynchronous: true
                onLoaded: root.tabReady(9)
                sourceComponent: Component {
            Item {
                id: residentTab
                anchors.fill: parent
                visible: root.currentTab === 9
                opacity: visible ? 1.0 : 0.0
                property real slideY: visible ? 0 : root.s(10)

                Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                transform: Translate { y: slideY }
                Behavior on opacity { NumberAnimation { duration: 250 } }

                readonly property string statsScript: "~/.config/hypr/scripts/quickshell/claude/resident_extras.py"
                readonly property string shotLogPath: "~/.cache/quickshell/claude/shot_answers.jsonl"

                ListModel { id: statsCategoryModel }
                property var statsMuted: []
                property var statsPeriodic: ({})

                ListModel { id: shotHistoryModel }

                function loadStats() { statsLoader.running = false; statsLoader.running = true }
                function loadShotHistory() { shotHistoryLoader.running = false; shotHistoryLoader.running = true }

                Timer { interval: 5000; running: residentTab.visible; repeat: true; onTriggered: { residentTab.loadStats(); residentTab.loadShotHistory() } }

                Process {
                    id: statsLoader
                    command: ["bash", "-c", "python3 " + residentTab.statsScript + " --stats 2>/dev/null || echo '{}'"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            statsCategoryModel.clear();
                            try {
                                let d = JSON.parse(this.text.trim() || "{}");
                                let cats = d.categories || [];
                                for (let i = 0; i < cats.length; i++) {
                                    statsCategoryModel.append(cats[i]);
                                }
                                residentTab.statsMuted = d.muted || [];
                                residentTab.statsPeriodic = d.periodic_last_run || {};
                            } catch (e) {}
                        }
                    }
                }

                Process {
                    id: shotHistoryLoader
                    command: ["bash", "-c", "tail -n 40 " + residentTab.shotLogPath + " 2>/dev/null || echo ''"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            shotHistoryModel.clear();
                            let lines = this.text.trim().split("\n").filter(l => l.length > 0);
                            for (let i = lines.length - 1; i >= 0; i--) {
                                try {
                                    let e = JSON.parse(lines[i]);
                                    shotHistoryModel.append({
                                        ts: e.ts || 0, question: e.question || "", answer: e.answer || "",
                                        image_path: e.image_path || ""
                                    });
                                } catch (err) {}
                            }
                        }
                    }
                }

                Component.onCompleted: { loadStats(); loadShotHistory() }

                Flickable {
                    anchors.fill: parent
                    anchors.margins: root.s(20)
                    contentWidth: width
                    contentHeight: residentCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: residentCol
                        width: parent.width
                        spacing: root.s(16)

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Resident"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(28); color: root.text }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                Layout.preferredWidth: root.s(80); Layout.preferredHeight: root.s(32)
                                radius: root.s(8)
                                color: residentRefreshMa.containsMouse ? root.surface1 : root.surface0
                                border.color: root.surface2; border.width: 1
                                Text { anchors.centerIn: parent; text: "Refresh"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.text }
                                MouseArea { id: residentRefreshMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { residentTab.loadStats(); residentTab.loadShotHistory() } }
                            }
                        }
                        Text {
                            text: "Read-only track record — proactive-fix findings by category, muted categories, and daily/weekly check history."
                            font.family: "JetBrains Mono"; font.pixelSize: root.s(13); color: root.subtext0
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.surface1, 0.5) }

                        Text { text: "Proactive-fix categories"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(15); color: root.text }
                        Text {
                            visible: statsCategoryModel.count === 0
                            text: "No proactive-fix activity recorded yet."
                            font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: root.subtext0
                        }
                        Repeater {
                            model: statsCategoryModel
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(40)
                                radius: root.s(8)
                                color: Qt.alpha(root.surface0, 0.4)
                                border.color: model.muted ? root.peach : root.surface1
                                border.width: 1
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: root.s(10)
                                    spacing: root.s(12)
                                    Text { text: model.key; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12); color: root.text; Layout.preferredWidth: root.s(180); elide: Text.ElideRight }
                                    Text { text: "resolved " + model.resolved; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.green }
                                    Text { text: "dismissed " + model.dismissals; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 }
                                    Item { Layout.fillWidth: true }
                                    Text { visible: model.muted; text: "muted"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: root.peach }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.surface1, 0.5) }

                        Text { text: "Daily / weekly checks"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(15); color: root.text }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: root.s(4)
                            Repeater {
                                model: Object.keys(residentTab.statsPeriodic)
                                delegate: RowLayout {
                                    Layout.fillWidth: true
                                    required property string modelData
                                    Text { text: modelData; font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: root.text; Layout.preferredWidth: root.s(180) }
                                    Text {
                                        text: residentTab.statsPeriodic[modelData] ? new Date(residentTab.statsPeriodic[modelData] * 1000).toLocaleString(Qt.locale(), "MMM d, HH:mm") : "never"
                                        font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: root.subtext0
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.surface1, 0.5) }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Screenshot answers"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(15); color: root.text }
                            Item { Layout.fillWidth: true }
                            Text { text: shotHistoryModel.count + " recent"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 }
                        }
                        Text {
                            text: "History from SUPER+CTRL+Z and SUPER+ALT+Z (\"answer this\" / ask-a-question screenshot flows)."
                            font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }
                        Text {
                            visible: shotHistoryModel.count === 0
                            text: "No screenshot answers recorded yet."
                            font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: root.subtext0
                        }
                        Repeater {
                            model: shotHistoryModel
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: shotCol.implicitHeight + root.s(20)
                                radius: root.s(8)
                                color: Qt.alpha(root.surface0, 0.4)
                                border.color: root.surface1
                                border.width: 1
                                ColumnLayout {
                                    id: shotCol
                                    anchors.fill: parent
                                    anchors.margins: root.s(12)
                                    spacing: root.s(4)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: model.question || "(auto)"
                                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12); color: root.mauve
                                            elide: Text.ElideRight; Layout.fillWidth: true
                                        }
                                        Text {
                                            text: model.ts ? new Date(model.ts * 1000).toLocaleTimeString(Qt.locale(), "HH:mm:ss") : ""
                                            font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0
                                        }
                                    }
                                    Text {
                                        text: model.answer
                                        font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: root.text
                                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                                    }
                                    Rectangle {
                                        Layout.preferredWidth: root.s(60); Layout.preferredHeight: root.s(24)
                                        radius: root.s(6)
                                        color: shotCopyMa.containsMouse ? root.surface2 : root.surface1
                                        Text { anchors.centerIn: parent; text: "Copy"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.text }
                                        MouseArea {
                                            id: shotCopyMa
                                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                shotCopyProc.command = ["bash", "-c", "printf %s " + JSON.stringify(model.answer) + " | wl-copy"]
                                                shotCopyProc.running = false; shotCopyProc.running = true
                                            }
                                        }
                                        Process { id: shotCopyProc }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            }
        }

            // ------------------------------------------
            // TAB 10: MUSIC STATS — recently played, most played,
            // BPM trend, album-color moodboard, on this day.
            // Reads music_stats.py's output, which itself reads
            // play_history.jsonl (an append-only log music_info.sh writes
            // on every real track change — not the same thing as
            // song_cache.json, which is a per-track color/bpm lookup that
            // gets overwritten in place, not a timeline).
            // ------------------------------------------
            Loader {
                id: tab10Loader
                anchors.fill: parent
                active: root.loadedTabs["10"] === true
                asynchronous: true
                onLoaded: root.tabReady(10)
                sourceComponent: Component {
            Item {
                id: musicStatsTab
                anchors.fill: parent
                visible: root.currentTab === 10
                opacity: visible ? 1.0 : 0.0
                property real slideY: visible ? 0 : root.s(10)
                Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                transform: Translate { y: slideY }
                Behavior on opacity { NumberAnimation { duration: 250 } }

                property var stats: ({})
                property bool statsLoading: true
                property int subTab: 0 // 0=Overview 1=This Week 2=This Month 3=Your Vibe
                function takeSubTabRequest() {
                    if (root.musicSubTabRequest < 0) return
                    musicStatsTab.subTab = root.musicSubTabRequest
                    if (root.musicSubTabRequest > 0) subTabScrollTimer.restart()
                    root.musicSubTabRequest = -1
                }
                Timer {
                    id: subTabScrollTimer
                    interval: 450
                    onTriggered: {
                        if (musicStatsTab.statsLoading) { restart(); return }
                        statsScrollAnim.to = Math.max(0, Math.min(subTabBar.y - root.s(12), statsFlick.contentHeight - statsFlick.height))
                        statsScrollAnim.restart()
                    }
                }
                Connections { target: root; function onMusicSubTabRequestChanged() { musicStatsTab.takeSubTabRequest() } }

                function reload() {
                    musicStatsTab.statsLoading = true
                    statsProc.running = false
                    statsProc.running = true
                }
                Process {
                    id: statsProc
                    command: ["python3", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/music/music_stats.py"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            musicStatsTab.statsLoading = false
                            try {
                                let d = JSON.parse(this.text.trim())
                                if (d && typeof d === "object") musicStatsTab.stats = d
                            } catch (e) {}
                        }
                    }
                }
                Component.onCompleted: { reload(); takeSubTabRequest() }

                property string heroQuote: ""
                property string heroQuoteKey: ""
                function signatureLine(d) {
                    if (!d || !d.found) return ""
                    let lines = d.synced && d.synced.length > 0 ? d.synced.map(function (x) { return x.text || "" }) : String(d.plain || "").split("\n")
                    let counts = {}, first = {}
                    for (let i = 0; i < lines.length; i++) {
                        let t = String(lines[i]).trim()
                        if (t.length < 14 || t.length > 64 || /^[\[(]/.test(t)) continue
                        let k = t.toLowerCase()
                        counts[k] = (counts[k] || 0) + 1
                        if (first[k] === undefined) first[k] = { i: i, t: t }
                    }
                    let best = null
                    for (let k in counts) {
                        if (!best || counts[k] > counts[best] || (counts[k] === counts[best] && first[k].i < first[best].i)) best = k
                    }
                    return best ? first[best].t : ""
                }
                property var heroQuoteTrack: null
                property var quoteQueue: []
                function fetchHeroQuote() {
                    let sp = musicStatsTab.stats.spotify
                    let list = sp ? (sp.topTracksShort || []).slice(0, 5) : []
                    if (list.length === 0) return
                    let key = list.map(function (t) { return t.artist + "|" + t.title }).join("\n")
                    if (key === musicStatsTab.heroQuoteKey) return
                    musicStatsTab.heroQuoteKey = key
                    musicStatsTab.heroQuote = ""
                    musicStatsTab.heroQuoteTrack = null
                    musicStatsTab.quoteQueue = list
                    musicStatsTab.nextQuote()
                }
                function nextQuote() {
                    if (musicStatsTab.quoteQueue.length === 0) return
                    let tt = musicStatsTab.quoteQueue[0]
                    musicStatsTab.quoteQueue = musicStatsTab.quoteQueue.slice(1)
                    lyricProc.track = tt
                    lyricProc.command = ["python3", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/music/lyrics_fetch.py",
                        String(tt.artist).split(",")[0].trim(), String(tt.title), String(Math.round(tt.durationSec || 0))]
                    lyricProc.running = false
                    lyricProc.running = true
                }
                onStatsChanged: fetchHeroQuote()
                Process {
                    id: lyricProc
                    property var track: null
                    stdout: StdioCollector {
                        onStreamFinished: {
                            let q = ""
                            try { q = musicStatsTab.signatureLine(JSON.parse(this.text.trim())) } catch (e) {}
                            if (q !== "") { musicStatsTab.heroQuoteTrack = lyricProc.track; musicStatsTab.heroQuote = q }
                            else musicStatsTab.nextQuote()
                        }
                    }
                }

                property bool spotifyRefreshing: false
                Process {
                    id: spotifyFetchProc
                    command: ["python3", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/music/spotify_fetch.py"]
                    stdout: StdioCollector {
                        onStreamFinished: { musicStatsTab.spotifyRefreshing = false; musicStatsTab.reload() }
                    }
                }
                function refreshSpotify() {
                    musicStatsTab.spotifyRefreshing = true
                    spotifyFetchProc.running = false
                    spotifyFetchProc.running = true
                }

                function fmtDuration(secs) {
                    if (!secs || secs <= 0) return "—"
                    let h = Math.floor(secs / 3600)
                    let m = Math.round((secs % 3600) / 60)
                    if (h > 0) return h + "h " + m + "m"
                    return m + "m"
                }
                function fmtHour(h) {
                    if (h === null || h === undefined) return "—"
                    let ampm = h < 12 ? "AM" : "PM"
                    let h12 = h % 12 === 0 ? 12 : h % 12
                    return h12 + (ampm)
                }
                function fmtClock(secs) {
                    let t = Math.max(0, Math.round(secs || 0))
                    let h = Math.floor(t / 3600)
                    let m = Math.floor((t % 3600) / 60)
                    return h > 0 ? h + "h " + m + "m" : m + "m"
                }
                function spanLabel(d) {
                    let n = Math.max(1, Math.round(d || 1))
                    return n + (n === 1 ? " DAY" : " DAYS")
                }
                function hiRes(u) { return String(u || "").replace("ab67616d00004851", "ab67616d00001e02") }
                function gradPair(g) {
                    let m = String(g || "").match(/#[0-9a-fA-F]{6}/g)
                    return m && m.length >= 2 ? [m[0], m[1]] : null
                }
                function trackKey(a, t) { return String(a || "").toLowerCase() + "|" + String(t || "").toLowerCase() }
                function leadArtist(a) { return String(a || "").split(",")[0].trim().toLowerCase() }
                // Local play log emits artist-less duplicate rows (e.g. "", "Jazz (We've Got)") — backend needs a follow-up look.
                function trackLine(a, t) { return a ? a + " — " + t : (t || "") }
                function boost(c) {
                    let q = Qt.color(String(c))
                    let h = q.hslHue < 0 ? 0.72 : q.hslHue
                    return Qt.hsla(h, q.hslHue < 0 ? 0.4 : Math.max(q.hslSaturation, 0.62), Math.min(Math.max(q.hslLightness, 0.5), 0.68), 1.0)
                }
                readonly property var paletteIndex: {
                    let d = {}, list = [], seen = {}
                    let s = musicStatsTab.stats
                    let src = [].concat(s.recentlyPlayed || [], s.topAllTime || [], s.topThisWeek || [])
                    for (let i = 0; i < src.length; i++) {
                        let e = src[i]
                        let p = musicStatsTab.gradPair(e.vibrantGrad || e.grad)
                        if (!p) continue
                        if (!seen[p[0]]) { seen[p[0]] = true; list.push(p) }
                        if (!e.artist) continue
                        let ak = musicStatsTab.leadArtist(e.artist)
                        if (!d[ak]) d[ak] = p
                        let tk = musicStatsTab.trackKey(e.artist, e.title)
                        if (!d[tk]) d[tk] = p
                    }
                    return { map: d, list: list }
                }
                readonly property var artIndex: {
                    let d = {}
                    let s = musicStatsTab.stats
                    let sp = s.spotify || {}
                    let src = [].concat(sp.topTracksShort || [], sp.topTracksLong || [], sp.recentlyPlayed || [],
                        (s.spotifyWeek || {}).topTracks || [], (s.spotifyMonth || {}).topTracks || [],
                        s.recentlyPlayed || [], s.topAllTime || [])
                    let rank = function (u) { return !u ? -1 : (u.indexOf("_l.jpg") >= 0 ? 2 : (u.indexOf("/spotify_art/") >= 0 ? 0 : 1)) }
                    for (let i = 0; i < src.length; i++) {
                        let e = src[i]
                        let a = e.artLarge || e.art
                        if (!a || !e.artist) continue
                        let ak = musicStatsTab.leadArtist(e.artist)
                        if (rank(a) > rank(d[ak])) d[ak] = a
                        let tk = musicStatsTab.trackKey(e.artist, e.title)
                        if (rank(a) > rank(d[tk])) d[tk] = a
                    }
                    return d
                }
                function paletteFor(artist, title, i) {
                    let m = musicStatsTab.paletteIndex.map
                    let p = (title ? m[musicStatsTab.trackKey(artist, title)] : null) || m[musicStatsTab.leadArtist(artist)]
                    if (p) return p
                    let l = musicStatsTab.paletteIndex.list
                    return l.length > 0 ? l[i % l.length] : [String(root.mauve), String(root.blue)]
                }
                function bestArt(e) { return e ? (e.artLarge || musicStatsTab.artFor(e.artist, e.title) || musicStatsTab.hiRes(e.art)) : "" }
                function artFor(artist, title) {
                    let d = musicStatsTab.artIndex
                    return musicStatsTab.hiRes((title ? d[musicStatsTab.trackKey(artist, title)] : "") || d[musicStatsTab.leadArtist(artist)] || "")
                }

                // Album-art thumbnail — local file:// or remote https:// art
                // URL, both work as a plain QML Image source. Falls back to
                // a rounded color swatch (from the cached gradient) when no
                // art is available at all, rather than a broken-image icon.
                component ArtThumb: Rectangle {
                    property string art: ""
                    property string fallbackGrad: ""
                    radius: root.s(6)
                    color: root.surface1
                    clip: true
                    Image {
                        anchors.fill: parent
                        visible: parent.art !== ""
                        source: parent.art
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: parent.art === ""
                        readonly property var swatch: (parent.fallbackGrad || "").match(/#[0-9a-fA-F]{6}/)
                        color: swatch ? swatch[0] : root.surface1
                        radius: parent.radius
                    }
                }

                // Big-number stat card — used for the top strip. A glowing
                // accent-tinted panel rather than a plain text pair, so the
                // headline numbers read at a glance instead of blending into
                // the rest of the page.
                component StatChip: Rectangle {
                    property string value: "—"
                    property string label: ""
                    property color accent: root.mauve
                    property string caption: ""
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(78)
                    radius: root.s(14)
                    color: Qt.alpha(accent, 0.12)
                    border.width: 1
                    border.color: Qt.alpha(accent, 0.3)

                    property bool hovered: chipHoverMa.containsMouse
                    scale: hovered ? 1.03 : 1.0
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

                    Shape {
                        id: chipGlow
                        z: -1
                        anchors.centerIn: parent
                        width: parent.width * 1.1; height: width
                        readonly property color tint: parent.accent
                        opacity: parent.hovered ? 0.55 : 0.32
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        transform: Scale { origin.x: chipGlow.width / 2; origin.y: chipGlow.height / 2; yScale: chipGlow.parent.height * 1.5 / Math.max(1, chipGlow.width) }
                        ShapePath {
                            strokeWidth: -1
                            strokeColor: "transparent"
                            fillGradient: RadialGradient {
                                centerX: chipGlow.width / 2; centerY: chipGlow.height / 2
                                focalX: chipGlow.width / 2; focalY: chipGlow.height / 2
                                centerRadius: chipGlow.width / 2
                                GradientStop { position: 0.0; color: Qt.alpha(chipGlow.tint, 0.6) }
                                GradientStop { position: 1.0; color: Qt.alpha(chipGlow.tint, 0) }
                            }
                            PathRectangle { x: 0; y: 0; width: chipGlow.width; height: chipGlow.height }
                        }
                    }

                    MouseArea { id: chipHoverMa; anchors.fill: parent; hoverEnabled: true }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: root.s(2)
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: parent.parent.value
                            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(24)
                            color: root.text
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: parent.parent.label
                            font.family: "JetBrains Mono"; font.pixelSize: root.s(9)
                            color: root.subtext0
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            visible: text !== ""
                            text: parent.parent.caption
                            font.family: "JetBrains Mono"; font.pixelSize: root.s(8)
                            color: root.subtext1
                        }
                    }
                }

                component GlassTag: Rectangle {
                    property string key: ""
                    property string value: ""
                    property color ink
                    width: glassRow.implicitWidth + root.s(22)
                    height: root.s(28)
                    radius: height / 2
                    color: Qt.alpha(ink, glassMa.containsMouse ? 0.24 : 0.15)
                    border.width: 1; border.color: Qt.alpha(ink, 0.24)
                    scale: glassMa.containsMouse ? 1.05 : 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                    Row {
                        id: glassRow
                        anchors.centerIn: parent
                        spacing: root.s(8)
                        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.key; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(9); font.letterSpacing: root.s(1); color: Qt.alpha(parent.parent.ink, 0.7) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.value; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12); color: parent.parent.ink }
                    }
                    MouseArea { id: glassMa; anchors.fill: parent; hoverEnabled: true }
                }

                component PeriodView: ColumnLayout {
                    id: pv
                    property var host: null
                    property var period: null
                    property string label: ""
                    property string emptyText: ""
                    property int paletteShift: 0
                    property bool active: false
                    readonly property bool hasData: !!period && period.trackedPlays > 0 && host !== null
                    readonly property var artists: hasData ? (period.topArtists || []) : []
                    readonly property var tracks: hasData ? (period.topTracks || []) : []
                    readonly property real span: hasData ? Math.max(1, period.spanDays || 1) : 1
                    readonly property var pal: hasData
                        ? host.paletteFor(artists.length > 0 ? artists[0][0] : "", "", paletteShift)
                        : [String(root.mauve), String(root.blue)]
                    property real prog: 0
                    NumberAnimation { id: pvCount; target: pv; property: "prog"; from: 0; to: 1; duration: 1300; easing.type: Easing.OutCubic }
                    onActiveChanged: if (active) pvCount.restart()
                    Component.onCompleted: if (active) pvCount.restart()
                    Layout.fillWidth: true
                    spacing: root.s(22)

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(120)
                        visible: !pv.hasData
                        radius: root.s(28)
                        color: root.surface0
                        border.width: 1; border.color: root.surface1
                        ColumnLayout {
                            anchors.centerIn: parent
                            width: parent.width - root.s(80)
                            spacing: root.s(6)
                            Text { Layout.alignment: Qt.AlignHCenter; text: "Nothing here yet"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(18); color: root.text }
                            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: pv.emptyText; wrapMode: Text.Wrap; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(240)
                        visible: pv.hasData

                        WrappedBackdrop {
                            id: pvBg
                            anchors.fill: parent
                            anchors.bottomMargin: root.s(14)
                            radius: root.s(32)
                            bedSpread: root.s(24)
                            from1: pv.pal[0]
                            from2: pv.pal[1]
                            art: pv.tracks.length > 0 ? pv.host.bestArt(pv.tracks[0]) : ""
                            live: pv.active
                            wash: 0.5
                        }

                        Item {
                            id: stackBox
                            anchors.left: pvBg.left; anchors.leftMargin: root.s(30)
                            anchors.verticalCenter: pvBg.verticalCenter
                            width: pvBg.height - root.s(52); height: width
                            HoverHandler { id: stackHover }
                            Repeater {
                                model: Math.min(3, pv.tracks.length)
                                delegate: WrappedArt {
                                    z: 3 - index
                                    width: stackBox.width; height: width
                                    radius: root.s(22)
                                    art: pv.host.bestArt(pv.tracks[index])
                                    fallback: Qt.alpha(pvBg.ink, 0.14)
                                    shadowColor: Qt.alpha(pvBg.deep, 0.4)
                                    shadowOffset: root.s(8)
                                    edge: Qt.alpha(pvBg.ink, 0.26)
                                    readonly property real fan: stackHover.hovered ? 1.8 : 1.0
                                    rotation: pv.active ? [-4, 6, 14][index] * fan : 0
                                    x: pv.active ? [0, root.s(16), root.s(30)][index] * fan : 0
                                    scale: [1, 0.9, 0.8][index]
                                    opacity: [1, 0.8, 0.6][index]
                                    Behavior on rotation { NumberAnimation { duration: 650 + index * 120; easing.type: Easing.OutBack } }
                                    Behavior on x { NumberAnimation { duration: 650 + index * 120; easing.type: Easing.OutBack } }
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.left: stackBox.right; anchors.leftMargin: root.s(78)
                            anchors.right: pvBg.right; anchors.rightMargin: root.s(28)
                            anchors.verticalCenter: pvBg.verticalCenter
                            spacing: root.s(4)

                            Rectangle {
                                Layout.preferredWidth: pvEyebrow.implicitWidth + root.s(18)
                                Layout.preferredHeight: root.s(20)
                                Layout.bottomMargin: root.s(2)
                                radius: height / 2
                                color: Qt.alpha(pvBg.ink, 0.16)
                                border.width: 1; border.color: Qt.alpha(pvBg.ink, 0.22)
                                Text {
                                    id: pvEyebrow
                                    anchors.centerIn: parent
                                    text: pv.label + " · LAST " + (pv.host ? pv.host.spanLabel(pv.span) : "")
                                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(9); font.letterSpacing: root.s(1.2)
                                    color: pvBg.ink
                                }
                            }
                            RowLayout {
                                spacing: root.s(10)
                                Text {
                                    text: pv.host ? pv.host.fmtClock((pv.hasData ? pv.period.listenSeconds : 0) * pv.prog) : ""
                                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(56); font.letterSpacing: -root.s(2)
                                    color: pvBg.ink
                                    style: Text.Raised; styleColor: Qt.alpha(pvBg.deep, 0.45)
                                }
                                Text {
                                    Layout.alignment: Qt.AlignBottom
                                    Layout.bottomMargin: root.s(12)
                                    text: "listened"
                                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13)
                                    color: Qt.alpha(pvBg.ink, 0.8)
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: (pv.hasData ? Math.round((pv.period.plays || 0) * pv.prog) : 0) + " plays across all your devices"
                                font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13)
                                color: Qt.alpha(pvBg.ink, 0.86)
                                elide: Text.ElideRight
                            }
                            Flow {
                                Layout.fillWidth: true
                                Layout.topMargin: root.s(10)
                                spacing: root.s(8)
                                GlassTag {
                                    visible: pv.artists.length > 0
                                    ink: pvBg.ink
                                    key: "#1 ARTIST"
                                    value: pv.artists.length > 0 ? pv.artists[0][0] + "  ×" + pv.artists[0][1] : ""
                                }
                                GlassTag {
                                    visible: pv.tracks.length > 0
                                    ink: pvBg.ink
                                    key: "#1 TRACK"
                                    value: pv.tracks.length > 0 ? pv.tracks[0].title + "  ×" + pv.tracks[0].count : ""
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: pv.hasData
                        spacing: root.s(10)
                        StatChip {
                            value: pv.host ? pv.host.fmtClock(pv.hasData ? pv.period.listenSeconds / pv.span : 0) : "—"
                            label: "PER DAY"
                            accent: pv.host ? pv.host.boost(pv.pal[0]) : root.mauve
                        }
                        StatChip {
                            value: pv.hasData ? ((pv.period.plays || 0) / pv.span).toFixed(pv.span < 2 ? 0 : 1) : "—"
                            label: "PLAYS / DAY"
                            accent: pv.host ? pv.host.boost(pv.pal[1]) : root.blue
                        }
                        StatChip {
                            value: {
                                if (!pv.hasData || !pv.period.trackedPlays) return "—"
                                let a = Math.round(pv.period.listenSeconds / pv.period.trackedPlays)
                                return Math.floor(a / 60) + ":" + String(a % 60).padStart(2, "0")
                            }
                            label: "AVG TRACK"
                            accent: pv.host ? pv.host.boost(pv.pal[0]) : root.mauve
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: pv.artists.length > 0
                        spacing: root.s(12)
                        Text { text: "Top artists"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(16); color: root.text }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: root.s(12)
                            Repeater {
                                model: pv.artists.slice(0, 3)
                                delegate: Item {
                                    id: pod
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(158)
                                    readonly property color tint: pv.host.boost(pv.host.paletteFor(modelData[0], "", index + pv.paletteShift + 1)[0])
                                    readonly property real share: modelData[1] / Math.max(1, pv.artists[0][1])
                                    property real reveal: 0
                                    SequentialAnimation {
                                        id: podIn
                                        PropertyAction { target: pod; property: "reveal"; value: 0 }
                                        PauseAnimation { duration: 90 * index }
                                        NumberAnimation { target: pod; property: "reveal"; to: 1; duration: 520; easing.type: Easing.OutBack }
                                    }
                                    Connections { target: pv; function onActiveChanged() { if (pv.active) podIn.restart() } }
                                    Component.onCompleted: if (pv.active) podIn.restart()
                                    opacity: Math.min(1, reveal)
                                    transform: Translate { y: (1 - pod.reveal) * root.s(22) }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: root.s(26)
                                        color: Qt.alpha(pod.tint, podMa.containsMouse ? 0.22 : 0.13)
                                        border.width: 1; border.color: Qt.alpha(pod.tint, podMa.containsMouse ? 0.6 : 0.3)
                                        scale: podMa.pressed ? 0.97 : (podMa.containsMouse ? 1.03 : 1)
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

                                        Text {
                                            anchors.right: parent.right; anchors.rightMargin: root.s(14)
                                            anchors.top: parent.top; anchors.topMargin: -root.s(6)
                                            text: index + 1
                                            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(84)
                                            color: Qt.alpha(pod.tint, index === 0 ? 0.4 : 0.24)
                                        }
                                        WrappedArt {
                                            id: podArt
                                            anchors.left: parent.left; anchors.top: parent.top
                                            anchors.margins: root.s(16)
                                            width: root.s(58); height: width
                                            radius: width / 2
                                            art: pv.host.artFor(modelData[0], "")
                                            fallback: pod.tint
                                            edge: Qt.alpha(pod.tint, 0.5)
                                            rotation: podMa.containsMouse ? -8 : 0
                                            Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                                        }
                                        ColumnLayout {
                                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: podBar.top
                                            anchors.leftMargin: root.s(16); anchors.rightMargin: root.s(16); anchors.bottomMargin: root.s(10)
                                            spacing: 0
                                            Text { Layout.fillWidth: true; text: modelData[0]; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(14); color: root.text; elide: Text.ElideRight }
                                            Text { Layout.fillWidth: true; text: modelData[1] + (modelData[1] === 1 ? " play" : " plays"); font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(10); color: root.subtext0 }
                                        }
                                        Rectangle {
                                            id: podBar
                                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                            anchors.margins: root.s(16)
                                            height: root.s(5); radius: height / 2
                                            color: Qt.alpha(pod.tint, 0.18)
                                            Rectangle {
                                                height: parent.height; radius: parent.radius
                                                width: parent.width * pod.share * Math.max(0, Math.min(1, pod.reveal))
                                                color: pod.tint
                                            }
                                        }
                                        MouseArea { id: podMa; anchors.fill: parent; hoverEnabled: true }
                                    }
                                }
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            visible: pv.artists.length > 3
                            spacing: root.s(8)
                            Repeater {
                                model: pv.artists.slice(3)
                                delegate: Rectangle {
                                    readonly property color tint: pv.host.boost(pv.host.paletteFor(modelData[0], "", index + 4 + pv.paletteShift)[0])
                                    width: restRow.implicitWidth + root.s(20); height: root.s(34)
                                    radius: height / 2
                                    color: restMa.containsMouse ? Qt.alpha(tint, 0.2) : root.surface0
                                    border.width: 1; border.color: Qt.alpha(tint, restMa.containsMouse ? 0.55 : 0.2)
                                    scale: restMa.containsMouse ? 1.06 : 1
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                    Row {
                                        id: restRow
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: root.s(6)
                                        spacing: root.s(8)
                                        WrappedArt { width: root.s(24); height: width; radius: width / 2; art: pv.host.artFor(modelData[0], ""); fallback: parent.parent.tint }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: root.text }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: "×" + modelData[1]; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(11); color: parent.parent.tint }
                                    }
                                    MouseArea { id: restMa; anchors.fill: parent; hoverEnabled: true }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: pv.tracks.length > 0
                        spacing: root.s(8)
                        Text { text: "Top tracks"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(16); color: root.text; Layout.bottomMargin: root.s(4) }
                        Repeater {
                            model: pv.tracks
                            delegate: Item {
                                id: trow
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(60)
                                readonly property color tint: pv.host.boost(pv.host.paletteFor(modelData.artist, modelData.title, index + pv.paletteShift)[0])
                                readonly property real share: modelData.count / Math.max(1, pv.tracks[0].count)
                                property real reveal: 0
                                SequentialAnimation {
                                    id: trowIn
                                    PropertyAction { target: trow; property: "reveal"; value: 0 }
                                    PauseAnimation { duration: 60 * index }
                                    NumberAnimation { target: trow; property: "reveal"; to: 1; duration: 480; easing.type: Easing.OutCubic }
                                }
                                Connections { target: pv; function onActiveChanged() { if (pv.active) trowIn.restart() } }
                                Component.onCompleted: if (pv.active) trowIn.restart()
                                opacity: reveal
                                transform: Translate { y: (1 - trow.reveal) * root.s(16) }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: root.s(20)
                                    color: trowMa.containsMouse ? root.surface1 : root.surface0
                                    border.width: 1; border.color: Qt.alpha(trow.tint, trowMa.containsMouse ? 0.5 : 0.14)
                                    scale: trowMa.containsMouse ? 1.012 : 1
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                    Rectangle {
                                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                        radius: parent.radius
                                        width: Math.max(parent.radius * 2, parent.width * trow.share * trow.reveal)
                                        opacity: trowMa.containsMouse ? 1 : 0.8
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: Qt.alpha(trow.tint, 0.34) }
                                            GradientStop { position: 1.0; color: Qt.alpha(trow.tint, 0.04) }
                                        }
                                    }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: root.s(14); anchors.rightMargin: root.s(12)
                                        spacing: root.s(12)
                                        Text {
                                            Layout.preferredWidth: root.s(28)
                                            text: String(index + 1).padStart(2, "0")
                                            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(16)
                                            color: index === 0 ? trow.tint : root.subtext1
                                        }
                                        WrappedArt {
                                            Layout.preferredWidth: root.s(42); Layout.preferredHeight: root.s(42)
                                            radius: root.s(11)
                                            art: pv.host.bestArt(modelData)
                                            fallback: trow.tint
                                            edge: Qt.alpha(trow.tint, 0.35)
                                            rotation: trowMa.containsMouse ? -5 : 0
                                            scale: trowMa.containsMouse ? 1.08 : 1
                                            Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                                            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Text { Layout.fillWidth: true; text: modelData.title; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(12); color: root.text; elide: Text.ElideRight }
                                            Text { Layout.fillWidth: true; text: modelData.artist; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0; elide: Text.ElideRight }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: trowCount.implicitWidth + root.s(18)
                                            Layout.preferredHeight: root.s(26)
                                            radius: height / 2
                                            color: Qt.alpha(trow.tint, trowMa.containsMouse ? 0.34 : 0.2)
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Text { id: trowCount; anchors.centerIn: parent; text: "×" + modelData.count; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(11); color: root.text }
                                        }
                                    }
                                    MouseArea { id: trowMa; anchors.fill: parent; hoverEnabled: true }
                                }
                            }
                        }
                    }
                }

                Flickable {
                    id: statsFlick
                    anchors.fill: parent
                    anchors.margins: root.s(20)
                    contentWidth: width
                    contentHeight: statsCol.implicitHeight
                    NumberAnimation { id: statsScrollAnim; target: statsFlick; property: "contentY"; duration: 650; easing.type: Easing.OutCubic }
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: statsCol
                        width: parent.width
                        spacing: root.s(22)

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Music Stats"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(28); color: root.text }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                width: root.s(70); height: root.s(26); radius: root.s(13)
                                color: refreshMa.containsMouse ? root.surface1 : root.surface0
                                border.color: root.surface2; border.width: 1
                                Text { anchors.centerIn: parent; text: musicStatsTab.statsLoading ? "…" : "Refresh"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0 }
                                MouseArea { id: refreshMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: musicStatsTab.reload() }
                            }
                        }

                        Item {
                            id: wrappedHost
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(224)
                            visible: wrappedCard.count > 0

                        Item {
                            id: wrappedCard
                            anchors.fill: parent
                            anchors.bottomMargin: root.s(14)
                            readonly property real radius: root.s(32)
                            property int panel: 0
                            property real fillProgress: 0
                            property bool pressed: false
                            property bool entered: false
                            property int seed: 0
                            opacity: entered ? 1 : 0
                            scale: (entered ? 1 : 0.94) * (pressed ? 0.975 : 1.0)
                            Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutQuad } }
                            Behavior on scale { NumberAnimation { duration: 340; easing.type: Easing.OutBack } }
                            Component.onCompleted: { seed = Math.floor(Math.random() * 1024); entered = true }
                            onPanelChanged: fillProgress = 0
                            function bleedAt(i) { return i < panels.length && !!panels[i].art && ((wrappedCard.seed >> i) & 1) === 1 }
                            function step(d) { if (count > 0) panel = (panel + d + count) % count }

                            readonly property var panels: {
                                let s = musicStatsTab.stats
                                let sp = s.spotify
                                let out = []
                                let ta = sp && (sp.topArtistsDerived || []).length > 0 ? sp.topArtistsDerived[0] : null
                                if (ta) out.push({ eyebrow: "YOUR TOP ARTIST", title: ta[0], sub: ta[1] + " plays across your recent history",
                                    art: musicStatsTab.artFor(ta[0], ""), pal: musicStatsTab.paletteFor(ta[0], "", 0) })
                                let tt = sp && (sp.topTracksShort || []).length > 0 ? sp.topTracksShort[0] : null
                                if (tt) out.push({ eyebrow: "YOUR TOP TRACK · 4 WEEKS", title: tt.title, sub: tt.artist,
                                    art: musicStatsTab.bestArt(tt), pal: musicStatsTab.paletteFor(tt.artist, tt.title, 1) })
                                let pe = s.personality
                                if (pe) out.push({ eyebrow: "YOUR LISTENER TYPE", title: pe.archetype.name, sub: pe.archetype.because,
                                    art: musicStatsTab.artFor(pe.facts.superfan.artist, ""), pal: musicStatsTab.paletteFor(pe.facts.superfan.artist, "", 2) })
                                let qt = musicStatsTab.heroQuoteTrack
                                if (qt && musicStatsTab.heroQuote !== "") out.push({ eyebrow: "ON REPEAT · LYRIC", quote: musicStatsTab.heroQuote,
                                    sub: "— " + qt.title + " · " + qt.artist, art: musicStatsTab.bestArt(qt), pal: musicStatsTab.paletteFor(qt.artist, qt.title, 5) })
                                let per = [["THIS WEEK", s.spotifyWeek], ["THIS MONTH", s.spotifyMonth]]
                                for (let k = 0; k < per.length; k++) {
                                    let p = per[k][1]
                                    if (!p || !(p.trackedPlays > 0)) continue
                                    let top = (p.topArtists || []).length > 0 ? p.topArtists[0] : null
                                    let tr = (p.topTracks || []).length > 0 ? p.topTracks[0] : null
                                    out.push({ eyebrow: per[k][0] + " · LAST " + musicStatsTab.spanLabel(p.spanDays),
                                        num: p.listenSeconds || 0, unit: "listened",
                                        sub: (p.plays || 0) + " plays" + (top ? "  ·  #1 " + top[0] + " ×" + top[1] : ""),
                                        art: tr ? musicStatsTab.bestArt(tr) : (top ? musicStatsTab.artFor(top[0], "") : ""),
                                        pal: musicStatsTab.paletteFor(top ? top[0] : "", tr ? tr.title : "", 2 + k) })
                                }
                                if (s.totalPlays > 0) {
                                    let r = (s.recentlyPlayed || [])[0] || {}
                                    out.push({ eyebrow: "THE NUMBERS",
                                        nums: [[s.totalPlays || 0, "plays logged"], [s.bpmOverall ? Math.round(s.bpmOverall) : 0, "avg bpm"], [s.uniqueTracks || 0, "unique tracks"]],
                                        art: musicStatsTab.bestArt(r),
                                        pal: musicStatsTab.gradPair(r.vibrantGrad) || musicStatsTab.paletteFor("", "", 4) })
                                }
                                return out
                            }
                            readonly property int count: panels.length
                            readonly property var cur: count > 0 ? panels[Math.min(panel, count - 1)] : null

                            Timer {
                                interval: 30; repeat: true
                                running: wrappedCard.entered && !wrappedCard.pressed && wrappedHost.visible && musicStatsTab.visible && wrappedCard.count > 1
                                onTriggered: {
                                    wrappedCard.fillProgress += 30 / 5200
                                    if (wrappedCard.fillProgress >= 1) wrappedCard.step(1)
                                }
                            }

                            WrappedBackdrop {
                                id: heroBg
                                anchors.fill: parent
                                radius: wrappedCard.radius
                                bedSpread: root.s(20)
                                from1: wrappedCard.cur ? wrappedCard.cur.pal[0] : root.mauve
                                from2: wrappedCard.cur ? wrappedCard.cur.pal[1] : root.blue
                                art: wrappedCard.cur ? wrappedCard.cur.art : ""
                                live: musicStatsTab.visible
                                wash: wrappedCard.cur && wrappedCard.bleedAt(wrappedCard.panel) ? 0.32 : 0.5

                                Repeater {
                                    model: wrappedCard.panels
                                    delegate: Loader {
                                        active: wrappedCard.bleedAt(index)
                                        sourceComponent: WrappedArt {
                                        readonly property bool shown: wrappedCard.panel === index && wrappedCard.bleedAt(index)
                                        property real sway: 0
                                        width: heroBg.height * 1.5; height: width
                                        x: heroBg.width - width * 0.74 + (shown ? 0 : root.s(70))
                                        y: (heroBg.height - height) / 2 + root.s(26)
                                        radius: root.s(28)
                                        rotation: 9 + sway * 3
                                        art: modelData.art || ""
                                        fallback: Qt.alpha(heroBg.ink, 0.12)
                                        shadowColor: Qt.alpha(heroBg.deep, 0.4)
                                        shadowOffset: root.s(12)
                                        edge: Qt.alpha(heroBg.ink, 0.2)
                                        opacity: shown ? 0.92 : 0
                                        visible: opacity > 0.01
                                        Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                                        Behavior on x { NumberAnimation { duration: 620; easing.type: Easing.OutCubic } }
                                        SequentialAnimation on sway {
                                            running: heroBg.running && shown
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 1; duration: 3800; easing.type: Easing.InOutSine }
                                            NumberAnimation { to: 0; duration: 3800; easing.type: Easing.InOutSine }
                                        }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                width: parent.width * 0.33
                                cursorShape: Qt.PointingHandCursor
                                onPressed: wrappedCard.pressed = true
                                onReleased: wrappedCard.pressed = false
                                onCanceled: wrappedCard.pressed = false
                                onClicked: wrappedCard.step(-1)
                            }
                            MouseArea {
                                anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                                width: parent.width * 0.67
                                cursorShape: Qt.PointingHandCursor
                                onPressed: wrappedCard.pressed = true
                                onReleased: wrappedCard.pressed = false
                                onCanceled: wrappedCard.pressed = false
                                onClicked: wrappedCard.step(1)
                            }

                            Row {
                                id: storyBars
                                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                anchors.topMargin: root.s(16); anchors.leftMargin: root.s(26); anchors.rightMargin: root.s(26)
                                height: root.s(4)
                                spacing: root.s(6)
                                Repeater {
                                    model: wrappedCard.count
                                    delegate: Rectangle {
                                        width: (storyBars.width - storyBars.spacing * (wrappedCard.count - 1)) / Math.max(1, wrappedCard.count)
                                        height: root.s(4); radius: root.s(2)
                                        color: Qt.alpha(heroBg.ink, 0.26)
                                        Rectangle {
                                            height: parent.height; radius: parent.radius
                                            color: heroBg.ink
                                            width: parent.width * (index < wrappedCard.panel ? 1 : (index === wrappedCard.panel ? wrappedCard.fillProgress : 0))
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -root.s(8)
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: wrappedCard.panel = index
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.top: storyBars.bottom; anchors.right: parent.right
                                anchors.topMargin: root.s(10); anchors.rightMargin: root.s(26)
                                text: "WRAPPED  " + (wrappedCard.panel + 1) + "/" + wrappedCard.count
                                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(9); font.letterSpacing: root.s(1.5)
                                color: Qt.alpha(heroBg.ink, 0.7)
                                style: Text.Raised; styleColor: Qt.alpha(heroBg.deep, 0.4)
                            }

                            Item {
                                id: heroStage
                                anchors.fill: parent
                                anchors.leftMargin: root.s(26); anchors.rightMargin: root.s(26)
                                anchors.topMargin: root.s(38); anchors.bottomMargin: root.s(22)

                                Repeater {
                                    model: wrappedCard.panels
                                    delegate: Item {
                                        id: pnl
                                        width: heroStage.width; height: heroStage.height
                                        readonly property bool isActive: wrappedCard.panel === index
                                        readonly property bool bleed: wrappedCard.bleedAt(index)
                                        readonly property real tilt: [-4, 3, -3, 4, -2][index % 5]
                                        property real shift: isActive ? 0 : (index < wrappedCard.panel ? -root.s(44) : root.s(44))
                                        property real prog: 0
                                        opacity: isActive ? 1 : 0
                                        visible: opacity > 0.01
                                        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                                        Behavior on shift { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }
                                        NumberAnimation { id: countUp; target: pnl; property: "prog"; from: 0; to: 1; duration: 1200; easing.type: Easing.OutCubic }
                                        onIsActiveChanged: if (isActive) countUp.restart()
                                        Component.onCompleted: if (isActive) countUp.restart()

                                        Loader {
                                            id: tile
                                            active: !pnl.bleed
                                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                            width: parent.height; height: width
                                            sourceComponent: WrappedArt {
                                                radius: root.s(24)
                                                art: modelData.art || ""
                                                fallback: Qt.alpha(heroBg.ink, 0.14)
                                                shadowColor: Qt.alpha(heroBg.deep, 0.45)
                                                shadowOffset: root.s(8)
                                                edge: Qt.alpha(heroBg.ink, 0.28)
                                            }
                                            rotation: pnl.isActive ? pnl.tilt : pnl.tilt * 3
                                            scale: pnl.isActive ? 1 : 0.84
                                            Behavior on rotation { NumberAnimation { duration: 560; easing.type: Easing.OutBack } }
                                            Behavior on scale { NumberAnimation { duration: 560; easing.type: Easing.OutBack } }
                                            transform: Translate { x: pnl.shift * 0.4 }
                                        }

                                        Rectangle {
                                            id: textPill
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: pnl.bleed ? -root.s(6) : tile.width + root.s(28)
                                            width: pnl.bleed ? Math.min(heroCol.implicitWidth + root.s(40), parent.width * 0.64) : parent.width - x
                                            height: heroCol.implicitHeight + (pnl.bleed ? root.s(30) : 0)
                                            radius: root.s(22)
                                            color: pnl.bleed ? Qt.alpha(heroBg.deep, 0.52) : "transparent"
                                            border.width: pnl.bleed ? 1 : 0
                                            border.color: Qt.alpha(heroBg.ink, 0.14)
                                            transform: Translate { x: pnl.shift }

                                            ColumnLayout {
                                                id: heroCol
                                                anchors.left: parent.left; anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.leftMargin: pnl.bleed ? root.s(20) : 0
                                                anchors.rightMargin: pnl.bleed ? root.s(20) : 0
                                                spacing: root.s(4)

                                                Rectangle {
                                                    Layout.preferredWidth: eyebrowTxt.implicitWidth + root.s(18)
                                                    Layout.preferredHeight: root.s(20)
                                                    Layout.bottomMargin: root.s(4)
                                                    radius: height / 2
                                                    color: Qt.alpha(heroBg.ink, 0.16)
                                                    border.width: 1; border.color: Qt.alpha(heroBg.ink, 0.22)
                                                    Text {
                                                        id: eyebrowTxt
                                                        anchors.centerIn: parent
                                                        text: modelData.eyebrow
                                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(9); font.letterSpacing: root.s(1.2)
                                                        color: heroBg.ink
                                                    }
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    visible: modelData.title !== undefined
                                                    text: modelData.title || ""
                                                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(38); font.letterSpacing: -root.s(1)
                                                    color: heroBg.ink
                                                    style: Text.Raised; styleColor: Qt.alpha(heroBg.deep, 0.45)
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    visible: modelData.quote !== undefined
                                                    text: "“" + (modelData.quote || "") + "”"
                                                    wrapMode: Text.WordWrap
                                                    maximumLineCount: 2
                                                    elide: Text.ElideRight
                                                    lineHeight: 1.05
                                                    font.family: "JetBrains Mono"; font.italic: true; font.weight: Font.Black; font.pixelSize: root.s(24); font.letterSpacing: -root.s(0.5)
                                                    color: heroBg.ink
                                                    style: Text.Raised; styleColor: Qt.alpha(heroBg.deep, 0.45)
                                                }
                                                RowLayout {
                                                    visible: modelData.num !== undefined
                                                    spacing: root.s(10)
                                                    Text {
                                                        text: musicStatsTab.fmtClock((modelData.num || 0) * pnl.prog)
                                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(50); font.letterSpacing: -root.s(1.5)
                                                        color: heroBg.ink
                                                        style: Text.Raised; styleColor: Qt.alpha(heroBg.deep, 0.45)
                                                    }
                                                    Text {
                                                        Layout.alignment: Qt.AlignBottom
                                                        Layout.bottomMargin: root.s(10)
                                                        text: modelData.unit || ""
                                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13)
                                                        color: Qt.alpha(heroBg.ink, 0.8)
                                                    }
                                                }
                                                RowLayout {
                                                    visible: modelData.nums !== undefined
                                                    spacing: root.s(30)
                                                    Repeater {
                                                        model: modelData.nums || []
                                                        delegate: ColumnLayout {
                                                            spacing: -root.s(2)
                                                            Text {
                                                                text: Math.round(modelData[0] * pnl.prog)
                                                                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(44); font.letterSpacing: -root.s(1.5)
                                                                color: heroBg.ink
                                                                style: Text.Raised; styleColor: Qt.alpha(heroBg.deep, 0.45)
                                                            }
                                                            Text {
                                                                text: modelData[1]
                                                                font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11)
                                                                color: Qt.alpha(heroBg.ink, 0.8)
                                                            }
                                                        }
                                                    }
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    visible: text !== ""
                                                    text: modelData.sub || ""
                                                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13)
                                                    color: Qt.alpha(heroBg.ink, 0.86)
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        }

                        Item {
                            id: subTabBar
                            Layout.fillWidth: true
                            Layout.topMargin: -root.s(8)
                            Layout.preferredHeight: root.s(42)
                            Rectangle {
                                width: segRow.implicitWidth + root.s(10)
                                height: parent.height
                                radius: height / 2
                                color: root.surface0
                                border.width: 1; border.color: root.surface1
                                Rectangle {
                                    x: segRow.x + segRow.kx
                                    y: root.s(5)
                                    width: segRow.kw
                                    height: parent.height - root.s(10)
                                    radius: height / 2
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: heroBg.tone1 }
                                        GradientStop { position: 1.0; color: heroBg.tone2 }
                                    }
                                    Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                                    Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                                }
                                Row {
                                    id: segRow
                                    property real kx: 0
                                    property real kw: 0
                                    x: root.s(5)
                                    anchors.verticalCenter: parent.verticalCenter
                                    Repeater {
                                        id: segRep
                                        model: ["Overview", "This Week", "This Month", "Your Vibe"]
                                        delegate: Item {
                                            id: segItem
                                            readonly property bool isActive: musicStatsTab.subTab === index
                                            width: segTxt.implicitWidth + root.s(32)
                                            height: root.s(32)
                                            function claim() { if (isActive) { segRow.kx = x; segRow.kw = width } }
                                            onIsActiveChanged: claim()
                                            onXChanged: claim()
                                            onWidthChanged: claim()
                                            Component.onCompleted: claim()
                                            Text {
                                                id: segTxt
                                                anchors.centerIn: parent
                                                text: modelData
                                                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(11)
                                                color: parent.isActive ? heroBg.ink : (segMa.containsMouse ? root.text : root.subtext0)
                                                scale: segMa.pressed ? 0.94 : 1
                                                Behavior on color { ColorAnimation { duration: 180 } }
                                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                                            }
                                            MouseArea {
                                                id: segMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: musicStatsTab.subTab = index
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: musicStatsTab.subTab === 0
                            spacing: root.s(22)

                        Text {
                            Layout.fillWidth: true
                            visible: musicStatsTab.stats.totalPlays === 0
                            text: "No plays logged locally yet — play something and check back. (The Spotify section below already has your real history.)"
                            font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0
                            wrapMode: Text.Wrap
                        }

                        // Headline stat strip — the numbers that used to be
                        // a plain sentence, now five glowing cards. Listening
                        // time is honest about partial coverage (only plays
                        // logged after durationSec was added carry a real
                        // duration) rather than implying it covers everything.
                        RowLayout {
                            Layout.fillWidth: true
                            visible: musicStatsTab.stats.totalPlays > 0
                            spacing: root.s(10)
                            StatChip {
                                value: musicStatsTab.stats.totalPlays || 0
                                label: "PLAYS LOGGED"
                                accent: root.mauve
                            }
                            StatChip {
                                value: musicStatsTab.fmtDuration(musicStatsTab.stats.listenSeconds)
                                label: "LISTENING TIME"
                                caption: musicStatsTab.stats.trackedPlays < musicStatsTab.stats.totalPlays
                                    ? "of " + musicStatsTab.stats.trackedPlays + " timed plays" : ""
                                accent: root.blue
                            }
                            StatChip {
                                value: musicStatsTab.stats.uniqueTracks || 0
                                label: "UNIQUE TRACKS"
                                accent: root.pink
                            }
                            StatChip {
                                value: musicStatsTab.stats.uniqueArtists || 0
                                label: "UNIQUE ARTISTS"
                                accent: root.sapphire
                            }
                            StatChip {
                                value: musicStatsTab.fmtHour(musicStatsTab.stats.topHour)
                                label: "PEAK HOUR"
                                accent: root.yellow
                            }
                        }

                        // Album-color moodboard — a strip of recent tracks'
                        // vibrant colors, most recent first. Purely visual,
                        // no labels — the point is the shape of your last
                        // ~25 plays as a color read, not a data table.
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: (musicStatsTab.stats.recentlyPlayed || []).length > 0
                            spacing: root.s(8)
                            Text { text: "Recent color trail"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                            Flow {
                                Layout.fillWidth: true
                                spacing: root.s(5)
                                Repeater {
                                    model: musicStatsTab.stats.recentlyPlayed || []
                                    delegate: Rectangle {
                                        readonly property var swatch: (modelData.vibrantGrad || modelData.grad || "").match(/#[0-9a-fA-F]{6}/)
                                        width: root.s(24); height: root.s(24); radius: root.s(6)
                                        color: swatch ? swatch[0] : root.surface1
                                        scale: moodMa.containsMouse ? 1.25 : 1.0
                                        z: moodMa.containsMouse ? 2 : 1
                                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                        MouseArea { id: moodMa; anchors.fill: parent; hoverEnabled: true }

                                        Rectangle {
                                            visible: moodMa.containsMouse
                                            anchors.bottom: parent.top; anchors.bottomMargin: root.s(6)
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: tipTxt.implicitWidth + root.s(16); height: root.s(24); radius: root.s(6)
                                            color: root.surface0
                                            border.width: 1; border.color: root.surface2
                                            Text {
                                                id: tipTxt
                                                anchors.centerIn: parent
                                                text: musicStatsTab.trackLine(modelData.artist, modelData.title)
                                                font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.text
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Listening by hour — a 24-slot grid is almost
                        // entirely empty columns with only a handful of
                        // plays logged (looks broken, not "sparse"). A
                        // ranked top-hours list stays dense and readable at
                        // any history size instead of degrading with it.
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: (musicStatsTab.stats.topHours || []).length > 0
                            spacing: root.s(8)
                            Text { text: "When you listen"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                            Repeater {
                                model: musicStatsTab.stats.topHours || []
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(30)
                                    radius: root.s(8)
                                    color: root.surface0
                                    readonly property real maxCount: (musicStatsTab.stats.topHours && musicStatsTab.stats.topHours.length > 0) ? musicStatsTab.stats.topHours[0].count : 1
                                    readonly property bool isPeak: index === 0
                                    Rectangle {
                                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                        radius: parent.radius
                                        width: Math.max(root.s(28), parent.width * (modelData.count / parent.maxCount))
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: Qt.alpha(root.mauve, parent.parent.isPeak ? 0.5 : 0.28) }
                                            GradientStop { position: 1.0; color: Qt.alpha(root.mauve, parent.parent.isPeak ? 0.18 : 0.08) }
                                        }
                                        Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutQuad } }
                                    }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: root.s(8)
                                        Text {
                                            text: musicStatsTab.fmtHour(modelData.hour)
                                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11)
                                            color: root.text
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: modelData.count + (modelData.count === 1 ? " play" : " plays")
                                            font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0
                                        }
                                    }
                                }
                            }
                        }

                        // BPM + this-week-on-Spotify — compact inline pills
                        // rather than the same big StatChip boxes used above,
                        // since these are secondary numbers, not headline ones.
                        RowLayout {
                            Layout.fillWidth: true
                            visible: !!musicStatsTab.stats.bpmOverall || !!musicStatsTab.stats.spotifyWeek
                            spacing: root.s(10)
                            Repeater {
                                model: {
                                    let items = []
                                    if (musicStatsTab.stats.bpmToday) items.push({label: "TODAY'S BPM", value: musicStatsTab.stats.bpmToday.toFixed(0), accent: root.mauve})
                                    if (musicStatsTab.stats.bpmOverall) items.push({label: "OVERALL BPM", value: musicStatsTab.stats.bpmOverall.toFixed(0), accent: root.blue})
                                    if (musicStatsTab.stats.spotifyWeek && musicStatsTab.stats.spotifyWeek.trackedPlays > 0) {
                                        let sw = musicStatsTab.stats.spotifyWeek
                                        items.push({
                                            label: "SPOTIFY, LAST " + sw.spanDays + "d (ALL DEVICES)",
                                            value: musicStatsTab.fmtDuration(sw.listenSeconds),
                                            accent: root.green
                                        })
                                    }
                                    return items
                                }
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(44)
                                    radius: root.s(10)
                                    color: Qt.alpha(modelData.accent, 0.12)
                                    border.width: 1; border.color: Qt.alpha(modelData.accent, 0.3)
                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: root.s(8)
                                        Text { text: modelData.value; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(17); color: root.text }
                                        Text { text: modelData.label; font.family: "JetBrains Mono"; font.pixelSize: root.s(8); color: root.subtext0 }
                                    }
                                }
                            }
                        }

                        // On this day — card list with real art, not plain text rows.
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: (musicStatsTab.stats.onThisDay || []).length > 0
                            spacing: root.s(8)
                            Text { text: "On this day"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                            Repeater {
                                model: musicStatsTab.stats.onThisDay || []
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(44)
                                    radius: root.s(10)
                                    color: onThisDayMa.containsMouse ? root.surface1 : root.surface0
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    MouseArea { id: onThisDayMa; anchors.fill: parent; hoverEnabled: true }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: root.s(8)
                                        spacing: root.s(10)
                                        ArtThumb { art: modelData.art || ""; fallbackGrad: modelData.grad; Layout.preferredWidth: root.s(28); Layout.preferredHeight: root.s(28) }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Text { Layout.fillWidth: true; text: modelData.title; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: root.text; elide: Text.ElideRight }
                                            Text { Layout.fillWidth: true; text: modelData.artist; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0; elide: Text.ElideRight }
                                        }
                                        Text { text: modelData.daysAgo + "d ago"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext1 }
                                    }
                                }
                            }
                        }

                        // ---------------- LOCAL section ----------------
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: root.s(8)
                            spacing: root.s(2)
                            Text { text: "THIS MACHINE"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(11); color: root.subtext1 }
                            Rectangle { Layout.fillWidth: true; height: root.s(2); radius: root.s(1); color: root.mauve; opacity: 0.4 }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: root.s(20)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(20)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(8)
                                    Text { text: "Most played — all time"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                    Repeater {
                                        model: musicStatsTab.stats.topAllTime || []
                                        delegate: Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: root.s(38)
                                            radius: root.s(8)
                                            color: root.surface0
                                            readonly property real maxCount: musicStatsTab.stats.topAllTime && musicStatsTab.stats.topAllTime.length > 0 ? musicStatsTab.stats.topAllTime[0].count : 1
                                            Rectangle {
                                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                                radius: parent.radius
                                                width: parent.width * (modelData.count / parent.maxCount)
                                                color: root.mauve; opacity: 0.16
                                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }
                                            }
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: root.s(6)
                                                spacing: root.s(8)
                                                ArtThumb { art: modelData.art || ""; fallbackGrad: modelData.grad; Layout.preferredWidth: root.s(26); Layout.preferredHeight: root.s(26) }
                                                Text { Layout.fillWidth: true; text: musicStatsTab.trackLine(modelData.artist, modelData.title); font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.text; elide: Text.ElideRight }
                                                Text { text: "×" + modelData.count; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: root.mauve }
                                            }
                                        }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(8)
                                    Text { text: "Most played — this week"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                    Repeater {
                                        model: musicStatsTab.stats.topThisWeek || []
                                        delegate: Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: root.s(38)
                                            radius: root.s(8)
                                            color: root.surface0
                                            readonly property real maxCount: musicStatsTab.stats.topThisWeek && musicStatsTab.stats.topThisWeek.length > 0 ? musicStatsTab.stats.topThisWeek[0].count : 1
                                            Rectangle {
                                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                                radius: parent.radius
                                                width: parent.width * (modelData.count / parent.maxCount)
                                                color: root.blue; opacity: 0.16
                                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }
                                            }
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: root.s(6)
                                                spacing: root.s(8)
                                                ArtThumb { art: modelData.art || ""; fallbackGrad: modelData.grad; Layout.preferredWidth: root.s(26); Layout.preferredHeight: root.s(26) }
                                                Text { Layout.fillWidth: true; text: musicStatsTab.trackLine(modelData.artist, modelData.title); font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.text; elide: Text.ElideRight }
                                                Text { text: "×" + modelData.count; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: root.blue }
                                            }
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(8)
                                Text { text: "Recently played"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Repeater {
                                    model: (musicStatsTab.stats.recentlyPlayed || []).slice(0, 12)
                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(34)
                                        radius: root.s(8)
                                        color: recentMa.containsMouse ? root.surface1 : "transparent"
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        MouseArea { id: recentMa; anchors.fill: parent; hoverEnabled: true }
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: root.s(5)
                                            spacing: root.s(8)
                                            ArtThumb { art: modelData.art || ""; fallbackGrad: modelData.grad; Layout.preferredWidth: root.s(24); Layout.preferredHeight: root.s(24) }
                                            Text { Layout.fillWidth: true; text: musicStatsTab.trackLine(modelData.artist, modelData.title); font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight }
                                            Text { text: Qt.formatDateTime(new Date(modelData.ts * 1000), "MMM d, HH:mm"); font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext1 }
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: root.s(8)
                            spacing: root.s(2)
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: musicStatsTab.stats.spotify
                                        ? "SPOTIFY — as of " + Qt.formatDateTime(new Date(musicStatsTab.stats.spotify.fetchedAt * 1000), "MMM d, HH:mm")
                                        : "SPOTIFY — not fetched yet"
                                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: root.s(11); color: root.subtext1
                                }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    width: root.s(110); height: root.s(24); radius: root.s(12)
                                    color: spotifyRefreshMa.containsMouse ? root.surface1 : root.surface0
                                    border.color: root.surface2; border.width: 1
                                    Text { anchors.centerIn: parent; text: musicStatsTab.spotifyRefreshing ? "Fetching…" : "Refresh Spotify"; font.family: "JetBrains Mono"; font.pixelSize: root.s(9); color: root.subtext0 }
                                    MouseArea { id: spotifyRefreshMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: musicStatsTab.refreshSpotify() }
                                }
                            }
                            Rectangle { Layout.fillWidth: true; height: root.s(2); radius: root.s(1); color: root.green; opacity: 0.4 }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: !!musicStatsTab.stats.spotify
                            spacing: root.s(20)

                            // Top artists — derived from track data (the API's own
                            // top-artists endpoint was erroring at the time this
                            // was built), shown as a wrapped chip row.
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(8)
                                visible: !!musicStatsTab.stats.spotify && (musicStatsTab.stats.spotify.topArtistsDerived || []).length > 0
                                Text { text: "Top artists"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: root.s(6)
                                    Repeater {
                                        model: musicStatsTab.stats.spotify ? musicStatsTab.stats.spotify.topArtistsDerived : []
                                        delegate: Rectangle {
                                            width: chipText.implicitWidth + root.s(16); height: root.s(24); radius: root.s(12)
                                            color: artistChipMa.containsMouse ? Qt.alpha(root.green, 0.22) : root.surface1
                                            border.width: 1; border.color: artistChipMa.containsMouse ? Qt.alpha(root.green, 0.5) : "transparent"
                                            scale: artistChipMa.containsMouse ? 1.06 : 1.0
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                            MouseArea { id: artistChipMa; anchors.fill: parent; hoverEnabled: true }
                                            Text { id: chipText; anchors.centerIn: parent; text: modelData[0] + " ×" + modelData[1]; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.text }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(20)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(8)
                                    Text { text: "Top tracks — last 4 weeks"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                    Repeater {
                                        model: musicStatsTab.stats.spotify ? musicStatsTab.stats.spotify.topTracksShort : []
                                        delegate: RowLayout {
                                            Layout.fillWidth: true
                                            spacing: root.s(8)
                                            ArtThumb { art: modelData.art || ""; Layout.preferredWidth: root.s(32); Layout.preferredHeight: root.s(32) }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text { Layout.fillWidth: true; text: modelData.title; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: root.text; elide: Text.ElideRight }
                                                Text { Layout.fillWidth: true; text: modelData.artist; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0; elide: Text.ElideRight }
                                            }
                                        }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(8)
                                    Text { text: "Top tracks — last year"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                    Repeater {
                                        model: musicStatsTab.stats.spotify ? musicStatsTab.stats.spotify.topTracksLong : []
                                        delegate: RowLayout {
                                            Layout.fillWidth: true
                                            spacing: root.s(8)
                                            ArtThumb { art: modelData.art || ""; Layout.preferredWidth: root.s(32); Layout.preferredHeight: root.s(32) }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text { Layout.fillWidth: true; text: modelData.title; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(11); color: root.text; elide: Text.ElideRight }
                                                Text { Layout.fillWidth: true; text: modelData.artist; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0; elide: Text.ElideRight }
                                            }
                                        }
                                    }
                                }
                            }

                            // Recently played, across every device — this is
                            // the part the local log genuinely can't see.
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: root.s(8)
                                Text { text: "Recently played — all devices"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                Repeater {
                                    model: musicStatsTab.stats.spotify ? musicStatsTab.stats.spotify.recentlyPlayed.slice(0, 15) : []
                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        spacing: root.s(8)
                                        ArtThumb { art: modelData.art || ""; Layout.preferredWidth: root.s(24); Layout.preferredHeight: root.s(24) }
                                        Text { Layout.fillWidth: true; text: musicStatsTab.trackLine(modelData.artist, modelData.title); font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0; elide: Text.ElideRight }
                                        Text { text: modelData.ts ? Qt.formatDateTime(new Date(modelData.ts * 1000), "MMM d, HH:mm") : ""; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext1 }
                                    }
                                }
                            }
                        }
                        } // end Overview sub-tab wrapper

                        Loader {
                            Layout.fillWidth: true
                            visible: musicStatsTab.subTab === 1
                            active: visible || item !== null
                            asynchronous: true
                            sourceComponent: PeriodView {
                                host: musicStatsTab
                                period: musicStatsTab.stats.spotifyWeek || null
                                label: "THIS WEEK"
                                paletteShift: 0
                                emptyText: "No Spotify history collected for this window yet — the accumulator only started recently, check back soon."
                                active: musicStatsTab.subTab === 1 && musicStatsTab.visible
                            }
                        }

                        Loader {
                            Layout.fillWidth: true
                            visible: musicStatsTab.subTab === 2
                            active: visible || item !== null
                            asynchronous: true
                            sourceComponent: PeriodView {
                                host: musicStatsTab
                                period: musicStatsTab.stats.spotifyMonth || null
                                label: "THIS MONTH"
                                paletteShift: 3
                                emptyText: "No Spotify history collected for this window yet — the accumulator needs about a month of uptime to fill this in."
                                active: musicStatsTab.subTab === 2 && musicStatsTab.visible
                            }
                        }

                        Loader {
                            Layout.fillWidth: true
                            visible: musicStatsTab.subTab === 3
                            active: visible || item !== null
                            asynchronous: true
                            sourceComponent: MusicVibeView {
                                host: musicStatsTab
                                ui: root
                                active: musicStatsTab.subTab === 3 && musicStatsTab.visible
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
