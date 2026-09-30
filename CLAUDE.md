# Hyprland + Quickshell Config — Reference

## Stack

- **Hyprland** 0.54.3 — tiling WM, config at `hyprland.conf` + `exec.conf`
- **Quickshell-git** 0.2.0 — QML shell framework, three separate processes
- **matugen** — wallpaper-derived color system, colors written to `qs_colors.json`
- **awww** — wallpaper daemon (live wallpapers via mpvpaper for video)
- **swayosd** — volume/brightness OSD
- **swaync** — notification daemon
- **rofi** — app launcher + clipboard
- **hypridle** — idle management

---

## Quickshell Processes (3 separate instances)

| Process | Entry point | Purpose |
|---|---|---|
| Main | `quickshell/Main.qml` | All popup widgets (single window, overlay layer) |
| TopBar | `quickshell/TopBar.qml` | Always-visible top bar (multi-monitor via `Variants`) |
| BatteryAlarm | `quickshell/BatteryAlarm.qml` | Battery low alert |

**Restart quickshell:** `pkill -f "quickshell.*Main"` — user runs `! pkill -f "quickshell.*Main"` in Claude chat due to sandbox. All three are auto-restarted by `qs_manager.sh` watchdog on next invocation.

**Logs:** `/run/user/1000/quickshell/by-id/*/log.qslog` — check here for QML errors before debugging blind.

---

## IPC Mechanism

All widget switching goes through `/tmp/qs_widget_state`:

1. Shell script writes `widgetname` or `widgetname:arg` to `/tmp/qs_widget_state`
2. `inotifywait` in `Main.qml` detects the write
3. `ipcPoller` reads the file, calls `switchWidget(cmd, arg)`
4. `switchWidget` uses `WindowRegistry.js` to get dimensions, loads the QML component into `StackView`

Current active widget tracked in `/tmp/qs_active_widget`.

**Entry point for IPC:** `scripts/qs_manager.sh` — always use this, never write to the IPC file directly from keybindings except in special cases.

---

## Widget Registry (`WindowRegistry.js`)

All widget dimensions and component paths defined in `getLayout()`:

| Widget | Size | Position | Component |
|---|---|---|---|
| battery | 480×760 | right edge, 70px from top | `battery/BatteryPopup.qml` |
| volume | 480×760 | right edge, 70px from top | `volume/VolumePopup.qml` |
| notifications | 480×850 | right edge, 70px from top | `notifications/NotificationPopup.qml` |
| calendar | 1450×750 | centered horizontal, 70px top | `calendar/CalendarPopup.qml` |
| music | 700×620 | left edge 12px, 70px top | `music/MusicPopup.qml` |
| network | 900×700 | right edge, 70px top | `network/NetworkPopup.qml` |
| stewart | 800×600 | centered both | `stewart/stewart.qml` |
| monitors | 850×580 | centered both | `monitors/MonitorPopup.qml` |
| focustime | 900×720 | centered both | `focustime/FocusTimePopup.qml` |
| guide | 1200×750 | centered both | `guide/GuidePopup.qml` |
| wallpaper | full width × 650 | full width, centered vertical | `wallpaper/WallpaperPicker.qml` |
| workspaces | full screen | 0,0 | `WorkspaceOverview.qml` |
| power | full screen | 0,0 | `power/PowerMenu.qml` |
| hidden | 1×1 | off-screen | — |

**To add a new widget:** add entry to `getLayout()` in `WindowRegistry.js`, create the QML component, done.

---

## Color System

**`MatugenColors.qml`** — loads colors from `qs_colors.json` (matugen output). Falls back to Catppuccin Mocha hardcoded defaults if file missing.

Available colors: `base`, `mantle`, `crust`, `text`, `subtext0`, `subtext1`, `surface0`–`2`, `overlay0`–`2`, `blue`, `sapphire`, `peach`, `green`, `red`, `mauve`, `pink`, `yellow`, `maroon`, `teal`.

**Critical gotcha:** matugen derives colors from the current wallpaper. `yellow`, `blue`, `mauve` etc. can all pull amber/warm tones on warm-palette wallpapers. **Never rely on matugen color names for semantic meaning in glows/accents.** Use fixed hex values (`#b4befe`, `#89dceb`, `#fab387`, `#f38ba8`) when visual distinction matters.

Usage in QML:
```qml
MatugenColors { id: _theme }
readonly property color base: _theme.base
```

Colors hot-reload via 1-second timer polling `qs_colors.json`.

---

## Scaling System

**`Scaler.qml`** — responsive scaling based on screen width.

