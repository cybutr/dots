# Command palette backend

`palette_index.py` is the only backend the palette talks to. Every call is
`python3 palette_index.py <subcommand> ...`, JSON on stdout, nothing on stdin.

| Subcommand | Output | Cost |
|---|---|---|
| *(none)* | full index: `actions`, `history`, `context`, `boost`, `suggest` | ~1-3s (live_states + context dominate), also rewrites `~/.cache/quickshell/palette/index.json` |
| `context` | `context`, `boost`, `suggest` only | ~0.3s, reads the cached index |
| `route "<text>"` | natural-language route result (below) | ~1-1.5s first time, ~5ms cached |
| `run <key> [--dry]` | executes a routed action; `--dry` prints resolved steps instead | |
| `used <id>` | records a use in `history.json` (ignores `route.*`, `window.*`, `mailhit.*`, `tab.*`, `spotifyhit.*`) | |
| `set <key> <json> [--str]` | writes one settings.json key; `--str` stores the value as a raw string | |
| `eco <level>` | unchanged | |

## Sources (`sources.py`)

Everything that reaches outside the shell lives in `sources.py`; `palette_index.py`
imports it for the index build and actions call it directly.

| Subcommand | What it does |
|---|---|
| `tabs` | JSON list of `tab` actions (Vivaldi via CDP `:9222`, Firefox from `sessionstore-backups/recovery.jsonlz4`) |
| `vscode` | JSON list of `code` actions (recent folders/workspaces) |
| `spotify <query>` | `{query, results[], error?}`, live Web API search (reuses `spotify_peek`/`spotify_fetch` auth) |
| `play <uri>` / `playtop <query>` | play a Spotify URI / the top hit for a query |
| `tab <cdp id>` / `fftab <url> <title>` | switch to a Vivaldi tab and focus its window / focus or reopen a Firefox tab |
| `open <text>` | URL → new Vivaldi tab via `t_browser_open` (bare domains get `https://`, anything else becomes a web search) |
| `openws <spec>` | `"<app> on <N>"` / `"<app> on a new workspace"` / `"<app> @ N"` → launch on that workspace, or `open_on_workspace.sh` when the app already runs; `new` = first workspace with no windows |
| `favicons <json urls>` | background favicon fetch into `~/.cache/quickshell/palette/favicons/` (spawned by `tabs`) |
| `projects` | JSON list of `project` actions from `do` (below) |
| `project open <type> <name> <path>` | focus the VS Code window already showing that folder, else open it through `do` |
| `project run <type> <name> <path>` | run it in a `kitty --hold` window (`web` opens `index.html` instead) |
| `project new <type> [name or idea]` | scaffold through `do new`, notify with the result |
| `project peek <path>` | `{files, modified, readme, git, branch, dirty, commit, commitAgo, repoRoot, gone}` for the preview |

Notes:
- Vivaldi tabs are read with a 1.2s cap, so a wedged CDP endpoint yields no tab rows instead of stalling the build.
- Firefox can't switch to a specific tab without an extension: the active tab focuses its window,
  any other tab opens a copy (`hint` says so).
- VS Code: `User/workspaceStorage/*/workspace.json` for the flatpak, `~/.config/Code`, Code OSS and VSCodium,
  newest 40 that still exist on disk.

## Dynamic categories

| `cat` | id shape | Source | Run |
|---|---|---|---|
| `tab` | `tab.v.<cdpId>`, `tab.f.<win>.<tab>` | index build | switch/focus |
| `code` | `code.<abs path>` | index build | open in the editor that owns it |
| `spotify` | `spotifyhit.<uri>` | live, `spotify.search` | play |
| `setting` | `setting.<key>` / `setting.<key>.<option>` | settings.json | write the key |

| `project` | `project.<type>.<name>`, `project.<type>.<dir>/<name>`, `project.sc.<shortcut>`, `project.new.<type>`, `project.last.<type>`, `project.scan` | `do` state, index build | open / run / scaffold |

`tab.*`, `spotifyhit.*`, `mailhit.*`, `window.*` and `route.*` are transient: not recorded in history, not pinnable.
Extra fields: `tab` rows carry `url`, `browser`; `spotifyhit` rows carry `kind` (track/album/artist/playlist),
`sub`, `mine`, and `image` (local cached cover, previewed by the `art` stage).

Static entry points (actions.json): `spotify.search` (`live: "spotify"`), `web.open`, `ws.openapp`.

## Projects (`do`)

`do` lives in `~/.config/do` (not this repo). The CLI needs its venv: every CLI call is
`~/.config/do/.venv/bin/python ~/.config/do/do.py ...` (falls back to `python3` if the venv is missing).
Reads don't touch the CLI: `sources.py` imports the typer-free `dolib` modules (`config`, `store`, `projects`,
`detect`, `ai`, `bus`, `launcher`) under system python and opens `state.sqlite` with `?mode=ro`, reusing
`dolib.store._FRECENCY_SQL` so frecency matches `do frequent` exactly. ~0.35s for the whole category, so it's
built eagerly with the index, no live search. `DO_CONFIG_DIR` is honoured (handy for testing against a scratch copy).

