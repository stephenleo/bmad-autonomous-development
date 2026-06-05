# OpenCode Watchdog Pattern

Replaces the Claude Code activity-log-based watchdog that used Monitor + the session-state hook to detect hung subagents. On OpenCode, there is no activity log hook and no Monitor tool, so the watchdog uses `find` modification-time polling on the agent's git worktree.

Behaviour depends on `MONITOR_SUPPORT`:

- `MONITOR_SUPPORT=true` (Claude Code) → use the native Monitor + activity log hook approach (see `references/coordinator/pattern-watchdog.md`)
- `MONITOR_SUPPORT=false` → use the bash polling approach described below

On OpenCode, `MONITOR_SUPPORT` is always `false`.

---

## How It Works

1. **Record a baseline** — measure the latest modification timestamp in the subagent's worktree before spawning.
2. **Spawn the subagent** as a background task.
3. **Poll periodically** — check if any file in the worktree has been modified since the baseline.
4. **On STALE** — no change for `STALE_TIMEOUT_MINUTES` — alert and ask the user how to proceed.
5. **On ALIVE** — update the baseline, keep waiting.

---

## Baseline Recording

Before spawning the subagent, record the latest file modification time in the worktree:

```bash
WORKTREE="{subagent_worktree_path}"
BASELINE_FILE="/tmp/bad_watchdog_baseline_${WORKTREE//\//_}"

find "$WORKTREE" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 > "$BASELINE_FILE"
echo "🐶 Watchdog: baseline recorded for $WORKTREE"
```

---

## Poll Loop

Start the watchdog as a background process:

```bash
# Called with: WATCHDOG_ID, WORKTREE, AGENT_LABEL, STALE_TIMEOUT_MINUTES
TIMER_ID="{WATCHDOG_ID}"
STALE_MINUTES="${STALE_TIMEOUT_MINUTES:-60}"
POLL_INTERVAL=120  # check every 2 minutes

cat > "/tmp/${TIMER_ID}_watchdog.sh" << 'WDSCRIPT'
#!/bin/bash
WORKTREE="{WORKTREE}"
AGENT_LABEL="{AGENT_LABEL}"
STALE_MINUTES={STALE_MINUTES}
POLL_INTERVAL={POLL_INTERVAL}
BASELINE_FILE="/tmp/bad_watchdog_baseline_${WORKTREE//\//_}"
SIGNAL_FILE="/tmp/${TIMER_ID}.signal"

while true; do
  # Get current latest modification time
  CURRENT_MTIME=$(find "$WORKTREE" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1)

  if [ -z "$CURRENT_MTIME" ]; then
    # Worktree inaccessible — agent may not have started yet
    echo "ALIVE:${AGENT_LABEL} — worktree not yet accessible" > "$SIGNAL_FILE"
    sleep "$POLL_INTERVAL"
    continue
  fi

  BASELINE=$(cat "$BASELINE_FILE" 2>/dev/null || echo "0")

  if [ -n "$BASELINE" ] && [ "$(echo "$CURRENT_MTIME > $BASELINE" | bc -l 2>/dev/null)" = "1" ]; then
    # Activity detected — update baseline
    echo "$CURRENT_MTIME" > "$BASELINE_FILE"
    echo "ALIVE:${AGENT_LABEL} — activity detected" > "$SIGNAL_FILE"
    sleep "$POLL_INTERVAL"
    continue
  fi

  # No new activity — check how long since baseline was last updated
  NOW=$(date +%s)
  BASELINE_SEC=$(echo "$BASELINE / 1" | bc 2>/dev/null || echo "0")
  AGE_MIN=$(( (NOW - BASELINE_SEC) / 60 ))

  if [ "$AGE_MIN" -ge "$STALE_MINUTES" ]; then
    LAST_FILE=$(find "$WORKTREE" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    echo "STALE:${AGE_MIN}:${LAST_FILE}" > "$SIGNAL_FILE"
    exit 1
  fi

  echo "ALIVE:${AGENT_LABEL} — last activity ${AGE_MIN}m ago" > "$SIGNAL_FILE"
  sleep "$POLL_INTERVAL"
done
WDSCRIPT

chmod +x "/tmp/${TIMER_ID}_watchdog.sh"
bash "/tmp/${TIMER_ID}_watchdog.sh" &
echo "$!" > "/tmp/${TIMER_ID}.pid"
```

