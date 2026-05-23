---
id: 2026-05-23.html-view-visual-style
entity_type: inbox-item
created_at: 2026-05-23
status: open
candidate_fate: t3
---

# HTML view visual style decisions needed

The HTML view (T2-projection §3.2) will need concrete visual style choices once it gets past M1's functional-only acceptance:

- **Colour palette per derived state** — visual differentiation between live / dormant / dead / orphaned / unknown. Probably a 5-colour scheme with accessibility-friendly contrast.
- **Typography** — readable monospace for IDs and timestamps; sans-serif for prose; clear hierarchy between entity title / metadata / sequence.
- **Layout for entity cards** — card grid for entity state board view. Density vs readability tradeoff.
- **Tree visualisation** — for the plan hierarchy tree view: D3.js (powerful but adds dependency), raw SVG (works without deps but verbose), pure CSS tree (limited interactivity). Per `swap-out-surfaces.md`, vanilla JS is the swap-out surface — avoid framework lock-in.
- **Responsive considerations** — most users on desktop, but Cowork might surface in narrower contexts.
- **Decision-arc click affordance** — fulcrum arcs need to be visually distinct + obviously clickable.

Currently the M1 acceptance is "functional, not polished" (T2-projection §7 Q4). Once functional ships, this inbox item becomes the placeholder for the polish pass — possibly an `XT` (crosscut) workstream if visual design becomes its own concern spanning multiple projection views.

**Resurrect when:** M1 ships and the bare functional view is in hand. Either spawn a T3 under T2-projection (`T3-html-view-polish`) or an XT workstream if design grows beyond M1's scope.
