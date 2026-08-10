# Empirical prompt architecture

For agent systems: start with a static system prompt; introduce dynamic composition only when real conversations show it's needed.

## The principle

When designing an agent (an extractor, a reviewer, a synthesiser), the temptation is to architect a sophisticated prompt-composition system from the start: dynamic context injection, role-based variations, multi-stage prompt assembly, retrieval-augmented templates.

Almost all of this is premature optimisation.

The empirical approach: start with the simplest possible static prompt. Run it against real cases. Observe where it fails or produces brittle outputs. Add *just enough* dynamic composition to fix those specific failures. Iterate.

## Why this matters

Agent behaviour is hard to predict from architecture alone. A prompt that looks elegant on paper may produce subtly wrong outputs in production; a "naive" static prompt may handle 95% of cases just fine. You don't know until you run it.

Pre-architecting prompt composition optimises for hypothesised problems. Empirical iteration optimises for actual problems.

## How to apply

When writing a new agent:

1. **Start static.** Write the prompt as a single coherent document. Hardcode whatever context it needs. Test against real cases.
2. **Catalogue failures.** When the agent fails or produces low-quality output, write down *why* — what context was missing, what instruction was ambiguous, what edge case wasn't covered.
3. **Add the minimum dynamic composition.** Only after you've seen the failure modes, introduce dynamism: inject a specific extra context block, vary one parameter, swap one section based on a discriminator.
4. **Avoid frameworks.** Don't introduce a prompt-templating engine until you have at least three real reasons to. Most agents never need one.

## Where this principle binds in our own design

- The M2 per-commit extraction agent: start with a single static prompt that includes the ontology summary, the schema, the input contract, and the output expectations. Test against real commits. Only add dynamic context injection (e.g. "fetch related plan files based on the diff") when concrete failures demand it.
- The M5 retrospective mapping note generator: start as a one-shot prompt that reads the repo's planning files and proposes mappings. Only add multi-stage decomposition when the one-shot produces low-quality output for specific project shapes.
- Any future agents (audit, validate, summarise): same discipline.

## Common failure mode

Building a "prompt orchestrator" that supports A/B testing of prompt variants, dynamic context retrieval, multi-turn refinement, all before the first version of the agent has run against real data. This produces an elaborate framework that's hard to debug and a prompt that's still wrong because nobody iterated on the actual prompt content.

## Connection to other philosophies

- `top-down-from-job.md`: an agent's prompt is designed for a specific job. Start simple, iterate from job-related failures.
- `disposable-etl.md`: the prompt itself is closer to bridge code than to permanent infrastructure. Treat it as iteratively-rewritable, not as long-term architecture.
