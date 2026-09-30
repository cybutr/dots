# Claude resident agent — architecture + session log

## How it integrates

**Three long-lived daemons** (autostarted in `exec.conf`):

- `context_daemon.sh` → runs `context.py` on triggers (battery/network/calendar files,
  pactl sink/source events, 30s failsafe) → writes `/tmp/qs_context.json`
  (system stats, mic, proc, schedule, workspaces, focus).
- `claude_daemon.py` → owns the actual `claude` CLI subprocess (via `agent.py`).
  Talks to the QML widget over `/tmp/qs_claude_in` (FIFO in) and
  `/tmp/qs_claude_stream` (newline-JSON transcript out) + `/tmp/qs_claude_status`
  (idle/busy). Survives the widget closing/reopening — the widget just tails the
  stream file. Self-dedups via `/tmp/qs_claude_daemon.pid`.
- `claude_resident.py` → polls context every 30s, fires proactive nudges
  (battery low, event soon, task overdue, mic left on) and a once-daily morning
  brief, surfaced via notification + the bar's status dot
  (`/tmp/qs_resident_suggestion`).

**`agent.py`** is the actual subprocess wrapper around the `claude` CLI
(`-p --input-format stream-json --output-format stream-json --verbose
--include-partial-messages`), one per chat session. Modes: `ask` (read-only
tools), `plan`, `auto` (full actuator access, `--dangerously-skip-permissions`),
`resident` (same as auto + `QS_AGENT_UNATTENDED=1`, used for one-shot agentic
runs kicked off by the resident daemon rather than the chat widget).

**`qs_mcp.py`** — zero-dependency MCP server (stdio JSON-RPC) exposing
`qs-desktop` tools. Current roster:

- Read-only: `get_system_state`, `list_events`, `list_tasks`, `focus_stats`,
  `read_quickshell_logs`, `get_workspaces`, `get_music`, `recall`.
- Actuators (AUTO/resident only): `complete_task`, `add_task`, `open_widget`,
  `hypr`, `notify`, `set_volume`, `toggle_mute`, `mic_mute`, `power_profile`,
  `remember`, `suggest`.
- Card tool: `show_card` — renders a structured card into the chat (inline) or
  as a pinned panel card. Supports 7 block types: `rows` (2-col label/value
  grid with live values), `gauges` (circular ring dials), `bars` (horizontal
  progress bars), `pills` (segmented selector), `buttons` (action row),
  `list`, `text`. Blocks with `metric:` poll the metrics bus (~4s); blocks with
  `watch:` update instantly via inotify on file change. Known watch files —
  always use these instead of polling/metric for the listed values:
  - `watch: /tmp/qs_volume_state` — current volume ("72%" or "muted"),
    written by `volume_listener.sh` on every PulseAudio change
  - `watch: /tmp/qs_workspaces.json` + `source: jq -r '[.[]|select(.state=="active")|.name]|first'` — active workspace
  - `watch: /tmp/qs_active_widget` — currently open widget name
  - `watch: /tmp/qs_claude_mailbox.json` — mailbox (source jq for count)
  - cpu/mem/battery/temp: use `metric:` (no watchable file exists)
  - brightness: `source: brightnessctl get` + `interval_ms: 500`
  Cards support `auto_pin: true` to immediately appear in the pinned panel.
  Button items can carry `action` (MCP tool name + args) for one-click
  actuator calls. `update_card` patches an existing card by `card_id` without
  rebuilding it.
- New this session — agentic/"lives in the PC" tools:
  - `screenshot` — grim capture (full or focused window), returned as a real
    image content block so Claude can see the screen.
  - `window_control` — list/launch/workspace/move/resize/focus/close/float/
    fullscreen/pin via hyprctl.
  - `input_control` — ydotool click/key/type/mouse-move (simulated input).
  - `file_ops` — scoped read/write/move/list, locked to `~/Documents`,
    `~/Downloads`, `~/Images`, `~/.config/hypr`.
  - `browser_tabs` / `browser_open` / `browser_switch_tab` / `browser_close_tab`
    — Vivaldi control via its CDP debug port (`localhost:9222`, already enabled
    via `--remote-debugging-port=9222` in `exec.conf`).

