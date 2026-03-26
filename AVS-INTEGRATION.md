# Agent Verification System (AVS) Integration

**Status:** Production Ready  
**Date:** 2026-03-23  
**Integration Lead:** Marcus (Orchestrator)

## Overview

The Agent Verification System (AVS) is now integrated into the production workflow as the backend for theater-pattern enforcement and completion gates. This replaces manual verification with an automated 4-tier verification architecture.

## Quick Start

### 1. Load Environment Configuration

```bash
source ~/bob-bootstrap/projects/agent-verification-system/avs-production.env
```

### 2. Verify AVS is Operational

```bash
# Check all components
ls -la $AVS_HOME/bin/

# Test theater verification
$AVS_HOME/bin/avs-theater-verify <path-to-deliverable.md>
```

### 3. Install Crontab (One-time Setup)

```bash
crontab ~/bob-bootstrap/projects/agent-verification-system/avs-production-crontab.txt
```

## 4-Tier Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  AVS PRODUCTION WORKFLOW                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  TIER 0: QUEUE MANAGEMENT                                        │
│  ├─ Paperclip Sync (10 min) → Fetches in_progress issues        │
│  ├─ Queue Executor (15 min) → Selects one pending task          │
│  └─ Queue Sync (15 min) → Matches artifacts to tasks           │
│                                                                  │
│  TIER 1: WORKER EXECUTION                                        │
│  └─ Agents perform work and write completion artifacts         │
│     to: ~/bob-bootstrap/OPERATIONAL/completion-artifacts/      │
│                                                                  │
│  TIER 2: VERIFICATION                                            │
│  ├─ Task Verifier (10 min) → Validates artifact integrity      │
│  └─ Theater Scanner (15 min) → Runs verify-checklist.py         │
│                                                                  │
│  TIER 3: META-MONITOR                                            │
│  └─ Health Check (30 min) → System-wide monitoring              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Integration with Theater Enforcement Gates

The 3-Gate Protocol is now enforced by AVS:

### Gate 1: Self-Check (Agent Responsibility)
```bash
# Before posting ANY deliverable, run:
python3 ~/bob-bootstrap/shared/BUILT_COMPONENTS/verify-checklist-fixed/verify-checklist.py <your-file.md>

# Must return exit code 0 (VERIFIED)
```

### Gate 2: AVS Theater Verification (Automated)
AVS automatically scans all completion artifacts every 15 minutes. If theater patterns are detected:
- Artifact is flagged in verification logs
- Alert is raised in meta-monitor
- Task cannot proceed to "complete" status

### Gate 3: Ruth Review (QA Authority)
Ruth can run manual verification:
```bash
~/bob-bootstrap/projects/agent-verification-system/bin/avs-theater-verify <deliverable-path> <task-id>
```

## Directory Structure

```
~/bob-bootstrap/
├── OPERATIONAL/                    # AVS operational data
│   ├── completion-artifacts/       # Worker completion artifacts
│   ├── verification-logs/          # Tier 2 verification logs
│   ├── verifier-completions/       # Verifier self-verification
│   └── meta-monitor/               # Tier 3 health reports
├── autonomous-queue.yaml           # Task queue (synced from Paperclip)
└── projects/agent-verification-system/
    ├── avs-production.env          # Environment configuration
    ├── avs-production-crontab.txt  # Production cron schedule
    ├── bin/
    │   ├── queue-executor.sh       # Tier 0: Task selection
    │   ├── verify-recent-tasks.sh  # Tier 2: Artifact verification
    │   ├── check-system-health.sh  # Tier 3: Health monitoring
    │   ├── avs-paperclip-sync      # Paperclip integration
    │   ├── avs-theater-verify      # Single-file theater check
    │   └── avs-theater-verify-scan # Batch theater scanner
    └── lib/
        ├── queue-sync-artifacts.py # Queue ↔ artifact sync
        └── paths.sh                  # Shared configuration
```

## For Agents: How to Write Verifiable Deliverables

### Required: Completion Artifacts

When you complete work, write a completion artifact:

```yaml
---
task_id: <paperclip-issue-id>
status: complete  # or: in_progress, failed, partial
timestamp_start: "2026-03-23T10:00:00Z"
timestamp_end: "2026-03-23T10:30:00Z"
outputs:
  - type: file
    path: /Users/serenerenze/bob-bootstrap/deliverables/my-work.md
    checksum: sha256:<file-sha256>
  - type: comment
    path: paperclip-issue-<id>
    summary: "Posted completion comment"
theater_check:
  status: pass  # or: fail, pending
  patterns_found: 0
notes: |
  Any relevant notes about the completion
```

