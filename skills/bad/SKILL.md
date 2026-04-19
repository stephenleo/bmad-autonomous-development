---
name: bad
description: 'BMad Autonomous Development — orchestrates parallel story implementation pipelines. Builds a dependency graph, updates PR status from GitHub, picks stories from the backlog, and runs each through create → dev → review → PR in parallel — each story isolated in its own git worktree — using dedicated subagents with fresh context windows. Loops through the entire sprint plan in batches, with optional epic retrospective. Use when the user says "run BAD", "start autonomous development", "automate the sprint", "run the pipeline", "kick off the sprint", or "start the dev pipeline". Run /bad setup or /bad configure to install and configure the module.'
---

# BAD — BMad Autonomous Development

## On Activation

Check if `{project-root}/_bmad/config.yaml` contains a `bad` section. If not — or if the user passed `setup` or `configure` as an argument — load `./assets/module-setup.md` and complete registration before proceeding.

The `setup`/`configure` argument always triggers `./assets/module-setup.md`, even if the module is already registered (for reconfiguration).

After setup completes (or if config already exists), load the `bad` config and continue to Startup below.

You are a **coordinator**. You delegate every step to subagents via the **Agent tool**. You never read files, run git/gh commands, or write to disk yourself.

**Coordinator-only responsibilities:**
- Pick stories from subagent-reported data
- Call the Agent tool to spawn subagents (in parallel where allowed — multiple Agent tool calls in one message)
- Manage timers (CronCreate / CronDelete)
- Run Pre-Continuation Checks (requires session stdin JSON — coordinator only)
- Handle user input, print summaries, and send channel notifications

**Everything else** — file reads, git operations, gh commands, disk writes — happens inside Agent tool subagents with fresh context windows.

## Startup: Capture Channel Context

Before doing anything else, determine how to send notifications:

1. **Check for a connected channel** — look at the current conversation context:
   - If you see a `<channel source="telegram" chat_id="..." ...>` tag, save `NOTIFY_CHAT_ID` and `NOTIFY_SOURCE="telegram"`.
   - If another channel type is connected, save its equivalent identifier.
   - If no channel is connected, set `NOTIFY_SOURCE="terminal"`.

2. **Send the BAD started notification** using the [Notify Pattern](references/coordinator/pattern-notify.md):
   ```
   🤖 BAD started — building dependency graph...
   ```

Then proceed to Phase 0.

---

## Configuration

Load base values from the `bad` section of `_bmad/config.yaml` at startup. Then parse any `KEY=VALUE` overrides from arguments passed to `/bad` — args win over config. For any variable not in config or args, use the default below.

| Variable | Config Key | Default | Description |
|----------|-----------|---------|-------------|
| `MAX_PARALLEL_STORIES` | `max_parallel_stories` | `3` | Max stories to run in a single batch |
| `WORKTREE_BASE_PATH` | `worktree_base_path` | `.worktrees` | Root directory for git worktrees |
| `MODEL_STANDARD` | `model_standard` | `sonnet` (Claude Code) / `gpt-5.3-codex default` (Codex) | Model for all subagents except Step 5 (code review): Phase 0, Phase 1 Epic-Start, Steps 1–4 and 6–7, Phase 3 (merge + cleanup), Phase 4 (assessment + retrospective) |
| `MODEL_QUALITY` | `model_quality` | `opus` (Claude Code) / `gpt-5.4 default` (Codex) | Model for Step 5 (code review) |
| `RETRO_TIMER_SECONDS` | `retro_timer_seconds` | `600` | Auto-retrospective countdown after epic completion (10 min) |
| `WAIT_TIMER_SECONDS` | `wait_timer_seconds` | `3600` | Post-batch wait before re-checking PR status (1 hr) |
| `CONTEXT_COMPACTION_THRESHOLD` | `context_compaction_threshold` | `80` | Context window % at which to compact/summarise context |
| `STALE_TIMEOUT_MINUTES` | `stale_timeout_minutes` | `60` | Minutes of subagent inactivity before watchdog alerts (0 = disabled) |
| `TIMER_SUPPORT` | `timer_support` | `true` | When `true`, use native platform timers; when `false`, use prompt-based continuation |
| `MONITOR_SUPPORT` | `monitor_support` | `true` | When `true`, use the Monitor tool for CI and PR-merge polling; when `false`, fall back to manual polling loops (required for Bedrock/Vertex/Foundry) |
| `API_FIVE_HOUR_THRESHOLD` | `api_five_hour_threshold` | `80` | (Claude Code) 5-hour rate limit % that triggers a pause |
| `API_SEVEN_DAY_THRESHOLD` | `api_seven_day_threshold` | `95` | (Claude Code) 7-day rate limit % that triggers a pause |
| `API_USAGE_THRESHOLD` | `api_usage_threshold` | `80` | (Other harnesses) Generic API usage % that triggers a pause |
| `RUN_CI_LOCALLY` | `run_ci_locally` | `false` | When `true`, skip GitHub Actions and always run the local CI fallback |
| `AUTO_PR_MERGE` | `auto_pr_merge` | `false` | When `true`, auto-merge batch PRs sequentially (lowest → highest) before Phase 4 |

