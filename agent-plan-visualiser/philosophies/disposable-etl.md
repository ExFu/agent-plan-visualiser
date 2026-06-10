# Disposable ETL

Code that bridges two stable surfaces is throwaway. Design for the bridge job, not for permanence.

## The principle

When two systems each have stable internal data shapes, the code that moves data between them is *bridge code* — its only job is to translate. Such code is intrinsically disposable: if either side changes, the bridge changes (or is replaced); if both sides stabilise, the bridge runs forever without modification.

This is the classic ETL (extract / transform / load) shape. It applies to:

- Cache builders (events.jsonl → SQLite).
- Projection emitters (SQLite → projection.json).
- View renderers (projection.json → HTML).
- Format migrators (schema v0.1 → schema v0.2).

## Why this matters for design

Treating bridge code as permanent leads to over-engineering: framework choices, plugin systems, configurable strategies — all premised on the bridge being load-bearing infrastructure rather than a glorified function.

Treating bridge code as disposable leads to right-sized solutions: a script. A function. A handful of SQL statements. Easy to read, easy to throw away when the shape changes.

## How to apply

When you find yourself writing code that just transforms shape A into shape B:

1. Ask: are A and B both designed for stability? (Usually yes — they're external surfaces, schemas, APIs.)
2. Ask: is the transformation logic itself going to be stable, or will it change whenever A or B does? (Almost always the latter.)
3. Then: write the simplest thing that works. Don't add configuration knobs. Don't make it extensible. Don't introduce a framework. The next person who needs to change it should be able to read it in two minutes and rewrite it in ten.

## Where this principle binds in our own design

- `scripts/cache-build.sh` (or equivalent) — pure SQL plus a small wrapper. Don't make it pluggable.
- `scripts/projection-emit.sh` — SQL queries to JSON. No interpretation, no rules engine.
- `view/app.js` — DOM rendering from JSON. No state management framework needed.

The temptation will be to add abstractions that "future-proof" the bridges. Resist. The bridge is meant to be thrown away. Throwing it away is the success case.

## Common failure mode

Building a generic "projection framework" with plugin architecture, configurable transformers, lifecycle hooks. This optimises for a future that probably won't happen. If a *second* projection target appears, *then* extract the common parts. Premature framework-building costs more than it saves.

## Connection to other philosophies

`swap-out-surfaces.md` is the inverse view: stable surfaces are explicitly named and their swap-out triggers documented. Bridges between them are the disposable layer.
