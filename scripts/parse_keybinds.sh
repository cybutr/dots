#!/usr/bin/env bash
# Parses hyprland.conf bind lines → JSON array for GuidePopup keybinds tab
CONF="$HOME/.config/hypr/hyprland.conf"

python3 - "$CONF" <<'PYEOF'
import sys, re, json

conf = open(sys.argv[1]).read()

# Resolve $mainMod and other variables
mainmod = "SUPER"
m = re.search(r'^\s*\$mainMod\s*=\s*(\S+)', conf, re.MULTILINE)
if m:
    mainmod = m.group(1).upper()

# Build variable map for all $var = value definitions
vars_map = {}
for vm in re.finditer(r'^\s*\$(\w+)\s*=\s*(.+)', conf, re.MULTILINE):
    vars_map[vm.group(1)] = vm.group(2).strip()

def resolve_vars(s):
    for k, v in vars_map.items():
        s = s.replace("$" + k, v)
    return s

# Explicit action labels — checked FIRST, keyed on substrings/regex of the exec command.
# Anything not matched here falls through to dynamic derivation below.
LABELS = {
    r"qs-master":                   "Close Window/Widget",
    "togglefloating":               "Toggle Floating",
    "killactive":                   "Close Window",
    "qs_manager.sh close":          "Close Widget",
    "kitty":                        "Open Terminal",
    "vivaldi":                      "Open Vivaldi",
    "flatpak run com.visualstudio": "Open VS Code",
    "hyprpicker":                   "Color Picker",
    "nautilus":                     "Open Files",
    "toggle applauncher":           "App Launcher",
    "toggle claudeask":             "Claude Ask",
    "alttab.sh":                    "Window Switcher (Alt+Tab)",
    "toggle clipboard":             "Clipboard History",
    "toggle workspaces":            "Workspace Overview",
    "toggle notifications":         "Notifications Panel",
    "toggle power":                 "Power Menu",
    "toggle calendar":              "Calendar Widget",
    "screenshot.sh --freeze":       "Screenshot (Freeze)",
    "screenshot.sh --edit":         "Screenshot (Edit)",
    "screenshot.sh --full --edit":  "Screenshot (Full+Edit)",
    "screenshot.sh --full":         "Screenshot (Full)",
    "screenshot.sh":                "Screenshot",
    "screenrec-toggle.sh full":     "Screen Record (Full)",
    "screenrec-toggle.sh region":   "Screen Record (Region)",
    "toggle music":                 "Music Widget",
    "toggle battery":               "Battery Widget",
    "scratchpad.sh":                "Scratchpad",
    "toggle_night_light":           "Toggle Night Light",
    "toggle wallpaper":             "Wallpaper Picker",
    "toggle network":               "Network Widget",
    "toggle focustime":             "FocusTime Widget",
    "toggle volume":                "Volume Widget",
    "toggle guide":                 "Guide (This Panel)",
    "toggle monitors":              "Monitors Widget",
    "toggle_hypridle":              "Toggle Idle Inhibit",
    "toggle_wakelock":              "Toggle Wakelock",
    "toggle_brightness_curve":      "Toggle Brightness Curve",
    "switch_kb_layout":             "Switch Keyboard Layout",
    "anthropic_acct":               "Cycle AI Account",
    "mira_toggle":                  "Toggle Mira",
    "lock.sh":                      "Lock Screen",
    "capslock_osd":                 "Caps Lock Indicator",
    "mic_mute_toggle":              "Mute Microphone",
    "volume_step.sh mute-toggle":   "Mute Volume",
    "media_control.sh play-pause":  "Play/Pause Media",
    "media_control.sh next":        "Next Track",
    "media_control.sh previous":    "Previous Track",
    "playerctl.*play-pause":        "Play/Pause Media",
    "playerctl.*next":              "Next Track",
    "playerctl.*prev":              "Previous Track",
    "swayosd.*mute-toggle.*source": "Mute Microphone",
    "swayosd.*mute-toggle":         "Mute Volume",
    "swayosd.*volume mute":         "Mute Volume",
    "swayosd.*caps-lock":           "Caps Lock OSD",
    "echo next > /tmp/qs_alttab_nav":    "Next Window",
    "echo confirm > /tmp/qs_alttab_nav": "Confirm Selection",
    "echo close > /tmp/qs_widget_state": "Close/Cancel",
}

