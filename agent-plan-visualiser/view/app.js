// agent-plan-visualiser — HTML view
// Three views: Entity state board, Plan hierarchy tree, Workstreams flow.
// Pure SVG + vanilla JS. No external dependencies. No build step.

const PROJECTION_PATH = "../../.agent-plan-tracker/projection.json";
const EVENTS_PATH = "../../.agent-plan-tracker/events.jsonl";

const state = {
  projection: null,
  events: null,
  currentView: "board",
  // Flow view — T3 (leaf) rows are grouped into bands by `flowAggregate`,
  // INDEPENDENT of which parent bands are shown. "none" = one flat T3 band.
  flowAggregate: "milestone", // "milestone" | "t2" | "none"
  flowShowMilestones: true,    // show the Milestones parent band
  flowShowDomains: true,       // show the T2 Domains parent band
  // Flow-view focus filters (T3-flow-view-filtering). Persist across switchView
  // re-renders. Entity-keyed members (hiddenEntities, entity isolateRoot,
  // lifecycle) are aggregate-independent; band-keyed members (hiddenSwimlanes,
  // collapsedSwimlanes, swimlane isolateRoot) are cleared when the aggregation
  // axis changes (T3 band keys differ between axes).
  flowFilters: {
    hiddenEntities: new Set(),     // entity keys muted via eye toggle — keep a greyed row
    hiddenSwimlanes: new Set(),    // swimlane keys muted via section eye toggle
    collapsedSwimlanes: new Set(), // swimlane keys collapsed to a placeholder node
    isolateRoot: null,             // { kind: "entity"|"swimlane", key } or null
    lifecycle: "all",              // "all" | "open" | "closed"
  },
};

// ---------------------------------------------------------------------------
// Bootstrap
// ---------------------------------------------------------------------------

async function main() {
  initAnalyser();
  try {
    const [pRes, eRes] = await Promise.all([
      fetch(PROJECTION_PATH),
      fetch(EVENTS_PATH),
    ]);
    if (!pRes.ok) throw new Error(`projection.json: HTTP ${pRes.status}`);
    if (!eRes.ok) throw new Error(`events.jsonl: HTTP ${eRes.status}`);
    state.projection = await pRes.json();
    const eText = await eRes.text();
    const rawEvents = eText.trim().split("\n").filter(Boolean).map(line => JSON.parse(line));
    // Apply the rename identity-migration to raw events so the view's identity
    // model matches the cache/projection. events.jsonl is the append-only
    // canonical log: an `entity.renamed` event does NOT rewrite the old events'
    // entity_id in the log — cache-build folds `from_name -> to_name` when it
    // materialises entities/relationships. The view ALSO reads raw events
    // directly (for full event objects projection.json doesn't carry), so it
    // must apply the SAME fold; otherwise a renamed entity splits into a phantom
    // lane under the old id plus an empty lane under the new id. Single-hop,
    // last-write-wins — mirrors cache-build.py's id_remap (see its rename
    // pre-scan + T2-ontology §3.11). Original ids are preserved in each rename
    // event's attributes.from_name for history.
    const renameMap = {};
    for (const ev of rawEvents) {
      if (ev.type !== "entity.renamed") continue;
      const from = ev.attributes?.from_name, to = ev.attributes?.to_name;
      if (from && to) renameMap[from] = to;
    }
    for (const ev of rawEvents) {
      if (ev.entity_id && renameMap[ev.entity_id]) ev.entity_id = renameMap[ev.entity_id];
    }
    state.events = rawEvents;

    // Reconcile denormalized membership (attributes.milestone / .t2_parent)
    // from the relationship fold — the single source of truth. An entity's
    // frozen entity.created seed can be STALE vs the fold after a reattach or
    // rename (e.g. M6-analyser -> M1.1-analyser, or a milestone re-tag):
    // cache-build rewrites the *relationship edges* last-write-wins but leaves
    // the seed copy in attributes untouched. milestone_progress already reads
    // the fold (M1.2 D-C); bandKey() reads attributes.milestone/.t2_parent,
    // so without this the flow view lanes renamed/reattached plans under their
    // stale seed (a phantom "M6-analyser" lane). Mirror the fold here so every
    // view groups consistently with milestone_progress and the hierarchy tree.
    {
      const ents = state.projection.entities;
      for (const rel of state.projection.relationships || []) {
        if (rel.type !== "spawns") continue;
        const parent = ents[rel.from], child = ents[rel.to];
        if (!parent || !child) continue;
        const pa = parent.attributes || {};
        child.attributes = child.attributes || {};
        if (pa.plan_kind === "milestone") child.attributes.milestone = parent.entity_id;
        else if (pa.tier === 2) child.attributes.t2_parent = parent.entity_id;
      }
    }
  } catch (e) {
    document.getElementById("content").innerHTML =
      `<p>Failed to load data: ${escapeHtml(e.message)}</p>
       <p>If you're opening this from <code>file://</code>, your browser may block fetch.
       Serve from the repo root with <code>python3 -m http.server 8765</code> and open
       <code>http://localhost:8765/agent-plan-visualiser/view/index.html</code> instead.</p>
       <p>Also confirm the pipeline has run:
       <code>python3 agent-plan-visualiser/scripts/projection-emit.py</code>.</p>`;
    return;
  }

  document.getElementById("meta").textContent =
    `Generated ${state.projection.generated_at} · ` +
    `${state.projection.summary_stats.total_events} events · ` +
    `${state.projection.summary_stats.live_count} live · ` +
    `${state.projection.summary_stats.dormant_count} dormant · ` +
    `${state.projection.summary_stats.closed_count} closed · ` +
    `${state.projection.summary_stats.orphaned_count} orphaned`;

  document.getElementById("btn-board").addEventListener("click", () => switchView("board"));
  document.getElementById("btn-tree").addEventListener("click", () => switchView("tree"));
  document.getElementById("btn-flow").addEventListener("click", () => switchView("flow"));

  // Esc clears flow-view isolation (T3-flow-view-filtering D2).
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && state.currentView === "flow" && state.flowFilters.isolateRoot) {
      state.flowFilters.isolateRoot = null;
      rerenderFlow();
    }
  });

  switchView("flow");
}

function switchView(view) {
  state.currentView = view;
  document.querySelectorAll(".toolbar button").forEach(b => b.classList.remove("active"));
  document.getElementById(`btn-${view}`).classList.add("active");
  const content = document.getElementById("content");
  content.innerHTML = "";
  hideTooltip();
  if (view === "board") renderBoard(state.projection, content);
  else if (view === "tree") renderTree(state.projection, content);
  else if (view === "flow") renderFlow(state.projection, state.events, content);
}

// ---------------------------------------------------------------------------
// View 1: Entity state board
// ---------------------------------------------------------------------------

function renderBoard(p, content) {
  const states = ["live", "dormant", "orphaned", "unknown", "closed"];
  for (const stateName of states) {
    const entries = Object.values(p.entities).filter(e => e.derived_state === stateName);
    if (!entries.length) continue;
    const sec = document.createElement("section");
    sec.className = "section";
    sec.innerHTML = `<h2>${stateName} (${entries.length})</h2>`;
    const grid = document.createElement("div");
    grid.className = "entity-grid";
    entries.sort((a, b) => a.entity_id.localeCompare(b.entity_id));
    for (const e of entries) grid.appendChild(card(e));
    sec.appendChild(grid);
    content.appendChild(sec);
  }
}

