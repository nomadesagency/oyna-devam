#!/bin/bash
# Oyna Devam installer (macOS). Usage:  bash install.sh [--no-sudo] [--yes]
#   - copies the scripts to ~/.claude/oyna-devam/
#   - adds 4 hooks + a permission rule to ~/.claude/settings.json (backed up first)
#   - (with sudo, once) allows passwordless `pmset schedule wake` -> /etc/sudoers.d/claude-oyna-devam
# Safe to run again (idempotent). To remove: bash uninstall.sh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/system"
DEST="${OYNA_DEVAM_HOME:-$HOME/.claude/oyna-devam}"
# Safety guard: only ever install into / delete a folder that is literally named "oyna-devam" (never $HOME, "/" or a relative path)
case "$DEST" in /*) ;; *) echo "Refusing: OYNA_DEVAM_HOME must be an absolute path ($DEST)" >&2; exit 1 ;; esac
if [ "$(basename "$DEST")" != oyna-devam ] || [ "$DEST" = "$HOME" ] || [ "$DEST" = / ]; then echo "Refusing: the install folder must be named 'oyna-devam' ($DEST)" >&2; exit 1; fi
SETTINGS="${OYNA_DEVAM_SETTINGS:-$HOME/.claude/settings.json}"
NO_SUDO=0; YES=0
for a in "$@"; do case "$a" in --no-sudo) NO_SUDO=1 ;; --yes) YES=1 ;; *) echo "unknown argument: $a" >&2; exit 1 ;; esac; done

say() { printf '\033[1m%s\033[0m\n' "$*"; }

[ "$(uname)" = Darwin ] || { echo "Oyna Devam only works on macOS (it needs pmset/caffeinate). For Windows use the oyna-devam-win folder."; exit 1; }
miss=0; for t in jq perl python3 caffeinate pmset osascript; do command -v "$t" >/dev/null || { echo "MISSING: $t"; miss=1; }; done
if [ "$miss" = 1 ]; then
  command -v jq >/dev/null || echo "  jq: macOS 15 (Sequoia) and newer include it. On older macOS open Terminal and run:  brew install jq   (Homebrew: https://brew.sh)"
  command -v python3 >/dev/null || echo "  python3: run  xcode-select --install  (a window asks to install the command line tools), wait until it finishes, then run the installer again."
  echo "After fixing, run the installer again. (Turkish step-by-step help: the user guide PDF, section 2.)"
  exit 1
fi
[ -d "$SRC" ] || { echo "system/ folder not found: $SRC"; exit 1; }

say "1/4  Copying files -> $DEST"
mkdir -p "$DEST"
# Leave working-state files (log, progress, state...) alone; only update the system files.
for f in "$SRC"/*; do cp "$f" "$DEST/$(basename "$f")"; done
chmod +x "$DEST"/*.sh
echo "     $(ls "$SRC" | wc -l | tr -d ' ') files copied."

say "2/4  Adding Claude Code hooks -> $SETTINGS"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp -p "$SETTINGS" "$SETTINGS.oyna-devam-backup-$(date +%Y%m%d-%H%M%S)"   # -p keeps the original (possibly restrictive) permissions
# keep only the 3 newest backups so repeated installs do not pile up files
ls -t "$SETTINGS".oyna-devam-backup-* 2>/dev/null | tail -n +4 | while IFS= read -r old_bk; do rm -f "$old_bk"; done
OYNA_DEVAM_DEST="$DEST" python3 - "$SETTINGS" <<'PY'
import json, os, sys
p = sys.argv[1]; dest = os.environ["OYNA_DEVAM_DEST"]
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
hooks = s.setdefault("hooks", {})
def ours(cmd): return (dest + "/hook-") in cmd or "/.claude/oyna-devam/hook-" in cmd
for ev in list(hooks):
    new = []
    for grp in hooks[ev]:
        grp["hooks"] = [h for h in grp.get("hooks", []) if not ours(h.get("command", ""))]
        if grp["hooks"]: new.append(grp)
    if new: hooks[ev] = new
    else: del hooks[ev]
def add(ev, script, timeout, matcher=None):
    grp = {"hooks": [{"type": "command", "command": f"bash {dest}/{script}", "timeout": timeout}]}
    if matcher: grp["matcher"] = matcher
    hooks.setdefault(ev, []).append(grp)
add("PreToolUse", "hook-pretooluse.sh", 10)
add("PostToolUse", "hook-posttool.sh", 10)
add("Stop", "hook-stop.sh", 60)
add("StopFailure", "hook-stopfailure.sh", 60, "rate_limit")
# Let the system's own control command run without a prompt, even before the session is bound (the first command of a task is `oyna-devam.sh on`).
allow = s.setdefault("permissions", {}).setdefault("allow", [])
allow[:] = [r for r in allow if (dest + "/oyna-devam.sh") not in r and "/.claude/oyna-devam/oyna-devam.sh" not in r]
for r in (f"Bash(bash {dest}/oyna-devam.sh:*)", "Bash(bash ~/.claude/oyna-devam/oyna-devam.sh:*)"):
    if r not in allow: allow.append(r)
save(p, s)
print("     hooks written (PreToolUse, PostToolUse, Stop, StopFailure) + permission rule for oyna-devam.sh.")
PY
say "3/4  Wake permission (sudoers)"
USERNAME="$(id -un)"
RULE="$USERNAME ALL=(root) NOPASSWD: /usr/bin/pmset schedule wake *, /usr/bin/pmset schedule cancel wake *"
if [ "$NO_SUDO" = 1 ]; then
  echo "     skipped (--no-sudo). Without the permission the computer is not suspended; when the limit fills up it stays awake and resumes."
elif sudo -n /usr/bin/pmset schedule wake "01/01/40 00:00:00" >/dev/null 2>&1; then
  sudo -n /usr/bin/pmset schedule cancel wake "01/01/40 00:00:00" >/dev/null 2>&1 || true
  echo "     permission already in place."
else
  echo "     This rule can ONLY run these without a password: 'pmset schedule wake' and 'pmset schedule cancel wake'."
  echo "     $RULE"
  if [ "$YES" != 1 ]; then read -r -p "     Install it? [y/N] " ans; [ "$ans" = y ] || [ "$ans" = Y ] || { echo "     skipped."; ans=skip; }; fi
  if [ "${ans:-y}" != skip ]; then
    tmp="$(mktemp)"; echo "$RULE" > "$tmp"
    if sudo visudo -cf "$tmp" >/dev/null && sudo install -m 440 -o root -g wheel "$tmp" /etc/sudoers.d/claude-oyna-devam; then echo "     /etc/sudoers.d/claude-oyna-devam installed."; else echo "     WARNING: could not install the sudoers rule."; fi
    rm -f "$tmp"
  fi
fi

say "4/4  Health check"
bash "$DEST/oyna-devam.sh" doctor || true

cat <<EOF

INSTALLED.  Next steps:
  1) Generate a task prompt (copied to the clipboard):   bash $DEST/oyna-devam.sh prompt "the task to do..."
  2) Open a new Claude Code session and paste it.   (Claude runs 'oyna-devam.sh on' as its first step.)
  3) Progress: the 'live status' window that opens, or  bash $DEST/oyna-devam.sh watch
NOTE: hooks take effect after restarting Claude Code (VS Code: reload the window).
EOF
