#!/bin/bash
# Tier 3: Meta-Monitor (V2 - with Verifier Verification & Human Escalation)
# FIXES: FM-1 (Checks verifier itself), FM-5 (Human escalation), FM-6 (Temporal coupling)

set -uo pipefail  # Note: removed -e to handle expected empty results

source "$(dirname "$0")/../lib/paths.sh"
WORKSPACE="$AVS_WORKSPACE"
OPERATIONAL_DIR="$AVS_OPERATIONAL_DIR"
LOG_DIR="$AVS_META_MONITOR_DIR"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TIMESTAMP_FILE=$(date -u +"%Y%m%d_%H%M%S")
ALERT_FILE="$LOG_DIR/ALERT_$TIMESTAMP_FILE.txt"
HEARTBEAT_FILE="$LOG_DIR/meta-monitor-heartbeat.txt"

mkdir -p "$LOG_DIR"

ISSUES=0

echo "=== META-MONITOR HEALTH CHECK: $TIMESTAMP ===" > "$ALERT_FILE"

# === Check 1: Worker Activity ===
# Has any worker run in last 2 hours?
RECENT_WORKERS=$(find "$OPERATIONAL_DIR/completion-artifacts" -name "*.yaml" -mmin -120 2>/dev/null | wc -l | tr -d ' ')

if [ "$RECENT_WORKERS" -eq 0 ]; then
    echo "⚠️  ALERT: No worker artifacts in last 2 hours" >> "$ALERT_FILE"
    echo "   Possible causes:" >> "$ALERT_FILE"
    echo "   - No tasks scheduled" >> "$ALERT_FILE"
    echo "   - Workers failing before writing artifacts" >> "$ALERT_FILE"
    echo "   - System offline" >> "$ALERT_FILE"
    ISSUES=$((ISSUES + 1))
else
    echo "✓ Worker activity: $RECENT_WORKERS artifacts in last 2h" >> "$ALERT_FILE"
fi

# === Check 2: Verifier Activity ===
# Has verifier run recently? (should run every 10 min)
RECENT_VERIFICATIONS=$(find "$OPERATIONAL_DIR/verification-logs" -name "*.log" -mmin -30 2>/dev/null | wc -l | tr -d ' ')

if [ "$RECENT_VERIFICATIONS" -eq 0 ]; then
    echo "⚠️  ALERT: No verification logs in last 30 minutes" >> "$ALERT_FILE"
    echo "   Expected: Verifier runs every 10 min via cron" >> "$ALERT_FILE"
    echo "   Action: Check crontab, verify verifier script is executable" >> "$ALERT_FILE"
    ISSUES=$((ISSUES + 1))
else
    echo "✓ Verifier activity: $RECENT_VERIFICATIONS runs in last 30min" >> "$ALERT_FILE"
fi