function card(e) {
  const div = document.createElement("div");
  div.className = "entity-card";
  const tierTag = renderTierTag(e);
  div.innerHTML = `
    <div class="entity-id">${escapeHtml(e.entity_id)}</div>
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
  if (a.plan_kind === "milestone") return `<span>· M${a.milestone_index ?? "?"}</span>`;
  if (a.tier !== undefined) {
    const prefix = a.tier_prefix || "";
    return `<span>· ${prefix}T${a.tier}</span>`;
  }
  return "";
}

// ---------------------------------------------------------------------------
// View 2: Plan hierarchy tree
// ---------------------------------------------------------------------------

function renderTree(p, content) {
  const plans = Object.values(p.entities).filter(e => e.entity_type === "plan");
  const children = {};
  for (const r of p.relationships.filter(r => r.type === "spawns")) {
    (children[r.from] ||= []).push(r.to);
  }
  const roots = plans.filter(e => {
    const a = e.attributes || {};
    if (a.plan_kind === "milestone") return true;
    if (a.tier === 1) return true;
    return false;
  });
  const sec = document.createElement("section");
  sec.className = "section";
  sec.innerHTML = "<h2>Plan hierarchy</h2>";
  const wrap = document.createElement("div");
  for (const root of roots.sort((a, b) => a.entity_id.localeCompare(b.entity_id))) {
    wrap.appendChild(treeNode(root, p, children));
  }
  sec.appendChild(wrap);
  content.appendChild(sec);
}

function treeNode(entity, p, children) {
  const div = document.createElement("div");
  div.className = "tree-node";
  const tierTag = renderTierTag(entity);
  div.innerHTML = `<span class="badge ${entity.derived_state}">${entity.derived_state}</span> <strong>${escapeHtml(entity.entity_id)}</strong> ${tierTag}`;
  const key = `plan:${entity.entity_id}`;
  const ch = (children[key] || []).map(k => p.entities[k]).filter(Boolean);
  if (ch.length) {
    const childWrap = document.createElement("div");
    childWrap.className = "tree-children";
    for (const c of ch.sort((a, b) => a.entity_id.localeCompare(b.entity_id))) {
      childWrap.appendChild(treeNode(c, p, children));
    }
    div.appendChild(childWrap);
  }
  return div;
}

// ---------------------------------------------------------------------------
// View 3: Workstreams flow
// ---------------------------------------------------------------------------

function renderFlow(projection, events, content) {
  const F = state.flowFilters;

  // Sub-mode toggle
  const sub = document.createElement("div");
  sub.className = "sub-toolbar";
  // Aggregate-by selector — groups ONLY the tier-3 leaf rows.
  sub.appendChild(document.createTextNode("aggregate:"));
  for (const [agg, label] of [
    ["milestone", "Milestones"],
    ["t2", "T2 Domains"],
    ["none", "None"],
  ]) {
    const b = document.createElement("button");
    b.textContent = label;
    if (agg === state.flowAggregate) b.classList.add("active");
    b.addEventListener("click", () => {
      if (state.flowAggregate !== agg) {
        state.flowAggregate = agg;
        // T3 band keys differ between axes — clear band-keyed filters.
        F.hiddenSwimlanes.clear();
        F.collapsedSwimlanes.clear();
        if (F.isolateRoot && F.isolateRoot.kind === "swimlane") F.isolateRoot = null;
      }
      switchView("flow");
    });
    sub.appendChild(b);
  }

  // Parent-band visibility toggles — show/hide a whole parent tier without
  // reflowing the T3 grouping.
  const parentToggles = document.createElement("span");
  parentToggles.className = "parent-toggles";
  for (const [field, label] of [
    ["flowShowMilestones", "Milestones"],
    ["flowShowDomains", "T2 Domains"],
  ]) {
    const b = document.createElement("button");
    b.textContent = (state[field] ? "☑ " : "☐ ") + label;
    b.title = `Show/hide the ${label} parent band`;
    if (state[field]) b.classList.add("active");
    b.addEventListener("click", () => { state[field] = !state[field]; switchView("flow"); });
    parentToggles.appendChild(b);
  }
  sub.appendChild(parentToggles);

  // Lifecycle filter (T3-flow-view-filtering D1): All / Open / Closed.
  const lcWrap = document.createElement("span");
  lcWrap.className = "lifecycle-filter";
  lcWrap.appendChild(document.createTextNode("show:"));
  for (const [val, label, title] of [
    ["all", "All", "Show every entity"],
    ["open", "Open", "Hide closed entities — keep live / dormant / orphaned"],
    ["closed", "Closed", "Show only closed entities"],
  ]) {
    const b = document.createElement("button");
    b.textContent = label;
    b.title = title;
    if (F.lifecycle === val) b.classList.add("active");
    b.addEventListener("click", () => { F.lifecycle = val; rerenderFlow(); });
    lcWrap.appendChild(b);
  }
  sub.appendChild(lcWrap);

  // Isolation banner + unisolate (T3-flow-view-filtering D2).
  if (F.isolateRoot) {
    const banner = document.createElement("span");
    banner.className = "isolate-banner";
    const what = F.isolateRoot.kind === "swimlane"
      ? bandLabel(F.isolateRoot.key)
      : (F.isolateRoot.key.split(":")[1] || F.isolateRoot.key);
    banner.appendChild(document.createTextNode(`Isolated: ${what} `));
    const clear = document.createElement("button");
    clear.className = "isolate-clear";
    clear.textContent = "✕ Unisolate";
    clear.title = "Clear isolation (Esc)";
    clear.addEventListener("click", () => { F.isolateRoot = null; rerenderFlow(); });
    banner.appendChild(clear);
    sub.appendChild(banner);
  }

  content.appendChild(sub);

  // Legend
  const legend = document.createElement("div");
  legend.className = "flow-legend";
  legend.innerHTML = `
    <strong>Legend:</strong>
    <span><svg width="14" height="14"><circle cx="7" cy="7" r="5" fill="#e91e63"/></svg> created</span>
    <span><svg width="14" height="14"><circle cx="7" cy="7" r="5" fill="#1565c0"/></svg> extended</span>
    <span><svg width="14" height="14"><circle cx="7" cy="7" r="5" fill="#ef6c00"/></svg> progressed</span>
    <span><svg width="14" height="14"><circle cx="7" cy="7" r="5" fill="#1b5e20"/></svg> completed</span>
    <span><svg width="14" height="14"><circle cx="7" cy="7" r="5" fill="#c62828"/></svg> fulcrum (parked/cancelled/etc.)</span>
    <span><svg width="14" height="14"><rect x="2.5" y="2.5" width="9" height="9" rx="1.5" fill="#6a1b9a"/></svg> primary summary</span>
    <span><svg width="14" height="14"><rect x="2.5" y="2.5" width="9" height="9" rx="1.5" fill="white" stroke="#6a1b9a" stroke-width="1.5"/></svg> derived summary</span>
    <span style="margin-left:1rem;color:#666;">solid line = entity spine · dashed = spawns · dotted = live continuation to "now" (click LIVE badge for timeline)</span>
  `;
  content.appendChild(legend);

  // Compute layout
  const layout = computeFlowLayout(projection, events, state.flowAggregate);

  // Two-pane split: SVG + drag handle + sidebar
  const split = document.createElement("div");
  split.className = "flow-split";

  const svgWrap = document.createElement("div");
  svgWrap.className = "flow-svg-wrap";

  // Task A: sticky HTML gutter overlaying the SVG's left margin. Contains
  // swimlane labels + per-entity labels as absolutely-positioned rows that
  // share y-coordinates with the SVG underneath. position:sticky;left:0
  // pins it during horizontal scroll. SVG keeps drawing swimlane bgs.
  const gutter = document.createElement("div");
  gutter.className = "flow-gutter";
  gutter.style.setProperty("--gutter-width", "220px");
  gutter.style.height = layout.totalHeight + "px";
  renderFlowGutter(layout, gutter);
  svgWrap.appendChild(gutter);

  svgWrap.appendChild(renderFlowSVG(layout));
  split.appendChild(svgWrap);

  // Wire the gutter resize handle.
  const gHandle = gutter.querySelector(".flow-gutter-drag-handle");
  if (gHandle) makeGutterResizable(gHandle, gutter);

  const handle = document.createElement("div");
  handle.className = "flow-drag-handle";
  handle.title = "Drag to resize the sidebar";
  split.appendChild(handle);

  const sidebar = document.createElement("aside");
  sidebar.id = "flow-sidebar";
  const detail = document.createElement("div");
  detail.id = "flow-detail";
  detail.innerHTML = "<p class='hint'>Hover a node for a tooltip. Click a node for event details, or click an entity name on the left for its full markdown content.</p>";
  sidebar.appendChild(detail);
  split.appendChild(sidebar);

  content.appendChild(split);

  makeResizable(handle, sidebar);
}

// --- Flow filter substrate (T3-flow-view-filtering D1/D2) -------------------

// Convenience: re-render the flow view after a filter mutation.
function rerenderFlow() { switchView("flow"); }

// Spawn adjacency over the unified relationship set (event + frontmatter edges).
function buildSpawnAdjacency(projection) {
  const parents = {};   // ekey -> Set(parent ekeys)
  const children = {};  // ekey -> Set(child ekeys)
  for (const r of (projection.relationships || [])) {
    if (r.type !== "spawns") continue;
    (children[r.from] ||= new Set()).add(r.to);
    (parents[r.to] ||= new Set()).add(r.from);
  }
  return { parents, children };
}

// For each superseding entity, the set of predecessors it replaces. Inverts the
// entity.superseded events: the event's own entity_id is the (closed) predecessor;
// each id in entity_ids is a superseder (live replacement). Used to scope the
// cascade-hide exemption: hiding a closed predecessor must not drag its live
// replacement into hiding — but only via the spawn edge it actually replaces,
// not wholesale (supersession is not itself a spawn edge).
function computeSupersededPredecessors(projection) {
  const byId = {};
  for (const [k, e] of Object.entries(projection.entities)) {
    if (!(e.entity_id in byId)) byId[e.entity_id] = k;
  }
  const out = new Map();  // superseder-key -> Set(predecessor-key)
  for (const ev of (state.events || [])) {
    if (ev.type !== "entity.superseded") continue;
    const predKey = byId[ev.entity_id];
    if (!predKey) continue;
    for (const id of (ev.attributes?.entity_ids || [])) {
      const supKey = byId[id];
      if (!supKey) continue;
      (out.get(supKey) || out.set(supKey, new Set()).get(supKey)).add(predKey);
    }
  }
  return out;
}

// root + all transitive ancestors (up the spawn graph) + all transitive
// descendants (down). Does NOT pull in siblings.
function relatedSetForEntity(ekey, adj) {
  const out = new Set([ekey]);
  const up = [ekey];
  while (up.length) {
    const k = up.pop();
    for (const p of (adj.parents[k] || [])) if (!out.has(p)) { out.add(p); up.push(p); }
  }
  const down = [ekey];
  while (down.length) {
    const k = down.pop();
    for (const c of (adj.children[k] || [])) if (!out.has(c)) { out.add(c); down.push(c); }
  }
  return out;
}

// Computes which entities get a row (laidOut), which of those have their SVG
// marks suppressed (eye-hide), and which swimlanes are collapsed. Pure.
function computeFlowVisibility(projection, filters, aggregate, show) {
  const entities = projection.entities;
  const allKeys = Object.keys(entities);
  const adj = buildSpawnAdjacency(projection);

  let candidate = new Set(allKeys);

  // 2. lifecycle filter — removes rows entirely.
  if (filters.lifecycle === "open") {
    candidate = new Set([...candidate].filter(k => entities[k].derived_state !== "closed"));
  } else if (filters.lifecycle === "closed") {
    candidate = new Set([...candidate].filter(k => entities[k].derived_state === "closed"));
  }

  // 2.5 parent-band visibility — hide a whole parent tier (its rows + arcs)
  // without touching the T3 grouping. Removed from `candidate` entirely (no
  // greyed row), so toggling never reflows the aggregated T3 bands.
  // Key off bandKey so these stay consistent with banding (e.g. a leaf
  // mis-tagged tier:2 is NOT removed when domains are hidden).
  if (show && !show.milestones) {
    candidate = new Set([...candidate].filter(k => bandKey(entities[k], aggregate) !== "_milestones"));
  }
  if (show && !show.domains) {
    candidate = new Set([...candidate].filter(k => bandKey(entities[k], aggregate) !== "_t2domains"));
  }

  // 3. isolation — removes rows entirely (intersection with related set).
  if (filters.isolateRoot) {
    let related;
    if (filters.isolateRoot.kind === "entity") {
      related = relatedSetForEntity(filters.isolateRoot.key, adj);
    } else {
      related = new Set();
      for (const k of allKeys) {
        if (bandKey(entities[k], aggregate) === filters.isolateRoot.key) {
          for (const r of relatedSetForEntity(k, adj)) related.add(r);
        }
      }
    }
    candidate = new Set([...candidate].filter(k => related.has(k)));
  }

  const laidOut = candidate;

  // 4. eye-hide — stays laid out, marks suppressed, greyed row retained.
  // Hiding an entity cascades to its spawned descendants that have no surviving
  // parent (every spawn-parent is also hidden). A node that supersedes one of
  // its own spawn-parents drops only that superseded parent from the test —
  // hiding a closed predecessor must not hide its live replacement — but the node
  // still cascade-hides when its remaining (real) spawn-parents are all hidden.
  const supPreds = computeSupersededPredecessors(projection);
  const closure = new Set(filters.hiddenEntities);
  let changed = true;
  while (changed) {
    changed = false;
    for (const k of allKeys) {
      if (closure.has(k)) continue;
      const ps = adj.parents[k];
      if (!ps || ps.size === 0) continue;
      const sup = supPreds.get(k);
      const eff = sup ? [...ps].filter(p => !sup.has(p)) : [...ps];
      if (eff.length > 0 && eff.every(p => closure.has(p))) {
        closure.add(k);
        changed = true;
      }
    }
  }

  const suppressed = new Set();
  for (const k of laidOut) {
    if (closure.has(k) ||
        filters.hiddenSwimlanes.has(bandKey(entities[k], aggregate))) {
      suppressed.add(k);
    }
  }

  // 5. collapse — keep only collapsed swimlanes that still have >=1 laid-out member.
  const collapsed = new Set();
  for (const k of laidOut) {
    const sl = bandKey(entities[k], aggregate);
    if (filters.collapsedSwimlanes.has(sl)) collapsed.add(sl);
  }

  return { laidOut, suppressed, collapsed, adj };
}

function computeFlowLayout(projection, events, aggregate) {
  // LEFT_MARGIN now small — the sticky HTML gutter (Task A) holds entity +
  // swimlane labels, so the SVG no longer needs to reserve space for them.
  // TOP_MARGIN larger to give vertical commit labels (Task B, rotate -90)
  // room to breathe.
  const LEFT_MARGIN = 16;
  const TOP_MARGIN = 170;
  // Commit columns shrunk dramatically (Task B). Vertical labels need only
  // ~font-height of horizontal space per column; previous 150 was to fit
  // a -28° rotated label's wedge.
  const COMMIT_WIDTH = 44;
  const NOW_COLUMN_WIDTH = 110;
  const ROW_HEIGHT = 22;
  const SWIMLANE_PADDING = 18;
  const NODE_RADIUS = 6;

  // 1. Extract commits in order from commit.recorded events.
  const commits = [];
  const commitMap = {}; // event_id -> {idx, id, message, ...}
  for (const ev of events) {
    if (ev.type === "commit.recorded") {
      const c = {
        id: ev.event_id,
        idx: commits.length,
        author: ev.attributes.author,
        date: ev.attributes.date,
        message: ev.attributes.message_first_line,
      };
      commits.push(c);
      commitMap[ev.event_id] = c;
    }
  }

  // 2. Assign each non-commit.recorded event to its bracketing commit
  //    by walking forward through events.jsonl and tracking the next commit.recorded.
  const eventToCommit = new Map(); // event_id -> commit.recorded event_id
  let buffer = [];
  for (const ev of events) {
    if (ev.type === "commit.recorded") {
      for (const b of buffer) eventToCommit.set(b.event_id, ev.event_id);
      buffer = [];
    } else {
      buffer.push(ev);
    }
  }
  // Trailing buffer (in-progress, no closing commit.recorded): no assignment.

  // 2.5. Visibility (T3-flow-view-filtering): which entities get rows, which
  // are mark-suppressed (eye-hide), which swimlanes are collapsed.
  const vis = computeFlowVisibility(projection, state.flowFilters, aggregate,
    { milestones: state.flowShowMilestones, domains: state.flowShowDomains });
  const isCollapsedSwimlane = (sl) => vis.collapsed.has(sl);
  // entity key -> collapsed swimlane key it belongs to (for edge rerouting).
  const memberCollapsedSwimlane = {};

  // 3. Group events by entity (excluding meta / non-entity events).
  //    Analysis events are also excluded — they get their own node kind
  //    (summary nodes) rendered separately (Phase C — T2-analyser §3.10).
  const entityEvents = {};
  for (const ev of events) {
    if (!ev.entity_id || !ev.entity_type) continue;
    if (ev.type === "analysis.live-summary" || ev.type === "analysis.invalidated") continue;
    const key = `${ev.entity_type}:${ev.entity_id}`;
    (entityEvents[key] ||= []).push(ev);
  }

  // 4. Assign entities to swimlanes.
  const entities = projection.entities;
  const swimlaneEntities = {};
  const swimlaneOrder = [];

  const collapsedMembers = {}; // sl -> [ekey] laid-out members of a collapsed swimlane
  for (const [ekey, entity] of Object.entries(entities)) {
    if (!vis.laidOut.has(ekey)) continue;
    const sl = bandKey(entity, aggregate);
    if (!swimlaneEntities[sl]) {
      swimlaneEntities[sl] = [];
      swimlaneOrder.push(sl);
    }
    if (isCollapsedSwimlane(sl)) {
      (collapsedMembers[sl] ||= []).push(ekey);
      memberCollapsedSwimlane[ekey] = sl;  // no individual row for collapsed members
    } else {
      swimlaneEntities[sl].push(ekey);
    }
  }

  // Sort bands: parent bands first (fixed order), then the aggregated T3 bands
  // (numeric so M1 < M1.1 < M1.2 < M2, and T2-* alpha), then the catch-alls,
  // with inbox always last.
  const HEAD = ["_t1", "_milestones", "_t2domains"];
  const TAIL = { "_unassigned": 1, "_other": 2, "_inbox": 3 };
  const rank = (k) => {
    const h = HEAD.indexOf(k);
    if (h !== -1) return [0, h];
    if (TAIL[k] !== undefined) return [2, TAIL[k]];
    return [1, 0]; // an aggregated T3 band (milestone id / t2 id / _t3flat)
  };
  swimlaneOrder.sort((a, b) => {
    const ra = rank(a), rb = rank(b);
    if (ra[0] !== rb[0]) return ra[0] - rb[0];
    if (ra[0] !== 1) return ra[1] - rb[1];                    // HEAD / TAIL: fixed order
    return a.localeCompare(b, undefined, { numeric: true });  // T3 bands: numeric
  });

  // 5. Within each swimlane, sort entities by index-of-first-event.
  for (const sl of swimlaneOrder) {
    swimlaneEntities[sl].sort((a, b) => {
      const aFirst = events.indexOf((entityEvents[a] || [])[0]);
      const bFirst = events.indexOf((entityEvents[b] || [])[0]);
      const ax = aFirst === -1 ? Infinity : aFirst;
      const bx = bFirst === -1 ? Infinity : bFirst;
      return ax - bx;
    });
  }

  // 6. Y-position each entity (or one placeholder row per collapsed swimlane)
  //    and compute swimlane spans.
  const entityRow = {}; // entity_key -> y
  const placeholderRowY = {}; // collapsed sl -> y
  const swimlaneSpans = [];
  let y = TOP_MARGIN;
  for (const sl of swimlaneOrder) {
    const slTop = y;
    y += 30; // top-band for swimlane label, then entities below
    const collapsed = isCollapsedSwimlane(sl);
    const ents = swimlaneEntities[sl];
    if (collapsed) {
      placeholderRowY[sl] = y + ROW_HEIGHT / 2;
      y += ROW_HEIGHT;
    } else {
      for (const ek of ents) {
        entityRow[ek] = y + ROW_HEIGHT / 2;
        y += ROW_HEIGHT;
      }
    }
    y += SWIMLANE_PADDING;
    swimlaneSpans.push({
      key: sl,
      label: bandLabel(sl),
      top: slTop,
      bottom: y - SWIMLANE_PADDING / 2,
      entities: ents,
      collapsed,
      placeholderY: collapsed ? placeholderRowY[sl] : undefined,
      memberCount: collapsed ? (collapsedMembers[sl] || []).length : ents.length,
    });
  }
  const totalHeight = y + 20;
  const nowX = LEFT_MARGIN + commits.length * COMMIT_WIDTH + NOW_COLUMN_WIDTH / 2;
  const totalWidth = LEFT_MARGIN + commits.length * COMMIT_WIDTH + NOW_COLUMN_WIDTH;

  // 7. Compute composite nodes: one per (entity, commit) intersection.
  const nodes = [];
  const entityNodes = {};
  for (const [ekey, evs] of Object.entries(entityEvents)) {
    if (vis.suppressed.has(ekey)) continue;        // eye-hidden: keep row, draw no marks
    if (entityRow[ekey] === undefined) continue;   // not laid out / collapsed member
    const byCommit = {};
    for (const ev of evs) {
      const cId = eventToCommit.get(ev.event_id);
      if (!cId) continue;
      (byCommit[cId] ||= []).push(ev);
    }
    for (const [cId, eventList] of Object.entries(byCommit)) {
      const c = commitMap[cId];
      if (!c) continue;
      const x = LEFT_MARGIN + c.idx * COMMIT_WIDTH + COMMIT_WIDTH / 2;
      const yCoord = entityRow[ekey];
      const node = {
        x, y: yCoord,
        eventCount: eventList.length,
        color: dominantEventColor(eventList),
        events: eventList,
        entityKey: ekey,
        entity: entities[ekey],
        commitId: cId,
        commitMessage: c.message,
        commitDate: c.date,
        commitIdx: c.idx,
      };
      nodes.push(node);
      (entityNodes[ekey] ||= []).push(node);
    }
  }
  for (const ek of Object.keys(entityNodes)) {
    entityNodes[ek].sort((a, b) => a.x - b.x);
  }

  // 7.1. Placeholder nodes for collapsed swimlanes (T3-flow-view-filtering D4).
  // One node per collapsed swimlane, at the x of the earliest member event's
  // commit column. Spawn edges into members reroute here.
  const placeholderNodes = {}; // sl -> { x, y, sl, members:[ekey], memberCount }
  for (const sl of Object.keys(collapsedMembers)) {
    if (placeholderRowY[sl] === undefined) continue;
    const members = collapsedMembers[sl];
    let minIdx = Infinity;
    for (const ek of members) {
      for (const ev of (entityEvents[ek] || [])) {
        const cId = eventToCommit.get(ev.event_id);
        const c = cId && commitMap[cId];
        if (c && c.idx < minIdx) minIdx = c.idx;
      }
    }
    const x = (minIdx === Infinity)
      ? LEFT_MARGIN + COMMIT_WIDTH / 2
      : LEFT_MARGIN + minIdx * COMMIT_WIDTH + COMMIT_WIDTH / 2;
    placeholderNodes[sl] = { x, y: placeholderRowY[sl], sl, members, memberCount: members.length };
  }

  // Maps an entity key to the node a spawn edge should attach to: its own
  // first/last node, or its collapsed swimlane's placeholder. null if the
  // entity has no drawable endpoint (suppressed or filtered out).
  const endpointNode = (ekey, which) => {
    // Hidden (eye-hide, or hidden section) wins over collapse: a hidden entity
    // is not a drawable arc endpoint even when its band is collapsed. Without
    // this, arcs into a collapsed+hidden band still aggregate to the placeholder
    // — the reported bug (collapsed+hidden must show no arcs, like open+hidden).
    if (vis.suppressed.has(ekey)) return null;
    const sl = memberCollapsedSwimlane[ekey];
    if (sl && placeholderNodes[sl]) return placeholderNodes[sl];
    const ns = entityNodes[ekey];
    if (ns && ns.length) return which === "last" ? ns[ns.length - 1] : ns[0];
    return null;
  };

  // 7.5. Summary nodes (Phase C — T2-analyser §3.10).
  // One node per analysis.live-summary event, placed on the entity's lifeline
  // at the x-coordinate of its bracketing commit column. Rendered separately
  // from event composite nodes to give them distinct visual treatment.
  const summaryNodes = [];
  const projectionSummaries = projection.summaries || {};
  for (const ev of events) {
    if (ev.type !== "analysis.live-summary") continue;
    const ekey = `${ev.entity_type}:${ev.entity_id}`;
    if (vis.suppressed.has(ekey)) continue;  // eye-hidden: no summary mark either
    const yCoord = entityRow[ekey];
    if (yCoord === undefined) continue;  // entity has no lifeline (collapsed / filtered)
    const cId = eventToCommit.get(ev.event_id);
    let x;
    if (cId) {
      const c = commitMap[cId];
      if (!c) continue;
      x = LEFT_MARGIN + c.idx * COMMIT_WIDTH + COMMIT_WIDTH / 2;
    } else {
      // No bracketing commit — render in the now column. Defensive; clean-tree
      // guard should prevent this in practice.
      x = nowX;
    }
    const meta = projectionSummaries[ev.event_id] || {};
    summaryNodes.push({
      x, y: yCoord,
      event_id: ev.event_id,
      entityKey: ekey,
      entity: entities[ekey],
      source: ev.attributes?.source || meta.source || "primary",
      model: ev.attributes?.model || meta.model || "?",
      valid: meta.valid !== false,  // default true if projection not yet rebuilt
      invalidated_by_event_id: meta.invalidated_by_event_id || null,
      origin_summary_event_id: ev.attributes?.origin_summary_event_id || meta.origin_summary_event_id || null,
      freeform_path: ev.attributes?.freeform_path || meta.freeform_path || "",
    });
  }

  // 8. Relationship edges (spawns), with collapsed-swimlane rerouting.
  const relEdges = [];
  for (const r of (projection.relationships || []).filter(r => r.type === "spawns")) {
    const from = endpointNode(r.from, "first");
    const to = endpointNode(r.to, "first");
    if (!from || !to) continue;   // an endpoint is hidden/filtered -> drop the edge
    if (from === to) continue;    // both ends inside one collapsed swimlane -> drop
    relEdges.push({ from, to });
  }

  // 9. Continuation lines + "now" badges for live/dormant/orphaned entities.
  const continuations = [];
  const nowBadges = [];
  for (const [ekey, entity] of Object.entries(entities)) {
    if (!["live", "dormant", "orphaned"].includes(entity.derived_state)) continue;
    const ns = entityNodes[ekey];
    if (!ns || !ns.length) continue;
    const last = ns[ns.length - 1];
    continuations.push({ fromNode: last, x2: nowX - 22, y: last.y });
    nowBadges.push({
      x: nowX,
      y: last.y,
      state: entity.derived_state,
      entityId: entity.entity_id,
    });
  }

  return {
    nodes, entityNodes, relEdges, continuations, nowBadges, summaryNodes,
    swimlaneSpans, commits, commitMap, entityRow, eventToCommit,
    suppressed: vis.suppressed, placeholderNodes, memberCollapsedSwimlane,
    LEFT_MARGIN, TOP_MARGIN, COMMIT_WIDTH, NOW_COLUMN_WIDTH, ROW_HEIGHT, NODE_RADIUS,
    nowX, totalWidth, totalHeight,
  };
}

// Which band an entity belongs to. Parent entities (T1 / milestones / T2s) get
// fixed structural bands, independent of the aggregation axis. Only tier-3 leaf
// work is grouped by the chosen `aggregate` axis (its fold-reconciled
// attributes.milestone / .t2_parent). This is what lets parent visibility and
// T3 aggregation be toggled independently.
function bandKey(entity, aggregate) {
  const a = entity.attributes || {};
  if (entity.entity_type === "inbox-item") return "_inbox";
  if (a.plan_kind === "milestone") return "_milestones";
  // A leaf (tier-3 work) is identified by having a `t2_parent` (it points up to
  // a T2) OR an explicit tier 3 — checked BEFORE the tier===2 bucket so a plan
  // mis-tagged tier:2 in its frozen entity.created attrs (e.g. T3-plugin-scaffold)
  // still groups as a leaf, not as a T2 domain. Leaves group by the aggregate axis.
  if (a.t2_parent || a.tier === 3) {
    if (aggregate === "milestone") return a.milestone || "_unassigned";
    if (aggregate === "t2") return a.t2_parent || "_unassigned";
    return "_t3flat"; // aggregate === "none"
  }
  if (a.tier === 2) return "_t2domains"; // a real T2 domain (no t2_parent)
  if (a.tier === 1) return "_t1";
  return "_other";
}

function bandLabel(key) {
  const labels = {
    "_t1": "T1 (root)",
    "_milestones": "Milestones",
    "_t2domains": "T2 Domains",
    "_t3flat": "Tier-3 work",
    "_unassigned": "— unassigned —",
    "_other": "Other",
    "_inbox": "Inbox items",
  };
  return labels[key] || key;
}

function dominantEventColor(eventList) {
  const types = new Set(eventList.map(e => e.type));
  // Fulcrum events first (most destructive / decision-needing).
  if (types.has("entity.cancelled")) return "#c62828";
  if (types.has("entity.superseded")) return "#ad1457";
  if (types.has("entity.parked")) return "#f9a825";
  if (types.has("entity.reopened")) return "#8e24aa";
  if (types.has("entity.renamed")) return "#6a1b9a";
  // Completion (the only green — unambiguous "done" signal).
  if (types.has("entity.completed")) return "#1b5e20";
  if (types.has("verification.failed")) return "#d32f2f";
  // Birth (pink/magenta — distinct from any green).
  if (types.has("entity.created")) return "#e91e63";
  if (types.has("entity.progressed")) return "#ef6c00";
  if (types.has("entity.extended")) return "#1565c0";
  if (types.has("blocker.raised")) return "#d32f2f";
  if (types.has("blocker.closed")) return "#43a047";
  if (types.has("verification.tested")) return "#00897b";
  if (types.has("relationship.spawns")) return "#7e57c2";
  return "#9e9e9e";
}

// Maps an event type to a CSS class suffix for pill styling.
function eventTypeKind(type) {
  if (type === "decision") return "decision";
  if (type === "commit.recorded") return "meta";
  if (type.startsWith("blocker.")) return "blocker";
  if (type.startsWith("verification.")) return "verification";
  if (type.startsWith("relationship.")) return "relationship";
  // entity.* lifecycle
  if (["entity.cancelled", "entity.superseded", "entity.parked", "entity.reopened", "entity.renamed"].includes(type)) return "fulcrum";
  if (type === "entity.completed") return "completed";
  if (type === "entity.created") return "created";
  if (type === "entity.extended") return "extended";
  if (type === "entity.progressed") return "progressed";
  return "other";
}

function renderFlowSVG(layout) {
  const NS = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("class", "flow-svg");
  svg.setAttribute("viewBox", `0 0 ${layout.totalWidth} ${layout.totalHeight}`);
  svg.setAttribute("width", layout.totalWidth);
  svg.setAttribute("height", layout.totalHeight);

  // Swimlane backgrounds. (Labels moved to the sticky HTML gutter — Task A.)
  // SVG still draws full-width banded rects underneath the gutter so banding
  // remains visible in the right-hand commit area where the gutter doesn't reach.
  const swG = createNS("g", { class: "swimlanes" });
  layout.swimlaneSpans.forEach((sl, i) => {
    swG.appendChild(createNS("rect", {
      class: `swimlane-band ${i % 2 === 0 ? "even" : "odd"}`,
      x: 0, y: sl.top,
      width: layout.totalWidth,
      height: sl.bottom - sl.top,
    }));
  });
  svg.appendChild(swG);

  // Commit column guides + VERTICAL labels at top (Task B).
  // Labels rotate -90° (bottom-to-top) so columns can shrink to ~44px wide.
  // Each commit gets a transparent hit-rect overlay so hover+click are easy
  // to target (the rotated text itself would be a slim hit target).
  const colG = createNS("g", { class: "columns" });
  for (const c of layout.commits) {
    const x = layout.LEFT_MARGIN + c.idx * layout.COMMIT_WIDTH + layout.COMMIT_WIDTH / 2;
    colG.appendChild(createNS("line", {
      class: "commit-column",
      x1: x, y1: layout.TOP_MARGIN - 5,
      x2: x, y2: layout.totalHeight - 10,
    }));
    // Vertical label group anchored at the bottom of the label band, rotated
    // -90° so text reads upward. text-anchor:end on the underlying tspan
    // keeps the truncated string flush against the column.
    const labelY = layout.TOP_MARGIN - 8;
    const g = createNS("g", {
      transform: `translate(${x},${labelY}) rotate(-90)`,
    });
    const truncated = c.message.length > 32 ? c.message.slice(0, 30) + "…" : c.message;
    const textEl = textNS({
      class: "commit-label commit-label-vertical",
      x: 0, y: 4,
      "text-anchor": "start",
    }, truncated);
    g.appendChild(textEl);
    colG.appendChild(g);

    // Transparent hit-rect covering the label column area for hover/click.
    // Sits in unrotated space; spans from top of svg down to the swimlanes.
    const hit = createNS("rect", {
      class: "commit-hit",
      x: x - layout.COMMIT_WIDTH / 2 + 1,
      y: 2,
      width: layout.COMMIT_WIDTH - 2,
      height: layout.TOP_MARGIN - 4,
      fill: "transparent",
      style: "cursor: pointer;",
    });
    const titleEl = createNS("title");
    titleEl.textContent = `${c.message}\n${c.date}`;
    hit.appendChild(titleEl);
    hit.addEventListener("mouseenter", (e) => showCommitTooltip(e, c));
    hit.addEventListener("mousemove", (e) => moveTooltip(e));
    hit.addEventListener("mouseleave", hideTooltip);
    hit.addEventListener("click", () => showCommitDetail(c, layout));
    colG.appendChild(hit);
  }
  // "Now" guide
  colG.appendChild(createNS("line", {
    class: "now-column",
    x1: layout.nowX, y1: layout.TOP_MARGIN - 5,
    x2: layout.nowX, y2: layout.totalHeight - 10,
  }));
  colG.appendChild(textNS({
    class: "now-label",
    x: layout.nowX, y: layout.TOP_MARGIN - 24,
    "text-anchor": "middle",
  }, "now"));
  svg.appendChild(colG);

  // Edges
  const edgeG = createNS("g", { class: "edges" });

  // Entity spines (solid, one path per entity connecting its nodes)
  for (const ek of Object.keys(layout.entityNodes)) {
    const ns = layout.entityNodes[ek];
    if (ns.length < 2) continue;
    edgeG.appendChild(createNS("path", {
      class: "entity-spine",
      d: "M " + ns.map(n => `${n.x} ${n.y}`).join(" L "),
    }));
  }

  // Relationship edges (dashed bezier)
  for (const r of layout.relEdges) {
    const dx = (r.to.x - r.from.x) / 2;
    edgeG.appendChild(createNS("path", {
      class: "rel-edge",
      d: `M ${r.from.x} ${r.from.y} C ${r.from.x + dx} ${r.from.y}, ${r.to.x - dx} ${r.to.y}, ${r.to.x} ${r.to.y}`,
    }));
  }

  // Continuation lines (dotted to now column)
  for (const c of layout.continuations) {
    edgeG.appendChild(createNS("line", {
      class: "continuation",
      x1: c.fromNode.x, y1: c.fromNode.y,
      x2: c.x2, y2: c.y,
    }));
  }

  svg.appendChild(edgeG);

  // Nodes
  const nodeG = createNS("g", { class: "nodes" });
  for (const n of layout.nodes) {
    const r = Math.min(11, layout.NODE_RADIUS + Math.log2(n.eventCount + 1) * 1.6);
    const circle = createNS("circle", {
      class: "node",
      cx: n.x, cy: n.y, r,
      fill: n.color,
    });
    circle.addEventListener("mouseenter", (e) => showTooltip(e, n));
    circle.addEventListener("mousemove", (e) => moveTooltip(e));
    circle.addEventListener("mouseleave", hideTooltip);
    circle.addEventListener("click", () => showDetail(n));
    nodeG.appendChild(circle);
    if (n.eventCount > 1) {
      nodeG.appendChild(textNS({
        class: "node-count",
        x: n.x, y: n.y + 3,
        "text-anchor": "middle",
      }, n.eventCount));
    }
  }
  svg.appendChild(nodeG);

  // "Now" badges on the right — click to see entity's recent timeline.
  const nowG = createNS("g", { class: "now-badges" });
  for (const b of layout.nowBadges) {
    const entityKey = `plan:${b.entityId}`;
    // Resolve entity from projection; fall back to scanning all entities for non-plan types.
    let entity = state.projection.entities[entityKey];
    if (!entity) {
      entity = Object.values(state.projection.entities).find(e => e.entity_id === b.entityId);
    }
    const rect = createNS("rect", {
      class: `now-badge ${b.state}`,
      x: layout.nowX - 20, y: b.y - 7,
      width: 40, height: 14, rx: 3,
    });
    const text = textNS({
      class: "now-badge-text",
      x: layout.nowX, y: b.y + 4,
      "text-anchor": "middle",
    }, b.state.toUpperCase().slice(0, 4));
    // SVG <title> for hover hint
    const titleEl = createNS("title");
    titleEl.textContent = `${b.entityId} (${b.state}) — click for recent timeline`;
    rect.appendChild(titleEl);
    if (entity) {
      const handler = () => showLiveStatus(entity);
      rect.addEventListener("click", handler);
      text.addEventListener("click", handler);
    }
    nowG.appendChild(rect);
    nowG.appendChild(text);
  }
  svg.appendChild(nowG);

  // Summary nodes (Phase C). Squares on entity lifelines, distinct from event
  // composite circles. Filled purple for primary; outlined purple for derived.
  // Invalidated summaries are dimmed + struck through (Phase D produces the
  // invalidation events; Phase C just renders them when present).
  const SUMMARY_SIDE = 9;
  const sumG = createNS("g", { class: "summary-nodes" });
  for (const s of layout.summaryNodes || []) {
    const classes = ["summary-node", `summary-node-${s.source}`];
    if (!s.valid) classes.push("summary-node-invalidated");
    const rect = createNS("rect", {
      class: classes.join(" "),
      x: s.x - SUMMARY_SIDE / 2, y: s.y - SUMMARY_SIDE / 2,
      width: SUMMARY_SIDE, height: SUMMARY_SIDE,
      rx: 1.5,
    });
    const titleEl = createNS("title");
    const tagText = s.source === "primary" ? "primary" : "derived";
    const validText = s.valid ? "" : " · INVALIDATED";
    titleEl.textContent = `Summary · ${tagText}${validText} · ${s.model} · click to open`;
    rect.appendChild(titleEl);
    rect.addEventListener("click", () => {
      if (!s.entity) return;
      const panel = document.getElementById("flow-detail");
      if (!panel) return;
      SavedSummary.renderByEventId(panel, s.entity, s.event_id);
    });
    sumG.appendChild(rect);
    // Strike-through line for invalidated summaries.
    if (!s.valid) {
      sumG.appendChild(createNS("line", {
        class: "summary-strike",
        x1: s.x - SUMMARY_SIDE / 2 - 1,
        x2: s.x + SUMMARY_SIDE / 2 + 1,
        y1: s.y, y2: s.y,
      }));
    }
  }
  svg.appendChild(sumG);

  // Placeholder nodes for collapsed swimlanes (T3-flow-view-filtering D4).
  // A hollow rounded rect with a count; spawn edges reroute to it. Click to expand.
  const phG = createNS("g", { class: "placeholder-nodes" });
  for (const sl of Object.keys(layout.placeholderNodes || {})) {
    const p = layout.placeholderNodes[sl];
    const W = 30, H = 16;
    const rect = createNS("rect", {
      class: "placeholder-node",
      x: p.x - W / 2, y: p.y - H / 2, width: W, height: H, rx: 3,
    });
    const titleEl = createNS("title");
    titleEl.textContent =
      `${bandLabel(sl)} — ${p.memberCount} entit${p.memberCount === 1 ? "y" : "ies"} collapsed\n` +
      p.members.map(k => "• " + k).join("\n") + "\n(click to expand)";
    rect.appendChild(titleEl);
    const expand = () => { state.flowFilters.collapsedSwimlanes.delete(sl); rerenderFlow(); };
    rect.addEventListener("click", expand);
    phG.appendChild(rect);
    const label = textNS({
      class: "placeholder-node-count",
      x: p.x, y: p.y + 4, "text-anchor": "middle",
    }, "▸ " + p.memberCount);
    label.addEventListener("click", expand);
    phG.appendChild(label);
  }
  svg.appendChild(phG);

  return svg;
}

// ---------------------------------------------------------------------------
// Flow gutter (Task A — sticky entity-name column)
// ---------------------------------------------------------------------------
//
// The gutter is a position:sticky HTML overlay that lives inside the
// horizontally-scrolling .flow-svg-wrap. It renders swimlane labels and
// per-entity labels at the same y-coordinates as the SVG underneath, so
// when the user scrolls horizontally the labels stay pinned at the left
// edge while the SVG's commit columns scroll past.

function renderFlowGutter(layout, gutter) {
  const F = state.flowFilters;

  // Drag handle on right edge.
  const handle = document.createElement("div");
  handle.className = "flow-gutter-drag-handle";
  handle.title = "Drag to resize the entity-name column";
  gutter.appendChild(handle);

  // Small clickable control glyph (isolate / eye / caret). stopPropagation so
  // a control click never triggers the row's open-markdown handler.
  const ctrl = (cls, glyph, title, onClick) => {
    const s = document.createElement("span");
    s.className = "gctrl " + cls;
    s.textContent = glyph;
    s.title = title;
    s.addEventListener("click", (e) => { e.stopPropagation(); onClick(); });
    return s;
  };

  // Swimlane headers — isolate / eye / collapse controls + label.
  for (const sl of layout.swimlaneSpans) {
    const div = document.createElement("div");
    div.className = "flow-gutter-swimlane";
    div.style.top = (sl.top + 4) + "px";

    const slIsIsolatedRoot = F.isolateRoot && F.isolateRoot.kind === "swimlane" && F.isolateRoot.key === sl.key;
    const ctrls = document.createElement("span");
    ctrls.className = "gctrls";
    if (slIsIsolatedRoot) {
      ctrls.appendChild(ctrl("gctrl-deisolate", "⊗", "Exit isolation (show everything again)",
        () => { F.isolateRoot = null; rerenderFlow(); }));
    } else {
      ctrls.appendChild(ctrl("gctrl-isolate", "⌖",
        `Isolate "${sl.label}" + everything it links to`,
        () => { F.isolateRoot = { kind: "swimlane", key: sl.key }; rerenderFlow(); }));
    }
    const slHidden = F.hiddenSwimlanes.has(sl.key);
    ctrls.appendChild(ctrl("gctrl-eye" + (slHidden ? " is-off" : ""), slHidden ? "◌" : "◉",
      slHidden ? "Show this section's nodes" : "Hide this section's nodes",
      () => { slHidden ? F.hiddenSwimlanes.delete(sl.key) : F.hiddenSwimlanes.add(sl.key); rerenderFlow(); }));
    ctrls.appendChild(ctrl("gctrl-caret", sl.collapsed ? "▸" : "▾",
      sl.collapsed ? "Expand this section" : "Collapse this section to a placeholder",
      () => { sl.collapsed ? F.collapsedSwimlanes.delete(sl.key) : F.collapsedSwimlanes.add(sl.key); rerenderFlow(); }));
    div.appendChild(ctrls);

    const label = document.createElement("span");
    label.className = "gsl-label" + (slIsIsolatedRoot ? " is-isolated-root" : "");
    label.textContent = sl.collapsed ? `${sl.label} (${sl.memberCount})` : sl.label;
    div.appendChild(label);
    gutter.appendChild(div);

    // Collapsed: one muted placeholder row in place of member rows.
    if (sl.collapsed && sl.placeholderY !== undefined) {
      const prow = document.createElement("div");
      prow.className = "flow-gutter-row flow-gutter-placeholder";
      prow.style.top = (sl.placeholderY - 9) + "px";
      prow.textContent = `▸ ${sl.memberCount} collapsed`;
      prow.title = "Click to expand this section";
      prow.addEventListener("click", () => { F.collapsedSwimlanes.delete(sl.key); rerenderFlow(); });
      gutter.appendChild(prow);
    }
  }

  // Per-entity rows (non-collapsed swimlanes only).
  for (const sl of layout.swimlaneSpans) {
    if (sl.collapsed) continue;
    for (const ek of sl.entities) {
      const yMid = (layout.entityRow && layout.entityRow[ek] !== undefined)
        ? layout.entityRow[ek]
        : layout.entityNodes[ek]?.[0]?.y;
      if (yMid === undefined) continue;
      const entity = state.projection.entities[ek];
      if (!entity) continue;
      const suppressed = layout.suppressed && layout.suppressed.has(ek);
      const row = document.createElement("div");
      row.className = "flow-gutter-row" + (suppressed ? " is-suppressed" : "");
      row.style.top = (yMid - 9) + "px";  // center on the lifeline (height=18)

      const isIsolatedRoot = F.isolateRoot && F.isolateRoot.kind === "entity" && F.isolateRoot.key === ek;
      const ctrls = document.createElement("span");
      ctrls.className = "gctrls";
      if (isIsolatedRoot) {
        // This row IS the current focus — offer the inverse (exit focus).
        ctrls.appendChild(ctrl("gctrl-deisolate", "⊗", "Exit isolation (show everything again)",
          () => { F.isolateRoot = null; rerenderFlow(); }));
      } else {
        ctrls.appendChild(ctrl("gctrl-isolate", "⌖", "Isolate to this entity + its parents/children",
          () => { F.isolateRoot = { kind: "entity", key: ek }; rerenderFlow(); }));
      }
      ctrls.appendChild(ctrl("gctrl-eye" + (suppressed ? " is-off" : ""), suppressed ? "◌" : "◉",
        suppressed ? "Show this entity's nodes" : "Hide this entity's nodes",
        () => { F.hiddenEntities.has(ek) ? F.hiddenEntities.delete(ek) : F.hiddenEntities.add(ek); rerenderFlow(); }));
      row.appendChild(ctrls);

      const name = document.createElement("span");
      name.className = "grow-label" + (isIsolatedRoot ? " is-isolated-root" : "");
      name.textContent = entity.entity_id;
      row.appendChild(name);

      row.title = entity.entity_id + " (click to open)";
      row.addEventListener("click", () => showPlanMarkdown(entity));
      gutter.appendChild(row);
    }
  }
}

function makeGutterResizable(handle, gutter) {
  let dragging = false;
  let startX = 0;
  let startWidth = 220;
  handle.addEventListener("mousedown", (e) => {
    dragging = true;
    startX = e.clientX;
    const cur = parseInt(getComputedStyle(gutter).getPropertyValue("width"), 10);
    startWidth = isNaN(cur) ? 220 : cur;
    handle.classList.add("dragging");
    document.body.style.cursor = "ew-resize";
    document.body.style.userSelect = "none";
    e.preventDefault();
    e.stopPropagation();
  });
  document.addEventListener("mousemove", (e) => {
    if (!dragging) return;
    const delta = e.clientX - startX;
    const newWidth = Math.min(360, Math.max(80, startWidth + delta));
    gutter.style.setProperty("--gutter-width", newWidth + "px");
  });
  document.addEventListener("mouseup", () => {
    if (dragging) {
      dragging = false;
      handle.classList.remove("dragging");
      document.body.style.cursor = "";
      document.body.style.userSelect = "";
    }
  });
}

// ---------------------------------------------------------------------------
// Tooltip + detail
// ---------------------------------------------------------------------------

let tooltipEl = null;

function getTooltip() {
  if (tooltipEl) return tooltipEl;
  tooltipEl = document.createElement("div");
  tooltipEl.id = "flow-tooltip";
  document.body.appendChild(tooltipEl);
  return tooltipEl;
}

function showTooltip(e, n) {
  const t = getTooltip();
  const typesByCount = {};
  for (const ev of n.events) {
    typesByCount[ev.type] = (typesByCount[ev.type] || 0) + 1;
  }
  const typeSummary = Object.entries(typesByCount)
    .map(([t, c]) => c > 1 ? `${t} ×${c}` : t)
    .join(", ");
  t.innerHTML = `
    <div class="tt-id">${escapeHtml(n.entity.entity_id)}</div>
    <div class="tt-commit">${escapeHtml(n.commitMessage || "")}</div>
    <div class="tt-types">${escapeHtml(typeSummary)}</div>
  `;
  moveTooltip(e);
  t.style.display = "block";
}

function moveTooltip(e) {
  if (!tooltipEl) return;
  let x = e.clientX + 14;
  let y = e.clientY + 14;
  // Avoid going off-screen right.
  if (x + 320 > window.innerWidth) x = e.clientX - 330;
  tooltipEl.style.left = x + "px";
  tooltipEl.style.top = y + "px";
}

function hideTooltip() {
  if (tooltipEl) tooltipEl.style.display = "none";
}

// Commit-label hover tooltip. Re-uses the existing #flow-tooltip element
// but populates a commit-shaped payload instead of an entity-node one.
function showCommitTooltip(e, c) {
  const t = getTooltip();
  t.innerHTML = `
    <div class="tt-id">commit #${c.idx + 1}</div>
    <div class="tt-commit">${escapeHtml(c.message || "")}</div>
    <div class="tt-types">${escapeHtml(c.date || "")} · ${escapeHtml(c.author || "")}</div>
  `;
  moveTooltip(e);
  t.style.display = "block";
}

// Per-commit detail panel in the sidebar (Task B). Lists all events
// bracketed by this commit, grouped by entity, with event-pills + summaries.
function showCommitDetail(commit, layout) {
  const panel = document.getElementById("flow-detail");
  if (!panel) return;
  // Walk events.jsonl and collect everything whose bracketing commit matches.
  const e2c = layout.eventToCommit;
  const bracketed = state.events.filter(ev =>
    ev.type !== "commit.recorded" && e2c.get(ev.event_id) === commit.id
  );
  // Group by entity for readability.
  const byEntity = {};
  for (const ev of bracketed) {
    const key = ev.entity_id ? `${ev.entity_type}:${ev.entity_id}` : "(no-entity)";
    (byEntity[key] ||= []).push(ev);
  }
  const parts = [];
  parts.push(`<h3 class="md-title">Commit #${commit.idx + 1}</h3>`);
  parts.push(`<p class="detail-commit"><strong>${escapeHtml(commit.message || "")}</strong><br>`);
  parts.push(`<span class="detail-date">${escapeHtml(commit.date || "")} · ${escapeHtml(commit.author || "")}</span></p>`);
  parts.push(`<p class="meta-line">${bracketed.length} event${bracketed.length === 1 ? '' : 's'} in this commit across ${Object.keys(byEntity).length} entit${Object.keys(byEntity).length === 1 ? 'y' : 'ies'}.</p>`);
  if (!bracketed.length) {
    parts.push("<p class='hint'>(no events bracketed by this commit — meta-only commit, e.g. tooling/docs without a tracked plan)</p>");
  } else {
    for (const [ekey, evs] of Object.entries(byEntity)) {
      const entity = state.projection.entities[ekey];
      const entityLabel = entity
        ? `<span class="badge ${entity.derived_state}">${entity.derived_state}</span> <strong>${escapeHtml(entity.entity_id)}</strong>`
        : `<em>${escapeHtml(ekey)}</em>`;
      parts.push(`<div style="margin: 0.6rem 0 0.3rem;">${entityLabel}</div>`);
      parts.push("<ul class='event-list'>");
      for (const ev of evs) parts.push(renderEventLi(ev));
      parts.push("</ul>");
    }
  }
  panel.innerHTML = parts.join("");
  attachReadMoreToggles(panel);
}

