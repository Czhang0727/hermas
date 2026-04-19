#!/bin/bash
set -euo pipefail

# ─── Sub-Agent Spawner ───
# Spawns a new headless Hermes sub-agent instance from the template.
# Uses the conda hermes-agent environment.

# ─── Paths ───
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Defaults ───
ROLE=""
TASK=""
MODEL="qwen/qwen3.5-35b-a3b"
MODE="cli"
MEMORY_FILE=""

# ─── Colors ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── Usage ───
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Spawn a new headless Hermes sub-agent instance.

Required:
  --role ROLE          Agent role (e.g., "researcher", "coder")
  --task "TASK"        Task description for the agent

Optional:
  --model MODEL        LLM model ID (default: qwen/qwen3.5-35b-a3b)
  --mode MODE          Run mode: cli|gateway (default: cli)
  --memory-file PATH   Path to a file with §-delimited memory entries to inject
  -h, --help           Show this help message

Examples:
  $(basename "$0") --role researcher --task "Research Rust async patterns"
  $(basename "$0") --role coder --task "Fix bug #42" --model openai/gpt-4o
  $(basename "$0") --role analyst --task "Summarize logs" --mode gateway
EOF
}

# ─── Parse Arguments ───
while [[ $# -gt 0 ]]; do
    case "$1" in
        --role)
            ROLE="$2"
            shift 2
            ;;
        --task)
            TASK="$2"
            shift 2
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --mode)
            MODE="$2"
            shift 2
            ;;
        --memory-file)
            MEMORY_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1\n$(usage)"
            ;;
    esac
done

# ─── Validate Required Arguments ───
if [[ -z "$ROLE" ]]; then
    error "Missing required --role argument\n$(usage)"
fi
if [[ -z "$TASK" ]]; then
    error "Missing required --task argument\n$(usage)"
fi
if [[ "$MODE" != "cli" && "$MODE" != "gateway" ]]; then
    error "Invalid --mode: $MODE (must be 'cli' or 'gateway')"
fi

# ─── Generate Agent ID ───
AGENT_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
info "Generated agent ID: $AGENT_ID"

# ─── Set Paths ───
BASE_DIR="$SCRIPT_DIR"
INSTANCE_DIR="$BASE_DIR/instances/$AGENT_ID/.hermes"
RUNTIME_DIR="$BASE_DIR/runtime"
MQ="$RUNTIME_DIR/mq.sh"
MANAGER="$RUNTIME_DIR/manager.py"

info "Instance directory: $INSTANCE_DIR"

# ─── Step 5: Create Instance Directory from Template ───
mkdir -p "$INSTANCE_DIR"
cp "$BASE_DIR/template/config.yaml" "$INSTANCE_DIR/config.yaml"
cp "$BASE_DIR/template/SOUL.md" "$INSTANCE_DIR/SOUL.md"
info "Copied template files"

# ─── Step 6: Symlink Skills from Main Agent ───
# Main agent's skills are at hermas/.hermes/skills/
ln -sf "$SCRIPT_DIR/../skills" "$INSTANCE_DIR/skills"
info "Symlinked skills directory"

# ─── Step 7: Replace Placeholders in config.yaml ───
PORT=$(python3 "$MANAGER" allocate-port)
info "Allocated port: $PORT"

# Read API key from .env file first, fall back to environment
API_KEY=$(grep '^OPENROUTER_API_KEY=' "$SCRIPT_DIR/../.env" 2>/dev/null | cut -d'=' -f2-)
if [[ -z "$API_KEY" ]]; then
    API_KEY="${OPENROUTER_API_KEY:-}"
fi
if [[ -z "$API_KEY" ]]; then
    error "OPENROUTER_API_KEY not found in $SCRIPT_DIR/../.env and not set in environment"
fi


