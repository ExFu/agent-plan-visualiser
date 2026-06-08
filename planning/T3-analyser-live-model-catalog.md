---
id: T3-analyser-live-model-catalog
plan_kind: thematic
tier: 3
t2_parent: T2-analyser
milestone: M1.1-analyser
status: completed
---

# T3-analyser-live-model-catalog — fetch the model list live from /v1/models

> **Follow-on T3.** Bug-fix follow-on to the completed `T3-analyser-phase-a-ephemeral`
> (which built the settings modal + model picker). Per inbox item
> `2026-05-30.progressed-after-completed-state-flip` rule #4, a bug-fix follow-on to a
> completed T3 gets its own follow-on T3 rather than reanimating the closed one.

**Status:** Completed. Created and closed in one commit — the fix was already
implemented and verified when this plan was written (dogfooding the trail, not
planning ahead of the work).

---

## 1. Why this T3

Clicking **Analyse outstanding** (and **Analyse all live**) failed with:

```
{"type":"error","error":{"type":"not_found_error","message":"model: claude-sonnet-4-20250514"}}
```

Root cause, confirmed against the live account catalogue: the view **hardcoded a
model list** that has since been retired. `GET /v1/models` for the account returns
`claude-opus-4-8`, `claude-opus-4-7`, `claude-sonnet-4-6`, `claude-opus-4-6`,
`claude-opus-4-5-20251101`, `claude-haiku-4-5-20251001`,
`claude-sonnet-4-5-20250929`, `claude-opus-4-1-20250805` — and **none** of the four
IDs the UI baked in (`claude-sonnet-4-20250514`, `claude-opus-4-20250514`,
`claude-3-5-sonnet-20241022`, `claude-3-5-haiku-20241022`). The API rejects the
selected model as `not_found` because it genuinely no longer exists for this key.

Hardcoding model IDs is the defect class: Anthropic retires snapshots, so any
baked-in list drifts out of the catalogue and eventually fails at call time.

## 2. What changed (root-cause fix)

- **New `ModelCatalog` module** (`view/app.js`) — fetches `GET /v1/models` with the
  user's key, caches per key, falls back conservatively only when no key is present
  or the fetch fails. Single source of truth for "which models can this key use".
- **`index.html`** — settings dropdown de-hardcoded; options are populated live.
- **`Settings._populateModelSelect`** — fetches the catalogue for the key currently
  in the input and rebuilds the dropdown. No preloading: an empty key field shows
  only the placeholder; a debounced `input` listener fetches dynamically the moment a
  key is provided/pasted; a fetch token discards out-of-order responses.
- **Cost-dialog picker** + **global-mode default** — sourced from the live catalogue
  instead of `Object.keys(Estimator.PRICING)` / a hardcoded fallback.
- **`ModelCatalog.defaultId`** — only honours a saved `defaultModel` if it is still in
  the live catalogue, so a stale saved default (the user's was the dead
  `claude-sonnet-4-20250514`) cannot re-trigger the failure.
- **`Estimator.priceFor`** — family-based pricing inference (opus / sonnet / haiku);
  the dead per-ID `PRICING` table is emptied, kept only as an override mechanism.

Net effect: the picker can only ever offer models the key actually supports, so the
`not_found_error` class of failure is structurally eliminated.

## 3. Files

- `agent-plan-tracker/view/app.js` — `ModelCatalog`, `Estimator.priceFor`, settings
  model-select wiring, cost-dialog + global-default sourcing.
- `agent-plan-tracker/view/index.html` — de-hardcoded settings dropdown.

## 4. Verification

- `node --check app.js` passes.
- No retired model IDs remain in code paths (one explanatory comment only).
- Root cause confirmed empirically via the account's `GET /v1/models`.
- End-to-end confirmed in-browser by Al — dropdown populates from the live catalogue;
  analyse on `M1-bootstrap` succeeds with no `not_found_error` — before merge.
- Entity-state board / plan-hierarchy tree / workstreams-flow views unaffected; no
  console errors on load (regression check).

## 5. Provenance

- Surfaced from a live `not_found_error` on `M1-bootstrap` analysis, 2026-05-30.
- Applies inbox rule `2026-05-30.progressed-after-completed-state-flip` #4
  (follow-on T3, not reanimation of `T3-analyser-phase-a-ephemeral`).
- Thematic parent `T2-analyser`; milestone `M1-bootstrap` per planning direction.