function showDetail(n) {
  const panel = document.getElementById("flow-detail");
  if (!panel) return;
  const parts = [];
  parts.push(`<h3 class="md-title">${escapeHtml(n.entity.entity_id)}</h3>`);
  parts.push(`<div class="detail-actions"><button class="btn-isolate" id="btn-isolate-detail" title="Show only this entity and its parents/children/spawns">⌖ Isolate to this</button></div>`);
  parts.push(`<p class="detail-commit"><strong>Commit:</strong> ${escapeHtml(n.commitMessage)}<br><span class="detail-date">${escapeHtml(n.commitDate)}</span></p>`);
  parts.push(`<p>${n.eventCount} event(s) in this commit for this entity:</p>`);
  parts.push("<ul class='event-list'>");
  for (const ev of n.events) {
    parts.push(renderEventLi(ev));
  }
  parts.push("</ul>");
  // Task C: spawn-relationships navigation.
  parts.push(spawnRelationshipsSection(n.entity));
  panel.innerHTML = parts.join("");
  attachReadMoreToggles(panel);
  attachSpawnRelClickHandlers(panel);
  document.getElementById("btn-isolate-detail")?.addEventListener("click", () => {
    state.flowFilters.isolateRoot = { kind: "entity", key: n.entityKey };
    rerenderFlow();
  });
}

