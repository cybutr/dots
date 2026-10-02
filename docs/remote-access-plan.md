# Remote Access Plan: Phone → VPS → Laptop, plus Windows Status Feed

Status as of 2026-10-01 (evening): Phases 1 (mesh), 3 (hub) and 6 (qs-remote Tier A) are live. qs-remote now has a v1 API with Tailscale-identity checks, a kill switch and cookie-based `/m`. The hub has the §8.2 file relay, and the native Android app (§8) is built in [cybutr/fleet-app](https://github.com/cybutr/fleet-app): Dashboard, Controls, Send. Kahoot (§8.3) is deferred. Laptop side: [fleet.md](fleet.md). §7's questions are still mostly open.

§8 below (native Android app, file relay, Kahoot-photo-answer) is now **superseded by reality** — all of it was built in a separate cloud session as [cybutr/fleet-app](https://github.com/cybutr/fleet-app) (`~/apps/fleet-app` locally): Compose app, CI-built debug APKs, pairing flow, touchpad/keyboard control (beyond what §8 even scoped), bidirectional file relay, and a working Kahoot `/api/v1/answer` endpoint (fast/Haiku + accurate/Sonnet modes). See `docs/fleet.md` for the real current state. §8 is kept below only as a historical record of the original plan, not as a live TODO.

---

## 0. What already exists (local recon, read-only)

This came from reading local config only. Nothing was connected to.

| Hint | Where | What it means |
|---|---|---|
| `Host netcup-vps` (user `vps`, key `netcup-vps-ntb.key`) | `~/.ssh/config` | **A VPS most likely exists already**: a netcup box. |
| `~/vps-basecamp-web/` | homepage-config, panel-app | That VPS runs **"basecamp"**: Docker with Caddy (TLS), Authelia (SSO), Portainer, a FastAPI panel (`PANEL_MODE=vps|game`), gethomepage and a Minecraft server, all under `*.basecamp.czeddaru.dev`. |
| `Host roam` → a `100.x.y.z` address | `~/.ssh/config` | That is Tailscale's CGNAT range, so **a tailnet already exists somewhere**. |
| `tailscale` not installed | `pacman -Q` | This laptop is not on that tailnet yet. |
| `Host oracle`, `Host runner` | `~/.ssh/config` | Two Oracle Cloud boxes (a bot runner). They could be added to the status feed later. |
| `Host local` → a `10.0.0.x` address | `~/.ssh/config` | A LAN machine (user `bot`). |
| `vpn_profiles.json` + `vpn_autoconnect.py` | hypr / claude | **ProtonVPN** auto-connects on learned SSIDs. It is not a mesh VPN and does not help here. It can also conflict with Tailscale (see §5). |
| `wg`, `wg-quick` installed | `/usr/bin` | WireGuard tooling is present, but there is no config for this use. |
| `cap_gate.py` / `approve_cap.sh` | claude/ | A capability-approval flow already exists. The remote API reuses it for anything risky. |

Important: the "home PC" here is a **ThinkPad that moves between networks** (eduroam, hotel Wi-Fi, ProtonVPN). Port forwarding and "reach home by IP" can't work with that. It has to be an outbound-initiated mesh.

---

## 1. Transport: recommendation

### Options

| | Tailscale mesh | VPS relay built from scratch (reverse SSH / WS relay) | Headscale (self-hosted Tailscale control) |
|---|---|---|---|
| VPS work | ~0 (just `tailscale up` on it) | Relay service, TLS, auth, reconnect logic, and keeping it maintained | One more container on basecamp |
| NAT/eduroam traversal | Built in (DERP fallback) | Works because the laptop dials out, but you build it yourself | Same as Tailscale |
| Phone app | Official app | Browser only, or build one | Official app pointed at a custom server |
| Phone → laptop latency | Direct peer-to-peer | Always hairpins through the VPS | Direct |
| Third-party dependency | Tailscale Inc. + your IdP | None | None (clients are OSS) |
| New public attack surface | **None** | A public relay endpoint | A public control-plane endpoint |

### Recommendation: **Tailscale now, Headscale later only if you want to drop the dependency.**

You said "shouldn't be that hard". Tailscale is the only option where that holds. There's a tailnet already (`roam`), so you add 4 devices and you're done: laptop, Windows PC, phone and the netcup VPS. After that, every device can reach every other one on a stable `100.x` IP or MagicDNS name without opening any port anywhere. The VPS stops being a required relay. It becomes the **always-on hub** that holds state while the laptop is asleep or roaming.

A relay built from scratch means writing and maintaining exactly what Tailscale already provides, and it's worse at it: it adds public attack surface and every packet hairpins through the VPS. Don't build it.

Headscale is a clean later swap because the clients stay the same. Consider it only if Tailscale's account model bothers you (§5).

---

## 2. What "control the PC from the phone" means

### Two very different risk tiers. Keep them separate.

- **Tier A: scoped API.** A small daemon on the laptop exposes a curated allowlist of actions that **already exist** in `qs_mcp.py` (66 `t_*` tools). The phone can only do what's on the list. If it's compromised, the worst case is someone skipping your song, changing your wallpaper or locking your screen.
- **Tier B: SSH from the phone.** Full shell. If it's compromised, they own the laptop. It's still useful for emergencies, but it's a separate path with separate controls (§5). It does not go through the web UI.

### v1 scope: `qs-remote`

A Python daemon on the laptop, under `scripts/quickshell/claude/qs_remote.py`. It imports `qs_mcp.py` the same way `vpn_autoconnect.py` does, so there's one source of truth. It runs via `lifeline.sh` and starts from `exec.conf`.

- **Binds only to the Tailscale interface.** Put it behind `tailscale serve` (tailnet-only HTTPS plus identity headers). It never binds to `0.0.0.0`.
- Serves a single-file PWA (vanilla JS, matugen colors read from `qs_colors.json`) plus a JSON API: `GET /state`, `POST /action/<name>`.

| Tier | v1? | Actions (existing `t_*` tools) |
|---|---|---|
| **A0 read** | yes | `system`, `music`, `workspaces`, `workspace_status`, `focus`, `events`, `tasks`, battery and eco state |
| **A1 benign actuators** | yes | `media_control`, `set_volume`, `toggle_mute`, `mic_mute`, `open_widget`, `set_wallpaper`, `night_light`, `set_brightness`, `notify`, `show_card` (push a resident card to the desktop from the phone), `add_task`, `reminder`, `power_profile`, **lock** (`lock.sh`), `mailbox_post` |
| **A2 sensitive** | **no.** Later, and only behind `cap_gate` desktop approval | `screenshot`, `record_screen`, `clipboard_control`, `window_control`, `app_open`, `browser_*`, `systemd_service`, `vpn_control`, `wifi_control`, suspend/poweroff |
| **Never over the API** | never | `input_control`, `file_ops`, `process_control`, `browser_eval`, `keybind`, anything that takes a free-form shell string |

For A2, reuse the existing `cap_gate.request()`/`approve_cap.sh` flow: the phone asks, a resident card appears on the desktop, and you approve it there. That's only useful when someone is sitting at the laptop, which is exactly when it's safe.

Every actuation writes to an audit log (`~/.local/state/qs-remote/audit.jsonl`) and pops a small `low`-urgency resident card, e.g. "phone: volume → 40". Anything done remotely is then visible on the desktop.

---

## 3. Windows PC status feed

### Transport: push to a hub on the VPS, over the tailnet

Push to the hub instead of having the laptop poll Windows directly:

- The laptop sleeps and roams. Something always-on has to remember "Windows last seen 3 days ago".
- The phone wants the same view even when the laptop is off.
- There's one ingest pattern for every device. Later, the laptop, the Oracle boxes and the VPS itself all push the same way.

### Hub: `fleet` container on basecamp

- A tiny FastAPI container (same stack as `panel-app`) with SQLite (latest snapshot per device plus 7 days of 1-minute rollups).
- It's published **only on the VPS's tailscale IP** (`ports: "100.x.x.x:8780:8780"`). It is **not** routed through Caddy and not public.
- Endpoints:
  - `POST /ingest/<device>`: a bearer token per device, which can only write its own device.
  - `GET /fleet`: all devices, last-seen and stats.
  - `GET /`: the fleet PWA view for the phone.
- The VPS reports its own stats as a device. Docker container status comes from the panel's existing vps-mode data, or from a read-only docker socket proxy. The hub never mounts the raw socket.

### Windows agent: **PowerShell, no installs**

`fleet-agent.ps1`, registered as a **Scheduled Task, "At log on", running as the user** (it must run in the user session to see the foreground window). It runs hidden (`conhost --headless powershell -File ...`) and loops every 30 s:

- CPU: `Get-CimInstance Win32_Processor` → LoadPercentage
- RAM: `Win32_OperatingSystem` (Free/TotalVisibleMemorySize)
- Disk: `Get-Volume`
- Uptime: `LastBootUpTime`
- GPU: optional, via `nvidia-smi` if present
- Idle seconds: `GetLastInputInfo` via `Add-Type`
- Foreground app: `GetForegroundWindow` → process name only, not the window title (the title leaks too much)

It then runs `Invoke-RestMethod -Method Post http://<vps-magicdns>:8780/ingest/windows -Headers @{Authorization="Bearer $tok"}`. The token lives in a DPAPI-protected file (`Export-Clixml`), not in the script.

The agent is **push-only and accepts no commands.** Remote control of Windows is explicitly out of scope for v1. If you want it later, use the same tiered-API idea with a Windows-side allowlist, never WinRM or RDP exposure.

The phone can push too, optionally: Android HTTP Shortcuts/Tasker, or an iOS Shortcuts automation, sends battery % to `/ingest/phone`. Tailscale presence alone already gives online/offline.

---

## 4. Plugging into the rice (illustrative)

- **`fleet_watch.py`** (through `lifeline.sh`): polls `GET /fleet` every 15 s, but only when the tailnet is up. It writes `/tmp/qs_fleet.json` and the bar watches that with the usual `inotifywait` + `cat` idiom. It also pushes the laptop's own heartbeat to `/ingest/laptop`.
- **TopBar "Fleet" pill:** a compact dot per device (online/stale/offline), styled like the stats chips. Its hover card follows the `volTip`/`batTip` pattern, including the input-mask `Region`:
  - one row per device with CPU/RAM/disk bars, uptime, idle time and foreground app
  - for the VPS, container up/down
  - Setting: `topBarFleetMode` (always/occasional/never).
- **Resident producers** (`resident_extras.py`), each with a Guide toggle under a new "FLEET" category:
  - "Windows PC idle 3 days: still on?", with an action to open basecamp
  - "VPS disk 90%"
  - "Minecraft container down"
  - Catch-up card: "Phone locked your screen at 14:02"
- **Guide tab:** optional. Better: a "FLEET" settings category for the hub URL, per-device visibility and the remote-API on/off switch (`qsRemoteEnabled`, default off).
- **MCP:** a `fleet_status` tool in `qs_mcp.py`, so the resident and Claude sessions can answer questions like "is the Windows box on".

---

## 5. Security

| Risk | Concrete mitigation |
|---|---|
| **The Tailscale account is a single point of failure.** Whoever controls the identity provider (Google/GitHub) controls the tailnet. | Hardware key or TOTP on that IdP. Enable **Tailnet Lock** (new nodes need a signature from a trusted node: laptop plus VPS). Turn on device approval. Optionally migrate to Headscale on basecamp later. |
| **Flat tailnet.** By default every node reaches every port on every other node. | Write an ACL policy with tags on day one: `tag:phone` → `laptop:443` (qs-remote) and `vps:8780`. `tag:windows` → `vps:8780` only. `tag:laptop` → `vps:8780,22`. SSH (22) only from `tag:laptop` and `tag:phone`. Deny everything else. The Windows box especially should reach nothing but the hub. |
| **Phone lost or stolen** | Phone lock screen plus biometric lock on the Tailscale app. Recovery takes three steps: remove the node in the admin console, revoke that device's qs-remote token and hub token (one line in each config), then rotate the phone's SSH key. qs-remote also checks the `Tailscale-User-Login`/node identity from `tailscale serve` **in addition to** a bearer token. A stolen token alone from another node gets nothing. Tier A limits the damage anyway: worst case is volume and lock. |
| **Phone SSH (Tier B)** | Use a dedicated ed25519 key per phone with a passphrase (Termux/Termius), stored in the app's secure storage. It gets **no sudo without a password**. Use `from="100.64.0.0/10"` in `authorized_keys` so the key only works over the tailnet. Don't use Tailscale SSH's "accept" mode without check mode. |
| **Basecamp already has public surface** (Caddy, Authelia, Portainer, panel) | **Portainer is root on the VPS**, and it's public behind Authelia. Once the VPS is on the tailnet, move Portainer (and SSH) to tailnet-only. Firewall 22 to `tailscale0` and keep netcup's web VNC console as break-glass. Do **not** add `fleet` or `qs-remote` to Caddy. Never use **Tailscale Funnel** for any of this. |
| **API scope creep** | The allowlist lives in code, not config. There's no endpoint that takes a free-form command string. A2 needs desktop approval via `cap_gate`. Every call goes to `audit.jsonl` plus a desktop card. Rate limit: 10 actions/min per device. |
| **Hub data leak** | The hub stores process names and stats only. No window titles, no screenshots, no clipboard. Retention is 7 days. |
| **ProtonVPN on the laptop** | Proton's kill switch and full-tunnel routing can blackhole `100.64.0.0/10` or break DERP. Test this in Phase 1. If it breaks, exclude the tailnet range or `tailscale0` in the Proton config, or accept that remote control is unavailable while Proton is up (the phone then sees the laptop as offline). |
| **Windows agent token** | The token is scoped to `/ingest/windows` only and protected with DPAPI. If it leaks, the worst case is fake stats for that one device. |

---

## 6. Phased plan

Each phase depends on the one before it unless noted.

1. **Mesh (≈1 h).**
   - Install `tailscale` on the laptop, VPS, Windows and phone, and join them to the **existing** tailnet (see Q2).
   - Write the ACL policy and tags. Enable Tailnet Lock and MFA.
   - Verify: laptop ↔ VPS ↔ phone ↔ Windows pings, including over eduroam and with ProtonVPN on.
2. **Harden basecamp (≈30 min, needs Phase 1).** Move Portainer and SSH to tailnet-only and firewall 22. Confirm netcup console access first.
3. **Hub (≈half day, needs Phase 1).** Add a `fleet` container to basecamp (tailnet-bound), with ingest, fleet endpoints and a minimal phone PWA. The VPS self-reports.
4. **Windows agent (≈1–2 h, needs Phase 3).** `fleet-agent.ps1` plus the Scheduled Task and DPAPI token.
5. **Rice integration (needs Phase 3).** `fleet_watch.py` → `/tmp/qs_fleet.json` → Fleet pill and hover card, `fleet_status` MCP tool, laptop heartbeat.
6. **`qs-remote` Tier A (≈half to one day, needs Phase 1 only; can run in parallel with 3–5).** A0 + A1 allowlist, `tailscale serve`, PWA, audit log, desktop cards.
7. **Resident producers (needs Phase 5).** Idle-Windows, VPS disk and container-down cards.
8. **Later, optional:** A2 via `cap_gate`, phone push heartbeat, Oracle boxes as fleet devices, Headscale migration, Windows Tier A.

---

## 8. Native Android app, file relay, Kahoot-photo-answer (added 2026-10-01, plan only)

Confirmed available on this machine: Android SDK at `~/Android/Sdk` (platforms 35/36, build-tools, cmdline-tools, platform-tools/adb present), Java 26 (`java`/`javac`). No `gradle`/`kotlinc` on PATH — use the Gradle wrapper (`./gradlew`, bootstraps itself, no global install needed) and Kotlin via the Android Gradle Plugin rather than installing `kotlinc` separately.

### 8.1 Scope decision

User explicitly chose **native Android app** over a PWA, understanding it's a bigger lift than extending the existing `/m` mobile page — dev toolchain, APK build/sign, sideload (no Play Store mentioned). Project should live as its own repo, same pattern as `~/apps/mira` (a separate app directory, not inside `~/.config/hypr`), e.g. `~/apps/fleet-app/` or similar name TBD.

Core screens, mapped to what already exists server-side:
- **Dashboard**: live system/music state (`qs_remote.py`'s `/state`), fleet view (VPS `/fleet` once Phase 5 lands) — all devices, online/stale/offline.
- **Controls**: the existing Tier-A actuator list (media, volume, mute, wallpaper, night light, brightness, lock, notify/show_card) — same allowlist as `/m`, just a real UI instead of button-links.
- **File/photo send**: see §8.2.
- **Kahoot-answer capture**: see §8.3.

Auth: reuse the existing bearer token (`~/.local/state/qs-remote/token`) for laptop calls; a separate per-device token for the VPS fleet hub's `/ingest`/relay endpoints once those exist (Phase 2/5 territory, already flagged to the hardening/fleet agents).

### 8.2 File/photo relay via VPS ("all directions" — phone↔laptop, through basecamp)

Don't peer-to-peer this (NAT/background-app complexity on Android for receiving unsolicited connections) — push through the VPS fleet hub as a relay/drop, consistent with the doc's existing "push to a hub, not direct polling" philosophy (§3).

Proposed shape, extending the existing `fleet` FastAPI container (`/opt/services/fleet/app/app/main.py`):
- `POST /relay/{device}` — multipart upload, same per-device bearer token model as `/ingest/{device}`, stores to local disk on the VPS (short retention, e.g. 24-48h, this is a relay not permanent storage) keyed by a generated drop id.
- `GET /relay/{device}` — list pending drops for a device (polled by whichever side is the receiver, or pushed via the same fleet-watch poll cadence already being built for Phase 5).
- `GET /relay/{device}/{drop_id}` — fetch the actual file.
- Laptop side: `qs_remote.py` gets a new `POST /action/receive_file` style endpoint, or (simpler) `fleet_watch.py` (being built right now for Phase 5) also polls `/relay/laptop` on its existing 15s cadence and saves drops to a watched directory, firing a resident card ("New file from phone: photo.jpg — Open / Save").
- Phone app side: a share-sheet target ("Share to Fleet") plus an explicit in-app file picker, both POST to `/relay/laptop`.

Security: same tier-A-style allowlist thinking — cap file size (a few MB, this is for photos/small files not bulk transfer), scan nothing fancy needed since it's bearer-token-gated and tailnet-only, but do rate-limit uploads per device same as the existing `ACT_PER_MIN`/`READ_PER_MIN` pattern in `qs_remote.py`.

### 8.3 Kahoot-answer capture (confirmed design: reuse shot_answer + named prompts)

This is NOT new capability — it's the existing `SUPER+CTRL+Z` screenshot-answer pipeline (`claude/shot_answer.py`, vision-based, already supports named/switchable prompts via `claude/shot_prompts.py` built earlier this session for the GeoGuessr use case) with a new input path and a new saved prompt.

Flow:
1. User has Kahoot open on the laptop screen (the actual quiz, in a browser).
2. Phone app camera captures a photo of the question + answer choices (as shown on a shared screen, projector, or someone else's device — whatever the real viewing setup is).
3. Photo uploads via the same relay path as §8.2 (`POST /relay/laptop`, or a dedicated `POST /action/kahoot_answer` on `qs_remote.py` directly, skipping the generic relay for lower latency since this is explicitly latency-sensitive).
4. Laptop-side handler runs the photo through `shot_answer.py`'s existing vision pipeline with `shot_prompts.py activate kahoot` (new saved prompt: "This is a Kahoot question with multiple choice answers. Identify the question and answer options from the image, determine the correct answer, respond with ONLY the correct answer text, as fast and concisely as possible" — tune wording later, speed matters more than explanation here unlike the GeoGuessr prompt).
5. Answer routes back to the phone fast — NOT via the Stage dock (that's for desktop narration, wrong device) — either as a direct HTTP response to the app's upload call (simplest, lowest latency, no polling needed) or a push-style follow-up if the vision call takes a few seconds and the app wants to show a spinner then result.

Latency matters here more than any other feature in this plan — Kahoot's answer window is short. Test real round-trip time (photo upload → vision inference → response) before assuming it's fast enough to be useful; if Haiku-tier vision is too slow, that's a real constraint to flag back to the user rather than silently shipping something too slow to use.

### 8.4 Suggested build order (not started — sequence for whenever this gets picked up)

1. VPS relay endpoints (§8.2) — small, server-only, no app needed yet to test (curl-testable).
2. Kahoot prompt + direct `qs_remote` endpoint (§8.3) — also curl-testable before any app exists, reuses everything already built.
3. Android app shell (auth, dashboard reading `/state`, Tier-A controls) — the actual multi-session native-app build effort.
4. Android app: file send (share-sheet + picker) wired to §8.2.
5. Android app: Kahoot capture screen (camera → §8.3 endpoint → fast result display) wired last, once the backend latency is already validated from step 2.

---

## 7. Open questions only the user can answer

1. **Is `netcup-vps` (basecamp) "the VPS"?** Local evidence says yes, but that's unconfirmed. Should the hub go there, or do you want it isolated from the game-server box?
2. **Whose tailnet is `roam` on, and what is `roam`?** Join that tailnet or start a fresh one? Which IdP does it log in with, and does it have MFA?
3. **Is Tailscale-the-company acceptable,** or go straight to Headscale on basecamp?
4. **Phone OS** (Android or iOS)? This decides Termux vs Termius and Tasker vs Shortcuts for the phone heartbeat.
5. **Is the Windows PC always on,** or only on while gaming? This changes what "idle 3 days" should mean.
6. **Does ProtonVPN need to stay on while remote control works,** or is "offline while on Proton" fine?
7. **Should `oracle`, `runner` and `local` (the LAN `bot` box) be part of the fleet view?**
8. **v1 actuator list:** does anything in A1 feel too much (e.g. `set_wallpaper`, `power_profile`), or is anything missing?