`MODEL_STANDARD` and `MODEL_QUALITY` defaults are chosen at setup time based on the detected current harness (see `./assets/module-setup.md` Step 6). Override via `/bad configure` or by editing `_bmad/config.yaml`.

After resolving all values, print the active configuration so the user can confirm before Phase 0 begins:
```
⚙️ BAD config: MAX_PARALLEL_STORIES=3, RUN_CI_LOCALLY=false, AUTO_PR_MERGE=false, MODEL_STANDARD=sonnet, MODEL_QUALITY=opus, TIMER_SUPPORT=true, ...
```

---

## Pipeline

```
Phase 0: Build (or update) dependency graph  [subagent]
           └─ bmad-help maps story dependencies
           └─ GitHub updates PR merge status per story
           └─ git pull origin main
           └─ Reports: ready stories, epic completion status
  │
Phase 1: Discover stories  [coordinator logic]
           └─ Pick up to MAX_PARALLEL_STORIES from Phase 0 report
           └─ If new epic → Epic-Start Test Design [subagent, blocking]
           └─ If none ready → skip to Phase 4
  │
Phase 2: Run the pipeline  [subagents — stories parallel, steps sequential]
  ├─► Story A ──► Step 1 → Step 2 → Step 3 → Step 4 → Step 5 → Step 6 → Step 7
  ├─► Story B ──► Step 1 → Step 2 → Step 3 → Step 4 → Step 5 → Step 6 → Step 7
  └─► Story C ──► Step 1 → Step 2 → Step 3 → Step 4 → Step 5 → Step 6 → Step 7
  │
Phase 3: Auto-Merge Batch PRs  [subagents — sequential]
           └─ One subagent per story (lowest → highest story number)
           └─ Cleanup subagent for branch safety + git pull
  │
Phase 4: Batch Completion & Continuation
           └─ Print batch summary  [coordinator]
           └─ Epic completion check  [subagent]
           └─ Optional retrospective  [subagent]
           └─ Gate & Continue (WAIT_TIMER timer) → Phase 0 → Phase 1
```

---

## Phase 0: Build or Update the Dependency Graph

Before spawning the subagent, **create the full initial task list** using TaskCreate so the user can see the complete pipeline at a glance. Mark Phase 0 `in_progress`; all others start as `[ ]`. Apply the Phase 3 rule at creation time:

```
[in_progress] Phase 0: Dependency graph
[ ] Phase 1: Story selection
[ ] Phase 2: Step 1 — Create story
[ ] Phase 2: Step 2 — ATDD
[ ] Phase 2: Step 3 — Develop
[ ] Phase 2: Step 4 — Test review
[ ] Phase 2: Step 5 — Code review
[ ] Phase 2: Step 6 — PR + CI
[ ] Phase 2: Step 7 — PR review
[ ] Phase 3: Auto-merge                                      ← if AUTO_PR_MERGE=true
[completed] Phase 3: Auto-merge — skipped (AUTO_PR_MERGE=false)  ← if AUTO_PR_MERGE=false
[ ] Phase 4: Batch summary + continuation
```

Call the **Agent tool** with `model: MODEL_STANDARD`, `description: "Phase 0: dependency graph"`, and this prompt. The coordinator waits for the report.