DIR_WORDS = {"l": "Left", "r": "Right", "u": "Up", "d": "Down",
             "left": "Left", "right": "Right", "up": "Up", "down": "Down"}

STEP_SUFFIX = {"raise": "Up", "up": "Up", "increase": "Up", "+": "Up",
               "lower": "Down", "down": "Down", "decrease": "Down", "-": "Down"}

KEY_FALLBACK = {
    "xf86monbrightnessup":   "Brightness Up",
    "xf86monbrightnessdown": "Brightness Down",
    "xf86audioraisevolume":  "Volume Up",
    "xf86audiolowervolume":  "Volume Down",
    "xf86audiomute":         "Mute Volume",
    "xf86audiomicmute":      "Mute Microphone",
    "xf86audioplay":         "Play Media",
    "xf86audiopause":        "Pause Media",
    "xf86poweroff":          "Power Button",
    "print":                 "Screenshot",
    "caps_lock":             "Caps Lock",
}

def prettify_script(token):
    name = token.split("/")[-1]
    name = re.sub(r'\.sh$', '', name)
    name = name.replace("_", " ").replace("-", " ")
    return name.strip().title()

def derive_exec_label(args, key):
    a = args.strip()
    if not a:
        return KEY_FALLBACK.get(key.lower(), key)
    low = a.lower()

    # qs_manager.sh <N> [move] → workspace switch/move (numbered workspace keys)
    m = re.search(r'qs_manager\.sh\s+(\d+)(\s+move)?\s*$', a)
    if m:
        return f"Move Window to Workspace {m.group(1)}" if m.group(2) else f"Switch to Workspace {m.group(1)}"

    # playerctl invocations (spotify seek/track control etc.)
    if "playerctl" in low:
        player = ""
        pm = re.search(r'--player[= ]([\w.]+)|-p\s+([\w.]+)', a)
        if pm:
            player = " (" + (pm.group(1) or pm.group(2)).title() + ")"
        if "play-pause" in low:
            return "Play/Pause" + player
        if re.search(r'\bnext\b', low):
            return "Next Track" + player
        if re.search(r'\bprev', low):
            return "Previous Track" + player
        pos = re.search(r'position\s+\d+([+-])', a)
        if pos:
            return ("Fast-Forward" if pos.group(1) == "+" else "Rewind") + player
        return "Media Control" + player

    # unwrap `bash -c '...'` — best-effort, take the last clause
    tokens = a.split()
    if tokens[:2] == ["bash", "-c"] and len(tokens) > 2:
        inner = a.split(None, 2)[2].strip().strip("'\"")
        clauses = [c.strip() for c in re.split(r'[;|&]', inner) if c.strip()]
        if clauses:
            last_tok = clauses[-1].split()
            if last_tok:
                return prettify_script(last_tok[0])
        return "Custom Command"

    if tokens and tokens[0] in ("bash", "sh"):
        tokens = tokens[1:]
    if not tokens:
        return a[:40] if a else key

    script_tok = tokens[0]
    rest = tokens[1:]
    name = prettify_script(script_tok)

    # "toggle <thing>" style scripts (qs_manager.sh toggle X, etc.)
    if rest and rest[0].lower() == "toggle":
        if len(rest) > 1:
            return "Toggle " + " ".join(w.title() for w in rest[1:])
        return "Toggle " + name

    # "<script>_step.sh raise/lower [amount]" style scripts
    dir_word = next((t.lower() for t in rest if t.lower() in STEP_SUFFIX), None)
    if dir_word and re.search(r'step|volume|bright', name, re.I):
        base = re.sub(r'\s*Step$', '', name, flags=re.I).strip()
        extra = [t for t in rest if t.lower() != dir_word]
        suffix = " (Fast)" if extra and extra[0].replace('.', '', 1).isdigit() and float(extra[0]) >= 100 else ""
        return f"{base} {STEP_SUFFIX[dir_word]}{suffix}"

    if rest:
        arg_str = " ".join(w.title() for w in rest[:2])
        return f"{name} {arg_str}"[:48]
    return name

