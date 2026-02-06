# OpenClaw Cron Configuration Needed

Add these 4 jobs to OpenClaw's cron system (Executor + Verification):

## 0. Queue Executor (20 minutes) — the missing piece
This job prevents “verification-only idling” by actually selecting and executing one pending task per tick.

```json
{
  "name": "AVS - Queue Executor (20min)",
  "enabled": true,
  "schedule": {"kind": "every", "everyMs": 1200000},
  "sessionTarget": "isolated",
  "payload": {
    "kind": "agentTurn",
    "timeoutSeconds": 1500,
    "deliver": false,
    "message": "Run an AVS queue execution tick. You must EXECUTE exactly one pending task (or mark it blocked) rather than just reporting status.\n\nPreflight (multi-person repos): if the task touches git repos, do a clean sync of origin/main before changes: fetch --all --prune; checkout main; pull --ff-only.\n\nSteps:\n1) Read AVS_QUEUE_FILE (default: ./autonomous-queue.yaml)\n2) Select ONE task (priority high>medium>low, status=pending)\n3) Mark it in_progress + started_at (UTC ISO)\n4) Execute the task fully using tools\n5) Write a completion artifact YAML into AVS_ARTIFACT_DIR (default: ./OPERATIONAL/completion-artifacts) with checksums for file outputs\n6) Mark the queue task complete/failed/blocked with completed_at and notes\n7) Commit any repo changes\n8) Output the task’s completion_signal verbatim"
  }
}
```

## 1. Task Verifier (10 minutes)
```json
{
  "name": "Verification - Task Verifier",
  "enabled": true,
  "schedule": {"kind": "every", "everyMs": 600000},
  "sessionTarget": "isolated",
  "payload": {
    "kind": "agentTurn",
    "message": "cd /path/to/agent-verification-system && bash bin/verify-recent-tasks.sh",
    "timeoutSeconds": 120,
    "deliver": false
  }
}
```

## 2. Queue Sync (15 minutes)
```json
{
  "name": "Verification - Queue Sync",
  "enabled": true,
  "schedule": {"kind": "every", "everyMs": 900000},
  "sessionTarget": "isolated",
  "payload": {
    "kind": "agentTurn",
    "message": "cd /path/to/agent-verification-system && python3 lib/queue-sync-artifacts.py",
    "timeoutSeconds": 60,
    "deliver": false
  }
}
```

## 3. Meta-Monitor (30 minutes)
```json
{
  "name": "Verification - Meta-Monitor",
  "enabled": true,
  "schedule": {"kind": "every", "everyMs": 1800000},
  "sessionTarget": "isolated",
  "payload": {
    "kind": "agentTurn",
    "message": "cd /path/to/agent-verification-system && bash bin/check-system-health.sh",
    "timeoutSeconds": 120,
    "deliver": false
  }
}
```

**Note:** `deliver: false` prevents internal messages from routing to chat.
