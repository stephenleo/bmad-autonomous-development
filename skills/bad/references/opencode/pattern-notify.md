# OpenCode Notify Pattern

Use this pattern every time a `📣 Notify:` callout appears **anywhere in the BAD skill** — including inside the Timer Pattern and Monitor Pattern.

Replaces Claude Code's Telegram MCP + print notification system. On OpenCode, there is no external notification channel available — the only channel is the conversation itself.

**Always print the message in the conversation** — this keeps the in-session transcript readable.

```bash
# Always just print the message
echo "{message}"
```

No external tool calls are made. There is no `/reload-plugins` equivalent, no MCP server to reconnect, and no chat_id configuration.

---

## Why Print-Only?

| Capability | Claude Code | OpenCode |
|------------|-------------|----------|
| Telegram MCP | ✅ Available | ❌ Not available |
| Other MCP plugins | ✅ /reload-plugins | ❌ No equivalent |
| Conversation output | ✅ print() | ✅ print() (same) |
| External push notifications | ✅ Telegram message | ❌ None |

Since OpenCode has no MCP plugin system, the only reliable notification channel is the conversation text the user sees when they check in.

---

## Future Extensibility

If a future OpenCode plugin adds notification capabilities (e.g. Slack webhook, email, desktop notification), this pattern should be updated to:

1. Keep the print-to-conversation step (always).
2. Check if the notification plugin is available (e.g. tool existence check).
3. If available, call the plugin with the message text.
4. If the call fails, fall back to print-only — no error escalation needed.

For now, **print always, call nothing else**.

---

## Notify Source Configuration

OpenCode does not use the `NOTIFY_SOURCE` session variable. If the BAD coordinator reads `NOTIFY_SOURCE` at session start, it should be set to `"terminal"` for OpenCode — which effectively means print-only everywhere in the skill.
