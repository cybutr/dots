# Custom resident card kinds

Resident cards (`/tmp/qs_resident_cards.jsonl`) render with the generic
title/body/actions template in `TopBar.qml` unless they carry a `kind`.
A `kind` swaps the whole card body for a bespoke layout.

## JSON shape

Standard card fields, plus:

```json
{
  "id": "wrapped-weekly",
  "kind": "wrapped",
  "data": { "...": "anything the renderer needs" },
  "title": "Your Weekly Wrapped is ready",
  "body": "3h 41m listened over the last 1d\nTop artist: ...",
  "actions": [{ "label": "Open Wrapped", "cmd": "bash ~/.config/hypr/scripts/qs_manager.sh open guide musicstats-week" }]
}
```

- `kind`: renderer key. Unknown kinds fall back to the generic template.
- `data`: free-form payload, only read by that kind's renderer.
- Keep `title`/`body` meaningful: history list, notifications and any
  consumer that doesn't know the kind still use them.
- `actions[0]` is the kind's primary action by convention.

## Emitting

```python
resident_card.emit(title, body, icon, urgency, hold_secs, actions, source, card_id,
                   kind="wrapped", data={...})
```

CLI: `resident_card.py --title ... --kind wrapped --data '{"listen":"3h"}'`

## Where it renders

`TopBar.qml`, `Rectangle { id: residentCard }`:

- `readonly property bool isWrapped: disp !== null && disp.kind === "wrapped"`
  drives size/position/radius/fill of the card shell and hides the generic
  children (`rcCol`, accent strip, hold bar, `residentGlow`).
- The kind's layout is a sibling `Item` at the end of `residentCard`
  (`id: rcWrapped`, `visible: residentCard.isWrapped`). It reads
  `residentCard.disp.data` and calls `barWindow.residentDismiss()`.
- Centre-pill corner squaring (`centerBox.bottomLeftRadius`) is skipped for
  detached kinds.

Shared visuals live in `quickshell/`:

- `WrappedBackdrop.qml`: boosted album-palette gradient, soft art colour
  field, drifting blobs, sheen, glow bed, rounded clip. Props: `from1`,
  `from2`, `art`, `radius`, `wash`, `bedSpread`, `live`. Exposes `ink`
  (legible text colour), `deep` (shadow/scrim), `tone1`/`tone2`.
- `WrappedArt.qml`: rounded album-art tile with fallback, shadow and edge.

The Guide's Music Stats hero card uses the same two components, so the bar
card and the Guide stay visually in sync.

## Adding a new kind

1. Producer: pass `kind="<name>", data={...}` to `resident_card.emit()`.
2. `TopBar.qml` → `residentCard`: add `readonly property bool is<Name>: disp !== null && disp.kind === "<name>"`.
3. Fold it into `isDetached` (and `isArtKind` if it renders on `rcWrapped`), and give it a
   height branch in `residentCard.height`. `isDetached` drives the shell bindings
   (width/y/radius/color/border/clip) and the `visible:` guards of the generic children.
4. Add a sibling at the end of `residentCard`: either an inline `Item { visible: residentCard.is<Name> }`
   or a component from `quickshell/rescards/` (preferred for new kinds; see below). Reuse `WrappedBackdrop`/`WrappedArt` for art-driven cards; text on them uses `ink`.
5. Wrap any new long-lived `Process` in `lifeline.sh`. No new ids that collide
   with existing ones (duplicate ids blank the bar silently).
6. Test: emit a card, `qsdev.sh bar`, screenshot. Wrapped has
   `python3 resident_extras.py --test-wrapped week|month`.

## Shipped kinds

| kind | producer (`resident_extras.py`) | renderer | setting | test |
|---|---|---|---|---|
| `wrapped` | `tick_wrapped_nudge` | `rcWrapped` (inline) | — | `--test-wrapped week\|month` |
| `nowplaying` | `tick_nowplaying_milestone` (every 20th play of a track hash) | `rcWrapped` branch (`isNowPlaying`) | `residentNowPlayingEnabled` | `--test-nowplaying` |
| `calendar` | `tick_calendar_nudge` (<=15 min before, once per event, via `schedule_manager.sh`) | `rescards/RcCalendar.qml` | `residentCalendarNudgeEnabled` | `--test-calendar` |
| `batteryhealth` | `tick_battery_health` (weekly) | `rescards/RcBatteryHealth.qml` | `residentBatteryHealthEnabled` | `--test-batteryhealth` |
| `uptimeguilt` | `tick_uptime_guilt` (tiers 3/5/7/10/14/21/30… days, once per tier per boot) | `rescards/RcUptime.qml` | `residentUptimeGuiltEnabled` | `--test-uptimeguilt` |
| `brief` | `run_brief(period)` — morning via `claude_resident` periodic, afternoon/night via `tick_day_briefs` | `rescards/RcBriefMorning/Afternoon/Night.qml` by `data.period` | `residentMorningBrief`/`residentAfternoonBrief`/`residentNightBrief` (off/text/spoken) + `…Time` windows | `--test-brief-card morning\|afternoon\|night` |
| `focusdone` | `focus_done` (called by TopBar `timerFinish()` via `--focus-done <secs> <endTs>`) | `rescards/RcFocusDone.qml` | `residentFocusDoneEnabled` | `--test-focusdone [mins]` |
| `gitpush` | `~/.config/git-hooks/pre-push` (global `core.hooksPath` git hook, fires on `git push` in ANY repo on the machine) | `rescards/RcGit.qml` | — | simulate: `echo "refs/heads/main abc abc" \| bash ~/.config/git-hooks/pre-push origin url` |
| `tailscale` | `tick_tailscale_key` (auth-key expiry, hardcoded `TAILSCALE_AUTHKEY_EXPIRY` — Tailscale doesn't expose this via CLI, only the admin console UI) | `rescards/RcTailscale.qml` | — (always on, high-urgency infinite-hold by design) | `tick_tailscale_key({}, force=True)` |

`rescards/` components share `RcShell.qml` (card fill, accent wash, glow bed, close button)
and `RcButton.qml` (primary action + "later"). API: `bar`, `theme`, `d`, `actions`, `live`,
signals `dismissRequested()` / `runRequested(cmd)`, height via `implicitHeight`.
Test flags emit real cards; restart the bar afterwards to clear them.

Accents are fixed hex per kind (matugen names wash out to grey on some wallpapers):
calendar `#fab387`, batteryhealth `#a6e3a1`/`#f9e2af`/`#f38ba8` by health, uptimeguilt `#b4befe`,
focusdone `#cba6f7`, brief morning `#f9e2af`, afternoon `#89dceb`, night `#89b4fa`,
gitpush `#a6e3a1`, tailscale `#89b4fa`/`#f38ba8` (urgent, <=3 days left).

Never put Text inside a `ClippingRectangle` — it renders its children through a
texture layer and text comes out blurry. `RcShell` clips only the background;
the content slot sits outside it.
