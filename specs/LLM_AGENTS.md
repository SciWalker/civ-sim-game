# LLM / SLM Agents — Feasibility & Architecture

> **Status: GOOD-TO-HAVE / EXPLORATORY — not a committed feature.**
> Feasibility is genuinely uncertain and this is *not* on the critical path. The
> simulation is designed to be fully playable on the deterministic utility-AI layer
> alone (`AGENT_CHARACTERS.md`), and nothing else in the project depends on any of
> this. Treat this document as a *parked investigation* — a sketch of how it
> **could** work if it's ever pursued — so the idea is captured without committing
> to building it. Pick it up only after the core sim, narrative, and governance
> layers are solid.

**The question:** can each agent be driven by a language model (LLM), or a small
language model (SLM)?

**Short answer:** Yes — but *not* as a replacement for the per-tick simulation, and
*not* one call per agent per tick. The only architecture that survives contact with
thousands of agents at 20 Hz is a **layered mind**: the existing utility AI
(`AGENT_CHARACTERS.md`) stays as the fast reflexive substrate for *every* agent
*every* tick, and a language model is an **occasional, asynchronous, budgeted
cognitive overlay** that runs for a small subset of agents far less often. Get that
split right and per-agent LLM behavior is very achievable; ignore it and the sim
falls over.

This spec covers why, and exactly how to wire it in.

---

## 1. The hard constraint: latency and budget vs. scale

The numbers are the whole story.

- The sim ticks **20×/second** — a **50 ms** budget per tick for *all* agents.
- A cloud LLM round-trip is **hundreds of ms to several seconds**. A local SLM
  (1–4B, Q4 quantized) on a decent machine emits **tens to a few thousand tokens/s**
  but still has **tens to hundreds of ms** of first-token latency per call.
- A single structured "what should I do and why" decision is **~50–300 output
  tokens**.

So one synchronous LLM call is **1–3 orders of magnitude slower than an entire
tick**. Calling a model per agent per tick is impossible even for 50 agents, let
alone thousands. Two consequences drive the entire design:

1. **LLM work must be off the tick thread** (async), and results applied whenever
   they arrive — the agent keeps acting on its last high-level intent in the
   meantime, with the utility AI filling every tick in between.
2. **LLM work must be rationed** by a global budget (calls/second), spent on the
   few agents where it matters most.

---

## 2. The layered mind

Three layers, fastest/cheapest at the bottom, slowest/richest at the top. This is
the **same idea as the LOD system** — spend cognition where the player is looking —
applied to thinking instead of movement.

| Layer | Runs for | How often | Mechanism | Job |
|-------|----------|-----------|-----------|-----|
| **Reflex** | every agent | every tick (50 ms) | utility AI (§4, `AGENT_CHARACTERS.md`) | needs, movement, moment-to-moment action |
| **Deliberation** | budgeted subset | seconds–minutes, event-driven | SLM, async | goals, social/political reasoning, dialogue, plans |
| **Reflection** | any agent, on demand | rare / offline | LLM (can be larger) | biographies, narrative, governance rhetoric |

The key relationship: **deliberation sets the agent's high-level *intent*; reflex
executes it.** The LLM does not move the agent — it returns something like
`{"goal": "court agent 88", "stance": "generous"}`, which biases the utility scores
and target selection until the next deliberation. Between LLM calls the agent is
fully autonomous on the cheap layer, so stale intent is harmless.

---

## 3. Which agents get to "think," and when

Never poll. Reuse the **event-driven queue** from `EMERGENT_NARRATIVE.md`: an agent
is nominated for a deliberation call only when something worth thinking about
happens. Good triggers:

- A **decision point**: chronic unmet need, a conflict, a mate/partner opportunity,
  a governance vote (`GOVERNANCE_EMERGENCE.md`).
- A **social encounter** with a high-relationship or high-influence agent.
- **Player attention**: the agent is inspected, spoken to, or is `Near` and on
  screen.
- A **liking/competence spike or crash** (§5.6 / §2.3) — a narratively loaded moment.

Each candidate gets an **interest score** (drama × influence × player-proximity).
A scheduler drains the highest-interest candidates up to the global budget
(e.g. *"≤ 10 SLM calls/second total"*) and drops the rest — they simply keep
running on reflex, which is fine. This makes cost **constant regardless of
population**: 200 agents or 200,000, you still spend the same budget on the most
interesting handful.

---

## 4. What the model sees and returns (keep it tiny)

SLMs degrade fast with long prompts, so the context must be small and structured —
which the data model already supports.

**Prompt = compact state, not prose.** Assemble from existing fields:

- Current needs (`hunger, energy, social, competence`) and last `liking` — from
  `get_needs`.
- A few recent events from the agent's memory log (`EMERGENT_NARRATIVE.md`) —
  already stored as compact `(tick, type, data)` tuples.
- A short relationship/faction summary (top relations, faction role).

