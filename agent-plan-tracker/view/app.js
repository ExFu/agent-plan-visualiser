const PROJECTION_PATH = "../../.agent-plan-tracker/projection.json";

async function main() {
  let projection;
  try {
    const r = await fetch(PROJECTION_PATH);
    projection = await r.json();
  } catch (e) {
    document.getElementById("content").innerHTML =
      `<p>Failed to load projection.json: ${e.message}</p>
       <p>Run <code>python3 agent-plan-tracker/scripts/projection-emit.py</code> first,
       or serve via <code>python3 -m http.server</code> from the repo root if file:// fetch is blocked.</p>`;
    return;
  }

  document.getElementById("meta").textContent =
    `Generated ${projection.generated_at} · ` +
    `${projection.summary_stats.total_events} events · ` +
    `${projection.summary_stats.live_count} live · ` +
    `${projection.summary_stats.dormant_count} dormant · ` +
    `${projection.summary_stats.dead_count} dead · ` +
    `${projection.summary_stats.orphaned_count} orphaned`;

  document.getElementById("btn-board").addEventListener("click", () => render(projection, "board"));
  document.getElementById("btn-tree").addEventListener("click", () => render(projection, "tree"));
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

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[c]);
}

main();
