# Golden circle grounding for downstream agents

Simon Sinek's Golden Circle is normally applied to brand positioning. Applied to agent instruction sets, it becomes load-bearing.

**Why → How → What.** Always in that order.

## Why this matters for agents

Agents need motivation and principles to make compatible judgement calls when instructions don't anticipate something. Shipping What (commands, schemas, file paths) without the surrounding Why/How produces brittle outputs that break on edge cases.

A T3 plan tells an agent *what* to do. But when the agent hits something unforeseen — a library quirk, a corrupted state, a contradiction — it has to make a judgement call. Without Why, the judgement is local-only ("this looks broken, let me delete it") and disconnected from project intent. With Why, the judgement aligns with the project's goals ("this looks broken; the project's purpose is X; the fix that preserves X is Y").

## How to apply

When writing any instruction set the plugin ships — skills, commands, philosophies, this file:

1. **Lead with Why.** What problem does this exist to solve? What's the underlying purpose?
2. **Follow with How.** What principles, conventions, methodology shape the approach? Why those specifically?
3. **Close with What.** Concrete steps, file paths, commands, schemas.

A skill that's all What is a recipe. A skill with Why and How is a recipe plus the cook's judgement.

## Where this principle binds in our own design

- This project's own T1 plan starts with §1 Why (the divergent-sources problem), moves to §2 How (the methodology), then §3 Themes (principles), then §4 What (concrete design — itself thin, pointing to T2 plans for architectural detail).
- The plugin's `skills/using-agent-plan-visualiser/SKILL.md` (when written) leads with Why agents need the methodology, then How they use the tracker, then What commands/scripts are available.
- The plugin's `cheatsheet/` content can be more What-heavy because it's a reference, not a grounding document. But the cheatsheet's preamble should still anchor in Why.

## Common failure mode

Putting Why at the END as a "rationale" or "background" section. Agents reading top-down stop reading once they have the commands they need. Rationale buried at the bottom is rationale not absorbed.

Put Why first. Even if it adds 100 words of prose before the commands.
