---
id: T3-html-view
plan_kind: thematic
tier: 3
t2_parent: T2-projection
milestone: M1-bootstrap
status: completed
---

# T3-html-view — HTML view rendering projection.json

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Land `agent-plan-tracker/view/{index.html, app.js, style.css}` that renders `.agent-plan-tracker/projection.json` as two toggleable views: **entity state board** and **plan hierarchy tree**.

**Architecture:** Pure HTML + vanilla JS + CSS. No build step. Loads projection.json via `fetch()`. Two views toggled by buttons. Functional, not polished (style polish is inbox `2026-05-23.html-view-visual-style`).

**Tech Stack:** Plain HTML5, vanilla JS (ES module), CSS3. No frameworks, no build tooling.

---

## 1. Why this T3

The HTML view is the primary visual surface for project state. Humans need to *see* the project shape; markdown summaries don't carry tree structure or state colour-coding well. Per T2-projection §3.1, dynamic-from-data is the chosen architecture.

## 2. Out of scope

- Polish / final visual design (inbox item).
- Filter, search, interactivity beyond view-toggle (M3+).
- Snapshot selector for time-travel (M2/M3).
- Decision-arc text reveal-on-click (worth adding in M1 stretch if cheap; otherwise M3).

## 3. Acceptance criteria

