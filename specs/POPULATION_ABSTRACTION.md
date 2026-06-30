# Population Abstraction — Organic, Multi-Scale Cohorts

**Status: DESIGN (no code yet).** This is the planned replacement for the broken
LOD-Far tier (`AGENT_CHARACTERS.md` §6), where off-screen agents currently decay but
can't act — which would silently starve the whole world the moment death is wired in.

**The approach (technique #2 from the survey):** off-screen population is simulated
*statistically, as groups*, not agent-by-agent — the way Paradox "pops" and The Sims'
off-lot "story progression" work. But with one important difference the project's
design demands: the groups are **not assigned labels like a fixed `faction`**. They
**emerge organically** from where people actually live, who they're related to, and
who they interact with — and an agent belongs to **several at once, nested by scale**.
A person isn't just "faction 3"; he is *of the Panomke valley*, *of the Tang lineage*,
*of the broader Han culture* — three overlapping memberships at three scales, all
emergent, all able to drift apart over time.

This works *because* we already have the narrative layer (`EMERGENT_NARRATIVE.md`):
the statistical mass can be abstracted safely precisely because the
narratively-significant individuals are pulled out and kept as real, tracked people.

---

## 1. The scientific basis

Four findings make "organic nested groups" the principled model rather than an ad-hoc
hack.

**Human social structure is layered, not flat (Dunbar).** Personal networks and
natural communities form concentric layers, each roughly **3× the size of the one
inside it** — about 5 (intimates), 15, 50, 150 (the "community"), 500, 1500
(acquaintance/tribe). These aren't arbitrary; they recur in everything from
hunter-gatherer bands to phone-call graphs. They give us **natural scale boundaries**
for cohorts: family → band → village → tribe → people.

**Identity is segmentary / nested (political anthropology).** Real group identity
nests: "my family, of my clan, of my valley, of my people." A person invokes whichever
level is relevant to the situation — feuding with a neighbour at the family level,
uniting with that same neighbour against an outside tribe. Membership is **multiple
and contextual**, not a single tag.

**Culture is inherited *and* drifts (dual inheritance theory; Boyd & Richerson).**
Humans transmit a *cultural* line alongside the genetic one. Cultural traits copy
down generations and across neighbours but **mutate and drift**, so isolated groups
diverge — exactly like species under isolation.

**Isolation by distance produces localism.** Because cultural transmission is
strongest between people who are physically and socially close, **geographic
separation breeds local variation** — dialects, customs, a distinct "valley identity"
— *on top of* a shared broader culture. This is precisely the "Han, but specifically
Panomke valley" texture you want, and it falls out for free from drift + distance.

**Groups are detected, not declared (network science).** Which agents form a
"community" can be read off the interaction+kinship+proximity graph (community
detection / clustering), rather than assigned. Communities are **emergent dense
regions** of the social graph at a given resolution.

---

## 2. Identity as emergent, nested coordinates

Replace the single `faction: i32` with a small **identity record** per agent — a set
of memberships at ascending scales, each an *emergent* id, not a designer label:

| Scale | ~Size (Dunbar) | Emerges from | Example |
|-------|----------------|--------------|---------|
| Household / kin | 5–15 | direct lineage (`EMERGENT_NARRATIVE.md`) | the Tang household |
| Locality / band | 50–150 | spatial cluster that persists + intermarries | Panomke valley folk |
| Region / tribe | 150–1500 | network of localities trading/marrying/allying | the Upper-River tribes |
| Culture / people | 1500+ | shared descent + shared cultural profile | the Han |

Each agent carries, at minimum: its lineage id (already implied by parents), a
**locality id**, a **culture id**, and a small **cultural-trait vector** (language
/dialect marker, customs, values) that it **inherits with mutation** from its parents
and neighbours (dual inheritance). The higher scales are *derived* by grouping the
lower ones, not stored per agent.

Crucially these scales are **not strictly hierarchical containers** — two valleys can
share a culture but belong to rival regions; a lineage can straddle two localities
after a migration. The memberships overlap, which is what makes the social world feel
organic instead of like a tidy org chart.

---

## 3. The cohort: a group simulated as statistics

A **cohort** is an emergent group at some scale (most often the locality/band level —
the natural unit of an off-screen settlement). When the player isn't near it, the
cohort is simulated *as aggregate numbers*, not as N individuals.

A cohort stores, instead of N full agents:

- **Population & structure** — head count, age distribution (a few buckets), sex
  ratio.
- **Need distribution** — mean and variance of hunger/energy/social/competence across
  members (not per-agent values). This is the statistical stand-in for the decay loop.
- **Resources & carrying capacity** — local food/surplus, which sets birth and death
  *rates*.
- **Cultural profile** — the cohort's average trait vector + drift state (its
  dialect, customs).
