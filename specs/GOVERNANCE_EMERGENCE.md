# Governance Emergence — What Kind of Government Will a Society Become?

**The question:** if you let a society of agents run, will it coalesce into a
*monarchy*, a *democracy*, something else — and can you tell which?

**The honest framing:** a low-level needs simulation will not spontaneously *invent*
the concept of "voting" any more than atoms invent chess. Emergence needs a
substrate to emerge *into*. So the design is: **build a small set of institutional
primitives** (power, legitimacy, collective decisions, succession) whose
*configuration* is not scripted, and let agent dynamics select which stable
configuration the society settles into. Government type then becomes an **emergent
equilibrium** — an attractor in the space those primitives define — and, crucially,
a **measurable** one. You don't script monarchy; you script the conditions under
which monarchy becomes the stable outcome, and then observe.

This builds directly on the agent model (`AGENT_CHARACTERS.md`) and the memory /
lineage layer (`EMERGENT_NARRATIVE.md`).

---

## 1. The science we're modeling

Three well-established frameworks give us both the primitives and the target
categories.

**Weber's three types of legitimate authority** — *why people obey* — map almost
one-to-one onto government types, which makes this the spine of the model:

- **Traditional** authority (obey because power has *always* sat with this
  person/family) → **monarchy / hereditary rule**.
- **Charismatic** authority (obey because of one individual's extraordinary personal
  qualities) → **chiefdom / cult-of-personality / strongman**. Inherently unstable:
  it dies with the leader.
- **Rational-legal** authority (obey the *rules/offices*, not the person) →
  **democracy / bureaucracy / rule of law**.

Real polities **blend all three**; the model should track the *mix*, not force a
single label.

**Service's political typology** — *scale drives complexity* — gives the developmental
axis: **band → tribe → chiefdom → state**, correlated with population size and
resource surplus. (Modern anthropology treats this as a typology, **not** a fixed
ladder every society must climb — collapse and lateral moves are normal. Model it as
an attractor landscape, not a one-way escalator.)

**Sources of power** — agents accrue influence from several independent channels
(economic surplus, social ties, kinship, coercion, perceived competence). Who can
convert which channel into authority decides the outcome.

---

## 2. The substrate already in place

The agent model gives most of what governance needs to grow from:

- **Factions** — the natural unit of a "polity."
- **Competence** (`AGENT_CHARACTERS.md` §2.3) — a per-agent effectiveness signal;
  the seed of *charismatic/competence-based* authority.
- **Liking** (§5.6) and relationships — the basis of *who supports whom*.
- **Lineage** (`EMERGENT_NARRATIVE.md`) — parents/children; the basis of *hereditary*
  (traditional) authority and succession.

We add three things on top: an **influence** score, a **polity** record per faction,
and **collective-decision + succession** rules.

---

## 3. New primitives

### 3.1 Influence (per agent)

A scalar `influence[i]`, recomputed slowly (not per tick — it's a low-frequency
quantity), as a weighted sum of the power channels the sim already exposes:

```
influence_i =  w_comp   * competence_i                // perceived effectiveness
             + w_wealth  * resources_controlled_i      // economic surplus (needs §10 food/resources)
             + w_social  * social_capital_i            // sum/strength of relationships
             + w_kin     * inherited_influence_i       // from parents (lineage)
             + w_coerce  * coercion_i                  // optional: force/military
```

The **weights are the dial that decides the regime**, and they need not be global —
they can themselves be cultural traits that drift per faction:

- High `w_kin` (influence is inherited) → power concentrates in lineages →
  **monarchy** attractor.
- High `w_comp` / `w_social`, low `w_kin` → power tracks ability and support, doesn't
  pass down → **democratic / meritocratic** attractor.
- High `w_coerce` → **strongman / military** attractor.

### 3.2 Polity (per faction)

```
Polity {
  faction_id: int
  members: [agent_id]
  leadership: [agent_id]        // 1 = autocracy, few = oligarchy/council, many = assembly
  legitimacy_mix: {traditional, charismatic, rational_legal}  // sums to 1.0
  decision_rule: enum           // AUTOCRATIC | COUNCIL | MAJORITY | CONSENSUS
  succession_rule: enum         // HEREDITARY | ELECTION | SEIZURE | NONE
}
```

`leadership`, `decision_rule`, and `succession_rule` are **not set by the designer** —
they are *derived* from the current influence distribution and recent history
(§4), and they change as that distribution changes.

### 3.3 Collective decisions

Governance only becomes observable when the group must make a **shared choice** —
where to migrate, whether to fight a neighbouring faction, how to allocate a surplus.
A decision is resolved by the polity's current `decision_rule`:

- **AUTOCRATIC** — the single highest-influence member chooses.
- **COUNCIL / OLIGARCHY** — influence-weighted vote among the top-k.
- **MAJORITY** — one-agent-one-vote across members (democracy).
- **CONSENSUS** — proceed only if dissent is below a threshold (small bands).

The chosen option then feeds back into needs/liking: good collective outcomes raise
members' competence/liking and the leadership's legitimacy; bad ones erode them —
which is the feedback loop that makes regimes rise and fall.

---

## 4. How a regime emerges (and is classified)

