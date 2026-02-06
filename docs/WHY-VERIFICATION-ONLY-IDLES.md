# Why “Verification-Only” Systems Idle (and How to Fix It)

Autonomous agents often fail in a particularly deceptive way:

> The system looks alive (crons are firing, logs are updating), but no real work is being executed.

This is not a “model problem.” It’s an **architecture problem**.

---

## The Failure Mode

### Symptoms
- The verifier runs regularly (every 5–15 minutes)
- The meta-monitor reports “healthy” (or only mild warnings)
- The queue file has many `pending` tasks
- You repeatedly see messages like:
  - “Evening lull — no artifacts expected”
  - “No artifacts found in last 30 minutes”
  - “Queue sync OK”
- **But the actual deliverables never appear**

### Root Cause
A verification system can only answer:

- “Did anything happen?”

It cannot cause:

- “Make something happen.”

If you build only Tier 2 + Tier 3 (Verifier + Monitor), you’ve built a dashboard that can accurately report that nothing happened.

---

## The Minimal Working Loop

A working autonomy loop needs **both execution and verification**.

### 4-Tier Loop

```
          ┌──────────────────────────────┐
          │ Tier 0: EXECUTOR            │
          │ Select 1 pending task       │
          │ Mark in_progress            │
          └──────────────┬──────────────┘
                         │
                         v
          ┌──────────────────────────────┐
          │ Tier 1: WORKER              │
          │ Do the work                 │
          │ Write completion artifact   │
          │ (with output checksums)     │
          └──────────────┬──────────────┘
                         │
                         v
          ┌──────────────────────────────┐
          │ Tier 2: VERIFIER            │
          │ Validate artifact + outputs │
          │ Write verifier proof        │
          └──────────────┬──────────────┘
                         │
                         v
          ┌──────────────────────────────┐
          │ Tier 3: META-MONITOR         │
          │ Detect stuck loops           │
          │ Escalate if needed           │
          └──────────────────────────────┘
```

The key insight:

> **Tier 0 is the difference between “observability” and “agency.”**

---

## Why This Happens in Practice

### Common anti-pattern
People schedule these as crons:
- verifier (checks artifacts)
- sync job (updates queue)
- health check (ensures cron is firing)

…but never schedule:
- a job that *actually executes tasks*

This happens because it feels safer to build monitoring first, and because “logs updating” looks like progress.

### Another common trap: “executor” that doesn’t execute
Sometimes an “executor” exists, but it only:
- prints the next task
- marks `in_progress`
- exits with something like “TASK_EXECUTION_REQUIRED”

If nothing consumes that signal to actually run the task, you still idle.

---

## Fix Checklist

### 1) Add Tier 0
Add a scheduled job that:
- selects **exactly one** task per tick
- prevents overlap (skip if any `in_progress` exists)
- marks status transitions (`pending → in_progress → completed/blocked`)

### 2) Make execution explicit
There are two safe patterns:

**Pattern A: Executor triggers a hook**
- Tier 0 selects the task
- Calls an external runner via `AVS_EXECUTE_HOOK`
- Useful for non-OpenClaw systems

**Pattern B (OpenClaw): Executor is an agentTurn**
- The cron job itself is an agent run
- It reads the queue and actually performs the task
- Writes artifacts + updates queue

### 3) Require completion artifacts
A task is not “complete” unless:
- artifact exists
- outputs exist
- checksums match

### 4) Preflight multi-person repos
When tasks touch repos used by multiple people:
- `git fetch --all --prune`
- `git checkout main`
- `git pull --ff-only`
- verify expected files exist on `main`

This prevents “working on stale branches” and silently diverging from reality.

---

## AVS Implementation Notes

In this repo, Tier 0 is implemented as:
- `bin/queue-executor.sh`

Tier 0 intentionally does **not** pretend to do Tier 1 by default. It either:
- calls `AVS_EXECUTE_HOOK`, or
- prints `TASK_EXECUTION_REQUIRED` (so you wire it into OpenClaw / your runner)

That explicitness is important: it prevents the system from *looking* like it executes tasks when it doesn’t.

---

## If you remember one line

**Verification without execution is a fancy dashboard for idling.**