```
Read `references/subagents/phase0-prompt.md` and follow its instructions exactly.
```

The coordinator uses the report to drive Phase 1. No coordinator-side file reads.

📣 **Notify** after Phase 0:
```
📊 Phase 0 complete
Ready: {N} stories — {comma-separated story numbers}
Blocked: {N} stories (if any)
```

After Phase 0 completes, **rebuild the task list in correct execution order** — tasks display in creation order, so delete and re-add to ensure Phase 2 story tasks appear before Phase 3 and Phase 4:

1. Mark `Phase 0: Dependency graph` → `completed`
2. Mark `Phase 1: Story selection` → `completed` (already done)
3. Delete all nine generic startup tasks: the seven `Phase 2: Step N` tasks, `Phase 3: Auto-merge`, and `Phase 4: Batch summary + continuation`
4. Re-add in execution order using TaskCreate:

```
[ ] Phase 1: Epic-Start Test Design            ← add once if new epic, before all story tasks
[ ] Phase 2 | Story {N}: Step 1 — Create story ← one set per selected story, all stories first
[ ] Phase 2 | Story {N}: Step 2 — ATDD
[ ] Phase 2 | Story {N}: Step 3 — Develop
[ ] Phase 2 | Story {N}: Step 4 — Test review
[ ] Phase 2 | Story {N}: Step 5 — Code review
[ ] Phase 2 | Story {N}: Step 6 — PR + CI
[ ] Phase 2 | Story {N}: Step 7 — PR review
                                               ← repeat for each story in the batch
[ ] Phase 3: Auto-merge                        ← if AUTO_PR_MERGE=true
[completed] Phase 3: Auto-merge — skipped (AUTO_PR_MERGE=false)  ← if AUTO_PR_MERGE=false
[ ] Phase 4: Batch summary + continuation
```

Update each story step task to `in_progress` when its subagent is spawned, and `completed` (or `failed`) when it reports back. Update Phase 3 and Phase 4 tasks similarly as they execute.

---

## Phase 1: Discover Stories

Pure coordinator logic — no file reads, no tool calls.

1. From Phase 0's `ready_stories` report, select at most `MAX_PARALLEL_STORIES` stories.
   - **Epic ordering is strictly enforced:** only pick stories from the lowest incomplete epic. Never pick a story from epic N if any story in epic N-1 (or earlier) is not yet merged — check this against the Phase 0 report.
2. **If no stories are ready** → report to the user which stories are blocked (from Phase 0 warnings), then jump to **Phase 4, Step 3 (Gate & Continue)**.
3. **Epic transition detection:** Compare the selected stories' epic to `CURRENT_EPIC` (a coordinator variable, initially unset).
   - If `CURRENT_EPIC` is unset or the selected stories belong to a different epic → update `CURRENT_EPIC` and run **Epic-Start Test Design** (below) as a blocking subagent before Phase 2 begins.
   - Otherwise → proceed directly to Phase 2.

> **Why epic ordering matters:** Stories in later epics build on earlier epics' code and product foundation. Starting epic 3 while epic 2 has open PRs risks merge conflicts and building on code that may still change.

### Epic-Start Test Design (`MODEL_STANDARD`)

Spawn before Phase 2 when starting a new epic (blocking — wait for completion before story pipelines begin):

```
You are the epic test design agent for {current_epic_name}.
Working directory: {repo_root}. Auto-approve all tool calls (yolo mode).

1. Run /bmad-testarch-test-design for {current_epic_name}.
2. Commit any new test plan files.

Report: success or failure with error details.
```

---

## Phase 2: Run the Pipeline

Launch all stories' Step 1 subagents **in a single message** (parallel). Each story's steps are **strictly sequential** — do not spawn step N+1 until step N reports success.

**Skip steps based on story status** (from Phase 0 report):

| Status          | Start from | Skip          |
|-----------------|------------|---------------|
| `backlog`       | Step 1     | nothing       |
| `ready-for-dev` | Step 2     | Step 1        |
| `atdd-done`     | Step 3     | Steps 1–2     |
| `in-progress`   | Step 3     | Steps 1–2     |
| `review`        | Step 4     | Steps 1–3     |
| `done`          | —          | all           |

