# Inbox (prehistoric)

This directory is the prehistoric materialisation of the inbox concept (T1 §2.6, formally `inbox-item` entity type per T2-ontology §3.9).

The inbox is an append-only capture surface for ideas, observations, partially-formed concerns, tool / skill / agent candidates, and miscellaneous future-work flags that have surfaced during design or execution but haven't yet earned a real plan.

## Convention (prehistoric — will formalise)

- One markdown file per inbox item.
- Filename: `<YYYY-MM-DD>-<title-slug>.md` (matches `entity_id` modulo the `.md`).
- Frontmatter:
  ```yaml
  ---
  id: <YYYY-MM-DD>.<title-slug>
  entity_type: inbox-item
  created_at: <YYYY-MM-DD>
  status: open
  candidate_fate: <skill | tool | t3 | t2 | decision | philosophy | discovery | undecided>
  ---
  ```
- Body: free-form. Include enough context that a future agent could resurrect the idea cold without the conversation that generated it.

## Lifecycle (per T1 §2.6)

Each item terminates as:

- **completed** — captured + resolved in-place; file marked.
- **cancelled** — won't pursue; file marked, kept for provenance.
- **parked** — explicitly deferred; file marked.
- **converted to plan** — promoted to a real plan; the inbox item closes via a `relationship.spawns` event linking to the new plan.

## Triage discipline

Inbox is checked periodically (per session start, or on demand). Items aren't allowed to age forever; old items get an explicit terminal status even if "parked".

## Why "prehistoric"

The inbox lifecycle, frontmatter schema, and tooling aren't fully specified yet. This directory implements enough of the concept to capture value now, with the expectation that the formal schema (in a future schema version) may reshape these files. Schema retro-migration is permitted under `0.0.0-prehistoric` discipline.

## Current items

(Auto-listing not yet implemented; see directory listing for now.)
