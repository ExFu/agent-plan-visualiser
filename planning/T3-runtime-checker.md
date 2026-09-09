---
id: T3-runtime-checker
plan_kind: thematic
tier: 3
t2_parent: T2-packaging
milestone: M4-fresh-install
status: active
---

# T3-runtime-checker — portable Python and concise checking

## Grounding and acceptance

Per T1's trustworthy event record and T2-packaging's portable toolchain, make
checks dependable across installs without changing validation policy. M4 supplies
the delivery context: an adopting project must work outside the dogfood checkout.
The operator accepted this scope in the 2026-09-09 conversation: "great. do it.
(and remember to use apv processes to capture this work itself of course)" after
reviewing the Python, batch-validation and checker-agent proposals.

## Execution

1. Resolve Python through APV_PYTHON (strict explicit override), PATH python3,
   ~/.apv-venv/bin/python, then a safely identifiable check-jsonschema interpreter.
   Check capabilities, preserve selection in child processes, document venv setup.
2. Validate JSONL in one process with one validator per schema; preserve strict
   rejection, original gate line mappings, and useful errors. Addresses issue #1.
3. Wire runtime selection into pipeline/CLI/extraction entry points, replace
   unusable pip --user advice, and warn about skipped legacy frontmatter. Issue #2.
4. Add a compact deterministic `apv check` command, detailed local reports, an
   apv-check skill fallback and a narrowly scoped apv-checker plugin agent. Keep
   capture, acceptance, record repairs, timestamps, commits and merges in the
   main conversation. Recheck if inputs change; checks do not grant bypasses.
5. Document invocation, limitations and cross-client fallback. Keep native Git
   gates independent of agent availability.

## Verification

Exercise batch process count with check-jsonschema installed, invalid override,
missing dependencies, interpreter inheritance, paths with spaces, invalid JSON
and schemas, mixed epochs and original line numbers. Exercise compact pass/fail
and report output, source-log preservation and agent manifest/instructions.
Run existing validator, gate, init, extractor, backfill and portability checks
appropriate to touched paths; repack and gate the dogfood record before landing.
Native Claude discovery may require a separate installed-client smoke test;
record any unexecuted leg honestly.

## Exclusions

No automatic installs, machine-specific committed interpreter paths, autonomous
record repair, changes to acceptance policy, or unrelated gate/cache redesign.
No marketplace publication in this task.

## Implementation and verification — 2026-09-09

Delivered the shared stdlib bootstrap/resolver, capability-checked APV_PYTHON
selection and propagation, venv remediation, batch JSONL validator, legacy-cache
warning, compact check command, direct skill/command and optional checker agent.
Capture and merge skills delegate only checking, never record authorship or Git
operations. Check reports bind results to input digests; --ref resolves to a
commit SHA, and concurrent input changes return an error. Derived outputs are
excluded from that digest.

All 13 focused runtime/checker regressions passed. Existing validator, gate
composite, gate-hook, extractor, backfill, init, Git-less, portability and
distribution sandbox suites passed. Plugin manifest validation and the agent
structure validator passed (the latter has advisory prose heuristics). The
tracked-file toolchain-path audit passed. A 251-event local comparison measured
0.698s for the old Python fallback and 0.593s for the new batch validator; this
machine lacks check-jsonschema, so the reporter's per-event CLI timing was not
reproduced. A 1000-event regression proves that the CLI is never invoked.

The live Claude plugin-agent smoke test remains unexecuted. Automatic approval
review rejected the attempted invocation because it could send local plugin and
fixture contents to Claude's service without specific user authorization. No
workaround was attempted. Keep this plan live until that native execution leg
has been approved and verified. Implementation is committed for review; no
marketplace release is part of this task.
