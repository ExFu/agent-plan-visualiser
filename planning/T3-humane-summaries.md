---
id: T3-humane-summaries
plan_kind: thematic
tier: 3
t2_parent: T2-packaging
milestone: M4-fresh-install
status: active
---

# T3-humane-summaries — capture summaries written for humans

## Grounding and acceptance

T1's premise is a record that cannot lie; T2-packaging owns how the plugin
lands in an adopting project. This plan adds one convention to that landing:
every capture already serves agents through its typed fields, so the
`summary` string should serve the human reading `summary.md` instead of
duplicating the fields in denser prose. The operator accepted the approach
in the 2026-09-10 conversation ("Ok, sounds like a reasonable plan. Proceed.")
after reviewing the three-layer proposal below.

## Execution

1. **Peer discovery, not dependency.** Plugin manifests cannot declare
   dependencies, so `apv-capture` gains a §0.5 that checks the session's
   skill list for `exfu-humane-agents:exfu-summarising` (the only test that
   works on Claude Code, Cowork and Desktop alike). Present → that skill
   governs every `summary`, `decision.text` and blocker `note`. Absent → a
   built-in fallback rule (outcome first; why, how, what; plain words; no IDs
   or tool names; caveats survive) so capture never depends on the peer.
2. **Session orientation names the peer.** `session-orient.sh` scans the
   plugin root's sibling directories (Desktop `rpm/plugin_*/` and CLI
   `<marketplace>/<plugin>/<version>/` layouts) with the same dependency-free
   sed, and appends one clause to the orientation line when the peer is
   installed. Silent otherwise. Covered by the orientation sandbox test.
3. **Mirror into the sibling skills that emit human prose.**
   `exfu-planning-apv-integration` verdict summaries follow the same rule.
   `apv-merge` emits no human prose and needs no change.
4. **The peer side** (repo `ExFu/humane-agents`, its own plan
   `T3-summarising-skill`): a new `exfu-summarising` skill — "explain it like
   I'm 12 and have ADHD", why → how → what in that order, hard word budgets,
   caveats survive — released as 0.2.0 through the `exfu` marketplace.
5. Version 0.10.0; release through the marketplace after the peer.

## Verification

- Orientation sandbox suite green, including the new peer-detection cases
  (CLI-cache layout, Desktop layout with a space in the path, no-peer
  silence).
- Manual run of the hook with this session's real Desktop plugin root
  detects the installed peer.
- The peer skill's own RED/GREEN evidence is recorded in its plan.

## Out of scope

- A `[peers]` table in `.apv-config.toml` to make the convention required
  per project. Discovery plus fallback is enough until a project asks.
- Rewriting historic summaries in the log (append-only law).
- Mechanically enforcing the register on `summary` strings in the gate.
