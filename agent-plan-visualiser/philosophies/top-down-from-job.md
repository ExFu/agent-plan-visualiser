# Top-down from the job

Architectural choices must trace to concrete jobs the system serves. Bottom-up reasoning from data shapes produces tools that don't add value.

## The failure mode this prevents

Bottom-up design starts with what's *available* (an event format, a database schema, a query language) and asks "what can we build with this?" — generating features that are technically interesting but don't map to anyone's real need.

The symptom: a product full of capabilities nobody asked for, missing the one capability everyone needs.

## How to apply

Every architectural decision should answer: **what job does this enable a user (human or agent) to do that they couldn't do before, or could only do painfully?**

- The SQLite cache exists because agents at session-start need a token-cheap "what's outstanding" query — not because SQLite is a fine database (it is, but that's not the job).
- The HTML view exists because humans need a visual project state at a glance — not because HTML is a fine rendering format.
- The decision-as-arc-metadata model exists because agents and humans both ask "why did this pivot?" when reading project history — not because decisions are a tidy ontological category.

When designing, name the job first. Then design the minimum architecture that enables it. Then iterate from real friction, not from imagined elegance.

## Where this principle binds in our own design

- Each T2 plan's §1 ("Why this T2 exists") explicitly names the jobs that theme serves before discussing architecture.
- Each open question in §7 of any plan is framed as a job-to-be-done that needs a design answer, not as a design choice in search of a justification.
- Swap-out points (see `swap-out-surfaces.md`) include the *trigger* for revisiting — i.e. the job-related signal that says "the current choice is no longer serving the job".

## Common failure mode

Designing the data layer first, then asking "what queries should we support?" That's bottom-up. Instead: name the queries (the jobs), then design the data layer to serve them efficiently.

Equivalent failure at higher altitudes: writing a T1 plan that's full of architectural detail before anyone has agreed on what the system is *for*.

## Connection to other philosophies

This is the operationalisation of `golden-circle-grounding.md`'s "lead with Why". The jobs are the why.