// Task C — return an HTML string listing the entity's spawn parents and
// children, plus tags distinguishing event-sourced vs frontmatter-derived
// edges. Empty string if neither direction has any rows (caller appends
// unconditionally; an empty string is a no-op insert).
function spawnRelationshipsSection(entity) {
  if (!entity || !state.projection) return "";
  const ekey = `${entity.entity_type}:${entity.entity_id}`;
  const rels = state.projection.relationships || [];
  const parents = [];
  const children = [];
  for (const r of rels) {
    if (r.type !== "spawns") continue;
    if (r.to === ekey) parents.push(r);
    else if (r.from === ekey) children.push(r);
  }
  if (!parents.length && !children.length) return "";
  const parts = [];
  parts.push(`<div class="spawn-rel-section">`);
  parts.push(`<h4 class="spawn-rel-header">Spawn relationships</h4>`);
  if (parents.length) {
    parts.push(`<div class="spawn-rel-group"><div class="spawn-rel-label">spawned by</div>`);
    for (const r of parents) parts.push(renderSpawnRow(r, r.from));
    parts.push(`</div>`);
  }
  if (children.length) {
    parts.push(`<div class="spawn-rel-group"><div class="spawn-rel-label">spawns</div>`);
    for (const r of children) parts.push(renderSpawnRow(r, r.to));
    parts.push(`</div>`);
  }
  parts.push(`</div>`);
  return parts.join("");
}

function renderSpawnRow(rel, targetKey) {
  const target = state.projection.entities[targetKey];
  if (!target) {
    return `<div class="spawn-rel-row spawn-rel-missing"><em>${escapeHtml(targetKey)}</em> <span class="hint">(not in projection)</span></div>`;
  }
  const sourceTag = rel.source === "frontmatter"
    ? `<span class="spawn-rel-source spawn-rel-source-fm" title="Derived from plan frontmatter, not from a relationship.spawns event">fm</span>`
    : `<span class="spawn-rel-source spawn-rel-source-ev" title="Sourced from a relationship.spawns event in events.jsonl">ev</span>`;
  return `<div class="spawn-rel-row" data-target-key="${escapeHtml(targetKey)}" title="Click to open ${escapeHtml(target.entity_id)}">
    <span class="badge ${target.derived_state}">${target.derived_state}</span>
    <span class="spawn-rel-id">${escapeHtml(target.entity_id)}</span>
    ${sourceTag}
  </div>`;
}

function attachSpawnRelClickHandlers(root) {
  root.querySelectorAll(".spawn-rel-row[data-target-key]").forEach(row => {
    row.addEventListener("click", () => {
      const key = row.dataset.targetKey;
      const target = state.projection.entities[key];
      if (target) showLiveStatus(target);
    });
  });
}

function renderEventLi(ev) {
  const kind = eventTypeKind(ev.type);
  const summary = ev.attributes?.summary || ev.attributes?.note || ev.attributes?.text || ev.attributes?.title || "(no summary)";
  const isLong = summary.length > 220;
  if (!isLong) {
    return `<li><span class="event-pill event-pill-${kind}">${escapeHtml(ev.type)}</span><div class="event-summary">${escapeHtml(summary)}</div></li>`;
  }
  return `<li><span class="event-pill event-pill-${kind}">${escapeHtml(ev.type)}</span><div class="event-summary expandable">${escapeHtml(summary)}</div><a href="#" class="read-more-toggle">read more</a></li>`;
}

function attachReadMoreToggles(root) {
  root.querySelectorAll(".read-more-toggle").forEach(a => {
    a.addEventListener("click", (e) => {
      e.preventDefault();
      const summary = a.previousElementSibling;
      const expanded = summary.classList.toggle("expanded");
      a.textContent = expanded ? "read less" : "read more";
    });
  });
}

async function showLiveStatus(entity) {
  const panel = document.getElementById("flow-detail");
  if (!panel) return;

  // Phase B: if a saved summary exists for this entity, render that instead
  // of the timeline. SavedSummary.render returns false if none exists.
  try {
    if (await SavedSummary.render(panel, entity)) return;
  } catch (e) {
    // Non-fatal — fall through to timeline if rendering fails.
    console.error("SavedSummary.render failed; falling back to timeline:", e);
  }

  // Filter events.jsonl for this entity, in order.
  const myEvents = state.events.filter(
    ev => ev.entity_type === entity.entity_type && ev.entity_id === entity.entity_id
  );

  const parts = [];
  parts.push(`<h3 class="md-title">${escapeHtml(entity.entity_id)}</h3>`);
  parts.push(`<p class="meta-line"><span class="badge ${entity.derived_state}">${entity.derived_state}</span> · ${escapeHtml(entity.entity_type)} · ${myEvents.length} event${myEvents.length === 1 ? '' : 's'} total</p>`);

  // Analyser actions row — only on plan / inbox-item; only enabled when an API key is configured.
  if (entity.entity_type === "plan" || entity.entity_type === "inbox-item") {
    const hasKey = Settings.hasKey();
    parts.push(`<div class="analyser-actions">`);
    parts.push(
      `<button class="btn-analyse" id="btn-analyse-outstanding" ${hasKey ? "" : "disabled"} ` +
      `title="${hasKey ? "Run a Claude-backed outstanding-work analysis on this entity" : "Configure API key in settings (gear pill, top-right)"}">` +
      `<span class="spark">✦</span>Analyse outstanding</button>`
    );
    if (!hasKey) {
      parts.push(`<button class="btn-secondary" id="btn-open-settings-from-live" style="font-size:0.78rem">Configure API key</button>`);
    }
    parts.push(`</div>`);
  }

  parts.push("<h4>Timeline</h4>");
  parts.push("<ul class='event-list'>");
  for (const ev of myEvents) {
    parts.push(renderEventLi(ev));
  }
  parts.push("</ul>");
  // Task C: spawn-relationships navigation.
  parts.push(spawnRelationshipsSection(entity));
  // Plus a "see full plan" affordance
  if (entity.entity_type === "plan" || entity.entity_type === "inbox-item") {
    parts.push(`<p class="hint"><a href="#" id="open-plan-from-live">→ Open the full plan/inbox markdown</a></p>`);
  }
  panel.innerHTML = parts.join("");
  attachReadMoreToggles(panel);
  attachSpawnRelClickHandlers(panel);

  const linkEl = document.getElementById("open-plan-from-live");
  if (linkEl) {
    linkEl.addEventListener("click", (e) => {
      e.preventDefault();
      showPlanMarkdown(entity);
    });
  }
  const analyseBtn = document.getElementById("btn-analyse-outstanding");
  if (analyseBtn) {
    analyseBtn.addEventListener("click", () => SidebarAnalyser.startAnalysis(entity));
  }
  const openSettings = document.getElementById("btn-open-settings-from-live");
  if (openSettings) {
    openSettings.addEventListener("click", () => Settings.openModal());
  }
}

async function showPlanMarkdown(entity) {
  const panel = document.getElementById("flow-detail");
  if (!panel) return;
  panel.innerHTML = `<p>Loading <code>${escapeHtml(entity.entity_id)}</code>…</p>`;

  let path;
  if (entity.entity_type === "plan") {
    path = `../../planning/${entity.entity_id}.md`;
  } else if (entity.entity_type === "inbox-item") {
    // Inbox filenames use dashes throughout; entity_id has a dot between date and slug.
    const filename = entity.entity_id.replace(/\./g, "-");
    path = `../../.agent-plan-tracker/inbox/${filename}.md`;
  } else {
    panel.innerHTML = `<p>No file mapping for entity_type <code>${escapeHtml(entity.entity_type)}</code>.</p>`;
    return;
  }

  try {
    const res = await fetch(path);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const md = await res.text();
    const body = stripFrontmatter(md);
    const rendered = (window.marked && window.marked.parse)
      ? window.marked.parse(body)
      : `<pre>${escapeHtml(body)}</pre>`;
    panel.innerHTML = `
      <h3 class="md-title">${escapeHtml(entity.entity_id)}</h3>
      <p class="meta-line"><span class="badge ${entity.derived_state}">${entity.derived_state}</span> · ${escapeHtml(entity.entity_type)} · <code>${escapeHtml(path)}</code></p>
      <div class="md-content">${rendered}</div>
    `;
  } catch (e) {
    panel.innerHTML = `<p>Failed to load <code>${escapeHtml(entity.entity_id)}</code>: ${escapeHtml(e.message)}</p><p class="hint">Path tried: <code>${escapeHtml(path)}</code></p>`;
  }
}

function stripFrontmatter(md) {
  const m = md.match(/^---\n[\s\S]*?\n---\n/);
  return m ? md.slice(m[0].length) : md;
}

function makeResizable(handle, sidebar) {
  let dragging = false;
  let startX = 0;
  let startWidth = 0;
  handle.addEventListener("mousedown", (e) => {
    dragging = true;
    startX = e.clientX;
    startWidth = sidebar.offsetWidth;
    document.body.style.cursor = "ew-resize";
    document.body.style.userSelect = "none";
    e.preventDefault();
  });
  document.addEventListener("mousemove", (e) => {
    if (!dragging) return;
    const delta = startX - e.clientX;
    const newWidth = Math.min(900, Math.max(280, startWidth + delta));
    // The sidebar lives inside a flex container with `flex: 0 0 380px`,
    // which pins flex-basis. Updating only `width` is overridden by the
    // basis; we have to set both for the drag to actually resize.
    sidebar.style.width = newWidth + "px";
    sidebar.style.flexBasis = newWidth + "px";
  });
  document.addEventListener("mouseup", () => {
    if (dragging) {
      dragging = false;
      document.body.style.cursor = "";
      document.body.style.userSelect = "";
    }
  });
}

// ---------------------------------------------------------------------------
// SVG helpers
// ---------------------------------------------------------------------------

function createNS(tag, attrs = {}) {
  const NS = "http://www.w3.org/2000/svg";
  const el = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v);
  return el;
}

function textNS(attrs, content) {
  const el = createNS("text", attrs);
  el.textContent = content;
  return el;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[c]);
}

// ===========================================================================
// === Analyser modules (Phase A — T3-analyser-phase-a-ephemeral) ============
// ===========================================================================
// Five small modules implementing the on-demand "what's outstanding?" loop:
//
//   Settings        — read/write API key + default model in localStorage
//   Estimator       — char-count token proxy + dollar cost per model
//   ContextBuilder  — pre-assembles the per-entity context bundle (§3.12)
//   AnalyseClient   — wraps fetch() to Anthropic; parses structured response
//   SidebarAnalyser — UI controller (analyse button → dialog → loading → result)
//
// No persistence in this phase. Closing the tab discards the summary.
// ===========================================================================

// --- Settings ---------------------------------------------------------------

