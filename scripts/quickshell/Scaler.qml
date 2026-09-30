import QtQuick
import Quickshell
import Quickshell.Io
import "WindowRegistry.js" as LayoutMath 

Item {
    id: root
    visible: false

    property real currentWidth: 1920.0
    property real uiScale: 1.0

    property real baseScale: LayoutMath.getScale(currentWidth, uiScale)
    
    function s(val) { 
        return LayoutMath.s(val, baseScale); 
    }

    Process {
        id: scaleReader
        command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (this.text && this.text.trim().length > 0 && this.text.trim() !== "{}") {
                        let parsed = JSON.parse(this.text);
                        if (parsed.uiScale !== undefined && root.uiScale !== parsed.uiScale) {
                            root.uiScale = parsed.uiScale;
                        }
                    }
                } catch (e) {}
            }
        }
    }

    // EVENT-DRIVEN WATCHER
    Process {
        id: scaleWatcher
        // Persistent monitor (-m): ONE long-lived inotifywait, never re-armed. The
        // `exec` makes bash replace itself so quickshell's SIGTERM on hot-reload hits
        // inotifywait directly — the old re-arm+while pattern orphaned a watcher on
        // every reload, leaking hundreds against the inotify instance limit and
        // eventually killing every inotify-backed widget (topbar, CAW, OSDs).
        command: ["/home/czeddaru/.config/hypr/scripts/quickshell/lifeline.sh", "f=~/.config/hypr/settings.json; while [ ! -f \"$f\" ]; do sleep 1; done; exec inotifywait -m -q -e modify,close_write \"$f\""]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: {
                scaleReader.running = false;
                scaleReader.running = true;
            }
        }
    }
}
