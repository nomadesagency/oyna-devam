# oyna-devam-mac — run long Claude Code tasks without being stopped by usage limits (macOS)

> **Provided "as is", without warranty; use at your own risk. Read `NOTICE.txt` before installing.** Independent project, not affiliated with Anthropic.

You give Claude Code a long task. When the 5-hour usage limit is about to run out, the system:

1. tells Claude to "bring the half-done work to a consistent point, write a note to `progress.md`, and stop",
2. waits 120 s for cloud sync (Google Drive etc.),
3. (Away profile) suspends the computer and **schedules a wake for the moment the limit resets** (`pmset schedule wake`); (Working profile) keeps the computer awake and just waits for the reset,
4. on wake, **resumes the same session** in a visible Terminal window (progress streams live),
5. repeats this loop until Claude says `done` (or hits a blocker),
6. when the task is finished it goes back to inactive (it stays installed) and, in the Away profile, suspends the computer.

It has two profiles: **Away** (you leave the computer; display dark, computer suspends at the limit and at the end) and **Working** (you keep using the computer; nothing suspends, display stays on). Installing and removing are one double-click each; to use it on another Mac, copy the folder and install the same way.

A step-by-step user guide (Turkish) is in `Oyna Devam - Mac Kullanım Kılavuzu.pdf`. For the Windows version see the `oyna-devam-win` folder.

---

## 1. Install (once per computer)

Requirements: **macOS**, `jq` (built into macOS 15 Sequoia and newer; on older macOS `brew install jq`), Claude Code (VS Code extension **or** CLI) and a logged-in account.

Double-click **`install.command`** (right-click → Open if macOS warns about an unidentified developer). Only your Mac password is asked, once. (Terminal alternative: `bash install.sh`.)

The installer does the following (safe to run again):

| Step | What it does |
|---|---|
| 1 | Copies the scripts in `system/` to `~/.claude/oyna-devam/` |
| 2 | Adds 4 hooks (PreToolUse, PostToolUse, Stop, StopFailure) and one permission rule for `oyna-devam.sh` to `~/.claude/settings.json` (backed up first: `settings.json.oyna-devam-backup-...`; only the 3 newest backups are kept). |
| 3 | Asks for `sudo` once: installs `/etc/sudoers.d/claude-oyna-devam`, a rule that lets only `pmset schedule wake` and `pmset schedule cancel wake` run without a password. Can be skipped with `--no-sudo`; then the computer is **not** suspended, it stays awake and resumes when the limit resets |
| 4 | Runs `oyna-devam.sh doctor` as a health check |

After installing, reload the window in VS Code (or open a new `claude` session) so the hooks take effect.

**Moving to another computer:** copy the `oyna-devam-mac` folder (Drive, USB, AirDrop — anything) and run `bash install.sh` there. Nothing user- or path-specific is stored in the folder; paths are computed at install time.

## 2. Use — pick a profile, write the task, paste

You never type a command. There are **two ready-made texts**, one per profile:

| Profile | File | Use it when | What the system does |
|---|---|---|---|
| **Away** | `task-prompt-away.txt` | You leave the computer alone | The display is switched off right away (not optional). When the limit fills up the computer **suspends** and wakes itself when the limit resets; the display is turned off again 120 s after the wake. If you wake the display yourself before the task is finished it is turned off again after at most 120 s. When the task is done the computer **suspends** (after 120 s) |
| **Working** | `task-prompt-working.txt` | You keep using the computer for other work while the task runs in the background | The display stays on and the computer **never suspends** — not at the limit, not at the end. When the limit fills up it only records when the limit resets, keeps waiting and carries on by itself. The progress window opens in the background without taking focus |

**1.** Open the file of your profile (any text editor).
**2.** Replace the line `<<< WRITE YOUR TASK HERE / GÖREVİ BURAYA YAZIN ... >>>` with your task. Do not touch the rest.
**3.** Paste the whole text into a **new** Claude Code session in the folder where the task should run, and send it.

As its first step Claude switches the (pre-installed, otherwise inactive) system on and **binds that session** (other sessions are not affected). A live status window opens and Claude prints a short `STATUS:` line after each meaningful step. When the task is finished Claude says `done`: the system goes back to inactive (it stays installed) and, in the Away profile, the computer suspends after 120 s.

**Approvals: Auto mode.** So that nothing waits for a click, tasks run in Claude Code's **Auto** permission mode: Claude runs commands by itself and a separate safety classifier blocks risky ones (force pushes, `curl | bash`, production deploys...). The system opens the resumed session in Auto mode by itself, and the installer adds a permission rule so the system's own `oyna-devam.sh` command never prompts. **One thing is yours to choose:** start the session in which you paste the text in **Auto mode** (mode picker next to the chat box in VS Code, or Shift+Tab in the terminal) — the system cannot change the mode of an already-open session. If the classifier blocks a step, Claude skips it and carries on. Advanced: `--mode bypassPermissions` skips the classifier too and the installed PreToolUse hook then approves every call of the bound session (only while a task runs); use it only for folders/tasks you trust. `--mode acceptEdits` brings normal prompts back.