- Base formula: `mw / 1920.0` with power curves (≤1920: `pow(r, 0.85)`, >1920: `pow(r, 0.5)`)
- User override via `settings.json` → `uiScale` (default 1.0)
- Scale factor hot-reloads via `inotifywait` on `settings.json`

Usage:
```qml
Scaler { id: scaler; currentWidth: Screen.width }
function s(val) { return scaler.s(val) }
// then use root.s(48) everywhere instead of hardcoded pixels
```

---

## Settings (`settings.json`)

```json
{
  "uiScale": 1,
  "openGuideAtStartup": true,
  "wallpaperDir": "/home/czeddaru/Wallpapers",
  "language": ""
}
```

Hot-reloads via `inotifywait` in both `Main.qml` and `Scaler.qml`.

---

## Top Bar (`TopBar.qml`)

Multi-monitor: uses `Variants { model: Quickshell.screens }` — one bar instance per screen.

**Left side:** Help (guide), Search (rofi), Notifications (swaync), Workspace Overview, Workspace pills, Media player
**Center:** Clock + date (clicks → calendar), Weather (matugen-tinted icon)
**Right side:** System tray, KB layout, WiFi/Ethernet, Bluetooth (hidden on desktop), Volume, Battery/Power button

Desktop detection: checks `/sys/class/power_supply/BAT*` — desktop mode hides bluetooth, shows ethernet, shows power icon instead of battery %.

Data sources:
- Workspaces: `workspaces.sh` → `/tmp/qs_workspaces.json` → `inotifywait` watcher
- Music: MPRIS via `music_info.sh`, DBus signal watcher for instant updates
- System info: `sys_info.sh` → `sys_waiter.sh` (event-driven, not polling)
- Weather: `calendar/weather.sh` every 150 seconds

---

## Key Keybindings

| Key | Action |
|---|---|
| `SUPER+SHIFT+E` | Toggle power menu |
| `SUPER+SHIFT+W` | Toggle workspace overview |
| `SUPER+SHIFT+X` | Toggle calendar |
| `SUPER+SHIFT+T` | Toggle focus time |
| `SUPER+SHIFT+V` | Toggle volume popup |
| `SUPER+SHIFT+H` | Toggle guide |
| `SUPER+SHIFT+M` | Toggle monitors |
| `SUPER+SHIFT+A` | Toggle swaync notification center |
| `SUPER+M` | Toggle music popup |
| `SUPER+B` | Toggle battery popup |
| `SUPER+N` | Toggle network popup |
| `SUPER+W` | Toggle wallpaper picker |
| `SUPER+A` | Rofi app launcher |
| `SUPER+V` | Rofi clipboard |
| `ALT+TAB` | ALT+TAB workspace switcher |
| `SUPER+1-0` | Switch workspace |
| `SUPER+L` | Lock screen |

---

## ALT+TAB System

Three-part system:
1. `alttab.sh` — opens `workspaces` widget, enters `alttab` submap, launches `alttab_monitor.py` via `setsid sg input -c ...`
2. `alttab_monitor.py` — waits for ALT key release (uses `evdev.active_keys()` check at startup to handle already-released ALT), then writes `confirm` to `/tmp/qs_alttab_nav`
3. `WorkspaceOverview.qml` — reads `/tmp/qs_alttab_nav` via inotifywait, handles `next`/`confirm`/`close`

**Navigation:** `ALT+TAB` = next, `Enter` = confirm, `Escape` = close. Arrow keys supported in overview.

**Permission requirement:** `alttab_monitor.py` needs input group access → run via `sg input -c "python3 ..."`.

---

## Power Menu (`power/PowerMenu.qml`)

Full-screen overlay. Hold-to-confirm mechanic with wave fill animation.

Buttons (left to right):
| Action | Hold time | Glow hex |
|---|---|---|
| LOCK | ~0.55s | `#b4befe` (lavender) |
| SLEEP | ~0.83s | `#89dceb` (cyan) |
| REBOOT | ~1.38s | `#fab387` (peach) |
| SHUTDOWN | ~1.93s | `#f38ba8` (pink/red) |

Commands: lock = `bash ~/.config/hypr/scripts/lock.sh`, sleep adds `& systemctl suspend`, reboot = `systemctl reboot`, shutdown = `systemctl poweroff -i`.

**Visual notes:**
- Glow colors are fixed hex (NOT matugen) — intentional, ensures visual distinction regardless of wallpaper
- Border overlay Rectangle must be declared AFTER Canvas child — otherwise canvas renders on top of border
- `active` state for glow/border uses `fillLevel > 0.01` not just `containsMouse` — prevents glow disappearing on fill completion when cursor hover briefly resets
- `gc` is a reserved JS/QML garbage collector name — property is named `glow`, not `gc`
- Uses `Quickshell.execDetached` with 400ms exit timer to allow fade-out animation before running command

