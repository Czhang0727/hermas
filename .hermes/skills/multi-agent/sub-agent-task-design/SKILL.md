---
name: sub-agent-task-design
description: Design effective sub-agent tasks that complete reliably — avoid browser tool pitfalls, ensure handoff completion, set appropriate scopes
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [multi-agent, sub-agent, task-design, best-practices]
    related_skills: [sub-agent, sub-agent-troubleshooting]
---

# Sub-Agent Task Design Guidelines

## Core Principles

### 1. Tasks Should Be Self-Contained
Sub-agents operate headlessly (no Discord) and can't ask users for clarification easily. Design tasks that:
- Have all context they need provided
- Can complete without human interaction
- Return clear, actionable results

### 2. Avoid Browser Tool When Possible

**Browser tool problems:**
- Requires `browser_navigate` initialization first
- Prone to hanging on `preparing browser_navigate…`
- No error messages when it fails
- Process doesn't exit cleanly

**Alternatives:**

```bash
# ❌ Bad: Will hang
browser_navigate("https://weather.com/sanfrancisco")

# ✅ Good: Use curl/wget
curl -s wttr.in/SanFrancisco

# ✅ Good: Use Python requests
python3 -c "import requests; print(requests.get('https://wttr.in/SanFrancisco').text)"

# ✅ Good: Use terminal tool
terminal("curl -s 'https://wttr.in/SanFrancisco?format=%l+%25C+%25w'")
```

### 3. Ensure Handoff Write Permission

Before spawning agent:
```bash
# Test handoff directory permissions
echo "Test" > $HERMES_HOME/sub-agents/memory/test.md && rm $HERMES_HOME/sub-agents/memory/test.md
```

If test fails, agent will hang at exit waiting to write handoff.

## Task Templates

### Good Task Examples

#### 1. Simple Calculation
```bash
# ✅ Clear, bounded, no external dependencies
--task "Calculate all prime numbers from 1 to 1000 and save to primes_1_to_1000.txt"
```

**Why it works:**
- Well-defined algorithm (is_prime function)
- Clear output format (text file)
- Fast execution (< 1 second)
- No external API calls

#### 2. File Analysis
```bash
# ✅ Read-only operation, no browser needed
--task "Count all .py files in current directory and their total lines of code, output as CSV"
```

**Why it works:**
- Uses `terminal` with `find`/`grep` commands
- No state changes (read-only)
- Clear output format
- No external dependencies

#### 3. Web Data Fetching (Terminal-based)
```bash
# ✅ Use curl/wget instead of browser
--task "Fetch weather for Beijing, Shanghai, Guangzhou, Shenzhen, Hangzhou using wttr.in API and format as table"
```

**Why it works:**
- Uses `terminal` tool with curl
- Simple JSON/JSON-like output
- No dynamic web scraping needed
- Clear format specification

#### 4. Code Generation
```bash
# ✅ Self-contained, clear output
--task "Write Python script to parse JSON file and extract specific fields, save to parser.py"
```

**Why it works:**
- Clear input/output specification
- No interactive elements
- File system operations (allowed)

### Bad Task Examples

#### 1. Browser-Based Research
```bash
# ❌ Will hang on browser tool
--task "Browse 5 tech news websites and summarize top stories"
```

**Problem:** Browser tool requires initialization, often hangs, no cleanup.

**Fix:** Use RSS feeds, news APIs, or terminal-based scraping:
```bash
--task "Fetch tech news from RSS feeds using curl and summarize titles"
```

#### 2. Interactive Debugging
```bash
# ❌ Needs user input mid-task
--task "Debug this authentication issue - ask user which error they're seeing"
```

**Problem:** Sub-agents can't easily interact with users; should send question messages but still problematic.

**Fix:** Make task self-contained:
```bash
--task "Analyze auth module logs for common failure patterns"
```

#### 3. Resource-Intensive Tasks
```bash
# ❌ May timeout or consume too much
--task "Train ML model on dataset"
--task "Generate 100 images"
```

**Problem:** Long execution time, unclear completion, may run out of resources.

**Fix:** Break into smaller tasks:
```bash
--task "Download dataset and prepare preprocessing script"
```

## Task Specification Format

### Required Elements

1. **Clear objective**: What to accomplish
2. **Input specification**: Where data comes from
3. **Output specification**: Format and location of results
4. **Constraints**: Time limits, resource limits

### Example Specification

