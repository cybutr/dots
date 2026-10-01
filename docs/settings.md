# Settings

Everything lives in `~/.config/hypr/settings.json` and is hot-reloaded (`inotifywait` in `Main.qml`, `Scaler.qml`, `TopBar.qml` and `settings_watcher.sh`). The usual way to edit it is **Guide → Settings** (<kbd>Super</kbd> <kbd>Shift</kbd> <kbd>H</kbd>). Hand edits work too.

Mode keys that take `always` / `occasional` / `never` are marked **A/O/N** below. `occasional` means "only when there's something to show".

## General

| Key | Default | |
|---|---|---|
| `uiScale` | `1` | Multiplier on top of the automatic width-based scale |
| `openGuideAtStartup` | `false` | Open the Guide on login |
| `wallpaperDir` | — | Folder for the wallpaper picker |
| `language` | `"us,cz"` | Keyboard layouts cycled by <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>Space</kbd> |
| `widgetStyles` | object | Per widget `legacy` or `revamp` (`volume`, `wallpaper`, `monitors`, `notifications_*`, …) |

## Top bar

| Key | Default | |
|---|---|---|
| `topBarHoverCardsEnabled` | `true` | Hover cards on every pill |
| `topBarAccentLine*` | on, top, 1 px, cycle | Animated accent line: `Position`, `Thickness`, `SpeedMs`, `ColorMode` (`cycle`/`fixed`), `FixedColor` |
| `topBarShowGpu` / `Net` / `Uptime` / `QuickshellCpu` | `true` | Optional stats chips |
| `topBarTimerEnabled`, `topBarTimerFillMode` | `true`, `always` | Timer pill |
| `topBarPillBgMaster` | A/O/N | Master switch for pill backgrounds |
| `topBar…Mode` | A/O/N | One per effect. See [topbar.md](topbar.md#pill-backgrounds) |
| `topBarEcoIndicatorMode` | A/O/N | Eco tint on workspace pills |
| `topBarFlourishesEnabled` (+ `…Uptime`, `…Battery`, `…CpuCalm`) | `true` | One-off celebration animations |
| `mediaVisualizerEnabled`, `mediaVisualizerMode` | `true`, `fft` | Media pill visualizer |
| `topBarFftIntensity`, `topBarVisualizerColorSource` | `1.4`, `dominant` | Visualizer look |
| `lyricsSyncOffsetSec` | `1` | Lyrics timing nudge |

## Ambient glow

`AmbientGlow.qml` draws screen-edge glow.

| Key | Default | |
|---|---|---|
| `ambientGlowEnabled` | `true` | |
| `ambientGlowIntensity`, `ambientGlowSpread` | `0.3`, `60` | |
| `ambientGlowEdgeTop` / `Bottom` / `Left` / `Right` | `true` | Which edges |
| `ambientGlowColorMode` | `album` | `album`, `cycle`, `fixed` |
| `ambientGlowBeatReactive` | `true` | Pulse on the beat |
| `ambientGlowIdleBehavior` | `fadeOut` | What happens when nothing is playing |
| `hyprlandBorderPulseEnabled` | `true` | Window border pulses with the music |

## Lock screen

| Key | Default | |
|---|---|---|
| `lockStyleEnabled` | `true` | New lock screen (`false` means `LockLegacy.qml`) |
| `lockShowMusic` / `Weather` / `Brief` / `QuickActions` | `true` | Chips |
| `lockShowNotifs` | `full` | |
| `lockBlurStrength`, `lockParallax` | `0.8`, `true` | Backdrop |
| `lockAmbientFx` | A/O/N | |
| `lockClockStyle` | `big` | |

Preview without locking: `bash ~/.config/hypr/scripts/lock_test.sh` (password `test`).

## Hyprland polish

| Key | Values | |
|---|---|---|
| `hyprPolishAnimations` | `off` / `subtle` / `juicy` | Animation preset written to `polish.conf` |
| `hyprPolishDimInactive` | `off` / `subtle` / `strong` | |
| `hyprPolishWsAccent` | `off` / `palette` / `smartws` | Border color per workspace (`ws_accent.py`) |
| `hyprPolishWsAccentSpeed` | `normal` | Cross-fade speed |

## Workspaces & eco mode

| Key | Default | |
|---|---|---|
| `smartWsAutoNames` | `always` | `off` / `hover` / `always` |
| `smartWsLayoutsEnabled`, `smartWsRestoreConfirm` | `true` | Layout save/restore |
| `ecoModeEnabled` | `true` | See [performance.md](performance.md#eco-mode) |
| `ecoThrottleSecs`, `ecoFreezeSecs` | `20`, `300` | Unfocused/hidden time before throttle/freeze |

## Resident & cards

| Key | Default | |
|---|---|---|
| `residentCardsEnabled` | `true` | Card popup under the clock |
| `residentCardMaxHeight`, `residentCardHoldMode` | `medium`, `auto` | |
| `residentCardSound`, `residentCardSoundFile` | `on`, `window-attention` | |
| `screenshotAnswerOutput` | `card` | `card` / `notification` / `both` |
| `residentMorningBrief` / `AfternoonBrief` / `NightBrief` | `text` | `off` / `text` / `spoken`, each with a `…Time` window |
| `residentCatchUp` | `true` | "While you were away" |
| `residentProactiveFixes` | `suggest` | |
| `residentStrictness` | `balanced` | How chatty nudges are |
| `residentVoiceNudges`, `residentClipboardAware`, `residentDeviceAlerts`, `residentEcoNotice` | `true` | |
| `residentSongReactChance` | `0.3` | |

## Misc

| Key | Default | |
|---|---|---|
| `nightLightStart` / `End` / `Temp` | `18:00` / `07:00` / `4000` | Night light schedule |
| `batteryAlertStyle` | `integrated` | |
| `calendarRefreshMinutes` | `3` | |
| `cardAccent`, `cardAnimations`, `cardDepth` | `blue`, `true`, `true` | Card styling |
| `pinGridSize`, `pinCompactMode`, `pinClutterCap` | `12`, `true`, `true` | Pinned cards |