sed -i '' "s|__PORT__|$PORT|g" "$INSTANCE_DIR/config.yaml"
sed -i '' "s|__API_KEY__|$API_KEY|g" "$INSTANCE_DIR/config.yaml"
sed -i '' "s|__MODEL__|$MODEL|g" "$INSTANCE_DIR/config.yaml"
info "Config placeholders replaced (port, api_key, model=$MODEL)"

# ─── Step 8: Replace Placeholders in SOUL.md ───
HANDOFF_PATH="$BASE_DIR/memory/${AGENT_ID}.md"
SKILLS_DRAFT_PATH="$BASE_DIR/skills-draft/${AGENT_ID}"

sed -i '' "s|__AGENT_ID__|$AGENT_ID|g" "$INSTANCE_DIR/SOUL.md"
sed -i '' "s|__HANDOFF_PATH__|$HANDOFF_PATH|g" "$INSTANCE_DIR/SOUL.md"
sed -i '' "s|__SKILLS_DRAFT_PATH__|$SKILLS_DRAFT_PATH|g" "$INSTANCE_DIR/SOUL.md"
info "SOUL.md placeholders replaced"

# ─── Step 9: Append Role and Task to SOUL.md ───
cat >> "$INSTANCE_DIR/SOUL.md" << EOF

---

## Your Assignment

**Role**: $ROLE
**Task**: $TASK
EOF
info "Appended role ($ROLE) and task to SOUL.md"

# ─── Step 10: Create Memories Directory and Inject Memory ───
mkdir -p "$INSTANCE_DIR/memories"
if [[ -n "${MEMORY_FILE:-}" ]] && [[ -f "$MEMORY_FILE" ]]; then
    cp "$MEMORY_FILE" "$INSTANCE_DIR/memories/MEMORY.md"
    info "Injected memory from $MEMORY_FILE"
fi

# ─── Step 11: Create Skills-Draft Directory ───
mkdir -p "$BASE_DIR/skills-draft/$AGENT_ID"

# ─── Step 12: Send Initial Task Message via MQ ───
# Escape the task for JSON
TASK_JSON=$(echo "$TASK" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
"$MQ" send --from main --to "$AGENT_ID" --type task --content "{\"role\": \"$ROLE\", \"task\": $TASK_JSON}"
info "Sent initial task message to agent inbox"

# ─── Step 13: Launch the Agent ───
LOG_FILE="$BASE_DIR/logs/${AGENT_ID}.log"

# Ensure log directory exists
mkdir -p "$BASE_DIR/logs"

if [[ "$MODE" = "gateway" ]]; then
    HERMES_HOME="$INSTANCE_DIR" OPENROUTER_API_KEY="$API_KEY" conda run -n hermes-agent hermes gateway run > "$LOG_FILE" 2>&1 &
    AGENT_PID=$!
else
    # CLI mode - single shot
    HERMES_HOME="$INSTANCE_DIR" OPENROUTER_API_KEY="$API_KEY" conda run -n hermes-agent hermes chat -q "You are a sub-agent. Read your initial task from your message inbox using: $MQ receive --agent $AGENT_ID  Then execute the task following your SOUL.md instructions." -Q > "$LOG_FILE" 2>&1 &
    AGENT_PID=$!
fi
info "Launched agent (PID=$AGENT_PID, mode=$MODE)"

# ─── Step 14: Register Agent ───
python3 "$MANAGER" register --agent-id "$AGENT_ID" --role "$ROLE" --pid "$AGENT_PID" --port "$PORT" --task "$TASK"
info "Registered agent in registry"

# ─── Step 15: Chain Completion Script (Background) ───
(wait $AGENT_PID 2>/dev/null; "$BASE_DIR/complete-agent.sh" --agent-id "$AGENT_ID") &
info "Completion watcher started"

# ─── Step 16: Output Result ───
echo "AGENT_ID=$AGENT_ID"
echo "PID=$AGENT_PID"
echo "PORT=$PORT"
echo "MODE=$MODE"
echo "LOG=$LOG_FILE"
