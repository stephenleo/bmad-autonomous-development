# OpenCode Session State Setup

Replaces the Claude Code session-state hook installation (Step 3 of `/bad setup`). On Claude Code, the setup installs `bad-statusline.sh` as a `statusLine` command hook that captures context-window usage and rate-limit data to `.claude/bad-session-state.json` for Pre-Continuation Checks.

On OpenCode, this entire setup step is **skipped** — there is no equivalent hook mechanism, and the checks it enables are handled differently.

---

## Why Skip?

| Capability | Claude Code | OpenCode |
|------------|-------------|----------|
| `statusLine` hook | ✅ Available | ❌ Not available |
| Context window data | ✅ `context_window.used_percentage` | ❌ No equivalent data |
| Rate limit data | ✅ `rate_limits.*` | ❌ No equivalent data |
| Session JSON capture | ✅ `.claude/bad-session-state.json` | ❌ Cannot capture |
| Channel reconnect | ✅ `/reload-plugins` | ❌ No external channel |

---

## Pre-Continuation Checks on OpenCode

The Pre-Continuation Checks gate (`references/coordinator/gate-pre-continuation.md`) has 3 numbered checks plus a channel-reconnect step on OpenCode, they are handled as follows:

### Channel Reconnect

**Skipped.** OpenCode has no Telegram or external notification channel. No action needed.

### Check 1: Context Window

**Skipped.** OpenCode uses auto-compaction — context window management is automatic and does not need manual intervention. There is no `context_window.used_percentage` to read and no `/compact` command to invoke.

### Check 2: Five-Hour Usage Limit

**Skipped.** There is no rate-limit data available on OpenCode. The Pre-Continuation Checks logic handles this gracefully:

> If a specific field is absent — silently skip only that check. If the file exists but `rate_limits` is entirely absent, print the warning once.

On OpenCode, the session-state file never exists, so the Pre-Continuation Checks print the absent-file warning once per session and skip all checks.

### Check 3: Seven-Day Usage Limit

**Skipped.** Same as Check 2 — no rate-limit data available.

---

## Summary

The entire `/bad setup` Step 3 (session-state hook installation) reduces to a single informational line on OpenCode:

```
ℹ️ OpenCode: session-state hook skipped (auto-compaction handles context;
   rate limit checks not applicable). Pre-Continuation Checks reduced to
   a single informational line.
```

---

## What About Future Harnesses?

If a future harness provides equivalent session-state data (context usage, rate limits) through a standard mechanism, this pattern should be updated to:

1. Detect the data source (e.g. file path, environment variables, API).
2. Read the relevant fields.
3. Apply the same Pre-Continuation Checks logic as Claude Code.

For now, the data sources do not exist, so all checks are skipped gracefully.
