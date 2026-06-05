# OpenCode Timer Pattern

Replaces the Claude Code `CronCreate` / `CronDelete` timer mechanism. OpenCode has no native cron tool, so timers are implemented as background `sleep` processes with PID files and signal files in `/tmp/`.

Behaviour depends on a session variable `OPENCODE_TIMER_PID`. A running timer has a non-empty PID; no running timer has it empty.

---

## Start Timer

Launch a background sleep and record the PID:

```bash
# Called with: TIMER_ID, DURATION_SECONDS
SLEEP_SECONDS="{DURATION_SECONDS}"
TIMER_ID="{TIMER_ID}"

# Start the background timer
(sleep "$SLEEP_SECONDS" && echo "BAD_TIMER_FIRED" > "/tmp/${TIMER_ID}.signal") &

# Save PID for later cleanup / modification
echo "$!" > "/tmp/${TIMER_ID}.pid"
```

Print the options menu:

> Timer running (PID: {PID}). I'll act in {N} seconds.
>
> - **[C] Continue** — {C label}
> - **[S] Stop** — {S label}
> - **[M] N** — modify countdown to N seconds

---

## Timer Options

### [C] Continue

Kill the timer and run the [C] action immediately:

```bash
kill "$(cat /tmp/${TIMER_ID}.pid)" 2>/dev/null
rm -f "/tmp/${TIMER_ID}.pid" "/tmp/${TIMER_ID}.signal"
```

### [S] Stop

Kill the timer and run the [S] action (typically abort / skip):

```bash
kill "$(cat /tmp/${TIMER_ID}.pid)" 2>/dev/null
rm -f "/tmp/${TIMER_ID}.pid" "/tmp/${TIMER_ID}.signal"
```

### [M] N

Kill the existing timer, restart with a new duration:

```bash
# Kill current timer
kill "$(cat /tmp/${TIMER_ID}.pid)" 2>/dev/null
rm -f "/tmp/${TIMER_ID}.pid" "/tmp/${TIMER_ID}.signal"

# Start new timer with N seconds
(sleep "{N}" && echo "BAD_TIMER_FIRED" > "/tmp/${TIMER_ID}.signal") &
echo "$!" > "/tmp/${TIMER_ID}.pid"

echo "⏱ Timer updated — {N} seconds (PID: $(cat /tmp/${TIMER_ID}.pid))"
```

---

## Timer Check

Between tool calls, check if the timer has fired:

```bash
if [ -f "/tmp/${TIMER_ID}.signal" ]; then
  rm -f "/tmp/${TIMER_ID}.signal"
  # Timer fired — run the [C] action automatically
fi
```

---

## Cleanup

When the timer completes or is cancelled, always remove both files:

```bash
kill "$(cat /tmp/${TIMER_ID}.pid)" 2>/dev/null
rm -f "/tmp/${TIMER_ID}.pid" "/tmp/${TIMER_ID}.signal"
```

---

## Elapsed Time Display

When a user replies before the timer fires, print elapsed time. The coordinator must record the start epoch when launching the timer:

```bash
# At timer launch (coordinator records this):
TIMER_START=$(date +%s)

# When user replies before timer fires:
ELAPSED=$(( $(date +%s) - TIMER_START ))
echo "⏱ Time elapsed: $((ELAPSED / 60))m $((ELAPSED % 60))s"
```

---

## Retry Timer (for timer-based watchdog fallback)

When used as a fixed-timeout watchdog (see `pattern-watchdog.md`), restart the timer after each [K]eep response:

```bash
# Kill old timer
kill "$(cat /tmp/${TIMER_ID}.pid)" 2>/dev/null

# Restart
(sleep "$SLEEP_SECONDS" && echo "BAD_TIMER_FIRED" > "/tmp/${TIMER_ID}.signal") &
echo "$!" > "/tmp/${TIMER_ID}.pid"
```

---

## Limitations

- No built-in cron persistence — timers are lost if the OpenCode session restarts.
- Background processes rely on the shell session remaining alive. If the terminal dies, the timer is lost with it.
- Precision is limited by the shell `sleep` implementation (typically ±1 second).
