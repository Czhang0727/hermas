#!/bin/bash

# 修复后的 launch 部分

mkdir -p "$BASE_DIR/logs"

if [[ "$MODE" = "gateway" ]]; then
    HERMES_HOME="$INSTANCE_DIR" conda run -n hermes-agent hermes gateway run > "$LOG_FILE" 2>&1 &
    AGENT_PID=$!
else
    # CLI mode - single shot (no -q to avoid premature exit)
    # 正确的命令格式：hermes chat -Q <任务描述>
    
    TASK_CMD="hermes chat -Q \"Read your task from message inbox using: \$MQ receive --agent \$AGENT_ID. Execute it following your SOUL.md instructions.\""
    
    HERMES_HOME="$INSTANCE_DIR" conda run -n hermes-agent $TASK_CMD > "$LOG_FILE" 2>&1 &
    AGENT_PID=$!
fi

info "Launched agent (PID=$AGENT_PID, mode=$MODE)"
