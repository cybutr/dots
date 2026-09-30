#!/usr/bin/env python3
import sys, os, json, subprocess, shutil, threading, time, re

RS = "\x1e"

SYSTEM = (
    "You are Claude, embedded in the user's Hyprland/Arch desktop as an ambient agent. "
    "Be tight and direct, no preamble, no sign-off. Use markdown: short headings, lists, "
    "and fenced code blocks with a language tag for any command or code. "
    "When you suggest a shell command, always put it in a ```sh or ```bash block so the UI "
    "can offer a Run button. When you need a decision from the user, you may use the "
    "AskUserQuestion tool to present concrete options. Match the user's energy: a one-word "
    "greeting like 'yo' gets a one-word reply, not a status report. Every message may carry "
    "a prepended machine snapshot (battery, volume, workspaces, music, etc) below a '---' "
    "separator — that block is ambient background, not the user's question. Never mention, "
    "recite, or reference any value from it (no 'battery is at X%', no 'you're on "
    "workspace Y') unless the user's actual text explicitly asks about that thing. The real "
    "question is always the part after '---'; a greeting or short message gets a matching "
    "short reply with zero stats in it."
    "If the message starts with the literal tag '[voice]', it arrived through the spoken "
    "wake-word pipeline, not typed chat, and NO chat window is open — strip the tag from "
    "your understanding of what they said, do the task (use your tools), then surface the "
    "result by calling the notify tool with a title like 'Kandor' and a ONE-line plain-text "
    "answer, because a desktop notification is the only thing the user will see. Keep any "
    "text reply to that same one line; no markdown, no show_card, no code blocks unless they "
    "explicitly ask to see/pin something visual. Fast and glanceable, not a rich card."
    "You have live senses of this machine via these tools — call them by their exact "
    "names, they are already available so never search for them first:\n"
    "- mcp__qs-desktop__get_system_state: battery, mic, volume, wifi, CPU/mem/temp, top process\n"
    "- mcp__qs-desktop__list_events: the user's Google calendar today\n"
    "- mcp__qs-desktop__list_tasks: the user's Google tasks today\n"
    "- mcp__qs-desktop__focus_stats: per-app usage time\n"
    "- mcp__qs-desktop__read_quickshell_logs: QML error logs for debugging widgets\n"
    "- mcp__qs-desktop__recall: read what you've saved about the user long-term\n"
    "- mcp__qs-desktop__remember: save a durable fact (preference, habit, ongoing task)\n"
    "Call them whenever a question touches machine state, schedule, or a misbehaving "
    "widget — do not guess, and do not call ToolSearch for them. When the user reveals a "
    "lasting preference or recurring thing, quietly remember it.\n"
    "When the user tells you to do something for a set duration (e.g. 'talk to X for an "
    "hour', 'work on this for 20 minutes'), your FIRST action MUST be "
    "mcp__qs-desktop__start_work_timer(minutes, task) — never CronCreate, the schedule "
    "skill, or the loop skill. A Stop hook then physically keeps you working until it "
    "expires; call mcp__qs-desktop__check_work_timer before you ever consider stopping.\n"
    "In AUTO mode you can also act on the desktop (these need AUTO; if not in AUTO, tell "
    "the user to switch): mcp__qs-desktop__complete_task and add_task (Google Tasks — get "
    "ids from list_tasks before completing), open_widget (open a popup), hypr (hyprctl "
    "Agent-only widgets you can open (no keybind — opened only via open_widget, or a card "
    "button action:{fn:'open_widget',args:{name:<w>}}): people (saved Discord contact "
    "profiles with full detail), memory (everything you've remembered long-term, "
    "searchable), netstatus (live wifi + ProtonVPN status). Open 'people' when the user "
    "asks 'who do you know' / 'show me my contacts', 'memory' for 'what do you remember "
    "about me', 'netstatus' for vpn/network state. "
    "dispatch), notify, set_volume, toggle_mute, mic_mute, power_profile, wifi_control "
    "(status/list/toggle/on/off/connect[ssid,password]/disconnect), bluetooth_control "
    "(status/toggle/on/off/connect[mac]/disconnect[mac] — get mac from status first), "
    "vpn_control (ProtonVPN: status/connect[server?]/disconnect, plus per-wifi "
    "auto-connect learning — autolearn marks the current wifi so VPN auto-connects "
    "there, autoforget/autolist manage them, autocheck connects if the current wifi is "
    "a learned spot. Default is IDLE: never connect unless the user asks or you're on a "
    "learned wifi. When the user says 'always vpn on this wifi' call autolearn; when they "
    "just say 'connect vpn' call connect. Never connect proactively on an unlearned wifi), "
    "screenshot (see "
    "the screen — pass target=<class/title substring> with mode=window to capture a "
    "specific app instead of whatever's focused, which during a chat turn is usually this "
    "chat widget itself), window_control (move/resize/focus/launch/close windows), app_open "
    "(focus an app if it's running or launch it if not, one call instead of "
    "list+launch+focus), input_control (simulate clicks/keys/typing via ydotool), file_ops "
    "(read/write/move files under ~/Documents, ~/Downloads, ~/Images, ~/.config/hypr), "
    "browser_tabs (list what's open in Vivaldi), browser_open (open a URL in a new tab — "
    "auto-launches Vivaldi if it's not running), browser_switch_tab and browser_close_tab "
    "(by id from browser_tabs), browser_eval (run JS in an open tab to actually read its "
    "content, e.g. document.body.innerText), clipboard_control (read/write/history), "
    "process_control (list/kill processes), notification_read (recent desktop "
    "notifications). window_control's launch action and app_open both take an optional "
    "background=true — when set, the app launches without stealing focus or yanking the "
    "user to another workspace, restoring focus to whatever they were on right after. Use "
    "background=true whenever you're opening something the user didn't directly ask to "
    "see right now (prep work, a reference tab, anything ambient) so it doesn't interrupt "
    "what they're doing. Confirm destructive or surprising actions in one short line before "
    "doing them. If a tool returns pending=true, it means an unattended run hit a "
    "capability that needs the user's one-time approval — stop and say so plainly, don't "
    "retry it.\n"
    "mcp__qs-desktop__card_template lets you save a show_card layout under a short name and "
    "recall it later instead of rebuilding the same dashboard from scratch every time — save "
    "one once a user reacts well to it, then list/get it on a later 'show me X again' ask.\n"
    "When the user corrects, criticizes, or states a clear preference about how a card LOOKS "
    "or BEHAVES — not its data — capture it with mcp__qs-desktop__remember as a short, "
    "directly-actionable note ('user prefers compact pinned cards by default', 'user wants "
    "media buttons bound to actually toggle, not static labels', 'don't add CPU/battery to "
    "cards that didn't ask for it'), not a vague 'user said something about cards'. Before "
    "building a non-trivial card (multiple blocks, or a dashboard/status card you suspect "
    "you've built for this user before), call mcp__qs-desktop__recall first if you haven't "
    "already this session, so those prior corrections actually shape the new card instead of "
    "sitting unused in memory. This is narrowly about fixing your card-building HABITS, not "
    "the same thing as card_template (which saves a literal layout to reuse) or general "
    "user-preference memory — it's specifically 'the user told me my cards were wrong, so "
    "build them that way from now on'.\n"
    "mcp__qs-desktop__show_card renders an interactive, composable card in the chat instead "
    "of plain text — use it proactively, don't wait to be asked. It's a title/icon plus a "
    "list of 'blocks' you stack and mix freely: rows (icon+label/value grid, e.g. a spec "
    "sheet), gauges (ring meters for percent-like values), bars (linear progress bars), "
    "pills (segmented choice, clicking sends the choice back), buttons (action row, e.g. "
    "Accept/Decline), list (bullets), text (a paragraph). Default to a card whenever your "
    "reply is mainly numbers/status (battery, CPU, memory, temp, volume, any "
    "get_system_state-shaped data) — gauges block for percent metrics, rows block for plain "
    "facts. Use buttons/pills when you want the user to decide something (also flags the "
    "topbar dot). Give a gauges/bars item 'source' (a shell command) instead of a static "
    "value to make it self-refresh on a timer for as long as the card is open — use this for "
    "anything that changes (CPU/battery/temp), not a one-time value. For cpu/mem/temp/battery/"
    "volume specifically, use 'metric' (set to that name) instead of 'source' — it reads a "
    "shared, centrally-polled bus rather than spawning a shell process per tile, which is "
    "cheaper and the right default any time the card shows one of those five. Still give a one-line "
    "text reply alongside the card, but let the card carry the actual data — and don't be "
    "shy about combining several blocks in one card. Icons: pass a semantic name string "
    "(e.g. icon:'cpu', 'gpu', 'disk', 'volume', 'wifi', 'battery', 'power', 'temp', 'kernel', "
    "'os', 'clock', 'calendar', 'task', 'check', 'close', 'warning', 'chart') — the UI maps "
    "known names to a real glyph; never hand-type a raw Nerd Font character, it silently "
    "renders blank. pills/buttons items can also be {label, icon?, action:{fn, args}} instead "
    "of a plain string — fn is one of power_profile{profile}, toggle_wifi{state}, "
    "toggle_bluetooth{}, bluetooth_connect{mac}, bluetooth_disconnect{mac}, "
    "set_volume{percent}, toggle_mute{}, mic_mute{muted}, media_control{action}, "
    "open_widget{name,toggle}, open_mail{thread_id,account}. A bound action runs instantly client-side with zero chat "
    "tokens and never becomes a message in your context. THIS IS NOT OPTIONAL: any pills, "
    "buttons, or iconbuttons item that maps to a known system action MUST use the "
    "{label, icon?, action:{fn, args}} form — NEVER a plain string for those. "
    "iconbuttons are ALWAYS wired: lock→{icon:'lock',label:'Lock',action:{fn:'hypr',args:{cmd:'dispatch exec bash ~/.config/hypr/scripts/lock.sh'}}}, "
    "sleep→{icon:'sleep',label:'Sleep',action:{fn:'hypr',args:{cmd:'dispatch exec systemctl suspend'}}}, "
    "reboot→{icon:'reboot',label:'Reboot',action:{fn:'hypr',args:{cmd:'dispatch exec systemctl reboot'}}}, "
    "shutdown→{icon:'shutdown',label:'Power Off',action:{fn:'hypr',args:{cmd:'dispatch exec systemctl poweroff -i'}}}, "
    "power profile pills→action:{fn:'power_profile',args:{profile:<label>}}, "
    "media→action:{fn:'media_control',args:{action:<play-pause|next|previous>}}, "
    "mute→action:{fn:'toggle_mute'}, volume→action:{fn:'set_volume',args:{percent:N}}, "
    "open widget→action:{fn:'open_widget',args:{name:<widget>}}. "
    "Plain strings only for choices you need to react to (wifi network name, free-form answer). If the user "
    "explicitly asks to pin/keep a card on screen, pass pinned:true on the show_card call "
    "itself instead of telling them to click the pin icon — it goes straight to the "
    "persistent side panel, live and clickable independent of this chat window. Add "
    "board:'<name>' alongside it to group related pinned cards under a named tab in that "
    "panel (e.g. 'System', 'Music') instead of one undifferentiated pile.\n"
    "Prefer 'watch':'<file>' over 'source'+timer whenever a file reflects live state. "
    "metric:/source:/watch: all work identically on gauges, bars AND rows items — a bars "
    "item can take watch:'<file>' (the file's contents become the bar fill/value, event-driven "
    "via inotify) exactly like a gauge can; don't fall back to source+timer for a bar when a "
    "file already reflects the value. "
    "Known watch files (ALWAYS use these, never poll/metric for them): "
    "/tmp/qs_volume_state (volume, '72%' or 'muted'), "
    "/tmp/qs_workspaces.json (workspace — source: jq -r '[.[]|select(.state==\"active\")|.name]|first'), "
    "/tmp/qs_active_widget (active widget name, bare watch). "
    "For cpu/mem/battery/temp use metric:. "
    "Action buttons should track live state — give a buttons item "
    "'live':{source?|watch?|metric?, interval_ms?} so labels stay current. "
    "Dropdowns: ALWAYS populate 'selected' with the current value before showing — "
    "call get_system_state or run a quick source command first if needed "
    "(e.g. power profile dropdown: run `powerprofilesctl get` to get current profile, "
    "pass it as selected; wifi dropdown: use the connected SSID from get_system_state). "
    "Never show a dropdown with no pre-selected value when the current state is knowable.\n"
    "mcp__qs-desktop__update_card edits a card you already showed, by the card_id you gave "
    "it on show_card (pass card_id:'<short-stable-id>' on show_card up front if you might "
    "want to revise that exact card later — confirming a result, flipping a status, "
    "updating a block — instead of posting a whole new one). patch:{blocks} replaces "
    "everything; patch:{block_ops:[{op:'replace'|'remove'|'insert', index?|match:{kind}, "
    "block?}]} edits surgically. This is how you close the loop on an action: show a card "
    "with a pending state, run the thing, then update_card the same card_id to reflect what "
    "actually happened, rather than leaving it frozen or sending a second unrelated card.\n"
    "For anything involving a password or other credential, use a 'secret' block on "
    "show_card (kind:'secret', prompt, action:{fn, args}; fn one of wifi_connect{ssid}, "
    "vpn_connect{name}, bluetooth_pair{mac}) instead of ever asking the user to type a "
    "password in chat. The value never reaches you — it's substituted client-side into the "
    "matching local command only, and the result (connected/failed) shows on the card "
    "itself. Failed attempts keep the input live for retry — the card only locks on success.\n"
    "Wifi/bluetooth flows: NEVER just ask 'which network?' in chat. ALWAYS build a card "
    "first. For wifi: run `nmcli -t -f SSID,SIGNAL,SECURITY device wifi list --rescan yes` "
    "via get_system_state or a bash source, show results as a buttons block (each button = "
    "one SSID, plain string so clicking it messages you), plus a rows block showing current "
    "connection status watching /tmp/qs_volume_state isn't relevant here — just use source. "
    "When the user picks a network (you see 'Card X: user chose Y'), immediately follow up "
    "with a secret card for that SSID. For bluetooth: run `bluetoothctl devices` to list "
    "known devices, show as buttons; for scanning nearby use "
    "`bluetoothctl --timeout 5 scan on && bluetoothctl devices`. "
    "Same pattern: buttons to pick, secret card to pair if needed.\n"
    "SILENT CONTROLS: any pills/buttons/iconbuttons/dropdown item (or dropdown 'options' "
    "entry) may carry silent:true. When the user clicks it, instead of messaging you a "
    "visible 'user chose X' chat line, the control itself enters a polished pending state "
    "(animated dots) and a HIDDEN turn runs you with no chat output — you carry out the "
    "implied action with your tools and call update_card on that same card_id to reflect the "
    "result, then the control resolves to a ✓ (or ✗ on failure). Nothing about the click or "
    "your work appears in chat. This is the THIRD wiring option; pick per item:\n"
    "  1. action:{fn,args} — a known allowlisted system action (the list above). Runs "
    "instantly client-side, zero agent turn. ALWAYS prefer this when the action fits an fn.\n"
    "  2. silent:true — the action needs YOU (multi-step, a non-allowlisted command, reads "
    "state then decides, or should update the card afterward) but the user shouldn't see "
    "chat chatter for it. Requires AUTO mode to actually mutate the desktop; in ASK it can "
    "still update_card (display) but not run commands.\n"
    "  3. plain string — only when you genuinely need the choice as a chat message to reason "
    "about and reply (wifi SSID pick, free-form answer).\n"
    "Silent turns: do the work, update_card the same card_id, write NO prose. If a silent "
    "control implies state the card should now show (toggled on, new profile, done), the "
    "update_card is mandatory or the control just blinks ✓ and reverts.\n"
    "CARD DOCTRINE — the user will often ask tersely ('make a system card rq', 'gimme media "
    "controls'). Do not interrogate them; make strong default choices and build it:\n"
    "  - Title + semantic icon always. Combine several block kinds in one card — a bare "
    "single block looks unfinished. Lead with the highest-signal block (gauges/rows).\n"
    "  - percent/0-100 live values -> gauges; linear quantities -> bars; flat facts -> rows; "
    "choices -> pills; actions -> buttons/iconbuttons; bullets -> list; prose -> text.\n"
    "  - WIRE EVERYTHING. No decorative/static controls — every button/pill/option gets "
    "action:{fn} (option 1) or silent:true (option 2). A control that does nothing is a bug.\n"
    "  - Live by default: cpu/mem/temp/battery/volume use metric:; file-backed state uses "
    "watch:; anything else that changes uses source:. Static values only for true constants.\n"
    "  - Colors/glass/sheen/hover are the renderer's job — never specify them; just choose "
    "good icons and sensible per-item ordering. Pre-select dropdowns/pills to current state.\n"
    "  - Default media/power/volume/wifi/bt controls to action:{fn}; default 'do a thing and "
    "show me the result on the card' controls to silent:true. When unsure between a chat "
    "reply and a silent card action for an actionable click, prefer silent.\n"
    "  - Keep one short text line in chat alongside; the card carries the data.\n"
    "  - NO reflex stats. Do NOT staple cpu/mem/temp/battery gauges onto a card just because "
    "you can — only include a metric the user asked for or that's genuinely the point of the "
    "card. A media card is media controls, not media + a CPU gauge.\n"
    "  - Before any non-trivial or dashboard/system card, call mcp__qs-desktop__pinned_cards "
    "first and respect what's already pinned: don't build a second card showing data the user "
    "already keeps pinned. If a fitting pinned card exists (match by card_id/title), update IT "
    "via update_card instead of spawning a near-duplicate."
)

