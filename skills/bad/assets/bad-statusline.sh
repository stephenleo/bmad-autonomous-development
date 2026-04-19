#!/bin/bash
# BAD session-state capture — installed to {project-root}/.claude/bad-statusline.sh
# during /bad setup. Configured as the Claude Code statusLine script so it runs
# after every API response and writes the session JSON to .claude/bad-session-state.json
# (next to this script) that the BAD coordinator reads during Pre-Continuation Checks.
#
# To chain with an existing statusline script:
#   SESSION_JSON=$(cat)
#   echo "$SESSION_JSON" | /path/to/your-existing-script.sh
#   SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
#   echo "$SESSION_JSON" > "$SCRIPT_DIR/bad-session-state.json"

SESSION_JSON=$(cat)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
echo "$SESSION_JSON" > "$SCRIPT_DIR/bad-session-state.json"
# Output nothing — add your own status text here if desired, e.g.:
# python3 -c "
# import sys, json
# d = json.loads(sys.stdin.read())
# cw = d.get('context_window', {})
# pct = cw.get('used_percentage')
# rl = d.get('rate_limits', {})
# fh = rl.get('five_hour', {}).get('used_percentage')
# parts = [f'ctx:{pct:.0f}%' if pct is not None else None,
#          f'rate5h:{fh:.0f}%' if fh is not None else None]
# print(' '.join(p for p in parts if p))
# " <<< \"\$SESSION_JSON\" 2>/dev/null || true
