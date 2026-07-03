---
description: Post-backfill Why triage — one sitting converts the walk's candidate hypotheses into recollected decisions (or leaves them honestly open). Run after a backfill run queues hypotheses.
---

Run the post-backfill Why triage (T2-ingest §3.7): the backfill walk could
not recover why historical pivots happened, so it queued candidate
hypotheses. The operator was there; you are harvesting their recollection —
**never supplying your own**. One sitting, batch-first.

1. Find the run's hypotheses file in the data dir (resolution: `APV_DATA_DIR`
   → `.apv-config.toml` `[storage] data_dir` → `.apv/`):

   ```bash
   ls <data-dir>/needs-review/hypotheses-*.jsonl
   ```

   None present → report "nothing queued for triage" and stop. (Consumed
   files live in `<data-dir>/archive/` — re-triage is a no-op by design.)

2. Read the file. For **each** entry, ask the operator ONE question
   (AskUserQuestion; resumable — stop cleanly if they bail mid-way):
   the fulcrum moment (entity, what happened, the anchored commit subject
   and date) and the walk's candidate rationales as options, plus:
   - each candidate as a selectable option (→ ruling `confirmed`, text =
     that candidate in full sentences);
   - "Other" free text (→ ruling `reworded`, text = their words);
   - an explicit "Don't remember / leave open" option (→ ruling `unknown`).
   Never pressure toward a candidate — an honest `unknown` beats a shaky
   confirmation; the question simply stays open in the record.

3. Write the rulings to a JSON file (array of `{question_entity_id,
   ruling, text}`) and run the deterministic emitter:

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/backfill/triage-emit.py" \
     --project-path . --run-id <run> --rulings <rulings.json> --actor <operator-handle>
   ```

   The emitter appends recollected `decision` events (operator as actor —
   their say-so is the event), closes answered questions, leaves unknowns
   standing, and archives the hypotheses file.

4. Conclude per capture discipline: validate (`repack-validate.sh`), stamp
   `.last-capture`, and seal the triage commit via /apv-capture — the
   block's seal message should name the run (e.g. "triage(bf-...): N
   recollected, M left open").