**After each step — mandatory gate (never skip, even with parallel stories):** 📣 **Notify** the step result (formats below), then run **Pre-Continuation Checks** (`references/coordinator/gate-pre-continuation.md`). Only after all checks pass → spawn the next subagent.

📣 **Notify per step** as each step completes:
- Success: `✅ Story {number}: Step {N} — {step name}`
- Failure: `❌ Story {number}: Step {N} — {step name} failed — {brief error}`

Step names: Step 1 — Create, Step 2 — ATDD, Step 3 — Develop, Step 4 — Test review, Step 5 — Code review, Step 6 — PR + CI, Step 7 — PR review.

**On failure:** stop that story's pipeline. Report step, story, and error. Other stories continue.  
**Exception:** rate/usage limit failures → run Pre-Continuation Checks (which auto-pauses until reset) then retry.

**Hung subagents:** when `MONITOR_SUPPORT=true` and the activity log hook is installed (Step 4 of setup), use the [Watchdog Pattern](references/coordinator/pattern-watchdog.md) when spawning Steps 2, 3, 4, and 5 to detect stale agents.

### Step 1: Create Story (`MODEL_STANDARD`)

Spawn with model `MODEL_STANDARD` (yolo mode):
```
You are the Step 1 story creator for story {number}-{short_description}.
Working directory: {repo_root}. Auto-approve all tool calls (yolo mode).

1. Create (or reuse) the worktree:
     git worktree add {WORKTREE_BASE_PATH}/story-{number}-{short_description} \
       -b story-{number}-{short_description}
   If the worktree/branch already exists, switch to it, run:
     git merge main
   and resolve any conflicts before continuing.

2. Change into the worktree directory:
     cd {repo_root}/{WORKTREE_BASE_PATH}/story-{number}-{short_description}

3. Run /bmad-create-story {number}-{short_description}.

4. Run "validate story {number}-{short_description}". For every finding,
   apply a fix directly to the story file using your best engineering judgement.
   Repeat until no findings remain.

5. Update sprint-status.yaml at the REPO ROOT (not the worktree copy):
     _bmad-output/implementation-artifacts/sprint-status.yaml
   Set story {number} status to `ready-for-dev`.

Report: success or failure with error details.
```

### Step 2: ATDD (`MODEL_STANDARD`)

Spawn with model `MODEL_STANDARD` (yolo mode):
```
You are the Step 2 ATDD agent for story {number}-{short_description}.
Working directory: {repo_root}/{WORKTREE_BASE_PATH}/story-{number}-{short_description}.
Auto-approve all tool calls (yolo mode).

1. Run /bmad-testarch-atdd {number}-{short_description}.
2. Commit any generated test files.
3. Update sprint-status.yaml at the REPO ROOT:
     {repo_root}/_bmad-output/implementation-artifacts/sprint-status.yaml
   Set story {number} status to `atdd-done`.

Report: success or failure with error details.
```

### Step 3: Develop Story (`MODEL_STANDARD`)

Spawn with model `MODEL_STANDARD` (yolo mode):
```
You are the Step 3 developer for story {number}-{short_description}.
Working directory: {repo_root}/{WORKTREE_BASE_PATH}/story-{number}-{short_description}.
Auto-approve all tool calls (yolo mode).

1. Run /bmad-dev-story {number}-{short_description}.
2. Commit all changes when implementation is complete.
3. Update sprint-status.yaml at the REPO ROOT:
     {repo_root}/_bmad-output/implementation-artifacts/sprint-status.yaml
   Set story {number} status to `review`.

Report: success or failure with error details.
```

### Step 4: Test Review (`MODEL_STANDARD`)

Spawn with model `MODEL_STANDARD` (yolo mode):
```
You are the Step 4 test reviewer for story {number}-{short_description}.
Working directory: {repo_root}/{WORKTREE_BASE_PATH}/story-{number}-{short_description}.
Auto-approve all tool calls (yolo mode).

1. Run /bmad-testarch-test-review {number}-{short_description}.
2. Apply all findings using your best engineering judgement.
3. Commit any changes from the review.

Report: success or failure with error details.
```

