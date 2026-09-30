.pragma library

function getScale(mw, userScale) {
    if (mw <= 0) return 1.0;
    let r = mw / 1920.0;
    let baseScale = 1.0;
    
    if (r <= 1.0) {
        baseScale = Math.max(0.35, Math.pow(r, 0.85));
    } else {
        // SCALING UP:
        baseScale = Math.pow(r, 0.5);
    }
    
    // Multiply the screen-calculated scale by the user's uiScale
    return baseScale * (userScale !== undefined ? userScale : 1.0);
}

// Helper to easily round scaled values
function s(val, scale) {
    return Math.round(val * scale);
}

// Centralized registry for all widget dimensions and positional mathematics.
function getLayout(name, mx, my, mw, mh, userScale, styles) {
    let scale = getScale(mw, userScale);

    let base = {
        // Right-aligned: pinned 20px from the right edge dynamically
        // Note on rx: The 500 represents the 480 base width + 20 margin. 
        "battery":   { w: s(480, scale), h: s(860, scale), rx: mw - s(500, scale), ry: s(70, scale), comp: "battery/BatteryPopup.qml" },
        "volume":    { w: s(480, scale), h: s(760, scale), rx: mw - s(500, scale), ry: s(70, scale), comp: (styles && styles.volume === "revamp") ? "volume/VolumePopupRevamp.qml" : "volume/VolumePopup.qml" },
        "notifications": { w: s(480, scale), h: s(850, scale), rx: mw - s(500, scale), ry: s(70, scale), comp: (styles && styles.notifications_center === "revamp") ? "notifications/NotificationCenterRevamp.qml" : "notifications/NotificationCenter.qml" },
        
        // Centered horizontally dynamically based on current screen width
        "calendar":  { w: s(1450, scale), h: s(750, scale), rx: Math.floor((mw/2)-(s(1450, scale)/2)), ry: s(70, scale), comp: "calendar/CalendarPopup.qml" },
        
        // Left-aligned: pinned 12px from the left edge
        "music":     { w: s(700, scale), h: s(700, scale), rx: s(12, scale), ry: s(70, scale), comp: "music/MusicPopup.qml" },
        
        // Right-aligned: pinned 20px from the right edge dynamically (Width: 900 + 20 margin = 920)
        "network":   { w: s(900, scale), h: s(700, scale), rx: mw - s(920, scale), ry: s(70, scale), comp: "network/NetworkPopup.qml" },

        // Bottom sheet: sized to hug its own deck layout (no side padding
        // wasted on empty monitor width), centered horizontally, flush
        // against the true bottom edge. Only the top corners are rounded.
        "quicksettings": { w: s(920, scale), h: s(330, scale), rx: Math.floor((mw/2)-(s(920, scale)/2)), ry: mh - s(330, scale), comp: "quicksettings/QuickSettingsDrawer.qml" },
        
        // Centered both horizontally and vertically
        "stewart":   { w: s(800, scale), h: s(600, scale), rx: Math.floor((mw/2)-(s(800, scale)/2)), ry: Math.floor((mh/2)-(s(600, scale)/2)), comp: "stewart/stewart.qml" },
        "monitors":  { w: s(850, scale), h: s(580, scale), rx: Math.floor((mw/2)-(s(850, scale)/2)), ry: Math.floor((mh/2)-(s(580, scale)/2)), comp: (styles && styles.monitors === "revamp") ? "monitors/MonitorPopupRevamp.qml" : "monitors/MonitorPopup.qml" },
        "focustime": { w: s(900, scale), h: s(720, scale), rx: Math.floor((mw/2)-(s(900, scale)/2)), ry: Math.floor((mh/2)-(s(720, scale)/2)), comp: (styles && styles.focustime === "revamp") ? "focustime/FocusTimePopupRevamp.qml" : "focustime/FocusTimePopup.qml" },
        
        // Guide Popup (Centered)
        "guide":     { w: s(1200, scale), h: s(750, scale), rx: Math.floor((mw/2)-(s(1200, scale)/2)), ry: Math.floor((mh/2)-(s(750, scale)/2)), comp: "guide/GuidePopup.qml" },
        // Full width, centered vertically
        "wallpaper": { w: mw, h: s(650, scale), rx: 0, ry: Math.floor((mh/2)-(s(650, scale)/2)), comp: (styles && styles.wallpaper === "revamp") ? "wallpaper/WallpaperPickerRevamp.qml" : "wallpaper/WallpaperPicker.qml" },
        
        "workspaces": { w: mw, h: mh, rx: 0, ry: 0, comp: (styles && styles.workspaces === "revamp") ? "WorkspaceOverviewRevamp.qml" : "WorkspaceOverview.qml" },
        "power":      { w: mw, h: mh, rx: 0, ry: 0, comp: "power/PowerMenu.qml" },

        "applauncher": { w: s(800, scale), h: s(700, scale), rx: Math.floor((mw/2)-(s(800, scale)/2)), ry: Math.floor((mh/2)-(s(700, scale)/2)), comp: "applauncher/appLauncher.qml" },
        "clipboard": { w: s(800, scale), h: s(700, scale), rx: Math.floor((mw/2)-(s(800, scale)/2)), ry: Math.floor((mh/2)-(s(700, scale)/2)), comp: "clipboard/ClipboardManager.qml" },
        "claudeask": { w: s(920, scale), h: s(720, scale), rx: Math.floor((mw/2)-(s(920, scale)/2)), ry: Math.floor((mh/2)-(s(720, scale)/2)), comp: "claude/ClaudeAsk.qml" },
        "quicktell": { w: s(720, scale), h: s(260, scale), rx: Math.floor((mw/2)-(s(720, scale)/2)), ry: Math.floor((mh/2)-(s(260, scale)/2)), comp: "claude/QuickTell.qml" },

        // agent-only widgets — no keybind, opened via MCP open_widget
        "people":    { w: s(1080, scale), h: s(680, scale), rx: Math.floor((mw/2)-(s(1080, scale)/2)), ry: Math.floor((mh/2)-(s(680, scale)/2)), comp: "agentwidgets/PeopleWidget.qml" },
        "memory":    { w: s(760, scale), h: s(680, scale), rx: Math.floor((mw/2)-(s(760, scale)/2)), ry: Math.floor((mh/2)-(s(680, scale)/2)), comp: "agentwidgets/MemoryWidget.qml" },
        "netstatus": { w: s(520, scale), h: s(560, scale), rx: Math.floor((mw/2)-(s(520, scale)/2)), ry: Math.floor((mh/2)-(s(560, scale)/2)), comp: "agentwidgets/NetworkWidget.qml" },

        "hidden":    { w: 1, h: 1, rx: -5000 - mx, ry: -5000 - my, comp: "" }
    };

    if (!base[name]) return null;
    
    let t = base[name];
    // Calculate final absolute coordinates based on active monitor offset
    t.x = mx + t.rx;
    t.y = my + t.ry;
    
    return t;
}

function getPopupLayout(mw, userScale) {
    let scale = getScale(mw, userScale);
    return {
        w: s(350, scale),
        marginTop: s(60, scale),
        marginRight: s(20, scale),
        spacing: s(12, scale),
        radius: s(14, scale),
        padding: s(12, scale)
    };
}
