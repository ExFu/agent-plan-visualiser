// agent-plan-tracker — HTML view
// Three views: Entity state board, Plan hierarchy tree, Workstreams flow.
// Pure SVG + vanilla JS. No external dependencies. No build step.

const PROJECTION_PATH = "../../.agent-plan-tracker/projection.json";
const EVENTS_PATH = "../../.agent-plan-tracker/events.jsonl";

const state = {
  projection: null,
  events: null,
  currentView: "board",
  flowMode: "milestone", // "milestone" | "t2"
};

// ---------------------------------------------------------------------------
// Bootstrap
// ---------------------------------------------------------------------------

async function main() {
  try {
    const [pRes, eRes] = await Promise.all([
      fetch(PROJECTION_PATH),
      fetch(EVENTS_PATH),
    ]);
    if (!pRes.ok) throw new Error(`projection.json: HTTP ${pRes.status}`);
    if (!eRes.ok) throw new Error(`events.jsonl: HTTP ${eRes.status}`);
    state.projection = await pRes.json();
    const eText = await eRes.text();
    state.events = eText.trim().split("\n").filter(Boolean).map(line => JSON.parse(line));
  } catch (e) {
    document.getElementById("content").innerHTML =
      `<p>Failed to load data: ${escapeHtml(e.message)}</p>
       <p>If you're opening this from <code>file://</code>, your browser may block fetch.
       Serve from the repo root with <code>python3 -m http.server 8765</code> and open
       <code>http://localhost:8765/agent-plan-tracker/view/index.html</code> instead.</p>
       <p>Also confirm the pipeline has run:
       <code>python3 agent-plan-tracker/scripts/projection-emit.py</code>.</p>`;
    return;
  }

  document.getElementById("meta").textContent =
    `Generated ${state.projection.generated_at} · ` +
    `${state.projection.summary_stats.total_events} events · ` +
    `${state.projection.summary_stats.live_count} live · ` +
    `${state.projection.summary_stats.dormant_count} dormant · ` +
    `${state.projection.summary_stats.dead_count} dead · ` +
    `${state.projection.summary_stats.orphaned_count} orphaned`;

  document.getElementById("btn-board").addEventListener("click", () => switchView("board"));
  document.getElementById("btn-tree").addEventListener("click", () => switchView("tree"));
  document.getElementById("btn-flow").addEventListener("click", () => switchView("flow"));

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
  const states = ["live", "dormant", "orphaned", "unknown", "dead"];
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
  // Sub-mode toggle
  const sub = document.createElement("div");
  sub.className = "sub-toolbar";
  for (const [mode, label] of [
    ["milestone", "Milestone swimlanes"],
    ["t2", "T2-domain swimlanes"],
  ]) {
    const b = document.createElement("button");
    b.textContent = label;
    if (mode === state.flowMode) b.classList.add("active");
    b.addEventListener("click", () => {
      state.flowMode = mode;
      switchView("flow");
    });
    sub.appendChild(b);
  }
  content.appendChild(sub);

  // Legend
  const legend = document.createElement("div");
  legend.className = "flow-legend";
  legend.innerHTML = `
    <strong>Legend:</strong>
    <span><svg width="14" height="14"><circle cx="7" cy="7" r="5" fill="#c2185b"/></svg> created</span>
    <span><svg width="14" height="14"><circle cx="7" cy="7" r="5" fill="#1565c0"/></svg> extended</span>
    <span><svg width="14" height="14"><circle cx="7" cy="7" r="5" fill="#ef6c00"/></svg> progressed</span>
    <span><svg width="14" height="14"><circle cx="7" cy="7" r="5" fill="#1b5e20"/></svg> completed</span>
    <span><svg width="14" height="14"><circle cx="7" cy="7" r="5" fill="#c62828"/></svg> fulcrum (parked/cancelled/etc.)</span>
    <span style="margin-left:1rem;color:#666;">solid line = entity spine · dashed = spawns · dotted = live continuation to "now" (click LIVE badge for timeline)</span>
  `;
  content.appendChild(legend);

  // Compute layout
  const layout = computeFlowLayout(projection, events, state.flowMode);

  // Two-pane split: SVG + drag handle + sidebar
  const split = document.createElement("div");
  split.className = "flow-split";

  const svgWrap = document.createElement("div");
  svgWrap.className = "flow-svg-wrap";
  svgWrap.appendChild(renderFlowSVG(layout));
  split.appendChild(svgWrap);

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

function computeFlowLayout(projection, events, mode) {
  const LEFT_MARGIN = 230;
  const TOP_MARGIN = 110;
  const COMMIT_WIDTH = 150;
  const NOW_COLUMN_WIDTH = 180;
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

  // 3. Group events by entity (excluding meta / non-entity events).
  const entityEvents = {};
  for (const ev of events) {
    if (!ev.entity_id || !ev.entity_type) continue;
    const key = `${ev.entity_type}:${ev.entity_id}`;
    (entityEvents[key] ||= []).push(ev);
  }

  // 4. Assign entities to swimlanes.
  const entities = projection.entities;
  const swimlaneEntities = {};
  const swimlaneOrder = [];

  for (const [ekey, entity] of Object.entries(entities)) {
    const sl = swimlaneKey(entity, mode);
    if (!swimlaneEntities[sl]) {
      swimlaneEntities[sl] = [];
      swimlaneOrder.push(sl);
    }
    swimlaneEntities[sl].push(ekey);
  }

  // Sort swimlane order by priority.
  const priorityOrder = mode === "milestone"
    ? ["_spine_t1", "_spine_t2", "_milestones", "_other", "_inbox"]
    : ["_t1_root", "_t2_themselves", "T2-ontology", "T2-storage", "T2-projection", "T2-packaging", "T2-extraction", "T2-ingest", "_milestones", "_inbox", "_other"];

  swimlaneOrder.sort((a, b) => {
    const ai = priorityOrder.indexOf(a);
    const bi = priorityOrder.indexOf(b);
    if (ai === -1 && bi === -1) {
      // For milestone mode, M1/M2/M3 should be in numeric order.
      if (mode === "milestone" && a.startsWith("M") && b.startsWith("M")) {
        return a.localeCompare(b, undefined, { numeric: true });
      }
      return a.localeCompare(b);
    }
    if (ai === -1) return 1;
    if (bi === -1) return -1;
    return ai - bi;
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

  // 6. Y-position each entity and compute swimlane spans.
  const entityRow = {}; // entity_key -> y
  const swimlaneSpans = [];
  let y = TOP_MARGIN;
  for (const sl of swimlaneOrder) {
    const slTop = y;
    y += 30; // top-band for swimlane label, then entities below
    const ents = swimlaneEntities[sl];
    for (const ek of ents) {
      entityRow[ek] = y + ROW_HEIGHT / 2;
      y += ROW_HEIGHT;
    }
    y += SWIMLANE_PADDING;
    swimlaneSpans.push({
      key: sl,
      label: swimlaneLabel(sl, mode),
      top: slTop,
      bottom: y - SWIMLANE_PADDING / 2,
      entities: ents,
    });
  }
  const totalHeight = y + 20;
  const nowX = LEFT_MARGIN + commits.length * COMMIT_WIDTH + NOW_COLUMN_WIDTH / 2;
  const totalWidth = LEFT_MARGIN + commits.length * COMMIT_WIDTH + NOW_COLUMN_WIDTH;

  // 7. Compute composite nodes: one per (entity, commit) intersection.
  const nodes = [];
  const entityNodes = {};
  for (const [ekey, evs] of Object.entries(entityEvents)) {
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

  // 8. Relationship edges (spawns).
  const relEdges = [];
  for (const r of (projection.relationships || []).filter(r => r.type === "spawns")) {
    const fns = entityNodes[r.from];
    const tns = entityNodes[r.to];
    if (!fns || !tns) continue;
    // From the source's first node, to the target's first node.
    relEdges.push({ from: fns[0], to: tns[0] });
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
    nodes, entityNodes, relEdges, continuations, nowBadges,
    swimlaneSpans, commits, commitMap,
    LEFT_MARGIN, TOP_MARGIN, COMMIT_WIDTH, NOW_COLUMN_WIDTH, ROW_HEIGHT, NODE_RADIUS,
    nowX, totalWidth, totalHeight,
  };
}

function swimlaneKey(entity, mode) {
  const a = entity.attributes || {};
  if (mode === "milestone") {
    if (entity.entity_type === "inbox-item") return "_inbox";
    if (a.plan_kind === "milestone") return "_milestones";
    if (a.milestone) return a.milestone;
    if (a.tier === 1) return "_spine_t1";
    if (a.tier === 2) return "_spine_t2";
    return "_other";
  } else {
    if (entity.entity_type === "inbox-item") return "_inbox";
    if (a.plan_kind === "milestone") return "_milestones";
    if (a.t2_parent) return a.t2_parent;
    if (a.tier === 2) return "_t2_themselves";
    if (a.tier === 1) return "_t1_root";
    return "_other";
  }
}

function swimlaneLabel(key, mode) {
  const labels = {
    "_inbox": "Inbox items",
    "_milestones": "Milestone plans (Mn)",
    "_spine_t1": "T1 (main spine)",
    "_spine_t2": "T2s without milestone tag",
    "_t1_root": "T1 root",
    "_t2_themselves": "T2 plans (themselves)",
    "_other": "Other",
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
  if (types.has("entity.created")) return "#c2185b";
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

  // Swimlane backgrounds
  const swG = createNS("g", { class: "swimlanes" });
  layout.swimlaneSpans.forEach((sl, i) => {
    swG.appendChild(createNS("rect", {
      class: `swimlane-band ${i % 2 === 0 ? "even" : "odd"}`,
      x: 0, y: sl.top,
      width: layout.totalWidth,
      height: sl.bottom - sl.top,
    }));
    swG.appendChild(textNS({
      class: "swimlane-label",
      x: 12, y: sl.top + 22,
    }, sl.label));
    // Per-entity sub-label
    for (const ek of sl.entities) {
      const yMid = layout.entityNodes[ek]?.[0]?.y;
      if (yMid === undefined) {
        // Compute from entityRow approximation: skip if unknown
        continue;
      }
      // entity short label on the left, full id available via <title>
      const entity = state.projection.entities[ek];
      const short = entity.entity_id.length > 28 ? entity.entity_id.slice(0, 26) + "…" : entity.entity_id;
      const labelEl = textNS({
        class: "entity-label",
        x: 28, y: yMid + 3,
      }, short);
      const titleEl = createNS("title");
      titleEl.textContent = entity.entity_id + " (click to open)";
      labelEl.appendChild(titleEl);
      labelEl.addEventListener("click", () => showPlanMarkdown(entity));
      swG.appendChild(labelEl);
    }
  });
  svg.appendChild(swG);

  // Commit column guides + rotated labels at top
  const colG = createNS("g", { class: "columns" });
  for (const c of layout.commits) {
    const x = layout.LEFT_MARGIN + c.idx * layout.COMMIT_WIDTH + layout.COMMIT_WIDTH / 2;
    colG.appendChild(createNS("line", {
      class: "commit-column",
      x1: x, y1: layout.TOP_MARGIN - 5,
      x2: x, y2: layout.totalHeight - 10,
    }));
    const g = createNS("g", {
      transform: `translate(${x},${layout.TOP_MARGIN - 12}) rotate(-28)`,
    });
    const truncated = c.message.length > 42 ? c.message.slice(0, 42) + "…" : c.message;
    g.appendChild(textNS({
      class: "commit-label",
      x: 0, y: 0,
      "text-anchor": "start",
    }, truncated));
    colG.appendChild(g);
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

  return svg;
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

function showDetail(n) {
  const panel = document.getElementById("flow-detail");
  if (!panel) return;
  const parts = [];
  parts.push(`<h3 class="md-title">${escapeHtml(n.entity.entity_id)}</h3>`);
  parts.push(`<p class="detail-commit"><strong>Commit:</strong> ${escapeHtml(n.commitMessage)}<br><span class="detail-date">${escapeHtml(n.commitDate)}</span></p>`);
  parts.push(`<p>${n.eventCount} event(s) in this commit for this entity:</p>`);
  parts.push("<ul class='event-list'>");
  for (const ev of n.events) {
    parts.push(renderEventLi(ev));
  }
  parts.push("</ul>");
  panel.innerHTML = parts.join("");
}

function renderEventLi(ev) {
  const kind = eventTypeKind(ev.type);
  const summary = ev.attributes?.summary || ev.attributes?.note || ev.attributes?.text || ev.attributes?.title || "(no summary)";
  const trunc = summary.length > 320 ? summary.slice(0, 320) + "…" : summary;
  return `<li><span class="event-pill event-pill-${kind}">${escapeHtml(ev.type)}</span><div class="event-summary">${escapeHtml(trunc)}</div></li>`;
}

async function showLiveStatus(entity) {
  const panel = document.getElementById("flow-detail");
  if (!panel) return;
  // Filter events.jsonl for this entity, in order.
  const myEvents = state.events.filter(
    ev => ev.entity_type === entity.entity_type && ev.entity_id === entity.entity_id
  );
  const last = myEvents[myEvents.length - 1];

  const parts = [];
  parts.push(`<h3 class="md-title">${escapeHtml(entity.entity_id)}</h3>`);
  parts.push(`<p class="meta-line"><span class="badge ${entity.derived_state}">${entity.derived_state}</span> · ${escapeHtml(entity.entity_type)} · ${myEvents.length} event${myEvents.length === 1 ? '' : 's'} total</p>`);
  parts.push(`<p class="hint">Showing the entity's full event timeline. For deep "what's outstanding?" analysis, see the proposed Claude-backed endpoint in the inbox (<code>2026-05-27.outstanding-work-analyser-endpoint</code>).</p>`);
  parts.push("<h4>Timeline</h4>");
  parts.push("<ul class='event-list'>");
  for (const ev of myEvents) {
    parts.push(renderEventLi(ev));
  }
  parts.push("</ul>");
  // Plus a "see full plan" affordance
  if (entity.entity_type === "plan" || entity.entity_type === "inbox-item") {
    parts.push(`<p class="hint"><a href="#" id="open-plan-from-live">→ Open the full plan/inbox markdown</a></p>`);
  }
  panel.innerHTML = parts.join("");
  const linkEl = document.getElementById("open-plan-from-live");
  if (linkEl) {
    linkEl.addEventListener("click", (e) => {
      e.preventDefault();
      showPlanMarkdown(entity);
    });
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
    sidebar.style.width = newWidth + "px";
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

main();