### Step 5: Code Review (`MODEL_QUALITY`)

Spawn with model `MODEL_QUALITY` (yolo mode):
```
You are the Step 5 code reviewer for story {number}-{short_description}.
Working directory: {repo_root}/{WORKTREE_BASE_PATH}/story-{number}-{short_description}.
Auto-approve all tool calls (yolo mode).

1. Run /bmad-code-review {number}-{short_description}.
2. Auto-accept all findings and apply fixes using your best engineering judgement.
3. Commit any changes from the review.

Report: success or failure with error details.
```

### Step 6: PR & CI (`MODEL_STANDARD`)

Spawn with model `MODEL_STANDARD` (yolo mode):
```
You are the Step 6 PR and CI agent for story {number}-{short_description}.
Working directory: {repo_root}/{WORKTREE_BASE_PATH}/story-{number}-{short_description}.
Auto-approve all tool calls (yolo mode).

1. Commit all outstanding changes.

2. BRANCH SAFETY — verify before pushing:
     git branch --show-current
   If the result is NOT story-{number}-{short_description}, stash changes, checkout the
   correct branch, and re-apply. Never push to main or create a new branch.

3. Look up the GitHub issue number for this story:
   Read the story's section in `_bmad-output/planning-artifacts/epics.md` and extract
   the `**GH Issue:**` field. Save as `gh_issue_number`. If the field is absent
   (local-only mode — no GitHub auth), proceed without it.

4. Run /commit-commands:commit-push-pr.
   PR title: story-{number}-{short_description} - fixes #{gh_issue_number}
   Include "Fixes #{gh_issue_number}" in the PR description body (omit only if
   no issue number was found in step 3).

5. CI:
   - If RUN_CI_LOCALLY is true → skip GitHub Actions and run the Local CI Fallback below.
   - Otherwise, if MONITOR_SUPPORT is true → use the Monitor tool to watch CI status:
       Write a poller script:
         while true; do gh run view --json status,conclusion 2>&1; sleep 30; done
       Start it with Monitor. React to each output line as it arrives:
       - conclusion=success → stop Monitor, report success
       - conclusion=failure or cancelled → stop Monitor, diagnose, fix, push, restart Monitor
       - Billing/spending limit error in output → stop Monitor, run Local CI Fallback
       - gh TLS/auth error in output → stop Monitor, switch to curl poller from `references/coordinator/pattern-gh-curl-fallback.md`
   - Otherwise → poll manually in a loop:
       gh run view
     (If `gh` fails, use `gh run view` curl equivalent from `references/coordinator/pattern-gh-curl-fallback.md`)
     - Billing/spending limit error → exit loop, run Local CI Fallback
     - CI failed for other reason, or Claude bot left PR comments → fix, push, loop
     - CI green → report success

LOCAL CI FALLBACK (when RUN_CI_LOCALLY=true or billing-limited):
  Read `references/subagents/step6-ci-fallback.md` and follow its instructions exactly.

Report: success or failure, and the PR number/URL if opened.
```

### Step 7: PR Code Review (`MODEL_STANDARD`)

Spawn with model `MODEL_STANDARD` (yolo mode):
```
You are the Step 7 PR code reviewer for story {number}-{short_description}.
Working directory: {repo_root}/{WORKTREE_BASE_PATH}/story-{number}-{short_description}.
Auto-approve all tool calls (yolo mode).

1. Run /code-review:code-review (reads the PR diff via gh pr diff).
2. For every finding, apply a fix using your best engineering judgement.
   Do not skip or defer any finding — fix them all.
3. Commit all fixes and push to the PR branch.
4. If any fixes were pushed, re-run /code-review:code-review once more to confirm
   no new issues were introduced. Repeat fix → commit → push → re-review until
   the review comes back clean.
5. Update sprint-status.yaml at the REPO ROOT:
     {repo_root}/_bmad-output/implementation-artifacts/sprint-status.yaml
   Set story {number} status to `done`.

Report: clean (no findings or all fixed) or failure with details.
```

---

## Phase 3: Auto-Merge Batch PRs (when AUTO_PR_MERGE=true)

After all batch stories complete Phase 2, merge every successful story's PR into `main` — one subagent per story, **sequentially** (lowest story number first).