RESIDENT_EXTRA = (
    "\nYou were woken up by the resident background watcher, not the chat widget — the "
    "user did not ask you anything directly this turn. Default every window_control/"
    "app_open/browser_open call to background=true unless the prompt explicitly says this "
    "is something the user wants to see immediately. Keep your final reply to one short "
    "line; it goes into a desktop notification, not a chat transcript."
)

MCP_CONFIG = os.path.expanduser("~/.config/hypr/scripts/quickshell/claude/qs_mcp.json")
QS_TOOLS = ["mcp__qs-desktop__get_system_state",
            "mcp__qs-desktop__list_events",
            "mcp__qs-desktop__list_tasks",
            "mcp__qs-desktop__focus_stats",
            "mcp__qs-desktop__read_quickshell_logs",
            "mcp__qs-desktop__recall",
            "mcp__qs-desktop__remember",
            "mcp__qs-desktop__memory_search",
            "mcp__qs-desktop__workspace_status"]

MEM_FILE = os.path.expanduser("~/.local/share/qs_claude_memory.md")


def memory_block():
    try:
        with open(MEM_FILE) as f:
            mem = f.read().strip()
        return ("\n\nWhat you remember about this user (long-term memory):\n" + mem) if mem else ""
    except OSError:
        return ""

# read-only / display-only MCP tools: safe in ASK mode. glance at state +
# render cards in chat, but never mutate the desktop (no open_widget, hypr,
# volume, wifi, window/input control, file_ops, etc.).
ASK_MCP = ["mcp__qs-desktop__get_workspaces",
           "mcp__qs-desktop__get_music",
           "mcp__qs-desktop__browser_tabs",
           "mcp__qs-desktop__notification_read",
           "mcp__qs-desktop__mailbox_read",
           "mcp__qs-desktop__mailbox_post",
           "mcp__qs-desktop__card_template",
           "mcp__qs-desktop__pinned_cards",
           "mcp__qs-desktop__show_card",
           "mcp__qs-desktop__update_card",
           "mcp__qs-desktop__suggest",
           "mcp__qs-desktop__notify",
           "mcp__qs-desktop__autopilot_await",
           "mcp__qs-desktop__start_work_timer",
           "mcp__qs-desktop__check_work_timer",
           "mcp__qs-desktop__mail_search",
           "mcp__qs-desktop__mail_read"]

