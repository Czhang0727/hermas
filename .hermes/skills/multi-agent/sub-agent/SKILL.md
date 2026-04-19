---
name: sub-agent
description: Spawn and manage Hermes sub-agents for parallel task delegation
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [multi-agent, sub-agent, delegation, parallel-tasks]
    related_skills: [merge-learnings]
---

# Sub-Agent Management

## Overview

Manage sub-agent delegation using two complementary approaches:

- **Built-in `delegate_task`** — Lightweight, in-process threads for quick parallel work. No memory write access, no skill creation. Use for fast, disposable tasks.
- **Custom `spawn-agent.sh`** — Full Hermes instances with memory write-back and skill learning. Use for tasks that should persist knowledge.

See the **Decision Guide** below for when to use which.

The sub-agent lifecycle has three phases:

1. **Spawn** — Create a new headless agent with curated memory and a specific task.
2. **Monitor & Relay** — Check status, relay user questions, send control messages.
3. **Collect** — Read the handoff file, merge learnings, and clean up.

All sub-agent paths are rooted at `$HERMES_HOME/sub-agents/`.

## Decision Guide: Which Delegation Method?

Hermes has **two** delegation mechanisms. Choose based on the task:

| Criteria | Built-in `delegate_task` | Custom `spawn-agent.sh` |
|----------|--------------------------|------------------------|
| **Best for** | Quick, focused, parallel lookups | Long-running tasks that should persist learnings |
| **Startup time** | ~0s (in-process thread) | ~5-10s (full Hermes instance) |
| **Memory write** | Blocked — subagents cannot update MEMORY.md | Full access — subagent has native `memory` tool |
| **Skill creation** | Not supported | Supported via handoff + merge-learnings |
| **Concurrency** | Up to 3 parallel (configurable) | Unlimited |
| **Process isolation** | None (same process) | Full OS process isolation |
| **Communication** | Synchronous return | Async via SQLite message queue |

### Use `delegate_task` when:
- Task is short (< 5 minutes)
- No memory updates needed — results are consumed immediately
- Parallel execution of 2-3 independent lookups
- Examples: weather checks, web searches, code analysis, data formatting

### Use `spawn-agent.sh` when:
- Task produces knowledge that should be remembered (memory back-propagation)
- Task follows a procedure that could become a reusable skill
- Task needs full tool access (including execute_code, memory)
- Task is long-running or needs user interaction mid-flight
- Task needs full process isolation (security-sensitive)
- Examples: research projects, bug investigations, architecture design, workflow automation

## Using Built-in delegate_task

You already have `delegate_task` as a native tool. Use it directly:

### Single task:
```
delegate_task(goal="Find the top 3 Python EPUB parsing libraries", context="Looking for async support and active maintenance")
```

### Parallel tasks (up to 3):
```
delegate_task(tasks=[
  {"goal": "Get weather for San Francisco", "toolsets": ["terminal"]},
  {"goal": "Get weather for New York", "toolsets": ["terminal"]},
  {"goal": "Get weather for Tokyo", "toolsets": ["terminal"]}
])
```

### Configuration (in config.yaml):
```yaml
delegation:
  model: "google/gemini-flash-2.0"  # Optional: cheaper model for subagents
  max_concurrent_children: 3         # Max parallel tasks
  max_iterations: 50                 # Turns per subagent
```

**Limitations:** Built-in subagents cannot write to memory, create skills, use execute_code, or call delegate_task recursively.

## Tool Access Differences: delegate_task vs spawn-agent.sh

**Critical distinction between the two sub-agent methods:**

