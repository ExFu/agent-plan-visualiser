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
  attachReadMoreToggles(panel);
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
  // Plus a "see full plan" affordance
  if (entity.entity_type === "plan" || entity.entity_type === "inbox-item") {
    parts.push(`<p class="hint"><a href="#" id="open-plan-from-live">→ Open the full plan/inbox markdown</a></p>`);
  }
  panel.innerHTML = parts.join("");
  attachReadMoreToggles(panel);

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
    document.getElementById("settings-default-model").value = this.defaultModel;
    modal.hidden = false;
  },
  closeModal() {
    const modal = document.getElementById("settings-modal");
    if (modal) modal.hidden = true;
  },

  initModal() {
    const saveBtn = document.getElementById("settings-save");
    const clearBtn = document.getElementById("settings-clear");
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

// --- Estimator --------------------------------------------------------------
// Char-count proxy: ~4 chars/token (English-heavy text). ±15-25% accuracy.
// Pricing baked in for v1; verify against Anthropic public pricing periodically.

const Estimator = {
  // USD per million tokens — keep in sync with anthropic.com/pricing.
  PRICING: {
    "claude-sonnet-4-20250514":    { in:  3, out: 15 },
    "claude-opus-4-20250514":      { in: 15, out: 75 },
    "claude-3-5-sonnet-20241022":  { in:  3, out: 15 },
    "claude-3-5-haiku-20241022":   { in: 0.80, out: 4 },
  },
  DEFAULT_MAX_OUTPUT: 2048,
  CHARS_PER_TOKEN: 4,

  estimateTokensFromText(text) {
    return Math.ceil((text || "").length / this.CHARS_PER_TOKEN);
  },
  estimateCallCost({ promptText, model, maxOutput }) {
    const inputTokens = this.estimateTokensFromText(promptText);
    const outputTokens = maxOutput || this.DEFAULT_MAX_OUTPUT;
    const p = this.PRICING[model] || { in: 3, out: 15 };
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
      "- If the entity is dead/complete, say so and keep outstanding empty.",
      "- Do not hedge with 'I don't have access to X' — you have everything; reason from what's here.",
      "- Output JSON before prose, always.",
      "- `derived_summaries` is OPTIONAL. Include one entry per 1-hop dependent you formed an opinion on. Skip dead entities. Empty array `[]` is fine. Don't pad — only include dependents where you have something concrete to say (one or two genuine outstanding/blocked/changed items, or a clear next_move).",
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

  async render(panel, entity) {
    const summary = this.forEntity(entity);
    if (!summary) return false;

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

    // Actions
    const hasKey = Settings.hasKey();
    parts.push(`<div class="analyser-toggle-row">
      <button class="btn-primary" id="btn-saved-regenerate" ${hasKey ? "" : "disabled"} style="font-size:0.78rem"
        title="${hasKey ? "Re-run analysis (new event will supersede this one)" : "Configure API key in settings first"}">↻ Regenerate</button>
      <button class="btn-secondary" id="btn-saved-show-summary-event" style="font-size:0.78rem">View event id</button>
    </div>`);

    panel.innerHTML = parts.join("");

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
    document.getElementById("btn-saved-show-summary-event")?.addEventListener("click", () => {
      alert(`Summary event id: ${summary.event_id}\nSource: ${summary.source}\nFreeform path: ${summary.freeform_path}\nSupersedes: ${summary.supersedes_summary_event_id || "(none)"}`);
    });

    return true;
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
    this._showCostDialog({ entity, systemPrompt, userPrompt, bundle });
  },

  _showCostDialog({ entity, systemPrompt, userPrompt, bundle }) {
    const dialog = document.getElementById("cost-dialog");
    const body = document.getElementById("cost-dialog-body");
    if (!dialog || !body) return;
    const defaultModel = Settings.defaultModel || "claude-sonnet-4-20250514";
    const fullPromptText = systemPrompt + "\n\n" + userPrompt;

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
            ${Object.keys(Estimator.PRICING).map(m =>
              `<option value="${m}" ${m === model ? "selected" : ""}>${m}</option>`
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
    const p = Estimator.PRICING[model] || { in: 3, out: 15 };
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
}

// main() is defined at the top of the file; it calls initAnalyser() before
// loading projection/events.

main();