---

## Checking for Events

Between tool calls, check the watchdog signal file:

```bash
if [ -f "/tmp/${TIMER_ID}.signal" ]; then
  EVENT=$(cat "/tmp/${TIMER_ID}.signal")
  rm -f "/tmp/${TIMER_ID}.signal"

  case "$EVENT" in
    ALIVE:*)
      # No action — keep waiting
      ;;
    STALE:*)
      STALE_INFO="${EVENT#STALE:}"
      MINUTES="${STALE_INFO%%:*}"
      DETAIL="${STALE_INFO#*:}"

      echo "⚠️ ${AGENT_LABEL} appears stuck — no file changes for ${MINUTES} min."
      echo "Last file touched: ${DETAIL}"
      echo ""
      echo "[K] Keep waiting another ${STALE_TIMEOUT_MINUTES} min"
      echo "[R] Retry — respawn this step from the start"
      echo "[S] Skip this story and continue with others"
      echo "[A] Abort BAD"
      ;;
  esac
fi
```

---

## User Options

### [K] Keep

Restart the watchdog (reset the staleness baseline) — the background agent keeps running:

```bash
# Re-record baseline
find "$WORKTREE" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 > "$BASELINE_FILE"

# Kill old watchdog and restart
kill "$(cat /tmp/${TIMER_ID}.pid)" 2>/dev/null
bash "/tmp/${TIMER_ID}_watchdog.sh" &
echo "$!" > "/tmp/${TIMER_ID}.pid"
```

### [R] Retry

Stop the watchdog, kill the hung subagent, and spawn a fresh one:

```bash
# Cleanup
kill "$(cat /tmp/${TIMER_ID}.pid)" 2>/dev/null
rm -f "/tmp/${TIMER_ID}.pid" "/tmp/${TIMER_ID}.signal" "/tmp/${TIMER_ID}_watchdog.sh"

# Kill the background subagent (replace with actual subagent PID)
kill "${SUBAGENT_PID}" 2>/dev/null

# Note the story as failed at this step
echo "Story ${STORY_ID} failed at step ${STEP_NAME} — will retry"

# Spawn fresh subagent (coordinator fills in the details)
```

### [S] Skip

Stop the watchdog, mark the story as failed, continue with remaining stories:

```bash
kill "$(cat /tmp/${TIMER_ID}.pid)" 2>/dev/null
rm -f "/tmp/${TIMER_ID}.pid" "/tmp/${TIMER_ID}.signal" "/tmp/${TIMER_ID}_watchdog.sh"
echo "Story ${STORY_ID} skipped at step ${STEP_NAME}"
```

### [A] Abort

Stop the watchdog, halt BAD entirely:

```bash
kill "$(cat /tmp/${TIMER_ID}.pid)" 2>/dev/null
rm -f "/tmp/${TIMER_ID}.pid" "/tmp/${TIMER_ID}.signal" "/tmp/${TIMER_ID}_watchdog.sh"
echo "🛑 BAD halted by user (watchdog abort)"
# Print summary of completed work
```

---

## Cleanup

When the subagent completes normally:

```bash
kill "$(cat /tmp/${TIMER_ID}.pid)" 2>/dev/null
rm -f "/tmp/${TIMER_ID}.pid" "/tmp/${TIMER_ID}.signal" "/tmp/${TIMER_ID}_watchdog.sh"
rm -f "$BASELINE_FILE"
```

---

## Configuration

`STALE_TIMEOUT_MINUTES` — read from BAD config. Default: `60`. Set lower (e.g. `30`) for faster detection; set higher (e.g. `90`) if your dev steps routinely involve long read-heavy analysis phases.

---

## Important Notes

- **Worktree-based detection**: This approach watches file modification times rather than tool-call activity. An agent that is actively reading files (not writing) will appear idle. Consider a higher timeout for read-heavy steps.
- **`bc` dependency**: The comparison uses `bc -l` for floating-point comparison of `printf '%T@'` timestamps. Ensure `bc` is available on the system.
- **No log file fallback**: Unlike Claude Code, OpenCode has no activity log hook. There is no per-agent log directory to check for tool-call timestamps. Worktree modification time is the only reliable signal.
- **Race on spawn**: The subagent may not have created any files yet when the watchdog starts. The watchdog treats "worktree not yet accessible" as ALIVE, not STALE.