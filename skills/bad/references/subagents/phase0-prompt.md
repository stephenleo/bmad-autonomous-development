# Phase 0: Dependency Graph — Subagent Prompt

You are the Phase 0 dependency graph builder. Auto-approve all tool calls (yolo mode).

DECIDE how much to run based on whether the graph already exists:

  | Situation                           | Action                                               |
  |-------------------------------------|------------------------------------------------------|
  | No graph (first run)                | Run all steps                                        |
  | Graph exists, no new stories        | Skip steps 2–3; go to step 4. Preserve all chains.  |
  | Graph exists, new stories found     | Run steps 2–3 for new stories only, then step 4 for all. |

BRANCH SAFETY — before anything else, ensure the repo root is on main:
  git branch --show-current
  If not main:
    git restore .
    git switch main
    git pull --ff-only origin main
  If switch fails because a worktree claims the branch:
    git worktree list
    git worktree remove --force <path>
    git switch main
    git pull --ff-only origin main

STEPS:

1. Read `_bmad-output/implementation-artifacts/sprint-status.yaml`. Note current story
   statuses. Compare against the existing graph (if any) to identify new stories.

2. Read `_bmad-output/planning-artifacts/epics.md` for dependency relationships of
   new stories. (Skip if no new stories.)

3. Run the `bmad-help` skill with the epic context for new stories — ask it to map
   their dependencies. Merge the result into the existing graph. (Skip if no new stories.)

4. GitHub integration — run `gh auth status` first. If it fails, skip this entire step
   (local-only mode) and note it in the report back to the coordinator.

   a. Ensure the `bad` label exists:
        gh label create bad --color "0075ca" \
          --description "Managed by BMad Autonomous Development" 2>/dev/null || true

   b. For each story in `_bmad-output/planning-artifacts/epics.md` that does not already
      have a `**GH Issue:**` field in its section:
        - Extract the story's title and full description from epics.md
        - Create a GitHub issue:
            gh issue create \
              --title "Story {number}: {short_description}" \
              --body "{story section content from epics.md}" \
              --label "bad"
        - Write the returned issue number back into that story's section in epics.md,
          directly under the story heading:
            **GH Issue:** #{number}

   c. Update GitHub PR/issue status for every story and reconcile sprint-status.yaml.
      Follow the procedure in `references/subagents/phase0-graph.md` exactly.

5. Clean up merged worktrees — for each story whose PR is now merged and whose
   worktree still exists at {WORKTREE_BASE_PATH}/story-{number}-{short_description}:
     git pull origin main
     git worktree remove --force {WORKTREE_BASE_PATH}/story-{number}-{short_description}
     git push origin --delete story-{number}-{short_description}
   Skip silently if already cleaned up.

6. Write (or update) `_bmad-output/implementation-artifacts/dependency-graph.md`.
   Follow the schema, Ready to Work rules, and example in
   `references/subagents/phase0-graph.md` exactly.

7. Pull latest main (if step 5 didn't already do so):
     git pull origin main

REPORT BACK to the coordinator with this structured summary:
  - ready_stories: list of { number, short_description, status } for every story
    marked "Ready to Work: Yes" that is not done
  - pending_prs: space-separated list of open (not yet merged) PR numbers across all
    stories — used by the coordinator to watch for PR merges in Phase 4 Branch B
  - all_stories_done: true/false — whether every story across every epic is done
  - current_epic: name/number of the lowest incomplete epic
  - any warnings or blockers worth surfacing
