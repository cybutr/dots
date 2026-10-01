# Stage — live narration surface

A Claude session (any terminal, any cwd) narrates to the desktop through one
CLI, `stage_say.py`, and blocks on the user with `stage_wait.sh`. Where the
narration renders is picked by the `showcaseBackend` key in
`~/.config/hypr/settings.json`, read on every call.

| `showcaseBackend` | Renders in | Notes |
|---|---|---|
| `"dock"` (default, also used when missing/invalid) | `StageDock.qml`, the always-on bottom-right dock | full log, typewriter streaming, Continue gate |
| `"resident"` | the existing resident card popup under the clock pill (`resident_card.emit`, `source: "stage"`) | Continue is a card action button |

`--backend dock|resident` on `say` overrides the setting for one call.

## stage_say.py

`python3 ~/.config/hypr/scripts/quickshell/claude/stage_say.py <cmd> ...`
If the first argument isn't a subcommand, `say` is implied
(`stage_say.py "text" --kind step` works).

| Command | Effect | stdout |
|---|---|---|
| `say [TEXT] [flags]` | push an entry (`TEXT` = `-` reads stdin) | entry id |
| `ack [ID] [--state ok\|cancel\|expired]` | resolve a gate (default: newest pending, `ok`) | resolved id(s) |
| `cancel [ID]` | resolve a gate as skipped | resolved id(s) |
| `pending` | list unresolved gate ids, oldest first | ids |
| `clear` | empty the log, cancel pending gates | |
| `collapse` / `expand` | fold/unfold the dock (dock backend only) | |

`say` flags:

| Flag | Meaning |
|---|---|
| `--title T` | bold heading; without it the kind name is shown |
| `--kind K` | `info` (default) `step` `tip` `done` `warn` `error` `wait` — sets the fixed-hex accent + default glyph |
| `--icon G` | Nerd Font glyph overriding the kind glyph |
| `--hold S` | seconds the dock stays open after this entry; `0` = stays until collapsed. Default scales with length (7-45s) |
| `--wait` | make this entry a Continue gate (kind defaults to `wait`). Any older unresolved gate is auto-cancelled |
| `--block [--timeout S]` | implies `--wait`, prints the id, then runs `stage_wait.sh` and exits with its code |
| `--id ID` | fixed id; reusing it replaces that entry in place |
| `--append` | with `--id`: append TEXT to that entry's body (streaming); creates it if missing |
| `--backend B` | one-call override of `showcaseBackend` |

Streaming pattern:

```bash
s=~/.config/hypr/scripts/quickshell/claude/stage_say.py
id=$(python3 $s say "Opening the calendar" --title "Calendar" --kind step)
python3 $s say " — it lists today's agenda." --id $id --append
```

## stage_wait.sh — the Continue contract

`bash ~/.config/hypr/scripts/quickshell/claude/stage_wait.sh [ID|latest] [TIMEOUT=300]`

| Exit | Meaning |
|---|---|
| `0` | user clicked Continue (or `ack ID` was run) |
| `1` | timed out; the gate is marked `expired` so the button disappears |
| `2` | usage error, or `latest` with nothing pending |
| `3` | gate was cancelled/superseded (`cancel`, `clear`, or a newer `--wait`) |

```bash
id=$(python3 $s say "Look at the dock, then continue" --title "Ready?" --wait)
bash ~/.config/hypr/scripts/quickshell/claude/stage_wait.sh "$id" 600
```

or in one call: `python3 $s say "..." --block --timeout 600`.

Acks are keyed by entry id, so a stale ack from an earlier gate can never
satisfy a new one. Keep the Bash tool timeout above the wait timeout.

## Files

| Path | Format |
|---|---|
| `/tmp/qs_stage.jsonl` | last 30 entries, replaced atomically: `{id, rev, ts, title, body, icon, kind, wait, hold, via}`. `rev` is a monotonic ms counter the dock uses to spot new/updated entries. `via` is the backend that rendered it; the dock ignores `via: "resident"` rows |
| `/tmp/qs_stage_ack` | append-only lines `<id> <ok\|cancel\|expired> <unix ts>`, last 200 kept; last line per id wins |
| `/tmp/qs_stage_ctl` | `{op: collapse\|expand, ts}` |

Every entry is written to the stage queue regardless of backend, so `pending`,
`ack`, and `stage_wait.sh` behave identically on both.

## Backends in code

- **dock** — `say()` writes the queue; `StageDock.qml` runs a single
  `inotifywait -m` on `/tmp` (filtered to the three files above, wrapped in
  `lifeline.sh`) and re-reads on each change. Clicking Continue runs
  `stage_say.py ack <id>`.
- **resident** — `say()` also calls `_resident()` →
  `resident_card.emit(title, body, icon, urgency, hold_secs, actions, source="stage", card_id=id)`.
  Gates get `hold_secs=0` and one action `Continue` → `stage_say.py ack <id>`,
  which the resident popup runs via `execDetached` and then dismisses. On
  timeout/cancel the card is re-emitted in place with `[timed out]`/`[skipped]`,
  no action, 8s hold. Appends re-emit the same card id with the full body.

Guide wiring for later: one row in GuidePopup.qml writing `showcaseBackend`
(`"dock"`/`"resident"`) to settings.json. Nothing else reads it, so no
watcher or restart is needed. The dock keeps running either way and stays idle
while the resident backend is selected.

## Dock process

`StageDock.qml`, started from `exec.conf` like the other OSDs, namespace
`qs-stage`, overlay layer, input mask limited to the dock itself. Restart:

```bash
pkill -f "quickshell -p .*StageDock.qml"
setsid -f quickshell -p ~/.config/hypr/scripts/quickshell/StageDock.qml
```

Run those as two separate Bash calls (exit-144 gotcha).
