# BAD — BMad Autonomous Development

> 🤖 Autonomous development orchestrator for the BMad Method. Runs fully autonomous parallel multi-agent pipelines through the full story lifecycle (create → dev → review → PR) driven by your sprint backlog and dependency graph.

<img src="docs/bad-overview.png" alt="BAD Overview" width="800"/>

## Overview

BAD is a [BMad Method](https://docs.bmad-method.org/) module that automates your entire sprint execution. A lightweight coordinator orchestrates the pipeline — it never reads files or writes code itself. **Every unit of work is delegated to a dedicated subagent with a fresh context window**, keeping each agent fully focused on its single task.

## Requirements

- [BMad Method](https://docs.bmad-method.org/) installed in your project `npx bmad-method install --modules bmm,tea`
- A sprint plan with epics, stories, and `sprint-status.yaml`
- Git + GitHub CLI (`gh`) installed and authenticated:
  1. `brew install gh`
  2. `gh auth login`
  3. Add to your `.zshrc` so BAD's subagents can connect to GitHub:
     ```bash
     export GITHUB_PERSONAL_ACCESS_TOKEN=$(gh auth token)
     ```
  4. If running Claude Code with sandbox mode, allow `gh` to reach GitHub's API — add to `.claude/settings.json`:
     ```json
     {
       "sandbox": {
         ...
         "enableWeakerNetworkIsolation": true
       }
     }
     ```

## Installation

```bash
npx skills add https://github.com/stephenleo/bmad-autonomous-development
```

Then run setup in your project:

```
/bad setup
```

## Usage

BAD spawns subagents for every step of the pipeline. For the full autonomous experience — no permission prompts — start Claude Code with:

```bash
claude --dangerously-skip-permissions
```

Then run:

```
/bad
```

> In Codex, use `$bad` instead of `/bad` (Codex's command prefix is `$`, not `/`). The same applies to `/bad setup`, `/bad configure`, and runtime overrides.

BAD can also be triggered naturally: *"run BAD"*, *"kick off the sprint"*, *"automate the sprint"*, *"start autonomous development"*, *"run the pipeline"*, *"start the dev pipeline"*

Run with optional runtime overrides:

```
/bad MAX_PARALLEL_STORIES=2 AUTO_PR_MERGE=true MODEL_STANDARD=opus
```

## Pipeline

Once your epics and stories are planned, BAD takes over:

1. *(`MODEL_STANDARD` subagent)* Builds a dependency graph from your sprint backlog — maps story dependencies, syncs GitHub PR status, and identifies what's ready to work on
2. Picks ready stories from the graph, respecting epic ordering and dependencies; runs a blocking epic-level test design step (`bmad-testarch-test-design`) once when starting each new epic
3. Runs up to `MAX_PARALLEL_STORIES` stories simultaneously — each in its own isolated git worktree — each through a sequential 7-step pipeline. **Every step runs in a dedicated subagent with a fresh context window**, keeping the coordinator lean and each agent fully focused on its single task:
   - **Step 1** *(`MODEL_STANDARD` subagent)* — `bmad-create-story`: generates and validates the story spec
   - **Step 2** *(`MODEL_STANDARD` subagent)* — `bmad-testarch-atdd`: generates failing acceptance tests
   - **Step 3** *(`MODEL_STANDARD` subagent)* — `bmad-dev-story`: implements the code
   - **Step 4** *(`MODEL_STANDARD` subagent)* — `bmad-testarch-test-review`: reviews test quality, applies fixes
   - **Step 5** *(`MODEL_QUALITY` subagent)* — `bmad-code-review`: reviews and fixes the implementation
   - **Step 6** *(`MODEL_STANDARD` subagent)* — commit, push, open PR, monitor CI, fix any failing checks
   - **Step 7** *(`MODEL_STANDARD` subagent)* — PR code review: reviews diff, applies fixes, pushes clean
4. *(`MODEL_STANDARD` subagent)* Optionally auto-merges batch PRs sequentially (lowest story number first), resolving any conflicts
5. On epic completion, optionally runs a retrospective (`bmad-retrospective`) after a `RETRO_TIMER_SECONDS` countdown — the user can trigger it early, skip it, or stop BAD
6. Waits, then loops back for the next batch — until the entire sprint is done

## Configuration

BAD is configured at install time (`/bad setup`) and stores settings in the `bad:` section of `_bmad/config.yaml`. All values can be overridden at runtime with `KEY=VALUE` args.

| Variable | Default | Description |
|---|---|---|
| `MAX_PARALLEL_STORIES` | `3` | Stories to run per batch |
| `WORKTREE_BASE_PATH` | `.worktrees` | Base directory for per-story git worktrees (relative to repo root) |
| `MODEL_STANDARD` | `sonnet` | Model for create, ATDD, dev, test review, and PR steps |
| `MODEL_QUALITY` | `opus` | Model for code review step |
| `AUTO_PR_MERGE` | `false` | Auto-merge PRs sequentially after each batch |
| `RUN_CI_LOCALLY` | `false` | Run CI locally instead of GitHub Actions |
| `WAIT_TIMER_SECONDS` | `3600` | Seconds to wait between batches |
| `RETRO_TIMER_SECONDS` | `600` | Seconds before auto-retrospective after epic completion |
| `CONTEXT_COMPACTION_THRESHOLD` | `80` | Context window % at which to compact context |
| `STALE_TIMEOUT_MINUTES` | `60` | Minutes of subagent inactivity before watchdog alerts (0 = disabled) |
| `TIMER_SUPPORT` | `cron` (Claude Code) / `blocking-sleep` (Codex) / `prompt` (others) | `cron` uses `CronCreate`; `blocking-sleep` uses a shell `sleep N` (auto-fires when it returns); `prompt` waits for a user reply. Legacy `true`/`false` still accepted |
| `MONITOR_SUPPORT` | `true` | Use the Monitor tool for CI/PR-merge polling; `false` for Bedrock/Vertex/Foundry |
| `API_FIVE_HOUR_THRESHOLD` | `80` | (Claude Code) 5-hour usage % at which to pause |
| `API_SEVEN_DAY_THRESHOLD` | `95` | (Claude Code) 7-day usage % at which to pause |
| `API_USAGE_THRESHOLD` | `80` | (Other harnesses) Generic usage % at which to pause |

## Agent Harness Support

BAD is harness-agnostic. Setup detects your installed harnesses by checking for their directories at the project root (`.claude/` for Claude Code, `.cursor/` for Cursor, `.github/skills/` for GitHub Copilot, etc.) and configures platform-specific settings accordingly:

- **Claude Code** — native timer support (`CronCreate`), Claude model names (`sonnet`/`opus`/`haiku`), 5-hour and 7-day rate limit thresholds
- **Other harnesses** — prompt-based continuation, free-text model names, single generic usage threshold

In multi-harness projects, setup runs once per detected harness and stores per-harness model settings (e.g. `claude_model_standard`, `cursor_model_standard`).

## Reconfigure

To update your configuration at any time:

```
/bad configure
```

## License

MIT © 2026 Marie Stephen Leo