const Settings = {
  KEY_LS_KEY: "apt_anthropic_api_key",
  MODEL_LS_KEY: "apt_default_model",

  get apiKey() {
    return localStorage.getItem(this.KEY_LS_KEY) || "";
  },
  set apiKey(v) {
    if (v && v.trim()) localStorage.setItem(this.KEY_LS_KEY, v.trim());
    else localStorage.removeItem(this.KEY_LS_KEY);
  },
  get defaultModel() {
    return localStorage.getItem(this.MODEL_LS_KEY) || "";
  },
  set defaultModel(v) {
    if (v) localStorage.setItem(this.MODEL_LS_KEY, v);
    else localStorage.removeItem(this.MODEL_LS_KEY);
  },
  hasKey() {
    return !!this.apiKey;
  },

  initToolbarPill() {
    const pill = document.getElementById("api-key-pill");
    if (!pill) return;
    pill.addEventListener("click", () => this.openModal());
    this.refreshPill();
  },
  refreshPill() {
    const pill = document.getElementById("api-key-pill");
    if (!pill) return;
    if (this.hasKey()) {
      pill.classList.remove("api-key-pill-missing");
      pill.classList.add("api-key-pill-ok");
      pill.title = `API key configured · default model: ${this.defaultModel || "(none — pick at call time)"}`;
    } else {
      pill.classList.add("api-key-pill-missing");
      pill.classList.remove("api-key-pill-ok");
      pill.title = "Configure Anthropic API key";
    }
  },

  openModal() {
    const modal = document.getElementById("settings-modal");
    if (!modal) return;
    document.getElementById("settings-api-key").value = this.apiKey;
    modal.hidden = false;
    // No preloading: populate only from the key actually in the input. On open
    // that's the saved key (if any); with no key the dropdown stays at its
    // placeholder until one is typed/pasted (see initModal).
    this._populateModelSelect(this.apiKey);
  },

  // Rebuild the default-model <select> from the live /v1/models catalogue for
  // the key currently in the input. We never preload a hardcoded list: with no
  // key the dropdown shows only the placeholder; the list is fetched
  // dynamically the moment a key is provided. `keyOverride` lets the key field
  // drive the list before the key is saved.
  async _populateModelSelect(keyOverride) {
    const sel = document.getElementById("settings-default-model");
    if (!sel) return;
    const cur = this.defaultModel;
    const placeholder = `<option value="">— none, pick at call time —</option>`;
    const key = (keyOverride !== undefined ? keyOverride : (this.apiKey || "")).trim();

    // No key in the input yet → nothing to fetch. Placeholder only.
    if (!key) {
      sel.innerHTML = placeholder;
      sel.value = "";
      sel.disabled = false;
      return;
    }

    // Token guards against an out-of-order response if the key changes while a
    // fetch is in flight (debounced input can fire several times).
    const token = (this._modelFetchToken = (this._modelFetchToken || 0) + 1);
    sel.disabled = true;
    sel.innerHTML = placeholder + `<option disabled>loading models…</option>`;

    let models;
    try {
      models = await ModelCatalog.list({ key });
    } catch {
      models = ModelCatalog.FALLBACK.slice();
    }
    if (token !== this._modelFetchToken) return;  // superseded by a newer fetch

    const opts = [placeholder];
    for (const m of models) {
      opts.push(`<option value="${escapeHtml(m.id)}" ${m.id === cur ? "selected" : ""}>${escapeHtml(m.display_name)}</option>`);
    }
    // Preserve a previously-saved default even if it's no longer in the catalogue,
    // so we don't silently drop the user's choice (they'll see it's stale).
    if (cur && !models.some(m => m.id === cur)) {
      opts.push(`<option value="${escapeHtml(cur)}" selected>${escapeHtml(cur)} (not in current catalogue)</option>`);
    }
    sel.innerHTML = opts.join("");
    sel.value = cur || "";
    sel.disabled = false;
  },
  closeModal() {
    const modal = document.getElementById("settings-modal");
    if (modal) modal.hidden = true;
  },

  initModal() {
    const saveBtn = document.getElementById("settings-save");
    const clearBtn = document.getElementById("settings-clear");
    const keyInput = document.getElementById("settings-api-key");
    // Fetch the model list dynamically as soon as a key is provided in the
    // input, debounced so a paste/type triggers a single fetch rather than one
    // per keystroke. An empty field shows only the placeholder (no preload).
    if (keyInput) {
      let keyDebounce;
      keyInput.addEventListener("input", () => {
        clearTimeout(keyDebounce);
        keyDebounce = setTimeout(() => this._populateModelSelect(keyInput.value), 400);
      });
    }
    if (saveBtn) saveBtn.addEventListener("click", () => {
      this.apiKey = document.getElementById("settings-api-key").value;
      this.defaultModel = document.getElementById("settings-default-model").value;
      this.refreshPill();
      this.closeModal();
      // If we have a live-status sidebar open, re-render to enable the button.
      const sidebar = document.getElementById("flow-detail");
      const btn = document.getElementById("btn-analyse-outstanding");
      if (sidebar && btn && btn.disabled && this.hasKey()) {
        // Crude refresh: trigger flow re-render. Simpler than precise state plumb.
        btn.disabled = false;
        btn.title = "Run a Claude-backed outstanding-work analysis on this entity";
      }
    });
    if (clearBtn) clearBtn.addEventListener("click", () => {
      document.getElementById("settings-api-key").value = "";
      this.apiKey = "";
      this.refreshPill();
    });
  },
};

// --- ModelCatalog -----------------------------------------------------------
// Single source of truth for which models the picker offers. We NEVER hardcode
// model IDs in the UI: Anthropic retires snapshots over time, and a baked-in ID
// (e.g. claude-sonnet-4-20250514) eventually returns `not_found_error` at call
// time. Instead we fetch the live catalogue from GET /v1/models with the user's
// key, so the picker can only ever offer models that key actually supports.
//
// Cached in-memory per key. A small static fallback is used ONLY when no key is
// present yet (so the dropdown isn't empty) or if the catalogue fetch fails.

const ModelCatalog = {
  ENDPOINT: "https://api.anthropic.com/v1/models",
  _cache: null,          // [{ id, display_name }]
  _cachedForKey: null,   // which key the cache belongs to

  // Last-resort placeholders. Intentionally generation-agnostic family aliases
  // are NOT valid model IDs, so we list a couple of conservative current IDs.
  // These are only shown pre-key / on fetch failure; the live catalogue
  // overrides them the moment a working key is available.
  FALLBACK: [
    { id: "claude-sonnet-4-5", display_name: "claude-sonnet-4-5 (fallback — confirm against your catalogue)" },
  ],

  async list({ key } = {}) {
    const useKey = (key !== undefined ? key : Settings.apiKey || "").trim();
    if (!useKey) return this.FALLBACK.slice();
    if (this._cache && this._cachedForKey === useKey) return this._cache;
    try {
      const res = await fetch(this.ENDPOINT + "?limit=100", {
        headers: {
          "x-api-key": useKey,
          "anthropic-version": AnalyseClient.API_VERSION,
          "anthropic-dangerous-direct-browser-access": "true",
        },
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      const models = (data.data || [])
        .map(m => ({ id: m.id, display_name: m.display_name || m.id }))
        .filter(m => m.id);
      this._cache = models.length ? models : this.FALLBACK.slice();
      this._cachedForKey = useKey;
      return this._cache;
    } catch (e) {
      console.warn("ModelCatalog: live /v1/models fetch failed; using fallback.", e);
      return this.FALLBACK.slice();
    }
  },

  // Pick a sensible default. An explicit Settings.defaultModel wins ONLY if it's
  // still in the live catalogue — otherwise a stale saved default (e.g. a model
  // that has since been retired) would be re-selected and fail with not_found at
  // call time. Falls back to a sonnet, then the first available model.
  defaultId(models) {
    const list = models || [];
    const saved = Settings.defaultModel;
    if (saved && list.some(m => m.id === saved)) return saved;
    const sonnet = list.find(m => /sonnet/i.test(m.id));
    return (sonnet || list[0] || {}).id || "";
  },
};

// --- Estimator --------------------------------------------------------------
// Char-count proxy: ~4 chars/token (English-heavy text). ±15-25% accuracy.
// Pricing baked in for v1; verify against Anthropic public pricing periodically.

const Estimator = {
  // USD per million tokens. Per-model-ID overrides only — leave empty unless a
  // specific snapshot's price diverges from its family. priceFor() falls back to
  // family inference (opus / sonnet / haiku), so new snapshots need no entry here
  // and we never hardcode model IDs that will later retire out of the catalogue.
  PRICING: {},
  DEFAULT_MAX_OUTPUT: 2048,
  CHARS_PER_TOKEN: 4,

  // Resolve $/M-token pricing for any model ID. Exact PRICING entries win;
  // otherwise infer by family so new snapshots (e.g. claude-opus-4-8) still get
  // a sane estimate rather than defaulting to sonnet rates. Cost is an estimate
  // either way (±15-25%), so family inference is acceptable.
  priceFor(model) {
    if (this.PRICING[model]) return this.PRICING[model];
    const id = String(model || "");
    if (/opus/i.test(id))  return { in: 15,  out: 75 };
    if (/haiku/i.test(id)) return { in: 1,   out: 5 };
    if (/sonnet/i.test(id)) return { in: 3,  out: 15 };
    return { in: 3, out: 15 };
  },

  estimateTokensFromText(text) {
    return Math.ceil((text || "").length / this.CHARS_PER_TOKEN);
  },
  estimateCallCost({ promptText, model, maxOutput }) {
    const inputTokens = this.estimateTokensFromText(promptText);
    const outputTokens = maxOutput || this.DEFAULT_MAX_OUTPUT;
    const p = this.priceFor(model);
    const dollars = (inputTokens * p.in + outputTokens * p.out) / 1_000_000;
    return { inputTokens, outputTokens, dollars };
  },
  formatCost(dollars) {
    if (dollars < 0.01) return `$${dollars.toFixed(4)}`;
    if (dollars < 1) return `$${dollars.toFixed(3)}`;
    return `$${dollars.toFixed(2)}`;
  },
};

// --- ContextBuilder ---------------------------------------------------------
// Assembles the bundle described in T2-analyser §3.12.
// Programmatic — no agent does discovery. We pre-fetch plan markdown and walk
// the relationship graph in the projection.

const ContextBuilder = {
  async buildPerEntityBundle(entity) {
    const projection = state.projection;
    const ekey = `${entity.entity_type}:${entity.entity_id}`;

    // Focal events (full timeline, in event-log order).
    const focalEvents = state.events.filter(
      ev => ev.entity_type === entity.entity_type && ev.entity_id === entity.entity_id
    );

    // Focal plan markdown body (or inbox-item md).
    let focalMd = "";
    try {
      focalMd = await this._fetchEntityMarkdown(entity);
    } catch (e) {
      focalMd = `(could not load markdown: ${e.message})`;
    }

    // 1-hop graph via relationships in projection.
    const related = this._related1Hop(ekey, projection);

    // Open blockers + open HITL referencing the focal id by event subject or 1-hop link.
    const openBlockers = this._openByType(projection, "blocker", ekey, related);
    const openHitl = this._openByType(projection, "hitl-question", ekey, related);

    // Inbox items referencing the focal entity_id — string match against the
    // inbox-item entity summaries available in the projection (cheap pre-pass).
    // Phase A: don't fetch every inbox md file (would be ~13 extra fetches);
    // rely on the summary text the projection already carries. TODO Phase B:
    // pre-computed inbox-index per T2-analyser §7 Q12.
    const inboxRefs = Object.values(projection.entities)
      .filter(e => e.entity_type === "inbox-item")
      .filter(e => {
        const summary = (e.attributes && e.attributes.summary) || "";
        const title = (e.attributes && e.attributes.title) || "";
        return (summary + title).includes(entity.entity_id);
      })
      .map(e => ({
        id: e.entity_id,
        title: (e.attributes && e.attributes.title) || "",
        summary: (e.attributes && e.attributes.summary) || "",
        derived_state: e.derived_state,
      }));

    // Prior valid summary (Phase B): populated from projection.latest_summary_by_entity
    // if present. The full freeform is fetched lazily by SidebarAnalyser when the
    // prompt is built — for the bundle we surface the structured fields + path.
    const latestMap = projection.latest_summary_by_entity || {};
    const priorSummary = latestMap[ekey] || null;

    return {
      focal: {
        id: entity.entity_id,
        type: entity.entity_type,
        plan_kind: entity.attributes?.plan_kind,
        tier: entity.attributes?.tier,
        derived_state: entity.derived_state,
        plan_md: focalMd,
        events: focalEvents.map(this._eventForBundle),
      },
      related_1hop: related,
      open_blockers: openBlockers,
      open_hitl: openHitl,
      inbox_refs: inboxRefs,
      prior_summary: priorSummary,
    };
  },

  _related1Hop(ekey, projection) {
    // Projection's relationships table is now unified: cache-build derives
    // frontmatter-implied edges (T3.t2_parent → T2, plan.milestone → Mn)
    // alongside event-sourced relationship.* events. Each row carries a
    // `source` field ('event' | 'frontmatter') for downstream consumers
    // that care. The analyser does not — a 1-hop walk over the unified
    // set is all that's needed.
    const rels = projection.relationships || [];
    const out = [];
    const seen = new Set();
    const push = (entity, relType, direction, source) => {
      const k = `${entity.entity_type}:${entity.entity_id}`;
      if (k === ekey || seen.has(k)) return;
      seen.add(k);
      const summary = this._relSummary(entity, relType, direction);
      if (source === "frontmatter") summary.relation += " · derived";
      out.push(summary);
    };
    for (const r of rels) {
      if (r.from === ekey) {
        const e = projection.entities[r.to];
        if (e) push(e, r.type, "outgoing", r.source);
      } else if (r.to === ekey) {
        const e = projection.entities[r.from];
        if (e) push(e, r.type, "incoming", r.source);
      }
    }
    return out;
  },
  _relSummary(entity, relType, direction) {
    const a = entity.attributes || {};
    const oneLiner = a.summary || a.title || `(${entity.entity_type} ${entity.entity_id})`;
    return {
      id: entity.entity_id,
      kind: entity.entity_type,
      plan_kind: a.plan_kind,
      tier: a.tier,
      derived_state: entity.derived_state,
      relation: `${relType} (${direction})`,
      one_liner: oneLiner.slice(0, 240),
    };
  },
  _openByType(projection, etype, focalKey, related) {
    return Object.values(projection.entities)
      .filter(e => e.entity_type === etype)
      .filter(e => e.derived_state === "live" || e.derived_state === "dormant")
      .filter(e => {
        const fkey = `${e.entity_type}:${e.entity_id}`;
        if (related.find(r => r.id === e.entity_id && r.kind === etype)) return true;
        const summary = (e.attributes && e.attributes.summary) || "";
        return summary.includes(focalKey.split(":")[1]);
      })
      .map(e => ({
        id: e.entity_id,
        summary: (e.attributes && e.attributes.summary) || "",
      }));
  },
  _eventForBundle(ev) {
    // Strip uuids; keep essentials.
    return {
      type: ev.type,
      actor: ev.actor,
      summary: (ev.attributes && (ev.attributes.summary || ev.attributes.note || ev.attributes.text || ev.attributes.title)) || "",
    };
  },

  async _fetchEntityMarkdown(entity) {
    let path;
    if (entity.entity_type === "plan") {
      path = `../../planning/${entity.entity_id}.md`;
    } else if (entity.entity_type === "inbox-item") {
      const filename = entity.entity_id.replace(/\./g, "-");
      path = `../../.agent-plan-tracker/inbox/${filename}.md`;
    } else {
      return "";
    }
    const res = await fetch(path);
    if (!res.ok) throw new Error(`HTTP ${res.status} fetching ${path}`);
    const raw = await res.text();
    return stripFrontmatter(raw).trim();
  },

  // Serialise the bundle to a single user-message string.
  bundleToPrompt(bundle) {
    const lines = [];
    const f = bundle.focal;
    lines.push(`# Focal entity: ${f.id}`);
    lines.push(`- type: ${f.type}${f.plan_kind ? ` (${f.plan_kind})` : ""}${f.tier ? ` · T${f.tier}` : ""}`);
    lines.push(`- derived state: ${f.derived_state}`);
    lines.push("");
    lines.push(`## Plan markdown for ${f.id}`);
    lines.push("");
    lines.push(f.plan_md || "(empty)");
    lines.push("");
    lines.push(`## Full event timeline for ${f.id} (${f.events.length} events)`);
    if (!f.events.length) {
      lines.push("(no events)");
    } else {
      for (const ev of f.events) {
        const sum = (ev.summary || "").slice(0, 500);
        lines.push(`- **${ev.type}** by ${ev.actor || "?"}: ${sum}`);
      }
    }
    lines.push("");
    lines.push(`## Related entities (1-hop relationship graph)`);
    if (!bundle.related_1hop.length) {
      lines.push("(none)");
    } else {
      for (const r of bundle.related_1hop) {
        lines.push(`- **${r.id}** (${r.kind}${r.plan_kind ? `/${r.plan_kind}` : ""}, ${r.derived_state}) — ${r.relation}: ${r.one_liner}`);
      }
    }
    lines.push("");
    lines.push(`## Open blockers referencing this entity`);
    if (!bundle.open_blockers.length) lines.push("(none)");
    else for (const b of bundle.open_blockers) lines.push(`- ${b.id}: ${b.summary.slice(0, 240)}`);
    lines.push("");
    lines.push(`## Open HITL questions referencing this entity`);
    if (!bundle.open_hitl.length) lines.push("(none)");
    else for (const h of bundle.open_hitl) lines.push(`- ${h.id}: ${h.summary.slice(0, 240)}`);
    lines.push("");
    lines.push(`## Open inbox items referencing this entity`);
    if (!bundle.inbox_refs.length) lines.push("(none)");
    else for (const i of bundle.inbox_refs) {
      lines.push(`- **${i.id}** (${i.derived_state}) — ${i.title}`);
      if (i.summary) lines.push(`  ${i.summary.slice(0, 300)}`);
    }
    lines.push("");
    lines.push(`## Prior analyser summary on ${f.id}`);
    if (!bundle.prior_summary) {
      lines.push("(none — this is the first analysis for this entity)");
    } else {
      const ps = bundle.prior_summary;
      const tag = ps.source === "derived" ? "derived (side-effect of another call)" : "primary";
      lines.push(`(${tag}, generated by ${ps.model || "?"})`);
      const s = ps.structured || {};
      lines.push("Outstanding:");
      for (const it of (s.outstanding || [])) lines.push(`- ${it}`);
      lines.push("Blocked:");
      for (const it of (s.blocked || [])) lines.push(`- ${it}`);
      lines.push("Recently changed:");
      for (const it of (s.recently_changed || [])) lines.push(`- ${it}`);
      lines.push(`Next move: ${s.next_move || "(empty)"}`);
      lines.push("");
      lines.push("Treat the above as established. Describe only what has changed since, plus what remains outstanding.");
    }
    return lines.join("\n");
  },

  buildSystemPrompt() {
    return [
      "You are analysing an entity in a planning-driven, event-sourced project.",
      "Your sole job: answer 'what is outstanding here?' given the pre-fetched plan, full event timeline, related entities, and any prior analyser summary. Do not request more data — you have what you need.",
      "",
      "Output format — EXACTLY this shape, in order:",
      "",
      "1. A fenced JSON code block tagged ```json with this schema:",
      "{",
      '  "outstanding": ["specific items still to do, one short string each"],',
      '  "blocked": ["items blocked by external dependencies or open HITL"],',
      '  "recently_changed": ["state changes captured in the most recent events"],',
      '  "next_move": "single most actionable next step (one sentence)",',
      '  "derived_summaries": [',
      '    {',
      '      "entity_type": "plan" | "inbox-item",',
      '      "entity_id": "<id of a 1-hop dependent>",',
      '      "outstanding": [...],',
      '      "blocked": [...],',
      '      "recently_changed": [...],',
      '      "next_move": "..."',
      '    }',
      '  ]',
      "}",
      "",
      "2. Immediately after, a '## Freeform analysis' h2 header followed by markdown prose: rationale, callouts of risk or smell, references to specific events or related entities by id. Keep it tight — under 400 words.",
      "",
      "Rules:",
      "- Reference events and entities by id when you can.",
      "- If the entity is closed/complete, say so and keep outstanding empty.",
      "- Do not hedge with 'I don't have access to X' — you have everything; reason from what's here.",
      "- Output JSON before prose, always.",
      "- `derived_summaries` is OPTIONAL. Include one entry per 1-hop dependent you formed an opinion on. Skip closed entities. Empty array `[]` is fine. Don't pad — only include dependents where you have something concrete to say (one or two genuine outstanding/blocked/changed items, or a clear next_move).",
    ].join("\n");
  },
};

// --- AnalyseClient ----------------------------------------------------------
// Direct call to api.anthropic.com from the browser. API key from Settings.
// Phase A: blocking call (no streaming).

const AnalyseClient = {
  ENDPOINT: "https://api.anthropic.com/v1/messages",
  API_VERSION: "2023-06-01",

  async run({ apiKey, model, systemPrompt, userPrompt, maxTokens = 2048 }) {
    const body = {
      model,
      max_tokens: maxTokens,
      system: systemPrompt,
      messages: [{ role: "user", content: userPrompt }],
    };
    let res;
    try {
      res = await fetch(this.ENDPOINT, {
        method: "POST",
        headers: {
          "x-api-key": apiKey,
          "anthropic-version": this.API_VERSION,
          "anthropic-dangerous-direct-browser-access": "true",
          "content-type": "application/json",
        },
        body: JSON.stringify(body),
      });
    } catch (e) {
      throw new AnalyseError("network", `Network error: ${e.message}`, null);
    }
    if (!res.ok) {
      let bodyText = "";
      try { bodyText = await res.text(); } catch {}
      const code = res.status === 401 ? "auth"
                 : res.status === 429 ? "rate-limit"
                 : res.status >= 500 ? "server"
                 : "http";
      throw new AnalyseError(code, `Anthropic API returned HTTP ${res.status}`, bodyText, res.headers);
    }
    const data = await res.json();
    const text = (data.content || []).filter(c => c.type === "text").map(c => c.text).join("\n");
    const usage = data.usage || {};
    const parsed = this._parseStructured(text);
    return {
      raw: text,
      structured: parsed.structured,
      freeform: parsed.freeform,
      parseFailed: parsed.parseFailed,
      usage: {
        inputTokens: usage.input_tokens || 0,
        outputTokens: usage.output_tokens || 0,
      },
      model,
    };
  },

  _parseStructured(text) {
    // Look for ```json ... ``` fenced block.
    const fence = text.match(/```json\s*\n([\s\S]*?)\n```/);
    if (!fence) {
      // Try a bare JSON object at the start.
      const bare = text.match(/^\s*(\{[\s\S]*?\})\s*\n\n/);
      if (bare) {
        try {
          const structured = JSON.parse(bare[1]);
          const freeform = text.slice(bare[0].length).trim();
          return { structured, freeform, parseFailed: false };
        } catch (e) { /* fallthrough */ }
      }
      return { structured: null, freeform: text, parseFailed: true };
    }
    let structured;
    try {
      structured = JSON.parse(fence[1]);
    } catch (e) {
      return { structured: null, freeform: text, parseFailed: true };
    }
    // Freeform is whatever comes after the fence.
    const after = text.slice(fence.index + fence[0].length).trim();
    return { structured, freeform: after, parseFailed: false };
  },
};

class AnalyseError extends Error {
  constructor(code, message, body, headers) {
    super(message);
    this.code = code;
    this.body = body;
    this.headers = headers;
  }
  userFacing() {
    if (this.code === "auth") return "API key rejected (401) — check the key in settings.";
    if (this.code === "rate-limit") {
      const retry = this.headers && this.headers.get("retry-after");
      return `Rate limited (429)${retry ? ` — retry in ${retry}s` : ""}.`;
    }
    if (this.code === "network") return this.message;
    if (this.code === "server") return "Anthropic API is unavailable (5xx). Try again shortly.";
    return this.message;
  }
}

// --- PersistenceClient ------------------------------------------------------
// Wraps the local server-wrapper endpoints (T2-analyser §3.4).
// Phase B endpoints: GET /api/clean-check, POST /api/save-summary.
// /api/invalidate-summary is a stub on the server (Phase D); not called here.

const PersistenceClient = {
  async cleanCheck() {
    const res = await fetch("/api/clean-check", { cache: "no-store" });
    if (!res.ok) {
      throw new PersistenceError("server", `clean-check HTTP ${res.status}`);
    }
    return await res.json();
  },

  async saveSummary({ primary, derived }) {
    const res = await fetch("/api/save-summary", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        event: primary.event,
        freeform_md: primary.freeform_md,
        derived: (derived || []).map(d => ({
          event: d.event,
          freeform_md: d.freeform_md,
        })),
      }),
    });
    let data = {};
    try { data = await res.json(); } catch {}
    if (!res.ok) {
      const code = res.status === 409 ? "dirty-tree"
                 : res.status === 422 ? "validation"
                 : res.status === 400 ? "bad-request"
                 : "server";
      const e = new PersistenceError(code, data.message || `HTTP ${res.status}`);
      e.status = res.status;
      e.dirty_files = data.dirty_files;
      e.errors = data.errors;
      throw e;
    }
    return data;
  },

  // Phase D — T3-analyser-phase-d-cascade-invalidation.
  // Server computes the cascade and emits one analysis.invalidated event
  // listing the cascade. Returns { ok, invalidation_event_id,
  // target_event_id, cascades_to_event_ids[], reason }.
  async invalidateSummary({ target_event_id, reason }) {
    const res = await fetch("/api/invalidate-summary", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ target_event_id, reason }),
    });
    let data = {};
    try { data = await res.json(); } catch {}
    if (!res.ok) {
      const code = res.status === 409 ? "dirty-tree"
                 : res.status === 404 ? "not-found"
                 : res.status === 400 ? "bad-request"
                 : "server";
      const e = new PersistenceError(code, data.message || `HTTP ${res.status}`);
      e.status = res.status;
      e.dirty_files = data.dirty_files;
      throw e;
    }
    return data;
  },
};

