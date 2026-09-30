# Installation

> [!WARNING]
> These are personal dotfiles for one ThinkPad with hybrid Intel/Nvidia graphics. Paths such as `/home/czeddaru/...` and several `env =` lines in `hyprland.conf` are machine-specific. Read before you run anything.

## Dependencies

Arch / CachyOS package names:

| Group | Packages |
|---|---|
| Compositor | `hyprland` (0.54+), `hypridle`, `hyprlock`, `hyprpicker`, `xdg-desktop-portal-hyprland` |
| Shell | `quickshell-git`, `qt6-5compat`, `qt6-multimedia` |
| Theming | `matugen`, `awww`, `mpvpaper` (for video wallpapers) |
| Media | `playerctl`, `pipewire`, `wireplumber`, `easyeffects` |
| System | `networkmanager`, `bluez-utils`, `brightnessctl`, `power-profiles-daemon`, `inotify-tools`, `jq` |
| Input / capture | `grim`, `slurp`, `swappy`, `wl-clipboard`, `cliphist`, `ydotool`, `python-evdev`, `libinput-gestures` |
| Launchers / OSD | `rofi-wayland`, `swayosd`, `swaync` |
| Fonts | `ttf-jetbrains-mono-nerd` |

The Claude resident also needs the `claude` CLI and `espeak-ng` for spoken briefs. See [claude-resident.md](claude-resident.md).

## Install

The repo *is* `~/.config/hypr`:

```bash
mv ~/.config/hypr ~/.config/hypr.bak     # keep your old config
git clone https://github.com/cybutr/dots ~/.config/hypr
```

Then:

1. Set `wallpaperDir` in `settings.json` and the `WALLPAPER_DIR` / `SCRIPT_DIR` env lines at the bottom of `hyprland.conf` to your paths.
2. Remove or adjust the Nvidia `env =` block if you don't have a PRIME laptop.
3. Trim `exec.conf`. It starts eduroam, a Discord bridge, a VPN autoconnect and other daemons you probably don't want.
4. Log into Hyprland. `init.sh` runs, the three main Quickshell processes start, and the Guide opens (<kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>H</kbd> to reopen it later).

Optional system tweaks (Nvidia runtime PM, 80% charge cap, earlyoom, ananicy rules) live in `scripts/apply_power_tweaks.sh`. It is **never** run automatically. Read it, then `sudo bash` it yourself. See [performance.md](performance.md).

## Restarting the shell

```bash
bash ~/.config/hypr/scripts/quickshell/claude/qsdev.sh main     # or: bar, shell, all
```

`qs_manager.sh`'s watchdog also restarts any dead instance the next time a widget opens. QML errors land in `/run/user/1000/quickshell/by-id/*/log.qslog`. Check there before you debug blind.

## Refreshing screenshots

The images in the README come from the Guide's own preview PNGs. To retake them on your machine:

```bash
bash ~/.config/hypr/scripts/docs/capture.sh          # every widget
bash ~/.config/hypr/scripts/docs/capture.sh music    # just one
```

This opens each popup through `qs_manager.sh`, grabs the focused monitor with `grim`, and writes `scripts/quickshell/guide/previews/preview_<widget>.png`. Then it runs `scripts/docs/build_assets.py` (needs Pillow) to crop `docs/assets/`. The crop boxes assume 1920×1080 at `uiScale: 1`. Adjust `BOXES` in `build_assets.py` for anything else.