- **Location** — centroid + spread on the world map; lets it migrate, split, merge.
- **Tracked individuals** — explicit references to the narratively-significant members
  who are *not* abstracted away (see §5).

The cohort is what gets ticked off-screen — cheaply, on a slow cadence — and it is the
natural home for the governance polity (`GOVERNANCE_EMERGENCE.md`) and for
cohort-level history.

---

## 4. Statistical update (how a cohort lives off-screen)

On a slow tick (game-weekly/monthly, event-driven where possible — reuse the
`EMERGENT_NARRATIVE.md` event queue), each cohort advances by **rates, not per-agent
decay**:

- **Subsistence.** Compare population to local carrying capacity. Surplus → needs
  satisfied, population can grow; shortfall → needs distribution shifts down and a
  **death rate** applies. Deaths are an *intentional statistical outcome* of scarcity,
  never a silent artifact of unsimulated decay — this is the whole point.
- **Births & deaths.** Apply fertility (scaled by surplus) and mortality (baseline +
  scarcity + age). Update population and age structure. Each event *can* spawn a
  narrative record at the cohort level, and a death that lands on a tracked individual
  (§5) fires a real individual event.
- **Migration / fission / fusion.** Under sustained pressure a cohort sheds a splinter
  that moves toward open land (emergent colonization — new localities appear
  organically); neighbouring cohorts that grow into each other merge. This is how the
  map of peoples redraws itself over time without authoring.
- **Cultural drift.** Nudge the cohort's trait vector by small random drift plus
  copying from frequently-contacted neighbours (dual inheritance). Isolated cohorts
  diverge → new dialects/identities; well-connected ones homogenize. **Localism
  emerges here.**
- **Inter-cohort relations.** Trade, alliance, rivalry, and conflict resolved as
  group-level interactions (and as inputs to governance / war).

Cost is per *cohort*, not per agent, so an entire continent of off-screen people costs
a handful of cheap updates — the Paradox/Sims trick, but feeding emergent groups.

---

## 5. Promotion & demotion (the seam with individual simulation)

This is where the narrative layer earns its keep, DF-style.

**Always-individual: tracked figures.** Any agent the narrative layer cares about —
has a memory log of note, a lineage role, leadership/influence, or a relationship to
someone the player follows — is a **tracked individual**. Tracked figures are *never*
dissolved into pure statistics; even inside an off-screen cohort they retain their
identity and continue to accrue real life-events (married, succeeded as headman,
died in the famine of year 60). This is exactly Dwarf Fortress keeping "historical
figures" while forgetting the anonymous mass.

**Promotion (zoom in / approach).** When the camera nears a cohort, **instantiate**
individual agents sampled from its statistics: draw N agents whose needs match the
cohort's mean/variance, ages match its structure, culture matches its profile — and
place the tracked figures at their exact known identities. The crowd you walk into is
statistically consistent with the numbers that were being simulated; it just gains
resolution.

**Demotion (zoom out / leave).** When the player leaves, **fold** the individuals back
into cohort statistics: summarize their needs into the distribution, retire anonymous
agents, and keep the tracked figures as references. Recent concrete events are
preserved; the rest becomes numbers again.

The result: seamless transitions (no pop, like the LOD design intends), bounded memory
(you never hold millions of full agents), and a living, mortal off-screen world.