| Feature | `delegate_task` | `spawn-agent.sh` |
|---------|-----------------|------------------|
| **Browser tool** | ✅ Works (uses main agent's Camofox/headless Chromium) | ❌ Requires browser drivers (Chromium/Camofox not installed) |
| **Environment** | Main agent's full process | Independent Hermes instance |
| **CLI tools** | ✅ Full access | ✅ Full access |
| **Discord** | ✅ Enabled | ❌ Disabled (headless) |

**Recommendation:** When using `spawn-agent.sh`, prefer CLI tools (`terminal`, `web`) over browser tools. If browser automation is essential, ensure browser drivers are installed in the sub-agent environment.

## Quick Start

The fastest path to spawning a sub-agent and collecting results:

```bash
# 1. (Optional) Write a memory file with task-relevant context
cat > /tmp/research-memory.md << 'EOF'
§ The project uses Rust with Tokio for async runtime
§ Database migrations are managed by sqlx-cli
§ The API follows REST conventions with JSON responses
EOF

# 2. Spawn the sub-agent
$HERMES_HOME/sub-agents/spawn-agent.sh \
  --role researcher \
  --task "Research best practices for Rust async error handling with this stack" \
  --memory-file /tmp/research-memory.md

# Output:
# AGENT_ID=abc123-def456-...
# PID=12345
# PORT=18800
# MODE=cli
# LOG=$HERMES_HOME/sub-agents/logs/abc123-def456-....log

# 3. Wait for a result message in your inbox
$HERMES_HOME/sub-agents/runtime/mq.sh receive --agent main

# 4. Read the handoff and merge learnings
cat $HERMES_HOME/sub-agents/memory/<AGENT_ID>.md
# Then invoke the merge-learnings skill to absorb memory updates
```

## Phase 1: Spawn (spawn-agent.sh)

### Curating Memory for Injection

Sub-agents start with no prior context. You must inject only the memory they need via a `--memory-file`. The file uses `§`-delimited entries — one fact per line, each starting with `§`.

**Format:**

```
§ Fact or context entry the sub-agent needs
§ Another relevant piece of information
§ File path, decision, or convention to be aware of
```

**Good memory selection** — only task-relevant context:

```
§ The project uses Python 3.11 with FastAPI
§ API keys are loaded from .env, never hardcoded
§ Tests run with pytest in the tests/ directory
§ The user prefers descriptive variable names over brevity
```

**Bad memory selection** — dumping everything:

```
§ I am a Hermes agent running on macOS
§ The Discord bot token is stored in .env
§ I like to use vim for editing
§ Yesterday I helped with a Docker issue
§ The weather was nice today
```

Guidelines:
- Include only facts the sub-agent needs to complete its task.
- Include relevant file paths, conventions, and prior decisions.
- Include user preferences that affect the task outcome.
- Do NOT include credentials, tokens, or unrelated context.
- When in doubt, include less. The sub-agent can ask questions if it needs more.

### Spawning a Sub-Agent

```bash
$HERMES_HOME/sub-agents/spawn-agent.sh \
  --role ROLE \
  --task "TASK DESCRIPTION" \
  [--model MODEL] \
  [--mode MODE] \
  [--memory-file PATH]
```

**Required arguments:**

| Flag | Description |
|------|-------------|
| `--role ROLE` | Agent role label (e.g., `researcher`, `coder`, `analyst`) |
| `--task "TASK"` | Task description the agent will execute |

**Optional arguments:**

| Flag | Default | Description |
|------|---------|-------------|
| `--model MODEL` | `qwen/qwen3.5-35b-a3b` | LLM model ID for the sub-agent |
| `--mode MODE` | `cli` | Run mode: `cli` or `gateway` |
| `--memory-file PATH` | (none) | Path to a file with §-delimited memory entries |

**Modes:**

- **CLI mode** (default) — Single-shot execution. The agent receives its task, completes it, and exits. Best for focused, self-contained tasks like research, analysis, or code generation.

- **Gateway mode** — Starts a full Hermes gateway instance. The agent stays running and can be interacted with via the message queue. Best for long-running or interactive tasks that require back-and-forth communication.

**Output format:**

```
AGENT_ID=<uuid>
PID=<process-id>
PORT=<allocated-port>
MODE=<cli|gateway>
LOG=$HERMES_HOME/sub-agents/logs/<agent-id>.log
```

Save the `AGENT_ID` — you need it for monitoring, relaying, and collecting results.

**Examples:**

```bash
# Simple research task with default model
$HERMES_HOME/sub-agents/spawn-agent.sh \
  --role researcher \
  --task "Research Rust async patterns"

# Coding task with a stronger model and memory injection
$HERMES_HOME/sub-agents/spawn-agent.sh \
  --role coder \
  --task "Fix bug #42 in the auth module" \
  --model openai/gpt-4o \
  --memory-file /tmp/auth-context.md

# Long-running analysis in gateway mode
$HERMES_HOME/sub-agents/spawn-agent.sh \
  --role analyst \
  --task "Monitor and summarize the deployment logs" \
  --mode gateway
```

## Phase 2: Monitor & Relay

### Checking Status

List all agents or filter by status:

```bash
# List all agents
python3 $HERMES_HOME/sub-agents/runtime/manager.py list

# List only running agents
python3 $HERMES_HOME/sub-agents/runtime/manager.py list --status running

# List completed agents
python3 $HERMES_HOME/sub-agents/runtime/manager.py list --status completed

# List failed agents
python3 $HERMES_HOME/sub-agents/runtime/manager.py list --status failed
```

Get detailed status for a specific agent:

```bash
python3 $HERMES_HOME/sub-agents/runtime/manager.py status --agent-id <AGENT_ID>
```

Output includes: Agent ID, Role, Status, PID, Port, Task, Created timestamp, and Completed timestamp (if applicable).

### Reading Messages

Read all pending messages from your inbox (non-blocking):

```bash
$HERMES_HOME/sub-agents/runtime/mq.sh receive --agent main
```

This returns each message as a JSON object on its own line. An empty inbox returns `[]`. Messages are removed from the inbox after reading.

Wait for a message (blocking, with timeout):

```bash
# Wait up to 30 seconds (default)
$HERMES_HOME/sub-agents/runtime/mq.sh wait --agent main

# Wait up to 120 seconds
$HERMES_HOME/sub-agents/runtime/mq.sh wait --agent main --timeout 120
```

Peek at messages without removing them:

```bash
$HERMES_HOME/sub-agents/runtime/mq.sh peek --agent main
```

Count pending messages:

```bash
$HERMES_HOME/sub-agents/runtime/mq.sh count --agent main
```

**Message envelope format:**

```json
{
  "id": "msg-uuid",
  "from": "sender-agent-id",
  "to": "recipient-agent-id",
  "type": "message-type",
  "timestamp": "2026-04-17T12:00:00Z",
  "content": { ... }
}
```

**Message types from sub-agents:**

| Type | Purpose | Content Example |
|------|---------|-----------------|
| `progress` | Status updates during long-running work | `{"percent": 40, "status": "Processing batch 2/5"}` |
| `question` | Needs user input or clarification | `{"question": "Which branch should I target?"}` |
| `result` | Final output of the task (sent by complete-agent.sh) | `{"agent_id": "...", "validation": "complete", "summary": "..."}` |
| `error` | Unrecoverable problem | `{"error": "Permission denied", "suggestion": "Need sudo access"}` |

### Relaying User Questions

When a sub-agent sends a `question` type message:

1. **Read it** from your inbox:
   ```bash
   $HERMES_HOME/sub-agents/runtime/mq.sh receive --agent main
   ```

2. **Present it** to the user on Discord — rephrase naturally, include context about which sub-agent is asking.

3. **Get the user's answer** from Discord.

4. **Send it back** to the sub-agent:
   ```bash
   $HERMES_HOME/sub-agents/runtime/mq.sh send \
     --from main \
     --to <AGENT_ID> \
     --type task \
     --content '{"answer": "user response here"}'
   ```

The sub-agent will pick up the answer on its next inbox check.

### Sending Control Messages

Send a stop signal to a sub-agent:

```bash
$HERMES_HOME/sub-agents/runtime/mq.sh send \
  --from main \
  --to <AGENT_ID> \
  --type control \
  --content '{"action": "stop"}'
```

Send additional instructions or context mid-task:

```bash
$HERMES_HOME/sub-agents/runtime/mq.sh send \
  --from main \
  --to <AGENT_ID> \
  --type task \
  --content '{"instruction": "Also check the migration files in db/migrations/"}'
```

### Flush an Inbox

Delete all messages for an agent (useful for clearing stale messages):

```bash
$HERMES_HOME/sub-agents/runtime/mq.sh flush --agent <AGENT_ID>
```

## Phase 3: Collect

### Reading the Handoff

When `complete-agent.sh` detects the sub-agent process has exited, it:
1. Validates the handoff file exists at `$HERMES_HOME/sub-agents/memory/<AGENT_ID>.md`
2. Checks that all required sections are present
3. Extracts any skill recommendation
4. Sends a `result` message to the main agent's inbox
5. Deregisters the agent from the registry

The `result` message content includes:

```json
{
  "agent_id": "<AGENT_ID>",
  "validation": "complete|incomplete|missing_handoff",
  "missing_sections": "none|## Section1 ## Section2",
  "skill_recommendation": "NEW_SKILL: ...|UPDATE_SKILL: ...|NO_SKILL",
  "handoff_path": "$HERMES_HOME/sub-agents/memory/<AGENT_ID>.md",
  "summary": "<first 20 lines of handoff>"
}
```

**Validation statuses:**

| Status | Meaning |
|--------|---------|
| `complete` | Handoff file exists with all required sections |
| `incomplete` | Handoff file exists but is missing one or more sections |
| `missing_handoff` | No handoff file was found — the agent may have crashed |

**Required handoff sections:**

The handoff file must contain these sections:

1. `## Task Summary` — What was accomplished and the approach taken
2. `## Process Log` — Step-by-step record of what the agent did
3. `## Key Findings` — Important discoveries, decisions, results
4. `## Memory Updates` — Entries the main agent should absorb
5. `## Skill Recommendation` — One of `NEW_SKILL:`, `UPDATE_SKILL:`, or `NO_SKILL`

Read the full handoff:

```bash
cat $HERMES_HOME/sub-agents/memory/<AGENT_ID>.md
```

### Invoking merge-learnings

After reading the handoff, invoke the `merge-learnings` skill to:
- Absorb the `## Memory Updates` section into your own memory
- Handle `NEW_SKILL` recommendations by creating a new skill draft from `$HERMES_HOME/sub-agents/skills-draft/<AGENT_ID>/`
- Handle `UPDATE_SKILL` recommendations by updating the existing skill

### Cleanup

Remove dead agents from the registry (marks any running agent whose process is no longer alive as `failed`):

```bash
python3 $HERMES_HOME/sub-agents/runtime/manager.py cleanup
```

This checks each running agent's PID with `os.kill(pid, 0)` and marks unresponsive ones as failed.

## Common Patterns

### Pattern 1: Quick Research Task

Spawn a researcher to find information while you continue other work.

```bash
# Spawn the researcher
$HERMES_HOME/sub-agents/spawn-agent.sh \
  --role researcher \
  --task "Find the best Python library for parsing EPUB files and summarize the top 3 options" \
  --memory-file /tmp/epub-context.md

# ... continue your own work ...

# Check for results later
$HERMES_HOME/sub-agents/runtime/mq.sh receive --agent main

# Read the handoff
cat $HERMES_HOME/sub-agents/memory/<AGENT_ID>.md
```

### Pattern 2: Parallel Coding Tasks

Spawn multiple coders for independent modules.

```bash
# Spawn coder for auth module
$HERMES_HOME/sub-agents/spawn-agent.sh \
  --role coder \
  --task "Implement JWT refresh token rotation in src/auth/" \
  --memory-file /tmp/auth-context.md

# Spawn coder for API module (gets a different AGENT_ID)
$HERMES_HOME/sub-agents/spawn-agent.sh \
  --role coder \
  --task "Add rate limiting middleware to src/middleware/" \
  --memory-file /tmp/rate-limit-context.md

# Check on both
python3 $HERMES_HOME/sub-agents/runtime/manager.py list --status running

# Collect results as they come in
$HERMES_HOME/sub-agents/runtime/mq.sh receive --agent main
```

### Pattern 3: User-in-the-Loop

Handle sub-agent questions that need user input.

```bash
# Spawn an agent
$HERMES_HOME/sub-agents/spawn-agent.sh \
  --role coder \
  --task "Refactor the database layer" \
  --mode gateway

# Later, check inbox for questions
$HERMES_HOME/sub-agents/runtime/mq.sh receive --agent main
# Returns: {"type": "question", "content": {"question": "Should I use SQLAlchemy or raw SQL?"}}

# Present to user on Discord, get answer, relay back
$HERMES_HOME/sub-agents/runtime/mq.sh send \
  --from main \
  --to <AGENT_ID> \
  --type task \
  --content '{"answer": "Use SQLAlchemy with the async extension"}'
```

## Error Handling

### Sub-agent crash

If a sub-agent crashes or exits unexpectedly:

1. Check the log file:
   ```bash
   cat $HERMES_HOME/sub-agents/logs/<AGENT_ID>.log
   ```
2. Run cleanup to mark it as failed in the registry:
   ```bash
   python3 $HERMES_HOME/sub-agents/runtime/manager.py cleanup
   ```
3. Decide whether to re-spawn or handle the task yourself.

### Agent completed but didn't exit normally

**Common issue:** Sub-agents may complete their tasks (files created, code written) but not exit cleanly, often when using certain tools like `browser_navigate`.

**How to verify task completion:**

```bash
# Check if output files exist
ls -la <expected-output-file>

# Check agent process still running
ps aux | grep <PID>

# Check log for completion messages
tail -n 50 $HERMES_HOME/sub-agents/logs/<AGENT_ID>.log
```

**When files exist but agent is stuck:**
1. Assume the task succeeded
2. Read the output files directly
3. Run `cleanup` to mark agent as failed
4. Don't wait for normal exit

### Timeout

If a sub-agent is taking too long:

1. Find its PID:
   ```bash
   python3 $HERMES_HOME/sub-agents/runtime/manager.py status --agent-id <AGENT_ID>
   ```
2. Kill the process:
   ```bash
   kill <PID>
   ```
3. Run cleanup:
   ```bash
   python3 $HERMES_HOME/sub-agents/runtime/manager.py cleanup
   ```

### Missing handoff

If `complete-agent.sh` reports `missing_handoff` validation status:
- The sub-agent may have crashed before writing the handoff file.
- Check the log for errors: `cat $HERMES_HOME/sub-agents/logs/<AGENT_ID>.log`
- The agent's result message will still arrive but with `validation: "missing_handoff"`.
- You may need to reconstruct what the agent accomplished from the log file.

### SQLite MQ unavailable

If message queue commands fail with connection errors:

1. Check if the mq.db file is writable:
   ```bash
   ls -la $HERMES_HOME/sub-agents/runtime/mq.db
   ```
2. Check disk space:
   ```bash
   df -h $HERMES_HOME
   ```
3. Verify WAL mode is enabled:
   ```bash
   sqlite3 $HERMES_HOME/sub-agents/runtime/mq.db "PRAGMA journal_mode;"
   # Should return: wal
   ```

## Troubleshooting

| Problem | Check Command | Fix |
|---------|--------------|-----|
| Agent not responding | `cat $HERMES_HOME/sub-agents/logs/<AGENT_ID>.log` | Check log for errors; kill and re-spawn if stuck |
| Agent not in registry | `python3 $HERMES_HOME/sub-agents/runtime/manager.py list` | Agent may have completed or been cleaned up |
| No messages arriving | `$HERMES_HOME/sub-agents/runtime/mq.sh count --agent main` | Check SQLite MQ is accessible; check agent status |
| SQLite MQ errors | `ls -la $HERMES_HOME/sub-agents/runtime/mq.db` | Check file permissions and disk space |
| Port allocation failure | `python3 $HERMES_HOME/sub-agents/runtime/manager.py list --status running` | Too many running agents; cleanup dead ones first |
| Stale messages in inbox | `$HERMES_HOME/sub-agents/runtime/mq.sh flush --agent <ID>` | Flush the inbox to clear stale messages |
