---
name: sub-agent-troubleshooting
description: Diagnose and fix common Hermes sub-agent issues — hanging processes, browser tool failures, handoff write problems
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [multi-agent, sub-agent, troubleshooting, debugging]
    related_skills: [sub-agent]
---

# Sub-Agent Troubleshooting Guide

## 🔥 Critical: API Key & Configuration Issues (2026-04-18)

### Issue: 401 Unauthorized on Sub-Agent Startup

**Symptoms:**
- Error in logs: `credential_pool: marking OPENROUTER_API_KEY exhausted`
- Error message: `User not found` or `Invalid API key`
- Session fails immediately after starting

**Root Cause:** 
1. `config.yaml` has hardcoded masked API key like `api_key: "sk-or-...f285"` instead of using env vars
2. Sub-agent instance doesn't have `.env` file to inherit credentials
3. `spawn-agent.sh` has broken environment variable export syntax

**Fixes:**

#### Fix 1: Remove hardcoded API key from config.yaml
```yaml
# In ~/.hermes/config.yaml - line ~15
model:
  provider: "openrouter"
  # ❌ WRONG - has placeholder key
  api_key: "sk-or-...f285"
  
  # ✅ CORRECT - use environment variable
  # api_key: ""  # Comment out or set empty to use OPENROUTER_API_KEY from env
```

#### Fix 2: Verify .env file has complete API key
```bash
# Check ~/.hermes/.env
cat ~/.hermes/.env | grep OPENROUTER
# Should have: OPENROUTER_API_KEY=sk-or-v1-actual-full-key-here (73 chars)
# NOT: OPENROUTER_API_KEY=***  (incomplete)
```

#### Fix 3: Verify spawn-agent.sh exports env vars correctly
```bash
# Check spawn-agent.sh around lines 170-180
grep -n "export.*API_KEY" $HERMES_HOME/sub-agents/spawn-agent.sh

# ✅ CORRECT:
export OPENROUTER_API_KEY=$(grep '^OPENROUTER_API_KEY=' ~/.hermes/.env | cut -d'=' -f2-)

# ❌ WRONG - broken heredoc/sed syntax:
export OPENROUTER_API_KEY=*** '^OPENROUTER_API_KEY=*** ~/.hermes/.env | cut -d'=' -f2-)
```

#### Fix 4: Ensure .env is copied to instance directory
```bash
# In spawn-agent.sh around line 119-120, ensure this line exists:
cp ~/.hermes/.env "$INSTANCE_DIR/.env"
```

### Quick Diagnostic Checklist

When a sub-agent hangs or fails, run these commands in order:

### 1. Check Agent Status
```bash
python3 $HERMES_HOME/sub-agents/runtime/manager.py list --status running
```

### 2. Check Process Alive
```bash
ps aux | grep -E "PID=<AGENT_PID>" | grep -v grep
```

### 3. Check Logs for Completion Status
```bash
tail -n 20 $HERMES_HOME/sub-agents/logs/<AGENT_ID>.log
# Look for:
# - "session_id:" at the end → agent is waiting
# - No "complete-agent.sh" execution → agent process didn't exit
# - Tool-specific prep messages → which tool is hanging
```

### 4. Check Handoff Files
```bash
ls -la $HERMES_HOME/sub-agents/memory/*.md
# If missing, agent didn't write handoff before exiting
```

### 5. Check Message Queue
```bash
$HERMES_HOME/sub-agents/runtime/mq.sh receive --agent main
# Empty array [] means no messages in inbox
```

## Common Issues and Fixes

### Issue 1: Missing Template Files

**Symptoms:**
```
cp: /Users/chenyzh/.../template/sub-agent-SOUL.md: No such file or directory
```

**Fix:**
```bash
# Check if template files exist
ls -la $HERMES_HOME/sub-agents/template/

# If missing, re-install hermes agent repo
# or restore from backup
```

### Issue 4: Agent Hangs on Browser Tool

**Symptoms:**
- Log ends with `preparing browser_navigate…` followed by `session_id:`
- No error messages, process doesn't exit

**Cause:** Browser tool needs explicit initialization before use