def label_for(action_str, key, dispatcher, args):
    s = action_str.lower()
    for pattern, label in LABELS.items():
        if re.search(pattern, s):
            return label

    if dispatcher == "movefocus":
        return "Focus " + DIR_WORDS.get(args.strip().lower(), args.strip().title())
    if dispatcher == "movewindow" and not key.lower().startswith("mouse:"):
        return "Move Window " + DIR_WORDS.get(args.strip().lower(), args.strip().title())
    if dispatcher in ("movewindow", "resizewindow") and key.lower().startswith("mouse:"):
        return "Drag to " + ("Move Window" if dispatcher == "movewindow" else "Resize Window")
    if dispatcher == "resizeactive":
        return "Resize Window (" + DIR_WORDS.get(key.lower(), key.title()) + ")"
    if dispatcher == "fullscreen":
        return "Fullscreen" if args.strip() == "1" else "Fullscreen (No Gaps)"
    if dispatcher == "togglespecialworkspace":
        return "Toggle Scratchpad" if "magic" in args.lower() else f"Toggle Special Workspace ({args})"
    if dispatcher == "movetoworkspacesilent":
        return "Send Window to Scratchpad" if "magic" in args.lower() else f"Move to Workspace ({args})"
    if dispatcher == "workspace":
        return f"Switch to Workspace {args}"
    if dispatcher == "movetoworkspace":
        return f"Move Window to Workspace {args}"
    if dispatcher == "exec":
        return derive_exec_label(args, key)

    # generic dispatcher fallback
    parts = args.strip().split()
    label = dispatcher.title() + (" " + " ".join(w.title() for w in parts[:2]) if parts else "")
    return label[:48]

def norm_mod(raw):
    raw = raw.replace("$mainMod", mainmod).replace("SHIFT_L", "SHIFT").replace("&", " ").replace(",", " ")
    parts = [p.strip().upper() for p in raw.split() if p.strip()]
    order = ["SUPER", "CTRL", "SHIFT", "ALT"]
    ordered = [p for p in order if p in parts]
    rest = [p for p in parts if p not in order]
    return "+".join(ordered + rest) if ordered else "+".join(rest)

def norm_key(key):
    if key.lower() == "mouse:272":
        return "LMB (Drag)"
    if key.lower() == "mouse:273":
        return "RMB (Drag)"
    return key.upper()

results = []
current_submap = None

for line in conf.splitlines():
    line = line.strip()
    if line.startswith("submap"):
        val = line.split("=")[-1].strip()
        current_submap = None if val == "reset" else val
        continue
    if not line.startswith("bind"):
        continue

    m = re.match(r'^bind([a-z]*)\s*=\s*([^,]*),\s*([^,]*),\s*(\w+)\s*,?\s*(.*)$', line)
    if not m:
        continue
    flags, mod_raw, key, dispatcher, args = m.group(1), m.group(2), m.group(3).strip(), m.group(4).strip(), m.group(5).strip()
    args = resolve_vars(args)

    # internal submap-transition plumbing, not a standalone user-facing action
    if dispatcher == "submap":
        continue

    mod = norm_mod(mod_raw)
    action_str = args if dispatcher == "exec" else dispatcher + " " + args
    action = label_for(action_str, key, dispatcher, args)
    cmd = args if dispatcher == "exec" else "hyprctl dispatch " + dispatcher + (" " + args if args else "")

    if current_submap:
        action += f" [{current_submap.title()} Mode]"

    results.append({"k1": mod, "k2": norm_key(key), "action": action, "cmd": cmd})

print(json.dumps(results))
PYEOF
