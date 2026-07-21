-- agent-plan-visualiser cache schema v0.5.0
-- (no DDL change from v0.4.0 at the epoch cut — the 0.5.0 epoch adds the
--  verification.deferred event type only; see schemas/0.5.0/events.schema.json.
--  Diff WITHIN 0.5.0, T3-multi-project: entities.project — the multi-project
--  membership fold. No event type added, so no new epoch; the cache is
--  dropped and rebuilt every run, so the column self-deploys.)
-- Derived from events.jsonl; fully regenerable.
--
-- Diff from v0.1.0:
--   - Adds `summaries` table for analysis.live-summary events
--     (T2-analyser §3.2 / Phase B).
--
-- Diff from v0.2.0 (the 0.4.0 provenance epoch, T2-ontology §3.12):
--   - events: origin / backfill_run / event_time (block seal day — the
--     event-time anchor projections order by; record order stays line_no).
--   - commits: origin / anchor_commit_ref (backfilled seals quote the
--     historical sha) / event_time.

CREATE TABLE IF NOT EXISTS events (
  event_id        TEXT PRIMARY KEY,
  type            TEXT NOT NULL,
  entity_type     TEXT,
  entity_id       TEXT,
  actor           TEXT NOT NULL,
  confidence      TEXT NOT NULL,
  schema_version  TEXT NOT NULL,
  attributes      TEXT NOT NULL,
  line_no         INTEGER NOT NULL,
  commit_ref      TEXT,
  commit_author   TEXT,
  commit_date     TEXT,
  commit_message_first_line TEXT,
  commit_recorded_event_id  TEXT,  -- event_id of the bracketing commit.recorded event; NULL for trailing in-progress events
  origin          TEXT,   -- NULL/'captured' = contemporaneous; 'backfilled' = retrospective
  backfill_run    TEXT,   -- cohort id for backfilled events (repudiation unit)
  event_time      TEXT    -- block anchor day (seal date[:10]); NULL for unsealed tail
);
CREATE INDEX IF NOT EXISTS idx_events_origin ON events(origin);
CREATE INDEX IF NOT EXISTS idx_events_event_time ON events(event_time);
CREATE INDEX IF NOT EXISTS idx_events_entity ON events(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_events_type ON events(type);
CREATE INDEX IF NOT EXISTS idx_events_commit_ref ON events(commit_ref);
CREATE INDEX IF NOT EXISTS idx_events_commit_date ON events(commit_date);
CREATE INDEX IF NOT EXISTS idx_events_commit_recorded ON events(commit_recorded_event_id);

CREATE TABLE IF NOT EXISTS entities (
  entity_type           TEXT NOT NULL,
  entity_id             TEXT NOT NULL,
  derived_state         TEXT NOT NULL,
  attributes            TEXT,
  last_event_id         TEXT NOT NULL,
  event_type_sequence   TEXT NOT NULL,
  origin                TEXT NOT NULL DEFAULT 'captured',  -- 'captured' | 'backfilled' | 'mixed'
  project               TEXT NOT NULL DEFAULT 'main',      -- registry name | 'main' | 'unassigned'
  PRIMARY KEY (entity_type, entity_id)
);
CREATE INDEX IF NOT EXISTS idx_entities_state ON entities(derived_state);
CREATE INDEX IF NOT EXISTS idx_entities_project ON entities(project);

CREATE TABLE IF NOT EXISTS relationships (
  from_entity_type      TEXT NOT NULL,
  from_entity_id        TEXT NOT NULL,
  to_entity_type        TEXT NOT NULL,
  to_entity_id          TEXT NOT NULL,
  relationship_type     TEXT NOT NULL,
  source_event_id       TEXT,             -- nullable: NULL for frontmatter-derived edges
  source                TEXT NOT NULL DEFAULT 'event',  -- 'event' | 'frontmatter'
  PRIMARY KEY (from_entity_type, from_entity_id, to_entity_type, to_entity_id, relationship_type)
);
CREATE INDEX IF NOT EXISTS idx_relationships_from ON relationships(from_entity_type, from_entity_id);
CREATE INDEX IF NOT EXISTS idx_relationships_to ON relationships(to_entity_type, to_entity_id);
CREATE INDEX IF NOT EXISTS idx_relationships_type ON relationships(relationship_type);
CREATE INDEX IF NOT EXISTS idx_relationships_source ON relationships(source);

CREATE TABLE IF NOT EXISTS decisions (
  decision_event_id     TEXT PRIMARY KEY,
  text                  TEXT NOT NULL,
  referenced_event_ids  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS commits (
  commit_recorded_event_id  TEXT PRIMARY KEY,
  commit_ref            TEXT,  -- nullable: post-rewrite (e.g. schema migration) multiple commit.recorded events may share a ref
  author                TEXT NOT NULL,
  date                  TEXT NOT NULL,
  message_first_line    TEXT NOT NULL,
  first_event_line_no   INTEGER NOT NULL,
  last_event_line_no    INTEGER NOT NULL,
  origin                TEXT,   -- 'backfilled' when the seal is a historical anchor
  anchor_commit_ref     TEXT,   -- backfilled seals: the anchored historical sha
  event_time            TEXT    -- seal date[:10]
);
CREATE INDEX IF NOT EXISTS idx_commits_ref ON commits(commit_ref);

-- New in v0.2.0: analyser summaries.
-- One row per analysis.live-summary event. `valid` flips to 0 when an
-- analysis.invalidated event references this row's event_id either directly
-- (target_event_id) or via cascade (cascades_to_event_ids[]).
CREATE TABLE IF NOT EXISTS summaries (
  event_id                       TEXT PRIMARY KEY,
  entity_type                    TEXT NOT NULL,
  entity_id                      TEXT NOT NULL,
  source                         TEXT NOT NULL,           -- 'primary' | 'derived'
  model                          TEXT NOT NULL,
  origin_summary_event_id        TEXT,
  supersedes_summary_event_id    TEXT,
  freeform_path                  TEXT NOT NULL,
  structured                     TEXT NOT NULL,           -- JSON blob
  line_no                        INTEGER NOT NULL,
  valid                          INTEGER NOT NULL DEFAULT 1,
  invalidated_by_event_id        TEXT,
  created_commit_recorded_event_id TEXT
);
CREATE INDEX IF NOT EXISTS idx_summaries_entity ON summaries(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_summaries_valid ON summaries(valid);
CREATE INDEX IF NOT EXISTS idx_summaries_source ON summaries(source);