**Fix:**
```bash
# Option 1: Kill hanging agent and restart with terminal-based approach
kill <AGENT_PID>
python3 $HERMES_HOME/sub-agents/runtime/manager.py cleanup

# Option 2: Use terminal tools instead of browser for simple tasks
# Edit task to use curl/wget/terminal instead of browser_navigate
```

**Prevention:** Tell agents to prefer terminal tools (curl, wget) over browser for simple web requests.

### Issue 5: Agent Doesn't Write Handoff

**Symptoms:**
- Log file very small (< 20 lines)
- No `session_id:` at end of log
- No `.md` file in `sub-agents/memory/`

**Fix:**
```bash
# Check for crash indicators
grep -i -E '(error|exception|panic|crash)' $HERMES_HOME/sub-agents/logs/<AGENT_ID>.log

# Deregister manually if agent is dead
python3 $HERMES_HOME/sub-agents/runtime/manager.py deregister --agent-id <AGENT_ID>
```

### Issue 3: 401/Unauthorized API Errors (New - 2026-04-18)

**Symptoms:**
- `ERROR: Non-retryable client error: Error code: 401`
- `credential_pool: marking OPENROUTER_API_KEY exhausted`
- Agent exits before executing task

**Causes:**
1. `config.yaml` has masked/hardcoded API key
2. `.env` file missing or incomplete in instance directory
3. `spawn-agent.sh` exports broken env vars

**Check:**
```bash
# 1. Check main config.yaml for hardcoded key
grep -A 2 "api_key" ~/.hermes/config.yaml | head -5

# 2. Verify .env file exists and has complete key
cat ~/.hermes/.env | grep OPENROUTER

# 3. Check spawn-agent.sh export syntax
grep -A 1 "export OPENROUTER" $HERMES_HOME/sub-agents/spawn-agent.sh

# 4. Check instance directory has .env
ls -la $HERMES_HOME/sub-agents/instances/<AGENT_ID>/.hermes/.env
```

**Solutions:**
- Comment out `api_key` line in config.yaml
- Add full API key to `~/.hermes/.env`
- Ensure `spawn-agent.sh` copies `.env` to instance directory
- Verify export syntax in spawn-agent.sh

### Issue 4: Agent Hangs on Browser Tool

**Symptoms:**
- Log ends with `preparing browser_navigate…` followed by `session_id:`
- No error messages, process doesn't exit

**Cause:** Browser tool needs explicit initialization before use

**Fix:**
```bash
# Option 1: Kill hanging agent and restart with terminal-based approach
kill <AGENT_PID>
python3 $HERMES_HOME/sub-agents/runtime/manager.py cleanup

# Option 2: Use terminal tools instead of browser for simple tasks
# Edit task to use curl/wget/terminal instead of browser_navigate
```

**Prevention:** Tell agents to prefer terminal tools (curl, wget) over browser for simple web requests.

### Issue 2: Agent Doesn't Write Handoff

**Symptoms:**
- Agent process exits but no `.md` file in memory directory
- Log ends mid-execution without handoff write

**Cause:**
- Agent crashed before writing handoff
- Handoff write blocked on file system
- Memory tool not being used to save findings

**Fix:**
```bash
# Check log for crash indicators
grep -i -E '(error|exception|panic|crash)' $HERMES_HOME/sub-agents/logs/<AGENT_ID>.log

# If agent is dead, deregister manually
python3 $HERMES_HOME/sub-agents/runtime/manager.py deregister --agent-id <AGENT_ID>
```

**Prevention:**
- Ensure agent knows to write handoff in SOUL.md template
- Use `memo` tool for Apple Notes if available on target system
- Test handoff write permission before spawning

### Issue 3: SQLite MQ Connection Failures

**Symptoms:**
- `mq.sh` commands fail with connection errors
- Agent can't receive task or send results

**Fix:**
```bash
# Check if mq.db file exists and is writable
ls -la $HERMES_HOME/sub-agents/runtime/mq.db

# Check disk space
df -h $HERMES_HOME

# Verify WAL mode is enabled
sqlite3 $HERMES_HOME/sub-agents/runtime/mq.db "PRAGMA journal_mode;"
# Should return: wal

# Flush stale agent messages
$HERMES_HOME/sub-agents/runtime/mq.sh flush --agent <AGENT_ID>
```

### Issue 4: Agent Process Dies Before Completion

