# Project conventions

## Specs and code must stay in sync — non-negotiable

**Every time you change the code, update the specs in the same change so they reflect
it.** The `specs/` folder is the source of truth for design; it must never drift from
what the code actually does.

This means, whenever you modify behavior, fields, constants, formulas, or
architecture:

1. **Find the spec(s) that describe what you changed** (see the map below) and edit
   them in the *same* pass — not "later."
2. **Keep numbers exact.** Constants, rates, thresholds, and formulas in the spec must
   match the code literally. If you change a value in code, change it in the spec's
   constants table too.
3. **Mark status honestly.** Use clear markers — e.g. ✅ implemented, ⚠ proposed /
   placeholder, "design only" — and update them when status changes. Never describe
   unbuilt behavior as if it exists, or leave shipped behavior marked as proposed.
4. **Note backend differences.** This project has two implementations of the sim
   (Rust `seamless_sim/rust/` and the GDScript fallback `seamless_sim/godot/`). If a
   change lands in one but not the other, say so explicitly in the spec.
5. **Keep cross-references intact.** Specs reference each other and reference code
   sections by number. If you renumber or move things, fix the references too.
6. **A change isn't done until the spec matches.** Treat a code edit with no
   corresponding spec update as an incomplete change.

If a code change has *no* design implication (pure refactor, rename, formatting),
the spec may not need editing — but say so, don't just skip silently.

## Spec map (what lives where)

- `specs/AGENT_CHARACTERS.md` — agent needs, wants, actions, utility AI, LOD, the
  per-tick loop, and the constants table. **Edit this for any change to
  `agent_sim.rs` or `GDScriptAgentSim.gd` behavior.**
- `specs/EMERGENT_NARRATIVE.md` — memory/event logs, lineage, event-driven scheduling.
- `specs/POPULATION_ABSTRACTION.md` — off-screen statistical cohorts, emergent nested
  identity, the planned replacement for the LOD-Far tier.
- `specs/GOVERNANCE_EMERGENCE.md` — emergent government types (influence, legitimacy,
  collective decisions, succession).
- `specs/LLM_AGENTS.md` — parked / good-to-have investigation into LLM/SLM-driven
  agents.
- `specs/TECH_STACK.md` — engine, language, rendering, persistence (SQLite), and
  tooling choices, plus the open 2D-vs-3D render-dimension decision. **Edit this when
  a tooling, dependency, or platform choice changes.**

## Code layout

- `seamless_sim/rust/src/agent_sim.rs` — the scale-path simulation (flat arrays).
- `seamless_sim/godot/scripts/agents/GDScriptAgentSim.gd` — pure-GDScript fallback
  with the **same public API**. Keep the two in parity unless a difference is
  intentional and documented in the spec.