class PersistenceError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
  userFacing() {
    if (this.code === "dirty-tree") return "Working tree dirty — commit or stash before saving.";
    if (this.code === "validation") return "Save rejected: event failed schema validation.";
    if (this.code === "server") return "Server error during save.";
    return this.message;
  }
}

// --- SavedSummary -----------------------------------------------------------
// Loads the latest valid summary for an entity (if any) from
// projection.latest_summary_by_entity + fetches its freeform markdown file.
// Renders as the default sidebar view in place of the timeline.
// Provides Regenerate + Show timeline + Show freeform / Show structured toggles.

const SavedSummary = {
  forEntity(entity) {
    const proj = state.projection || {};
    const map = proj.latest_summary_by_entity || {};
    return map[`${entity.entity_type}:${entity.entity_id}`] || null;
  },

  byEventId(eventId) {
    // Phase C: look up an arbitrary summary by event_id (not just the latest
    // on its entity). Allows the flow view's summary-node click handler to
    // open whichever summary was clicked, including superseded ones.
    const proj = state.projection || {};
    const map = proj.summaries || {};
    return map[eventId] || null;
  },

  async renderByEventId(panel, entity, eventId) {
    const summary = this.byEventId(eventId);
    if (!summary) {
      panel.innerHTML = `<p class="analyser-error">Summary <code>${escapeHtml(eventId)}</code> not found in projection. Try refreshing.</p>`;
      return false;
    }
    return this._renderInner(panel, entity, summary);
  },

  async render(panel, entity) {
    const summary = this.forEntity(entity);
    if (!summary) return false;
    return this._renderInner(panel, entity, summary);
  },

  async _renderInner(panel, entity, summary) {

    // Load freeform markdown lazily.
    let freeform = "";
    try {
      const path = `../../${summary.freeform_path}`;
      const res = await fetch(path);
      if (res.ok) freeform = await res.text();
    } catch {
      freeform = "";
    }

    const isDerived = summary.source === "derived";
    const parts = [];
    parts.push(`<h3 class="md-title">${escapeHtml(entity.entity_id)}</h3>`);
    parts.push(`<p class="meta-line">
      <span class="badge ${entity.derived_state}">${entity.derived_state}</span> ·
      ${escapeHtml(entity.entity_type)} ·
      <span class="tag saved-tag">saved summary</span>
      ${isDerived ? '<span class="tag derived-tag">side-effect (derived)</span>' : ""}
      <code class="model-tag">${escapeHtml(summary.model || "?")}</code>
    </p>`);
    if (isDerived) {
      parts.push(`<p class="hint">This summary was generated as a side-effect of a primary analysis on another entity. Run primary analysis here for precision.</p>`);
    }

    // Invalidation banner (Phase D) — shown HERE, right at the top, so the
    // operator sees the stale-state warning before reading the content below.
    const isInvalid = summary.valid === false;
    if (isInvalid) {
      parts.push(`<div class="invalidation-banner">
        <strong>⚠ This summary has been invalidated.</strong>
        ${summary.invalidated_by_event_id ? `<div class="hint">invalidated by event <code>${escapeHtml(summary.invalidated_by_event_id)}</code></div>` : ""}
        <div class="hint">Regenerate to replace.</div>
      </div>`);
    }

    parts.push(`<div class="analyser-toggle-row">
      <button class="active" data-show="structured">Structured</button>
      <button data-show="freeform">Freeform</button>
      <button data-show="timeline">Timeline</button>
    </div>`);

    // Structured pane
    parts.push(`<div id="analyser-pane-structured">`);
    const s = summary.structured || {};
    parts.push(SidebarAnalyser._renderSection("Outstanding", "outstanding", s.outstanding || []));
    parts.push(SidebarAnalyser._renderSection("Blocked", "blocked", s.blocked || []));
    parts.push(SidebarAnalyser._renderSection("Recently changed", "recently_changed", s.recently_changed || []));
    parts.push(SidebarAnalyser._renderNextMove(s.next_move || ""));
    parts.push(`</div>`);

    // Freeform pane
    parts.push(`<div id="analyser-pane-freeform" hidden>`);
    const ffBody = stripFrontmatter(freeform || "");
    const ffHtml = ffBody
      ? (window.marked && window.marked.parse ? window.marked.parse(ffBody) : `<pre>${escapeHtml(ffBody)}</pre>`)
      : `<p class="empty-section">(no freeform content)</p>`;
    parts.push(`<div class="analyser-freeform">${ffHtml}</div>`);
    parts.push(`</div>`);

    // Timeline pane (lazy-populated)
    parts.push(`<div id="analyser-pane-timeline" hidden></div>`);

    // Actions (isInvalid was computed earlier, near the banner placement)
    const hasKey = Settings.hasKey();
    parts.push(`<div class="analyser-toggle-row">
      <button class="btn-primary" id="btn-saved-regenerate" ${hasKey ? "" : "disabled"} style="font-size:0.78rem"
        title="${hasKey ? "Re-run analysis (new event will supersede this one)" : "Configure API key in settings first"}">↻ Regenerate</button>
      <button class="btn-danger" id="btn-saved-invalidate" ${isInvalid ? "disabled" : ""} style="font-size:0.78rem"
        title="${isInvalid ? "Already invalidated" : "Mark this summary invalid. Cascade-detects dependents and marks them too. One-way; regenerate to replace."}">⊘ Invalidate</button>
      <button class="btn-secondary" id="btn-saved-show-summary-event" style="font-size:0.78rem">View event id</button>
    </div>`);
    parts.push(`<div id="analyser-invalidate-feedback"></div>`);

    // Task C: spawn-relationships navigation, after the actions row.
    parts.push(spawnRelationshipsSection(entity));

    panel.innerHTML = parts.join("");
    attachSpawnRelClickHandlers(panel);

    // Toggle wiring
    panel.querySelectorAll(".analyser-toggle-row [data-show]").forEach(btn => {
      btn.addEventListener("click", () => {
        panel.querySelectorAll(".analyser-toggle-row [data-show]").forEach(b => b.classList.remove("active"));
        btn.classList.add("active");
        const show = btn.dataset.show;
        document.getElementById("analyser-pane-structured").hidden = (show !== "structured");
        document.getElementById("analyser-pane-freeform").hidden = (show !== "freeform");
        const tlPane = document.getElementById("analyser-pane-timeline");
        if (tlPane) {
          tlPane.hidden = (show !== "timeline");
          if (show === "timeline" && !tlPane.dataset.populated) {
            this._renderTimelineInto(tlPane, entity);
            tlPane.dataset.populated = "1";
          }
        }
      });
    });

    document.getElementById("btn-saved-regenerate")?.addEventListener("click", () => {
      SidebarAnalyser.startAnalysis(entity);
    });
    document.getElementById("btn-saved-invalidate")?.addEventListener("click", () => {
      SavedSummary._openInvalidateDialog(entity, summary);
    });
    document.getElementById("btn-saved-show-summary-event")?.addEventListener("click", () => {
      alert(`Summary event id: ${summary.event_id}\nSource: ${summary.source}\nFreeform path: ${summary.freeform_path}\nSupersedes: ${summary.supersedes_summary_event_id || "(none)"}`);
    });

    return true;
  },

  // Phase D: client-side cascade preview + confirmation dialog.
  // Mirrors the server's cascade rules so the user knows what will happen
  // BEFORE confirming. The server re-computes from scratch on commit; this
  // is a UI courtesy only.
  _previewCascade(targetSummary) {
    const proj = state.projection || {};
    const allSummaries = Object.values(proj.summaries || {});
    const targetKey = `${targetSummary.entity_type}:${targetSummary.entity_id}`;
    const targetLine = (allSummaries.find(s => s.event_id === targetSummary.event_id) || {}).line_no
      ?? Number.NEGATIVE_INFINITY;

    // Build 1-hop spawn neighbours via event-sourced edges only.
    const eventSpawnNeighbours = new Set();
    for (const r of (proj.relationships || [])) {
      if (r.type !== "spawns" || r.source !== "event") continue;
      if (r.from === targetKey) eventSpawnNeighbours.add(r.to);
      else if (r.to === targetKey) eventSpawnNeighbours.add(r.from);
    }

    const cascade = [];
    for (const s of allSummaries) {
      if (s.event_id === targetSummary.event_id) continue;
      if (s.valid === false) continue;  // already invalidated
      const sKey = `${s.entity_type}:${s.entity_id}`;
      // (1) Same-entity chain successor
      if (sKey === targetKey && (s.line_no || 0) > targetLine) {
        cascade.push(s); continue;
      }
      // (2) Origin chain (derived whose primary is the target)
      if (s.origin_summary_event_id === targetSummary.event_id) {
        cascade.push(s); continue;
      }
      // (3) Cross-entity via spawn graph, after target
      if (eventSpawnNeighbours.has(sKey) && (s.line_no || 0) > targetLine) {
        cascade.push(s); continue;
      }
    }
    return cascade;
  },

  _openInvalidateDialog(entity, summary) {
    const cascade = SavedSummary._previewCascade(summary);
    const dialog = document.getElementById("cost-dialog");  // re-purpose the modal
    const titleEl = document.getElementById("cost-dialog-title");
    const body = document.getElementById("cost-dialog-body");
    const cancelBtn = document.getElementById("cost-cancel");
    const confirmBtn = document.getElementById("cost-confirm");
    if (!dialog || !body || !confirmBtn) return;

    titleEl.textContent = "Invalidate summary";
    body.innerHTML = `
      <p class="modal-hint">
        About to mark this summary invalid. This is <strong>one-way</strong>;
        the only way to "restore" is to regenerate (which supersedes it with
        a fresh primary). Cascade-detected dependents are also marked invalid
        in the same operation.
      </p>
      <div class="cost-line"><span class="cost-label">Target</span><span class="cost-value">${escapeHtml(summary.event_id.slice(0, 8))}… on ${escapeHtml(entity.entity_id)}</span></div>
      <div class="cost-line"><span class="cost-label">Source</span><span class="cost-value">${escapeHtml(summary.source || "?")}</span></div>
      <div class="cost-line cost-total"><span class="cost-label">Cascade size</span><span class="cost-value">${cascade.length}</span></div>
      ${cascade.length ? `
        <div class="invalidate-cascade-list">
          <div class="form-label" style="margin-top:0.7rem">Will also invalidate:</div>
          <ul style="font-size:0.78rem;font-family:var(--mono);max-height:160px;overflow-y:auto;padding-left:1.1rem;margin:0.3rem 0 0.5rem">
            ${cascade.map(c => `<li>${escapeHtml(c.entity_id)} <span style="color:#888">(${escapeHtml(c.source)}, ${escapeHtml(c.event_id.slice(0,8))}…)</span></li>`).join("")}
          </ul>
        </div>
      ` : `<div class="cost-warning-banner" style="background:#e8f5e9;border-color:#43a047;color:#1b5e20">No dependents detected — invalidating only this summary.</div>`}
      <div class="form-row">
        <span class="form-label">Reason</span>
        <select id="invalidate-reason">
          <option value="user-triggered (stale)">user-triggered (stale)</option>
          <option value="underlying-events-changed">underlying-events-changed</option>
          <option value="regenerating-replacement">regenerating-replacement</option>
          <option value="other">other</option>
        </select>
      </div>
    `;
    // Re-label the confirm button to be unambiguous about the destructive action.
    confirmBtn.textContent = "Confirm and invalidate";
    confirmBtn.classList.remove("btn-primary");
    confirmBtn.classList.add("btn-danger");

    // Detach any previous handler.
    if (SavedSummary._invalidateConfirmHandler) {
      confirmBtn.removeEventListener("click", SavedSummary._invalidateConfirmHandler);
    }
    SavedSummary._invalidateConfirmHandler = async () => {
      const reason = document.getElementById("invalidate-reason").value || "user-triggered";
      dialog.hidden = true;
      // Restore button look for any future cost-dialog opens.
      confirmBtn.textContent = "Confirm and run";
      confirmBtn.classList.remove("btn-danger");
      confirmBtn.classList.add("btn-primary");
      await SavedSummary._performInvalidate(entity, summary, reason);
    };
    confirmBtn.addEventListener("click", SavedSummary._invalidateConfirmHandler);

    // Cancel restores button look too.
    const cancelRestore = () => {
      confirmBtn.textContent = "Confirm and run";
      confirmBtn.classList.remove("btn-danger");
      confirmBtn.classList.add("btn-primary");
      cancelBtn.removeEventListener("click", cancelRestore);
    };
    cancelBtn.addEventListener("click", cancelRestore);

    dialog.hidden = false;
  },

  async _performInvalidate(entity, summary, reason) {
    const fb = document.getElementById("analyser-invalidate-feedback");
    const btn = document.getElementById("btn-saved-invalidate");
    if (btn) btn.disabled = true;
    if (fb) fb.innerHTML = `<div class="analyser-loading"><div class="spinner"></div>Invalidating…</div>`;

    try {
      const resp = await PersistenceClient.invalidateSummary({
        target_event_id: summary.event_id,
        reason,
      });
      const n = (resp.cascades_to_event_ids || []).length;
      if (fb) {
        fb.innerHTML = `<div class="analyser-saved-banner" style="background:#fff3cd;border-color:#ffc107;color:#5d4400">
          Invalidated · <code>${escapeHtml(resp.invalidation_event_id)}</code>
          ${n > 0 ? `· +${n} cascaded` : ""}
          <br><span class="hint">Run <code>repack-validate.sh</code> then reload to see the flow view repaint (struck-through node).</span>
        </div>`;
      }
      if (btn) {
        btn.textContent = "⊘ Invalidated";
        btn.disabled = true;
      }
    } catch (e) {
      const message = e instanceof PersistenceError ? e.userFacing() : (e.message || "Invalidate failed");
      const detail = (e && e.dirty_files) ? `\n${(e.dirty_files || []).join("\n")}` : "";
      if (fb) {
        fb.innerHTML = `<div class="analyser-error"><strong>${escapeHtml(message)}</strong>${detail ? `<pre>${escapeHtml(detail)}</pre>` : ""}</div>`;
      }
      if (btn) btn.disabled = false;
    }
  },

  _renderTimelineInto(pane, entity) {
    const myEvents = state.events.filter(
      ev => ev.entity_type === entity.entity_type && ev.entity_id === entity.entity_id
    );
    const parts = ["<h4>Timeline</h4>", "<ul class='event-list'>"];
    for (const ev of myEvents) parts.push(renderEventLi(ev));
    parts.push("</ul>");
    pane.innerHTML = parts.join("");
    attachReadMoreToggles(pane);
  },
};