Rows:
- every project `do` knows: indexed rows with a live folder, plus folders under each type's current root that look
  like code (do's `detect_lang`, the type's `manifests`, or a source file at top level; drops GOPATH `bin`/`pkg`),
  plus `do shortcut` targets not already covered. Label is the folder name, `bias` (0-4, from frecency) feeds `fuzzy.js`.
- `project.new.<type>` for every configured type. Naming types take an optional text param;
  `new pva/wba` show the next number (`Creates Ukol10 in ...`).
- `project.last.<type>` for prefix-numbered types (`do <type>` / `do last <type>`).
- `project.scan` → `do scan`.

Exact invocations:

| Action | Runs |
|---|---|
| open, folder under the type's current root | `do open <type> <name>` |
| open, shortcut | `do open <shortcut>` |
| open, older root (e.g. `pva` in `ClassWork2`, which `do open` can't resolve because it only looks in the current academic-year folder) | `dolib.store.log_access` + `dolib.bus.publish` + `dolib.launcher.open_editor`, the same steps `do open` takes |
| open, folder already open in VS Code | `hyprctl dispatch focuswindow` + `log_access`, no second window |
| run (shift+enter, or a query starting with `run `) | `kitty --hold --directory <path> do run <type> <name>`; older roots and shortcuts run `dolib.launcher.run_project` in the same kitty; `web` → `xdg-open index.html` |
| new, no text / single word | `do new <type>` / `do new <type> -m <word>` |
| new, text with spaces on a naming type | `dolib.ai.name_for` (Haiku via `claude_say.py`) first, then `do new <type> -m <slug>` |
| scan | `do scan` |

`do new -m "<idea>"` is deliberately not used: its AI path does `.splitlines()[0]` on the reply, so an empty
`claude_say` reply (API down, no key) raises `IndexError` and kills the command, and when AI is off it creates a
folder named with the raw idea, spaces included. Naming here falls back to a slug of the idea.

Runnable = do's `detect_lang` (or the stored `lang`) is one `do run` handles; python additionally needs `main.py`.
Failures (missing folder, unknown runner, scaffold error) arrive as `notify-send -a do` notifications.

Frontend:
- `project` category, tint `#f9e2af`, `CAT_BIAS` 2.
- preview stage `project`: language tile with a frecency bar, git branch/changes, last commit, description or README
  line, opens/last-opened/item count. Git and README come from `project peek`, fetched on selection (90ms debounce)
  and cached per path while the palette is open. `new` rows preview the folder that will be created.
- actions may carry `alt: {verb, how, cmd, args}`; shift+enter runs it, and a query starting with `run ` makes it the
  default for matching rows. The verb bar shows the other one as `shift ↵ ...`.
- empty-query suggestions: the most recently opened project if it was within 4 days ("where you left off"), and the
  top-frecency project if different and frecency >= 2.
- `code.<path>` rows (VS Code recents) are dropped when a `project` row owns the same path.
- `paletteExcluded.cats: ["project"]` skips the whole thing.

## Settings coverage

Every settings.json key gets at least one row except `paletteExcluded`:
- booleans: a toggle (`SETTING_LABELS` for curated labels, otherwise humanised)
- known option sets (`ENUMS`, plus any `*Mode` key currently `always|occasional|never`): one row per other option
- numbers: a `number` param row (`NUMS` for label/range/unit; `param.float` keeps decimals)
- other strings: a `text` param row, written with `--str`
- objects (`widgetStyles`): a row that opens the Guide

## Excluding things from the palette

```json
"paletteExcluded": {
  "ids":  ["widget.power", "setting.resident*", "app.Steam"],
  "cats": ["tab", "code", "spotify"]
}
```

- `ids`: exact action ids; a trailing `*` makes it a prefix match.
- `cats`: whole categories. Excluded `tab`/`code` aren't even enumerated. Excluding `spotify` or `mail` also
  removes their live search (it hangs off `spotify.search` / `mail.search`).
- Applied at index-build time, so it also hides the entries from NL routing. Missing/invalid value = nothing excluded.
- Picked up on the next index build (every palette open; a settings.json write also triggers a rebuild while open).
- Known catch: the Guide's Apply rewrites settings.json from its own property list, so until the Guide carries
  `paletteExcluded` through, an Apply drops it. A Guide row only needs to read/write this one object.

## Context hook

Index and `context` output carry three extra top-level keys. Older frontends
ignore them.

- `context`: runtime snapshot from files that already exist (`/tmp/qs_context.json`,
  `/tmp/music_info.json`, `/tmp/qs_timer.json`, `/tmp/qs_recording.json`,
  `/tmp/qs_eco_state.json`, `/tmp/qs_perf.json`, `/tmp/qs_mira_unread.json`,
  `hyprctl activewindow`). Fields: `hour daypart media track player volume muted
  battery plugged focus timer recording eventSoon cpu mem shellCpu orphans eco
  unread stale tags`.
- `context.tags`: flat set used for scoring: `morning|afternoon|evening|night`,
  `media_playing|media_paused|media_none`, `timer_idle|timer_running|timer_paused`,
  `plugged|on_battery`, `battery_low` (<=20, discharging), `battery_mid` (<=40),
  `muted`, `recording`, `event_soon` (<=30 min), `cpu_hot`, `mem_high`, `shell_hot`,
  `eco_active`, `unread_mail`, `focus:<class>`, plus `<state>_on|off` for every live
  toggle (`mute mic nightlight idle wakelock dnd wifi bt quiet kandor`). Note
  `mic_on` means the mic is *muted* (state follows the "Mute microphone" toggle).
- `boost`: `{actionId: number}`, the sum of an action's `ctx` weights whose tag is active.
  Weights are small (1-5) so they nudge, not override, fuzzy scores (which run ~10-40).
  Suggested use: `score += boost[a.id] || 0` after `Fuzzy.rank`, and on an empty query
  sort the default/recent rail by boost.
- `suggest`: up to 8 action ids with the highest positive boost, ready for a
  "right now" rail.

Weights live in data: any action may carry `"ctx": {"tag": weight}` (actions.json
for static actions, `WIDGET_CTX` / `SETTING_CTX` in the script for generated ones).

## Natural-language routing

Runs Haiku (`claude_say.say`, raw Messages API, same key and model as the other
ambient scripts) against a compact catalogue of the current index plus a one-line
context. Results are cached per normalised query in
`~/.cache/quickshell/palette/routes.json` (30 days for hits, 10 minutes for misses),
so repeat phrasings are instant and free.

### Frontend wiring (CommandPalette.qml)

`maybeRoute()` runs on every recompute. A `route` Process fires when:
- the text reads like "open/launch X on N | on a new workspace" (`wsIntent`), debounce 120ms, or
- it has ` and ` / `,` / ` then ` (always), or 3+ words with a weak fuzzy top (score < 12 or `claude.ask`),
  debounce 600ms. Never for URL-looking text or while a live search (mail/spotify) is the top row.

A returned `action` becomes the top row and takes the selection if the user hadn't moved it.
Synchronous lead rows cover the gap before it lands: `ws.openapp` for workspace phrasing, `web.open`
for URL-looking text, both with the whole query as param.

`route` itself resolves workspace phrasing locally first (`direct_route`, no Haiku, ~70ms) when the app
matches by name; anything else, including multi-step requests, goes to Haiku, which now also knows
`ws.openapp`, `spotify.search` and `web.open`.

### When to call it

Fuzzy stays first and synchronous. Fire `route` asynchronously, debounced ~600ms
after the last keystroke, only when all of these hold:

- the query has 3+ words, or contains ` and `, `,` or ` then `
- the top fuzzy result is missing or weak (score < ~12, or it is the `claude.ask` fallback row)

Keep at most one route Process alive; restart it on a newer query. Drop any result
whose `query` no longer equals the input text.

### Result shape

```json
{
  "ok": true,
  "query": "turn down volume and mute mic",
  "key": "333c4c031f0f",
  "cached": false,
  "ms": 1146,
  "steps": [
    {"id": "audio.down", "label": "Volume down", "cat": "audio", "icon": "...", "args": [""]},
    {"id": "audio.mic", "label": "Mute microphone", "cat": "audio", "icon": "...", "args": [""],
     "want": "on", "show": "on", "skip": true}
  ],
  "action": {
    "id": "route.333c4c031f0f", "label": "Turn down volume and mute mic",
    "hint": "Volume down  ›  Mute microphone on (already)", "cat": "claude", "icon": "...",
    "keywords": "", "cmd": "python3 \".../palette_index.py\" run \"$1\"", "arg": "333c4c031f0f",
    "verb": "Run", "danger": false, "close": true, "routed": true, "steps": [ ... ]
  }
}
```

On failure: `{"ok": false, "query", "key", "error": "short|no-client|no-reply|no-match", ...}`.
Show nothing extra on failure; the existing `claude.ask` fallback row already covers it.

### Running it

`action` is a normal palette action. Insert it as a result row
(`{a: res.action, score: <above the weak fuzzy top>, hits: [], param: ""}`) and the
existing `run()` path works unchanged: `danger` triggers the confirm, `close` is
false only when a step opens a widget (the widget then replaces the palette),
and `execDetached(["bash","-c",a.cmd,"_",a.arg])` hands off to `run <key>`.

`run` re-resolves every step at execution time: relative volume/brightness
(`+N`/`-N`) are applied to the live value, toggles with `want` are skipped if
already in that state, setting toggles are written explicitly (never flipped),
widget-opening steps go last. Each executed step is recorded in history under its
real id, so routed usage feeds the normal fuzzy ranking.

`steps[].show` is the resolved param or wanted state for display; `skip` marks a
step that is already satisfied. A preview panel can render `steps` directly, or
call `run <key> --dry` for live-resolved values (e.g. the actual target volume).