# Discord read-only tools — safe in ASK mode. Mutators (send/edit/delete/react/etc.)
# are deliberately NOT here: the ask-approve-gate hook permits those one at a time
# after the user approves the on-screen card.
DISCORD_READ = ["mcp__discord-mcp__connection_status",
                "mcp__discord-mcp__get_current_user",
                "mcp__discord-mcp__get_user_info",
                "mcp__discord-mcp__get_guild_info",
                "mcp__discord-mcp__list_guilds",
                "mcp__discord-mcp__list_channels",
                "mcp__discord-mcp__get_channel_info",
                "mcp__discord-mcp__read_messages",
                "mcp__discord-mcp__search_messages",
                "mcp__discord-mcp__list_dms",
                "mcp__discord-mcp__list_guild_members",
                "mcp__discord-mcp__list_roles",
                "mcp__discord-mcp__discord_inbox",
                "mcp__discord-mcp__discord_wait_events",
                "mcp__discord-mcp__discord_fetch_attachment",
                "mcp__discord-mcp__discord_style",
                "mcp__discord-mcp__discord_trusted",
                "mcp__discord-mcp__discord_identity",
                "mcp__discord-mcp__discord_my_messages",
                "mcp__discord-mcp__person_get",
                "mcp__discord-mcp__person_note",
                "mcp__discord-mcp__person_list"]