---

## Scripts Reference

| Script | Purpose |
|---|---|
| `qs_manager.sh` | Main IPC gateway — open/close/toggle widgets, workspace switching, zombie watchdog |
| `init.sh` | Startup initialization |
| `lock.sh` | Lock screen (hyprlock) |
| `alttab.sh` | Launch ALT+TAB session |
| `alttab_monitor.py` | Detect ALT key release via evdev |
| `screenshot.sh` | Screenshots (region/full/edit modes) |
| `settings_watcher.sh` | Watch settings.json, fire downstream reloads |
| `volume_listener.sh` | Volume change listener |
| `ws_thumb_daemon.sh` / `ws_thumb_interval.sh` | Workspace thumbnail generation |
| `open_on_workspace.sh` | Open app on specific workspace |
| `power-profiles.sh` | Power profile switching |
| `rofi_show.sh` / `rofi_clipboard.sh` | Rofi launcher wrappers |
| `vivaldi_set_bg.py` | Set Vivaldi browser background |

Quickshell-internal scripts in `scripts/quickshell/`:
| Script | Purpose |
|---|---|
| `sys_info.sh` | JSON: wifi, bluetooth, audio, battery, keyboard layout |
| `sys_waiter.sh` | Event-driven wait before next sys_info poll |
| `workspaces.sh` | JSON workspace list → `/tmp/qs_workspaces.json` |
| `music/music_info.sh` | MPRIS metadata → JSON |
| `calendar/weather.sh` | Weather data (wttr.in) |
| `wallpaper/matugen_reload.sh` | Run matugen on new wallpaper, update `qs_colors.json` |

---

## Autostart (exec.conf)

Services: `libinput-gestures`, `awww-daemon`, `hypridle`, `playerctld`, `swayosd-server`, `easyeffects`, `cliphist`

Scripts: `init.sh`, `ws_thumb_daemon.sh`, `ws_thumb_interval.sh`, `settings_watcher.sh`, `volume_listener.sh`

Quickshell: `Main.qml`, `TopBar.qml`, `BatteryAlarm.qml`, `focus_daemon.py`

Startup: workspace 1 gets Vivaldi, special workspace `magic` gets kitty silently.

---

## Session Additions (2026-09) — TopBar Rice Overhaul, Eco Mode, Perf Fixes

Large multi-agent session added a lot of subsystems on top of the base rice
described above. This section is the index — read it before grepping,
before spawning a research agent, before re-deriving anything below by
reading code cold. If `graphify-out/graph.json` exists, query it first for
structural questions; this section is for *what exists and why*, the graph
is for *how files reference each other*.

### TopBar.qml — Hover Card System

Every status pill (weather, clock, media, workspaces, stats chips, volume,
battery, wifi, bluetooth, Claude) has a hover card that grows flush out of
its pill. Shared component: `component HoverCard: Rectangle { ... }`
declared inline near the top of `barRow` in TopBar.qml. Pattern per card
(copy an existing one, e.g. `volTip`/`batTip`, rather than reinventing):

- Reparented onto `centerBox`/`sysCapsule` (its real visual ancestor) via
  `parent: centerBox`, positioned with plain reactive property arithmetic
  (`x: rightLayout.x - centerBox.x + sysCapsule.x`) — **never `mapToItem`
  for a live binding**, it freezes at a stale value after first layout and
  never updates again.
- `hoverConfirmed` (1s open delay) + `cardKeep` (`isHovered || card.cardHovered`)
  + a 200ms close-grace Timer, so moving the pointer from the pill onto the
  card itself doesn't close it. `HoverHandler { enabled: pill.hoverConfirmed }`
  on the card itself feeds `cardHovered`.
- Every card's Rectangle/Region must be added to the bar's input mask near
  the top of the file (`Region { item: xTip.visible && xBox.hoverConfirmed ? xTip : null }`)
  or the pointer literally cannot reach it — this was the root cause of
  multiple "card won't show/stay open" bugs this session.
- Style: matches its parent pill's fill/border/radius (`barWindow.cardFill`,
  ambient-cycling border via `barWindow.ambientBreath(phase)` with a unique
  phase per card), flush square top corners + a thin top highlight line,
  corner-squaring on the source pill/capsule timed to `hoverConfirmed` (not
  raw hover), `clip: true`, all text elided.