# === Check 3: Verifier Completion Artifacts (NEW) ===
# Does verifier write its own completion artifacts?
if [ -d "$OPERATIONAL_DIR/verifier-completions" ]; then
    RECENT_VERIFIER_ARTIFACTS=$(find "$OPERATIONAL_DIR/verifier-completions" -name "*.yaml" -mmin -30 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$RECENT_VERIFIER_ARTIFACTS" -eq 0 ]; then
        echo "🔴 CRITICAL: Verifier ran but produced no completion artifact" >> "$ALERT_FILE"
        echo "   This means verifier itself is not being verified!" >> "$ALERT_FILE"
        echo "   Action: Upgrade to verify-recent-tasks-v2.sh" >> "$ALERT_FILE"
        ISSUES=$((ISSUES + 1))
    else
        echo "✓ Verifier accountability: $RECENT_VERIFIER_ARTIFACTS completion artifacts in last 30min" >> "$ALERT_FILE"
        
        # Check if any verifier runs failed
        for artifact in $(find "$OPERATIONAL_DIR/verifier-completions" -name "*.yaml" -mmin -30 2>/dev/null); do
            STATUS=$(yq eval '.status' "$artifact" 2>/dev/null || echo "unknown")
            ARTIFACTS_FAILED=$(yq eval '.artifacts_failed' "$artifact" 2>/dev/null || echo 0)
            
            if [ "$ARTIFACTS_FAILED" -gt 0 ]; then
                echo "⚠️  WARNING: Verifier found $ARTIFACTS_FAILED failed task(s) in $(basename "$artifact")" >> "$ALERT_FILE"
                ISSUES=$((ISSUES + 1))
            fi
        done
    fi
else
    echo "⚠️  WARNING: verifier-completions directory missing - verifier not self-verifying" >> "$ALERT_FILE"
    ISSUES=$((ISSUES + 1))
fi

# === Check 4: Stuck Tasks ===
# Any tasks reported as stuck by verifier?
STUCK_COUNT=0
if [ -d "$OPERATIONAL_DIR/verification-logs" ]; then
    STUCK_COUNT=$(grep -l "STUCK_WORK_DETECTED\|FAIL.*stale_heartbeat" "$OPERATIONAL_DIR/verification-logs"/*.log 2>/dev/null | wc -l | tr -d ' ')
fi

if [ "$STUCK_COUNT" -gt 0 ]; then
    echo "🔴 CRITICAL: $STUCK_COUNT stuck task report(s) found" >> "$ALERT_FILE"
    echo "   Action: Investigate stalled workers, check for crashed processes" >> "$ALERT_FILE"
    ISSUES=$((ISSUES + 1))
else
    echo "✓ No stuck tasks detected" >> "$ALERT_FILE"
fi

# === Check 5: Context Size ===
# Check if approaching context limits
CONTEXT_CHECK_OUTPUT=$("$WORKSPACE/scripts/check-context-size.sh" 2>&1 || true)
CONTEXT_EXIT_CODE=$?

if [ "$CONTEXT_EXIT_CODE" -eq 2 ]; then
    echo "🔴 CRITICAL: Context size at CRITICAL level" >> "$ALERT_FILE"
    echo "   $CONTEXT_CHECK_OUTPUT" >> "$ALERT_FILE"
    ISSUES=$((ISSUES + 1))
elif [ "$CONTEXT_EXIT_CODE" -eq 1 ]; then
    echo "⚠️  WARNING: Context size at WARNING level" >> "$ALERT_FILE"
    echo "   $CONTEXT_CHECK_OUTPUT" >> "$ALERT_FILE"
    ISSUES=$((ISSUES + 1))
else
    echo "✓ Context size healthy" >> "$ALERT_FILE"
fi

# === Check 6: Disk Space ===
DISK_USAGE=$(df -h "$WORKSPACE" | tail -1 | awk '{print $5}' | sed 's/%//')

if [ "$DISK_USAGE" -gt 90 ]; then
    echo "🔴 CRITICAL: Disk usage at ${DISK_USAGE}%" >> "$ALERT_FILE"
    echo "   Risk: Workers may fail to write artifacts" >> "$ALERT_FILE"
    ISSUES=$((ISSUES + 1))
elif [ "$DISK_USAGE" -gt 80 ]; then
    echo "⚠️  WARNING: Disk usage at ${DISK_USAGE}%" >> "$ALERT_FILE"
    ISSUES=$((ISSUES + 1))
else
    echo "✓ Disk space: ${DISK_USAGE}% used" >> "$ALERT_FILE"
fi

# === Check 7: Human Acknowledgment (NEW) ===
# Has human acknowledged system health recently?
HUMAN_ACK_FILE="$LOG_DIR/human-ack-timestamp.txt"

if [ -f "$HUMAN_ACK_FILE" ]; then
    LAST_ACK=$(cat "$HUMAN_ACK_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    ACK_AGE_HOURS=$(( (NOW - LAST_ACK) / 3600 ))
    
    if [ "$ACK_AGE_HOURS" -gt 48 ]; then
        echo "⚠️  WARNING: No human acknowledgment in $ACK_AGE_HOURS hours" >> "$ALERT_FILE"
        echo "   System may be running unmonitored" >> "$ALERT_FILE"
        echo "   Action: Run 'echo \$(date +%s) > $HUMAN_ACK_FILE'" >> "$ALERT_FILE"
        ISSUES=$((ISSUES + 1))
    else
        echo "✓ Human acknowledged system $ACK_AGE_HOURS hours ago" >> "$ALERT_FILE"
    fi
else
    echo "ℹ️  INFO: No human acknowledgment file (first run)" >> "$ALERT_FILE"
fi

# === Check 8: Queue Health ===
# Check autonomous-queue.yaml for anomalies
QUEUE_FILE="$WORKSPACE/autonomous-queue.yaml"

if [ -f "$QUEUE_FILE" ]; then
    PENDING_COUNT=$(yq eval '.tasks[] | select(.status == "pending")' "$QUEUE_FILE" 2>/dev/null | grep -c 'id:' || echo 0)
    IN_PROGRESS_COUNT=$(yq eval '.tasks[] | select(.status == "in_progress")' "$QUEUE_FILE" 2>/dev/null | grep -c 'id:' || echo 0)
    BLOCKED_COUNT=$(yq eval '.tasks[] | select(.status == "blocked")' "$QUEUE_FILE" 2>/dev/null | grep -c 'id:' || echo 0)
    
    echo "ℹ️  Queue status: $PENDING_COUNT pending, $IN_PROGRESS_COUNT in_progress, $BLOCKED_COUNT blocked" >> "$ALERT_FILE"
    
    if [ "$BLOCKED_COUNT" -gt 5 ]; then
        echo "⚠️  WARNING: $BLOCKED_COUNT blocked tasks - review BLOCKERS.md" >> "$ALERT_FILE"
        ISSUES=$((ISSUES + 1))
    fi
else
    echo "⚠️  WARNING: autonomous-queue.yaml not found" >> "$ALERT_FILE"
    ISSUES=$((ISSUES + 1))
fi

# === Write Heartbeat ===
echo "$(date +%s)" > "$HEARTBEAT_FILE"
echo "✓ Meta-monitor heartbeat updated" >> "$ALERT_FILE"

# === Summary ===
echo "" >> "$ALERT_FILE"
echo "=== SUMMARY ===" >> "$ALERT_FILE"
echo "Total issues detected: $ISSUES" >> "$ALERT_FILE"
echo "Timestamp: $TIMESTAMP" >> "$ALERT_FILE"

# === Health Log ===
if [ "$ISSUES" -eq 0 ]; then
    echo "$TIMESTAMP: HEALTHY - All systems operational" >> "$LOG_DIR/health.log"
    
    # Don't spam with healthy reports - only log to file
    cat "$ALERT_FILE"
    rm "$ALERT_FILE"  # Clean up
    exit 0
else
    echo "$TIMESTAMP: ALERT_RAISED - $ISSUES issue(s)" >> "$LOG_DIR/health.log"
    echo "escalated_at: $TIMESTAMP" >> "$ALERT_FILE"
    
    # === Escalation Hook (Optional) ===
    # Default behavior: write alert file and exit nonzero (cron can email).
    # If you want external alerting (Slack/Telegram/etc), set AVS_ALERT_HOOK.
    # Hook will be called as: AVS_ALERT_HOOK=<cmd> where <cmd> receives ALERT_FILE in $ALERT_FILE.

    if [ -n "$AVS_ALERT_HOOK" ]; then
        echo "Invoking AVS_ALERT_HOOK: $AVS_ALERT_HOOK" >> "$ALERT_FILE"
        ALERT_FILE="$ALERT_FILE" ISSUES="$ISSUES" TIMESTAMP="$TIMESTAMP" bash -lc "$AVS_ALERT_HOOK" >> "$ALERT_FILE" 2>&1 || true
    fi

    # Always output alert to stdout
    cat "$ALERT_FILE"

    exit 1
fi
