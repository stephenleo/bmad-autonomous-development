# OpenCode Monitor Pattern

Replaces the Claude Code Monitor tool for CI status polling and PR-merge watching. OpenCode has no native Monitor tool, so polling loops are implemented as `while true` background `bash` processes — same approach as `pattern-timer.md`.

Behaviour depends on `MONITOR_SUPPORT`:

- `MONITOR_SUPPORT=true` (Claude Code) → use the native Monitor tool (see `references/coordinator/pattern-monitor.md`)
- `MONITOR_SUPPORT=false` → use the bash polling loops described below

On OpenCode, `MONITOR_SUPPORT` is always `false`.

---

## How It Works

1. **Write a poll script** — a `while true; do ...; sleep N; done` loop that writes events to a signal file.
2. **Start it as a background process** — same mechanism as the timer pattern.
3. **Check the signal file** between tool calls — like checking if a timer has fired.
4. **React to events** — on each line in the signal file, apply the caller's reaction logic.
5. **Stop** — kill the background PID and remove files.

---

## CI Status Polling (Step 6)

Poll script:

```bash
# Called with: POLL_ID
TIMER_ID="{POLL_ID}"
SLEEP_SECONDS=30

cat > "/tmp/${TIMER_ID}_poll.sh" << 'POLLSCRIPT'
#!/bin/bash
# Polls CI status until complete or failed
GH_BIN="$(command -v gh)"
SIGNAL_FILE="/tmp/${TIMER_ID}.signal"

while true; do
  RUN_ID=$("$GH_BIN" run list --json databaseId --limit 1 --jq '.[0].databaseId' 2>/dev/null)
  if [ -z "$RUN_ID" ]; then
    echo "CI_NO_RUNS" > "$SIGNAL_FILE"
    exit 0
  fi
  RESULT=$("$GH_BIN" run view "$RUN_ID" --json status,conclusion 2>&1)

  if echo "$RESULT" | grep -q '"conclusion":"success"'; then
    echo "CI_PASSED" > "$SIGNAL_FILE"
    exit 0
  fi

  if echo "$RESULT" | grep -qE '"conclusion":"(failure|cancelled)"'; then
    echo "CI_FAILED" > "$SIGNAL_FILE"
    exit 0
  fi

  if echo "$RESULT" | grep -qiE "(billing|spending limit|credit)"; then
    echo "CI_BILLING_LIMIT" > "$SIGNAL_FILE"
    exit 0
  fi

  sleep "$SLEEP_SECONDS"
done
POLLSCRIPT

chmod +x "/tmp/${TIMER_ID}_poll.sh"
bash "/tmp/${TIMER_ID}_poll.sh" &
echo "$!" > "/tmp/${TIMER_ID}.pid"
```

React to each event in the signal file:

```bash
if [ -f "/tmp/${TIMER_ID}.signal" ]; then
  EVENT=$(cat "/tmp/${TIMER_ID}.signal")
  rm -f "/tmp/${TIMER_ID}.signal"

  case "$EVENT" in
    CI_PASSED)
      poll cleanup
      echo "✅ CI passed — proceeding"
      ;;
    CI_FAILED)
      poll cleanup
      echo "❌ CI failed — diagnosing"
      ;;
    CI_BILLING_LIMIT)
      poll cleanup
      echo "💰 CI billing limit hit — running Local CI Fallback"
      ;;
  esac
fi
```

---

## PR-Merge Watching (Phase 4 Branch B)

The coordinator fills in `BATCH_PRS` (space-separated PR numbers) before starting.

Poll script:

```bash
# Called with: POLL_ID, BATCH_PRS, REPO_PATH
TIMER_ID="{POLL_ID}"
SLEEP_SECONDS=60

cat > "/tmp/${TIMER_ID}_poll.sh" << 'POLLSCRIPT'
#!/bin/bash
GH_BIN="$(command -v gh)"
BATCH_PRS="{BATCH_PRS}"
ALREADY_REPORTED=""
SIGNAL_FILE="/tmp/${TIMER_ID}.signal"

while true; do
  MERGED_NOW=$(cd "{REPO_PATH}" && "$GH_BIN" pr list --state merged --json number \
    --jq '.[].number' 2>/dev/null | tr '\n' ' ' || echo "")
  ALL_DONE=true

  for PR in $BATCH_PRS; do
    if echo " $MERGED_NOW " | grep -q " $PR "; then
      if ! echo " $ALREADY_REPORTED " | grep -q " $PR "; then
        echo "MERGED: #$PR" >> "$SIGNAL_FILE"
        ALREADY_REPORTED="$ALREADY_REPORTED $PR"
      fi
    else
      ALL_DONE=false
    fi
  done

  if [ "$ALL_DONE" = "true" ]; then
    echo "ALL_MERGED" >> "$SIGNAL_FILE"
    exit 0
  fi

  sleep "$SLEEP_SECONDS"
done
POLLSCRIPT

chmod +x "/tmp/${TIMER_ID}_poll.sh"
bash "/tmp/${TIMER_ID}_poll.sh" &
echo "$!" > "/tmp/${TIMER_ID}.pid"
```

Read and react to events from the signal file between tool calls:

```bash
if [ -f "/tmp/${TIMER_ID}.signal" ]; then
  while IFS= read -r line; do
    case "$line" in
      MERGED:\ #*)
        PR_NUM="${line#MERGED: #}"
        echo "✅ PR #${PR_NUM} merged — waiting for remaining batch PRs"
        ;;
      ALL_MERGED)
        echo "✅ All batch PRs merged — proceeding"
        poll_cleanup
        # Proceed to Pre-Continuation Checks then re-run Phase 0
        ;;
    esac
  done < "/tmp/${TIMER_ID}.signal"
  rm -f "/tmp/${TIMER_ID}.signal"
fi
```

---

## Poll Cleanup

```bash
kill "$(cat /tmp/${TIMER_ID}.pid)" 2>/dev/null
rm -f "/tmp/${TIMER_ID}.pid" "/tmp/${TIMER_ID}.signal" "/tmp/${TIMER_ID}_poll.sh"
```

---

## User Interrupt

The user can always interrupt a poll loop by replying in the conversation. Any user reply cancels the poll:

```bash
# When user replies before poll completes:
kill "$(cat /tmp/${TIMER_ID}.pid)" 2>/dev/null
rm -f "/tmp/${TIMER_ID}.pid" "/tmp/${TIMER_ID}.signal" "/tmp/${TIMER_ID}_poll.sh"
echo "⏹ Poll interrupted by user"
```

---

## Important Notes

- **`gh` path resolution**: The Monitor shell inherits a stripped PATH. Always resolve `gh` with `command -v gh` before the script runs, not by name inside it.
- **`gh` has no `-C` flag** (unlike `git`) — use `cd` to the repo path instead.
- **`gh pr list` defaults to `--state open`** — merged PRs are invisible without `--state merged`.
- **Signal file races**: If multiple events occur between checks, they are all appended to the signal file. Always read the full file and process every line.