Each "governance epoch" (every N ticks, cheap), per faction:

1. **Recompute influence** for members (§3.1).
2. **Derive the structure** from the influence distribution:
   - **Concentration** — use the **Gini coefficient** (or top-1 share) of
     `influence` across members.
     - Very high, lodged in one agent → autocratic leadership.
     - High across a few → oligarchy/council.
     - Low/even → assembly/majority.
3. **Derive the legitimacy mix** from *why* the leader(s) hold influence:
   - dominated by `inherited_influence` → **traditional** (monarchy).
   - dominated by a single agent's `competence`/charisma, not inherited →
     **charismatic** (chiefdom).
   - influence broad and offices outliving individuals → **rational-legal**
     (democracy/bureaucracy).
4. **Set succession_rule** from observed practice: does influence pass to children
   (HEREDITARY), get re-selected among members (ELECTION), or get taken by force
   (SEIZURE)?
5. **Classify** the polity from the (concentration × legitimacy-mix × succession)
   triple — e.g. *high concentration + traditional + hereditary = **monarchy***;
   *low concentration + rational-legal + election = **democracy***; *high
   concentration + charismatic + none = **chiefdom/strongman** (expect instability
   at the leader's death)*.

Classification is **read out**, never assigned — so the same ruleset can produce
different governments in different playthroughs depending on how the dynamics fell.

---

## 5. Why different attractors are stable (the dynamics)

Government type is the *equilibrium* of feedback loops, not a one-time roll:

- **Scale (Service).** Tiny factions (below ~a Dunbar-like threshold) are stable as
  egalitarian bands/consensus — no surplus to fight over, everyone knows everyone.
  As a faction grows and accumulates surplus, consensus gets expensive and a
  hierarchy becomes the stable way to make decisions → drift toward chiefdom/state.
- **Inheritance loop (monarchy).** If `w_kin` is high, a leader's children start with
  high influence, win the next decision, accrue more, and pass *that* down. The loop
  is self-reinforcing → durable dynasty. `EMERGENT_NARRATIVE.md` lineage already
  tracks the family tree this needs.
- **Charisma decay (chiefdom).** Pure charismatic influence isn't inheritable and
  isn't institutional, so at the leader's death the polity faces a succession
  crisis: it fragments, gets seized, or **routinizes** into either tradition (a heir
  is declared → monarchy) or rules (an office is created → proto-democracy). This
  Weberian "routinization of charisma" is a natural, emergent regime *transition* to
  log as a story beat.
- **Legitimacy erosion (revolution).** When leadership delivers bad collective
  outcomes (famine, lost wars), members' liking/support falls; once support drops
  below a threshold the `decision_rule`/leadership is forced to recompute — a coup,
  an election, or a collapse. This is how the model produces *regime change*, not
  just static government.

---

## 6. Measuring it (so you can actually answer the question)

Log per faction per epoch: Gini of influence, leadership size, legitimacy mix,
decision & succession rules, and the classified label. Then you can literally chart
*"this colony started as a consensus band, became a charismatic chiefdom under agent
#427, and routinized into a hereditary monarchy when she died, then fell to an
oligarchic council after the famine of year 60."* That timeline **is** the answer to
"what kind of government did the society become" — emergent, measurable, and
different every run.

A live artifact (governance dashboard reading these logs) is the natural way to
watch it unfold.

---

## 7. Implementation order

1. **Influence score** (§3.1) from existing fields (start with competence + social;
   add wealth once resources exist, §10 of `AGENT_CHARACTERS.md`).
2. **Polity record + classifier** (§3.2, §4) — read-only at first: derive and log a
   government label from the influence distribution, change nothing about behavior.
   This alone answers the question and is low-risk.
3. **Collective decisions** (§3.3) — give factions real shared choices and resolve
   them by `decision_rule`; feed outcomes back to needs/liking.
4. **Succession & legitimacy dynamics** (§5) — inheritance of influence, charisma
   routinization, legitimacy erosion → regime transitions.
5. **Cultural weight drift** — let `w_kin` / `w_comp` / `w_coerce` vary and evolve
   per faction so different societies tend toward different regimes.

Steps 1–2 are enough to start observing emergent government types; 3–5 make them
*dynamic* and produce revolutions, dynasties, and collapses.

> **Optional LLM tie-in.** Per `LLM_AGENTS.md`, keep the *outcome* of governance in
> these rule-based systems (deterministic, debuggable) and use an LLM only to
> *flavor* it — leaders' speeches, faction rhetoric, the player-facing narration of
> a coup — not to decide who wins.

---

## References

- Weber's three types of authority (traditional / charismatic / rational-legal):
  <https://en.wikipedia.org/wiki/Tripartite_classification_of_authority>
- Power and authority overview — Howard CC / Intro to Sociology:
  <https://pressbooks.howardcc.edu/soci101/chapter/14-1-power-and-authority/>
- Service's political typology (band / tribe / chiefdom / state) — Sociopolitical
  typology: <https://en.wikipedia.org/wiki/Sociopolitical_typology>
- Political systems (anthropology) — Intro to Anthropology, U. Nebraska:
  <https://pressbooks.nebraska.edu/anth110/chapter/political-systems/>
