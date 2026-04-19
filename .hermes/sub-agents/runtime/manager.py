#!/usr/bin/env python3
"""
Sub-agent lifecycle manager for Hermes.

Manages the sub-agent registry and port allocation.
Used by spawn-agent.sh and complete-agent.sh, and directly by the main Hermes agent.
"""

import argparse
import fcntl
import json
import os
import socket
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# Registry file path
REGISTRY_PATH = Path(__file__).parent.parent / "registry.json"

# Port allocation range
BASE_PORT = 18800
MAX_PORT = 65535


def _ensure_registry_exists() -> None:
    """Create registry file with empty agents dict if it doesn't exist."""
    REGISTRY_PATH.parent.mkdir(parents=True, exist_ok=True)
    if not REGISTRY_PATH.exists():
        with open(REGISTRY_PATH, "w") as f:
            json.dump({"agents": {}}, f, indent=2)


def _read_registry() -> dict:
    """Read and return the registry data."""
    _ensure_registry_exists()
    with open(REGISTRY_PATH, "r") as f:
        return json.load(f)


def _write_registry(data: dict) -> None:
    """Write registry data to file."""
    with open(REGISTRY_PATH, "w") as f:
        json.dump(data, f, indent=2)


def _acquire_lock(f) -> None:
    """Acquire exclusive lock on file for concurrent access safety."""
    fcntl.flock(f.fileno(), fcntl.LOCK_EX)


def _release_lock(f) -> None:
    """Release lock on file."""
    fcntl.flock(f.fileno(), fcntl.LOCK_UN)


def _now_iso() -> str:
    """Return current UTC time in ISO-8601 format."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def register_agent(agent_id: str, role: str, pid: int, port: int, task: str) -> None:
    """
    Register a new agent in the registry.

    Args:
        agent_id: Unique identifier for the agent
        role: Agent role (e.g., "researcher", "coder")
        pid: Process ID of the agent
        port: Port number assigned to the agent
        task: Description of the assigned task
    """
    _ensure_registry_exists()

    with open(REGISTRY_PATH, "r+") as f:
        _acquire_lock(f)
        try:
            data = json.load(f)

            data["agents"][agent_id] = {
                "role": role,
                "pid": pid,
                "port": port,
                "status": "running",
                "task": task,
                "created_at": _now_iso(),
                "completed_at": None,
            }

            f.seek(0)
            f.truncate()
            json.dump(data, f, indent=2)
        finally:
            _release_lock(f)


def deregister_agent(agent_id: str) -> bool:
    """
    Mark an agent as completed in the registry.

    Args:
        agent_id: Unique identifier for the agent

    Returns:
        True if agent was found and updated, False otherwise
    """
    _ensure_registry_exists()

    with open(REGISTRY_PATH, "r+") as f:
        _acquire_lock(f)
        try:
            data = json.load(f)

            if agent_id not in data["agents"]:
                return False

            data["agents"][agent_id]["status"] = "completed"
            data["agents"][agent_id]["completed_at"] = _now_iso()

            f.seek(0)
            f.truncate()
            json.dump(data, f, indent=2)
            return True
        finally:
            _release_lock(f)


def list_agents(status: Optional[str] = None) -> dict:
    """
    List all agents, optionally filtered by status.

    Args:
        status: Optional filter - "running", "completed", or "failed"

    Returns:
        Dictionary of agent_id -> agent_data for matching agents
    """
    data = _read_registry()
    agents = data.get("agents", {})

    if status:
        return {k: v for k, v in agents.items() if v.get("status") == status}

    return agents


def get_agent(agent_id: str) -> Optional[dict]:
    """
    Get details for a specific agent.

    Args:
        agent_id: Unique identifier for the agent

    Returns:
        Agent details dict, or None if not found
    """
    data = _read_registry()
    return data.get("agents", {}).get(agent_id)


def _is_port_available(port: int) -> bool:
    """Check if a port is available by attempting to bind to it."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(("127.0.0.1", port))
            return True
    except OSError:
        return False


def allocate_port() -> int:
    """
    Find the next available port starting from BASE_PORT.

    Checks both the registry for assigned ports and actual port availability
    via socket bind test.

    Returns:
        Available port number

    Raises:
        RuntimeError: If no ports are available in the valid range
    """
    data = _read_registry()
    agents = data.get("agents", {})

    # Get all ports currently in use by running agents
    used_ports = {
        agent["port"]
        for agent in agents.values()
        if agent.get("status") == "running" and "port" in agent
    }

    # Find next available port
    for port in range(BASE_PORT, MAX_PORT + 1):
        if port not in used_ports and _is_port_available(port):
            return port

    raise RuntimeError("No available ports found in valid range")


