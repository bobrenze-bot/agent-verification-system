#!/bin/bash
# Tier 2: Verification Script (V2 - with self-verification)
# FIXES: FM-1 (Verifier Accountability), FM-3 (Checksum Validation), FM-11 (Environment Validation)

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# === Environment Validation ===
for cmd in find grep sed date shasum; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "FATAL: Required command '$cmd' not found in PATH" >&2
        exit 127
    fi
done

# === Configuration ===
WORKSPACE="/Users/serenerenze/bob-bootstrap"
ARTIFACT_DIR="$WORKSPACE/OPERATIONAL/completion-artifacts"
LOG_DIR="$WORKSPACE/OPERATIONAL/verification-logs"
VERIFIER_DIR="$WORKSPACE/OPERATIONAL/verifier-completions"
TIMESTAMP=$(date -u +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/verification_$TIMESTAMP.log"
VERIFIER_ARTIFACT="$VERIFIER_DIR/verify_$TIMESTAMP.yaml"

# Validate directories writable
for dir in "$ARTIFACT_DIR" "$LOG_DIR" "$VERIFIER_DIR"; do
    mkdir -p "$dir"
    if [ ! -w "$dir" ]; then
        echo "FATAL: Directory '$dir' not writable" >&2
        exit 1
    fi
done

# === Lockfile (prevent concurrent executions) ===
LOCKFILE="/tmp/verify-recent-tasks.lock"
if [ -f "$LOCKFILE" ]; then
    LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null)
    if ps -p "$LOCK_PID" > /dev/null 2>&1; then
        echo "Verifier already running (PID: $LOCK_PID)" >&2
        exit 0
    fi
fi
echo $$ > "$LOCKFILE"
# Cleanup lock on exit
trap 'rm -f "$LOCKFILE"' EXIT

# === Begin Verification ===
echo "=== TASK VERIFICATION RUN: $TIMESTAMP ===" | tee -a "$LOG_FILE"

ARTIFACTS_CHECKED=0
ARTIFACTS_PASSED=0
ARTIFACTS_FAILED=0
FAILED_TASKS=()

# Check for artifacts in last 30 minutes
RECENT_ARTIFACTS=$(find "$ARTIFACT_DIR" -name "*.yaml" -mmin -30 2>/dev/null)

if [ -z "$RECENT_ARTIFACTS" ]; then
    echo "WARNING: No artifacts found in last 30 minutes" | tee -a "$LOG_FILE"
    # Don't exit yet - write verifier completion artifact with this finding
fi

