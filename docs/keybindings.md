# Keybindings

`$mainMod` is <kbd>Super</kbd>. Source of truth: `hyprland.conf` (the `bind` block at around line 235). The in-shell Guide (<kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>H</kbd>) parses the same file live through `scripts/parse_keybinds.sh`.

## Shell popups

| Keys | Opens |
|---|---|
| <kbd>Super</kbd> <kbd>K</kbd> | Command palette (actions, apps, windows, settings) |
| <kbd>Super</kbd> <kbd>A</kbd> | App launcher |
| <kbd>Super</kbd> <kbd>V</kbd> | Clipboard history |
| <kbd>Super</kbd> <kbd>M</kbd> | Music |
| <kbd>Super</kbd> <kbd>B</kbd> | Battery |
| <kbd>Super</kbd> <kbd>N</kbd> | Network |
| <kbd>Super</kbd> <kbd>W</kbd> | Wallpaper picker |
| <kbd>Super</kbd> <kbd>U</kbd> | Quick settings drawer |
| <kbd>Super</kbd> <kbd>`</kbd> | Ask Claude |
| <kbd>Super</kbd> <kbd>G</kbd> / <kbd>Super</kbd> <kbd>Alt</kbd> <kbd>G</kbd> | Quick-tell (text / voice) |
| <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>X</kbd> | Calendar |
| <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>V</kbd> | Volume |
| <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>T</kbd> | Focus time |
| <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>M</kbd> | Monitors |
| <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>H</kbd> | Guide and settings |
| <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>A</kbd> | Notification center |
| <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>W</kbd> | Workspace overview |
| <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>E</kbd> | Power menu |
| <kbd>Super</kbd> <kbd>Q</kbd> | Closes the open popup, or kills the active window |

**Leader key:** press <kbd>Super</kbd> <kbd>J</kbd>, then within about 600 ms press <kbd>C</kbd> for calendar, <kbd>M</kbd> for music or <kbd>N</kbd> for network.

## Windows

| Keys | Action |
|---|---|
| <kbd>Super</kbd> <kbd>←↑→↓</kbd> | Move focus |
| <kbd>Super</kbd> <kbd>Ctrl</kbd> <kbd>←↑→↓</kbd> | Move window |
| <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>←↑→↓</kbd> | Resize by 50 px |
| <kbd>Super</kbd> <kbd>D</kbd> / <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>D</kbd> | Maximize / true fullscreen |
| <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>F</kbd> | Toggle floating |
| <kbd>Super</kbd> + drag LMB / RMB | Move / resize |

## Workspaces

| Keys | Action |
|---|---|
| <kbd>Super</kbd> <kbd>1</kbd>–<kbd>0</kbd> | Go to workspace 1–10 |
| <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>1</kbd>–<kbd>0</kbd> | Move window to workspace |
| <kbd>Alt</kbd> <kbd>Tab</kbd> | Workspace switcher. Release <kbd>Alt</kbd> or press <kbd>Enter</kbd> to confirm, <kbd>Esc</kbd> to cancel |
| <kbd>Super</kbd> <kbd>S</kbd> | Toggle the `magic` scratch workspace |
| <kbd>Super</kbd> <kbd>Alt</kbd> <kbd>S</kbd> | Send window to `magic` |
| <kbd>Super</kbd> <kbd>P</kbd> | Scratchpad |

## Apps

| Keys | Launches |
|---|---|
| <kbd>Super</kbd> <kbd>T</kbd> | Terminal (kitty) |
| <kbd>Super</kbd> <kbd>F</kbd> | Vivaldi |
| <kbd>Super</kbd> <kbd>C</kbd> | VS Code |
| <kbd>Super</kbd> <kbd>E</kbd> | Nautilus |
| <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>C</kbd> | Color picker (hyprpicker) |

## Screenshots & recording

| Keys | Action |
|---|---|
| <kbd>Print</kbd> / <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>S</kbd> | Region screenshot |
| <kbd>Super</kbd> <kbd>Ctrl</kbd> <kbd>S</kbd> | Region screenshot, frozen screen |
| <kbd>Shift</kbd> <kbd>Print</kbd> | Region, then open in editor |
| <kbd>Super</kbd> <kbd>Print</kbd> | Full screen (<kbd>+Shift</kbd> to edit) |
| <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>Z</kbd> | Screenshot → ask Claude about it |
| <kbd>Super</kbd> <kbd>Ctrl</kbd> <kbd>Z</kbd> | Screenshot → Claude answers it as a card |
| <kbd>Super</kbd> <kbd>Alt</kbd> <kbd>R</kbd> | Toggle screen recording (<kbd>+Shift</kbd> for region) |

## Media & hardware

| Keys | Action |
|---|---|
| <kbd>Super</kbd> <kbd>Space</kbd> | Play / pause |
| <kbd>Super</kbd> <kbd>.</kbd> / <kbd>Super</kbd> <kbd>,</kbd> | Next / previous track |
| <kbd>Super</kbd> + brightness keys | Seek back / forward |
| <kbd>Super</kbd> + volume keys | Spotify-only volume |
| <kbd>Super</kbd> <kbd>Shift</kbd> + volume keys | Volume up to 150% |
| <kbd>Super</kbd> <kbd>Ctrl</kbd> <kbd>M</kbd> / <kbd>Super</kbd> <kbd>Alt</kbd> <kbd>M</kbd> | Mute output / mic |
| <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>Space</kbd> | Switch keyboard layout (us / cz) |
| <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>G</kbd> | Night light |
| <kbd>Super</kbd> <kbd>Shift</kbd> <kbd>I</kbd> | Toggle hypridle |
| <kbd>Super</kbd> <kbd>Alt</kbd> <kbd>K</kbd> | Wake lock |
| <kbd>Super</kbd> <kbd>Alt</kbd> <kbd>B</kbd> | Auto-brightness curve |
| <kbd>Super</kbd> <kbd>L</kbd> / power key | Lock |

## Hold actions

Hold the chord until the ring fills. Releasing early aborts.

| Hold | Action |
|---|---|
| <kbd>Super</kbd> <kbd>Alt</kbd> <kbd>Shift</kbd> <kbd>K</kbd> | Emergency-kill Quickshell |
| <kbd>Super</kbd> <kbd>Alt</kbd> <kbd>Shift</kbd> <kbd>D</kbd> | Toggle do-not-disturb |
| <kbd>Super</kbd> <kbd>Alt</kbd> <kbd>Shift</kbd> <kbd>L</kbd> | Lock and suspend |
| <kbd>Super</kbd> <kbd>Alt</kbd> <kbd>Shift</kbd> <kbd>M</kbd> | Emergency mute |