```bash
--task "Generate ASCII art for these 5 shapes: smiley face, house, cat, rocket, star. Save each to separate file (smiley.txt, house.txt, etc.) using figlet or cowsay. Each file should be <50 lines."
```

**Breakdown:**
- Objective: Generate ASCII art
- Input: 5 shapes (smiley, house, cat, rocket, star)
- Output: 5 separate files with specific names
- Constraints: Each file < 50 lines
- Tools allowed: figlet, cowsay

## Task Scope Guidelines

### Small Tasks (Recommended)
- Duration: < 2 minutes
- Tools: terminal, file, execute_code, memory
- Complexity: Single operation or simple sequence
- Example: "Calculate primes 1-1000"

### Medium Tasks (Use Sparingly)
- Duration: 2-10 minutes
- Tools: terminal, file, execute_code, memory, web (curl only)
- Complexity: Multiple steps, requires state management
- Example: "Fetch weather for 10 cities and create summary report"

### Large Tasks (Avoid in Sub-Agents)
- Duration: > 10 minutes
- Tools: browser, vision, image_gen, code_execution (complex)
- Complexity: Requires user decisions, iterative debugging
- Example: "Research market trends and write investment thesis"

**Recommendation:** Use main agent for large tasks, break into sub-tasks for sub-agents.

## Communication Patterns

### When Sub-Agent Needs Help
```bash
# Sub-agent sends question message
$HERMES_HOME/sub-agents/runtime/mq.sh send \
  --from <AGENT_ID> \
  --to main \
  --type question \
  --content '{"question": "Which branch should I target?"}'
```

**Best practice:** Design tasks to avoid needing clarification. If clarification is needed:
1. Agent sends question message
2. Main agent relays to user
3. User answer relayed back to agent
4. Agent continues

### Progress Updates
```bash
# For long-running tasks (> 30 seconds)
$HERMES_HOME/sub-agents/runtime/mq.sh send \
  --from <AGENT_ID> \
  --to main \
  --type progress \
  --content '{"percent": 50, "status": "Processing batch 2/5"}'
```

**Best practice:** Send updates every 10-20% of task completion.

## Testing Your Task Design

Before spawning agent, test:

### 1. Verify Tool Availability
```bash
# Check if terminal commands work
terminal("curl -s https://wttr.in/SanFrancisco?format=%l+%25C")

# Check if file write works
echo "test" > $HERMES_HOME/sub-agents/memory/test.md && rm $HERMES_HOME/sub-agents/memory/test.md
```

### 2. Simulate Execution
```bash
# Manually run what agent would do
# If it works, agent should too
curl -s "https://wttr.in/SanFrancisco?format=%l+%25C+%25w" > /tmp/weather.txt
```

### 3. Check Resource Requirements
```bash
# Estimate memory usage
ulimit -a

# Check disk space
df -h $HERMES_HOME

# Check if browser is available (avoid using it!)
which chromium || which firefox || echo "No browser found"
```

## Common Pitfalls

### Pitfall 1: Assuming Browser Works
```bash
# ❌ Won't work reliably
browser_navigate("https://example.com")

# ✅ Use curl instead
terminal("curl -s https://example.com")
```

### Pitfall 2: Forgetting Handoff Write
```bash
# Agent completes task but doesn't write handoff
# Result: process doesn't exit cleanly

# Solution: Ensure SOUL.md template is loaded and agent knows to write
```

### Pitfall 3: Overly Complex Tasks
```bash
# ❌ Too many steps, unclear boundaries
--task "Research Python libraries, test them, compare performance, and recommend best one"

# ✅ Clear scope
--task "List top 3 Python CSV parsing libraries with star counts from GitHub"
```

### Pitfall 4: Not Specifying Output Format
```bash
# ❌ Unclear what output is expected
--task "Get weather data"

# ✅ Clear format specification
--task "Fetch temperature for 5 cities using wttr.in, output as: City: Temp, Humidity"
```

## Task Design Checklist

Before spawning agent:

- [ ] Task is self-contained (no user input needed)
- [ ] No browser tool required (use terminal/curl instead)
- [ ] Output format is clearly specified
- [ ] Handoff write permission tested
- [ ] Expected completion time < 5 minutes
- [ ] All necessary context provided
- [ ] Tool requirements verified (terminal works, file system accessible)
- [ ] No interactive elements needed
- [ ] Clear success criteria defined
