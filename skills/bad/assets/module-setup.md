# BAD Module Setup

Standalone module self-registration for BMad Autonomous Development. This file is loaded when:
- The user passes `setup`, `configure`, or `install` as an argument
- The module is not yet registered in `{project-root}/_bmad/config.yaml` (no `bad:` section)

## Overview

Registers BAD into a project. Writes to:
- **`{project-root}/_bmad/config.yaml`** — shared project config (universal settings + harness-specific settings)
- **`{project-root}/_bmad/config.user.yaml`** — personal settings (gitignored): `user_name`, `communication_language`, and any `user_setting: true` variable
- **`{project-root}/_bmad/module-help.csv`** — registers BAD capabilities for the help system

Both config scripts use an anti-zombie pattern — existing `bad` entries are removed before writing fresh ones, so stale values never persist.

`{project-root}` is a **literal token** in config values — never substitute it with an actual path.

## Step 1: Check Existing Config

1. Read `./assets/module.yaml` for module metadata.
2. Check if `{project-root}/_bmad/config.yaml` has a `bad` section — if so, inform the user this is a reconfiguration and show existing values as defaults.
3. Check for inline args (e.g. `accept all defaults`, `--headless`, or `MAX_PARALLEL_STORIES=5`) — map any provided values to config keys, use defaults for the rest, skip prompting for those keys.

## Step 2: Detect Installed Harnesses

Check for the presence of harness directories at the project root:

| Directory | Harness |
|---|---|
| `.claude/` | `claude-code` |
| `.cursor/` | `cursor` |
| `.github/skills/` | `github-copilot` (use `/skills/` subfolder to avoid false positive on bare `.github/`) |
| `.codex/` | `openai-codex` |
| `.gemini/` | `gemini` |
| `.windsurf/` | `windsurf` |
| `.cline/` | `cline` |

Store all detected harnesses. Determine the **current harness** from this skill's own file path — whichever harness directory contains this running skill is the current harness. Use the current harness to drive the question branch in Step 3.

## Step 3: Session-State Hook (Claude Code only)

Skip this step if `claude-code` was not detected in Step 2, or if `--headless` /
`accept all defaults` was passed (auto-accept as yes).

Silently check: does `.claude/bad-statusline.sh` exist and does `.claude/settings.local.json`
have a `statusLine` entry pointing to it? Note `already installed` or `not yet installed`.

Invoke the **`AskUserQuestion`** tool (your only output for this turn — do not proceed to
Step 4 until the tool returns):

```
questions: [
  {
    question: "Install BAD session-state capture? Writes rate-limit / context data to a temp file so the coordinator can pause near API limits. [<state-hook-status>]",
    header: "State hook",
    multiSelect: false,
    options: [
      { label: "Yes, install", description: "Recommended — enables rate-limit pausing and context compaction" },
      { label: "No, skip",     description: "Pre-Continuation Checks will not have session data" }
    ]
  }
]
```

If **Yes**: read and follow `references/coordinator/setup-statusline-hook.md`, then proceed to Step 4.
If **No**: proceed to Step 4.

## Step 4: Activity Log Hook (Claude Code only)

Skip this step if `claude-code` was not detected in Step 2, or if `--headless` /
`accept all defaults` was passed (auto-accept as yes).

**Always run on every setup and reconfiguration** — even if already installed. The script is safe to re-run (anti-zombie pattern).

Silently check: does `.claude/settings.local.json` have a `PostToolUse` hook whose `command`
references `bad-logs`? Note `already installed — will reinstall` or `not yet installed`.

Invoke the **`AskUserQuestion`** tool (your only output for this turn — do not proceed to
Step 5 until the tool returns):

```
questions: [
  {
    question: "Install BAD activity log hook? Logs every tool call passively so the watchdog can detect hung subagents. [<activity-hook-status>]",
    header: "Activity hook",
    multiSelect: false,
    options: [
      { label: "Yes, install", description: "Recommended — enables hang detection via the watchdog pattern" },
      { label: "No, skip",     description: "Watchdog pattern will be disabled" }
    ]
  }
]
```

If **Yes**, run:
```bash
python3 ./scripts/setup-activity-hook.py \
  --settings-path ".claude/settings.local.json" \
  --project-root "$(pwd)"
```
The script adds a `PostToolUse` hook to `.claude/settings.local.json` (project-scoped), writes
one TSV line per tool call to `~/.claude/projects/<encoded-project>/bad-logs/<agent-slug>/<session-id>.log`,
and uses an anti-zombie pattern so it is safe to re-run.

Proceed to Step 5.

---

## Step 5: Core Config (only if not yet set)

Skip this step if `user_name` already exists in `config.yaml` or `config.user.yaml`.

**If `--headless` / `accept all defaults`:** use defaults (`BMad`, `English`) without prompting.

Otherwise, invoke the **`AskUserQuestion`** tool:

```
questions: [
  {
    question: "What name should BAD use for you in notifications and reports?",
    header: "Your name",
    multiSelect: false,
    options: [
      { label: "BMad",  description: "Default" },
      { label: "Other", description: "Type your name" }
    ]
  },
  {
    question: "What language should BAD use for communication and documents?",
    header: "Language",
    multiSelect: false,
    options: [
      { label: "English", description: "Default" },
      { label: "Other",   description: "Type your language" }
    ]
  }
]
```

