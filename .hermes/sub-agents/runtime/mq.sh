#!/bin/bash
set -euo pipefail

# SQLite WAL Message Queue Layer for Inter-Agent Messaging
# Replaces Redis with a zero-dependency SQLite backend using Python3 stdlib.
# All database operations are delegated to inline Python3 scripts.
# Bash handles argument parsing; Python3 handles all DB/JSON work.

# Resolve the directory where this script lives so mq.db is colocated
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_PATH="${SCRIPT_DIR}/mq.db"

# ---------------------------------------------------------------------------
# Helper: run inline Python3 against the shared mq.db
#   $1  — the Python3 code to execute
#   remaining args are forwarded as sys.argv for the script
# ---------------------------------------------------------------------------
run_python() {
    local code="$1"; shift
    python3 -c "$code" "$@"
}

# ---------------------------------------------------------------------------
# Schema bootstrap — idempotent; called once before every command
# ---------------------------------------------------------------------------
init_db() {
    run_python '
import sqlite3, os

db = os.environ["MQ_DB_PATH"]
conn = sqlite3.connect(db)
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("""
    CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        from_agent TEXT NOT NULL,
        to_agent TEXT NOT NULL,
        type TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at REAL DEFAULT (unixepoch('"'"'subsec'"'"'))
    )
""")
conn.execute("""
    CREATE INDEX IF NOT EXISTS idx_to_agent
    ON messages(to_agent)
""")
conn.commit()
conn.close()
' >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Send a message to an agent
# Usage: send --from AGENT --to AGENT --type TYPE --content 'JSON_STRING'
# Prints: message ID
# ---------------------------------------------------------------------------
cmd_send() {
    local from_agent=""
    local to_agent=""
    local msg_type=""
    local content=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from)   from_agent="$2"; shift 2 ;;
            --to)     to_agent="$2";   shift 2 ;;
            --type)   msg_type="$2";   shift 2 ;;
            --content) content="$2";   shift 2 ;;
            *)
                echo "Error: Unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    if [[ -z "$from_agent" || -z "$to_agent" || -z "$msg_type" || -z "$content" ]]; then
        echo "Error: Missing required arguments for send command" >&2
        echo "Usage: send --from AGENT --to AGENT --type TYPE --content 'JSON_STRING'" >&2
        return 1
    fi

    init_db

    run_python '
import sqlite3, uuid, json, os, sys
from datetime import datetime, timezone

db        = os.environ["MQ_DB_PATH"]
from_a    = sys.argv[1]
to_a      = sys.argv[2]
msg_type  = sys.argv[3]
content   = sys.argv[4]

msg_id    = str(uuid.uuid4())
timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# Validate that content is valid JSON; store as-is
parsed = json.loads(content)

conn = sqlite3.connect(db)
conn.execute("PRAGMA journal_mode=WAL")
conn.execute(
    "INSERT INTO messages (id, from_agent, to_agent, type, timestamp, content) VALUES (?, ?, ?, ?, ?, ?)",
    (msg_id, from_a, to_a, msg_type, timestamp, json.dumps(parsed)),
)
conn.commit()
conn.close()
print(msg_id)
' "$from_agent" "$to_agent" "$msg_type" "$content"
}

# ---------------------------------------------------------------------------
# Receive all messages for an agent (non-blocking, removes messages)
# Usage: receive --agent AGENT
# Prints: each message JSON on a separate line, or [] if none
# ---------------------------------------------------------------------------
cmd_receive() {
    local agent=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent) agent="$2"; shift 2 ;;
            *)
                echo "Error: Unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    if [[ -z "$agent" ]]; then
        echo "Error: Missing required --agent argument" >&2
        echo "Usage: receive --agent AGENT" >&2
        return 1
    fi

    init_db

    run_python '
import sqlite3, json, os, sys

db    = os.environ["MQ_DB_PATH"]
agent = sys.argv[1]

conn = sqlite3.connect(db)
conn.execute("PRAGMA journal_mode=WAL")
conn.row_factory = sqlite3.Row

rows = conn.execute(
    "SELECT * FROM messages WHERE to_agent=? ORDER BY created_at ASC",
    (agent,),
).fetchall()

if rows:
    ids = [r["id"] for r in rows]
    conn.execute(
        "DELETE FROM messages WHERE id IN ({})".format(",".join("?" * len(ids))),
        ids,
    )
    conn.commit()

    for r in rows:
        print(json.dumps({
            "id":        r["id"],
            "from":      r["from_agent"],
            "to":        r["to_agent"],
            "type":      r["type"],
            "timestamp": r["timestamp"],
            "content":   json.loads(r["content"]),
        }))
else:
    print("[]")

conn.close()
' "$agent"
}

# ---------------------------------------------------------------------------
# Wait for a message (blocking with polling)
# Usage: wait --agent AGENT [--timeout SECONDS]
# Prints: message JSON, or null on timeout
# ---------------------------------------------------------------------------
cmd_wait() {
    local agent=""
    local timeout=30

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent)   agent="$2";   shift 2 ;;
            --timeout) timeout="$2"; shift 2 ;;
            *)
                echo "Error: Unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    if [[ -z "$agent" ]]; then
        echo "Error: Missing required --agent argument" >&2
        echo "Usage: wait --agent AGENT [--timeout SECONDS]" >&2
        return 1
    fi

    init_db

    run_python '
import sqlite3, json, os, sys, time

db      = os.environ["MQ_DB_PATH"]
agent   = sys.argv[1]
timeout = float(sys.argv[2])

