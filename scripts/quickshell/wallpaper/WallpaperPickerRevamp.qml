import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtCore
import Qt.labs.folderlistmodel
import QtMultimedia
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window
    width: Screen.width

    Scaler {
        id: scaler
        currentWidth: Screen.width
    }

    function s(val) {
        return scaler.s(val);
    }

    MatugenColors { id: _theme }

    // -------------------------------------------------------------------------
    // PROPERTIES & IPC RECEIVER
    // -------------------------------------------------------------------------
    property string widgetArg: ""
    property string targetWallName: ""
    property bool initialFocusSet: false
    property int visibleItemCount: -1
    property int scrollAccum: 0
    property real scrollThreshold: window.s(300)

    // Revamp: browse mode + auxiliary UI state
    property string browseMode: "coverflow"
    property bool claudeExpanded: false
    property string focusedSize: ""

    // Filter System Properties
    property string currentFilter: "All"
    property string _lastFilter: "All"
    property string searchQuery: ""
    property bool isOnlineSearch: false
    property bool isSearchPaused: false
    property bool hasSearched: false
    property var colorMap: ({})
    property int cacheVersion: 0

    // Download and Status Tracking Properties
    property bool isDownloadingWallpaper: false
    property string currentDownloadName: ""

    // STRICT ARCHITECTURAL LOCK
    property bool isApplying: false
    property int flashTrigger: 0

    // Reactive Status Properties
    property bool isStartup: localFolderModel.status === FolderListModel.Loading || srcModel.status === FolderListModel.Loading
    property bool isReady: visible && localFolderModel.status === FolderListModel.Ready
    property bool isSearchActive: window.currentFilter === "Search" && window.hasSearched && searchFolderModel.status === FolderListModel.Loading

    // Memory Properties for Search
    property string lastSearchName: ""
    property bool isModelChanging: false
    property bool searchIndexRestored: false

    property bool isScrollingBlocked: window.currentFilter === "Search" && window.hasSearched && window.isSearchActive && !window.isSearchPaused
    property bool jumpToLastOnFilterChange: false

    readonly property var filterData: [
        { name: "All", hex: "", label: "All" },
        { name: "Video", hex: "", label: "Vid" },
        { name: "Red", hex: "#FF4500", label: "" },
        { name: "Orange", hex: "#FFA500", label: "" },
        { name: "Yellow", hex: "#FFD700", label: "" },
        { name: "Green", hex: "#32CD32", label: "" },
        { name: "Blue", hex: "#1E90FF", label: "" },
        { name: "Purple", hex: "#8A2BE2", label: "" },
        { name: "Pink", hex: "#FF69B4", label: "" },
        { name: "Monochrome", hex: "#A9A9A9", label: "" },
        { name: "Search", hex: "", label: "Search" }
    ]

    // Revamp: focused item resolution (works in both grid and coverflow)
    readonly property string focusedName: {
        let m = window.activeModel;
        if (m && view.currentIndex >= 0 && view.currentIndex < m.count) {
            let it = m.get(view.currentIndex);
            return it ? String(it.fileName || "") : "";
        }
        return "";
    }
    readonly property string focusedUrl: {
        let m = window.activeModel;
        if (m && view.currentIndex >= 0 && view.currentIndex < m.count) {
            let it = m.get(view.currentIndex);
            return it ? String(it.fileUrl || "") : "";
        }
        return "";
    }
    readonly property bool focusedIsVideo: window.focusedName.startsWith("000_")
    readonly property var focusedPalette: (window.cacheVersion, window.paletteFor(window.focusedName))

    function paletteFor(name) {
        let base = window.colorMap[String(name)];
        if (!base) return [];
        let c = Qt.color(base);
        return [ Qt.darker(c, 1.45), Qt.darker(c, 1.18), c, Qt.lighter(c, 1.22), Qt.lighter(c, 1.55) ];
    }

    // -------------------------------------------------------------------------
    // GLOBAL ACTION: APPLY WALLPAPER
    // -------------------------------------------------------------------------
    function applyWallpaper(safeFileName, isVideo) {
        if (!safeFileName || window.isApplying) return;

        window.isApplying = true;
        window.flashTrigger++;

        window.targetWallName = safeFileName
        let cleanName = window.getCleanName(safeFileName)
        let reloadScript = Qt.resolvedUrl("matugen_reload.sh").toString()

        if (reloadScript.startsWith("file://")) {
            reloadScript = decodeURIComponent(reloadScript.substring(7))
        }

        const escapeBash = (str) => String(str).replace(/(["\\$`])/g, '\\$1');

        const renderOverride = "env WGPU_BACKEND=vulkan ";
        const randomTransition = window.transitions[Math.floor(Math.random() * window.transitions.length)];

        const ensureDaemonCmd = `if ! pgrep -x "awww-daemon" > /dev/null; then awww-daemon >/dev/null 2>&1 & sleep 0.2; fi`;

        if (window.currentFilter === "Search" && window.hasSearched) {
            let alreadyExists = window.isDownloaded(safeFileName);
            let destFile = window.srcDir + "/" + safeFileName;
            let finalThumb = decodeURIComponent(window.thumbDir.replace("file://", "")) + "/" + safeFileName;
            let tempThumb = decodeURIComponent(window.searchDir.replace("file://", "")) + "/" + safeFileName;
            let mapFile = Quickshell.env("HOME") + "/.cache/wallpaper_picker/search_map.txt";

            if (alreadyExists) {
                const applyScript = `
                    (
                        echo 'close' > /tmp/qs_widget_state

                        export DEST_FILE="${escapeBash(destFile)}"
                        export FINAL_THUMB="${escapeBash(finalThumb)}"
                        export RELOAD_SCRIPT="${escapeBash(reloadScript)}"

                        cp "$DEST_FILE" /tmp/lock_bg.png || true
                        pkill mpvpaper || true

                        ${ensureDaemonCmd}

                        ( matugen image "$FINAL_THUMB" --source-color-index 0 || true; bash "$RELOAD_SCRIPT" || true ) &
                        MATUGEN_PID=$!

                        for i in {1..20}; do
                            if ${renderOverride}awww img "$DEST_FILE" --transition-type ${randomTransition} --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >/dev/null 2>&1; then
                                break
                            fi
                            sleep 0.05
                        done

                        wait $MATUGEN_PID
                    ) </dev/null >/dev/null 2>&1 & disown
                `;
                Quickshell.execDetached(["bash", "-c", applyScript]);
            } else {
                window.isDownloadingWallpaper = true;
                window.currentDownloadName = safeFileName;

                const downloadScript = `
                    export SAFE_NAME="${escapeBash(safeFileName)}"
                    export DEST_FILE="${escapeBash(destFile)}"
                    export FINAL_THUMB="${escapeBash(finalThumb)}"
                    export TEMP_THUMB="${escapeBash(tempThumb)}"
                    export RELOAD_SCRIPT="${escapeBash(reloadScript)}"
                    export MAP_FILE="${escapeBash(mapFile)}"

                    (
                        URL=$(awk -F'|' -v fname="$SAFE_NAME" '$1 == fname {print $2; exit}' "$MAP_FILE")
                        if [ -n "$URL" ]; then
                            curl -s -L -A "Mozilla/5.0" "$URL" -o "$DEST_FILE.tmp"

                            if file "$DEST_FILE.tmp" | grep -iq "webp"; then
                                magick "$DEST_FILE.tmp" "$DEST_FILE"
                                rm -f "$DEST_FILE.tmp"
                            else
                                mv "$DEST_FILE.tmp" "$DEST_FILE"
                            fi

                            cp "$TEMP_THUMB" "$FINAL_THUMB"
                            magick "$DEST_FILE" -resize x420 -quality 70 "$FINAL_THUMB" || true

                            echo 'close' > /tmp/qs_widget_state

                            cp "$DEST_FILE" /tmp/lock_bg.png || true
                            pkill mpvpaper || true

                            ${ensureDaemonCmd}

                            ( matugen image "$FINAL_THUMB" --source-color-index 0 || true; bash "$RELOAD_SCRIPT" || true ) &
                            MATUGEN_PID=$!

                            for i in {1..20}; do
                                if ${renderOverride}awww img "$DEST_FILE" --transition-type ${randomTransition} --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >/dev/null 2>&1; then
                                    break
                                fi
                                sleep 0.05
                            done

                            wait $MATUGEN_PID
                        fi
                    ) </dev/null >/dev/null 2>&1 & disown
                `;
                Quickshell.execDetached(["bash", "-c", downloadScript]);
            }
            return;
        }

        const originalFile = window.srcDir + "/" + cleanName
        const thumbFile = Quickshell.env("HOME") + "/.cache/wallpaper_picker/thumbs/" + safeFileName

        let wallpaperCmd = ""
        let lockBgCmd = ""

        const escOriginal = escapeBash(originalFile);
        const escThumb = escapeBash(thumbFile);
        const escReload = escapeBash(reloadScript);

        if (isVideo) {
            wallpaperCmd = `mpvpaper -o 'loop --no-audio --hwdec=auto --profile=high-quality --video-sync=display-resample --interpolation --tscale=oversample' '*' "$WALL_FILE"`
            lockBgCmd = `cp "$THUMB_FILE" /tmp/lock_bg.png`
        } else {
            wallpaperCmd = `
                ${ensureDaemonCmd}
                for i in {1..20}; do
                    if ${renderOverride}awww img "$WALL_FILE" --transition-type ${randomTransition} --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >/dev/null 2>&1; then
                        break
                    fi
                    sleep 0.05
                done
            `
            lockBgCmd = `cp "$WALL_FILE" /tmp/lock_bg.png`
        }

        const fullScript = `
            (
                echo 'close' > /tmp/qs_widget_state

                export WALL_FILE="${escOriginal}"
                export THUMB_FILE="${escThumb}"
                export RELOAD_SCRIPT="${escReload}"

                ${lockBgCmd} || true
                pkill mpvpaper || true

                ( matugen image "$THUMB_FILE" --source-color-index 0 || true; bash "$RELOAD_SCRIPT" || true ) &
                MATUGEN_PID=$!

                ${wallpaperCmd}

                wait $MATUGEN_PID
            ) </dev/null >/dev/null 2>&1 & disown
        `
        Quickshell.execDetached(["bash", "-c", fullScript])
    }

    // Revamp: seed the chat with a wallpaper-mood request
    function askClaude() {
        let q = claudeInput.text.trim();
        if (q === "") return;
        let safe = q.replace(/'/g, "");
        Quickshell.execDetached(["bash", "-c", "echo 'claude:wallpaper:" + safe + "' > /tmp/qs_widget_state"]);
    }

    // -------------------------------------------------------------------------
    // PERSISTENT SETTINGS
    // -------------------------------------------------------------------------
    Settings {
        id: searchState
        category: "QS_WallpaperPicker"
        property string query: ""
        property bool searched: false
        property string lastName: ""
    }

    onIsSearchPausedChanged: {
        Quickshell.execDetached(["bash", "-c", "echo '" + (isSearchPaused ? "pause" : "run") + "' > /tmp/ddg_search_control"]);
    }

    // -------------------------------------------------------------------------
    // VISIBILITY LOGIC
    // -------------------------------------------------------------------------
    onVisibleChanged: {
        if (!visible) {
            window.initialFocusSet = false;
            window.searchIndexRestored = false;
            window.isApplying = false;
            window.claudeExpanded = false;

            if (window.hasSearched) {
                window.isSearchPaused = true;
            }
        } else {
            wpSettingsReader.running = false;
            wpSettingsReader.running = true;

            window.isFilterAnimating = true;
            filterAnimationTimer.restart();

            if (window.currentFilter !== "Search") {
                window.applyFilters(true);
            } else if (window.hasSearched) {
                window.searchIndexRestored = false;
                window.isSearchPaused = true;
                window.trySearchFocus();
                window.syncSearchModel();
            }
        }
    }

    onBrowseModeChanged: {
        if (window.browseMode === "grid") {
            window.rebuildGridModel();
            Qt.callLater(() => gridView.forceActiveFocus());
        } else {
            Qt.callLater(() => view.forceActiveFocus());
        }
        Quickshell.execDetached(["bash", "-c", "printf '%s' '" + browseMode + "' > /tmp/qs_wallpaper_mode"]);
    }

    Process {
        id: modeRestorer
        running: false
        command: ["bash", "-c", "cat /tmp/qs_wallpaper_mode 2>/dev/null || echo coverflow"]
        stdout: StdioCollector {
            onStreamFinished: {
                let m = this.text.trim();
                if (m === "grid" || m === "coverflow") window.browseMode = m;
            }
        }
    }

    onFocusedNameChanged: window.updateFileSize()

    // -------------------------------------------------------------------------
    // NOTIFICATION & LABEL STATE LOGIC
    // -------------------------------------------------------------------------
    property bool isLoading: localFolderModel.status === FolderListModel.Loading ||
                             srcModel.status === FolderListModel.Loading ||
                             (window.currentFilter === "Search" && searchFolderModel.status === FolderListModel.Loading)

    property bool showSpinner: window.isDownloadingWallpaper ||
                               (window.currentFilter === "Search" && window.hasSearched && !window.isSearchPaused) ||
                               (window.currentFilter !== "Search" && window.isLoading)

    property string currentNotification: {
        if (window.isDownloadingWallpaper) return "Downloading wallpaper...";

        if (window.currentFilter === "Search") {
            if (!window.hasSearched) return "Type something to search...";
            if (window.isSearchPaused) return "Search Paused";
            if (window.visibleItemCount === 0) return "Searching DDG (FHD+)...";
            return "Generating thumbnails...";
        }

        if (isLoading) return "Generating thumbnails...";
        if (window.visibleItemCount === 0) return "No wallpapers found";

        if (window.currentFilter === "All") return "";
        if (window.currentFilter === "Video") return "Videos";

        return window.currentFilter;
    }

    property bool showNotification: !window.isStartup && currentNotification !== ""

    function getCleanName(name) {
        if (!name) return "";
        let clean = String(name);

        let lastSlashIndex = clean.lastIndexOf("/");
        if (lastSlashIndex !== -1) {
            clean = clean.substring(lastSlashIndex + 1);
        }

        return clean.startsWith("000_") ? clean.substring(4) : clean;
    }

    function isDownloaded(name) {
        if (!name) return false;
        for (let i = 0; i < srcModel.count; i++) {
            if (srcModel.get(i, "fileName") === name) return true;
        }
        return false;
    }

    onWidgetArgChanged: {
        if (widgetArg !== "") {
            targetWallName = widgetArg;
            initialFocusSet = false;
            tryFocus();
        }
    }

    function executeFocusRestore(targetIndex, isSearchRestore, requirePositioning) {
        let targetModel = window.getModelForFilter(window.currentFilter);

        if (targetIndex !== -1 && targetIndex < targetModel.count) {
            window.isModelChanging = true;

            if (requirePositioning) {
                view.forceLayout();
                view.positionViewAtIndex(targetIndex, ListView.Center);
            }

            view.currentIndex = targetIndex;

            if (isSearchRestore) {
                window.searchIndexRestored = true;
            }

            window.isModelChanging = false;
            window.initialFocusSet = true;
        } else if (isSearchRestore) {
            window.searchIndexRestored = true;
        }
    }

    function tryFocus() {
        if (initialFocusSet) return;

        if (localProxyModel.count > 0) {
            let foundIndex = -1;
            let cleanTarget = window.getCleanName(targetWallName);

            if (cleanTarget !== "") {
                for (let i = 0; i < localProxyModel.count; i++) {
                    let fname = localProxyModel.get(i).fileName || "";
                    if (window.getCleanName(fname) === cleanTarget) {
                        foundIndex = i;
                        break;
                    }
                }
            }

            if (foundIndex !== -1) {
                window.executeFocusRestore(foundIndex, false, true);
            } else if (localFolderModel.status === FolderListModel.Ready) {
                window.executeFocusRestore(0, false, true);
            }
        }
    }

    function trySearchFocus() {
        if (window.searchIndexRestored || searchProxyModel.count === 0) return;

        if (window.lastSearchName === "") {
             window.searchIndexRestored = true;
             return;
        }

        for (let i = 0; i < searchProxyModel.count; i++) {
            let fname = searchProxyModel.get(i).fileName || "";
            if (fname === window.lastSearchName) {
                window.executeFocusRestore(i, true, true);
                return;
            }
        }

        if (searchFolderModel.status === FolderListModel.Ready && searchProxyModel.count === searchFolderModel.count) {
             window.searchIndexRestored = true;
        }
    }

    function getModelForFilter(filter) {
        return filter === "Search" ? searchProxyModel : localProxyModel;
    }

    function updateVisibleCount() {
        let targetModel = window.getModelForFilter(window.currentFilter);

        if (!targetModel || targetModel.count === 0) {
            window.visibleItemCount = 0;
            if (window.browseMode === "grid") window.rebuildGridModel();
            return;
        }
        let count = 0;
        for (let i = 0; i < targetModel.count; i++) {
            let fname = targetModel.get(i).fileName || "";
            let isVid = fname.startsWith("000_");
            if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                count++;
            }
        }
        window.visibleItemCount = count;
        if (window.browseMode === "grid") window.rebuildGridModel();
    }

    function rebuildGridModel() {
        let src = window.getModelForFilter(window.currentFilter);
        gridModel.clear();
        if (!src) return;
        for (let i = 0; i < src.count; i++) {
            let it = src.get(i);
            if (!it) continue;
            let fname = it.fileName || "";
            let isVid = fname.startsWith("000_");
            if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                gridModel.append({ "fileName": fname, "fileUrl": String(it.fileUrl), "srcIndex": i });
            }
        }
    }

    function updateFileSize() {
        window.focusedSize = "";
        if (window.focusedName === "") return;
        let p = window.srcDir + "/" + window.getCleanName(window.focusedName);
        statProc.target = p;
        statProc.running = false;
        statProc.running = true;
    }

    function triggerOnlineSearch() {
        if (searchInput.text.trim() === "") return;

        window.isModelChanging = true;
        searchProxyModel.clear();
        window.lastSearchName = "";
        searchState.lastName = "";

        if (window.currentFilter === "Search") {
            view.currentIndex = 0;
            view.positionViewAtIndex(0, ListView.Center);
        }
        window.isModelChanging = false;

        window.searchIndexRestored = true;
        window.isOnlineSearch = true;
        window.hasSearched = true;

        window.visibleItemCount = 0;

        searchState.searched = true;
        searchState.query = searchInput.text.trim();

        window.isSearchPaused = false;
        window.searchQuery = searchInput.text.trim();

        let rawSearchDir = decodeURIComponent(window.searchDir.replace(/^file:\/\//, ""));
        let scriptPath = decodeURIComponent(Qt.resolvedUrl("ddg_search.sh").toString().replace(/^file:\/\//, ""));

        const cmd = `
            exec > /tmp/qs_ddg_run.log 2>&1
            echo "=== QML Shell Handoff Successful ==="
            export PATH=$PATH:/run/current-system/sw/bin

            echo "Gracefully stopping old processes..."
            echo 'stop' > /tmp/ddg_search_control

            for p in $(pgrep -f ddg_search.sh); do
                if [ "$p" != "$$" ] && [ "$p" != "$BASHPID" ]; then
                    kill -9 $p 2>/dev/null || true
                fi
            done
            pkill -f "[g]et_ddg_links.py" || true
            sleep 0.2

            echo "Clearing old cache..."
            rm -rf "${rawSearchDir}"/* || true
            rm -f "${rawSearchDir}/../search_map.txt" || true

            echo "Setting control state back to run..."
            echo 'run' > /tmp/ddg_search_control

            echo "Executing new search pipeline..."
            bash "${scriptPath}" "${window.searchQuery}" &
        `;

        Quickshell.execDetached(["bash", "-c", cmd]);

        searchInput.focus = false;
        view.forceActiveFocus();
    }

    readonly property string homeDir: "file://" + Quickshell.env("HOME")
    readonly property string thumbDir: homeDir + "/.cache/wallpaper_picker/thumbs"
    readonly property string searchDir: homeDir + "/.cache/wallpaper_picker/search_thumbs"
    property string srcDir: Quickshell.env("HOME") + "/Pictures/Wallpapers"

    Process {
        id: wpSettingsReader
        command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (this.text && this.text.trim().length > 0 && this.text.trim() !== "{}") {
                        let parsed = JSON.parse(this.text);
                        if (parsed.wallpaperDir) {
                            let dir = parsed.wallpaperDir.trim();
                            if (dir.startsWith("~/")) {
                                dir = Quickshell.env("HOME") + dir.substring(1);
                            }
                            if (dir.endsWith("/")) {
                                dir = dir.substring(0, dir.length - 1);
                            }
                            window.srcDir = dir;
                        }
                    }
                } catch (e) {
                    console.log("Error parsing settings in WallpaperPicker:", e);
                }
            }
        }
    }

    Process {
        id: statProc
        property string target: ""
        command: ["bash", "-c", "stat -c %s \"" + target + "\" 2>/dev/null | numfmt --to=iec --suffix=B 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: window.focusedSize = this.text.trim()
        }
    }

    readonly property var transitions: ["grow", "outer", "any", "wipe", "wave", "pixel", "center"]

    readonly property real itemWidth: window.s(400)
    readonly property real itemHeight: window.s(420)
    readonly property real borderWidth: window.s(3)
    readonly property real spacing: window.s(10)
    readonly property real skewFactor: -0.35

    Timer {
        id: scrollThrottle
        interval: 150
    }

    property bool isFilterAnimating: false
    Timer {
        id: filterAnimationTimer
        interval: 800
        onTriggered: window.isFilterAnimating = false
    }

    property bool isItemAnimating: false
    Timer {
        id: itemAnimationTimer
        interval: 500
        onTriggered: window.isItemAnimating = false
    }

    // -------------------------------------------------------------------------
    // COLOR FILTERING MATH & NATIVE FILE SYSTEM CACHE
    // -------------------------------------------------------------------------
    function getHexBucket(hexStr) {
        if (!hexStr) return "Monochrome";

        hexStr = String(hexStr).trim().replace(/#/g, '');
        if (hexStr.length > 6) hexStr = hexStr.substring(0, 6);
        if (hexStr.length !== 6) return "Monochrome";

        let r = parseInt(hexStr.substring(0,2), 16) / 255;
        let g = parseInt(hexStr.substring(2,4), 16) / 255;
        let b = parseInt(hexStr.substring(4,6), 16) / 255;

        if (isNaN(r) || isNaN(g) || isNaN(b)) return "Monochrome";

        let max = Math.max(r, g, b), min = Math.min(r, g, b);
        let d = max - min;

        let h = 0;
        let sat = max === 0 ? 0 : d / max;
        let v = max;

        if (max !== min) {
            if (max === r) {
                h = (g - b) / d + (g < b ? 6 : 0);
            } else if (max === g) {
                h = (b - r) / d + 2;
            } else {
                h = (r - g) / d + 4;
            }
            h /= 6;
        }
        h = h * 360;

        if (sat < 0.05 || v < 0.08) return "Monochrome";

        if (h >= 345 || h < 15) return "Red";
        if (h >= 15 && h < 45) return "Orange";
        if (h >= 45 && h < 75) return "Yellow";
        if (h >= 75 && h < 165) return "Green";
        if (h >= 165 && h < 260) return "Blue";
        if (h >= 260 && h < 315) return "Purple";
        if (h >= 315 && h < 345) return "Pink";

        return "Monochrome";
    }

    function checkItemMatchesFilter(fileName, isVid, cv, filter) {
        if (filter === "Search") return true;

        if (filter === "All") return true;
        if (filter === "Video") return isVid;

        let hexColor = window.colorMap[String(fileName)];
        if (!hexColor) return filter === "Monochrome";

        return window.getHexBucket(hexColor) === filter;
    }

    FolderListModel {
        id: markerModel
        folder: "file://" + Quickshell.env("HOME") + "/.cache/wallpaper_picker/colors_markers"
        showDirs: false
        nameFilters: ["*_HEX_*"]

        onCountChanged: window.processMarkers()
        onStatusChanged: {
            if (status === FolderListModel.Ready) window.processMarkers()
        }
    }

    FolderListModel {
        id: srcModel
        folder: "file://" + window.srcDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.mp4", "*.mkv", "*.mov", "*.webm"]
        showDirs: false

        onCountChanged: {
            if (window.isDownloadingWallpaper && window.isDownloaded(window.currentDownloadName)) {
                window.isDownloadingWallpaper = false;
            }
        }
    }

    function processMarkers() {
        let newMap = {};
        for (let i = 0; i < markerModel.count; i++) {
            let markerName = markerModel.get(i, "fileName") || "";
            if (!markerName) continue;

            let splitIdx = markerName.lastIndexOf("_HEX_");
            if (splitIdx !== -1) {
                let fName = markerName.substring(0, splitIdx);
                let hexCode = markerName.substring(splitIdx + 5);
                newMap[fName] = "#" + hexCode;
            }
        }
        window.colorMap = newMap;
        window.cacheVersion++;
        window.updateVisibleCount();
    }

    function triggerColorExtraction() {
        const extractScript = `
            COLOR_DIR="$HOME/.cache/wallpaper_picker/colors_markers"
            THUMBS="$HOME/.cache/wallpaper_picker/thumbs"
            CSV="$HOME/.cache/wallpaper_picker/colors.csv"

            mkdir -p "$COLOR_DIR"

            if [ -f "$CSV" ]; then
                while IFS=, read -r fname hexcode; do
                    cleanhex=$(echo "$hexcode" | tr -d '\r#' | cut -c 1-6)
                    if [ -n "$cleanhex" ] && [ -n "$fname" ]; then
                        touch "$COLOR_DIR/$fname""_HEX_$cleanhex" 2>/dev/null
                    fi
                done < "$CSV"
                mv "$CSV" "$CSV.bak" 2>/dev/null
            fi

            if command -v magick &> /dev/null; then CMD="magick"; else CMD="convert"; fi

            for file in "$THUMBS"/*; do
                if [ -f "$file" ]; then
                    filename=$(basename "$file")
                    found=0
                    for marker in "$COLOR_DIR/$filename"_HEX_*; do
                        if [ -e "$marker" ]; then found=1; break; fi
                    done

                    if [ $found -eq 0 ]; then
                        hex=$($CMD "$file" -modulate 100,200 -resize "1x1^" -gravity center -extent 1x1 -depth 8 -format "%[hex:p{0,0}]" info:- 2>/dev/null | grep -oE '[0-9A-Fa-f]{6}' | head -n 1)
                        if [ -n "$hex" ]; then
                            touch "$COLOR_DIR/$filename""_HEX_$hex"
                        fi
                    fi
                fi
            done
        `;
        Quickshell.execDetached(["bash", "-c", extractScript]);
    }

    function stepToNextValidIndex(direction) {
        let targetModel = window.getModelForFilter(window.currentFilter);
        if (!targetModel || targetModel.count === 0) return;

        let start = view.currentIndex;
        let found = -1;

        if (direction === 1) {
            for (let i = start + 1; i < targetModel.count; i++) {
                let fname = targetModel.get(i).fileName || "";
                let isVid = fname.startsWith("000_");
                if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                    found = i; break;
                }
            }
        } else {
            for (let i = start - 1; i >= 0; i--) {
                let fname = targetModel.get(i).fileName || "";
                let isVid = fname.startsWith("000_");
                if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                    found = i; break;
                }
            }
        }

        if (found !== -1) {
            view.currentIndex = found;
            return;
        }

        let filterOrder = ["All", "Video", "Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink", "Monochrome"];
        let currentFilterIdx = filterOrder.indexOf(window.currentFilter);

        if (currentFilterIdx === -1) {
            let current = start;
            for (let i = 0; i < targetModel.count; i++) {
                current = (current + direction + targetModel.count) % targetModel.count;
                let fname = targetModel.get(current).fileName || "";
                let isVid = fname.startsWith("000_");

                if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                    view.currentIndex = current;
                    return;
                }
            }
            return;
        }

        let nextFilterIdx = currentFilterIdx + direction;

        if (nextFilterIdx >= 0 && nextFilterIdx < filterOrder.length) {
            window.jumpToLastOnFilterChange = (direction === -1);
            window.currentFilter = filterOrder[nextFilterIdx];
        }
    }

    function cycleFilter(direction) {
        let currentIdx = -1;
        for (let i = 0; i < window.filterData.length; i++) {
            if (window.filterData[i].name === window.currentFilter) {
                currentIdx = i;
                break;
            }
        }

        if (currentIdx !== -1) {
            let nextIdx = (currentIdx + direction + window.filterData.length) % window.filterData.length;
            window.currentFilter = window.filterData[nextIdx].name;
        }
    }

    function applyFilters(forceSnap) {
        let targetModel = window.getModelForFilter(window.currentFilter);

        if (!targetModel || targetModel.count === 0) {
            window.updateVisibleCount();
            return;
        }

        if (window.currentFilter === "Search") {
            window.updateVisibleCount();
            return;
        }

        let firstValidIndex = -1;
        let lastValidIndex = -1;
        let cleanTarget = window.getCleanName(window.targetWallName);
        let targetIndex = -1;

        for (let i = 0; i < targetModel.count; i++) {
            let fname = targetModel.get(i).fileName || "";
            let isVid = fname.startsWith("000_");

            if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                if (firstValidIndex === -1) {
                    firstValidIndex = i;
                }
                lastValidIndex = i;

                if (cleanTarget !== "" && window.getCleanName(fname) === cleanTarget) {
                    targetIndex = i;
                }
            }
        }

        let indexToFocus = -1;

        if (targetIndex !== -1) {
             indexToFocus = targetIndex;
        } else if (window.jumpToLastOnFilterChange && lastValidIndex !== -1) {
            indexToFocus = lastValidIndex;
        } else if (firstValidIndex !== -1) {
            if (window.initialFocusSet || localFolderModel.status === FolderListModel.Ready) {
                indexToFocus = firstValidIndex;
            }
        }

        window.jumpToLastOnFilterChange = false;

        if (indexToFocus !== -1) {
            window.executeFocusRestore(indexToFocus, false, forceSnap === true);
        }

        window.updateVisibleCount();
    }

    onCurrentFilterChanged: {
        window.isFilterAnimating = true;
        filterAnimationTimer.restart();
        window.isModelChanging = true;
        let returningFromSearch = (window._lastFilter === "Search" && window.currentFilter !== "Search");
        window._lastFilter = window.currentFilter;

        if (returningFromSearch) {
             window.searchIndexRestored = false;
        }

        Qt.callLater(() => {
            view.forceActiveFocus();

            if (window.currentFilter === "Search") {
                if (window.hasSearched) {
                    window.searchIndexRestored = false;
                    window.trySearchFocus();
                }
            } else {
                window.applyFilters(returningFromSearch);
            }
            window.isModelChanging = false;
            window.rebuildGridModel();
        });
    }

    // -------------------------------------------------------------------------
    // SHORTCUTS
    // -------------------------------------------------------------------------
    Shortcut {
        sequence: "Left";
        enabled: !window.isScrollingBlocked && !window.isApplying
        onActivated: window.stepToNextValidIndex(-1)
    }
    Shortcut {
        sequence: "Right";
        enabled: !window.isScrollingBlocked && !window.isApplying
        onActivated: window.stepToNextValidIndex(1)
    }

    Shortcut {
        sequence: "Return"
        enabled: !searchInput.activeFocus && !claudeInput.activeFocus && !window.isScrollingBlocked && !window.isApplying
        onActivated: {
            let targetModel = window.getModelForFilter(window.currentFilter);
            if (view.currentIndex >= 0 && view.currentIndex < targetModel.count) {
                let fname = targetModel.get(view.currentIndex).fileName;
                if (fname) {
                    let isVid = String(fname).startsWith("000_");
                    window.applyWallpaper(String(fname), isVid);
                }
            }
        }
    }

    Shortcut { sequence: "Escape"; enabled: !window.isApplying; onActivated: { if (window.claudeExpanded) { window.claudeExpanded = false; } else if (window.currentFilter === "Search") { window.currentFilter = "All"; } } }
    Shortcut { sequence: "Tab"; enabled: !window.isApplying; onActivated: window.cycleFilter(1) }
    Shortcut { sequence: "Backtab"; enabled: !window.isApplying; onActivated: window.cycleFilter(-1) }

    // -------------------------------------------------------------------------
    // CONTENT & DUAL MODELS
    // -------------------------------------------------------------------------
    ListModel { id: localProxyModel }
    ListModel { id: searchProxyModel }
    ListModel { id: gridModel }

    readonly property var activeModel: window.currentFilter === "Search" ? searchProxyModel : localProxyModel

    FolderListModel {
        id: localFolderModel
        folder: window.thumbDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.mp4", "*.mkv", "*.mov", "*.webm"]
        showDirs: false
        sortField: FolderListModel.Name

        onCountChanged: window.syncLocalModel()
        onStatusChanged: { if (status === FolderListModel.Ready) window.syncLocalModel() }
    }

    function syncLocalModel() {
        let needsClear = false;

        if (localFolderModel.count < localProxyModel.count) {
            needsClear = true;
        } else if (localProxyModel.count > 0 && localFolderModel.count > 0) {
            if (localProxyModel.get(0).fileName !== localFolderModel.get(0, "fileName")) {
                needsClear = true;
            }
        }

        if (needsClear) {
            window.isModelChanging = true;
            localProxyModel.clear();
            window.isModelChanging = false;
        }

        let startIdx = localProxyModel.count;
        let endIdx = localFolderModel.count;

        for (let i = startIdx; i < endIdx; i++) {
            let fn = localFolderModel.get(i, "fileName");
            let fu = localFolderModel.get(i, "fileUrl");
            if (fn !== undefined) {
                localProxyModel.append({ "fileName": fn, "fileUrl": String(fu) });
            }
        }

        if (window.currentFilter !== "Search") window.updateVisibleCount();

        if (!window.initialFocusSet && window.currentFilter !== "Search" && localProxyModel.count > 0) {
            window.tryFocus();
        }
    }

    FolderListModel {
        id: searchFolderModel
        folder: window.searchDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.mp4", "*.mkv", "*.mov", "*.webm"]
        showDirs: false
        sortField: FolderListModel.Name

        onFolderChanged: {
            window.isModelChanging = true;
            searchProxyModel.clear()
            window.isModelChanging = false;
        }

        onCountChanged: window.syncSearchModel()
        onStatusChanged: { if (status === FolderListModel.Ready) window.syncSearchModel() }
    }

    function syncSearchModel() {
        let startIdx = searchProxyModel.count;
        let endIdx = searchFolderModel.count;

        if (endIdx < startIdx) {
            window.isModelChanging = true;
            searchProxyModel.clear();
            startIdx = 0;
            window.isModelChanging = false;
        }

        for (let i = startIdx; i < endIdx; i++) {
            let fn = searchFolderModel.get(i, "fileName");
            let fu = searchFolderModel.get(i, "fileUrl");
            if (fn !== undefined) {
                searchProxyModel.append({ "fileName": fn, "fileUrl": String(fu) });
            }
        }

        if (window.currentFilter === "Search") window.updateVisibleCount();

        if (window.currentFilter === "Search" && window.hasSearched) {
            if (!window.searchIndexRestored) {
                window.trySearchFocus();
            }

            if (window.isScrollingBlocked && startIdx === 0 && searchProxyModel.count > 0 && window.lastSearchName === "") {
                view.forceLayout();
                view.currentIndex = 0;
                view.positionViewAtIndex(0, ListView.Center);
            }
        }
    }

    // -------------------------------------------------------------------------
    // COVERFLOW (FOCUS MODE)
    // -------------------------------------------------------------------------
    ListView {
        id: view
        anchors.fill: parent

        opacity: (window.isReady && window.browseMode === "coverflow") ? 1.0 : 0.0
        anchors.margins: window.isReady ? 0 : window.s(40)
        visible: opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutQuart } }
        Behavior on anchors.margins { NumberAnimation { duration: 700; easing.type: Easing.OutExpo } }

        spacing: 0
        orientation: ListView.Horizontal
        clip: false

        interactive: window.browseMode === "coverflow" && !window.isScrollingBlocked && !window.isApplying
        cacheBuffer: 2000

        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width / 2) - ((window.itemWidth * 1.5 + window.spacing) / 2)
        preferredHighlightEnd: (width / 2) + ((window.itemWidth * 1.5 + window.spacing) / 2)

        highlightMoveDuration: window.initialFocusSet ? 500 : 0
        focus: window.browseMode === "coverflow"
        Keys.enabled: window.browseMode === "coverflow"
        Keys.forwardTo: window.browseMode === "grid" ? [gridView] : []

        onCurrentIndexChanged: {
            window.isItemAnimating = true;
            itemAnimationTimer.restart();

            if (view.model !== searchProxyModel || window.currentFilter !== "Search") return;

            if (!window.isModelChanging && window.hasSearched && window.searchIndexRestored) {
                if (currentIndex >= 0 && currentIndex < searchProxyModel.count) {
                    let fname = searchProxyModel.get(currentIndex).fileName;
                    if (fname !== undefined && fname !== "") {
                        window.lastSearchName = String(fname);
                        searchState.lastName = String(fname);
                    }
                }
            }
        }

        add: Transition {
            enabled: window.initialFocusSet
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 400; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.5; to: 1; duration: 400; easing.type: Easing.OutBack }
            }
        }
        addDisplaced: Transition {
            enabled: window.initialFocusSet
            NumberAnimation { property: "x"; duration: 400; easing.type: Easing.OutCubic }
        }

        header: Item { width: Math.max(0, (view.width / 2) - ((window.itemWidth * 1.5) / 2)) }
        footer: Item { width: Math.max(0, (view.width / 2) - ((window.itemWidth * 1.5) / 2)) }

        model: window.activeModel

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton

            onWheel: (wheel) => {
                if (window.isScrollingBlocked || window.isApplying) {
                    wheel.accepted = true;
                    return;
                }

                if (scrollThrottle.running) {
                   wheel.accepted = true
                   return
                }

                let dx = wheel.angleDelta.x
                let dy = wheel.angleDelta.y
                let delta = Math.abs(dx) > Math.abs(dy) ? dx : dy

                scrollAccum += delta

                if (Math.abs(scrollAccum) >= scrollThreshold) {
                    window.stepToNextValidIndex(scrollAccum > 0 ? -1 : 1)
                    scrollAccum = 0
                    scrollThrottle.start()
                }

                wheel.accepted = true
            }
        }

        delegate: Item {
            id: delegateRoot

            readonly property string safeFileName: fileName !== undefined ? String(fileName) : ""

            readonly property bool isCurrent: ListView.isCurrentItem && !window.isScrollingBlocked
            readonly property bool isFakeSelected: window.isScrollingBlocked && index === 0
            readonly property bool isVisuallyEnlarged: isCurrent || isFakeSelected

            readonly property bool isVideo: safeFileName.startsWith("000_")
            readonly property bool matchesFilter: window.checkItemMatchesFilter(safeFileName, isVideo, window.cacheVersion, window.currentFilter)

            readonly property real targetWidth: isVisuallyEnlarged ? (window.itemWidth * 1.5) : (window.itemWidth * 0.5)
            readonly property real targetHeight: isVisuallyEnlarged ? (window.itemHeight + window.s(30)) : window.itemHeight

            property bool isPlayingVideo: false

            Timer {
                id: videoPlayTimer
                interval: 250
                running: delegateRoot.isVisuallyEnlarged && delegateRoot.isVideo && !window.isScrollingBlocked && !window.isFilterAnimating && !window.isItemAnimating
                onTriggered: {
                    if (delegateRoot.isVisuallyEnlarged && delegateRoot.isVideo) {
                        delegateRoot.isPlayingVideo = true;
                        previewPlayer.play();
                    }
                }
            }

            onIsVisuallyEnlargedChanged: {
                if (!isVisuallyEnlarged) {
                    isPlayingVideo = false;
                    videoPlayTimer.stop();
                    previewPlayer.stop();
                }
            }

            width: matchesFilter ? (targetWidth + window.spacing) : 0
            visible: width > 0.1 || opacity > 0.01
            opacity: matchesFilter ? (isVisuallyEnlarged ? 1.0 : 0.6) : 0.0

            scale: matchesFilter ? 1.0 : 0.5

            height: matchesFilter ? targetHeight : 0
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: window.s(15)

            z: isVisuallyEnlarged ? 10 : Math.max(1, 5 - Math.abs(index - view.currentIndex))

            Behavior on scale { enabled: window.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
            Behavior on width { enabled: window.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
            Behavior on height { enabled: window.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
            Behavior on opacity { enabled: window.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }

            Item {
                id: cardItem
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: ((window.itemHeight - height) / 2) * window.skewFactor

                width: parent.width > 0 ? parent.width * (targetWidth / (targetWidth + window.spacing)) : 0
                height: parent.height

                transform: Matrix4x4 {
                    property real sk: window.skewFactor
                    matrix: Qt.matrix4x4(1, sk, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: delegateRoot.matchesFilter && !window.isScrollingBlocked && !window.isApplying
                    onClicked: {
                        view.currentIndex = index
                        window.applyWallpaper(delegateRoot.safeFileName, delegateRoot.isVideo)
                    }
                }

                Image {
                    anchors.fill: parent
                    source: fileUrl !== undefined ? fileUrl : ""
                    sourceSize: Qt.size(1, 1)
                    fillMode: Image.Stretch
                    visible: true
                    asynchronous: true
                }

                Item {
                    anchors.fill: parent
                    anchors.margins: window.borderWidth
                    Rectangle { anchors.fill: parent; color: "black" }
                    clip: true

                    Image {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: window.s(-50)
                        width: (window.itemWidth * 1.5) + ((window.itemHeight + window.s(30)) * Math.abs(window.skewFactor)) + window.s(50)
                        height: window.itemHeight + window.s(30)
                        fillMode: Image.PreserveAspectCrop
                        source: fileUrl !== undefined ? fileUrl : ""
                        asynchronous: true

                        transform: Matrix4x4 {
                            property real sk: -window.skewFactor
                            matrix: Qt.matrix4x4(1, sk, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }
                    }

                    MediaPlayer {
                        id: previewPlayer
                        source: delegateRoot.isPlayingVideo ? "file://" + window.srcDir + "/" + window.getCleanName(delegateRoot.safeFileName) : ""
                        audioOutput: AudioOutput { muted: true }
                        videoOutput: previewOutput
                        loops: MediaPlayer.Infinite
                    }

                    VideoOutput {
                        id: previewOutput
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: window.s(-50)
                        width: (window.itemWidth * 1.5) + ((window.itemHeight + window.s(30)) * Math.abs(window.skewFactor)) + window.s(50)
                        height: window.itemHeight + window.s(30)
                        fillMode: VideoOutput.PreserveAspectCrop
                        visible: delegateRoot.isPlayingVideo && previewPlayer.playbackState === MediaPlayer.PlayingState

                        transform: Matrix4x4 {
                            property real sk: -window.skewFactor
                            matrix: Qt.matrix4x4(1, sk, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }
                    }

                    Rectangle {
                        visible: delegateRoot.isVideo && (!delegateRoot.isPlayingVideo || previewPlayer.playbackState !== MediaPlayer.PlayingState)
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: window.s(10)
                        width: window.s(32)
                        height: window.s(32)
                        radius: window.s(6)
                        color: "#60000000"
                        transform: Matrix4x4 {
                            property real sk: -window.skewFactor
                            matrix: Qt.matrix4x4(1, sk, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }

                        Canvas {
                            anchors.fill: parent
                            anchors.margins: window.s(8)
                            property real scaleTrigger: window.s(1)
                            onScaleTriggerChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d");
                                var sf = window.s;
                                ctx.reset();
                                ctx.fillStyle = "#EEFFFFFF";
                                ctx.beginPath();
                                ctx.moveTo(sf(4), 0);
                                ctx.lineTo(sf(14), sf(8));
                                ctx.lineTo(sf(4), sf(16));
                                ctx.closePath();
                                ctx.fill();
                            }
                        }
                    }
                }

                Rectangle {
                    id: flashRect
                    anchors.fill: parent
                    radius: window.s(6)
                    color: "white"
                    opacity: 0

                    Connections {
                        target: window
                        function onFlashTriggerChanged() {
                            if (delegateRoot.isVisuallyEnlarged) flashAnim.restart();
                        }
                    }

                    SequentialAnimation {
                        id: flashAnim
                        NumberAnimation { target: flashRect; property: "opacity"; to: 0.35; duration: 80 }
                        NumberAnimation { target: flashRect; property: "opacity"; to: 0; duration: 400; easing.type: Easing.OutExpo }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // GRID (BROWSE MODE)
    // -------------------------------------------------------------------------
    GridView {
        id: gridView
        anchors.fill: parent
        anchors.topMargin: window.s(110)
        anchors.bottomMargin: window.s(150)
        anchors.leftMargin: window.s(24)
        anchors.rightMargin: window.s(24)

        opacity: (window.isReady && window.browseMode === "grid") ? 1.0 : 0.0
        visible: opacity > 0.01
        enabled: window.browseMode === "grid" && !window.isApplying
        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutQuart } }

        clip: true
        cacheBuffer: window.s(2400)
        cellWidth: gridView.width / 5
        cellHeight: cellWidth * 0.6
        model: gridModel

        focus: window.browseMode === "grid"
        Keys.enabled: window.browseMode === "grid"
        Keys.onLeftPressed: { if (currentIndex > 0) currentIndex-- }
        Keys.onRightPressed: { if (currentIndex < count - 1) currentIndex++ }
        Keys.onUpPressed: { if (currentIndex >= 5) currentIndex -= 5 }
        Keys.onDownPressed: { if (currentIndex + 5 < count) currentIndex += 5 }
        Keys.onReturnPressed: {
            if (currentIndex >= 0 && currentIndex < count) {
                let item = gridModel.get(currentIndex);
                view.currentIndex = item.srcIndex;
                window.browseMode = "coverflow";
            }
        }

        delegate: Item {
            id: gcell
            width: gridView.cellWidth
            height: gridView.cellHeight

            readonly property bool isVid: String(fileName).startsWith("000_")
            readonly property bool isSel: index === gridView.currentIndex

            HoverHandler { id: hov }

            Rectangle {
                anchors.fill: card
                anchors.margins: -window.s(8)
                radius: window.s(12)
                color: Qt.rgba(_theme.peach.r, _theme.peach.g, _theme.peach.b, 1)
                opacity: hov.hovered ? 0.22 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
                z: -1
            }

            Rectangle {
                id: card
                anchors.fill: parent
                anchors.margins: window.s(6)
                radius: window.s(8)
                clip: true
                color: "black"

                border.color: gcell.isSel ? _theme.mauve : "transparent"
                border.width: gcell.isSel ? window.s(2) : 0

                scale: (hov.hovered || gcell.isSel) ? 1.04 : 1.0
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

                Image {
                    anchors.fill: parent
                    source: fileUrl !== undefined ? fileUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                MediaPlayer {
                    id: gridPlayer
                    source: (hov.hovered && gcell.isVid) ? "file://" + window.srcDir + "/" + window.getCleanName(String(fileName)) : ""
                    audioOutput: AudioOutput { muted: true }
                    videoOutput: gridOutput
                    loops: MediaPlayer.Infinite
                    onSourceChanged: { if (source !== "") play(); }
                }

                VideoOutput {
                    id: gridOutput
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectCrop
                    visible: gcell.isVid && gridPlayer.playbackState === MediaPlayer.PlayingState
                }

                Rectangle {
                    visible: gcell.isVid && gridPlayer.playbackState !== MediaPlayer.PlayingState
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: window.s(8)
                    width: window.s(28)
                    height: window.s(28)
                    radius: window.s(6)
                    color: "#60000000"

                    Canvas {
                        anchors.fill: parent
                        anchors.margins: window.s(7)
                        property real scaleTrigger: window.s(1)
                        onScaleTriggerChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d");
                            var sf = window.s;
                            ctx.reset();
                            ctx.fillStyle = "#EEFFFFFF";
                            ctx.beginPath();
                            ctx.moveTo(sf(3), 0);
                            ctx.lineTo(sf(13), sf(7));
                            ctx.lineTo(sf(3), sf(14));
                            ctx.closePath();
                            ctx.fill();
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !window.isApplying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        view.currentIndex = srcIndex;
                        window.browseMode = "coverflow";
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // BOTTOM INFO BAR (focused item)
    // -------------------------------------------------------------------------
    Rectangle {
        id: infoBar
        anchors.bottom: parent.bottom
        anchors.bottomMargin: window.isReady ? (window.browseMode === "coverflow" ? window.s(6) : window.s(40)) : window.s(-120)
        anchors.horizontalCenter: parent.horizontalCenter
        z: 20

        opacity: (window.isReady && window.focusedName !== "") ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

        height: window.s(72)
        width: infoRow.width + window.s(32)
        radius: window.s(16)

        color: Qt.rgba(_theme.mantle.r, _theme.mantle.g, _theme.mantle.b, 0.92)
        border.color: Qt.rgba(_theme.surface2.r, _theme.surface2.g, _theme.surface2.b, 0.8)
        border.width: 1

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 1
            height: parent.height * 0.45
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
        }

        Row {
            id: infoRow
            anchors.centerIn: parent
            spacing: window.s(18)

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: window.s(3)

                Text {
                    text: window.getCleanName(window.focusedName)
                    color: _theme.text
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(15)
                    font.bold: true
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, window.s(320))
                }
                Text {
                    text: window.focusedSize !== "" ? window.focusedSize : (window.focusedIsVideo ? "video" : "")
                    color: _theme.subtext0
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(12)
                }
            }

            Rectangle {
                width: 1
                height: window.s(40)
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(_theme.surface2.r, _theme.surface2.g, _theme.surface2.b, 0.6)
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: window.s(4)

                Text {
                    text: "THEME PREVIEW"
                    color: _theme.subtext0
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(10)
                    font.letterSpacing: window.s(1)
                }
                Row {
                    spacing: window.s(6)
                    Repeater {
                        model: 5
                        delegate: Rectangle {
                            width: window.s(24)
                            height: window.s(24)
                            radius: window.s(6)
                            property bool hasPalette: window.focusedPalette.length > 0
                            color: hasPalette
                                    ? window.focusedPalette[index]
                                    : Qt.rgba(_theme.surface2.r, _theme.surface2.g, _theme.surface2.b, 0.4)
                            border.color: Qt.rgba(_theme.surface1.r, _theme.surface1.g, _theme.surface1.b, 0.7)
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 300 } }
                        }
                    }
                }
            }

            Rectangle {
                width: 1
                height: window.s(40)
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(_theme.surface2.r, _theme.surface2.g, _theme.surface2.b, 0.6)
            }

            Rectangle {
                id: applyBtn
                anchors.verticalCenter: parent.verticalCenter
                width: applyText.implicitWidth + window.s(32)
                height: window.s(42)
                radius: window.s(10)
                color: applyMouse.containsMouse ? _theme.mauve : Qt.rgba(_theme.mauve.r, _theme.mauve.g, _theme.mauve.b, 0.85)
                scale: applyMouse.pressed ? 0.95 : 1.0
                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on scale { NumberAnimation { duration: 120 } }

                Text {
                    id: applyText
                    anchors.centerIn: parent
                    text: "APPLY"
                    color: _theme.crust
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(14)
                    font.bold: true
                }

                MouseArea {
                    id: applyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !window.isApplying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: window.applyWallpaper(window.focusedName, window.focusedIsVideo)
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // FLOATING FILTER BAR & INLINE NOTIFICATION DRAWER
    // -------------------------------------------------------------------------
    Rectangle {
        id: filterBarBackground
        anchors.top: parent.top

        anchors.topMargin: window.isReady ? window.s(40) : window.s(-100)
        opacity: window.isReady ? 1.0 : 0.0
        Behavior on anchors.topMargin { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

        anchors.horizontalCenter: parent.horizontalCenter
        z: 20
        height: window.s(56)
        width: filterRow.width + window.s(24)
        radius: window.s(14)

        color: Qt.rgba(_theme.mantle.r, _theme.mantle.g, _theme.mantle.b, 0.90)
        border.color: Qt.rgba(_theme.surface2.r, _theme.surface2.g, _theme.surface2.b, 0.8)
        border.width: 1

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 1
            height: parent.height * 0.5
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
        }

        Row {
            id: filterRow
            anchors.centerIn: parent
            spacing: window.s(12)

            Row {
                id: modeToggle
                anchors.verticalCenter: parent.verticalCenter
                spacing: window.s(6)

                Repeater {
                    model: [
                        { mode: "grid", icon: "grid" },
                        { mode: "coverflow", icon: "flow" }
                    ]

                    delegate: Item {
                        width: window.s(44)
                        height: window.s(36)
                        anchors.verticalCenter: parent.verticalCenter

                        readonly property bool isActive: window.browseMode === modelData.mode

                        Rectangle {
                            id: modePill
                            anchors.fill: parent
                            radius: window.s(10)
                            color: isActive ? _theme.mauve : "transparent"

                            HoverHandler { id: modePillHov }

                            border.color: "transparent"
                            border.width: 0
                            scale: modeMouse.pressed ? 0.93 : 1.0

                            Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                            Behavior on color { ColorAnimation { duration: 300 } }
                            Behavior on border.color { ColorAnimation { duration: 300 } }

                            Canvas {
                                visible: modelData.icon === "grid"
                                width: window.s(14); height: window.s(14)
                                anchors.centerIn: parent
                                property string activeColor: isActive ? _theme.crust : (modePillHov.containsMouse ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7))
                                onActiveColorChanged: requestPaint()
                                property real scaleTrigger: window.s(1)
                                onScaleTriggerChanged: requestPaint()

                                onPaint: {
                                    var ctx = getContext("2d");
                                    var sf = window.s;
                                    ctx.reset();
                                    ctx.fillStyle = activeColor;
                                    ctx.fillRect(0, 0, sf(6), sf(6));
                                    ctx.fillRect(sf(8), 0, sf(6), sf(6));
                                    ctx.fillRect(0, sf(8), sf(6), sf(6));
                                    ctx.fillRect(sf(8), sf(8), sf(6), sf(6));
                                }
                            }

                            Canvas {
                                visible: modelData.icon === "flow"
                                width: window.s(16); height: window.s(16)
                                anchors.centerIn: parent
                                property string activeColor: isActive ? _theme.crust : (modePillHov.containsMouse ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7))
                                onActiveColorChanged: requestPaint()
                                property real scaleTrigger: window.s(1)
                                onScaleTriggerChanged: requestPaint()

                                onPaint: {
                                    var ctx = getContext("2d");
                                    var sf = window.s;
                                    ctx.reset();
                                    ctx.fillStyle = activeColor;
                                    ctx.globalAlpha = 0.5;
                                    ctx.fillRect(0, sf(3), sf(4), sf(10));
                                    ctx.fillRect(sf(12), sf(3), sf(4), sf(10));
                                    ctx.globalAlpha = 1.0;
                                    ctx.fillRect(sf(5), 0, sf(6), sf(16));
                                }
                            }
                        }

                        MouseArea {
                            id: modeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !window.isApplying
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.browseMode = modelData.mode
                        }
                    }
                }
            }

            Rectangle {
                width: 1
                height: window.s(28)
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(_theme.surface2.r, _theme.surface2.g, _theme.surface2.b, 0.6)
            }

            Rectangle {
                id: notifDrawer
                height: window.s(44)
                anchors.verticalCenter: parent.verticalCenter
                property real paddingLeft: window.showSpinner ? window.s(40) : window.s(16)
                property real targetWidth: window.showNotification ? Math.min(notifTextDrawer.implicitWidth + paddingLeft + window.s(20), window.s(300)) : 0
                width: targetWidth
                visible: width > 0.1
                radius: window.s(10)
                clip: true

                color: window.showNotification ? Qt.rgba(_theme.surface2.r, _theme.surface2.g, _theme.surface2.b, 0.5) : "transparent"
                border.color: window.showNotification ? Qt.rgba(_theme.surface1.r, _theme.surface1.g, _theme.surface1.b, 0.8) : "transparent"
                border.width: 1

                Behavior on width {
                    NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
                }
                Behavior on color { ColorAnimation { duration: 400 } }
                Behavior on border.color { ColorAnimation { duration: 400 } }

                Item {
                    visible: window.showSpinner
                    width: window.s(44)
                    height: window.s(44)
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    Canvas {
                        id: notifSpinner
                        width: window.s(14)
                        height: window.s(14)
                        anchors.centerIn: parent
                        property real scaleTrigger: window.s(1)
                        onScaleTriggerChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d");
                            var sf = window.s;
                            ctx.reset();
                            ctx.lineWidth = sf(2);
                            ctx.strokeStyle = Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.3);
                            ctx.beginPath();
                            ctx.arc(sf(7), sf(7), sf(5), 0, Math.PI * 2);
                            ctx.stroke();

                            ctx.strokeStyle = Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.9);
                            ctx.beginPath();
                            ctx.arc(sf(7), sf(7), sf(5), 0, Math.PI * 0.5);
                            ctx.stroke();
                        }
                        RotationAnimation on rotation {
                            loops: Animation.Infinite
                            from: 0; to: 360
                            duration: 800
                            running: window.showSpinner && window.showNotification
                        }
                    }
                }

                Text {
                    id: notifTextDrawer
                    anchors.left: parent.left
                    anchors.leftMargin: window.showSpinner ? window.s(40) : window.s(16)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, window.s(300) - anchors.leftMargin - window.s(16))
                    text: window.currentNotification

                    color: _theme.text
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(14)
                    font.bold: true
                    elide: Text.ElideRight

                    opacity: window.showNotification ? 0.9 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }
                    Behavior on anchors.leftMargin {
                        NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
                    }
                }
            }

            Repeater {
                model: window.filterData

                delegate: Item {
                    visible: modelData.name !== "Search"
                    width: !visible ? 0 : ((modelData.name === "Video" || modelData.name === "All") ? window.s(44) : (modelData.hex === "" ? filterText.contentWidth + window.s(24) : window.s(36)))
                    height: !visible ? 0 : window.s(36)
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors { fill: pill; margins: -window.s(3) }
                        radius: pill.radius + window.s(3)
                        color: Qt.rgba(_theme.peach.r, _theme.peach.g, _theme.peach.b, 1)
                        opacity: pillHov.containsMouse ? 0.2 : 0
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                        z: pill.z - 1
                    }

                    Rectangle {
                        id: pill
                        anchors.fill: parent
                        radius: window.s(10)
                        color: modelData.hex === ""
                                ? (window.currentFilter === modelData.name ? _theme.surface2 : "transparent")
                                : modelData.hex

                        HoverHandler { id: pillHov }

                        border.color: window.currentFilter === modelData.name ? _theme.text : Qt.rgba(_theme.surface1.r, _theme.surface1.g, _theme.surface1.b, 0.6)
                        border.width: window.currentFilter === modelData.name ? window.s(2) : 1
                        scale: window.currentFilter === modelData.name ? 1.15 : (filterMouse.containsMouse ? 1.08 : 1.0)

                        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                        Behavior on border.color { ColorAnimation { duration: 300 } }

                        Text {
                            id: filterText
                            visible: modelData.hex === "" && modelData.name !== "Video" && modelData.name !== "All"
                            text: modelData.label
                            anchors.centerIn: parent
                            color: window.currentFilter === modelData.name ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                            font.family: "JetBrains Mono"
                            font.pixelSize: window.s(14)
                            font.bold: window.currentFilter === modelData.name
                            Behavior on color { ColorAnimation { duration: 400; easing.type: Easing.OutQuart } }
                        }

                        Canvas {
                            visible: modelData.name === "Video"
                            width: window.s(14); height: window.s(16)
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: window.s(2)
                            property string activeColor: window.currentFilter === modelData.name ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                            onActiveColorChanged: requestPaint()
                            property real scaleTrigger: window.s(1)
                            onScaleTriggerChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d");
                                var sf = window.s;
                                ctx.reset();
                                ctx.fillStyle = activeColor;
                                ctx.beginPath();
                                ctx.moveTo(0, 0);
                                ctx.lineTo(sf(14), sf(8));
                                ctx.lineTo(0, sf(16));
                                ctx.closePath();
                                ctx.fill();
                            }
                        }

                        Canvas {
                            visible: modelData.name === "All"
                            width: window.s(14); height: window.s(14)
                            anchors.centerIn: parent
                            property string activeColor: window.currentFilter === modelData.name ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                            onActiveColorChanged: requestPaint()
                            property real scaleTrigger: window.s(1)
                            onScaleTriggerChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d");
                                var sf = window.s;
                                ctx.reset();
                                ctx.fillStyle = activeColor;
                                ctx.fillRect(0, 0, sf(6), sf(6));
                                ctx.fillRect(sf(8), 0, sf(6), sf(6));
                                ctx.fillRect(0, sf(8), sf(6), sf(6));
                                ctx.fillRect(sf(8), sf(8), sf(6), sf(6));
                            }
                        }
                    }

                    MouseArea {
                        id: filterMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !window.isApplying
                        onClicked: window.currentFilter = modelData.name
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }

            Rectangle {
                id: searchControlBtn
                visible: window.currentFilter === "Search" && window.hasSearched
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? window.s(44) : 0
                height: window.s(44)
                radius: window.s(10)
                clip: true
                color: window.isSearchPaused ? _theme.surface2 : "transparent"
                border.color: window.isSearchPaused ? _theme.text : Qt.rgba(_theme.surface1.r, _theme.surface1.g, _theme.surface1.b, 0.6)
                border.width: window.isSearchPaused ? window.s(2) : 1

                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
                Behavior on color { ColorAnimation { duration: 400; easing.type: Easing.OutQuart } }

                MouseArea {
                    id: scMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !window.isApplying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: window.isSearchPaused = !window.isSearchPaused
                }

                Canvas {
                    width: window.s(44); height: window.s(44)
                    anchors.centerIn: parent
                    property bool paused: window.isSearchPaused
                    property string activeColor: paused ? _theme.text : (scMouse.containsMouse ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7))
                    onActiveColorChanged: requestPaint()
                    onPausedChanged: requestPaint()
                    property real scaleTrigger: window.s(1)
                    onScaleTriggerChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d");
                        var sf = window.s;
                        ctx.reset();
                        ctx.fillStyle = activeColor;
                        if (!paused) {
                            ctx.fillRect(sf(15), sf(14), sf(4), sf(16));
                            ctx.fillRect(sf(25), sf(14), sf(4), sf(16));
                        } else {
                            ctx.beginPath();
                            ctx.moveTo(sf(16), sf(12));
                            ctx.lineTo(sf(32), sf(22));
                            ctx.lineTo(sf(16), sf(32));
                            ctx.closePath();
                            ctx.fill();
                        }
                    }
                }
            }

            Rectangle {
                id: searchBox
                height: window.s(44)
                anchors.verticalCenter: parent.verticalCenter
                width: window.currentFilter === "Search" ? window.s(360) : window.s(44)
                radius: window.s(10)
                clip: true

                color: window.currentFilter === "Search" ? Qt.rgba(_theme.surface2.r, _theme.surface2.g, _theme.surface2.b, 0.8) : "transparent"
                border.color: window.currentFilter === "Search" ? Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.5) : Qt.rgba(_theme.surface1.r, _theme.surface1.g, _theme.surface1.b, 0.6)
                border.width: window.currentFilter === "Search" ? window.s(2) : 1

                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
                Behavior on color { ColorAnimation { duration: 400; easing.type: Easing.OutQuart } }
                Behavior on border.color { ColorAnimation { duration: 400 } }

                MouseArea {
                    id: searchMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !window.isApplying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (window.currentFilter !== "Search") {
                            window.currentFilter = "Search"
                        } else {
                            window.currentFilter = "All"
                        }
                    }
                }

                Canvas {
                    id: searchIcon
                    width: window.s(44)
                    height: window.s(44)
                    anchors.left: parent.left
                    anchors.leftMargin: window.currentFilter === "Search" ? window.s(5) : 0
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on anchors.leftMargin { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                    property string activeColor: window.currentFilter === "Search" ? _theme.text : (searchMouseArea.containsMouse ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7))
                    onActiveColorChanged: requestPaint()
                    property real scaleTrigger: window.s(1)
                    onScaleTriggerChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d");
                        var sf = window.s;
                        ctx.reset();
                        ctx.lineWidth = sf(3);
                        ctx.strokeStyle = activeColor;
                        ctx.beginPath();
                        ctx.arc(sf(18), sf(18), sf(7), 0, Math.PI * 2);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.moveTo(sf(23), sf(23));
                        ctx.lineTo(sf(31), sf(31));
                        ctx.stroke();
                    }
                }

                TextInput {
                    id: searchInput
                    anchors.left: searchIcon.right
                    anchors.right: submitBtn.left
                    anchors.rightMargin: window.s(8)
                    anchors.verticalCenter: parent.verticalCenter

                    opacity: window.currentFilter === "Search" ? 1.0 : 0.0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }

                    color: _theme.text
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(16)
                    clip: true

                    onTextEdited: {
                        window.hasSearched = false;
                        searchState.searched = false;
                    }

                    onAccepted: {
                        window.triggerOnlineSearch();
                        searchInput.focus = false;
                        view.forceActiveFocus();
                    }
                }

                Rectangle {
                    id: submitBtn
                    width: window.s(32)
                    height: window.s(32)
                    radius: window.s(8)
                    anchors.right: parent.right
                    anchors.rightMargin: window.s(8)
                    anchors.verticalCenter: parent.verticalCenter

                    opacity: window.currentFilter === "Search" ? 1.0 : 0.0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }

                    color: submitMouseArea.containsMouse ? Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.1) : "transparent"
                    border.color: submitMouseArea.containsMouse ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.3)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 300 } }

                    MouseArea {
                        id: submitMouseArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        enabled: !window.isApplying
                        onClicked: {
                            window.triggerOnlineSearch();
                        }
                    }

                    Canvas {
                        width: window.s(16)
                        height: window.s(16)
                        anchors.centerIn: parent
                        property string activeColor: submitMouseArea.containsMouse ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                        onActiveColorChanged: requestPaint()
                        property real scaleTrigger: window.s(1)
                        onScaleTriggerChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d");
                            var sf = window.s;
                            ctx.reset();
                            ctx.lineWidth = sf(2);
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";
                            ctx.strokeStyle = activeColor;

                            ctx.beginPath();
                            ctx.moveTo(sf(2), sf(8));
                            ctx.lineTo(sf(14), sf(8));
                            ctx.moveTo(sf(9), sf(3));
                            ctx.lineTo(sf(14), sf(8));
                            ctx.lineTo(sf(9), sf(13));
                            ctx.stroke();
                        }
                    }
                }
            }

            // Revamp: Ask Claude mood-search pill + expander
            Rectangle {
                id: claudeBox
                anchors.verticalCenter: parent.verticalCenter
                height: window.s(44)
                width: window.s(44) + (window.claudeExpanded ? window.s(240) : 0)
                radius: window.s(10)
                clip: true

                color: window.claudeExpanded ? Qt.rgba(_theme.mauve.r, _theme.mauve.g, _theme.mauve.b, 0.18) : "transparent"
                border.color: window.claudeExpanded ? _theme.mauve : "transparent"
                border.width: window.claudeExpanded ? window.s(2) : 0

                Behavior on width { SpringAnimation { spring: 3.0; damping: 0.32; epsilon: 0.25 } }
                Behavior on color { ColorAnimation { duration: 300 } }
                Behavior on border.color { ColorAnimation { duration: 300 } }

                Canvas {
                    id: sparkleIcon
                    width: window.s(44)
                    height: window.s(44)
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    property string activeColor: window.claudeExpanded ? _theme.mauve : (claudeHov.hovered ? "#cba6f7" : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7))
                    onActiveColorChanged: requestPaint()
                    property real scaleTrigger: window.s(1)
                    onScaleTriggerChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d");
                        var sf = window.s;
                        ctx.reset();
                        ctx.fillStyle = activeColor;
                        function star(cx, cy, r) {
                            ctx.beginPath();
                            ctx.moveTo(cx, cy - r);
                            ctx.quadraticCurveTo(cx, cy, cx + r, cy);
                            ctx.quadraticCurveTo(cx, cy, cx, cy + r);
                            ctx.quadraticCurveTo(cx, cy, cx - r, cy);
                            ctx.quadraticCurveTo(cx, cy, cx, cy - r);
                            ctx.fill();
                        }
                        star(sf(20), sf(20), sf(8));
                        star(sf(30), sf(13), sf(4));
                        star(sf(31), sf(28), sf(3));
                    }
                }

                TextInput {
                    id: claudeInput
                    anchors.left: sparkleIcon.right
                    anchors.right: parent.right
                    anchors.rightMargin: window.s(12)
                    anchors.verticalCenter: parent.verticalCenter

                    opacity: window.claudeExpanded ? 1.0 : 0.0
                    visible: opacity > 0
                    enabled: window.claudeExpanded
                    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }

                    color: _theme.text
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(15)
                    clip: true

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: claudeInput.text === ""
                        text: "describe a vibe..."
                        color: Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.4)
                        font.family: "JetBrains Mono"
                        font.pixelSize: window.s(15)
                    }

                    onAccepted: {
                        window.askClaude();
                        claudeInput.focus = false;
                    }
                }

                MouseArea {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: window.s(44)
                    hoverEnabled: true
                    enabled: !window.isApplying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        window.claudeExpanded = !window.claudeExpanded;
                        if (window.claudeExpanded) claudeInput.forceActiveFocus();
                        else view.forceActiveFocus();
                    }
                    HoverHandler { id: claudeHov }
                }
            }
        }
    }

    Component.onCompleted: {
        Quickshell.execDetached(["bash", "-c", "mkdir -p '" + decodeURIComponent(window.searchDir.replace("file://", "")) + "'"]);

        if (searchState.searched) {
            searchInput.text = searchState.query;
            window.searchQuery = searchState.query;
            window.hasSearched = true;
            window.lastSearchName = searchState.lastName;
            window.isSearchPaused = true;
        }

        view.forceActiveFocus();
        window.processMarkers();
        window.triggerColorExtraction();
        window.rebuildGridModel();
        modeRestorer.running = true;
    }

    Component.onDestruction: {
        if (window.hasSearched) {
            searchState.query = searchInput.text;
            searchState.searched = window.hasSearched;
            searchState.lastName = window.lastSearchName;

            Quickshell.execDetached(["bash", "-c", "echo 'pause' > /tmp/ddg_search_control"]);
        } else {
            Quickshell.execDetached(["bash", "-c", "echo 'stop' > /tmp/ddg_search_control; for p in $(pgrep -f ddg_search.sh); do if [ \"$p\" != \"$$\" ] && [ \"$p\" != \"$BASHPID\" ]; then kill -9 $p 2>/dev/null || true; fi; done; pkill -f '[g]et_ddg_links.py'"]);
        }
    }
}