---

## 6. Narrative at two scales

The narrative system stops being only about individuals and gains a **collective**
layer, which is where epic history comes from:

- **Cohort events** — "the Panomke valley suffered a three-year famine and lost a
  third of its people," "the Upper-River tribes fused under one chief," "the eastern
  dialect split off." These are history the player can read at the map level.
- **Individual events** still happen for tracked figures and for anyone currently
  instantiated, and they **nest inside** the collective ones: the famine (cohort) is
  also the event where *Mara of the Tang household* lost her child (individual).

A death in an abstracted cohort is a statistic; a death of a tracked figure is a story;
the famine that caused both is shared history. That layering is the organic,
multi-scale narrative the project is reaching for.

---

## 7. How this ties the other specs together

- **Replaces LOD-Far** (`AGENT_CHARACTERS.md` §6): "decay only, no action" becomes
  "belongs to a cohort simulated statistically." Near/Mid individual simulation is
  unchanged; the far tier is now *aggregate*, not *frozen*.
- **Unblocks death** (`AGENT_CHARACTERS.md` §10 item 2): starvation death is now safe,
  because off-screen mortality is a deliberate cohort rate, not a side-effect.
- **Feeds governance** (`GOVERNANCE_EMERGENCE.md`): cohorts at nested scales *are*
  nested polities — a valley headman under a regional lord under a cultural empire
  (segmentary politics). Emergent groups give governance its real substrate.
- **Generalizes faction**: the flat `faction` id becomes the emergent identity record
  (§2); existing faction-based code (e.g. `nearest_ally`) reads the locality/culture
  membership instead.

---

## 8. Build order (when implementation begins)

1. **Identity record** — replace `faction: i32` with lineage + locality + culture +
   trait-vector. Derive locality by spatial+kin clustering on a slow tick.
2. **Cohort container + read-only aggregation** — group instantiated agents into
   cohorts and compute their statistics, changing no behavior. Lets you *see* the
   emergent groups and verify clustering before relying on it.
3. **Statistical cohort update** (§4) for cohorts with no player nearby — births,
   deaths-as-rate, subsistence. This is the actual fix for off-screen decay.
4. **Promotion / demotion** (§5) with tracked-figure preservation.
5. **Cultural drift + migration/fission** (§4) — the slow machinery that grows
   localism and redraws the map.
6. **Cohort-level narrative + governance hookup** (§6, §7).

Steps 1–3 already solve the original problem (no silent mass death, scalable
off-screen world). 4–6 are what make it *organic and alive*.

---

## 9. Open questions / tunables

- **Clustering cadence & method** — how often to recompute localities, and by what
  rule (pure spatial vs. spatial+kin+interaction). Affects how stable identities feel.
- **Where to draw the abstraction line** — by camera distance, by loaded-chunk
  boundary, or by an "interest" budget. Likely a blend, mirroring the existing LOD
  distances.
- **Drift rates** — too fast and dialects churn meaninglessly; too slow and the world
  feels uniform. Needs play-testing.
- **Sampling fidelity on promotion** — how faithfully instantiated crowds must match
  cohort stats before differences become noticeable.
- **Tracked-figure budget** — how many individuals to keep fully persistent
  world-wide before it costs too much (DF caps this implicitly).

---

## References

- Dunbar's number & layered social circles (each ~3× the inner) — Dunbar, *The
  Conversation*:
  <https://theconversation.com/dunbars-number-why-my-theory-that-humans-can-only-maintain-150-friendships-has-withstood-30-years-of-scrutiny-160676>
- Dual inheritance theory (genetic + cultural transmission, drift) — Boyd &
  Richerson; overview:
  <https://en.wikipedia.org/wiki/Dual_inheritance_theory>
- Multilevel cultural evolution (theory → applications):
  <https://pmc.ncbi.nlm.nih.gov/articles/PMC10120078/>
- Sociopolitical typology / segmentary organization (nested political units):
  <https://en.wikipedia.org/wiki/Sociopolitical_typology>
