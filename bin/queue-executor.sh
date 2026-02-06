#!/bin/bash
# Tier 0: Queue Executor (scheduling/selection)
#
# This is the missing piece: verification alone only tells you nothing happened.
# The executor's job is to:
#  - detect pending tasks
#  - ensure exactly ONE task is selected per tick
#  - (optionally) trigger execution via an external runner (OpenClaw cron agentTurn, or a hook)
#
# In pure shell/system-cron mode, this script *does not* "do the task" unless you
# provide AVS_EXECUTE_HOOK. For OpenClaw, you typically use an agentTurn cron job
# that reads the queue and performs the task itself.

set -euo pipefail

source "$(dirname "$0")/../lib/paths.sh"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$AVS_OPERATIONAL_DIR" "$AVS_META_MONITOR_DIR"

if [ ! -f "$AVS_QUEUE_FILE" ]; then
  echo "NO_QUEUE_FILE: $AVS_QUEUE_FILE"
  exit 0
fi

if ! command -v yq &>/dev/null; then
  echo "ERROR: yq not installed (required for queue executor). Install yq and retry." >&2
  exit 1
fi

# Prevent overlap: if anything is already in_progress, do nothing
IN_PROGRESS=$(yq '.tasks[] | select(.status == "in_progress") | .id' "$AVS_QUEUE_FILE" 2>/dev/null | head -1 || true)
if [ -n "$IN_PROGRESS" ]; then
  echo "SKIP: Task already in_progress (#$IN_PROGRESS)"
  exit 0
fi

# Select next task by priority order
NEXT_ID=$(yq '.tasks[] | select(.status == "pending" and .priority == "high") | .id' "$AVS_QUEUE_FILE" 2>/dev/null | head -1 || true)
if [ -z "$NEXT_ID" ]; then
  NEXT_ID=$(yq '.tasks[] | select(.status == "pending" and .priority == "medium") | .id' "$AVS_QUEUE_FILE" 2>/dev/null | head -1 || true)
fi
if [ -z "$NEXT_ID" ]; then
  NEXT_ID=$(yq '.tasks[] | select(.status == "pending" and .priority == "low") | .id' "$AVS_QUEUE_FILE" 2>/dev/null | head -1 || true)
fi

if [ -z "$NEXT_ID" ]; then
  echo "NO_PENDING_TASKS"
  exit 0
fi

# Resolve task line index and details
TASK_LINE=$(yq ".tasks[] | select(.id == $NEXT_ID) | line" "$AVS_QUEUE_FILE")
TASK_DESC=$(yq ".tasks[$TASK_LINE].task" "$AVS_QUEUE_FILE")

# Mark in_progress
STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
yq -i ".tasks[$TASK_LINE].status = \"in_progress\"" "$AVS_QUEUE_FILE"
yq -i ".tasks[$TASK_LINE].started_at = \"$STARTED_AT\"" "$AVS_QUEUE_FILE"

echo "EXECUTOR_SELECTED: #$NEXT_ID"
echo "TASK: $TASK_DESC"
echo "STARTED_AT: $STARTED_AT"

echo "${TIMESTAMP} selected task #$NEXT_ID" > "$AVS_META_MONITOR_DIR/executor-heartbeat.txt"

# Optional: call hook to actually run the task (for non-OpenClaw setups)
# Hook receives TASK_ID and TASK_DESC as env vars.
AVS_EXECUTE_HOOK="${AVS_EXECUTE_HOOK:-}"
if [ -n "$AVS_EXECUTE_HOOK" ]; then
  echo "RUN_HOOK: $AVS_EXECUTE_HOOK"
  TASK_ID="$NEXT_ID" TASK_DESC="$TASK_DESC" bash -lc "$AVS_EXECUTE_HOOK"
else
  echo "TASK_EXECUTION_REQUIRED: Provide AVS_EXECUTE_HOOK or use OpenClaw cron agentTurn executor."
fi
