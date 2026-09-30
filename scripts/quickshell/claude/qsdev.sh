#!/usr/bin/env bash
# Dev helper for the Claude resident agent stack. One command, no stitching.
# Usage: bash qsdev.sh <target>
#   daemon    restart claude_daemon (chat agent)
#   context   restart context_daemon (the machine-state bus)
#   resident  restart claude_resident (proactive nudges)
#   main      restart quickshell Main.qml (popup widgets)
#   bar       restart quickshell TopBar.qml
#   shell     restart Main + TopBar
#   agents    restart daemon + context + resident (no quickshell)
#   all       restart everything
#   status    show what's alive
#   log       tail the debug log
CLA="$HOME/.config/hypr/scripts/quickshell/claude"

restart_daemon() {
    pkill -9 -f claude_daemon.py 2>/dev/null
    pkill -9 -f "quickshell/claude/agent.py" 2>/dev/null
    sleep 1
    rm -f /tmp/qs_claude_daemon.pid /tmp/qs_claude_stream /tmp/qs_claude_in
    setsid -f python3 "$CLA/claude_daemon.py"
    echo "daemon restarted"
}
restart_context() {
    pkill -9 -f context_daemon.sh 2>/dev/null
    pkill -9 -f "quickshell/claude/context.py" 2>/dev/null
    sleep 1
    rm -f /tmp/qs_context_daemon.pid
    setsid -f bash "$CLA/context_daemon.sh"
    echo "context daemon restarted"
}
restart_resident() {
    pkill -9 -f claude_resident.py 2>/dev/null
    sleep 1
    rm -f /tmp/qs_resident.pid
    setsid -f python3 "$CLA/claude_resident.py"
    echo "resident restarted"
}
restart_main() {
    pkill -f "quickshell.*Main" 2>/dev/null; sleep 1
    setsid -f quickshell -p "$HOME/.config/hypr/scripts/quickshell/Main.qml"
    echo "Main.qml restarted"
}
restart_bar() {
    pkill -f "quickshell.*TopBar" 2>/dev/null; sleep 1
    setsid -f quickshell -p "$HOME/.config/hypr/scripts/quickshell/TopBar.qml"
    echo "TopBar.qml restarted"
}
status() {
    echo "claude_daemon : $(pgrep -fc claude_daemon.py)"
    echo "context_daemon: $(pgrep -fc context_daemon.sh)"
    echo "resident      : $(pgrep -fc claude_resident.py)"
    echo "agent (live)  : $(pgrep -fc 'quickshell/claude/agent.py')"
    echo "Main.qml      : $(pgrep -fc 'quickshell.*Main')"
    echo "TopBar.qml    : $(pgrep -fc 'quickshell.*TopBar')"
    echo "daemon status : $(cat /tmp/qs_claude_status 2>/dev/null || echo n/a)"
}

case "${1:-help}" in
    daemon)   restart_daemon ;;
    context)  restart_context ;;
    resident) restart_resident ;;
    main)     restart_main ;;
    bar)      restart_bar ;;
    shell)    restart_main; restart_bar ;;
    agents)   restart_daemon; restart_context; restart_resident ;;
    all)      restart_context; restart_resident; restart_daemon; restart_main; restart_bar ;;
    status)   status ;;
    log)      tail -n 40 -f /tmp/qs_claude_debug.log ;;
    *)        echo "usage: qsdev.sh {daemon|context|resident|main|bar|shell|agents|all|status|log}" ;;
esac