# Spotify read-only tools — safe in ASK (no playback/library mutation).
SPOTIFY_READ = ["mcp__spotify__getNowPlaying", "mcp__spotify__searchSpotify",
                "mcp__spotify__getMyPlaylists", "mcp__spotify__getPlaylist",
                "mcp__spotify__getPlaylistTracks", "mcp__spotify__getQueue",
                "mcp__spotify__getRecentlyPlayed", "mcp__spotify__getUsersSavedTracks",
                "mcp__spotify__getAlbums", "mcp__spotify__getAlbumTracks",
                "mcp__spotify__getAvailableDevices", "mcp__spotify__getTopArtists",
                "mcp__spotify__getTopTracks", "mcp__spotify__checkUsersSavedAlbums"]

# Spotify control/mutating tools — gated in ASK (approval card), free in AUTO.
SPOTIFY_CONTROL = ["mcp__spotify__playMusic", "mcp__spotify__pausePlayback",
                   "mcp__spotify__resumePlayback", "mcp__spotify__skipToNext",
                   "mcp__spotify__skipToPrevious", "mcp__spotify__addToQueue",
                   "mcp__spotify__setVolume", "mcp__spotify__adjustVolume",
                   "mcp__spotify__createPlaylist", "mcp__spotify__addTracksToPlaylist",
                   "mcp__spotify__removeTracksFromPlaylist", "mcp__spotify__reorderPlaylistItems",
                   "mcp__spotify__unfollowPlaylist", "mcp__spotify__updatePlaylist",
                   "mcp__spotify__saveOrRemoveAlbumForUser", "mcp__spotify__removeUsersSavedTracks"]

# Obsidian tools — the user's own notes (low-stakes, reversible via Obsidian
# history); allowed freely in ASK, not gated, so the photo→notes flow is smooth.
OBSIDIAN_TOOLS = ["mcp__obsidian__obsidian_list", "mcp__obsidian__obsidian_read",
                  "mcp__obsidian__obsidian_search", "mcp__obsidian__obsidian_append",
                  "mcp__obsidian__obsidian_create", "mcp__obsidian__obsidian_patch"]

READ_TOOLS = (["Read", "Glob", "Grep", "WebSearch", "WebFetch", "AskUserQuestion"]
              + QS_TOOLS + ASK_MCP + DISCORD_READ + SPOTIFY_READ + OBSIDIAN_TOOLS)

# Action tools allowed in ASK mode. The ask-approve-gate.js hook decides which
# actually need an approval card: outward-facing ones (Discord sends, file edits)
# are gated; low-stakes reversible ones (your own Spotify playback) pass freely.
# Listed here so they're callable at all in ASK.
ASK_GATED_TOOLS = ["Write", "Edit",
                   "mcp__discord-mcp__send_message", "mcp__discord-mcp__send_dm",
                   "mcp__discord-mcp__edit_message", "mcp__discord-mcp__delete_message",
                   "mcp__discord-mcp__add_reaction", "mcp__discord-mcp__remove_reaction",
                   "mcp__discord-mcp__create_thread", "mcp__discord-mcp__pin_message",
                   "mcp__discord-mcp__unpin_message", "mcp__discord-mcp__set_nickname",
                   "mcp__discord-mcp__set_status", "mcp__discord-mcp__start_typing",
                   "mcp__discord-mcp__discord_send_gif", "mcp__discord-mcp__discord_send_file",
                   "mcp__discord-mcp__discord_queue"] + SPOTIFY_CONTROL

_emit_lock = threading.Lock()


def find_claude():
    p = shutil.which("claude")
    if p:
        return p
    for c in [os.path.expanduser("~/.local/bin/claude"), "/usr/bin/claude", "/usr/local/bin/claude"]:
        if os.path.exists(c):
            return c
    return "claude"


def get_key():
    k = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if k:
        return k
    for p in [os.path.expanduser("~/.config/anthropic/key"),
              os.path.expanduser("~/.config/anthropic/api_key")]:
        try:
            with open(p) as f:
                v = f.read().strip()
                if v:
                    return v
        except OSError:
            pass
    return ""


CONF = os.path.expanduser("~/.config/anthropic")
PROXY_URL = "https://cc.freemodel.dev"


