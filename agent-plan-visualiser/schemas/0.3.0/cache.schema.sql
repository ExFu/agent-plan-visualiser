-- agent-plan-tracker cache schema v0.2.0
-- Derived from events.jsonl; fully regenerable.
--
-- Diff from v0.1.0:
--   - Adds `summaries` table for analysis.live-summary events
--     (T2-analyser §3.2 / Phase B).

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
  commit_recorded_event_id  TEXT  -- event_id of the bracketing commit.recorded event; NULL for trailing in-progress events
);
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
  PRIMARY KEY (entity_type, entity_id)
);
CREATE INDEX IF NOT EXISTS idx_entities_state ON entities(derived_state);

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
  last_event_line_no    INTEGER NOT NULL
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