**Symptoms:**
- Agent registered but never writes handoff
- Log file very small (< 20 lines)
- `complete-agent.sh` never executes

**Diagnosis:**
```bash
# Check if process exists
ps -p <AGENT_PID>

# Check for resource limits
ulimit -a

# Check system logs for OOM killer
sudo grep -i "out of memory" /var/log/syslog | tail -5
```

**Fix:**
```bash
# Kill zombie process
kill -9 <AGENT_PID>

# Cleanup registry
python3 $HERMES_HOME/sub-agents/runtime/manager.py cleanup

# Re-spawn with more reasonable task scope
```

### Issue 5: Timeout Without Exit

**Symptoms:**
- Agent runs indefinitely
- No progress updates in log
- No errors or completion signals

**Diagnosis:**
```bash
# Check what tool is being prepared
tail -n 10 $HERMES_HOME/sub-agents/logs/<AGENT_ID>.log

# Look for patterns:
# "preparing <tool>…" → that tool is hanging
# "session_id:" at end → waiting for tool response
```

**Fix:**
```bash
# Send stop signal via message queue
$HERMES_HOME/sub-agents/runtime/mq.sh send \
  --from main \
  --to <AGENT_ID> \
  --type control \
  --content '{"action": "stop"}'

# If that fails, kill process
kill -9 <AGENT_PID>
python3 $HERMES_HOME/sub-agents/runtime/manager.py cleanup
```

## Prevention Best Practices

### 1. Use Appropriate Tools for Sub-Agents

**Preferred tools for sub-agents:**
- `terminal` - shell commands, curl, wget
- `file` - read/write files
- `execute_code` - Python scripts
- `memory` - save findings

**Avoid in sub-agents:**
- `browser` - requires initialization, often hangs
- `vision` - image analysis, can be slow
- `image_gen` - resource intensive

### 2. Set Clear Task Boundaries

Good sub-agent tasks:
- ✅ "Calculate primes 1-1000 and save to file"
- ✅ "Find all .py files and count lines of code"
- ✅ "Research Python error handling patterns"

Bad sub-agent tasks:
- ❌ "Browse 50 websites and summarize" (too long)
- ❌ "Navigate to dynamic web app and extract data" (browser hangs)
- ❌ "Interactive debugging session" (needs user feedback)

### 3. Use Short Timeouts

For long-running sub-agent tasks, implement timeout monitoring:
```bash
# Monitor agent with timeout
timeout 600 bash -c "wait $AGENT_PID || echo 'Agent timed out'"
```

### 4. Test Handoff Write Permission

Before spawning agents in new environment:
```bash
# Test handoff write permission
echo "Test" > $HERMES_HOME/sub-agents/memory/test.md && rm $HERMES_HOME/sub-agents/memory/test.md
```

## Recovery Procedures

### Full Cleanup
```bash
# Kill all sub-agent processes
python3 $HERMES_HOME/sub-agents/runtime/manager.py cleanup

# Flush all message queue
$HERMES_HOME/sub-agents/runtime/mq.sh flush --agent main

# Clean up any orphaned handoff files
rm -f $HERMES_HOME/sub-agents/memory/*.md
```

### Re-Spawn Agent
```bash
# After cleanup, re-spawn with same or modified task
$HERMES_HOME/sub-agents/spawn-agent.sh \
  --role <role> \
  --task "<task>" \
  --memory-file <context-file>
```

## Advanced Debugging

### Enable Verbose Logging
```bash
# Set debug level for agent instance
export HERMES_DEBUG=1
```

### Monitor Agent Process
```bash
# Watch agent process activity
watch -n 1 "ps -p <AGENT_PID> -o pid,pcpu,pmem,cmd"
```

### Check System Resources
```bash
# Check memory usage
free -h

# Check disk space
df -h $HERMES_HOME

# Check process limits
ulimit -a
```

### Analyze Agent Memory Dump
```bash
# If agent has memory tool access, check saved findings
cat ~/.hermes/memory.md
```

## Communication Protocol

When sub-agent needs help:
1. Sends `question` type message via MQ
2. Main agent presents to user
3. User answer relayed back via MQ
4. Agent continues with new information

When main agent wants to stop:
1. Sends `control` message with `action: stop`
2. Agent should complete current step and exit
3. If unresponsive, kill process directly