def _load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


ACCT_SH = os.path.expanduser("~/.config/hypr/scripts/anthropic_acct.sh")

# same rate-limit/outage vocabulary the terminal `claude` wrapper (claude.fish)
# uses to decide whether to fall over to the next backend
FAIL_RE = re.compile(
    r"rate.?limit|usage limit|exceeded|too many requests|429|quota|overloaded|"
    r"please try again|/login|not logged in|econnrefused|network error|fetch failed|"
    r"upstream|bad gateway|service unavailable|gateway timeout|internal server error|"
    r"authentication_error", re.I)


def resolve_auth(override):
    return resolve_auth_for_id(override, _load_json(os.path.join(CONF, "accounts.json"),
                                                      {"active": "", "entries": []}))


def resolve_auth_for_id(tid_or_override, reg, set_active=False):
    cur = _load_json(os.path.join(CONF, "current.json"), {})
    entries = {e.get("id"): e for e in reg.get("entries", [])}
    tid = tid_or_override if (tid_or_override and tid_or_override not in ("auto", "")) \
        else (cur.get("id") or reg.get("active", ""))
    entry = entries.get(tid)
    if entry is None:
        k = get_key()
        return ("key", k, PROXY_URL, "", None) if k else ("account", None, None, "", None)
    etype = entry.get("type")
    if etype == "key":
        try:
            with open(os.path.join(CONF, "accounts", tid + ".key")) as f:
                k = f.read().strip()
        except OSError:
            k = ""
        return ("key", k, entry.get("base_url") or PROXY_URL, entry.get("model") or "", None)
    if etype == "opencode":
        return ("opencode", None, None, "", entry)
    if set_active and tid and cur.get("id") != tid:
        try:
            subprocess.run([ACCT_SH, "set", tid, "silent"], check=False, timeout=10)
        except Exception:
            pass
    return ("account", None, None, "", None)


def build_candidates(auth_override):
    """active/chosen backend first, then every other non-disabled registry
    entry in order — mirrors claude.fish's fallback chain so a rate-limited
    or unreachable account never leaves the agent silently stuck."""
    reg = _load_json(os.path.join(CONF, "accounts.json"), {"active": "", "entries": []})
    cur = _load_json(os.path.join(CONF, "current.json"), {})
    orig = auth_override if (auth_override and auth_override not in ("auto", "")) \
        else (cur.get("id") or reg.get("active", ""))
    ids = [orig] if orig else []
    for e in reg.get("entries", []):
        if e.get("disabled"):
            continue
        eid = e.get("id")
        if eid and eid not in ids:
            ids.append(eid)
    return ids, reg


def auto_disable(tid, resets_at, reason):
    if not tid or not resets_at:
        return
    try:
        subprocess.run([ACCT_SH, "auto-disable", tid, str(int(resets_at)), reason or "limit"],
                       check=False, timeout=10)
    except Exception:
        pass


def find_opencode():
    p = shutil.which("opencode")
    if p:
        return p
    c = os.path.expanduser("~/.local/bin/opencode")
    return c if os.path.exists(c) else "opencode"


def run_opencode_once(entry, text, timeout_s=25):
    """opencode has no persistent bidirectional stream like claude -p
    --input-format stream-json — each turn is a fresh one-shot `opencode run`.
    No MCP/card tools here, just a plain-text reply; that's an accepted trade
    for having a real, working fallback tier instead of nothing."""
    provider = (entry or {}).get("provider", "") or "opencode"
    model = (entry or {}).get("model", "")
    cmd = [find_opencode(), "run"]
    if model:
        cmd += ["--model", f"{provider}/{model}"]
    cmd.append(text)
    env = os.environ.copy()
    env["PATH"] = os.path.expanduser("~/.local/bin") + ":" + env.get("PATH", "")
    try:
        # stdin must NOT inherit agent.py's own stdin — that's a long-lived
        # pipe from the daemon that's never closed, and opencode blocks
        # waiting on it instead of returning
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s,
                           env=env, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return (False, f"opencode timed out after {timeout_s}s")
    out = (r.stdout or "").strip()
    err = (r.stderr or "").strip()
    combined = (out + "\n" + err).strip()
    if r.returncode == 0 and out and not FAIL_RE.search(combined):
        return (True, out)
    return (False, combined[:400] or "opencode error")


# a silent turn (a card control flagged silent:true) tags every event it produces so the
# daemon drops them from the chat transcript and resolves the control via the ack bus instead.
g_silent = False
g_iid = ""


def emit(obj):
    if g_silent:
        obj = dict(obj)
        obj["silent"] = True
        obj["iid"] = g_iid
    with _emit_lock:
        sys.stdout.write(json.dumps(obj) + RS)
        sys.stdout.flush()


def end_turn():
    global g_silent, g_iid
    emit({"t": "turn"})
    g_silent = False
    g_iid = ""


SILENT_NOTE = (
    "[SILENT CARD INTERACTION] The user clicked a control on a card you rendered. Carry out "
    "the action it implies using your tools — run the command, call update_card to reflect the "
    "new state on that control, send a notification if useful. Do NOT write any chat prose: "
    "there is no visible chat for this interaction, only your tool calls take effect.\n\n"
)

MODE_NOTES = {
    "ask": ("\n\nCURRENT MODE: ASK (approval-gated). You can read freely and you MAY act, "
            "but every action that changes anything (sending a message, editing/writing a "
            "file, shell, volume/wifi/window/input, opening widgets) requires the user's "
            "approval first. To act: show an approval card with mcp__qs-desktop__show_card "
            "describing the exact action, with a buttons block "
            "[{label:\"Approve\",icon:\"check\",action:{fn:\"autopilot_decide\",args:{id:\"<id>\","
            "choice:\"approve\"}}},{label:\"Deny\",icon:\"x\",action:{fn:\"autopilot_decide\","
            "args:{id:\"<id>\",choice:\"deny\"}}}] (use a unique id), then call "
            "mcp__qs-desktop__autopilot_await({id:\"<id>\"}); if approved, immediately perform "
            "the action — it will be permitted once. If you forget and call an action "
            "directly, it's blocked with a reminder to do this. One approval authorizes one "
            "action. Reads, web search, and rendering cards never need approval."),
    "plan": ("\n\nCURRENT MODE: PLAN. Think the task through and present a concrete plan "
             "via ExitPlanMode — do NOT edit files, run commands, or change the desktop. "
             "When the user approves, the UI switches you to AUTO and re-sends the go-ahead; "
             "only then do you execute."),
    "auto": ("\n\nCURRENT MODE: AUTO. Full access — act directly. Use the desktop action "
             "tools (open_widget, hypr, set_volume, window_control, file_ops, etc.) to "
             "actually do what's asked instead of describing it. Do NOT show approval cards "
             "and do NOT call autopilot_await — those exist ONLY for ASK mode. In AUTO you are "
             "pre-authorized: just run the tool (reading processes, files, system state, sending "
             "a message, etc.) and report the result. The only thing you pause for is a genuinely "
             "destructive or irreversible action (deleting many files, force-killing critical "
             "processes) — confirm that in one short line, nothing else."),
    "resident": "",
}


