#!/bin/bash
# Shared path/config helpers for Agent Verification System (AVS)
# All scripts should source this file and use these variables.

set -euo pipefail

# Repo root (works even when invoked from elsewhere)
AVS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# User-configurable workspace (optional)
# If you're integrating AVS into another repo, set AVS_WORKSPACE to that repo root.
AVS_WORKSPACE="${AVS_WORKSPACE:-$AVS_ROOT}"

# Operational dirs (default inside AVS_WORKSPACE)
AVS_OPERATIONAL_DIR="${AVS_OPERATIONAL_DIR:-$AVS_WORKSPACE/OPERATIONAL}"
AVS_ARTIFACT_DIR="${AVS_ARTIFACT_DIR:-$AVS_OPERATIONAL_DIR/completion-artifacts}"
AVS_VERIFICATION_LOG_DIR="${AVS_VERIFICATION_LOG_DIR:-$AVS_OPERATIONAL_DIR/verification-logs}"
AVS_VERIFIER_COMPLETIONS_DIR="${AVS_VERIFIER_COMPLETIONS_DIR:-$AVS_OPERATIONAL_DIR/verifier-completions}"
AVS_META_MONITOR_DIR="${AVS_META_MONITOR_DIR:-$AVS_OPERATIONAL_DIR/meta-monitor}"

# Queue integration (optional)
AVS_QUEUE_FILE="${AVS_QUEUE_FILE:-$AVS_WORKSPACE/autonomous-queue.yaml}"
AVS_BLOCKERS_FILE="${AVS_BLOCKERS_FILE:-$AVS_WORKSPACE/BLOCKERS.md}"

# Optional alert hook (shell command). If set, meta-monitor will invoke it with ALERT_FILE path.
AVS_ALERT_HOOK="${AVS_ALERT_HOOK:-}"
