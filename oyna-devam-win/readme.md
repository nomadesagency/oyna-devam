# oyna-devam-win — run long Claude Code tasks without being stopped by usage limits (Windows version)

> **Provided "as is", without warranty; use at your own risk. Read `NOTICE.txt` before installing.** Independent project, not affiliated with Anthropic.

This is the Windows counterpart of the `oyna-devam-mac` folder (macOS). Same logic, same commands; only the Windows-specific parts (PowerShell, Task Scheduler, power settings) differ.

> **Important — status:** this version has **not yet been tested on a real Windows computer** (it was developed on macOS; the macOS version has been used and works). The logic (settings, profiles, hooks, limit reading, waiter flow, prompts, install/uninstall) was exercised under PowerShell 7 on macOS; the Windows-only calls (Task Scheduler wake task, suspend, display off, power settings) could not be run there. The scripts were written carefully and reviewed, but on first use please give it a **small trial task** and check the output of `oyna-devam.cmd doctor`. If something goes wrong, `log.txt` (see below) shows why. The 2026-10-25 update (robust reset-time parsing, bounded `/usage` reads, approval-gate rule, doctor reset check) was executed and checked under PowerShell 7 on macOS (parser, reset-time formats, hook flow, doctor, prompt, install/uninstall) but not on Windows itself or Windows PowerShell 5.1: after installing, run `oyna-devam.cmd doctor` and confirm that the `limit readable` line shows a reset time.

You give Claude Code a long task. When the 5-hour usage limit is about to run out, the system:

1. tells Claude to "bring the half-done work to a consistent point, write a note to `progress.md`, and stop",
2. waits 120 s for cloud sync (Google Drive etc.),
3. **creates a wake task for the moment the limit resets** (Task Scheduler, with "wake the computer" set) and suspends the computer,
4. on wake, **resumes the same session** in a visible PowerShell window (progress streams live),
5. repeats this loop until Claude says `done`; then it goes back to inactive (it stays installed) and, in the Away profile, suspends the computer.

It has two profiles: **Away** (you leave the computer; display dark, computer suspends at the limit and at the end) and **Working** (you keep using the computer; nothing suspends, the display stays on, the limit wait happens while the computer stays awake).

A step-by-step user guide (Turkish) is in `Oyna Devam - Windows Kullanım Kılavuzu.pdf`.

---

## 1. Install (once per computer)

Requirements: **Windows 10/11**, Claude Code (VS Code extension **or** terminal; on Windows Claude Code itself needs Git for Windows) and a logged-in account. PowerShell ships with Windows; no extra tools such as `jq` are needed.

1. Copy the `oyna-devam-win` folder to your computer.
2. Double-click **`install.bat`**. (Or in PowerShell: `powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1`)
3. In the health check that follows, every line should start with `[ok]`.
4. Reload the window in VS Code (or open a new `claude` session).

The installer (safe to run again): copies the scripts to `%USERPROFILE%\.claude\oyna-devam\`; adds 4 hooks and one permission rule for `oyna-devam.ps1` to `%USERPROFILE%\.claude\settings.json` (backed up first, only the 3 newest backups are kept); tries to enable "wake timers". **No administrator password is needed.**

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

**Approval gates are never skipped.** The ready-made text tells Claude: if a project rule needs your explicit approval before an action (deleting, publishing, sending, paying, changing protected files), it must not assume approval. It finishes everything else, runs `powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/oyna-devam/oyna-devam.ps1" blocked "approval needed: <what>"` and stops; the system then switches itself off, so nothing irreversible happens while you are away. Approve the step yourself and continue in a new session from `progress.md`.

**Approvals: Auto mode.** So that nothing waits for a click, tasks run in Claude Code's **Auto** permission mode: Claude runs commands by itself and a separate safety classifier blocks risky ones (force pushes, `curl | bash`, production deploys...). The system opens the resumed session in Auto mode by itself, and the installer adds a permission rule so the system's own `oyna-devam.ps1` command never prompts. **One thing is yours to choose:** start the session in which you paste the text in **Auto mode** (mode picker next to the chat box in VS Code, or Shift+Tab in the terminal) — the system cannot change the mode of an already-open session. If the classifier blocks a step, Claude skips it and carries on. Advanced: `-Mode bypassPermissions` skips the classifier too and the installed PreToolUse hook then approves every call of the bound session (only while a task runs); use it only for folders/tasks you trust. `-Mode acceptEdits` brings normal prompts back.

Fixed settings in the texts: limit threshold 90 %, permission mode `auto`, resume mode `stream`. Advanced users can change them in the `on ...` line of the text or generate a text from the command line (section 3).

> To check the installation: `oyna-devam.cmd doctor`

### How the session resumes after waking (`-Resume`)

| Mode | What you see | Notes |
|---|---|---|
| `stream` (**default**) | Live readable stream in a PowerShell window (`[message]`, `[tool]`, `->` result, `[turn finished]`) | Fully automatic; no approval dialog |
| `terminal` | The interactive `claude` session | The first time you may have to accept the "bypass permissions" warning by hand |
| `vscode` | Opens the session in the VS Code Claude panel | **Experimental**; the prompt may not be sent automatically |
| `headless` | No window; output goes to `resume-run.log` | Progress is invisible |

## 3. Commands

```
oyna-devam.cmd on [-Project DIR] [-Threshold 90] [-Mode auto] [-Resume stream] [-Profile away|working] [-Watch]
oyna-devam.cmd done | blocked "reason" | off | cancel | status | watch | doctor | reset
oyna-devam.cmd prompt "task"  [-TaskFile F] [-Threshold N] [-Mode M] [-Resume R] [-Profile away|working] [-NoWatch]
```