// --- SidebarAnalyser --------------------------------------------------------
// UI controller: analyse button → cost dialog → loading → result.
// Ephemeral state on the controller; rerunning rebuilds from scratch.

const SidebarAnalyser = {
  _pendingConfirmHandler: null,

  async startAnalysis(entity) {
    const panel = document.getElementById("flow-detail");
    if (!panel) return;
    if (!Settings.hasKey()) {
      Settings.openModal();
      return;
    }
    // Build the bundle + prompts, then show the cost dialog.
    let bundle, userPrompt, systemPrompt;
    try {
      panel.innerHTML = `<div class="analyser-loading"><div class="spinner"></div>Assembling context bundle for <code>${escapeHtml(entity.entity_id)}</code>…</div>`;
      bundle = await ContextBuilder.buildPerEntityBundle(entity);
      userPrompt = ContextBuilder.bundleToPrompt(bundle);
      systemPrompt = ContextBuilder.buildSystemPrompt();
    } catch (e) {
      this._renderError(panel, entity, "Could not build context bundle", e.message);
      return;
    }
    // Restore the live-status view while the dialog is open.
    showLiveStatus(entity);
    await this._showCostDialog({ entity, systemPrompt, userPrompt, bundle });
  },

  async _showCostDialog({ entity, systemPrompt, userPrompt, bundle }) {
    const dialog = document.getElementById("cost-dialog");
    const body = document.getElementById("cost-dialog-body");
    if (!dialog || !body) return;
    const fullPromptText = systemPrompt + "\n\n" + userPrompt;
    // Live model catalogue for this key — never a hardcoded list.
    const models = await ModelCatalog.list();
    const defaultModel = ModelCatalog.defaultId(models);

    const renderForModel = (model) => {
      const cost = Estimator.estimateCallCost({ promptText: fullPromptText, model });
      body.innerHTML = `
        <p class="modal-hint">
          About to analyse <strong>${escapeHtml(entity.entity_id)}</strong> by calling the Anthropic API directly from this browser.
          Context bundle assembled programmatically (no agent discovery). Estimates use a char-count proxy; actuals will differ ±15-25%.
        </p>
        <div class="form-row">
          <span class="form-label">Model</span>
          <select id="cost-model-pick">
            ${models.map(m =>
              `<option value="${escapeHtml(m.id)}" ${m.id === model ? "selected" : ""}>${escapeHtml(m.display_name)}</option>`
            ).join("")}
          </select>
        </div>
        <div class="cost-line"><span class="cost-label">Input tokens (estimated)</span><span class="cost-value">~${cost.inputTokens.toLocaleString()}</span></div>
        <div class="cost-line"><span class="cost-label">Output tokens (max)</span><span class="cost-value">~${cost.outputTokens.toLocaleString()}</span></div>
        <div class="cost-line"><span class="cost-label">Related entities (1-hop)</span><span class="cost-value">${bundle.related_1hop.length}</span></div>
        <div class="cost-line"><span class="cost-label">Inbox refs</span><span class="cost-value">${bundle.inbox_refs.length}</span></div>
        <div class="cost-line cost-total"><span class="cost-label">Estimated cost</span><span class="cost-value">${Estimator.formatCost(cost.dollars)}</span></div>
        ${cost.dollars > 0.20 ? `<div class="cost-warning-banner">Estimated cost above $0.20 — consider the cheaper model or proceed knowingly.</div>` : ""}
      `;
      // Re-render on model change
      document.getElementById("cost-model-pick").addEventListener("change", (e) => {
        renderForModel(e.target.value);
      });
    };
    renderForModel(defaultModel);
    dialog.hidden = false;

    // Confirm wiring — replace prior handler if any.
    const confirm = document.getElementById("cost-confirm");
    if (this._pendingConfirmHandler) {
      confirm.removeEventListener("click", this._pendingConfirmHandler);
    }
    this._pendingConfirmHandler = async () => {
      const model = document.getElementById("cost-model-pick").value;
      dialog.hidden = true;
      await this._performAnalysis({ entity, systemPrompt, userPrompt, model });
    };
    confirm.addEventListener("click", this._pendingConfirmHandler);
  },

  async _performAnalysis({ entity, systemPrompt, userPrompt, model }) {
    const panel = document.getElementById("flow-detail");
    if (!panel) return;
    panel.innerHTML = `
      <h3 class="md-title">${escapeHtml(entity.entity_id)}</h3>
      <p class="meta-line"><span class="badge ${entity.derived_state}">${entity.derived_state}</span> · ${escapeHtml(entity.entity_type)}</p>
      <div class="analyser-loading"><div class="spinner"></div>Analysing with <code>${escapeHtml(model)}</code>… this can take up to ~30 seconds.</div>
    `;
    const startedAt = Date.now();
    try {
      const result = await AnalyseClient.run({
        apiKey: Settings.apiKey,
        model,
        systemPrompt,
        userPrompt,
      });
      const elapsedMs = Date.now() - startedAt;
      this._renderResult(panel, entity, result, elapsedMs, { systemPrompt, userPrompt, model });
    } catch (e) {
      const isAnalyseError = e instanceof AnalyseError;
      const message = isAnalyseError ? e.userFacing() : (e.message || "Unknown error");
      const body = isAnalyseError && e.body ? e.body : "";
      this._renderError(panel, entity, message, body, { systemPrompt, userPrompt, model });
    }
  },

  _renderResult(panel, entity, result, elapsedMs, retryCtx) {
    const cost = result.usage.inputTokens || result.usage.outputTokens
      ? this._actualCostFromUsage(result.usage, result.model)
      : null;
    const headerParts = [
      `<span class="tag">analysed</span>`,
      `<code>${escapeHtml(result.model)}</code>`,
      `· ${result.usage.inputTokens.toLocaleString()} in / ${result.usage.outputTokens.toLocaleString()} out tokens`,
      cost !== null ? `· ${Estimator.formatCost(cost)}` : "",
      `· ${(elapsedMs / 1000).toFixed(1)}s`,
      `· <strong>ephemeral</strong> (not saved — Phase A)`,
    ];
    const parts = [];
    parts.push(`<h3 class="md-title">${escapeHtml(entity.entity_id)}</h3>`);
    parts.push(`<p class="meta-line"><span class="badge ${entity.derived_state}">${entity.derived_state}</span> · ${escapeHtml(entity.entity_type)}</p>`);
    parts.push(`<div class="analyser-result-header">${headerParts.filter(Boolean).join(" ")}</div>`);

    if (result.parseFailed) {
      parts.push(`<div class="analyser-error"><strong>Couldn't parse structured response.</strong>The model didn't return a valid JSON block. Freeform output shown below.</div>`);
    }

    parts.push(`<div class="analyser-toggle-row">
      <button class="active" data-show="structured">Structured</button>
      <button data-show="freeform">Freeform</button>
    </div>`);

    parts.push(`<div id="analyser-pane-structured">`);
    if (result.structured) {
      const s = result.structured;
      parts.push(this._renderSection("Outstanding", "outstanding", s.outstanding || []));
      parts.push(this._renderSection("Blocked", "blocked", s.blocked || []));
      parts.push(this._renderSection("Recently changed", "recently_changed", s.recently_changed || []));
      parts.push(this._renderNextMove(s.next_move || ""));
    } else {
      parts.push(`<p class="empty-section">No structured data — see freeform.</p>`);
    }
    parts.push(`</div>`);

    parts.push(`<div id="analyser-pane-freeform" hidden>`);
    const freeformHtml = result.freeform
      ? (window.marked && window.marked.parse ? window.marked.parse(result.freeform) : `<pre>${escapeHtml(result.freeform)}</pre>`)
      : `<p class="empty-section">No freeform analysis.</p>`;
    parts.push(`<div class="analyser-freeform">${freeformHtml}</div>`);
    parts.push(`</div>`);

    // Save row (Phase B). The button stays hidden if there's no structured output.
    const canSave = !!result.structured;
    parts.push(`<div class="analyser-toggle-row" id="analyser-action-row">
      ${canSave ? `<button class="btn-primary" id="btn-analyser-save" style="font-size:0.78rem">💾 Save</button>` : ""}
      <button class="btn-secondary" id="btn-analyser-rerun" style="font-size:0.78rem">↻ Re-analyse</button>
      <button class="btn-secondary" id="btn-analyser-back" style="font-size:0.78rem">← Back to timeline</button>
    </div>`);
    parts.push(`<div id="analyser-save-feedback"></div>`);

    panel.innerHTML = parts.join("");

    // Wire toggle + actions.
    panel.querySelectorAll(".analyser-toggle-row [data-show]").forEach(btn => {
      btn.addEventListener("click", () => {
        panel.querySelectorAll(".analyser-toggle-row [data-show]").forEach(b => b.classList.remove("active"));
        btn.classList.add("active");
        const show = btn.dataset.show;
        document.getElementById("analyser-pane-structured").hidden = (show !== "structured");
        document.getElementById("analyser-pane-freeform").hidden = (show !== "freeform");
      });
    });
    document.getElementById("btn-analyser-rerun")?.addEventListener("click", () => {
      this.startAnalysis(entity);
    });
    document.getElementById("btn-analyser-back")?.addEventListener("click", () => {
      showLiveStatus(entity);
    });
    document.getElementById("btn-analyser-save")?.addEventListener("click", () => {
      this._performSave({ panel, entity, result });
    });
  },

  async _performSave({ panel, entity, result }) {
    const fb = document.getElementById("analyser-save-feedback");
    const btn = document.getElementById("btn-analyser-save");
    if (btn) btn.disabled = true;
    if (fb) fb.innerHTML = `<div class="analyser-loading"><div class="spinner"></div>Saving…</div>`;

    try {
      // Pre-flight clean-check (server enforces it again, but this surfaces
      // the dirty list immediately).
      const cc = await PersistenceClient.cleanCheck();
      if (!cc.clean) {
        if (fb) fb.innerHTML = `<div class="analyser-error"><strong>Working tree dirty — commit or stash before saving.</strong><pre>${escapeHtml((cc.dirty_files || []).join("\n"))}</pre></div>`;
        if (btn) btn.disabled = false;
        return;
      }

      // Build the primary event.
      const structured = { ...result.structured };
      // Strip derived_summaries out of the primary's structured field — they
      // become their own events. The schema for analysis.live-summary doesn't
      // include derived_summaries as a key; carrying it in would fail validation.
      const derivedSummaries = Array.isArray(structured.derived_summaries) ? structured.derived_summaries : [];
      delete structured.derived_summaries;

      const primaryEvent = {
        entity_type: entity.entity_type,
        entity_id: entity.entity_id,
        attributes: {
          model: result.model,
          structured,
          estimated_input_tokens: null,
          estimated_output_tokens: null,
          actual_input_tokens: result.usage.inputTokens || null,
          actual_output_tokens: result.usage.outputTokens || null,
        },
      };
      const primaryFreeform = result.freeform || result.raw || "";

      // Build derived events (1 per derived_summaries entry, if any).
      const derived = derivedSummaries
        .filter(d => d && d.entity_id && d.entity_type)
        .map(d => {
          const dStructured = {
            outstanding: Array.isArray(d.outstanding) ? d.outstanding : [],
            blocked: Array.isArray(d.blocked) ? d.blocked : [],
            recently_changed: Array.isArray(d.recently_changed) ? d.recently_changed : [],
            next_move: typeof d.next_move === "string" ? d.next_move : "",
          };
          // Minimal freeform stub for derived: structured fields rendered as markdown.
          const stubMd = [
            `# Derived summary for ${d.entity_id}`,
            `(side-effect of primary analysis on ${entity.entity_id})`,
            "",
            "## Outstanding",
            ...(dStructured.outstanding.length ? dStructured.outstanding.map(s => `- ${s}`) : ["(none)"]),
            "",
            "## Blocked",
            ...(dStructured.blocked.length ? dStructured.blocked.map(s => `- ${s}`) : ["(none)"]),
            "",
            "## Recently changed",
            ...(dStructured.recently_changed.length ? dStructured.recently_changed.map(s => `- ${s}`) : ["(none)"]),
            "",
            "## Next move",
            dStructured.next_move || "(none)",
          ].join("\n");
          return {
            event: {
              entity_type: d.entity_type,
              entity_id: d.entity_id,
              attributes: {
                model: result.model,
                structured: dStructured,
              },
            },
            freeform_md: stubMd,
          };
        });

      const resp = await PersistenceClient.saveSummary({
        primary: { event: primaryEvent, freeform_md: primaryFreeform },
        derived,
      });

      if (fb) {
        const derivedCount = (resp.derived_event_ids || []).length;
        fb.innerHTML = `<div class="analyser-saved-banner">
          Saved · <code>${escapeHtml(resp.primary_event_id)}</code>
          ${derivedCount > 0 ? `· +${derivedCount} derived` : ""}
          <br><span class="hint">Reload to see this as the default sidebar view.</span>
        </div>`;
      }
      // Replace the Save button with a small "Saved" indicator + jump to saved view.
      if (btn) {
        btn.disabled = true;
        btn.textContent = "✓ Saved";
      }
    } catch (e) {
      const message = e instanceof PersistenceError ? e.userFacing() : (e.message || "Save failed");
      const detail = (e && e.dirty_files) ? `\n${(e.dirty_files || []).join("\n")}`
                  : (e && e.errors) ? `\n${(e.errors || []).join("\n")}`
                  : "";
      if (fb) {
        fb.innerHTML = `<div class="analyser-error"><strong>${escapeHtml(message)}</strong>${detail ? `<pre>${escapeHtml(detail)}</pre>` : ""}</div>`;
      }
      if (btn) btn.disabled = false;
    }
  },

  _actualCostFromUsage(usage, model) {
    const p = Estimator.priceFor(model);
    return (usage.inputTokens * p.in + usage.outputTokens * p.out) / 1_000_000;
  },

  _renderSection(label, key, items) {
    if (!items.length) {
      return `<div class="summary-card section-${key}"><h4>${escapeHtml(label)}</h4><p class="empty-section">(none)</p></div>`;
    }
    const lis = items.map(it => `<li>${escapeHtml(String(it))}</li>`).join("");
    return `<div class="summary-card section-${key}"><h4>${escapeHtml(label)}</h4><ul>${lis}</ul></div>`;
  },
  _renderNextMove(text) {
    if (!text) {
      return `<div class="summary-card section-next_move"><h4>Next move</h4><p class="empty-section">(none — entity may be complete or dormant)</p></div>`;
    }
    return `<div class="summary-card section-next_move"><h4>Next move</h4><p class="next-move-text">${escapeHtml(text)}</p></div>`;
  },

  _renderError(panel, entity, message, body, retryCtx) {
    const parts = [];
    parts.push(`<h3 class="md-title">${escapeHtml(entity.entity_id)}</h3>`);
    parts.push(`<p class="meta-line"><span class="badge ${entity.derived_state}">${entity.derived_state}</span> · ${escapeHtml(entity.entity_type)}</p>`);
    parts.push(`<div class="analyser-error">`);
    parts.push(`<strong>Analysis failed</strong>${escapeHtml(message)}`);
    if (body) {
      parts.push(`<pre>${escapeHtml(body.slice(0, 1500))}</pre>`);
    }
    parts.push(`<div class="retry-row">`);
    if (retryCtx) {
      parts.push(`<button class="btn-primary" id="btn-analyser-retry" style="font-size:0.78rem">Retry</button> `);
    }
    parts.push(`<button class="btn-secondary" id="btn-analyser-back" style="font-size:0.78rem">Back to timeline</button>`);
    parts.push(`</div></div>`);
    panel.innerHTML = parts.join("");
    document.getElementById("btn-analyser-retry")?.addEventListener("click", () => {
      this._performAnalysis({ ...retryCtx, entity });
    });
    document.getElementById("btn-analyser-back")?.addEventListener("click", () => {
      showLiveStatus(entity);
    });
  },
};

