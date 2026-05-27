-- agent-plan-tracker cache schema v0.1.0
-- Derived from events.jsonl; fully regenerable.

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
  commit_message_first_line TEXT
);
CREATE INDEX IF NOT EXISTS idx_events_entity ON events(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_events_type ON events(type);
CREATE INDEX IF NOT EXISTS idx_events_commit_ref ON events(commit_ref);
CREATE INDEX IF NOT EXISTS idx_events_commit_date ON events(commit_date);

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
  source_event_id       TEXT NOT NULL,
  PRIMARY KEY (from_entity_type, from_entity_id, to_entity_type, to_entity_id, relationship_type)
);
CREATE INDEX IF NOT EXISTS idx_relationships_from ON relationships(from_entity_type, from_entity_id);
CREATE INDEX IF NOT EXISTS idx_relationships_to ON relationships(to_entity_type, to_entity_id);
CREATE INDEX IF NOT EXISTS idx_relationships_type ON relationships(relationship_type);

CREATE TABLE IF NOT EXISTS decisions (
  decision_event_id     TEXT PRIMARY KEY,
  text                  TEXT NOT NULL,
  referenced_event_ids  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS commits (
  commit_ref            TEXT PRIMARY KEY,
  author                TEXT NOT NULL,
  date                  TEXT NOT NULL,
  message_first_line    TEXT NOT NULL,
  commit_recorded_event_id  TEXT NOT NULL,
  first_event_line_no   INTEGER NOT NULL,
  last_event_line_no    INTEGER NOT NULL
);