Advanced options for `on`/`prompt`: `-Mode` (`auto` default, `bypassPermissions`, `acceptEdits`, `default`, `plan`), `-Threshold N` (limit threshold in %, default 90), `-Resume` (see below), `-NoWatch`. You normally never type any of these: Claude runs `on` / `done` / `blocked` itself (see the ready-made texts in section 2).

Environment variables: `OYNA_DEVAM_HOME` (install dir), `OYNA_DEVAM_CLAUDE_BIN` (path to the claude binary), `OYNA_DEVAM_SYNC_DELAY` (cloud-sync wait in seconds, default 120), `OYNA_DEVAM_WAKE_MARGIN`, `OYNA_DEVAM_USAGE_TIMEOUT` (seconds to wait for `/usage`, default 60), `OYNA_DEVAM_USAGE_FIXTURE` (testing: read a text file instead of calling claude), `OYNA_DEVAM_DRY=1` (testing: no real suspend).

## 4. Windows-specific notes

- **Wake task (Away profile only):** the system creates a one-time task named `ClaudeOynaDevamWake` (visible in Task Scheduler). For it to work, **"Allow wake timers" must be Enabled** in your power plan; `install.bat` tries to set this and `doctor` checks it.
- **Laptops with Modern Standby (S0)** may not wake from a timer during suspend. In that case the computer stays suspended until you wake it, and then it continues. For the most reliable result keep it plugged in; if suspending fails the system simply stays awake and waits.
- **Suspend (not hibernate)** is used.
- **Script execution policy:** every command is called with `-ExecutionPolicy Bypass`, so you do not need to change your system settings.
- **SmartScreen / downloaded file warning:** if the `.bat` shows "Windows protected your PC", choose "More info → Run anyway", or right-click the file → Properties → "Unblock".
- **One active task at a time:** the limit is account-wide, so this is deliberate.
- Auto mode has a safety classifier, but it "reduces permission prompts and does not guarantee safety" (Claude Code docs). Auto mode needs a supported model/plan and can be disabled by an organization (then the session falls back to normal prompts). `-Mode bypassPermissions` has no classifier at all: use it only for tasks you trust.

## 5. Troubleshooting

| Symptom | Fix |
|---|---|
| `doctor`: "claude not found" | `setx OYNA_DEVAM_CLAUDE_BIN "C:\path\claude.exe"` and open a new window (VS Code extension: `%USERPROFILE%\.vscode\extensions\anthropic.claude-code-*\resources\native-binary\claude.exe`) |
| Only the Claude **desktop app** is installed, `claude not found` | The scripts look in `%APPDATA%\Claude\claude-code\<version>\claude.exe` and, for Microsoft Store (MSIX) installs, in the real location `%LOCALAPPDATA%\Packages\Claude_<id>\LocalCache\Roaming\Claude\claude-code\<version>\claude.exe` (both taken from public bug reports, not verified on a machine). If it is still not found, install the CLI with the official installer (`irm https://claude.ai/install.ps1 \| iex`) — it lands in `%USERPROFILE%\.local\bin\claude.exe` |
| `doctor`: `limit readable ... RESET TIME was not understood` | The percentage is read but the reset time could not be parsed. The system still works: it stores a safe estimate (now + 5 h, the latest possible reset), so it wakes at the latest possible moment instead of the exact one. The raw `/usage` line is in `log.txt` (`WARNING reset time not understood`); the parser is in `system/usage-refresh.ps1` |
| `doctor`: wake timers disabled | Control Panel → Power Options → Change plan settings → Advanced → Sleep → "Allow wake timers" → Enable (the check looks for English-language powercfg output, so it can be a false alarm on other Windows languages) |
| Nothing triggers | Hooks not loaded: run `doctor`, then reload VS Code |
| No window opened on wake | `type %USERPROFILE%\.claude\oyna-devam\log.txt`; run the resume script by hand: `powershell -File "%USERPROFILE%\.claude\oyna-devam\resume.ps1"` |
| Stop everything | `oyna-devam.cmd off` |
| Nothing above helps | Open this folder in VS Code and ask Claude to fix it: give it `readme.md`, the problem and the last lines of `log.txt` (the Turkish guide has a ready-made text; section 8, "Son çare"). Re-run `install.bat` afterwards |

Log: `%USERPROFILE%\.claude\oyna-devam\log.txt` · hand-over note: `progress.md`

## 6. Uninstall

`uninstall.bat` (double-click) — removes the hooks, the wake task and the files (backs up `settings.json` first). `-KeepData` leaves the log/progress files.

## 7. Folder contents

```
oyna-devam-win/
  task-prompt-away.txt      READY-MADE prompt, Away profile: write your task in, paste into a new session
  task-prompt-working.txt   READY-MADE prompt, Working profile
  readme.md                 this file
  NOTICE.txt                disclaimer: provided as is, what it changes on your computer, no affiliation with Anthropic
  Oyna Devam - Windows Kullanım Kılavuzu.pdf   step-by-step user guide (Turkish), for sharing
  install.bat / install.ps1       installer
  uninstall.bat / uninstall.ps1   uninstaller
  system/                   copied to %USERPROFILE%\.claude\oyna-devam\
    oyna-devam.ps1  oyna-devam.cmd    main command (+ shortcut)
    common.ps1              shared functions (incl. session binding)
    hook-pretooluse.ps1  hook-posttool.ps1  hook-stop.ps1  hook-stopfailure.ps1
    suspend-and-resume.ps1  final-suspend.ps1  usage-refresh.ps1  keepawake.ps1  dark-guard.ps1  (keeps the display off in the Away profile, max 120 s on)
    watch.ps1  format-stream.ps1
    task-template.md        task prompt template
```