Save to: `~/bob-bootstrap/OPERATIONAL/completion-artifacts/TASK_<id>_<timestamp>.yaml`

### Theater Pattern Prevention

AVS will flag these patterns:

| Pattern | What to Avoid | What to Include |
|---------|---------------|-----------------|
| Research Theater | Research-to-execution ratio > 3:1 | Execution evidence |
| Code Theater | Files touched without running | Test results, logs |
| Status Theater | "VERIFIED" without verification | Actual verify-checklist output |
| Routing Theater | Delegation without scope | Clear scope boundaries |
| Task Bait-and-Switch | Deliverable ≠ requirements | Requirements traceability |

## For Ruth: QA Review Protocol

### Manual Verification

```bash
# Verify a specific deliverable
~/bob-bootstrap/projects/agent-verification-system/bin/avs-theater-verify \
  ~/bob-bootstrap/deliverables/<file>.md \
  <task-id>
```

### Reviewing AVS Reports

Check latest theater scan:
```bash
cat ~/bob-bootstrap/OPERATIONAL/meta-monitor/theater-report-latest.txt
```

Check system health:
```bash
cat ~/bob-bootstrap/OPERATIONAL/meta-monitor/health.log
tail -50 ~/bob-bootstrap/OPERATIONAL/meta-monitor/ALERT_*.txt 2>/dev/null || echo "No active alerts"
```

## Monitoring and Logs

### Log Locations

| Component | Log Location |
|-----------|---------------|
| Paperclip Sync | `/tmp/avs-paperclip-sync.log` |
| Queue Executor | `/tmp/avs-executor.log` |
| Task Verifier | `/tmp/avs-verifier.log` |
| Theater Scanner | `/tmp/avs-theater.log` |
| Meta-Monitor | `/tmp/avs-meta-monitor.log` |
| Verification Artifacts | `~/bob-bootstrap/OPERATIONAL/verification-logs/` |

### Health Check

```bash
# View system health
cd ~/bob-bootstrap/projects/agent-verification-system
source avs-production.env
bin/check-system-health.sh
```

### Alert Configuration

To receive alerts (Slack/Telegram/etc), set the hook:

```bash
export AVS_ALERT_HOOK="/path/to/your/alert-script.sh"
```

Add to `avs-production.env` or crontab.

## Troubleshooting

### Issue: No tasks being picked up
**Check:** 
```bash
# Verify Paperclip sync is working
tail -20 /tmp/avs-paperclip-sync.log

# Check queue file
cat ~/bob-bootstrap/autonomous-queue.yaml
```

### Issue: Theater patterns not detected
**Check:**
```bash
# Verify checklist is executable
python3 ~/bob-bootstrap/shared/BUILT_COMPONENTS/verify-checklist-fixed/verify-checklist.py --help

# Test on a file
python3 ~/bob-bootstrap/shared/BUILT_COMPONENTS/verify-checklist-fixed/verify-checklist.py <file.md>
```

### Issue: Meta-monitor reporting no worker activity
**Check:**
```bash
# Verify crontab is installed
crontab -l | grep avs

# Check completion artifacts exist
ls -la ~/bob-bootstrap/OPERATIONAL/completion-artifacts/
```

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AVS_HOME` | `/Users/serenerenze/bob-bootstrap/projects/agent-verification-system` | AVS installation |
| `AVS_WORKSPACE` | `/Users/serenerenze/bob-bootstrap` | Workspace to monitor |
| `AVS_OPERATIONAL_DIR` | `~/bob-bootstrap/OPERATIONAL` | Operational data |
| `AVS_QUEUE_FILE` | `~/bob-bootstrap/autonomous-queue.yaml` | Task queue |
| `AVS_THEATER_CHECKLIST` | Path to verify-checklist.py | Theater detection |
| `AVS_ALERT_HOOK` | (unset) | Optional alert command |

### Cron Schedule

| Job | Frequency | Purpose |
|-----|-----------|---------|
| Paperclip Sync | 10 min | Sync issues to queue |
| Queue Executor | 15 min | Select next task |
| Queue Sync | 15 min | Match artifacts |
| Task Verifier | 10 min | Validate artifacts |
| Theater Scanner | 15 min | Pattern detection |
| Meta-Monitor | 30 min | System health |

## Migration Notes

This integration connects the previously stalled AVS project (6 weeks old) with the current theater enforcement gates. The existing:
- `verify-checklist.py` (theater detection) → Now integrated as Tier 2 verifier
- 3-Gate Protocol → Enforced by AVS automation
- Paperclip workflow → Synced to AVS queue

No changes to agent behavior required — AVS runs in parallel and enforces gates automatically.

---

**Integration Status:** ✅ Operational  
**Next Review:** Weekly with meta-monitor reports
