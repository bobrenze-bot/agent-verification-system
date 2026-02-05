# OpenClaw Cron Configuration Needed

Add these 3 jobs to OpenClaw's cron system:

## 1. Task Verifier (10 minutes)
```json
{
  "name": "Verification - Task Verifier",
  "enabled": true,
  "schedule": {"kind": "every", "everyMs": 600000},
  "sessionTarget": "isolated",
  "payload": {
    "kind": "agentTurn",
    "message": "Run bash /Users/serenerenze/bob-bootstrap/OPERATIONAL/verify-recent-tasks.sh",
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
    "message": "Run python3 /Users/serenerenze/bob-bootstrap/OPERATIONAL/queue-sync-artifacts.py",
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
    "message": "Run bash /Users/serenerenze/bob-bootstrap/OPERATIONAL/meta-monitor/check-system-health.sh",
    "timeoutSeconds": 120,
    "deliver": false
  }
}
```

**Note:** `deliver: false` prevents internal messages from routing to chat.
