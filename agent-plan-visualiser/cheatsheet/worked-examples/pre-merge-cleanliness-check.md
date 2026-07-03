# Worked example — pre-merge cleanliness check

**Question**: "can this branch land on main?" — the answer is the gate,
run branch-side *before* attempting the merge.

```bash
bash "$APV/scripts/gate-check.sh"            # gates the working state vs HEAD
```

- **Exit 0 (PASS)** — the record is trustworthy; proceed to `/apv-merge`,
  which re-runs the gate as part of its doctrine (main's log must be a
  prefix of the branch's; contradictions go to the operator).
- **Exit 1 (BLOCK)** — a `BLOCK [...]` line names the defect and the
  entity. Blocking defects are corruption of the record and are
  **repaired append-only, never overridden**: e.g. implementation events
  against a draft entity are healed by the operator's `entity.accepted`
  (their say-so, captured), a resurrection by a deliberate
  `entity.reopened` + `decision`. Re-run until green.
- **WARN lines** — dashboard signal (drift, orphans, stalled,
  long-blockers); they merge freely but are worth a look while you're here.

The pre-push and reference-transaction hooks enforce the same contract
mechanically, so nothing red reaches main even if this step is skipped.