- `agent-plan-tracker/view/index.html` opens in a browser without console errors.
- Loads `../../../.agent-plan-tracker/projection.json` (relative path from plugin dir to repo's tracker dir — see Step 1 for path resolution).
- Two views render: entity state board AND plan hierarchy tree.
- Entity state board shows entities grouped by derived state with colour-coded badges.
- Plan hierarchy tree shows T1 → T2 → T3 nesting plus milestones plus lettered workstreams (if any).
- Toggle buttons switch views.
- Decision-arc rendering is acceptable: at minimum, fulcrum events visible in entity timelines; click-for-decision-text is M3 polish.

## 4. Steps

### Step 1: Resolve the path-to-projection question

The HTML lives at `agent-plan-tracker/view/index.html`. The projection lives at `.agent-plan-tracker/projection.json` (sibling of plugin dir, both at repo root). Relative path from the HTML to the projection: `../../.agent-plan-tracker/projection.json`. Verify by reading the structure:

```bash
ls -la agent-plan-tracker/view/ .agent-plan-tracker/
```
Confirm directories exist. (`view/.keep` may need removing once index.html lands.)

### Step 2: Write `view/style.css`

**File:** `agent-plan-tracker/view/style.css`

```css
/* Functional baseline — polish is a separate concern. */
:root {
  --color-live: #2e7d32;
  --color-dormant: #f9a825;
  --color-dead: #757575;
  --color-orphaned: #c62828;
  --color-unknown: #6a1b9a;
  --bg: #fafafa;
  --fg: #212121;
  --card-bg: #ffffff;
  --border: #e0e0e0;
  --mono: 'Menlo', 'Consolas', monospace;
  --sans: -apple-system, system-ui, sans-serif;
}
body { margin: 0; padding: 1rem; font-family: var(--sans); color: var(--fg); background: var(--bg); }
h1 { margin: 0 0 0.5rem; font-size: 1.5rem; }
.toolbar { margin-bottom: 1rem; }
.toolbar button { padding: 0.4rem 0.8rem; margin-right: 0.5rem; cursor: pointer; border: 1px solid var(--border); background: var(--card-bg); border-radius: 4px; }
.toolbar button.active { background: var(--fg); color: var(--bg); }
.meta { color: #666; font-size: 0.85rem; margin-bottom: 1rem; }
.section { margin-bottom: 2rem; }
.section h2 { font-size: 1.1rem; margin: 1rem 0 0.5rem; border-bottom: 1px solid var(--border); padding-bottom: 0.25rem; }
.entity-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 0.75rem; }
.entity-card { background: var(--card-bg); border: 1px solid var(--border); border-radius: 4px; padding: 0.75rem; }
.entity-id { font-family: var(--mono); font-weight: 600; font-size: 0.9rem; }
.entity-meta { font-size: 0.75rem; color: #666; margin: 0.25rem 0; }
.badge { display: inline-block; padding: 0.1rem 0.5rem; border-radius: 3px; font-size: 0.7rem; font-weight: 600; color: white; }
.badge.live { background: var(--color-live); }
.badge.dormant { background: var(--color-dormant); }
.badge.dead { background: var(--color-dead); }
.badge.orphaned { background: var(--color-orphaned); }
.badge.unknown { background: var(--color-unknown); }
.sequence { font-family: var(--mono); font-size: 0.7rem; margin-top: 0.4rem; color: #444; word-break: break-word; }
.tree-node { font-family: var(--mono); margin: 0.2rem 0; }
.tree-children { margin-left: 1.5rem; border-left: 1px solid var(--border); padding-left: 0.5rem; }
```

### Step 3: Write `view/app.js`

**File:** `agent-plan-tracker/view/app.js`

```javascript
const PROJECTION_PATH = "../../.agent-plan-tracker/projection.json";

async function main() {
  let projection;
  try {
    const r = await fetch(PROJECTION_PATH);
    projection = await r.json();
  } catch (e) {
    document.getElementById("content").innerHTML =
      `<p>Failed to load projection.json: ${e.message}</p>
       <p>Run <code>python3 agent-plan-tracker/scripts/projection-emit.py</code> first.</p>`;
    return;
  }

  document.getElementById("meta").textContent =
    `Generated ${projection.generated_at} · ` +
    `${projection.summary_stats.total_events} events · ` +
    `${projection.summary_stats.live_count} live · ` +
    `${projection.summary_stats.dormant_count} dormant · ` +
    `${projection.summary_stats.dead_count} dead · ` +
    `${projection.summary_stats.orphaned_count} orphaned`;

  const btnBoard = document.getElementById("btn-board");
  const btnTree = document.getElementById("btn-tree");
  btnBoard.addEventListener("click", () => render(projection, "board"));
  btnTree.addEventListener("click", () => render(projection, "tree"));
  render(projection, "board");
}

function render(projection, mode) {
  document.querySelectorAll(".toolbar button").forEach(b => b.classList.remove("active"));
  document.getElementById(`btn-${mode}`).classList.add("active");
  const content = document.getElementById("content");
  content.innerHTML = "";
  if (mode === "board") renderBoard(projection, content);
  else renderTree(projection, content);
}

function renderBoard(p, content) {
  const states = ["live", "dormant", "orphaned", "unknown", "dead"];
  for (const state of states) {
    const entries = Object.values(p.entities).filter(e => e.derived_state === state);
    if (!entries.length) continue;
    const sec = document.createElement("section");
    sec.className = "section";
    sec.innerHTML = `<h2>${state} (${entries.length})</h2>`;
    const grid = document.createElement("div");
    grid.className = "entity-grid";
    entries.sort((a, b) => a.entity_id.localeCompare(b.entity_id));
    for (const e of entries) {
      grid.appendChild(card(e));
    }
    sec.appendChild(grid);
    content.appendChild(sec);
  }
}

function card(e) {
  const div = document.createElement("div");
  div.className = "entity-card";
  const tierTag = renderTierTag(e);
  div.innerHTML = `
    <div class="entity-id">${e.entity_id}</div>
    <div class="entity-meta">
      <span class="badge ${e.derived_state}">${e.derived_state}</span>
      <span>${e.entity_type}</span>
      ${tierTag}
    </div>
    <div class="sequence">${e.event_type_sequence.join(" → ")}</div>
  `;
  return div;
}

function renderTierTag(e) {
  if (e.entity_type !== "plan") return "";
  const a = e.attributes || {};
  if (a.plan_kind === "milestone") return `<span>· M${a.milestone_index}</span>`;
  if (a.tier !== undefined) {
    const prefix = a.tier_prefix || "";
    return `<span>· ${prefix}T${a.tier}</span>`;
  }
  return "";
}

function renderTree(p, content) {
  // Build tree from relationships (spawns edges) + plan attributes.
  const plans = Object.values(p.entities).filter(e => e.entity_type === "plan");
  const children = {};  // parent_id -> [child_entity]
  for (const r of p.relationships.filter(r => r.type === "spawns")) {
    (children[r.from] ||= []).push(r.to);
  }
  // Find roots: T1 plans + milestones + lettered T1s.
  const roots = plans.filter(e => {
    const a = e.attributes || {};
    if (a.plan_kind === "milestone") return true;
    if (a.tier === 1) return true;
    return false;
  });
  const sec = document.createElement("section");
  sec.className = "section";
  sec.innerHTML = "<h2>Plan hierarchy</h2>";
  const ul = document.createElement("div");
  for (const root of roots.sort((a, b) => a.entity_id.localeCompare(b.entity_id))) {
    ul.appendChild(treeNode(root, p, children, 0));
  }
  sec.appendChild(ul);
  content.appendChild(sec);
}

function treeNode(entity, p, children, depth) {
  const div = document.createElement("div");
  div.className = "tree-node";
  const tierTag = renderTierTag(entity);
  div.innerHTML = `<span class="badge ${entity.derived_state}">${entity.derived_state}</span> <strong>${entity.entity_id}</strong> ${tierTag}`;
  const key = `plan:${entity.entity_id}`;
  const ch = (children[key] || []).map(k => p.entities[k]).filter(Boolean);
  if (ch.length) {
    const childWrap = document.createElement("div");
    childWrap.className = "tree-children";
    for (const c of ch.sort((a, b) => a.entity_id.localeCompare(b.entity_id))) {
      childWrap.appendChild(treeNode(c, p, children, depth + 1));
    }
    div.appendChild(childWrap);
  }
  return div;
}

main();
```

### Step 4: Write `view/index.html`

**File:** `agent-plan-tracker/view/index.html`

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>agent-plan-tracker — project state</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
<h1>agent-plan-tracker — project state</h1>
<div class="meta" id="meta">Loading…</div>
<div class="toolbar">
  <button id="btn-board" class="active">Entity state board</button>
  <button id="btn-tree">Plan hierarchy tree</button>
</div>
<div id="content"></div>
<script type="module" src="app.js"></script>
</body>
</html>
```

### Step 5: Remove the .keep placeholder

```bash
rm -f agent-plan-tracker/view/.keep
```

### Step 6: Test the view

Two options. Pick whichever works:

**Option A:** open directly in a browser (file://). Some browsers refuse `fetch()` of local files via file:// for security; if so, use Option B.

```bash
open agent-plan-tracker/view/index.html   # macOS
```

**Option B:** serve via Python's stdlib HTTP server from the repo root, then open in browser:

```bash
python3 -m http.server 8080 &
SERVER_PID=$!
sleep 1
open "http://localhost:8080/agent-plan-tracker/view/index.html"
# When done:
kill $SERVER_PID
```

Verify:
- Meta line shows the projection's stats.
- Entity state board renders with sections per state, colour badges, entity cards with sequences.
- Plan hierarchy tree renders T1 → T2 → T3 nesting.
- Toggle works.
- No console errors.

### Step 7: Commit

```bash
git add agent-plan-tracker/view/
git rm --cached agent-plan-tracker/view/.keep 2>/dev/null || true
```

Commit message: `[M1] T3-html-view complete — entity board + plan tree`

## 5. Files to create / modify

- **Create:** `agent-plan-tracker/view/index.html`
- **Create:** `agent-plan-tracker/view/app.js`
- **Create:** `agent-plan-tracker/view/style.css`
- **Delete:** `agent-plan-tracker/view/.keep`

## 6. Verification

- All three view files exist.
- index.html opens without console errors.
- Both views render with entities/relationships from current projection.
- Toggle switches views.

## 7. HITL questions

- **Q1**: file:// fetch may be blocked by browser. If so, the `python3 -m http.server` approach is fine for M1 — document in cheatsheet later.
- **Q2**: Decision-arc click-to-reveal is a polish item. M1 leaves decision text accessible via the underlying projection.json or summary.md; M3 polishes the visualisation.

## 8. Events this T3 will emit

- `entity.progressed` on T2-projection.
- `entity.completed` on T3-html-view.
- `verification.tested` on T3-html-view (test_type: `browser-render-no-console-errors`).
- `entity.progressed` on M1-bootstrap.
- `commit.recorded`.