> **Why sequential:** Merging lowest-first ensures each subsequent merge rebases against a main that already contains its predecessors — keeping conflict resolution incremental and predictable.

**Steps:**

1. Collect all stories from the current batch that reached Step 6 successfully (have a PR). Sort ascending by story number.
2. For each story **sequentially** (wait for each to complete before starting the next):
   - Pull latest main at the repo root: spawn a quick subagent or include in the merge subagent.
   - Spawn a `MODEL_STANDARD` subagent (yolo mode) with the instructions from `references/subagents/phase3-merge.md`.
   - Run Pre-Continuation Checks after the subagent completes. If it fails (unresolvable conflict, CI blocking), report the error and continue to the next story.
3. Print a merge summary (coordinator formats from subagent reports):
   ```
   Auto-Merge Results:
   Story   | PR    | Outcome
   --------|-------|--------
   6.1     | #142  | Merged ✅
   6.2     | #143  | Merged ✅ (conflict resolved: src/foo.ts)
   6.3     | #144  | Failed ❌ (CI blocking — manual merge required)
   ```
📣 **Notify** after all merges are processed (coordinator formats from subagent reports):
```
🔀 Auto-merge complete
{story}: ✅ PR #{pr} | {story}: ✅ PR #{pr} (conflict resolved) | {story}: ❌ manual merge needed
```

4. Spawn a **cleanup subagent** (`MODEL_STANDARD`, yolo mode):
   ```
   Post-merge cleanup. Auto-approve all tool calls (yolo mode).
   Read `references/subagents/phase3-cleanup.md` and follow its instructions exactly.
   ```

---

## Phase 4: Batch Completion & Continuation

### Step 1: Print Batch Summary

Coordinator prints immediately — no file reads, formats from Phase 2 step results:

```
Story   | Step 1 | Step 2 | Step 3 | Step 4 | Step 5 | Step 6 | Step 7 | Result
--------|--------|--------|--------|--------|--------|--------|--------|-------
9.1     |   OK   |   OK   |   OK   |   OK   |   OK   |   OK   |   OK   | PR #142
9.2     |   OK   |   OK   |   OK   |  FAIL  |   --   |   --   |   --   | Test review failed: ...
9.3     |   OK   |   OK   |   OK   |   OK   |   OK   |   OK   |   OK   | PR #143
```

If arriving from Phase 1 with no ready stories:
```
No stories ready to work on.
Blocked stories: {from Phase 0 report}
```

📣 **Notify** with the batch summary (same content, condensed to one line per story):
```
📦 Batch complete — {N} stories
{number} ✅ PR #{pr} | {number} ❌ Step {N} | ...
```
Or if no stories were ready: `⏸ No stories ready — waiting for PRs to merge`

### Step 2: Check for Epic Completion

From Phase 2 results, collect the batch stories and their PR numbers (e.g. `8.1 → #101, 8.2 → #102`). Pass these as `BATCH_STORIES_WITH_PRS` in the assessment prompt below.

Spawn an **assessment subagent** (`MODEL_STANDARD`, yolo mode):
```
Epic completion assessment. Auto-approve all tool calls (yolo mode).
BATCH_STORIES_WITH_PRS: {coordinator substitutes: "story → #PR" pairs from this batch, one per line}

Read `references/subagents/phase4-assessment.md` and follow its instructions exactly.
```

Using the assessment report:

**If `current_epic_merged = true`:**
1. Print: `🎉 Epic {current_epic_name} is complete! Starting retrospective countdown ({RETRO_TIMER_SECONDS ÷ 60} minutes)...`

   📣 **Notify:** `🎉 Epic {current_epic_name} complete! Running retrospective in {RETRO_TIMER_SECONDS ÷ 60} min...`