**Output = constrained JSON**, e.g.
`{"goal": "...", "target_id": 88, "stance": "...", "say": "..."}`. Use the model's
**function-calling / structured-output mode with constrained decoding** so the
result always parses — no free-form text to clean up. Modern small models are built
for exactly this (Ministral-3-3B is explicitly agent-ready with JSON/function
calling).

The returned intent is written back to a small per-agent `intent` record that the
utility AI reads: it biases action scores (e.g. raise the social score toward
`target_id`) and can set a temporary goal location. Intent has a **time-to-live**;
when it expires the agent reverts to pure reflex until its next call.

---

## 5. Local SLM options (as of 2026)

Per-agent cognition argues for **local** models — no per-call cloud cost, no network
latency, privacy. Any machine with **8 GB RAM runs a 1–4B model at Q4**, and 2026
flagship phones do on-device inference up to ~4B. Reasonable picks:

- **Ministral-3-3B-Instruct** — designed for edge, **agent-ready** with function
  calling and JSON output. Strong default for the deliberation layer.
- **Phi-4-mini (3.8B)** — top of the 3–4B class on reasoning benchmarks, ~3 GB
  VRAM, 128K context. Best quality if you can spare the budget.
- **SmolLM3-3B** — fully open, beats Llama-3.2-3B / Qwen2.5-3B at 3B; good if you
  want an open weights story.
- **Gemma 3 1B** — **>2,500 tok/s on a mobile GPU**; use when you need many cheap
  calls and can accept shallower reasoning.
- **Llama 3.2 1B / Qwen3.5-0.8B** — ultra-light fallback for the lowest tier or
  weakest hardware.

Serve via a local runtime (llama.cpp / Ollama-style) in a **separate process or
thread**, talk to it over a queue, and **batch** concurrent deliberation requests —
batching is where local throughput is won.

---

## 6. If it's ever pursued — a possible order

(Not a roadmap. This is the sequence that would de-risk the idea *if* someone
decides to explore it later. Each step is independently abandonable.)

1. **Reflection first (lowest risk, immediate payoff).** Wire an LLM to turn an
   agent's event log into a biography on demand (the inspector in
   `EMERGENT_NARRATIVE.md` §6). No tick-loop coupling, no budget pressure, and it
   makes the emergent stories legible today.
2. **Add the intent record + scheduler.** Per-agent `intent` struct with TTL; a
   global budgeted scheduler fed by the event queue and interest scores (§3). No
   model yet — stub the "call" with a deterministic heuristic to prove the plumbing
   and keep tests reproducible.
3. **Drop in a local SLM for deliberation.** Replace the stub with an async SLM call
   returning structured intent (§4). Start with **one faction / a few dozen agents**
   to tune the budget and prompt.
4. **Bias the utility AI from intent.** Have `choose_and_act` read the intent record
   (goal target, stance) as extra terms in the v1 score — this is the same additive
   pattern as anticipation/salience, so it slots in cleanly.
5. **Scale the budget, not the call rate per agent.** Raise total calls/sec to taste;
   interest-ranking keeps it spent where it matters.

---

## 7. Honest caveats

- **Determinism breaks.** The reflex sim is deterministic (seeded xorshift RNG);
  LLM sampling is not. For replays/tests, either fix sampling to greedy + cache by
  prompt hash, or keep the LLM layer off in deterministic runs (the sim is fully
  playable on reflex alone).
- **Cost is a design budget, not an afterthought.** The architecture makes cost
  *bounded and tunable*, but it is never zero. Decide the calls/sec budget up front.
- **SLMs are not wise.** A 1–3B model gives *flavor and plausible local choices*,
  not deep strategy. Keep consequential, global decisions (war, governance outcomes)
  in rule-based systems (`GOVERNANCE_EMERGENCE.md`) and use the model for *coloring*
  them, not deciding them — unless you accept the variance.
- **The reflex layer is load-bearing.** Every agent must remain fully functional
  with the LLM layer disabled. The model is an overlay, never a dependency.

---

## 8. Bottom line

Per-agent LLM/SLM cognition *appears* feasible **as a layered, budgeted, event-driven
overlay** — never as a per-tick replacement for the utility AI. But the cost,
latency, determinism, and quality trade-offs are real and unproven for this project,
so it stays a **good-to-have** parked here rather than a planned feature. If it's
ever taken up, the non-negotiable rule is: the deterministic reflex layer remains the
substrate every agent runs on, and the model only ever *flavors* behavior the cheap
layer already produces. Until then, the sim needs none of this to be complete.

---

## References

- Best open-source SLMs, 2026 — BentoML:
  <https://www.bentoml.com/blog/the-best-open-source-small-language-models>
- Small Language Models guide, 2026 — Local AI Master:
  <https://localaimaster.com/blog/small-language-models-guide-2026>
- Top small language models, 2026 — DataCamp:
  <https://www.datacamp.com/blog/top-small-language-models>
- Running LLMs locally (Ollama, llama.cpp), 2026 — daily.dev:
  <https://daily.dev/blog/running-llms-locally-ollama-llama-cpp-self-hosted-ai-developers/>