- Content is per-card: weather (`weatherTip`) gets full forecast + hourly +
  5-day; clock/date (`clockTip`) gets today's real agenda from
  `calendar/schedule/schedule_manager.sh` (NOT the dead
  `/tmp/qs_current_event.json`/`barWindow.currentEventData` pipeline — that
  feed is empty, don't use it for anything new); media, workspaces, stats,
  volume, battery, wifi, bluetooth all have their own enriched cards with
  live 1s polling while open and real interactive controls (sliders,
  per-app volume mixer, device switching, click-to-focus/connect/disconnect).
- Claude pill has its own card too (nudge + history + run/dismiss), separate
  from the resident card popup below.

### TopBar.qml — Pill Background Effects

Ambient/reactive backgrounds drawn *behind* a pill's text/icons (declared
before the content Row, `z` below it), each independently mode-gated.
Settings category "PILL BACKGROUNDS" in the Guide: a master
`topBarPillBgMaster` (always/occasional/never) plus one per-effect mode key
each also always/occasional/never, default occasional:

| Effect | Setting key | Where |
|---|---|---|
| Battery liquid fill | `topBarBatteryLiquidMode` | battery pill |
| Volume fill | `topBarVolumeFillMode` | volume pill |
| Sky (time-of-day/weather) | `topBarSkyMode` | clock/weather pill + card |
| Wifi radar rings | `topBarWifiRadarMode` | wifi pill |
| Bluetooth connect pulse | `topBarBtPulseMode` | bt pill |
| CPU/GPU load area fill | `topBarCpuAreaMode` | stats chips (fg sparklines removed, this replaced them) |
| Net up/down particles | `topBarNetParticlesMode` | net chip |
| Uptime constellation | `topBarUptimeStarsMode` | uptime chip |
| Workspace focused-app tint | `topBarWorkspaceTintMode` | workspace pills |
| Claude aurora | `topBarClaudeAuroraMode` | Claude pill (non-compact only — the compact dot version must NOT show it, that was the "ugly pale blob" bug) |

All of these live inside a shared clipped-rounded-corner background
component so none of them can bleed past a pill's corners (QML `clip` is
rectangular — a rounded mask needs either a Canvas clip path or an inset
safe zone; every effect here uses that shared component, don't add a new
effect that clips itself a different way).

Hidden test trigger (same file as the flourish one, extended): write a
keyword to `/tmp/qs_topbar_test_flourish` to preview any effect on demand
without waiting for real conditions: `skyfx`, `wififx`, `btfx`, `cpufx`,
`netfx`, `uptimefx`, `wsfx`, `claudefx`, plus the earlier `batteryfill`,
`volumefill`, `uptime`, `battery`, `cpu`.

### TopBar.qml — Timer Pill

Compact time-only pill (no glyph, hugs the text). State machine: idle →
running → paused, plus a "stop?" confirm state on double-click while
running (2nd click within ~3s confirms, timeout cancels). Controls:
left-click starts (idle only), double-click-then-confirm stops, right-click
pauses/resumes, mouse wheel ±1 minute, **Ctrl+wheel ±1 hour**. Ctrl+wheel
needed a workaround: the bar window never gets keyboard focus, so Wayland
reports wheel events with no modifier state regardless of what's actually
held — `scripts/ctrl_watch.py` reads the real Ctrl key state from `evdev`
directly and the bar only runs it while the pointer is over the timer pill.
State persists across bar restarts in `/tmp/qs_timer.json`
(`{state, durationSecs, endTs, remainingSecs}`), watched via the usual
inotifywait+cat idiom so all monitor instances stay in sync. Drivable/testable
via `/tmp/qs_timer_cmd`: `start`, `pause`, `resume`, `stop`, `set <minutes>`.
No hover card (removed per user request — kept intentionally minimal).
Settings: `topBarTimerEnabled`, `topBarTimerFillMode`.

### TopBar.qml — Resident Card Popup

A card drops down under the **middle (clock/weather) pill**, used by the
Claude resident and related one-off tools (screenshot answers, timer-done).
Separate from the per-pill hover cards above — this one is queue-driven,
not hover-driven, and stays up as long as the emitter wants.

- **Queue file:** `/tmp/qs_resident_cards.jsonl`, append-only JSON lines,
  capped at ~60/20 (writer/reader side respectively). Fields: `id`, `ts`,
  `title`, `body`, `icon`, `urgency` (`low`/`normal`/`high`), `hold_secs`
  (0 = stays until dismissed; otherwise auto-dismiss, roughly 60ms/char with
  an 8s floor if not specified), `actions` (list of `{label, cmd}`, run via
  `Quickshell.execDetached` then dismiss), `source`.
- **Emit a card:** `claude/resident_card.py` — importable (`emit(...)`) or
  CLI (`resident_card.py --title ... --body ... --hold N --action "label=cmd"`).
  A card emitted with an `id` that already exists replaces the old one in
  place.
