#!/usr/bin/env bash
#
# agent-snapshot.sh — reference implementation of Agent M's core data access.
# Mirrors what the Swift app does, so behavior can be validated from the shell.
#
#   ./agent-snapshot.sh                      list all sessions + status + transcript path
#   ./agent-snapshot.sh <id-or-name>         follow one session's conversation (tail -f)
#   ./agent-snapshot.sh <id-or-name> -n 40   print last 40 turns and exit
#
# Depends only on: a `claude` binary on PATH (or a known location), python3. No jq required.
set -euo pipefail

# Resolve the claude binary the way a GUI app must (PATH is not guaranteed for .app bundles).
find_claude() {
  for c in "$(command -v claude 2>/dev/null || true)" \
           "$HOME/.local/bin/claude" "/opt/homebrew/bin/claude" \
           "/usr/local/bin/claude" "$HOME/.claude/local/claude"; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  echo "error: could not locate the 'claude' binary" >&2
  return 1
}
CLAUDE="$(find_claude)"

list_sessions() {
  "$CLAUDE" agents --json --all 2>/dev/null | python3 -c '
import sys, json, glob, os
projects = os.path.expanduser("~/.claude/projects")
try:
    data = json.load(sys.stdin)
except Exception:
    print("no sessions / could not parse output"); sys.exit(0)

def transcript(sid):
    hits = glob.glob(os.path.join(projects, "*", sid + ".jsonl"))
    return hits[0] if hits else "(no transcript yet)"

data.sort(key=lambda e: (e.get("status") != "busy", e.get("startedAt", 0)))
print("%-9s %-12s %-28s %s" % ("STATUS", "KIND", "NAME", "CWD"))
print("-" * 100)
for e in data:
    st = e.get("status", "?")
    if e.get("kind") == "background":
        st = st + "/" + e.get("state", "?")
    kind = e.get("kind", "?")
    name = (e.get("name") or "-")[:28]
    cwd = e.get("cwd", "?")
    sid = e.get("sessionId", "?")
    print("%-9s %-12s %-28s %s" % (st, kind, name, cwd))
    print("        sid=" + sid)
    print("        log=" + transcript(sid))
'
}

resolve_transcript() {
  # Accept a sessionId (or prefix) or a name substring; print the transcript path.
  "$CLAUDE" agents --json --all 2>/dev/null | python3 -c '
import sys, json, glob, os
q = sys.argv[1].lower()
projects = os.path.expanduser("~/.claude/projects")
data = json.load(sys.stdin)
for e in data:
    sid = e.get("sessionId", "")
    name = (e.get("name") or "").lower()
    if sid.lower().startswith(q) or (q and q in name):
        hits = glob.glob(os.path.join(projects, "*", sid + ".jsonl"))
        if hits:
            print(hits[0]); sys.exit(0)
sys.exit(1)
' "$1"
}

render_jsonl() {
  # Pretty-print user/assistant turns from a transcript stream on stdin.
  python3 -c '
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        rec = json.loads(line)
    except Exception:
        continue  # partial / non-json line -- skip (the real app buffers these)
    t = rec.get("type")
    if t not in ("user", "assistant"):
        continue
    content = rec.get("message", {}).get("content", "")
    if isinstance(content, list):
        parts = []
        for b in content:
            if not isinstance(b, dict):
                continue
            bt = b.get("type")
            if bt == "text":
                parts.append(b.get("text", ""))
            elif bt == "tool_use":
                parts.append("[tool_use: " + str(b.get("name")) + "]")
            elif bt == "tool_result":
                parts.append("[tool_result]")
        content = "\n".join(p for p in parts if p)
    print("\n=== " + t.upper() + " (" + str(rec.get("timestamp", "")) + ") ===")
    print(content)
'
}

main() {
  if [ $# -eq 0 ]; then
    list_sessions
    return
  fi
  local query="$1"; shift
  local path
  if ! path="$(resolve_transcript "$query")"; then
    echo "error: no session matching '$query'" >&2; exit 1
  fi
  echo "# transcript: $path" >&2
  if [ "${1:-}" = "-n" ]; then
    tail -n "${2:-30}" "$path" | render_jsonl
  else
    echo "# following (Ctrl-C to stop)..." >&2
    tail -n 30 -f "$path" | render_jsonl
  fi
}

main "$@"