2. Start a timer using the **[Timer Pattern](references/coordinator/pattern-timer.md)** with:
   - **Duration:** `RETRO_TIMER_SECONDS`
   - **Fire prompt:** `"BAD_RETRO_TIMER_FIRED — The retrospective countdown has elapsed. Auto-run the retrospective: spawn a MODEL_STANDARD subagent (yolo mode) to run /bmad-retrospective, accept all changes. Run Pre-Continuation Checks after it completes, then proceed to Phase 4 Step 3."`
   - **[C] label:** `Run retrospective now`
   - **[S] label:** `Skip retrospective`
   - **[X] label:** `Stop BAD`
   - **[C] / FIRED action:** Spawn MODEL_STANDARD subagent (yolo mode) to run `/bmad-retrospective`. Accept all changes. Run Pre-Continuation Checks after.
   - **[S] action:** Skip retrospective.
   - **[X] action:** `CronDelete(JOB_ID)`, stop BAD, print final summary, and 📣 **Notify:** `🛑 BAD stopped by user.`
3. Proceed to Step 3 after the retrospective decision resolves.

### Step 3: Gate & Continue

Using the assessment report from Step 2, follow the applicable branch:

**Branch A — All epics complete (`all_epics_complete = true`):**
```
🏁 All epics are complete — sprint is done! BAD is stopping.
```
📣 **Notify:** `🏁 Sprint complete — all epics done! BAD is stopping.`

**Branch B — More work remains:**

1. Print a status line:
   - `current_epic_merged = true` (epic fully landed): `✅ Epic {current_epic_name} complete. Next up: Epic {next_epic_name} ({stories_remaining} stories remaining).`
   - `current_epic_prs_open = true` (all stories have PRs, waiting for merges): `⏸ Epic {current_epic_name} in review — waiting for PRs to merge before continuing.`
   - Otherwise (more stories to develop in current epic): `✅ Batch complete. Ready for the next batch.`
2. Start the wait using the **[Monitor Pattern](references/coordinator/pattern-monitor.md)** (when `MONITOR_SUPPORT=true` **and** `AUTO_PR_MERGE=false`) or the **[Timer Pattern](references/coordinator/pattern-timer.md)** otherwise:

   > **`AUTO_PR_MERGE=true` guard:** When `AUTO_PR_MERGE=true`, Phase 3 already merged all batch PRs before Phase 4 runs. `BATCH_PRS` will be empty, causing the Monitor to fire `ALL_MERGED` immediately with no actual pause. Skip the Monitor path entirely and go directly to the **Timer only** path below — the `WAIT_TIMER_SECONDS` cooldown must still fire before the next batch. The wait exists to give the developer a chance to review the merged changes and course-correct before the next batch begins — never skip or shorten it.

   **If `MONITOR_SUPPORT=true` and `AUTO_PR_MERGE=false` — Monitor + CronCreate fallback:**
   - Fill in `BATCH_PRS` from the Phase 0 pending-PR report (space-separated numbers, e.g. `"101 102 103"`). Use the PR-merge watcher script from [monitor-pattern.md](references/coordinator/pattern-monitor.md) with that value substituted. Save the Monitor handle as `PR_MONITOR`.
   - Also start a CronCreate fallback timer using the [Timer Pattern](references/coordinator/pattern-timer.md) with:
     - **Duration:** `WAIT_TIMER_SECONDS`
     - **Fire prompt:** `"BAD_WAIT_TIMER_FIRED — Max wait elapsed. Stop PR_MONITOR, run Pre-Continuation Checks, then re-run Phase 0."`
     - **[C] label:** `Continue now`
     - **[S] label:** `Stop BAD`
     - **[C] / FIRED action:** Stop `PR_MONITOR`, run Pre-Continuation Checks, then re-run Phase 0.
     - **[S] action:** Stop `PR_MONITOR`, CronDelete, stop BAD, print final summary, and 📣 **Notify:** `🛑 BAD stopped by user.`
   - **On `MERGED: #N` event:** log progress — `✅ PR #N merged — waiting for remaining batch PRs`; keep `PR_MONITOR` running.
   - **On `ALL_MERGED` event:** CronDelete the fallback timer, stop `PR_MONITOR`, run Pre-Continuation Checks, re-run Phase 0.
   - 📣 **Notify:** `⏳ Watching for PR merges (max wait: {WAIT_TIMER_SECONDS ÷ 60} min)...`

   **If `MONITOR_SUPPORT=false` or `AUTO_PR_MERGE=true` — Timer only:**
   - Use the [Timer Pattern](references/coordinator/pattern-timer.md) with:
     - **Duration:** `WAIT_TIMER_SECONDS`
     - **Fire prompt:** `"BAD_WAIT_TIMER_FIRED — The post-batch wait has elapsed. Run Pre-Continuation Checks, then re-run Phase 0, then proceed to Phase 1."`
     - **[C] label:** `Continue now`
     - **[S] label:** `Stop BAD`
     - **[C] / FIRED action:** Run Pre-Continuation Checks, then re-run Phase 0.
     - **[S] action:** Stop BAD, print a final summary, and 📣 **Notify:** `🛑 BAD stopped by user.`