// ===========================================================================
// === Global update mode (Phase E — T3-analyser-phase-e-global-mode) ========
// ===========================================================================
// Three modules:
//   GlobalContextBuilder  — assembles the project-level shared prefix once
//   GlobalAnalyseClient   — per-entity follow-on call with cache_control
//   GlobalAnalyser        — UI controller: button → dialog → progress modal
//
// Derived-summary emission is suppressed in this mode (every entity gets a
// primary anyway, no point producing weaker derived shadows of them).

const GlobalContextBuilder = {
  async buildSharedPrompt(projection, events) {
    // 1. T1-top-level markdown (project's why/what — the most stable, largest,
    //    most-cacheable input).
    let t1md = "";
    try {
      const res = await fetch("../../planning/T1-top-level.md");
      if (res.ok) t1md = stripFrontmatter(await res.text()).trim();
    } catch { /* tolerate */ }

    // 2. Live entities index.
    const liveEntities = Object.values(projection.entities)
      .filter(e => e.derived_state === "live")
      .sort((a, b) => a.entity_id.localeCompare(b.entity_id));
    const liveIndex = liveEntities.map(e => {
      const a = e.attributes || {};
      const tier = a.tier ? `T${a.tier}` : (a.plan_kind === "milestone" ? `M${a.milestone_index}` : "");
      const sum = (a.summary || a.title || "").slice(0, 140);
      return `- ${e.entity_id} (${e.entity_type}${tier ? "/" + tier : ""}, live): ${sum}`;
    });

    // 3. Project-wide recent event stream (last 50 events, excluding analysis.* +
    //    commit.recorded which is metadata).
    const recent = events
      .filter(ev => !ev.type.startsWith("analysis.") && ev.type !== "commit.recorded")
      .slice(-50)
      .map(ev => `- ${ev.type} on ${ev.entity_type}:${ev.entity_id}: ${((ev.attributes && (ev.attributes.summary || ev.attributes.note || ev.attributes.text || ev.attributes.title)) || "").slice(0, 180)}`);

    const lines = [];
    lines.push("# Shared project context (used for every entity in this global pass)");
    lines.push("");
    lines.push("## T1 — top-level plan");
    lines.push("");
    lines.push(t1md || "(could not load T1)");
    lines.push("");
    lines.push("## Live entities index");
    lines.push(...liveIndex);
    lines.push("");
    lines.push("## Recent project-wide event stream (last 50 events)");
    lines.push(...recent);
    return { sharedPrompt: lines.join("\n"), liveEntities };
  },

  systemPrompt() {
    return [
      "You are doing a GLOBAL pass over a planning-driven, event-sourced project.",
      "For each entity you're focused on in turn, answer: 'what is outstanding here?'",
      "",
      "Output format — EXACTLY this shape:",
      "1. A fenced JSON code block tagged ```json with this schema (no extra keys):",
      "{",
      '  "outstanding": ["specific items still to do, one short string each"],',
      '  "blocked": ["items blocked by external dependencies or open HITL"],',
      '  "recently_changed": ["state changes captured in the most recent events"],',
      '  "next_move": "single most actionable next step (one sentence)"',
      "}",
      "",
      "2. Immediately after, a '## Freeform analysis' h2 header followed by markdown prose: under 400 words.",
      "",
      "Rules:",
      "- Reference entities/events by id when relevant.",
      "- Use the shared context (T1 + live index + recent events) to ground your answer about THE FOCAL entity.",
      "- Do not hedge with 'I don't have access to X' — you have the shared context plus the focal's own plan + timeline.",
      "- This is a global pass — DO NOT output `derived_summaries`. Each entity is being analysed as a primary in its own right.",
      "- Output JSON before prose, always.",
    ].join("\n");
  },

  async buildPerEntityTail(entity) {
    // Per-entity portion — small, varies per call. Plan body + timeline +
    // 1-hop graph + prior valid summary.
    const bundle = await ContextBuilder.buildPerEntityBundle(entity);
    // Reuse the per-entity serialiser but trim its preamble since the shared
    // context already framed the project.
    const lines = [];
    lines.push(`# Now focus on entity: ${entity.entity_id}`);
    lines.push("");
    const f = bundle.focal;
    lines.push(`- type: ${f.type}${f.plan_kind ? ` (${f.plan_kind})` : ""}${f.tier ? ` · T${f.tier}` : ""}`);
    lines.push(`- derived state: ${f.derived_state}`);
    lines.push("");
    lines.push(`## Plan markdown for ${f.id}`);
    lines.push(f.plan_md || "(empty)");
    lines.push("");
    lines.push(`## Full event timeline for ${f.id}`);
    if (!f.events.length) lines.push("(no events)");
    else for (const ev of f.events) {
      lines.push(`- **${ev.type}** by ${ev.actor || "?"}: ${(ev.summary || "").slice(0, 500)}`);
    }
    lines.push("");
    lines.push(`## Related entities (1-hop)`);
    if (!bundle.related_1hop.length) lines.push("(none)");
    else for (const r of bundle.related_1hop) {
      lines.push(`- **${r.id}** (${r.kind}/${r.plan_kind || "?"}, ${r.derived_state}): ${r.one_liner}`);
    }
    lines.push("");
    lines.push(`## Prior analyser summary on ${f.id}`);
    const ps = bundle.prior_summary;
    if (!ps) lines.push("(none)");
    else {
      const s = ps.structured || {};
      lines.push(`(${ps.source || "?"}, ${ps.model || "?"})`);
      lines.push(`Outstanding: ${(s.outstanding || []).join("; ")}`);
      lines.push(`Blocked: ${(s.blocked || []).join("; ")}`);
      lines.push(`Recently changed: ${(s.recently_changed || []).join("; ")}`);
      lines.push(`Next move: ${s.next_move || ""}`);
    }
    return lines.join("\n");
  },
};

const GlobalAnalyseClient = {
  async runOne({ apiKey, model, sharedPrompt, perEntityPrompt, systemPrompt, maxTokens = 2048 }) {
    const body = {
      model,
      max_tokens: maxTokens,
      system: systemPrompt,
      messages: [{
        role: "user",
        content: [
          // The big shared prefix — marked for ephemeral caching. Anthropic
          // caches blocks >= 1024 tokens for 5 minutes by default.
          { type: "text", text: sharedPrompt, cache_control: { type: "ephemeral" } },
          // Per-entity tail — varies each call.
          { type: "text", text: perEntityPrompt },
        ],
      }],
    };
    let res;
    try {
      res = await fetch(AnalyseClient.ENDPOINT, {
        method: "POST",
        headers: {
          "x-api-key": apiKey,
          "anthropic-version": AnalyseClient.API_VERSION,
          "anthropic-dangerous-direct-browser-access": "true",
          "content-type": "application/json",
        },
        body: JSON.stringify(body),
      });
    } catch (e) {
      throw new AnalyseError("network", `Network error: ${e.message}`, null);
    }
    if (!res.ok) {
      let bodyText = "";
      try { bodyText = await res.text(); } catch {}
      const code = res.status === 401 ? "auth"
                 : res.status === 429 ? "rate-limit"
                 : res.status >= 500 ? "server"
                 : "http";
      throw new AnalyseError(code, `Anthropic API HTTP ${res.status}`, bodyText, res.headers);
    }
    const data = await res.json();
    const text = (data.content || []).filter(c => c.type === "text").map(c => c.text).join("\n");
    const u = data.usage || {};
    const inputTokens = u.input_tokens || 0;
    const cacheRead = u.cache_read_input_tokens || 0;
    const cacheCreate = u.cache_creation_input_tokens || 0;
    return {
      raw: text,
      ...AnalyseClient._parseStructured(text),
      usage: {
        inputTokens,
        outputTokens: u.output_tokens || 0,
        cacheRead,
        cacheCreate,
        cacheHitRatio: inputTokens > 0 ? cacheRead / (inputTokens + cacheRead) : 0,
      },
      model,
    };
  },
};

const GlobalAnalyser = {
  _cancelled: false,
  _running: false,

  initToolbarButton() {
    const btn = document.getElementById("btn-global-analyse");
    if (!btn) return;
    const refresh = () => {
      btn.disabled = !Settings.hasKey();
      btn.title = Settings.hasKey()
        ? "Analyse every live entity in one sweep (Anthropic prompt caching). Token-heavy."
        : "Configure API key in settings first";
    };
    refresh();
    btn.addEventListener("click", () => this.start());
    // Hook into Settings.refreshPill — but simpler: refresh on a small interval.
    // (No event from Settings; we'd need to wire one. Cheap to refresh on demand.)
    document.addEventListener("click", refresh);
  },

  async start() {
    if (this._running) return;
    if (!Settings.hasKey()) { Settings.openModal(); return; }
    const model = ModelCatalog.defaultId(await ModelCatalog.list());
    if (!model) { alert("No usable model found for this API key (GET /v1/models returned nothing). Check the key in settings."); return; }

    // Pre-flight clean tree.
    try {
      const cc = await PersistenceClient.cleanCheck();
      if (!cc.clean) {
        alert("Working tree dirty — commit or stash before running global analysis.\n\n" + (cc.dirty_files || []).join("\n"));
        return;
      }
    } catch (e) {
      alert("Clean-check failed: " + (e.message || e));
      return;
    }

    // Build shared context.
    const { sharedPrompt, liveEntities } = await GlobalContextBuilder.buildSharedPrompt(state.projection, state.events);
    const systemPrompt = GlobalContextBuilder.systemPrompt();

    // Estimate cost: per-entity tail varies but average ~1500 input tokens;
    // shared block billed once at full rate, then cached-read rate (~10% of full).
    const sharedTok = Estimator.estimateTokensFromText(systemPrompt + "\n" + sharedPrompt);
    const perTailEstimate = 1500;
    const perOutputEstimate = 1500;
    const p = Estimator.priceFor(model);
    const firstCallIn = sharedTok + perTailEstimate;
    const subsequentCallIn = perTailEstimate + sharedTok * 0.1;  // cache-read rate (~10% rough)
    const nEnts = liveEntities.length;
    const inputDollarsApprox =
      (firstCallIn * p.in + Math.max(0, nEnts - 1) * subsequentCallIn * p.in) / 1_000_000;
    const outputDollarsApprox = (nEnts * perOutputEstimate * p.out) / 1_000_000;
    const totalDollars = inputDollarsApprox + outputDollarsApprox;

    // Confirm dialog.
    const dialog = document.getElementById("cost-dialog");
    const body = document.getElementById("cost-dialog-body");
    document.getElementById("cost-dialog-title").textContent = "Confirm GLOBAL analysis";
    body.innerHTML = `
      <p class="modal-hint" style="background:#fff3cd;color:#5d4400">
        <strong>This will analyse every live entity in one sweep.</strong>
        It's token-heavy. The shared project context is cached after the first call,
        so calls 2..N cost ~10% of input on the shared portion. Estimates assume an
        80% cache-hit ratio on input.
      </p>
      <div class="cost-line"><span class="cost-label">Live entities</span><span class="cost-value">${nEnts}</span></div>
      <div class="cost-line"><span class="cost-label">Model</span><span class="cost-value"><code>${escapeHtml(model)}</code></span></div>
      <div class="cost-line"><span class="cost-label">Shared prefix tokens</span><span class="cost-value">~${sharedTok.toLocaleString()}</span></div>
      <div class="cost-line"><span class="cost-label">Estimated input cost</span><span class="cost-value">${Estimator.formatCost(inputDollarsApprox)}</span></div>
      <div class="cost-line"><span class="cost-label">Estimated output cost</span><span class="cost-value">${Estimator.formatCost(outputDollarsApprox)}</span></div>
      <div class="cost-line cost-total"><span class="cost-label">Estimated total</span><span class="cost-value">${Estimator.formatCost(totalDollars)}</span></div>
      <div class="cost-warning-banner">Click "Confirm and run" to start. Each per-entity result saves to events.jsonl + a markdown file. Cancel mid-run is supported.</div>
    `;
    const confirmBtn = document.getElementById("cost-confirm");
    confirmBtn.textContent = "Confirm and run global";
    confirmBtn.classList.remove("btn-primary");
    confirmBtn.classList.add("btn-danger");

    // Wire confirm once.
    const handler = async () => {
      dialog.hidden = true;
      confirmBtn.textContent = "Confirm and run";
      confirmBtn.classList.remove("btn-danger");
      confirmBtn.classList.add("btn-primary");
      confirmBtn.removeEventListener("click", handler);
      await this._runLoop({ liveEntities, sharedPrompt, systemPrompt, model });
    };
    confirmBtn.addEventListener("click", handler);
    dialog.hidden = false;
  },

  async _runLoop({ liveEntities, sharedPrompt, systemPrompt, model }) {
    this._running = true;
    this._cancelled = false;
    const modal = document.getElementById("global-modal");
    const body = document.getElementById("global-modal-body");
    const totalsEl = document.getElementById("global-running-totals");
    const cancelBtn = document.getElementById("global-cancel-run");
    const closeBtn = document.getElementById("global-close");

    cancelBtn.hidden = false;
    closeBtn.hidden = true;
    cancelBtn.onclick = () => { this._cancelled = true; };

    // Render initial progress table.
    const rows = liveEntities.map(e => ({
      entity: e,
      status: "queued",
      cost: null,
      cacheHit: null,
      eventId: null,
      error: null,
    }));
    const renderTable = () => {
      body.innerHTML = `
        <table class="global-progress-table">
          <thead>
            <tr><th>Entity</th><th>Status</th><th>Cost</th><th>Cache hit</th><th>Result</th></tr>
          </thead>
          <tbody>
            ${rows.map(r => `
              <tr class="global-row global-status-${r.status}">
                <td><code>${escapeHtml(r.entity.entity_id)}</code></td>
                <td class="status-cell">${r.status}</td>
                <td>${r.cost != null ? Estimator.formatCost(r.cost) : "—"}</td>
                <td>${r.cacheHit != null ? `${(r.cacheHit * 100).toFixed(0)}%` : "—"}</td>
                <td>${r.eventId ? `<code>${escapeHtml(r.eventId.slice(0, 8))}…</code>` : r.error ? `<span style="color:#b71c1c">${escapeHtml(r.error)}</span>` : "—"}</td>
              </tr>
            `).join("")}
          </tbody>
        </table>
      `;
    };
    const updateTotals = () => {
      const saved = rows.filter(r => r.status === "saved").length;
      const failed = rows.filter(r => r.status === "failed").length;
      const total = rows.reduce((s, r) => s + (r.cost || 0), 0);
      const avgCache = rows.filter(r => r.cacheHit != null).reduce((s, r, _, a) => s + r.cacheHit / a.length, 0);
      totalsEl.textContent = `${saved}/${rows.length} saved · ${failed} failed · cost so far ${Estimator.formatCost(total)} · avg cache-hit ${(avgCache * 100).toFixed(0)}%`;
    };
    renderTable();
    updateTotals();
    modal.hidden = false;

    for (let i = 0; i < rows.length; i++) {
      if (this._cancelled) break;
      const row = rows[i];
      row.status = "running";
      renderTable(); updateTotals();

      // Clean-tree re-check (skip on first iteration since we already did pre-flight).
      if (i > 0) {
        try {
          const cc = await PersistenceClient.cleanCheck();
          if (!cc.clean) {
            row.status = "failed";
            row.error = "tree went dirty mid-run";
            renderTable(); updateTotals();
            break;
          }
        } catch { /* tolerate, proceed */ }
      }

      try {
        const perEntityPrompt = await GlobalContextBuilder.buildPerEntityTail(row.entity);
        const result = await GlobalAnalyseClient.runOne({
          apiKey: Settings.apiKey,
          model,
          sharedPrompt,
          perEntityPrompt,
          systemPrompt,
        });
        if (!result.structured) throw new Error("model didn't return parseable JSON");

        const primaryEvent = {
          entity_type: row.entity.entity_type,
          entity_id: row.entity.entity_id,
          attributes: {
            model,
            structured: result.structured,
            actual_input_tokens: result.usage.inputTokens,
            actual_output_tokens: result.usage.outputTokens,
            prompt_cache_hit_ratio: result.usage.cacheHitRatio,
            cache_read_input_tokens: result.usage.cacheRead,
            cache_creation_input_tokens: result.usage.cacheCreate,
          },
        };
        const md = result.freeform || result.raw;
        const resp = await PersistenceClient.saveSummary({
          primary: { event: primaryEvent, freeform_md: md },
          derived: [],  // Phase E: derived suppressed.
        });
        row.status = "saved";
        row.eventId = resp.primary_event_id;
        row.cost = (result.usage.inputTokens * Estimator.priceFor(model).in +
                    result.usage.outputTokens * Estimator.priceFor(model).out) / 1_000_000;
        row.cacheHit = result.usage.cacheHitRatio;
      } catch (e) {
        row.status = "failed";
        row.error = e instanceof AnalyseError ? e.userFacing()
                  : e instanceof PersistenceError ? e.userFacing()
                  : (e.message || "unknown");
      }
      renderTable(); updateTotals();
    }

    this._running = false;
    cancelBtn.hidden = true;
    closeBtn.hidden = false;
    closeBtn.onclick = () => { modal.hidden = true; };
  },
};

// ===========================================================================
// === End Phase E ===========================================================
// ===========================================================================

// --- Modal close wiring (Esc + backdrop + × button) -------------------------

function initModalCloseHandlers() {
  document.querySelectorAll(".modal-close").forEach(btn => {
    btn.addEventListener("click", () => {
      const id = btn.dataset.close;
      const m = document.getElementById(id);
      if (m) m.hidden = true;
    });
  });
  // Click backdrop (outside .modal) closes
  document.querySelectorAll(".modal-backdrop").forEach(bd => {
    bd.addEventListener("click", (e) => {
      if (e.target === bd) bd.hidden = true;
    });
  });
  // Esc closes any open modal
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      document.querySelectorAll(".modal-backdrop").forEach(bd => {
        if (!bd.hidden) bd.hidden = true;
      });
    }
  });
  // Cost dialog cancel button is just a close.
  document.getElementById("cost-cancel")?.addEventListener("click", () => {
    document.getElementById("cost-dialog").hidden = true;
  });
}

// ===========================================================================
// === End analyser modules ==================================================
// ===========================================================================

// Initialise analyser surfaces once DOM is parsed.
function initAnalyser() {
  Settings.initToolbarPill();
  Settings.initModal();
  initModalCloseHandlers();
  GlobalAnalyser.initToolbarButton();
}

// main() is defined at the top of the file; it calls initAnalyser() before
// loading projection/events.

main();
