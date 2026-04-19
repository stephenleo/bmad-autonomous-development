# Timer Pattern

Both the retrospective and post-batch wait timers use this pattern. The caller supplies the duration, fire prompt, option labels, and actions.

Behaviour depends on `TIMER_SUPPORT`. Accepted values:

- `cron` — Claude Code's `CronCreate` schedules a one-shot wake-up.
- `blocking-sleep` — Codex (and any harness without a scheduler but with a shell): a blocking `sleep N` *is* the timer; it auto-fires when it returns.
- `prompt` — no auto-fire; wait for the user to reply.

Legacy values: `true` is read as `cron`, `false` is read as `prompt`.

---

## If `TIMER_SUPPORT=cron` (native platform timers)

**Step 1 — compute target cron expression** (convert seconds to minutes: `SECONDS ÷ 60`):
```bash
# macOS
date -v +{N}M '+%M %H %d %m *'
# Linux
date -d '+{N} minutes' '+%M %H %d %m *'
```
Save as `CRON_EXPR`. Save `TIMER_START=$(date +%s)`.

**Step 2 — create the one-shot timer** via `CronCreate`:
- `cron`: expression from Step 1
- `recurring`: `false`
- `prompt`: the caller-supplied fire prompt

Save the returned job ID as `JOB_ID`.

**Step 3 — print the options menu** (always [C], [S], [M]; include [X] only if the caller supplied an [X] label):
> Timer running (job: {JOB_ID}). I'll act in {N} minutes.
>
> - **[C] Continue** — {C label}
> - **[S] Stop** — {S label}
> - **[X] Exit** — {X label}  ← omit this line if no [X] label was supplied
> - **[M] {N} Modify timer to {N} minutes** — shorten or extend the countdown

📣 **Notify** (see `references/coordinator/pattern-notify.md`) with the same options so the user can respond from their device:
```
⏱ Timer set — {N} minutes (job: {JOB_ID})

[C] {C label}
[S] {S label}
[X] {X label}   ← omit if no [X] label supplied
[M] {minutes} — modify countdown
```

Wait for whichever arrives first — user reply or fired prompt. On any human reply, print elapsed time first:
```bash
ELAPSED=$(( $(date +%s) - TIMER_START ))
echo "⏱ Time elapsed: $((ELAPSED / 60))m $((ELAPSED % 60))s"
```

- **[C]** → `CronDelete(JOB_ID)`, run the [C] action
- **[S]** → `CronDelete(JOB_ID)`, run the [S] action
- **[X]** → `CronDelete(JOB_ID)`, run the [X] action ← only if [X] label was supplied
- **[M] N** → `CronDelete(JOB_ID)`, recompute cron for N minutes from now, `CronCreate` again with same fire prompt, update `JOB_ID` and `TIMER_START`, print updated countdown, then 📣 **Notify**:
  ```
  ⏱ Timer updated — {N} minutes (job: {JOB_ID})

  [C] {C label}
  [S] {S label}
  [X] {X label}   ← omit if no [X] label supplied
  [M] {minutes} — modify countdown
  ```
- **FIRED (no prior reply)** → run the [C] action automatically

---

## If `TIMER_SUPPORT=blocking-sleep` (Codex — shell-blocking timer)

Save `TIMER_START=$(date +%s)`. Codex has no scheduler, but its shell tool blocks on long commands — so `sleep N` *is* the timer. Print the options menu:

> Timer running — shell sleep for {N} minutes. I'll act automatically when it returns.
>
> - **[C] Continue** — {C label} (auto-fires when sleep completes)
> - **[S] Stop** — {S label}
> - **[X] Exit** — {X label}  ← omit this line if no [X] label was supplied
> - **[M] N** — to modify the countdown, press **Esc** (or ctrl-C) to interrupt the sleep, then reply with `[M] <minutes>`

📣 **Notify** (see `references/coordinator/pattern-notify.md`) with the same options. Make sure the user knows that typing a reply mid-wait requires pressing Esc first — while the shell tool is running, the agent is blocked on it.

Then run a single blocking command:
```bash
sleep {SECONDS}
EXIT=$?
ELAPSED=$(( $(date +%s) - TIMER_START ))
echo "⏱ Time elapsed: $((ELAPSED / 60))m $((ELAPSED % 60))s (exit=$EXIT)"
```

- **`EXIT=0`** (sleep completed normally) → run the [C] action automatically. This is the auto-fire path.
- **`EXIT!=0`** (user interrupted with Esc / ctrl-C) → reprint the menu and wait for the user's reply:
  - **[C]** → run the [C] action
  - **[S]** → run the [S] action
  - **[X]** → run the [X] action ← only if [X] label was supplied
  - **[M] N** → update `TIMER_START`, recompute `SECONDS = N × 60`, print the updated wait message, 📣 **Notify**, then re-run the `sleep $SECONDS` command above

---

## If `TIMER_SUPPORT=prompt` (prompt-based continuation)

Save `TIMER_START=$(date +%s)`. No native timer is created — print the options menu immediately and wait for user reply:

> Waiting {N} minutes before continuing. Reply when ready.
>
> - **[C] Continue** — {C label}
> - **[S] Stop** — {S label}
> - **[X] Exit** — {X label}  ← omit this line if no [X] label was supplied
> - **[M] N** — remind me after N minutes (reply with `[M] <minutes>`)

📣 **Notify** (see `references/coordinator/pattern-notify.md`) with the same options.

On any human reply, print elapsed time first:
```bash
ELAPSED=$(( $(date +%s) - TIMER_START ))
echo "⏱ Time elapsed: $((ELAPSED / 60))m $((ELAPSED % 60))s"
```

- **[C]** → run the [C] action
- **[S]** → run the [S] action
- **[X]** → run the [X] action ← only if [X] label was supplied
- **[M] N** → update `TIMER_START`, print updated wait message, 📣 **Notify**, and wait again
