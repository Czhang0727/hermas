---
name: merge-learnings
description: Absorb sub-agent learnings into main agent memory and create/update skills from sub-agent workflows
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [multi-agent, memory, skill-creation, learning]
    related_skills: [sub-agent]
---

# Merge Learnings

## Overview

This skill is invoked after a sub-agent (spawned via `spawn-agent.sh`) completes its task. It implements a two-step process to curate what the main agent should absorb into its native Hermes memory and whether the workflow should become a reusable skill.

This skill hooks directly into the native Hermes memory pipeline — all memory operations use the built-in `memory` tool which writes to `$HERMES_HOME/memories/MEMORY.md` using §-delimited entries with a 2,200-character limit.

**Note:** This skill is NOT needed for built-in `delegate_task` results — those are ephemeral and don't produce structured handoffs. Use this only for `spawn-agent.sh` sub-agents.

## Memory Pipeline

The merge-learnings process connects sub-agent output to the main agent's native memory system:

```
Sub-agent writes handoff → complete-agent.sh validates → Redis MQ notifies main
    → main reads handoff → merge-learnings reviews → native memory(add/replace/remove)
    → MEMORY.md updated on disk (§-delimited, 2200 char limit)
```

**Important:** Memory writes take effect on disk immediately but are NOT reflected in the current session's system prompt (Hermes uses a frozen snapshot pattern — memory changes appear in the NEXT session). This is normal behavior.

## When to Use

- After receiving a `result` message from a sub-agent (via `complete-agent.sh`)
- The result message contains: `agent_id`, `validation status`, `skill_recommendation`, `handoff_path`
- Read the full handoff file before proceeding

## Step 1: Review & Select

### Reading the Handoff

```bash
cat $HERMES_HOME/sub-agents/memory/<agent-id>.md
```

Read the entire handoff file. You need the full context before making decisions about what to absorb.

### Reviewing Memory Updates

The `## Memory Updates` section contains entries formatted as:

```
ACTION: add | CONTENT: "fact to remember"
ACTION: replace | OLD: "outdated fact" | CONTENT: "corrected fact"
ACTION: remove | OLD: "fact to forget"
```

**Decision criteria for each entry:**

- Is this fact accurate based on what you know?
- Is it novel (not already in your memory)?
- Is it broadly useful (not just for this one task)?
- Is it concise enough for memory (remember: MEMORY.md has a 2,200 char limit)?

**Skip entries that are:**

- Duplicates of existing memory — if you already know this fact, skip it
- Task-specific details unlikely to be useful again
- Unverified claims (if uncertain, skip or verify first)
- Too verbose (consolidate into shorter form)
- Already captured by a previous sub-agent's merge

### Reviewing Skill Recommendation

The `## Skill Recommendation` section says one of:

- `NEW_SKILL: [name]` — the sub-agent thinks it developed a novel procedure
- `UPDATE_SKILL: [existing-skill-name]` — the sub-agent refined an existing workflow
- `NO_SKILL` — one-off task, no reusable pattern

**Decision criteria:**

- Does the `## Process Log` show a repeatable, multi-step procedure?
- Would another agent benefit from having this as a skill?
- For `UPDATE_SKILL`: does the existing skill actually need updating?
- For `NO_SKILL`: confirm the process was truly one-off

**Skip if already learned:** Before creating or updating a skill, check if an equivalent skill already exists in `$HERMES_HOME/skills/`. If a skill covering the same procedure is already present and up-to-date, **simply ignore** the recommendation — do not create duplicates or make unnecessary updates. Only act on `NEW_SKILL` if the procedure is genuinely novel, and only act on `UPDATE_SKILL` if there is meaningful new information the existing skill lacks.

## Step 2: Execute & Polish

### Absorbing Memory Updates

For each selected memory update, use your native `memory` tool:

```
memory(action="add", target="memory", content="The /api/v2/users endpoint requires Bearer auth")
memory(action="replace", target="memory", old_text="Redis 6.x", content="Project uses Redis 7.2")
memory(action="remove", target="memory", old_text="outdated fact to remove")
```

**Tips:**

- Execute one at a time, verify each succeeds
- If memory is near capacity (check the usage % in your system prompt), consolidate existing entries first
- Prefer replacing outdated entries over adding new ones
- Remember: memory writes update the disk file immediately, but your current session's system prompt snapshot won't change. The updates will be visible in your next session.

### Creating a New Skill (NEW_SKILL)

1. Read the sub-agent's draft: `$HERMES_HOME/sub-agents/skills-draft/<agent-id>/SKILL.md`
2. If no draft exists, create one from the `## Process Log`

**Polish checklist:**

- Add proper YAML frontmatter:
  ```yaml
  ---
  name: <skill-name>
  description: <one-line description>
  version: 1.0.0
  author: Hermes Agent
  license: MIT
  metadata:
    hermes:
      tags: [relevant, tags]
      related_skills: [related-skill-names]
  ---
  ```
- Structure with clear sections: Overview, When to Use, Steps, Examples, Troubleshooting
- Remove agent-specific details (agent IDs, timestamps, etc.)
- Make instructions generic and reusable
- Add concrete examples

3. Choose a category (browse existing categories in `$HERMES_HOME/skills/` for reference)
4. Write to: `$HERMES_HOME/skills/<category>/<skill-name>/SKILL.md`
5. Verify the file is valid Markdown

### Updating an Existing Skill (UPDATE_SKILL)