- **UI:** flush under the clock pill, glows in the urgency color, scrollable
  body (Flickable) capped at ~40% screen height for long answers, a
  draining progress line for timed cards that **pauses while the pointer is
  over the card**, multiple cards queue with a `+N` badge and prev/next
  arrows, Escape/middle-click/X dismisses.
- **Wired producers:** `shot_action.py`/`shot_answer.py` (screenshot
  classify + the `SUPER+CTRL+Z` "answer this" flow — see below) emit cards
  per the `screenshotAnswerOutput` setting (card/notification/both); the
  timer pill's finish event; `claude_resident.py`'s morning brief,
  catch-up, and proactive-fix flows (see below).
- Settings category "RESIDENT CARDS": `residentCardsEnabled`,
  `residentCardMaxHeight`, `residentCardHoldMode`, `residentCardSound`,
  `screenshotAnswerOutput`.

### Claude Resident Upgrades (`claude/claude_resident.py` + new files)

Three new proactive behaviors, all going through the card queue above (and
espeak for the spoken one), all with their own on/off in the Guide
("CLAUDE RESIDENT" section):

- **Morning brief** (`residentMorningBrief`: off/text/spoken,
  `residentBriefTime` window) — fires once/day inside the window, only
  while you're at the PC. Covers weather, agenda, battery, notification
  count, pending nudges. `resident_extras.py --test-brief` dry-runs it
  (prints instead of speaking).
- **Catch-up** (`residentCatchUp`) — after 2+ minutes away (idle/lock
  tracked via the existing `/tmp/qs_pc_idle` marker), emits a "While you
  were away" card: new notifications, downloads, git changes, waiting
  Discord conversations, battery delta. Also refreshes
  `/tmp/qs_lock_brief.json` (`{ts, headline, items[]}`) continuously while
  away, which the new lock screen reads. `--test-catchup` to dry-run.
- **Proactive fixes** (`residentProactiveFixes`) — every ~10min, 6h cooldown
  per fix: full disk, leaked/hung processes, a memory hog (respects
  `HOG_NAME_BLOCKLIST`), failed systemd user units, pending package updates,
  battery health. Only ever *proposes* — clicking a card action runs
  `resident_actions.sh` (a whitelisted runner); anything needing sudo is
  copied to the clipboard instead of run. `--test-fixes` to dry-run
  (WARNING: this actually scans your real machine and will emit real cards
  for real issues found — remove test cards after if you don't want them
  sitting in the queue).

New files: `claude/resident_card.py`, `claude/resident_extras.py`,
`resident_actions.sh`.

**Mailbox is a real cross-session convention, not just a resident feature** —
`mailbox_post`/`mailbox_read` MCP tools, backed by `/tmp/qs_claude_mailbox.json`.
Any Claude Code session working in this repo: `mailbox_read` early when
starting non-trivial work, `mailbox_post` a one-liner when you finish
something worth a trail (bug fixed, subsystem changed, decision made). See
`claude/AGENT.md` for the full convention and current producer list.

### Lock Screen Revamp (`scripts/quickshell/Lock.qml`)

Full redesign: blurred/parallax wallpaper backdrop, rolling-digit clock
(reuses `RollText.qml`) + time-of-day greeting, weather chip, now-playing
card with working playerctl controls, notification/wifi/battery chips, a
Claude line read from `/tmp/qs_lock_brief.json` (fed by the catch-up
behavior above), animated password ring (per-key pulse, shake+red flash on
wrong password, success burst), caps-lock badge.

- **The actual PAM auth path is unchanged.** The old screen is kept intact
  as `LockLegacy.qml`; `lock.sh` picks new-vs-old based on a setting.
  `hypridle.conf` points at whichever `lock.sh` resolves to.
- **`bash ~/.config/hypr/scripts/lock_test.sh`** — a NON-locking preview
  (password is literally `test`), Esc-twice or 90s auto-closes. **Always
  use this for any visual iteration on the lock screen** — never test by
  actually locking the session unless you've confirmed the real auth path
  separately and are prepared to unlock for real.
- Settings category "LOCK SCREEN": style toggle (new/legacy), music,
  weather, notifications, Claude line, blur strength, parallax, ambient fx
  mode, clock size — 9 rows total.

### Smart Workspaces (`scripts/smartws.py` + `scripts/smartws.sh`)

Auto-names/icons each workspace from the dominant app category of the
windows on it (rules in `~/.config/hypr/smartws/rules.json`, hot-reloaded,
user-editable — class→category, category→{name,glyph,color}), tie-broken by
focus recency. Also layout save/restore: captures each window's command +
workspace + floating geometry + monitor, can relaunch missing apps and
reposition existing ones.

