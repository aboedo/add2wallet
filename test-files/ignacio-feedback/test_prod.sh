#!/usr/bin/env bash
set -euo pipefail

BASE="https://add2wallet-backend-production.up.railway.app"
DIR="$(cd "$(dirname "$0")" && pwd)"

API_KEY="${API_KEY:-}"
if [[ -z "$API_KEY" ]]; then
  echo "ERROR: set API_KEY env var" >&2
  exit 1
fi

OUT="$DIR/PROD_RESULTS.md"
: > "$OUT"

dejson() {
  python3 - "$1" <<'PY'
import json,sys
raw=sys.argv[1]
try:
  d=json.loads(raw)
except Exception as e:
  print(f"- RESULT: parse_error: {e}")
  sys.exit(0)

status=d.get('status','?')
print(f"- status: {status}")
if status=='completed':
  m=d.get('ai_metadata',{}) or {}
  passes=d.get('passes') or []
  n=len(passes) if passes else 1
  print(f"- event_name: {m.get('event_name')}")
  print(f"- event_type: {m.get('event_type')}")
  print(f"- date: {m.get('date')} time: {m.get('time')}")
  if m.get('origin') or m.get('destination'):
    print(f"- route: {m.get('origin')} -> {m.get('destination')}")
  print(f"- n_passes: {n}")
else:
  print(f"- error: {d.get('message') or d.get('detail')}")
PY
}

run_one() {
  local pdf="$1"
  local name
  name=$(basename "$pdf")

  {
    echo "## $name"

    resp=$(curl -s --max-time 90 -X POST "$BASE/upload" \
      -H "x-api-key: $API_KEY" \
      -F "file=@$pdf" \
      -F "user_id=test" \
      -F "session_token=test" || true)

    if [[ -z "$resp" ]]; then
      echo "- RESULT: (empty/timeout)"
      echo ""
      return
    fi

    dejson "$resp"
    echo ""
  } >> "$OUT"
}

for i in {1..13}; do
  pdf=$(ls "$DIR"/${i}-*.pdf 2>/dev/null | head -1 || true)
  [[ -n "$pdf" ]] && run_one "$pdf"
done

echo "Wrote $OUT"