deadline = time.time() + timeout

while True:
    conn = sqlite3.connect(db)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.row_factory = sqlite3.Row

    row = conn.execute(
        "SELECT * FROM messages WHERE to_agent=? ORDER BY created_at ASC LIMIT 1",
        (agent,),
    ).fetchone()

    if row:
        conn.execute("DELETE FROM messages WHERE id=?", (row["id"],))
        conn.commit()
        conn.close()
        print(json.dumps({
            "id":        row["id"],
            "from":      row["from_agent"],
            "to":        row["to_agent"],
            "type":      row["type"],
            "timestamp": row["timestamp"],
            "content":   json.loads(row["content"]),
        }))
        sys.exit(0)

    conn.close()

    if time.time() >= deadline:
        print("null")
        sys.exit(0)

    time.sleep(0.5)
' "$agent" "$timeout"
}

# ---------------------------------------------------------------------------
# Peek at all pending messages without removing them
# Usage: peek --agent AGENT
# Prints: JSON array of messages
# ---------------------------------------------------------------------------
cmd_peek() {
    local agent=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent) agent="$2"; shift 2 ;;
            *)
                echo "Error: Unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    if [[ -z "$agent" ]]; then
        echo "Error: Missing required --agent argument" >&2
        echo "Usage: peek --agent AGENT" >&2
        return 1
    fi

    init_db

    run_python '
import sqlite3, json, os, sys

db    = os.environ["MQ_DB_PATH"]
agent = sys.argv[1]

conn = sqlite3.connect(db)
conn.execute("PRAGMA journal_mode=WAL")
conn.row_factory = sqlite3.Row

rows = conn.execute(
    "SELECT * FROM messages WHERE to_agent=? ORDER BY created_at ASC",
    (agent,),
).fetchall()
conn.close()

messages = [
    {
        "id":        r["id"],
        "from":      r["from_agent"],
        "to":        r["to_agent"],
        "type":      r["type"],
        "timestamp": r["timestamp"],
        "content":   json.loads(r["content"]),
    }
    for r in rows
]
print(json.dumps(messages))
' "$agent"
}

# ---------------------------------------------------------------------------
# Flush all messages for an agent
# Usage: flush --agent AGENT
# ---------------------------------------------------------------------------
cmd_flush() {
    local agent=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent) agent="$2"; shift 2 ;;
            *)
                echo "Error: Unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    if [[ -z "$agent" ]]; then
        echo "Error: Missing required --agent argument" >&2
        echo "Usage: flush --agent AGENT" >&2
        return 1
    fi

    init_db

    run_python '
import sqlite3, os, sys

db    = os.environ["MQ_DB_PATH"]
agent = sys.argv[1]

conn = sqlite3.connect(db)
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("DELETE FROM messages WHERE to_agent=?", (agent,))
conn.commit()
conn.close()
print(f"Flushed inbox for agent: {agent}")
' "$agent"
}

# ---------------------------------------------------------------------------
# Count pending messages for an agent
# Usage: count --agent AGENT
# Prints: integer count
# ---------------------------------------------------------------------------
cmd_count() {
    local agent=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent) agent="$2"; shift 2 ;;
            *)
                echo "Error: Unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    if [[ -z "$agent" ]]; then
        echo "Error: Missing required --agent argument" >&2
        echo "Usage: count --agent AGENT" >&2
        return 1
    fi

    init_db

    run_python '
import sqlite3, os, sys

db    = os.environ["MQ_DB_PATH"]
agent = sys.argv[1]

conn = sqlite3.connect(db)
conn.execute("PRAGMA journal_mode=WAL")
(count,) = conn.execute(
    "SELECT COUNT(*) FROM messages WHERE to_agent=?",
    (agent,),
).fetchone()
conn.close()
print(count)
' "$agent"
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat << EOF
SQLite WAL Message Queue Layer for Inter-Agent Messaging

Usage: $0 <command> [options]

Commands:
  send --from AGENT --to AGENT --type TYPE --content 'JSON_STRING'
    Send a message to an agent. Prints the message ID.

  receive --agent AGENT
    Receive all pending messages for an agent (non-blocking).
    Prints each message JSON on a separate line, or [] if none.

  wait --agent AGENT [--timeout SECONDS]
    Wait for a message (blocking). Default timeout is 30 seconds.
    Prints the message JSON, or null on timeout.

  peek --agent AGENT
    Peek at all pending messages without removing them.
    Prints messages as a JSON array.

  flush --agent AGENT
    Delete all messages for an agent.

  count --agent AGENT
    Count pending messages for an agent.

Database:
  $DB_PATH  (SQLite WAL mode, zero external deps)

Examples:
  $0 send --from manager --to coding --type task --content '{"task": "review code"}'
  $0 receive --agent coding
  $0 wait --agent coding --timeout 60
  $0 peek --agent manager
  $0 flush --agent coding
  $0 count --agent manager
EOF
}

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------
main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    local command="$1"
    shift

    # Export DB path for Python subprocesses
    export MQ_DB_PATH="$DB_PATH"

    case "$command" in
        send)    cmd_send "$@"    ;;
        receive) cmd_receive "$@" ;;
        wait)    cmd_wait "$@"    ;;
        peek)    cmd_peek "$@"    ;;
        flush)   cmd_flush "$@"   ;;
        count)   cmd_count "$@"   ;;
        help|--help|-h)
            usage
            ;;
        *)
            echo "Error: Unknown command: $command" >&2
            usage
            exit 1
            ;;
    esac
}

main "$@"