Record `user_name` → `config.user.yaml`; `communication_language` and
`document_output_language` (same value) → `config.user.yaml` and `config.yaml` respectively.

---

## Step 6: BAD Configuration

**Default priority** (highest wins): existing config values > harness-aware defaults (below) > `./assets/module.yaml` defaults.
**If `--headless` / `accept all defaults`:** skip this step entirely and use defaults.

**Harness-aware model defaults.** Before resolving `model_standard` / `model_quality`, branch on the `current_harness` detected in Step 2. If the existing config already has values, keep them; otherwise pick from this table:

| Current harness  | `model_standard` default | `model_quality` default |
|------------------|--------------------------|-------------------------|
| `openai-codex`   | `gpt-5.3-codex default`          | `gpt-5.4 default`               |
| anything else    | `sonnet`                 | `opus`                  |

First, **print all current config values** as a formatted block so the user can review them:

```
⚙️ BAD Configuration — current values shown in [brackets]

Universal settings:
  max_parallel_stories          [<value>] — Max stories per batch
  worktree_base_path            [<value>] — Git worktrees directory
  auto_pr_merge                 [<value>] — Auto-merge batch PRs after each batch
  run_ci_locally                [<value>] — Skip GitHub Actions, run CI locally
  wait_timer_seconds            [<value>] — Seconds between batches
  retro_timer_seconds           [<value>] — Seconds before auto-retrospective
  context_compaction_threshold  [<value>] — Context % to trigger compaction
  stale_timeout_minutes         [<value>] — Inactivity minutes before watchdog alerts

Model & rate-limit settings (current harness: <current_harness>):
  model_standard           [<value>] — Model for story/dev/PR steps
  model_quality            [<value>] — Model for code review
  api_five_hour_threshold  [<value>] — 5-hour usage % to pause (Claude Code only)
  api_seven_day_threshold  [<value>] — 7-day usage % to pause (Claude Code only)
```

Then invoke the **`AskUserQuestion`** tool (your only output for this turn — do not proceed
to Step 7 until the tool returns):

```
questions: [
  {
    question: "Review the configuration above. Accept all defaults, or specify what to change?",
    header: "Config",
    multiSelect: false,
    options: [
      { label: "Accept all defaults", description: "Keep every value shown above and proceed" },
      { label: "Change some values",  description: "Select 'Other' to type overrides as KEY=VALUE pairs, e.g. max_parallel_stories=5, model_quality=sonnet" }
    ]
  }
]
```

- **Accept all defaults:** proceed to Step 7.
- **Change some values / Other:** parse the user's text as `KEY=VALUE` pairs (space or comma
  separated). Apply overrides to the resolved config. Proceed to Step 7.

If multiple harnesses are detected, repeat this step once per additional harness — label each
section clearly and store model/threshold values with a harness prefix (e.g.
`claude_model_standard`).

Automatically write without prompting:
- Claude Code: `timer_support: true`, `monitor_support: true`
- All other harnesses: `timer_support: false`, `monitor_support: false`

## Step 7: Write Files

Write a temp JSON file with collected answers structured as:
```json
{
  "core": { "user_name": "...", "document_output_language": "...", "output_folder": "..." },
  "bad": {
    "max_parallel_stories": "3",
    "worktree_base_path": ".worktrees",
    "auto_pr_merge": false,
    "run_ci_locally": false,
    "wait_timer_seconds": "3600",
    "retro_timer_seconds": "600",
    "context_compaction_threshold": "80",
    "stale_timeout_minutes": "60",
    "timer_support": true,
    "monitor_support": true,
    "model_standard": "<resolved in Step 6 — sonnet on Claude Code, gpt-5.3-codex default on openai-codex>",
    "model_quality": "<resolved in Step 6 — opus on Claude Code, gpt-5.4 default on openai-codex>",
    "api_five_hour_threshold": "80",
    "api_seven_day_threshold": "95"
  }
}
```

Omit `core` key if core config already exists. Run both scripts in parallel:

```bash
python3 ./scripts/merge-config.py \
  --config-path "{project-root}/_bmad/config.yaml" \
  --user-config-path "{project-root}/_bmad/config.user.yaml" \
  --module-yaml ./assets/module.yaml \
  --answers {temp-file}

python3 ./scripts/merge-help-csv.py \
  --target "{project-root}/_bmad/module-help.csv" \
  --source ./assets/module-help.csv \
  --module-code bad
```

If either exits non-zero, surface the error and stop.

Run `./scripts/merge-config.py --help` or `./scripts/merge-help-csv.py --help` for full usage.

## Step 8: Create Directories

After writing config, create the worktree base directory at the resolved path of `{project-root}/{worktree_base_path}` if it does not exist. Use the actual resolved path for filesystem operations only — config values must continue to use the literal `{project-root}` token.

Also create `output_folder` and any other `{project-root}/`-prefixed values from the config that don't exist on disk.

## Step 9: Confirm and Greet

Display what was written: config values set, user settings written, help entries registered, fresh install vs reconfiguration.

Then display the module greeting:

> BAD is ready. Run /bad to start. Pass KEY=VALUE args to override config at runtime (e.g. /bad MAX_PARALLEL_STORIES=2).

## Return to Skill

Setup is complete. Resume normal BAD activation — load config from the freshly written files and proceed with whatever the user originally intended.
