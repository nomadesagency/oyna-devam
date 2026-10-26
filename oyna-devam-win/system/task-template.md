OYNA DEVAM MODE (Windows)

TASK:
{{TASK}}

SETUP (first thing, before the task):
1. Run `powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/oyna-devam/oyna-devam.ps1" on -Profile {{PROFILE}} -Mode {{MODE}} -Threshold {{THRESHOLD}} -Resume {{RESUME}} {{EXTRA_FLAGS}}`. This turns the (pre-installed, normally inactive) system on and binds THIS session; a live status window opens. {{PROFILE_NOTE}}
2. Check the "current limit reading" line in the command output. If it says "WARNING: could not read the limit", tell me "limit cannot be monitored" and continue the task anyway.

WORKING RULES
1. Work without stopping until the task is finished. Do not ask for approval or stop to ask questions; proceed with reasonable assumptions. The project's own rules (CLAUDE.md, review/approval steps, folder protocols) apply as usual. Reply to me in the language the task is written in. Never assume approval: if a project rule needs my explicit approval before an action (deleting, publishing, sending, paying, changing protected files), do not skip that gate and do not wait for an answer; finish everything else, then run `powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/oyna-devam/oyna-devam.ps1" blocked "approval needed: <what>"` and stop.
2. Keep me informed in this window: after each meaningful step print one short line starting with "STATUS:" (what is done, what is next, roughly how much is left).
3. If you hit a blocker you truly cannot resolve, run `powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/oyna-devam/oyna-devam.ps1" blocked "short reason"` and stop.
4. When the 5-hour limit reaches {{THRESHOLD}}%, the system sends you a "LIMIT WARNING" context. At that moment:
   - do not start any new sub-task;
   - bring the step you are working on (half-written file, command, verification) to a consistent point and finish it;
   - write a "done / next step" note to `~/.claude/oyna-devam/progress.md` (unfinished work, file paths, pending agents included);
   - end your turn (no final summary; the task is not finished).
   {{LIMIT_NOTE}}
5. If you receive a "RESUME AFTER SUSPEND" message, read `~/.claude/oyna-devam/progress.md` and this task definition, and carry on from where you left off without stopping. The same rules apply in that session: if you reach the threshold again, repeat the same steps.
6. When the task is completely finished (including all verification/approval steps) run `powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/oyna-devam/oyna-devam.ps1" done`, then write your final summary and end the turn. `done` switches the system back to inactive (it stays installed). {{FINAL_NOTE}}

To stop everything by hand: `... oyna-devam.ps1 off`. To cancel a pending suspend: `... oyna-devam.ps1 cancel`.