def mode_note_for(mode):
    return MODE_NOTES.get(mode, "")


def _claude_env_map():
    values = {}
    env_path = Path(__file__).with_name(".env")
    if env_path.exists():
        for raw_line in env_path.read_text().splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


CLAUDE_ENV = _claude_env_map()
GOOGLE_USER_EMAIL = os.environ.get("USER_GOOGLE_EMAIL") or CLAUDE_ENV.get("USER_GOOGLE_EMAIL") or "simekadam007@gmail.com"


GMAIL_NOTE = (f"\n\nGOOGLE WORKSPACE: Gmail/Drive/Docs/Sheets/Calendar run through the gsuite "
              f"MCP (mcp__gsuite__*). The ONLY authorized account is {GOOGLE_USER_EMAIL} — "
              f"always pass user_google_email='{GOOGLE_USER_EMAIL}' to every gsuite tool. "
              "NEVER use claude@pixelfields.net or any other address; doing so triggers a bogus "
              "reauth loop. Just call the gsuite tool you need directly — do NOT call "
              "mcp__qs-desktop__workspace_status first 'to be safe', that's a wasted round-trip "
              "almost every time. Only if a tool returns an auth-required error for "
              f"{GOOGLE_USER_EMAIL} (the token genuinely expired) do you call workspace_status "
              "to get a fresh reauth_url, then show the user an UNPINNABLE card titled 'Google "
              "sign-in needed' with a buttons block "
              "[{label:'Authorize Google',icon:'google',action:{fn:'open_url',args:{url:'<reauth_url "
              "from workspace_status>'}}}], one short line telling them to finish sign-in in the "
              "browser, then retry once they confirm. The card is auto-refused for pinning."
              " FINDING MAIL: when the user wants to find, check or quote an email (\"find that email from X "
              "about Y\", \"did Z reply\", \"what was the tracking number\"), use mcp__qs-desktop__mail_search "
              "(and mail_read for contents) instead of gsuite — it covers every account in Mira, their mail "
              "client, works in every mode, and each hit carries an open_action. Answer in one short line, then "
              "show_card with the top 1-3 hits (sender, subject, date) and 'Open in Mira' buttons using each "
              "hit's open_action {fn:'open_mail', args:{thread_id, account}}.")

MAILBOX_NOTE = ("\n\nMAILBOX: /tmp/qs_claude_mailbox.json is a real cross-session log shared with "
                "the resident daemon and every other Claude process on this machine (mailbox_read/"
                "mailbox_post) — treat it as live, not decorative. Call mcp__qs-desktop__mailbox_read "
                "(for='me' or unread_only=false) early when the user's ask is substantive or "
                "multi-step (debugging, a config change, anything that takes several tool calls) — "
                "another session or the resident may have left context worth knowing before you dig "
                "in. Skip it for simple one-off questions/greetings, don't call it on every message. "
                "Call mcp__qs-desktop__mailbox_post when you finish something another session, the "
                "resident, or the user would want a trail of — a bug fixed, a subsystem changed, a "
                "decision made. Keep it to genuinely notable moments, one line is enough "
                "(to='user' for a human-readable note, to='resident' if it's something the ambient "
                "daemon should act on or know). Don't post routine Q&A.")

MUSIC_NOTE = ("\n\nMUSIC: the Spotify MCP tools (mcp__spotify__*) are the source of truth for "
              "anything music — use them for what's playing, search, play/pause/skip/queue, volume, "
              "and playlists. The ambient machine snapshot's now-playing line and get_music are only a "
              "passive readout; do not call get_music to answer a music question — use "
              "mcp__spotify__getNowPlaying. Reach for Spotify tools whenever music comes up.")


def _partial_json(raw):
    """Best-effort parse of an in-progress JSON object being streamed token by
    token — used to render a show_card preview while Claude is still 'typing'
    the tool call, instead of a blank typing indicator for several seconds."""
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        pass
    stack = []
    in_str = False
    esc = False
    last_safe = 0
    for i, c in enumerate(raw):
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
                last_safe = i + 1
            continue
        if c == '"':
            in_str = True
        elif c in "{[":
            stack.append(c)
            last_safe = i + 1
        elif c in "}]":
            if stack:
                stack.pop()
            last_safe = i + 1
        elif c in ",:" or c.isspace():
            continue
    candidate = raw[:last_safe].rstrip()
    if candidate.endswith(","):
        candidate = candidate[:-1]
    closer = "".join("}" if ch == "{" else "]" for ch in reversed(stack))
    try:
        return json.loads(candidate + closer)
    except (json.JSONDecodeError, ValueError):
        return None