def cleanup_dead() -> list[str]:
    """
    Check all running agents and mark dead ones as failed.

    Uses os.kill(pid, 0) to check if a process is still alive.

    Returns:
        List of agent IDs that were marked as failed
    """
    _ensure_registry_exists()

    dead_agents: list[str] = []

    with open(REGISTRY_PATH, "r+") as f:
        _acquire_lock(f)
        try:
            data = json.load(f)
            agents = data.get("agents", {})

            for agent_id, agent in agents.items():
                if agent.get("status") != "running":
                    continue

                pid = agent.get("pid")
                if pid is None:
                    continue

                try:
                    # Check if process exists
                    os.kill(pid, 0)
                except (OSError, ProcessLookupError):
                    # Process is dead
                    agent["status"] = "failed"
                    agent["completed_at"] = _now_iso()
                    dead_agents.append(agent_id)

            if dead_agents:
                f.seek(0)
                f.truncate()
                json.dump(data, f, indent=2)

            return dead_agents
        finally:
            _release_lock(f)


def _format_agent_line(agent_id: str, agent: dict) -> str:
    """Format a single agent for list display."""
    return (
        f"{agent_id:20} {agent['role']:12} {agent['status']:10} "
        f"{agent['port']:5} {agent['task'][:40]:40}"
    )


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Sub-agent lifecycle manager for Hermes"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # register command
    register_parser = subparsers.add_parser("register", help="Register a new agent")
    register_parser.add_argument("--agent-id", required=True, help="Agent unique ID")
    register_parser.add_argument("--role", required=True, help="Agent role")
    register_parser.add_argument("--pid", type=int, required=True, help="Process ID")
    register_parser.add_argument("--port", type=int, required=True, help="Port number")
    register_parser.add_argument("--task", required=True, help="Task description")

    # deregister command
    deregister_parser = subparsers.add_parser(
        "deregister", help="Mark an agent as completed"
    )
    deregister_parser.add_argument("--agent-id", required=True, help="Agent unique ID")

    # list command
    list_parser = subparsers.add_parser("list", help="List all agents")
    list_parser.add_argument(
        "--status",
        choices=["running", "completed", "failed"],
        help="Filter by status",
    )

    # status command
    status_parser = subparsers.add_parser(
        "status", help="Show detailed status for an agent"
    )
    status_parser.add_argument("--agent-id", required=True, help="Agent unique ID")

    # allocate-port command
    subparsers.add_parser("allocate-port", help="Allocate an available port")

    # cleanup command
    subparsers.add_parser("cleanup", help="Mark dead agents as failed")

    args = parser.parse_args()

    if args.command == "register":
        register_agent(args.agent_id, args.role, args.pid, args.port, args.task)
        print(f"Registered agent: {args.agent_id}")

    elif args.command == "deregister":
        if deregister_agent(args.agent_id):
            print(f"Deregistered agent: {args.agent_id}")
        else:
            print(f"Agent not found: {args.agent_id}")
            exit(1)

    elif args.command == "list":
        agents = list_agents(args.status)
        if not agents:
            print("No agents found")
        else:
            print(f"{'AGENT ID':20} {'ROLE':12} {'STATUS':10} {'PORT':5} {'TASK':40}")
            print("-" * 95)
            for agent_id, agent in sorted(agents.items()):
                print(_format_agent_line(agent_id, agent))

    elif args.command == "status":
        agent = get_agent(args.agent_id)
        if agent is None:
            print(f"Agent not found: {args.agent_id}")
            exit(1)
        else:
            print(f"Agent ID:     {args.agent_id}")
            print(f"Role:         {agent['role']}")
            print(f"Status:       {agent['status']}")
            print(f"PID:          {agent['pid']}")
            print(f"Port:         {agent['port']}")
            print(f"Task:         {agent['task']}")
            print(f"Created:      {agent['created_at']}")
            if agent.get('completed_at'):
                print(f"Completed:    {agent['completed_at']}")

    elif args.command == "allocate-port":
        port = allocate_port()
        print(port)

    elif args.command == "cleanup":
        dead = cleanup_dead()
        if dead:
            print(f"Marked {len(dead)} dead agent(s) as failed:")
            for agent_id in dead:
                print(f"  - {agent_id}")
        else:
            print("No dead agents found")


if __name__ == "__main__":
    main()