1. Read the existing skill: `$HERMES_HOME/skills/<category>/<skill-name>/SKILL.md`
2. Read the sub-agent's process log and draft
3. Identify what's new: additional steps, edge cases, corrections, better examples
4. Merge carefully:
   - Add new sections/steps where appropriate
   - Update outdated information
   - Add new examples or troubleshooting entries
   - Bump the version number in frontmatter
   - Do NOT remove existing content unless it is wrong
5. Write the updated skill file

### Reporting to User

After completing both memory and skill updates, report to the user:

- Number of memory entries absorbed (and any skipped with reasons)
- If a new skill was created: name, category, and brief description
- If an existing skill was updated: what was changed
- Any concerns or items that need user verification

### Cleanup

After merging is complete, **delete the remaining artifacts** to keep disk usage low:

```bash
# Delete handoff file (already absorbed into memory)
rm -f $HERMES_HOME/sub-agents/memory/<agent-id>.md

# Delete log file
rm -f $HERMES_HOME/sub-agents/logs/<agent-id>.log

# Delete skills draft directory
rm -rf $HERMES_HOME/sub-agents/skills-draft/<agent-id>/
```

**Note:** The instance directory (`instances/<agent-id>/`) is already auto-deleted by `complete-agent.sh` right after the handoff is validated. You only need to clean up these remaining files.

Do NOT skip cleanup — sub-agent artifacts accumulate fast (each instance can be 10+ MB).

## Skill Naming Conventions

- Use lowercase kebab-case: `api-testing`, `docker-deployment`
- Be specific but concise: `redis-caching` not `how-to-use-redis-for-caching`
- Match existing category names when possible

## Category Selection Guide

Browse `$HERMES_HOME/skills/` to see existing categories. Common ones:

- `software-development` — coding practices, debugging, testing
- `devops` — deployment, CI/CD, infrastructure
- `research` — information gathering, analysis
- `multi-agent` — sub-agent coordination, handoff processing, memory management

Create a new category only if nothing fits.

## Examples

### Example 1: Simple Memory Absorption

A sub-agent returns a handoff with these memory updates:

```
## Memory Updates
ACTION: add | CONTENT: "Redis connection string is stored in REDIS_URL env var, not config.yaml"
ACTION: add | CONTENT: "Sub-agent abc-123 ran for 14 minutes on 2025-04-17"
ACTION: replace | OLD: "Redis listens on default port 6379" | CONTENT: "Redis listens on port 6380 in production"
```

**Review:**

- Entry 1: Novel, broadly useful — **absorb**.
- Entry 2: Task-specific detail with agent ID and timestamp — **skip**.
- Entry 3: Corrects existing memory — **absorb**.

**Execute:**

```
memory(action="add", target="memory", content="Redis connection string is stored in REDIS_URL env var, not config.yaml")
memory(action="replace", target="memory", old_text="Redis listens on default port 6379", content="Redis listens on port 6380 in production")
```

**Report:** "Absorbed 2 of 3 memory updates. Skipped 1 (task-specific detail)."

### Example 2: New Skill Creation

A sub-agent's handoff says:

```
## Skill Recommendation
NEW_SKILL: docker-healthcheck -- the sub-agent developed a repeatable procedure for adding health checks to Docker containers, including compose integration and test verification
```

The sub-agent also wrote a draft at `$HERMES_HOME/sub-agents/skills-draft/abc-123/SKILL.md`.

**Steps:**

1. Read the draft.
2. Polish: add frontmatter, remove agent-specific references, add a Troubleshooting section.
3. Category: `devops` (already exists).
4. Write to: `$HERMES_HOME/skills/devops/docker-healthcheck/SKILL.md`
5. Verify valid Markdown.

**Report:** "Created new skill `docker-healthcheck` in category `devops`. Covers adding health checks to Docker containers with compose integration and test verification."

### Example 3: Skill Update

A sub-agent's handoff says:

```
## Skill Recommendation
UPDATE_SKILL: plan -- discovered that plan files should include a "Rollback Strategy" section for infrastructure changes
```

**Steps:**

1. Read the existing skill at `$HERMES_HOME/skills/software-development/plan/SKILL.md`.
2. Read the sub-agent's process log — it shows the rollback section was needed on 3 separate tasks.
3. Add a "Rollback Strategy" bullet to the Output Requirements section.
4. Bump version from 1.0.0 to 1.1.0.
5. Write the updated file.

**Report:** "Updated skill `plan` (v1.0.0 → v1.1.0). Added 'Rollback Strategy' to output requirements, based on 3 infra tasks where it was needed."

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Handoff file not found at expected path | Check `complete-agent.sh` output for the actual `handoff_path`. The sub-agent may have written it to a non-default location. |
| Sub-agent's draft SKILL.md is empty or missing | Reconstruct from the `## Process Log` section of the handoff. Use the log entries as step-by-step instructions. |
| Memory update fails (capacity limit) | Consolidate existing memory entries first. Merge related facts into single entries. Remove the lowest-value entries. |
| Unsure whether a skill recommendation is valid | Err on the side of NOT creating a skill. You can always create it later if the pattern recurs. Premature skills add noise. |
| Existing skill to update is not found | Search `$HERMES_HOME/skills/` recursively for the skill name. The sub-agent may have used a slightly different name. If truly missing, treat it as NEW_SKILL instead. |
| Two sub-agents recommend conflicting memory updates | Trust the more recent one, but verify against your own knowledge. If unsure, skip both and flag for user review. |