def reader(proc, mgr):
    tool_inputs = {}
    tool_names = {}
    card_sids = {}
    card_last_emit = {}
    card_sid_by_tool_id = {}
    ask_ids = set()
    model_name = ""
    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue
        try:
            o = json.loads(line)
        except json.JSONDecodeError:
            continue
        t = o.get("type")

        if t == "system" and o.get("subtype") == "init":
            sid = o.get("session_id")
            model_name = o.get("model", "") or model_name
            if sid:
                emit({"t": "session", "id": sid, "model": model_name})

        elif t == "stream_event":
            ev = o.get("event", {})
            et = ev.get("type")
            if et == "message_start":
                m = ev.get("message", {})
                model_name = m.get("model", "") or model_name
            elif et == "content_block_start":
                idx = ev.get("index")
                cb = ev.get("content_block", {})
                if cb.get("type") == "tool_use":
                    mgr.turn_state["has_output"] = True
                    tool_inputs[idx] = ""
                    name = cb.get("name", "tool")
                    tool_names[idx] = name
                    if name == "show_card" or name.endswith("__show_card"):
                        sid = f"sc{idx}_{int(time.time() * 1000)}"
                        card_sids[idx] = sid
                        tool_id = cb.get("id")
                        if tool_id:
                            card_sid_by_tool_id[tool_id] = sid
                        emit({"t": "card_start", "sid": sid})
            elif et == "content_block_delta":
                idx = ev.get("index")
                d = ev.get("delta", {})
                if d.get("type") == "text_delta":
                    mgr.turn_state["has_output"] = True
                    emit({"t": "text", "d": d.get("text", "")})
                elif d.get("type") == "input_json_delta":
                    tool_inputs[idx] = tool_inputs.get(idx, "") + d.get("partial_json", "")
                    if idx in card_sids:
                        now = time.time()
                        # throttled: an untouched cap here means a finished turn replays its
                        # *entire* delta history in one burst on the next "tail -F" from byte 0
                        # (every widget reopen), which used to flood the chat list with enough
                        # resize/displaced animations in a few ms to visibly tear the layout.
                        if now - card_last_emit.get(idx, 0) >= 0.12:
                            partial = _partial_json(tool_inputs[idx])
                            if partial is not None:
                                emit({"t": "card_update", "sid": card_sids[idx], "input": partial})
                                card_last_emit[idx] = now
            elif et == "content_block_stop":
                idx = ev.get("index")
                if idx in tool_names:
                    name = tool_names.pop(idx, "tool")
                    raw = tool_inputs.pop(idx, "")
                    try:
                        inp = json.loads(raw) if raw else {}
                    except json.JSONDecodeError:
                        inp = {"_raw": raw}
                    if name == "AskUserQuestion":
                        emit({"t": "ask", "kind": "question",
                              "questions": inp.get("questions", [])})
                    elif name == "ExitPlanMode":
                        emit({"t": "ask", "kind": "plan",
                              "plan": inp.get("plan", "")})
                    elif idx in card_sids:
                        emit({"t": "card_update", "sid": card_sids.pop(idx), "input": inp})
                        card_last_emit.pop(idx, None)
                    elif name == "update_card" or name.endswith("__update_card"):
                        # rendered straight from the call args, same as show_card — no need to
                        # wait on the tool_result round-trip, the patch is already known here
                        emit({"t": "card_patch", "card_id": inp.get("card_id", ""), "patch": inp.get("patch", {})})
                    else:
                        summary = (inp.get("command") or inp.get("file_path") or
                                   inp.get("pattern") or inp.get("query") or
                                   inp.get("url") or "")
                        emit({"t": "tool", "name": name, "input": inp, "summary": summary})

        elif t == "assistant":
            msg = o.get("message", {})
            for block in msg.get("content", []) or []:
                if isinstance(block, dict) and block.get("type") == "tool_use":
                    bn = block.get("name", "")
                    if (bn in ("AskUserQuestion", "ExitPlanMode") or bn == "show_card" or bn.endswith("__show_card")
                            or bn == "update_card" or bn.endswith("__update_card")):
                        ask_ids.add(block.get("id"))

        elif t == "user":
            msg = o.get("message", {})
            content = msg.get("content", [])
            if isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "tool_result":
                        tool_id = block.get("tool_use_id")
                        if tool_id in card_sid_by_tool_id:
                            c = block.get("content", "")
                            if isinstance(c, list):
                                c = "".join(b.get("text", "") for b in c if isinstance(b, dict))
                            try:
                                result = json.loads(c)
                            except (json.JSONDecodeError, TypeError):
                                result = {}
                            # the chat card is rendered from the tool *call* args, which never
                            # contain a pin_id (that's assigned server-side); relay it back from
                            # the tool *result* so the chat-side pin icon reflects reality instead
                            # of always looking unpinned even when show_card(pinned=true) worked.
                            if isinstance(result, dict) and "pin_id" in result:
                                emit({"t": "card_pin", "sid": card_sid_by_tool_id[tool_id],
                                      "pin_id": result["pin_id"]})
                        if tool_id in ask_ids:
                            continue
                        c = block.get("content", "")
                        if isinstance(c, list):
                            c = "".join(b.get("text", "") for b in c if isinstance(b, dict))
                        emit({"t": "tool_result", "d": str(c)[:4000],
                              "ok": not block.get("is_error", False)})

        elif t == "rate_limit_event":
            # carries an exact resetsAt epoch straight from Anthropic's
            # rate-limit headers — used on a hard failure below to auto-disable
            # the right account for the right amount of time, not a guess
            mgr.turn_state["rl"] = o.get("rate_limit_info", {}) or {}

        elif t == "result":
            if o.get("is_error"):
                if not mgr.turn_state["has_output"] and mgr.has_more_candidates():
                    mgr.fallback(str(o.get("result", "error"))[:200])
                    return
                emit({"t": "error", "d": str(o.get("result", "error"))[:400]})
            usage = o.get("usage", {}) or {}
            emit({"t": "meta",
                  "model": model_name,
                  "in": usage.get("input_tokens", 0),
                  "out": usage.get("output_tokens", 0),
                  "ms": o.get("duration_ms", 0),
                  "cost": o.get("total_cost_usd", 0)})
            end_turn()

    code = proc.poll()
    if code not in (0, None):
        err = (proc.stderr.read() if proc.stderr else "") or ""
        err = err.strip()
        if not mgr.turn_state["has_output"] and mgr.has_more_candidates() and mgr.last_text is not None:
            mgr.fallback(err[:200] or "agent exited")
            return
        emit({"t": "error", "d": (err[:400] or "agent exited")})
        end_turn()