- **IPC/CLI:** `/tmp/qs_smartws_cmd` or direct CLI — `save`,
  `restore <name> [--dry-run]`, `delete`, `list`, `rename <ws> <name|->`,
  `cycle <ws>`.
- **UI:** workspace hover card header shows icon+name+cycle button; a save
  button + up to 3 saved layouts with click-to-restore/delete (double-click
  confirm pattern, 3s window).
- **Known limitation:** rename via the UI doesn't work — the bar window
  never gets keyboard focus so a text field can't take typed input. CLI/IPC
  only for renaming; the cycle button is the in-UI alternative.
- Settings: `smartWsAutoNames` (off/hover/always), `smartWsLayoutsEnabled`,
  `smartWsRestoreConfirm`.

### Eco Mode (`scripts/eco_daemon.py`)

Per-app CPU/freeze policy for unfocused apps, so background apps (Spotify
being the original complaint — was ~50% CPU doing nothing) get throttled
without ever touching anything playing audio, capturing screen/mic, or
currently focused.

- **Rules:** `~/.config/hypr/eco/rules.json`, hot-reloaded, keyed by window
  class: `never` (exempt — terminals, quickshell, Hyprland, anything
  fullscreen/urgent/focused), `throttle` (CPU-capped via systemd --user
  scope after `ecoThrottleSecs` unfocused, default 20s — Spotify's default
  policy, NEVER freeze it, audio), `freeze` (cgroup-frozen after
  `ecoFreezeSecs` hidden on another workspace, default 300s — default
  candidates: telegram, browsers when not playing audio, steam helpers).
- **Safety:** every freeze is guaranteed a thaw — on daemon exit, and a
  startup sweep thaws anything left frozen from a crash. State:
  `/tmp/qs_eco_state.json` (`[{class,pid,level,since,workspace,title,cpuQuota}]`).
