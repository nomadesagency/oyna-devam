#!/bin/bash
# Completely removes sleep:  bash uninstall.sh [--keep-data] [--no-sudo]
#   - stops running sleep/wake jobs and caffeinate
#   - removes the sleep hooks from ~/.claude/settings.json (backed up first)
#   - deletes the ~/.claude/sleep/ folder (--keep-data: leaves the log/progress files)
#   - removes /etc/sudoers.d/claude-sleep
DEST="${SLEEP_HOME:-$HOME/.claude/sleep}"
SETTINGS="${SLEEP_SETTINGS:-$HOME/.claude/settings.json}"
KEEP=0; NO_SUDO=0
for a in "$@"; do case "$a" in --keep-data) KEEP=1 ;; --no-sudo) NO_SUDO=1 ;; *) echo "unknown argument: $a" >&2; exit 1 ;; esac; done
# Safety guard: only ever install into / delete a folder that is literally named "sleep" (never $HOME, "/" or a relative path)
case "$DEST" in /*) ;; *) echo "Refusing: SLEEP_HOME must be an absolute path ($DEST)" >&2; exit 1 ;; esac
if [ "$(basename "$DEST")" != sleep ] || [ "$DEST" = "$HOME" ] || [ "$DEST" = / ]; then echo "Refusing: the install folder must be named 'sleep' ($DEST)" >&2; exit 1; fi

echo "1/4 stopping running jobs"
for d in "$DEST"; do
  [ -d "$d" ] || continue
  touch "$d/CANCEL"
  for pf in "$d"/sleeper.pid "$d"/caffeinate.pid "$d"/darkguard.pid; do [ -f "$pf" ] && kill "$(cat "$pf")" 2>/dev/null; done
done
for d in "$DEST"; do
  pkill -f "$d/sleep-and-resume.sh" 2>/dev/null; pkill -f "$d/final-sleep.sh" 2>/dev/null; pkill -f "$d/watch.sh" 2>/dev/null
done

echo "2/4 cleaning the hooks in settings.json"
if [ -f "$SETTINGS" ]; then
  cp -p "$SETTINGS" "$SETTINGS.sleep-backup-$(date +%Y%m%d-%H%M%S)"   # -p keeps the original (possibly restrictive) permissions
  ls -t "$SETTINGS".sleep-backup-* 2>/dev/null | tail -n +4 | while IFS= read -r old_bk; do rm -f "$old_bk"; done
  SLEEP_DEST="$DEST" python3 - "$SETTINGS" <<'PY'
import json, os, sys
p = sys.argv[1]; dest = os.environ["SLEEP_DEST"]
def save(path, obj):
    # atomic write: temp file in the same folder, then replace; a symlinked settings.json is followed, not replaced
    import tempfile, shutil
    real = os.path.realpath(path)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(real), prefix=".settings.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f: json.dump(obj, f, ensure_ascii=False, indent=2)
        try: shutil.copymode(real, tmp)
        except OSError: pass
        os.replace(tmp, real)
    except Exception:
        try: os.remove(tmp)
        except OSError: pass
        raise
s = json.load(open(p, encoding="utf-8"))
hooks = s.get("hooks", {})
def ours(c): return (dest + "/hook-") in c or "/.claude/sleep/hook-" in c
removed = 0
for ev in list(hooks):
    new = []
    for grp in hooks[ev]:
        before = len(grp.get("hooks", []))
        grp["hooks"] = [h for h in grp.get("hooks", []) if not ours(h.get("command", ""))]
        removed += before - len(grp["hooks"])
        if grp["hooks"]: new.append(grp)
    if new: hooks[ev] = new
    else: del hooks[ev]
if not hooks: s.pop("hooks", None)
perm = s.get("permissions", {})
allow = perm.get("allow", [])
n_rules = len(allow)
allow[:] = [r for r in allow if (dest + "/sleep.sh") not in r and "/.claude/sleep/sleep.sh" not in r]
removed += n_rules - len(allow)
if "allow" in perm and not allow: perm.pop("allow")
if "permissions" in s and not perm: s.pop("permissions")
save(p, s)
print(f"   {removed} hook(s)/permission rule(s) removed.")
PY
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "   Could not clean settings.json (it was left unchanged; a backup exists). Nothing was deleted, so the hooks keep working."
    echo "   Fix settings.json (or remove the sleep hooks by hand) and run this uninstaller again."
    exit 1
  fi
fi

echo "3/4 deleting files"
if [ "$KEEP" = 1 ]; then
  for f in "$DEST"/*.sh "$DEST"/*.jq "$DEST"/task-template.md "$DEST"/*.command; do [ -e "$f" ] && rm -f "$f"; done
  echo "   --keep-data: log/progress files left in place ($DEST)"
else
  rm -rf "$DEST"
fi

echo "4/4 sudoers rule"
if [ "$NO_SUDO" = 1 ]; then echo "   skipped (--no-sudo)"; else
  for f in /etc/sudoers.d/claude-sleep; do
    if sudo test -e "$f" 2>/dev/null; then sudo rm -f "$f" && echo "   $f removed"; fi
  done
fi
echo "Removed. (Reload Claude Code / VS Code.)"