3. After Phase 0 completes:
   - At least one story unblocked → proceed to Phase 1.
   - All stories still blocked → print which PRs are pending (from Phase 0 report), restart Branch B for another wait.

---

## Notify Pattern

Read `references/coordinator/pattern-notify.md` whenever a `📣 Notify:` callout appears. It covers Telegram and terminal output.

---

## Timer Pattern

Read `references/coordinator/pattern-timer.md` when instructed to start a timer. It covers both `TIMER_SUPPORT=true` (CronCreate) and `TIMER_SUPPORT=false` (prompt-based) paths.

---

## Monitor Pattern

Read `references/coordinator/pattern-monitor.md` when `MONITOR_SUPPORT=true`. It covers CI status polling (Step 6) and PR-merge watching (Phase 4 Branch B), plus the `MONITOR_SUPPORT=false` fallback for each.

---

## Watchdog Pattern

Read `references/coordinator/pattern-watchdog.md` when `MONITOR_SUPPORT=true` and the activity log hook is installed (Step 4 of setup). Use it before spawning long-running Phase 2 subagents (Steps 2, 3, 4, 5) to detect hung agents via activity log monitoring.

---

## gh → curl Fallback Pattern

Read `references/coordinator/pattern-gh-curl-fallback.md` when any `gh` command fails (TLS error, sandbox restriction, spending limit, etc.). Pass the path to subagents that run `gh` commands so they can self-recover. Note: `gh pr merge` has no curl fallback — if unavailable, surface the failure to the user.

---

## Rules

1. **Delegate mode only** — never read project files, run git/gh commands, or write to disk yourself. Coordinator-only direct operations are limited to: Pre-Continuation Checks (Bash session-state read, `/reload-plugins`, `/compact`), timer management (CronCreate/CronDelete), channel notifications (Telegram tool), and the Monitor tool for CI/PR polling. All story-level operations are delegated to subagents.
2. **One subagent per step per story** — spawn only after the previous step reports success.
3. **Sequential steps within a story** — Steps 1→2→3→4→5→6→7 run strictly in order.
4. **Parallel stories** — launch all stories' Step 1 in one message (one tool call per story). Phase 3 runs sequentially by design.
5. **Dependency graph is authoritative** — never pick a story whose dependencies are not fully merged. Use Phase 0's report, not your own file reads.
6. **Phase 0 runs before every batch** — always after the Phase 4 wait. Always as a fresh subagent.
7. **Phase 4 wait is mandatory and full-duration** — always use `WAIT_TIMER_SECONDS` unchanged. Never shorten or skip the wait because PRs are already merged or the wait seems unnecessary. The wait gives the developer time to review merged changes and course-correct before the next batch.
8. **Confirm success** before spawning the next subagent.
9. **sprint-status.yaml is updated by step subagents** — each step subagent writes to the repo root copy. The coordinator never does this directly.
10. **On failure** — report the error, halt that story. No auto-retry. **Exception:** rate/usage limit failures → run Pre-Continuation Checks (auto-pauses until reset) then retry.
11. **Issue all Step 1 subagent calls in one response** when Phase 2 begins. After each story's Step 1 completes, issue that story's Step 2 — never wait for all stories' Step 1 to finish before issuing any Step 2. This rolling-start rule applies to all sequential steps within a story.
12. **Pre-Continuation Checks are mandatory at every gate** — run `references/coordinator/gate-pre-continuation.md` between every step spawn, after each Phase 3 merge, and before every Phase 0 re-entry. Never skip or defer these checks, even when handling multiple parallel story completions simultaneously.