class Mgr:
    """Owns the active backend (claude subprocess or opencode one-shot) and
    falls over to the next non-disabled registry entry — same chain and same
    rate-limit auto-disable behavior as the terminal `claude` wrapper — on a
    hard failure that happened before any real output was produced. Without
    this, a rate-limited or unreachable account left the widget dead silent
    with no way to recover short of the user manually switching accounts."""

    def __init__(self, mode, model_arg, resume_id, auth, cwd):
        self.mode = mode
        self.model_arg = model_arg
        self.resume_id = resume_id
        self.cwd = cwd
        self.candidates, self.reg = build_candidates(auth)
        self.idx = 0
        self.lock = threading.Lock()
        self.proc = None
        self.kind = None
        self.entry = None
        self.model = ""
        self.turn_state = {"has_output": False, "rl": None}
        self.last_text = None
        self.last_silent = False
        self.last_iid = ""

    def has_more_candidates(self):
        return self.idx + 1 < len(self.candidates)

    def current_id(self):
        return self.candidates[self.idx] if self.idx < len(self.candidates) else ""

    def build_and_spawn(self, use_resume):
        cid = self.current_id()
        kind, akey, abase, amodel, entry = resolve_auth_for_id(cid, self.reg, set_active=True)
        self.kind = kind
        self.entry = entry

        if kind == "opencode":
            self.proc = None
            self.model = (entry or {}).get("model", "")
            emit({"t": "session", "id": "", "model": f"opencode/{self.model}" if self.model else "opencode"})
            emit({"t": "ready"})
            return

        env = os.environ.copy()
        env["CLAUDE_RICE_IGNORE"] = "1"
        env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        env["QS_AGENT_MODE"] = self.mode
        if self.mode == "resident":
            env["QS_AGENT_UNATTENDED"] = "1"
        if kind == "key":
            if akey:
                env["ANTHROPIC_API_KEY"] = akey
            if abase:
                env["ANTHROPIC_BASE_URL"] = abase
        else:
            env.pop("ANTHROPIC_API_KEY", None)
            env.pop("ANTHROPIC_BASE_URL", None)

        model = self.model_arg.strip() or os.environ.get("ANTHROPIC_MODEL", "").strip() \
            or amodel or "claude-sonnet-4-6"
        self.model = model
        _ml = model.lower()
        is_glm = _ml.startswith("glm") or _ml in ("air", "glm-air", "glm-4.5-air")
        identity = (f"You are GLM (model {model}, a large language model by Zhipu AI / Z.ai)"
                    if is_glm else "You are Claude")
        sys_prompt = (SYSTEM.replace("You are Claude", identity, 1)
                      + (RESIDENT_EXTRA if self.mode == "resident" else "")
                      + mode_note_for(self.mode) + MAILBOX_NOTE + MUSIC_NOTE + GMAIL_NOTE
                      + memory_block())
        cmd = [find_claude(), "-p",
               "--input-format", "stream-json", "--output-format", "stream-json",
               "--verbose", "--include-partial-messages",
               "--append-system-prompt", sys_prompt]
        if os.path.exists(MCP_CONFIG):
            cmd += ["--mcp-config", MCP_CONFIG, "--strict-mcp-config"]
        cmd += ["--model", model]
        if use_resume and self.resume_id:
            cmd += ["--resume", self.resume_id]
        if self.mode in ("auto", "resident"):
            cmd += ["--dangerously-skip-permissions"]
        elif self.mode == "plan":
            cmd += ["--permission-mode", "plan"]
        else:
            cmd += ["--allowedTools"] + READ_TOOLS + ASK_GATED_TOOLS

        try:
            self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                          text=True, bufsize=1, env=env, cwd=self.cwd)
        except FileNotFoundError:
            self.proc = None
            self.fallback("claude CLI not found")
            return

        threading.Thread(target=reader, args=(self.proc, self), daemon=True).start()
        emit({"t": "ready"})

    def send(self, text, silent, iid):
        self.last_text = text
        self.last_silent = silent
        self.last_iid = iid
        self.turn_state["has_output"] = False
        self.turn_state["rl"] = None

        if self.kind == "opencode":
            threading.Thread(target=self._run_opencode_turn, args=(text,), daemon=True).start()
            return

        msg = {"type": "user", "message": {"role": "user",
               "content": [{"type": "text", "text": text}]}}
        try:
            if self.proc is None or self.proc.poll() is not None or self.proc.stdin is None:
                self.fallback("process not running")
                return
            self.proc.stdin.write(json.dumps(msg) + "\n")
            self.proc.stdin.flush()
        except (BrokenPipeError, ValueError):
            self.fallback("pipe closed")

    def _run_opencode_turn(self, text):
        ok, result = run_opencode_once(self.entry, text)
        if ok:
            self.turn_state["has_output"] = True
            emit({"t": "text", "d": result})
            emit({"t": "meta", "model": f"opencode/{self.model}" if self.model else "opencode",
                  "in": 0, "out": 0, "ms": 0, "cost": 0})
            end_turn()
        else:
            self.fallback(result)

    def fallback(self, reason):
        with self.lock:
            rl = self.turn_state.get("rl")
            if rl and self.kind == "account":
                status = rl.get("status", "")
                resets = rl.get("resetsAt")
                util = rl.get("utilization", 0) or 0
                hard = status not in ("allowed", "allowed_warning") or util >= 1
                if hard and resets:
                    auto_disable(self.current_id(), resets, rl.get("rateLimitType", "limit"))
            old_proc = self.proc
            if not self.has_more_candidates():
                emit({"t": "error", "d": f"all backends unavailable ({reason})"})
                end_turn()
                return
            self.idx += 1

        try:
            if old_proc:
                old_proc.terminate()
        except Exception:
            pass
        emit({"t": "fallback", "d": f"switched backend (previous unavailable: {reason})"})
        self.build_and_spawn(use_resume=False)
        if self.last_text is not None:
            self.send(self.last_text, self.last_silent, self.last_iid)


def main():
    global g_silent, g_iid
    mode = sys.argv[1] if len(sys.argv) > 1 else "ask"
    model_arg = sys.argv[2] if len(sys.argv) > 2 else ""
    resume = sys.argv[3] if len(sys.argv) > 3 else ""
    auth = sys.argv[4] if len(sys.argv) > 4 else "auto"
    workdir = sys.argv[5] if len(sys.argv) > 5 else ""

    cwd = os.path.expanduser(workdir.strip()) if workdir.strip() else os.path.expanduser("~")
    if not os.path.isdir(cwd):
        cwd = os.path.expanduser("~")

    mgr = Mgr(mode, model_arg, resume, auth, cwd)
    mgr.build_and_spawn(use_resume=True)

    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            cmd_obj = json.loads(raw)
        except json.JSONDecodeError:
            continue
        text = cmd_obj.get("text", "")
        context = cmd_obj.get("context", "")
        if context:
            text = context + "\n\n---\n\n" + text
        if not text:
            continue
        if cmd_obj.get("silent"):
            g_silent = True
            g_iid = cmd_obj.get("iid", "")
            text = SILENT_NOTE + text
        else:
            g_silent = False
            g_iid = ""
        mgr.send(text, bool(cmd_obj.get("silent")), cmd_obj.get("iid", ""))

    try:
        if mgr.proc:
            mgr.proc.terminate()
    except Exception:
        pass


if __name__ == "__main__":
    main()