**Capability gate** (`cap_gate.py`) — the 4 new actuator-heavy tools
(screenshot, window_control, input_control, file_ops) are ungated in normal
AUTO chat (you're already supervising), but gated when run unattended
(`QS_AGENT_UNATTENDED=1`, i.e. resident-triggered runs): first use of each
pauses with `{"pending": true}`, fires a critical notification + bar
suggestion with a one-liner to approve (`bash approve_cap.sh <cap>`).
Approval persists in `/tmp/qs_agent_caps.json` until cleared.
`claude_resident.py` has a ready `run_agentic_task(prompt)` helper for this —
no trigger condition wired to it yet (deliberately — needs a decision on what
should actually kick off an unattended run).

**`inject_ctx.py`** — every chat message gets a short ambient snapshot
(battery/volume/mic/cpu/mem, workspaces in use, now-playing music) prepended
below a `---` separator. The system prompt explicitly tells Claude this is
silent background, never to recite/reference it unless the actual question
needs it — fixes earlier "yo" → full stats dump behavior.

**Mailbox convention (`/tmp/qs_claude_mailbox.json`, `mailbox_post`/`mailbox_read`
MCP tools)** — this is a real cross-session log, meant to be used, not just
occasionally written to by the resident. Producers now include `claude_resident.py`
(fix-resolves, morning brief, catch-up), `eco_daemon.py` (freeze events),
`smartws.py` (layout restores), `leak_reaper.py` (meaningful orphan reaps, 5+),
`device_watch.py` (bluetooth connects), `net_watch.py` (first-seen networks).
**Any Claude Code session working in this repo should do the same:**
- `mailbox_read` (for="me" or unread_only=false to see everything) early when
  starting non-trivial work here — another session or the resident may have
  left context worth knowing before you dig in.
- `mailbox_post` when you finish something another session/the resident/the
  user would want a trail of — a bug fixed, a subsystem changed, a decision
  made. Keep it to genuinely notable moments, one line is enough
  (`to: "user"` for a human-readable note, `to: "resident"` if it's something
  the ambient daemon should act on or know).
This makes `mailbox_read` a real "what's been happening on this machine"
feed across every Claude client (chat widget, resident, one-shot agent runs,
and any terminal Claude Code session) instead of a rarely-touched channel.

**Multi-account auth** — `anthropic_acct.sh` manages OAuth accounts + API keys
in `~/.config/anthropic/accounts.json`, swapping `~/.claude/.credentials.json`
on switch (`set <id>` / `cycle`, bound to `SUPER+ALT+A`). `update <id>` and
`relabel` refresh stored entries.

## Session changelog

- **Card framework** — `show_card` MCP tool + `CardRenderer.qml` shared renderer
  (used by both inline chat cards and the pinned panel). 7 block types: rows,
  gauges, bars, pills, buttons, list, text. `update_card` for surgical edits via
  `block_ops` (patch/insert/remove/replace) without rebuilding. `auto_pin: true`
  flag pins directly on creation. Block-level edit mode: click any block to select
  it, Edit pill opens an inline composer that sends the edit request back to Claude
  as a normal message. Edit composer closes on deselect or editMode toggle.
  Cards deduped by `card_id` so agent retries don't create duplicate rows.
  Double-encoded `blocks` (JSON string instead of array) normalized at both MCP
  server and client-side `card_update` handler.
- **Event-driven card values** — `gaugesBlock` and `barsBlock` gained full `watch`
  support (inotifywait watcher process + timer disabled when watch set) matching
  `rowsBlock`. All three block types now update instantly on file change with no
  polling. `volume_listener.sh` extended to write `/tmp/qs_volume_state` on every
  PulseAudio change — cards watch this instead of polling. Tool description updated
  with prescriptive watch-file table so agent always defaults to watch for
  volume/workspace/widget/mailbox without being told.
- **PinnedCards focusable** — `focusable: false` → `true` so compositor routes
  keyboard events to the pinned panel window, enabling typing in card input fields
  (secret fields, edit composers). Previously all keypresses went to the last
  focused window (usually ClaudeAsk) regardless of click target.
- **Card background opacity** — `ccard` background raised from `Qt.rgba(blue, 0.08)`
  to `Qt.rgba(base, 0.92)` so pinned cards are readable on any desktop background,
  not just dark apps. Blur-behind from Hyprland layershell already active.
- **iconMap additions** — `workspace`, `widget`, `window`, `panel`, `mail`,
  `mailbox`, `inbox`, `message` added to resolve to Nerd Font glyphs instead of
  falling back to letter badges.

- **"yo" tone fix** — `agent.py` SYSTEM prompt rewritten so the ambient context
  block is never volunteered/recited; replies match the user's message energy.
- **Agentic tool pack** — added `screenshot`, `window_control`, `input_control`,
  `file_ops` to `qs_mcp.py`, gated for unattended runs via `cap_gate.py` +
  `approve_cap.sh`. `agent.py` gained a `resident` mode that sets
  `QS_AGENT_UNATTENDED=1`. `ydotoold` installed + autostarted (`exec.conf`);
  `/dev/uinput` ACL already granted to the user.
- **Browser control** — `browser_tabs/open/switch_tab/close_tab` added, talking
  to Vivaldi's existing CDP port 9222.
- **Stop-button bug fixed** — `claude_daemon.py` now spawns `agent.py` with
  `start_new_session=True` and kills the whole process group
  (`os.killpg`) on stop/clear. Previously, terminating `agent.py` alone left
  its `claude` CLI grandchild running, so a turn kept going after pressing
  Stop, especially across widget reopen.
- **Volume button crash fixed** — root cause was `sys_waiter.sh` leaking one
  orphaned `pactl subscribe` process every ~30s poll cycle (its EXIT trap only
  killed the subshell wrapper, not the piped `pactl` inside it). Over ~80
  minutes this exhausted pipewire-pulse's client connection limit ("too many
  client application connections"), breaking `pactl`/`swayosd-client`
  system-wide. Fixed with `set -m` + process-group kill on trap. Also added a
  missing self-dedup pidfile guard to `volume_listener.sh` (it had none, unlike
  every other daemon in this stack), since duplicate instances each hold their
  own `pactl subscribe` connection too.
- **Account-switch 401 fixed** — `anthropic_acct.sh` was restoring a frozen
  credential snapshot on every switch, clobbering tokens the `claude` CLI had
  auto-refreshed during use. Added `snapshot_current()`, called before every
  swap (`set_active`/`cycle`), which persists whatever's currently on disk back
  into the account being left. (Introduced and immediately fixed a `set -e`
  footgun in that same function — bare `return` inherited a failing test's
  exit code and silently killed the script, which is why `SUPER+ALT+A` worked
  once then stopped responding.)
- **Browser/window control hardened** — `browser_open`'s `/json/new` CDP call was
  using GET, which modern Vivaldi/Chrome rejects with 405 (CDP now requires
  PUT). Fixed, and `browser_open` now auto-launches Vivaldi and retries for up
  to 10s if the CDP port isn't up yet, instead of erroring and making the
  agent launch it manually then retry itself. Added `app_open` — unified
  focus-or-launch for any app (matches window class/title/initialClass, falls
  back to `hyprctl dispatch exec`) so launching/switching to an app is one
  tool call instead of list+launch+focus. `screenshot` mode=window now takes
  a `target` (class/title substring) to capture a specific app's window
  geometry directly, rather than defaulting to whatever's currently focused
  — which during a chat turn is usually the agent widget itself, making the
  screenshot useless.
- **Action audit log + new actuators** — every actuator call now appended to
  `/tmp/qs_agent_actions.log` (ts/tool/args/ok/error), logged centrally in
  `qs_mcp.py`'s `tools/call` dispatch (`ACTUATORS` set + `_log_action`).
  Needed before any unattended trigger gets wired to `run_agentic_task` —
  otherwise a bad resident-triggered run is undebuggable. Added 4 tools:
  `browser_eval` (CDP Runtime.evaluate over a raw websocket, hand-rolled
  RFC6455 client since the MCP server stays zero-dependency — lets the agent
  actually read page content instead of just opening tabs blind);
  `clipboard_control` (wl-copy/wl-paste/cliphist); `process_control`
  (ps list / kill by pid or pkill -f by name); `notification_read`. All new
  gated actuators (`clipboard_control`, `process_control`) added to
  `cap_gate.py`'s `CAPS` and `approve_cap.sh`'s whitelist.
- **Notification source correction** — confirmed swaync is `pkill -x`'d at
  Hyprland startup (`exec.conf:28`) and is NOT the active notification
  daemon; quickshell's own `NotificationServer` in `Main.qml` is. Since that
  history lived only in an in-process QML ListModel with no file output,
  added `writeNotificationSnapshot()` (called on every `onNotification`) that
  writes the last 20 to `/tmp/qs_notifications.json` via the same
  `python3 -c "...open(sys.argv[1],'w').write(sys.argv[2])"` argv-safe-write
  pattern already used in `ScratchpadHost.qml`/`GuidePopup.qml`, so
  `notification_read` has something to read.
- **Resident: background launches + gated agentic tasks + real triggers wired**
  — addresses the long-standing "no trigger wired to `run_agentic_task`" gap.
  - `qs_mcp.py` gained `_launch()`/`_current_window_addr()`: `window_control`
    launch and `app_open` now take `background=true`, which dispatches via
    hyprctl's `[silent]` exec flag and snapshots+restores the previously
    focused window ~1.5s later, so an agent-opened app doesn't yank focus or
    workspace away from whatever the user's doing — same idea as
    `matugen_reload.sh`'s silent-workspace vivaldi relaunch. `browser_open`'s
    auto-launch-if-not-running path now goes through this too.
    `agent.py`'s SYSTEM prompt documents `background` and gained a
    `RESIDENT_EXTRA` block (appended only when `mode == "resident"`) telling
    the agent to default to `background=true` and one-line replies, since a
    resident-triggered run has no user watching a chat transcript.
  - `claude_resident.py` gained a **task-approval gate**, separate from
    `cap_gate`'s per-actuator gate: `request_task_approval(key, prompt,
    summary, notified)` persists the prompt to
    `/tmp/qs_resident_pending_tasks.json` and sends a notification with a
    one-liner (`bash approve_task.sh <key>`) instead of firing
    `run_agentic_task` blind. New `approve_task.sh` + `--approve-task <key>`
    CLI mode on `claude_resident.py` runs the approved prompt and notifies
    the result. This is the missing piece for "resident does things
    unattended" — every agentic run now needs an explicit click first.
  - Wired one concrete trigger end-to-end: `detect()` now reads
    `/tmp/qs_notifications.json` (the file `Main.qml` just started writing),
    tracks `last_notif_uid` in resident state, and for any new notification
    not from Claude itself, proposes (via the approval gate above) an
    agentic task that reads the notification and reports back whether it
    needs a reaction — closing the loop on the new `notification_read` tool.
  - Battery handling de-duplicated against `BatteryAlarm.qml`'s native
    30/20/10% banners: `BATTERY_LOW` threshold moved from 15% to 20% to line
    up with its level-1 banner, and `surface()` gained `also_notify=False`
    (used for `battery_low`) so resident still updates the bar's "needs you"
    pill + one-click power-saver action without firing a second, redundant
    OS notification on top of the already-visible banner.
  - **Not done yet**: focus/thrash-detection trigger (rapid app-switching via
    `focus_daemon.py`'s `focus_minutes` sqlite table) — flagged as a good
    next candidate but not wired this round, to avoid shipping an untested
    DB-query-based trigger blind.
- **FreeModel proxy dead** — `cc.freemodel.dev` now 403s
  ("This service is restricted to the official Claude Code client") even for
  the real `claude` CLI and raw curl with identical headers — confirmed
  server-side block, not fixable from this end. Active account switched to
  `kouklikkarel0` (Pro) so the widget doesn't default to a dead proxy. Entry
  left in `accounts.json` in case the block lifts later.

## Known follow-ups (not yet decided/built)

- No trigger wired to `run_agentic_task` yet — needs a decision on what
  unattended condition should actually kick off a resident agentic run
  (flow/thrash detection via `focus_daemon.py` was discussed as one option).
- `window_control`/`input_control` are coarse — no fine-grained drag, no
  multi-monitor-aware coordinates beyond what hyprctl/ydotool give natively.
