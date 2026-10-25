#!/bin/bash
# Reads the 5-hour limit percentage and reset time from `claude -p "/usage"` and writes them to state.json.
# (The VS Code extension does not run the statusline, so this is the data source.)
# Testing: SLEEP_USAGE_FIXTURE=file   |   SLEEP_USAGE_TIMEOUT=seconds (how long to wait for /usage, default 60)
#
# Reset-time formats understood (case-insensitive, time zone in parentheses optional):
#   "resets Oct 26 at 3:59am (Europe/London)"   date + time
#   "resets 3:59am (Europe/London)"             time only (today, or tomorrow if already past)
#   "resets 15:59"                                24-hour clock
# If the reset time cannot be parsed or is not plausible for a 5-hour window, a SAFE ESTIMATE (now + 5 h, the latest
# possible reset) is stored with "resets_estimated": true. The system then still triggers at the threshold; it just
# wakes at the latest possible moment instead of the exact one. The raw line is logged so the format can be fixed.
. "$(dirname "$0")/common.sh"
export LC_ALL=C
TMO="${SLEEP_USAGE_TIMEOUT:-60}"

# One refresh at a time (a stale lock is cleared after 2 minutes)
if ! mkdir "$U/refresh.lock" 2>/dev/null; then
  if [ -n "$(find "$U/refresh.lock" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
    rmdir "$U/refresh.lock" 2>/dev/null; mkdir "$U/refresh.lock" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
trap 'rmdir "$U/refresh.lock" 2>/dev/null' EXIT

if [ -n "$SLEEP_USAGE_FIXTURE" ]; then
  out=$(cat "$SLEEP_USAGE_FIXTURE")
else
  bin=$(claude_bin)
  [ -z "$bin" ] && { log "usage-refresh: claude binary not found"; exit 1; }
  tmp="$U/usage.out.$$"
  ( cd /tmp && "$bin" -p "/usage" >"$tmp" 2>/dev/null ) &
  p=$!
  for _ in $(seq 1 "$TMO"); do kill -0 "$p" 2>/dev/null || break; sleep 1; done
  kill "$p" 2>/dev/null
  out=$(cat "$tmp" 2>/dev/null); rm -f "$tmp"
fi

line=$(grep -m1 '^Current session:' <<<"$out")
if [ -z "$line" ]; then log "usage-refresh: 'Current session' line not found"; exit 1; fi
pct=$(sed -nE 's/^Current session: ([0-9.]+)% used.*/\1/p' <<<"$line")
[ -z "$pct" ] && { log "usage-refresh: could not parse percentage: $line"; exit 1; }

resets=$(python3 - "$line" <<'PY' 2>/dev/null
import re, sys, datetime as dt
line = sys.argv[1]
MON = {m: i + 1 for i, m in enumerate("jan feb mar apr may jun jul aug sep oct nov dec".split())}
m = re.search(
    r"resets\s+(?:(?P<mon>[A-Za-z]{3})[A-Za-z]*\.?\s+(?P<day>\d{1,2})(?:st|nd|rd|th)?,?\s*(?:at\s+)?|(?:at\s+)?)"
    r"(?P<h>\d{1,2})(?::(?P<mi>\d{2}))?\s*(?P<ap>[ap]m)?\b(?:\s*\((?P<tz>[^)]*)\))?",
    line, re.I)
try:
    if not m or not (m.group("ap") or m.group("mi")):
        raise ValueError("no time")
    h = int(m.group("h")); mi = int(m.group("mi") or 0); ap = (m.group("ap") or "").lower()
    if ap == "pm" and h < 12: h += 12
    if ap == "am" and h == 12: h = 0
    tz = None
    if m.group("tz"):
        try:
            import zoneinfo
            tz = zoneinfo.ZoneInfo(m.group("tz").strip())
        except Exception:
            tz = None  # unknown zone name: fall back to this computer's local time
    now = dt.datetime.now(tz)
    if m.group("mon"):
        mon = MON[m.group("mon").lower()]
        cand = now.replace(month=mon, day=int(m.group("day")), hour=h, minute=mi, second=0, microsecond=0)
        if cand < now - dt.timedelta(days=1):   # year rollover (e.g. Dec -> Jan)
            cand = cand.replace(year=cand.year + 1)
    else:
        cand = now.replace(hour=h, minute=mi, second=0, microsecond=0)
        if cand < now:
            cand += dt.timedelta(days=1)
    print(int(cand.timestamp()))
except Exception:
    print(0)
PY
)
[[ "$resets" =~ ^[0-9]+$ ]] || resets=0

# Plausibility: a 5-hour window resets within the next 5 h (allow 10 min slack) and is not in the past.
now=$(date +%s); est=false
if [ "$resets" -lt $((now - 300)) ] || [ "$resets" -gt $((now + 18600)) ]; then
  log "usage-refresh: WARNING reset time not understood (parsed=$resets), using safe estimate now+5h. Raw line: $line"
  resets=$((now + 18000)); est=true
fi

printf '{"five_hour_pct":%s,"resets_at":%s,"resets_estimated":%s,"ts":%s}\n' "$pct" "$resets" "$est" "$now" > "$U/state.json.tmp" && mv "$U/state.json.tmp" "$STATE"
log "usage-refresh: %$pct resets_at=$resets estimated=$est"