# Verify each artifact
for artifact in $RECENT_ARTIFACTS; do
    ARTIFACTS_CHECKED=$((ARTIFACTS_CHECKED + 1))
    echo "--- Checking: $(basename "$artifact") ---" | tee -a "$LOG_FILE"
    
    # Validate it's valid YAML
    if ! yq eval . "$artifact" >/dev/null 2>&1; then
        echo "FAIL: Invalid YAML in $(basename "$artifact")" | tee -a "$LOG_FILE"
        FAILED_TASKS+=("$(basename "$artifact"):invalid_yaml")
        ARTIFACTS_FAILED=$((ARTIFACTS_FAILED + 1))
        continue
    fi
    
    # Check required fields exist
    if ! yq eval '.task_id' "$artifact" >/dev/null 2>&1; then
        echo "FAIL: Missing task_id in $(basename "$artifact")" | tee -a "$LOG_FILE"
        FAILED_TASKS+=("$(basename "$artifact"):missing_task_id")
        ARTIFACTS_FAILED=$((ARTIFACTS_FAILED + 1))
        continue
    fi
    
    if ! yq eval '.status' "$artifact" >/dev/null 2>&1; then
        echo "FAIL: Missing status in $(basename "$artifact")" | tee -a "$LOG_FILE"
        FAILED_TASKS+=("$(basename "$artifact"):missing_status")
        ARTIFACTS_FAILED=$((ARTIFACTS_FAILED + 1))
        continue
    fi
    
    # Get status
    STATUS=$(yq eval '.status' "$artifact" 2>/dev/null || echo "unknown")
    
    # Validate status value
    if [[ "$STATUS" != "complete" && "$STATUS" != "failed" && "$STATUS" != "partial" && "$STATUS" != "in_progress" ]]; then
        echo "FAIL: Invalid status '$STATUS' in $(basename "$artifact")" | tee -a "$LOG_FILE"
        FAILED_TASKS+=("$(basename "$artifact"):invalid_status")
        ARTIFACTS_FAILED=$((ARTIFACTS_FAILED + 1))
        continue
    fi
    
    # If in_progress, check heartbeat
    if [ "$STATUS" = "in_progress" ]; then
        LAST_HEARTBEAT=$(yq eval '.last_heartbeat' "$artifact" 2>/dev/null || echo "")
        if [ -z "$LAST_HEARTBEAT" ]; then
            echo "WARN: in_progress task without heartbeat in $(basename "$artifact")" | tee -a "$LOG_FILE"
        else
            # Check if heartbeat is stale (>2 min old)
            HEARTBEAT_AGE=$(( $(date +%s) - $(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$LAST_HEARTBEAT" +%s 2>/dev/null || echo 0) ))
            if [ "$HEARTBEAT_AGE" -gt 120 ]; then
                echo "FAIL: Stale heartbeat (${HEARTBEAT_AGE}s) in $(basename "$artifact")" | tee -a "$LOG_FILE"
                FAILED_TASKS+=("$(basename "$artifact"):stale_heartbeat")
                ARTIFACTS_FAILED=$((ARTIFACTS_FAILED + 1))
                continue
            fi
        fi
        
        # Don't verify outputs for in_progress tasks
        echo "SKIP: Task still in progress - $(basename "$artifact")" | tee -a "$LOG_FILE"
        continue
    fi
    
    # Verify outputs exist if status is complete
    if [ "$STATUS" = "complete" ]; then
        # Get output paths
        OUTPUT_COUNT=$(yq eval '.outputs | length' "$artifact" 2>/dev/null || echo 0)
        
        if [ "$OUTPUT_COUNT" -eq 0 ]; then
            echo "WARN: Complete task has no outputs in $(basename "$artifact")" | tee -a "$LOG_FILE"
        else
            for i in $(seq 0 $((OUTPUT_COUNT - 1))); do
                OUTPUT_PATH=$(yq eval ".outputs[$i].path" "$artifact" 2>/dev/null)
                OUTPUT_CHECKSUM=$(yq eval ".outputs[$i].checksum" "$artifact" 2>/dev/null || echo "")
                
                # Check file exists
                if [ ! -f "$OUTPUT_PATH" ]; then
                    echo "FAIL: Output file missing: $OUTPUT_PATH" | tee -a "$LOG_FILE"
                    FAILED_TASKS+=("$(basename "$artifact"):missing_output")
                    ARTIFACTS_FAILED=$((ARTIFACTS_FAILED + 1))
                    STATUS="failed"
                    break
                fi
                
                # Verify checksum if present (supports shasum256 or md5 format)
                if [ -n "$OUTPUT_CHECKSUM" ]; then
                    if [[ "$OUTPUT_CHECKSUM" == sha256:* ]]; then
                        EXPECTED_CHECKSUM=${OUTPUT_CHECKSUM#sha256:}
                        ACTUAL_CHECKSUM=$(shasum -a 256 "$OUTPUT_PATH" 2>/dev/null | awk '{print $1}' || echo "")
                    elif [[ "$OUTPUT_CHECKSUM" == md5:* ]]; then
                        EXPECTED_CHECKSUM=${OUTPUT_CHECKSUM#md5:}
                        ACTUAL_CHECKSUM=$(md5 -q "$OUTPUT_PATH" 2>/dev/null || echo "")
                    fi
                    
                    if [ -n "$EXPECTED_CHECKSUM" ] && [ "$ACTUAL_CHECKSUM" != "$EXPECTED_CHECKSUM" ]; then
                        echo "FAIL: Checksum mismatch for $OUTPUT_PATH" | tee -a "$LOG_FILE"
                        echo "  Expected: $EXPECTED_CHECKSUM" | tee -a "$LOG_FILE"
                        echo "  Actual:   $ACTUAL_CHECKSUM" | tee -a "$LOG_FILE"
                        FAILED_TASKS+=("$(basename "$artifact"):checksum_mismatch")
                        ARTIFACTS_FAILED=$((ARTIFACTS_FAILED + 1))
                        STATUS="failed"
                        break
                    fi
                fi
            done
        fi
    fi
    
    if [ "$STATUS" = "failed" ]; then
        ARTIFACTS_FAILED=$((ARTIFACTS_FAILED + 1))
    else
        ARTIFACTS_PASSED=$((ARTIFACTS_PASSED + 1))
        echo "PASS: $(basename "$artifact") - status: $STATUS" | tee -a "$LOG_FILE"
    fi
done

# === Write Verifier Completion Artifact ===
VERIFIER_STATUS="complete"
if [ "$ARTIFACTS_FAILED" -gt 0 ]; then
    VERIFIER_STATUS="complete_with_failures"
fi

cat > "$VERIFIER_ARTIFACT" <<EOF
---
verifier_run_id: "verify_$TIMESTAMP"
status: $VERIFIER_STATUS
timestamp: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
artifacts_checked: $ARTIFACTS_CHECKED
artifacts_passed: $ARTIFACTS_PASSED
artifacts_failed: $ARTIFACTS_FAILED
failed_tasks:
EOF

for failed in "${FAILED_TASKS[@]:-}"; do
    if [ -n "$failed" ]; then
        echo "  - $failed" >> "$VERIFIER_ARTIFACT"
    fi
done

echo "=== VERIFICATION COMPLETE ===" | tee -a "$LOG_FILE"
echo "Checked: $ARTIFACTS_CHECKED | Passed: $ARTIFACTS_PASSED | Failed: $ARTIFACTS_FAILED" | tee -a "$LOG_FILE"
echo "Verifier artifact: $VERIFIER_ARTIFACT" | tee -a "$LOG_FILE"

# Exit code reflects verification results
if [ "$ARTIFACTS_FAILED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
