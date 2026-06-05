# OpenCode Reference Docs

This directory contains reference documentation for BAD's OpenCode-specific implementations. Each file documents how a mechanism that uses Claude Code-native tools (CronCreate, Monitor, Telegram MCP, activity log hook) is replaced with OpenCode-native alternatives (bash background processes, signal files, print-only notifications, worktree modification time polling).

---

## Pattern Index

| File | Replaces | Mechanism |
|------|----------|-----------|
| `pattern-timer.md` | CronCreate / CronDelete | Background `sleep` + PID file + signal file |
| `pattern-notify.md` | Telegram MCP + print | Print-only notifications (no external channel) |
| `pattern-monitor.md` | Monitor tool | Bash `while true` polling loop + signal file |
| `pattern-watchdog.md` | Activity log hook + Monitor | `find` worktree modification time polling |
| `setup-session-state.md` | `statusLine` hook for session data | Skipped (auto-compaction, no rate-limit data) |

---

## Config Variables

OpenCode introduces the following config variables (set in the BAD config, e.g. `opencode.json` or environment):

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCODE_MODEL_STANDARD` | `"deepseek-v4-flash"` | Model used for standard coder/reviewer subagents |
| `OPENCODE_MODEL_QUALITY` | `"deepseek-v4-flash"` | Model used for architect/designer (higher-quality) tasks |

These replace the Claude Code-specific model selection which was tied to `.claude/settings.json`.

---

## Detecting OpenCode

The BAD coordinator detects the OpenCode harness by checking for the existence of `.opencode/` at the project root:

```bash
if [ -d ".opencode" ]; then
  HARNESS="opencode"
else
  HARNESS="claude-code"
fi
```

When `HARNESS=opencode`:

- `TIMER_SUPPORT=false` — use background `sleep` instead of CronCreate
- `MONITOR_SUPPORT=false` — use bash polling loops instead of Monitor tool
- `NOTIFY_SOURCE="terminal"` — print-only notifications (no Telegram)
- No session-state hook installation
- Pre-Continuation Checks skipped (auto-compaction handles everything)

---

## Cross-Reference

For the Claude Code equivalents of these patterns, see:

- `references/coordinator/pattern-timer.md`
- `references/coordinator/pattern-notify.md`
- `references/coordinator/pattern-monitor.md`
- `references/coordinator/pattern-watchdog.md`
- `references/coordinator/setup-statusline-hook.md`
- `references/coordinator/gate-pre-continuation.md`