- **Visible in the UI:** workspace pills carry a subtle in-theme tint for
  eco'd apps (cyan wash + slow breathing = throttled, ice-blue frost = frozen
  — NOT corner badges, that was tried and reverted per user feedback,
  "looked tacked on"). Workspace hover card shows a full eco section: per-window
  tag (`throttled · 20% cpu · 3m`, counting up live), footer with eco
  on/off + power-profile chip. Setting: `topBarEcoIndicatorMode`
  (always/occasional/never, default occasional = only show when something's
  actually eco'd).
- **Settings:** `ecoModeEnabled` (global on/off, default true),
  `ecoThrottleSecs` (20), `ecoFreezeSecs` (300).
- Complementary ananicy-cpp rules for Spotify/heavy apps exist too — see
  Performance section below, different layer (nice/ionice vs cgroup
  throttle/freeze).

### Hyprland Polish (`hyprland.conf` + `scripts/ws_accent.py` + `scripts/hypr_polish_apply.sh`)

Settings category "HYPRLAND POLISH": `hyprPolishAnimations`
(off/subtle/juicy — subtle is default, ~150-240ms with tuned beziers, juicy
adds overshoot), `hyprPolishDimInactive` (off/subtle/strong, default off),
`hyprPolishWsAccent` (off/palette/smartws), `hyprPolishWsAccentSpeed`.
`hypr_polish_apply.sh` applies presets live via `hyprctl keyword` AND
persists to `~/.config/hypr/polish.conf` (which `hyprland.conf` now
`source`s in place of its old inline animations block) — `settings_watcher.sh`
calls it on every settings save. `ws_accent.py` (single-instance, exec.conf,
~0% idle CPU) listens to Hyprland workspace-switch events and cross-fades
`general:col.active_border` per workspace over a few animated steps; it
coordinates with the pre-existing `media_border_pulse.sh` rather than
fighting it (pauses accent updates while a pulse owns the border).
Backups from install: `/tmp/hyprland.conf.polish.bak`.

### Performance / Battery Work

**Root cause of the "everything is slow" complaint:** quickshell kills only
a Process's *direct* child on restart, not any grandchildren — every
`inotifywait | while read`-style pipeline, every `while true; do ...; sleep`
loop, every `playerctl --follow`, every `dbus-monitor`, survived every
single bar/Main restart as an orphan (ppid 1). After a full session of
iterative restarts this reached **1000+ leaked processes and a load average
over 40** on a 12-thread machine, which is what actually made widget-open
feel broken, not QML/rendering itself.

- **Fix at the source:** `scripts/quickshell/lifeline.sh` — every long-lived
  `Process { command: [...] }` in every QML file (48 call sites across 15
  files, TopBar.qml has zero unwrapped ones left) now routes its command
  through this wrapper so the child dies when its quickshell parent dies.
  **Any new long-lived Process/loop/watcher added to any QML file must go
  through `lifeline.sh` too, or it will leak on every future restart.**
- **Standing safety net:** `scripts/leak_reaper.py` — single-instance,
  started from `exec.conf`, scans every 10s for orphaned (ppid==1) watcher
  processes matching known leak patterns older than 15s and kills them.
  Logs to `/tmp/qs_leak_reaper.log`. This exists *because* new leak sources
  can still slip in (every agent that touches this file should still wrap
  new Processes in lifeline.sh — the reaper is a backstop, not a license to
  skip that).
- **Manual one-shot cleanup:** `bash ~/.config/hypr/scripts/kill_orphans.sh`
  — broader pattern match, prints found/remaining counts. Use if load
  average looks wrong and you want to confirm/clear it immediately rather
  than wait for the reaper's next pass.
- **`sys_toggles.sh`'s old 5Hz polling loop** replaced by
  `sys_toggles_daemon.sh`, event-driven, only emits on change.
- **Widget open latency:** `qs_manager.sh` used to run ~17 `pgrep` scans
  *before* writing the open command (up to 3.5s under load) — its watchdog
  now runs *after* the open command and at most once/30s. `Main.qml`
  background-preloads ~15 widget components (Claude Ask and Guide first in
  the queue). `GuidePopup.qml`'s 9 tabs lazy-load
  (`Loader { active: loadedTabs[n] === true; asynchronous: true }`) so only
  the visible tab is built. **Known trap already hit once:** two different
  agents each independently added a `setResidentCardHoldMode` property to
  GuidePopup.qml — a duplicate property name makes QML refuse to
  instantiate the whole component, and Main silently shows an empty
  full-screen blur with zero error in any log (qmllint doesn't catch
  duplicate properties either). If Settings ever shows nothing but a blur
  again, check for a duplicate property/id in GuidePopup.qml first.
- **System-level tweaks:** `scripts/apply_power_tweaks.sh` — a single
  reviewable script the user runs themselves with `sudo bash`, never
  auto-executed. Covers (see the file's own comments for exact revert
  commands per block): Nvidia dynamic runtime power management (dGPU can't
  reach deep sleep otherwise; needs a reboot to take effect, verify after
  with `cat /proc/driver/nvidia/gpus/*/power | grep Runtime`), battery
  charge cap at 80% via `thinkpad_acpi` (a systemd oneshot unit), earlyoom,
  extra ananicy-cpp rules for heavy apps (`~/.config/hypr/eco/zz-heavy-apps.rules`,
  plus the earlier `zz-spotify.rules`), irqbalance. `auto-cpufreq` is
  present but **commented out by default** — it replaces
  `power-profiles-daemon`, which both eco_daemon.py and the topbar's
  power-profile chip depend on via `powerprofilesctl`; only enable it if
  the user explicitly accepts losing that integration (or wire eco
  mode/topbar to auto-cpufreq's own status output instead, not done).
  PCIe ASPM was investigated and found genuinely unsupported by this
  laptop's firmware (`-EPERM` from the kernel regardless of privilege,
  confirmed by testing, not a permissions bug) — do not re-attempt without
  `pcie_aspm=force`, which carries real PCIe/NVMe stability risk on
  hardware whose firmware didn't hand over ASPM control. vm.swappiness/
  vfs_cache_pressure were checked and are already tuned correctly by the
  `cachyos-settings` package — don't re-propose a sysctl.d override there.
- **Visual CPU indicator:** a 5th stats chip (`topBarShowQuickshellCpu`)
  shows quickshell's own combined CPU%, sourced from `perf_watch.py`
  writing `/tmp/qs_perf.json`, so the user can tell the shell itself apart
  from their apps at a glance. It also emits a throttled "Bar running hot"
  resident card if quickshell CPU or orphan count sustains high. *(Check
  whether `scripts/perf_watch.py` exists before assuming this landed —
  it was mid-build as of this writing; if missing, it needs finishing.)*

### Ydotool Coordinate Gotcha (for any future synthetic-input testing)

`ydotool mousemove --absolute -x -y` does **NOT** take raw pixel
coordinates on this system — empirically confirmed the value is exactly
**half** the real screen pixel position (`raw * 2 = actual pixel`, e.g. to
hit pixel (860,18) send `-x 430 -y 9`). Verify with `hyprctl cursorpos`
after moving, don't assume 1:1 or the 0-32767 evdev convention. Multiple
agents this session wasted significant time reporting "hover doesn't work"
when the real issue was synthetic input landing in the wrong place —
always calibrate with a 0/100/1000 probe and `hyprctl cursorpos` before
trusting a synthetic hover test's result, or hand it back to the user to
test for real.

### Common QML Gotchas — additions this session

(see the pre-existing list below for the original set; these were newly
hit/documented this session)

- **`default property alias content: row.data` silently redirects every
  CALLER-added child into the aliased target** — a component like
  `component StatChip: Rectangle { default property alias content: chipRow.data; Row { id: chipRow } }`
  will silently move any child a *caller* declares into `chipRow` (a Row)
  instead of leaving it a real sibling, even if that child was meant to be
  an overlay (e.g. a glow Rectangle with `anchors.fill: parent`). This
  creates a circular width binding (the glow sizes off the Row it just got
  stuffed into) that silently breaks rendering with zero error. Fix: build
  the overlay as a real property on the component itself, declared *inside*
  the component's own body (not by a caller) — only a caller's children get
  redirected by the alias, the component's own declared children don't.
- **`RowLayout`/`ColumnLayout` overrides ANY direct child's plain
  width/height every relayout pass** — this includes a `MouseArea` added
  as a direct child for hover detection; it silently collapses to 0x0 with
  no error, so `containsMouse` never fires no matter how long you wait.
  Fix pattern used throughout this file: wrap the real content in a plain
  `Item` (not a Layout) sized one-directionally from an inner `Row`/`Column`'s
  implicit size, put the MouseArea as a sibling of that inner
  Row/Column with `anchors.fill: parent` (parent = the outer plain Item).
  Hit twice this session (weatherBox originally, then clockBox when a
  MouseArea was added to what was still a ColumnLayout).
  self-sizing width `Math.max` shared across pills — do this per logical
  pair/group, not globally, if pills need matched widths (e.g. cpu+net
  chips one width, gpu+uptime chips another) — a single global Math.max
  across all N pills reliably breaks whichever pill has the most different
  content length.
- **Duplicate property/id names fail SILENTLY as an empty blurred window**,
  not a visible QML error — `qmllint` does not catch this either. If a
  popup shows only backdrop blur and no content, grep the file for a
  property/id declared twice before looking anywhere else.
- **ListModel roles holding a raw JS array get silently converted to a
  nested ListModel object**, not kept as a plain array — `model.someRole.length`
  and indexing silently break (reads as `undefined`/wrong object) with no
  error. Fix: store `JSON.stringify(array)` as the role (a plain string
  role works fine) and `JSON.parse()` it back out in the delegate.
- **Battery/system state defaults matter** — e.g. `property string batPercent: "100%"`
  as a placeholder before the first real poll means `batCap` briefly reads
  100 on every cold start, which can spuriously fire a "100%!" celebration
  on every single restart if you gate logic on `batCap === 100` without a
  "skip the first reading" guard (same pattern as `lastCelebratedUptimeDays === -1`
  used elsewhere for exactly this reason).
- **`uptime -p` drops any time unit that's exactly zero** (e.g. omits "0
  minutes" entirely), making the displayed component count jitter/look
  broken as time crosses a boundary — parse `/proc/uptime` directly instead
  if you need a consistent, all-units-always-present format.
- **The bar window never receives keyboard focus** — any feature needing
  real key input (rename-in-place text fields, modifier-aware scroll) needs
  a workaround: either read the key state directly from `evdev` (see
  `ctrl_watch.py` for the Ctrl+scroll pattern) or push the interaction out
  to a CLI/IPC file instead of an in-bar text field (see smart workspaces'
  rename).
- Chained shell commands in one Bash call that include a restart
  (`pkill ...; sleep 1; ...`) intermittently return a mystery exit code 144
  in this environment — always run a restart (`qsdev.sh <target>`) as its
  own separate Bash call, never chained with anything before or after it.
  A literal `pkill -f "quickshell.*TopBar"` typed directly also matches its
  own invoking shell's command line under `-f` and can kill unrelated
  things — prefer `qsdev.sh` over typing `pkill` yourself.

## Common QML Gotchas

- `gc` is reserved (garbage collector) — never use as property name
- `font.letterSpacing` not `letterSpacing` — must be under `font.*`
- Canvas children render on top of parent Rectangle's border paint — put border overlay Rectangle AFTER canvas as last child
- `containsMouse` can briefly flip false during cursor shape changes — gate persistent state on `fillLevel > 0.01` not just `containsMouse`
- `layer.enabled: true` on Rectangle with `radius: width/2` = circular crop for avatars/images
- `MultiEffect` with multiple simultaneous blur layers is unreliable in quickshell-git — use simple colored Rectangles for glows instead
- QML errors break widget loading silently from keybind perspective — always check log at `/run/user/1000/quickshell/by-id/*/log.qslog`