**Approval gates are never skipped.** The ready-made text tells Claude: if a project rule needs your explicit approval before an action (deleting, publishing, sending, paying, changing protected files), it must not assume approval. It finishes everything else, runs `bash ~/.claude/oyna-devam/oyna-devam.sh blocked "approval needed: <what>"` and stops; the system then switches itself off, so nothing irreversible happens while you are away. Approve the step yourself and continue in a new session from `progress.md`.

Fixed settings in the texts: limit threshold 90 %, permission mode `auto`, resume mode `stream`. Advanced users can change them in the `on ...` line of the text or generate a text from the command line (section 3).

> To check the installation: `bash ~/.claude/oyna-devam/oyna-devam.sh doctor`

### Seeing progress — resume modes

After waking, the session is resumed in one of these ways (`--resume`):

| Mode | What you see | Notes |
|---|---|---|
| `stream` (**default**) | Live readable stream in Terminal: `💬 message`, `🔧 Bash: ...`, `↳ result`, `■ turn finished` | Fully automatic; no permission/approval dialog. Keeps the same session id |
| `terminal` | The interactive `claude` session (Claude's normal UI) | The first time you may have to run `claude --permission-mode bypassPermissions` by hand and accept the "bypass" warning; otherwise it waits at the approval dialog |
| `vscode` | Opens the session in the VS Code Claude panel (`vscode://anthropic.claude-code/open`) | **Experimental**: the prompt is typed into the box but may not be sent automatically (Enter may be needed). Not recommended for unattended runs |
| `headless` | No window; output goes to `~/.claude/oyna-devam/resume-run.log` | Progress is invisible |

> While the computer suspends the VS Code chat panel only shows the session that was open. The resumed session uses the same conversation history, but the live stream is in the Terminal window. When the task is done, closing the chat in VS Code and re-opening the same session from the history shows all turns.

## 3. Commands

```
oyna-devam.sh on [--project DIR] [--threshold 90] [--mode acceptEdits] [--resume stream|terminal|vscode|headless]
            [--profile away|working] [--watch]         turn the system on and bind the session
oyna-devam.sh done               task-finished flag (Claude runs it) -> system turns off; Away profile: final suspend starts
oyna-devam.sh blocked "reason"   unresolvable blocker (Claude runs it) -> system turns off, notification
oyna-devam.sh off                turn the system off now and cancel any pending suspend
oyna-devam.sh cancel             cancel only the pending suspend/wake job
oyna-devam.sh status             short status + last log lines
oyna-devam.sh watch              live status board
oyna-devam.sh doctor             installation / dependency / permission check
oyna-devam.sh reset              reset working state (log, progress, flags); installation stays
oyna-devam.sh prompt [--profile away|working] [--task-file F | "task"] ...   generate a task prompt (copies it to the clipboard)

Advanced options for `on`/`prompt`: `--mode` (`auto` default, `bypassPermissions`, `acceptEdits`, `default`, `plan`), `--threshold N` (limit threshold in %, default 90), `--resume` (see below), `--no-watch`. You normally never type any of these: Claude runs `on` / `done` / `blocked` itself (see the ready-made texts in section 2).
```

## 4. How it works (short)

```
Claude Code ──hook──► hook-posttool.sh   when it sees `oyna-devam.sh on` it binds the session;
                                          at limit >= threshold it adds a "LIMIT WARNING" context for Claude
            ──hook──► hook-stop.sh        decides when a turn ends:
                                            DONE/BLOCKED → turn off
                                            limit >= threshold → start suspend-and-resume.sh detached
                                            otherwise "task not finished, keep going" (exit 2)
            ──hook──► hook-stopfailure.sh if the limit filled up unnoticed, still plan a suspend
suspend-and-resume.sh : wait 120 s → pmset schedule wake → pmset sleepnow → after wake wait for the reset
                      → open resume.command in Terminal (same session)
usage-refresh.sh    : reads the limit % and reset time from `claude -p "/usage"` (date+time, time-only and 24 h formats,
                      time zone and year rollover handled; unparsable reset time -> safe estimate now+5h, logged)
```

Key parts: **session binding** (`active.json` → `session`), **limit reading** (the VS Code extension does not run the statusline, so `/usage` is used; the read is time-bounded inside hooks, a stale reading is logged, and the StopFailure hook is the backstop if the limit fills up unnoticed), **runaway-loop guard** (turns off after 300 forced continuations), **caffeinate** (the Mac does not suspend by itself while the task runs; in the Working profile the display is kept on too).

Files live in `~/.claude/oyna-devam/`: `active.json` (settings), `state.json` (limit), `progress.md` (Claude's hand-over note), `log.txt` (event log), `resume.command` (the last generated resume script).

Environment variables: `OYNA_DEVAM_HOME` (install dir), `OYNA_DEVAM_CLAUDE_BIN` (path to the claude binary), `OYNA_DEVAM_SYNC_DELAY` (cloud-sync wait in seconds, default 120), `OYNA_DEVAM_WAKE_MARGIN`, `OYNA_DEVAM_USAGE_TIMEOUT` (seconds to wait for `/usage`, default 60), `OYNA_DEVAM_USAGE_FIXTURE` (testing: read a text file instead of calling claude), `OYNA_DEVAM_DRY=1` (testing: no real suspend).

## 5. Limits and safety

- **macOS only** (`pmset`, `caffeinate`, `date -j`). Linux/Windows need a separate port (Windows: see `oyna-devam-win`).
- **One active task at a time.** The limit is account-wide, so this is deliberate.
- Auto mode has a safety classifier, but it "reduces permission prompts and does not guarantee safety" (Claude Code docs). Auto mode needs a supported model/plan and can be disabled by an organization (then the session falls back to normal prompts). `--mode bypassPermissions` has no classifier at all: use it only for tasks/folders you trust.
- The sudoers rule only lets the two `pmset schedule` commands run without a password; it grants nothing else.
- The sudoers rule and the wake only matter for the Away profile; the Working profile never suspends the computer.
- Keep the lid open while a task runs: closing a MacBook's lid suspends it (the system only prevents idle suspend) and the task stops before the limit is reached. In the Away profile the system turns the display off by itself.
- A wake is not guaranteed on a MacBook with the lid closed on battery; keep it plugged in.
- If you work in a folder such as Google Drive you can change the 120 s sync wait with `OYNA_DEVAM_SYNC_DELAY`.

## 6. Troubleshooting

| Symptom | Fix |
|---|---|
| `doctor`: `no sudo pmset permission` | Run `bash install.sh` (approve sudo). Without it the system does not suspend, it stays awake |
| `doctor`: `claude binary not found` | `export OYNA_DEVAM_CLAUDE_BIN=/path/claude` (VS Code extension: `~/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude`) |
| `doctor`: `limit readable ... RESET TIME was not understood` | The percentage is read but the reset time could not be parsed. The system still works: it stores a safe estimate (now + 5 h, the latest possible reset), so it wakes at the latest possible moment instead of the exact one. The raw `/usage` line is in `log.txt` (`WARNING reset time not understood`); the parser is in `system/usage-refresh.sh` |
| Limit cannot be read | Are you logged in to `claude`? Does `claude -p "/usage"` work by hand? |
| Nothing triggers | Hooks not loaded: run `oyna-devam.sh doctor`, then reload VS Code |
| No window opened on wake | Look at the end of `~/.claude/oyna-devam/log.txt`; you can run `bash ~/.claude/oyna-devam/resume.command` by hand |
| Stuck, I want to drop everything | `bash ~/.claude/oyna-devam/oyna-devam.sh off` |

## 7. Uninstall / reset

Double-click `uninstall.command`, or in Terminal:

```bash
bash uninstall.sh              # removes hooks, files and the sudoers rule (backs up settings first)
bash uninstall.sh --keep-data  # leaves the log and progress files
bash ~/.claude/oyna-devam/oyna-devam.sh reset   # only resets the working state; the installation stays
```

## 8. Folder contents

```
oyna-devam-mac/
  task-prompt-away.txt      READY-MADE prompt, Away profile: write your task in, paste into a new session
  task-prompt-working.txt   READY-MADE prompt, Working profile
  install.command           installer (double-click)
  uninstall.command         uninstaller (double-click)
  readme.md                  this file
  NOTICE.txt                 disclaimer: provided as is, what it changes on your computer, no affiliation with Anthropic
  Oyna Devam - Mac Kullanım Kılavuzu.pdf   step-by-step user guide (Turkish), for sharing
  install.sh                 installer
  uninstall.sh               uninstaller
  system/                    copied to ~/.claude/oyna-devam/
    oyna-devam.sh                 main command (on/off/status/done/blocked/cancel/watch/doctor/reset/prompt)
    common.sh                shared functions (incl. session binding)
    hook-pretooluse.sh  hook-posttool.sh  hook-stop.sh  hook-stopfailure.sh
    suspend-and-resume.sh  final-suspend.sh  usage-refresh.sh
    dark-guard.sh            keeps the display off in the Away profile (max 120 s on)
    watch.sh                 live status board
    format.jq                live-stream formatter
    task-template.md         task prompt template ({{TASK}}, {{THRESHOLD}}, {{MODE}}, {{RESUME}}, ...)
```

To adapt the template to your own work, edit `system/task-template.md` and re-install with `bash install.sh`.
