#!/bin/bash
set -euo pipefail

# ─── Sub-Agent Completion Handler ───
# Post-completion wrapper: validates handoff, extracts skill recommendations,
# sends result message to main agent, and deregisters from the registry.

# ─── Paths ───
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Defaults ───
AGENT_ID=""

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

Handle post-completion tasks for a sub-agent instance.

Required:
  --agent-id AGENT_ID   The agent ID to complete

Optional:
  -h, --help            Show this help message

Examples:
  $(basename "$0") --agent-id abc123-def456-...
EOF
}

# ─── Parse Arguments ───
while [[ $# -gt 0 ]]; do
    case "$1" in
        --agent-id)
            AGENT_ID="$2"
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
if [[ -z "$AGENT_ID" ]]; then
    error "Missing required --agent-id argument\n$(usage)"
fi

# ─── Set Paths ───
BASE_DIR="$SCRIPT_DIR"
RUNTIME_DIR="$BASE_DIR/runtime"
MQ="$RUNTIME_DIR/mq.sh"
MANAGER="$RUNTIME_DIR/manager.py"
HANDOFF="$BASE_DIR/memory/${AGENT_ID}.md"

info "Processing completion for agent: $AGENT_ID"

# ─── Instance directory (for cleanup later) ───
INSTANCE_DIR="$BASE_DIR/instances/$AGENT_ID"

# ─── Early check: Handle missing handoff gracefully ───
# If agent failed before writing a handoff file, avoid crash from set -euo pipefail
if [[ ! -f "$HANDOFF" ]]; then
    warn "Handoff file not found at $HANDOFF — agent likely failed before producing output"
    python3 "$MANAGER" deregister --agent-id "$AGENT_ID"
    "$MQ" send --from "$AGENT_ID" --to main --type result --content "{\"agent_id\": \"$AGENT_ID\", \"validation\": \"failed\", \"missing_sections\": \"all\", \"skill_recommendation\": \"NO_SKILL\", \"handoff_path\": \"$HANDOFF\", \"summary\": \"Agent failed without producing a handoff file.\"}"
    info "Deregistered failed agent and notified main"
    # Clean up instance directory immediately for failed agents
    if [[ -d "$INSTANCE_DIR" ]]; then
        rm -rf "$INSTANCE_DIR"
        info "Cleaned up instance directory for failed agent"
    fi
    exit 0
fi

# ─── Step 4: Validate Handoff Exists ───
VALIDATION_STATUS="complete"
if [[ ! -f "$HANDOFF" ]]; then
    warn "Handoff file not found at $HANDOFF"
    VALIDATION_STATUS="missing_handoff"
fi

# ─── Step 5: Check Required Sections ───
MISSING_SECTIONS=()
if [[ -f "$HANDOFF" ]]; then
    REQUIRED_SECTIONS=("## Task Summary" "## Process Log" "## Key Findings" "## Memory Updates" "## Skill Recommendation")
    for section in "${REQUIRED_SECTIONS[@]}"; do
        if ! grep -q "$section" "$HANDOFF"; then
            MISSING_SECTIONS+=("$section")
        fi
    done
fi

# ─── Step 6: Extract Skill Recommendation ───
SKILL_REC="NO_SKILL"
if [[ -f "$HANDOFF" ]]; then
    if grep -q "NEW_SKILL:" "$HANDOFF" 2>/dev/null; then
        SKILL_REC=$(grep "NEW_SKILL:" "$HANDOFF" | head -1)
    elif grep -q "UPDATE_SKILL:" "$HANDOFF" 2>/dev/null; then
        SKILL_REC=$(grep "UPDATE_SKILL:" "$HANDOFF" | head -1)
    fi
fi

# ─── Step 7: Build Validation Status ───
if [[ "$VALIDATION_STATUS" != "missing_handoff" ]]; then
    if [[ ${#MISSING_SECTIONS[@]} -eq 0 ]]; then
        VALIDATION_STATUS="complete"
    else
        VALIDATION_STATUS="incomplete"
    fi
fi

info "Validation status: $VALIDATION_STATUS"
if [[ ${#MISSING_SECTIONS[@]} -gt 0 ]]; then
    warn "Missing sections: ${MISSING_SECTIONS[*]}"
fi

# ─── Step 8: Send Result Message to Main Agent ───
SUMMARY=$(head -20 "$HANDOFF" 2>/dev/null | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" || echo '""')

"$MQ" send --from "$AGENT_ID" --to main --type result --content "{\"agent_id\": \"$AGENT_ID\", \"validation\": \"$VALIDATION_STATUS\", \"missing_sections\": \"${MISSING_SECTIONS[*]:-none}\", \"skill_recommendation\": $(echo "$SKILL_REC" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))"), \"handoff_path\": \"$HANDOFF\", \"summary\": $SUMMARY}"
info "Sent result message to main agent"

# ─── Step 9: Update Registry ───
python3 "$MANAGER" deregister --agent-id "$AGENT_ID"
info "Deregistered agent from registry"

# ─── Step 10: Clean Up Instance Directory ───
# The handoff file is saved at memory/<agent-id>.md (outside the instance).
# The instance dir contains a full .hermes/ copy (state.db, sessions, etc) — delete it to save disk.
if [[ -d "$INSTANCE_DIR" ]]; then
    rm -rf "$INSTANCE_DIR"
    info "Cleaned up instance directory (handoff preserved at $HANDOFF)"
fi

# ─── Step 11: Print Completion Summary ───
echo "Agent $AGENT_ID completed"
echo "Validation: $VALIDATION_STATUS"
echo "Skill recommendation: $SKILL_REC"
echo "Handoff: $HANDOFF"
