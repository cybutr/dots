# Claude Desktop Integration — Build Backlog

Research pass: 2026-06-27. Ordered by priority.

---

## Do First (high signal, small effort)

### #5 deep-work-guard `S`
Extend `focus_insight.py`. Watches active window during a focus session; when you switch to a distraction app (discord/youtube/steam), fires a gentle Haiku nudge with a "back to work" `hypr dispatch` button. Cooldown 600s. Uses existing `SUGGEST`/`surface()` pattern.

### #1 notif-action-extract `S`
Extend `claude_resident.py` `detect()`. Pre-filter notification body with regex (OTP pattern, date/time, tracking number). If matches, Haiku call → structured `{type, value, suggested_action}`. Surfaces one-click card: "Copy 449302" / "Add 'Dentist Thu 3pm' to calendar". Uses existing `surface_card`.

### #7 clip-smart-transform `M`
New `claude/clip_watch.py` + autostart. Watches clipboard (`wl-paste --watch` or cliphist). Classifies locally (JSON / stacktrace / code / foreign-language / long-prose / URL). On open, surfaces "paste+" card with 3-4 context-relevant transform buttons (format/translate/summarize/explain) — each button does a Haiku call + `wl-copy result`. Piggyback #8 on same watcher.

### #4 resume-context `M`
New `claude/resume_watch.py` + autostart. Hooks `lock.sh` end (or watches hyprlock exit via `inotify` on a lockfile). Reads `focus.project` + focus DB. Haiku: "Back in Chambers (Map.Mountains.cs) — 40min before you left." Surfaces as SUGGEST card. TTL 120s.

### #17 project-context-dock `M`
New `claude/project_watch.py` + autostart. Watches `focus.project` changes in `/tmp/qs_context.json` (inotify). On change: full agent auto-turn → updates pinned "Project" card (board "Project") with git status, recent branches, open TODOs via `show_card`/`update_card`. Debounce 10s.

---

## Then (medium effort, solid daily value)

### #12 meeting-prep `M`
Upgrade existing `event_` branch in `claude_resident.py`. Trigger: `5 <= mins_until <= 15` AND not already prepped this event. Full agent async turn: pulls related Vivaldi tabs + recent files + prior notes → pinned prep card (board "Meetings"). Add `state["prepped"][event_id]` guard.

### #8 clip-error-explain `S`
Piggyback on #7's `clip_watch.py`. Pattern-match for stacktrace / non-zero exit shape. Haiku → one-line cause+fix. Card with "Ask Claude" that writes `claude:<trace>` to `/tmp/qs_widget_state`.

### #9 resource-hog-explain `S`
`claude_resident.py` detect branch. `ctx.proc.top.cpu > 80` for 2 consecutive polls. Haiku names the process plainly, says if it's normal. Card: "kill it" (`process_control`) / "leave it". Uses existing `state["prev_hog"]` pattern.

### #14 overdue-reschedule `M`
`claude_resident.py` detect branch (upgrade existing overdue branch). Compute free calendar gaps locally. Haiku proposes a slot given overdue tasks + gaps. One-line card + "block it" button.

### #13 task-breakdown `S`
Wrap `t_add_task` in `qs_mcp.py`. After task added with title >= 4 words, Haiku breaks into first action + up to 3 subtasks (JSON). Card: "add subtasks?" with accept/skip buttons (`add_task` MCP call).

---

## Nice-to-Have

### #3 notif-digest `M`
New `claude/notif_digest.py`. Timer 60min OR when focus active. Haiku folds N low-priority notifications into 2-line summary card. Suppress during focus mode.

### #6 end-of-day-review `M`
Fold into `claude_resident.py` (like `maybe_brief`). Trigger: first poll after configurable EOD hour (default 18:00), once/day. Full agent: focus stats + completed tasks + tomorrow's first event → pinned "Day" card.

### #10 screenshot-action `M`
Hook end of `screenshot.sh`. New `claude/shot_action.py`. Vision-capable model classifies screenshot (error/text/UI). Surfaces matching one-action card: OCR/explain/annotate. Silent if nothing actionable.

### #11 focus-soundtrack `S`
Extend `focus_insight.py`. Trigger: focus session starts + nothing playing + `settings.musicSuggest=true`. Haiku suggests vibe (time-of-day + project type). Card with `media_control` play button. Off by default.

### #15 unknown-wifi `S`
New `claude/net_watch.py`. Polls SSID via `sys_info`. On new SSID not in known set: Haiku one-line risk note (open/public/captive). Card with VPN button. Save known set to state file.

### #16 connectivity-troubleshoot `M`
`claude_resident.py` detect. `system.wifi` drops for 2 polls while active. Full agent: runs `wifi_control status/list`, ping, checks DNS, proposes single most-likely fix card.

### #18 wake/return summary `S`
`claude/resume_watch.py` (shared with #4). Detect suspend via `now - state.last_poll > 300`. Haiku folds accrued notifs + mailbox into one "while you were gone" card.

### #2 notif-reply-draft `S`
`claude_resident.py` detect. App in `MSG_APPS` (signal/telegram/discord/vivaldi) + question-shaped body. Haiku drafts 1-line reply. Card: "copy reply" (`wl-copy`) + "chat about it" (`claude:<context>`).

---

## Deferred — do NOT build yet

### #19 tts-voice-output `M` — HOLD, user mostly mute at the PC, no speech output wanted right now
Piper TTS swap-in for `claude_say.py`/resident nudges (replace espeak). Natural voice + barge-in (interrupt playback on new wake-word hit — needs VAD/turn-taking signal, not just an energy threshold). Revisit only when voice output is actually wanted.

### #20 personal-stt-finetune `M` — proposed 2026-07-03, training plan in chat
Adapt the STT model in `voice/stt_server.py` (faster-whisper) to the user's own voice/accent to cut wake-word and transcription errors. Ranked options: (1) fine-tune Whisper via HF `transformers` + LoRA on 30-60min self-recorded audio — cheapest GPU cost, best accuracy/effort ratio; (2) swap base model size (small→medium/distil-large-v3) for headroom before finetuning is needed; (3) NeMo/Parakeet if latency becomes the bottleneck instead of accuracy. Needs a recording+alignment pipeline first.

---

## Infrastructure notes
- New autostart watchers: use PID-guard pattern from `focus_insight.py`. Register in `exec.conf`.
- Triggers already in `/tmp/qs_context.json` (#1 #2 #9 #14): add `detect()` branches in `claude_resident.py`, avoid new scripts.
- New file-based triggers (#4 #7 #15 #17 #18): separate watcher scripts.
- All surface via `surface()`/SUGGEST → topbar dot + `_expire_passive` lifecycle for free.
