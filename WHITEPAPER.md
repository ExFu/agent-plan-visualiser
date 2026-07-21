# The ExFu Planning Methodology

**A project management model for working with AI agents.**

*(Working name. ExFu, 2026.)*

## The problem

AI agents now do serious project work. Planning practice hasn't caught up.

Three failures repeat in every agent-driven project:

**Agents have no memory.** Every session starts cold. An agent that can't consult structured history will re-propose rejected ideas, miss open threads, and contradict decisions it never saw.

**Claimed is not done.** Plans say complete. Commit messages say complete. Some of it is. The gap surfaces months later, in an audit nobody scheduled.

**Documents rot.** Status reports, READMEs and roadmaps go stale the moment work moves on. Each artefact drifts from reality at its own speed, and they disagree with each other.

Humans absorb these gaps with memory and judgment. Agents cannot. At agent speed the gaps compound in days, not months.

## The model

Four commitments.

### 1. Plans at three altitudes

- **Intent** (Tier 1): why the project exists and what success looks like. Written once, rarely touched.
- **Architecture** (Tier 2): how each area of the system will work. Rewritten at pivots.
- **Execution** (Tier 3): briefs precise enough for an agent to do the work cold. Written just before the work.

Each reader gets one altitude. The implementing agent isn't wading through strategy. The reviewer isn't wading through file paths.

### 2. Two axes

Every task belongs to a theme (where in the system) and a milestone (when it ships). One intersection each. "What's open in this area?" and "what's left in this release?" are both single queries, not archaeology.

### 3. Append-only plans

Plans are never edited destructively and never deleted. Small changes append. Larger shifts supersede: the old plan stays in place as evidence of what was tried. Abandoned approaches remain visible, so nobody proposes them twice. Human or agent.

### 4. A record that cannot lie

Every unit of work is captured as structured events (created, progressed, completed, superseded, blocked), sealed to the commit that did the work. Every pivot carries a recorded decision: what changed, and why.

All state is computed from this record: what's done, what's blocked, what's waiting on a human. Nothing is hand-maintained, so nothing goes stale.

Capture is enforced mechanically. Work cannot land without it. Agents forget instructions; hooks fire anyway.

Some moves stay human by design: accepting a plan, closing a milestone, ruling on a contradiction. The system queues these ceremonies. It never performs them.

## Why this works with agents

The record substitutes for the memory agents don't have. Any agent, in any session, reads what happened, what's open, and what was rejected. Seconds, not archaeology.

The plan and the record are kept deliberately separate. Plans hold intent. The record holds what happened. The gap between them is where the interesting problems live: unfinished threads, quiet scope cuts, decisions that never landed.

## Coming from another framework

| You use | It maps |
|---|---|
| **Scrum / Jira** | Initiative → Tier 1. Epic → Tier 2. Story → Tier 3. Sprint → milestone axis. |
| **Kanban** | Keep the board. The model adds what the board forgets: how each card got here, and why. |
| **PRINCE2** | PID → Tier 1. Work packages → Tier 3. Stages → milestones. Management by exception → human ceremonies. |
| **OKRs** | Objective → Tier 1. Key results → milestone criteria. Initiatives → Tier 3. Quarter → milestone axis. |

The structures are deliberately familiar. What's new is the record underneath them.

## Tooling

The methodology ships as open tooling (agent-plan-visualiser): event capture at commit time, integrity gates on your main branch, and a dashboard showing what's outstanding, what's blocked, and what's waiting on you.

*ExFu · 2026 · [contact]*
