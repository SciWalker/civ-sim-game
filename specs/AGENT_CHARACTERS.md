# Agent Characters — Needs, Wants, and Actions

A specification for what an agent *is* and how it *behaves* in the world.

This spec is **implementation-matched**: every field, constant, and formula below
corresponds to the current simulation in `seamless_sim/rust/src/agent_sim.rs` (and
its GDScript fallback `GDScriptAgentSim.gd`). It formalizes the model that exists
today and the few near-term hooks already stubbed in code. It is not a wishlist —
where the code uses a placeholder, this spec says so explicitly.

For the longer-horizon memory/lineage layer, see `EMERGENT_NARRATIVE.md`. This
document covers the moment-to-moment "what does an agent do this tick" loop that
sits underneath it.

### Scientific grounding

The original three-need / utility-AI loop is classic **drive-reduction theory**
(Hull, 1943): a deficit builds, behavior reduces it, repeat. That still works as the
skeleton, but motivation science has moved on, and four modern frameworks let the
layers behave far more like real organisms without abandoning the flat-array design.
This revision grounds each layer in one of them:

- **Needs → homeostasis + allostasis.** A need is a homeostatic *set point* the
  agent regulates, and good agents act *predictively* (allostasis) before a deficit
  becomes a crisis — the same imperative the *active-inference / free-energy*
  account gives for adaptive agents: keep internal states within a hospitable range
  and minimize expected "surprise" (Friston; Corcoran et al., 2024).
- **Needs → which needs.** *Self-Determination Theory* (Deci & Ryan) splits
  motivation into physiological needs and three psychological ones —
  **autonomy, competence, relatedness**. Our `social` need is really *relatedness*;
  *competence* is the strongest candidate for a fourth need (§2.3).
- **Wants → wanting (incentive salience).** Affective neuroscience (Berridge &
  Robinson) shows "wanting" is **dissociable** from "liking": wanting is
  cue-triggered, dopaminergic *pull toward* a reward, amplified by nearby cues.
  This is exactly what the "want" layer should compute (§3).
- **Reward → liking (hedonic impact).** The *satisfaction* of acting is a separate
  signal from the wanting that drove it, and it is state-dependent — food is
  "liked" more when hungry (alliesthesia). Modeling liking separately gives a clean
  reinforcement signal and narrative beats (§5.6).

Full citations in §11.

---

## 1. What an agent is

An agent is **not an object**. It is an integer index `i` shared across parallel
flat arrays. Every property below is the `i`-th element of its array. This is the
data-oriented layout that lets the sim scale to thousands of agents.

### 1.1 State fields (per agent)

| Field | Array | Type | Range / meaning |
|-------|-------|------|-----------------|
| Position | `pos` | `f32 × 2` | interleaved `[x, y]` in world units |
| Velocity | `vel` | `f32 × 2` | interleaved `[vx, vy]`, world units / sec |
| Hunger | `hunger` | `f32` | `1.0` = full, `0.0` = starving |
| Energy | `energy` | `f32` | `1.0` = rested, `0.0` = exhausted |
| Social | `social` | `f32` | `1.0` = content, `0.0` = lonely |
| Faction | `faction` | `i32` | faction id, `-1` = none |
| LOD | `lod` | `enum` | `Near` / `Mid` / `Far` |

All three needs share one convention: **higher is better, `0.0` is the crisis
point.** Keep that convention for any need added later — the utility scoring in §4
depends on it.

A newly spawned agent starts at `hunger = energy = social = 1.0`, `vel = (0, 0)`,
and `lod = Far` (it is promoted on the first tick once distance is evaluated).

---

## 2. Needs (homeostatic set points)

A need is a scalar the agent **regulates toward a set point** (`1.0`). Left alone it
**decays every tick, at every LOD**, and it is **only restored by acting on it**.
Decay running at all LODs (even for far, unsimulated agents) is deliberate: it keeps
an off-screen agent's internal state consistent so that when it is promoted back to
`Near`, its behavior resumes seamlessly with no pop.

**Homeostasis framing.** Read `1.0 − need` as the *homeostatic error*: the distance
between the agent's current internal state and its set point. The whole behavior
loop is error-correction — pick the action that most reduces the largest error. This
is the same objective active-inference agents pursue (keep internal variables in
range, minimize expected surprise), expressed in arithmetic the flat-array sim can
run cheaply.

**Allostasis (act early, not at the cliff).** Real organisms regulate
*predictively* — they eat before starving, rest before collapse. A purely reactive
agent that only acts at the crisis point looks robotic and dies to the first
unlucky gap in food. So the comfort band and anticipatory weighting below exist to
make agents act *ahead* of the deficit:

- **Comfort band.** A need in `[0.75, 1.0]` is "satisfied" and exerts little pull;
  below `0.75` the agent starts wanting to correct it. (This band is exactly the
  existing `0.25` idle threshold from §4, now given a homeostatic meaning rather
  than being a magic number.)
- **Anticipatory weighting.** Faster-decaying needs should be acted on *earlier*,
  because they will hit crisis sooner. Weight each need's urgency by its decay rate
  so hunger (fastest) pulls before social (slowest) at equal depletion. See §4.1.

### 2.1 Decay rates

Per tick, with frame delta `delta` (seconds):

```
hunger -= hunger_rate * delta      // hunger_rate = 0.02
energy -= energy_rate * delta      // energy_rate = 0.015
social -= social_rate * delta      // social_rate = 0.01
```

Each is clamped to a floor of `0.0`. These rates are **exposed to GDScript** as
tunables so balance can be changed without recompiling Rust.

Hunger decays fastest, social slowest. At `delta` of one 20 Hz tick (0.05 s),
hunger falls a full `1.0 → 0.0` in ~1000 ticks (~50 s of sim time), energy in
~67 s, social in ~100 s. These are the levers that set the rhythm of an agent's
day; tune them together, not in isolation.

### 2.2 The three needs

**Hunger** — the survival drive. Fastest decay. Refilled by the *Eat* action.
Currently has no death consequence at `0.0` in the Rust core (the
`EMERGENT_NARRATIVE.md` layer adds starvation death on top).

**Energy** — the rest drive. Medium decay. Refilled by the *Rest* action, which
requires the agent to stop moving.

**Social** — the belonging drive, i.e. **relatedness** in Self-Determination Theory
terms: the need to feel connected to others. Slowest decay. Refilled by the
*Socialise* action, which requires proximity to a same-faction agent. This is the
only need whose satisfaction depends on *other agents*, which is what makes factions
matter behaviorally rather than just as a color.

Hunger and energy are **physiological** needs (homeostatic in the literal,
metabolic sense); social/relatedness is a **psychological** need. SDT names two more
psychological needs the model does not yet have — *competence* and *autonomy* — of
which competence is the high-value next addition (§2.3).

### 2.3 Competence — fourth need (SDT) ✅ implemented

✅ **Shipped** in both `agent_sim.rs` and `GDScriptAgentSim.gd`.

*Competence* is the need to **feel effective** — to master tasks and succeed at what
you attempt (Deci & Ryan). It is the cleanest SDT addition for this sim because the
agent already performs actions that visibly succeed or fail:

- **Decays slowly** at `competence_rate = 0.005` (slowest need), every tick at every
  LOD like the others.
- **Restored by successful action** (`+0.05 * delta` on success), not by a dedicated
  "do competence" behavior — so it is **not a selectable action** in the argmax.
  Eat, Rest, and a Socialise *that finds an ally* count as successes; a Socialise
  with **no ally in range fails** and grants no competence (and falls back to
  wander). This is what lets a lonely or resource-starved agent's competence erode.
- **Why it matters for emergence:** competence turns the flat need-loop into
  something with a *direction of growth*. An agent that keeps succeeding accrues
  competence and reads as thriving/skilled; one that keeps failing reads as
  struggling. Tie it into the §5.6 liking signal and the memory log (an
  `achievement` event when competence crosses a high threshold) and you get
  "this colonist became a master forager" stories with no scripting.

*Autonomy* (the third SDT need — acting from volition rather than coercion) is
noted for completeness but is **out of scope** until agents can be *directed* by a
player or leader; without coercion there is nothing for autonomy to be the absence
of.

### 2.4 Adding a need later (contract)

A new need must: (a) live in its own flat `Vec<f32>` parallel array; (b) follow
the higher-is-better / `0.0`-is-crisis convention; (c) decay every tick at every
LOD; (d) expose a `*_rate` tunable; (e) contribute one `*_score` to the utility
comparison in §4; (f) be paired with exactly one refilling action in §5.

---

## 3. Wants (incentive salience — "wanting")

An agent has no persistent goal stack and no scripted plan. Its "want" is **derived
fresh each tick**. This is the core design stance: behavior *emerges* from need
pressure rather than from an `if hungry then eat` script.

The key scientific correction here: **a want is not the same thing as a need.**
Berridge & Robinson showed "wanting" (incentive salience — the dopaminergic *pull*
toward a reward) is dissociable from both the underlying deficit and the "liking" of
the reward. Two things drive wanting:

1. **Internal deficit** — how far below set point the need is (the homeostatic
   error from §2).
2. **Cue salience** — the presence of a relevant *cue* in the world. A visible food
   source nearby amplifies the wanting for food, even when hunger isn't yet
   critical. This is why agents should opportunistically grab nearby resources, and
   why a wanting model produces more lifelike behavior than pure deficit ranking.

So the want each tick is the **winner of the utility comparison** in §4, scored as
`deficit + cue salience` rather than deficit alone. An agent's current want is one
of:

- *Satisfy hunger / energy / competence* (homeostatic correction)
- *Satisfy social/relatedness*
- *Wander* (the default when nothing is pressing and no cue beckons)

Because the want is recomputed every tick, an agent can abandon a half-finished
action the instant a more urgent need — or a more salient cue — overtakes it: stop
walking to a friend because it just got too hungry, or detour to food it happened to
pass. No interruption logic is needed; the comparison handles it for free.

Note that wanting is **deliberately not** the same as enjoying — see §5.6 on liking.
Keeping them separate is what lets the model later represent things like an agent
that compulsively seeks a resource it no longer benefits from (the same dissociation
that, in humans, underlies craving).

---

## 4. Decision making (utility AI)

Run **only for `Near`-LOD agents** (see §6). `Mid` and `Far` agents skip this
entirely.

### 4.1 Scoring

**v0 — current code (reactive deficit).** Each action scores by how badly its need
is unmet:

```
eat_score    = 1.0 - hunger
rest_score   = 1.0 - energy
social_score = 1.0 - social

max = max(eat_score, rest_score, social_score)
```

A score near `1.0` means that need is nearly empty (urgent); near `0.0` means
satisfied. This is the drive-reduction baseline and is fine as a fallback.

**v1 — science-grounded (allostatic deficit + incentive salience).** ✅ **Shipped**
in both backends (with one difference noted below). Two additive terms upgrade each
score, matching §2 (allostasis) and §3 (wanting):

```
deficit_i      = 1.0 - need_i
anticipation_i = decay_rate_i * HORIZON          // allostasis: act earlier on
                                                 // faster-decaying needs
salience_i     = SALIENCE_GAIN * cue_proximity_i // wanting: nearby cue amplifies
                                                 // pull; 0 if no cue in range

score_i = deficit_i + anticipation_i + salience_i
```

where:

- `cue_proximity_i ∈ [0, 1]` = `1 − (dist_to_nearest_cue / sensory_radius)`,
  clamped at `0` when the nearest relevant cue (food source, ally, …) is beyond
  `sensory_radius` (reuse the `200.0` ally-query radius). For needs with no external
  cue (e.g. rest, which the agent can do anywhere), `salience_i = 0`.
- `HORIZON` — how many seconds ahead the agent anticipates; propose `2.0`. With the
  current rates this makes hunger's anticipation term (`0.02 × 2.0 = 0.04`) about
  twice energy's and four times social's, so a hungry-and-tired agent eats first, as
  it should.
- `SALIENCE_GAIN` — how strongly cues pull; propose `0.3`. Big enough to make an
  agent grab adjacent food it wasn't yet desperate for, small enough not to override
  a genuine crisis elsewhere.

v1 reduces to v0 when `HORIZON = 0` and `SALIENCE_GAIN = 0`, so it can ship behind
those two tunables and be dialed in without code changes.

> **Backend difference.** The Rust backend computes salience for **both** eat
> (origin placeholder) and social (nearest ally, via the spatial grid). The
> GDScript fallback has no spatial grid, so it computes **eat-cue salience only**;
> its social score uses deficit + anticipation with no cue term. Behavior is
> otherwise identical. Once real food sources land (§10), the eat cue switches from
> the origin placeholder to the nearest food entity in both backends with no other
> change.

### 4.2 Action selection

```
if max < 0.25:                 → Wander   (all needs reasonably met)
else if max == eat_score:      → Eat
else if max == rest_score:     → Rest
else:                          → Socialise
```

The `0.25` **idle threshold** is what prevents agents from frantically topping off
needs that are already 75%+ full; below it they meander instead. As noted in §2,
this threshold *is* the homeostatic comfort band's lower edge — keep the two values
identical. Ties resolve in the order written (eat > rest > social), a consequence of
the `==` comparison chain — keep this in mind if scores can be exactly equal.

With v1 scoring or a fourth need, replace the hardcoded `if/else` chain with a plain
**argmax over all action scores**, then compare the winner against the idle
threshold. The selection logic is otherwise unchanged.

---

## 5. Actions (how a want becomes movement + need change)

Each action does two things: it steers the agent (sets `vel` or position) and it
refills the corresponding need. Refill rates are **larger than decay rates**, so a
chosen action wins ground against the decay — but not instantly, so the agent
commits to it for several ticks.

| Action | Steering | Need effect (per tick) |
|--------|----------|------------------------|
| **Eat** | `seek` toward food source | `hunger += 0.3 * delta` (cap 1.0) |
| **Rest** | stop: `vel = (0, 0)` | `energy += 0.4 * delta` (cap 1.0) |
| **Socialise** | `seek` nearest ally | `social += 0.25 * delta` (cap 1.0) |
| **Wander** | random steering jitter | none |

After an action sets velocity, position integrates as `pos += vel * delta` (at
`Near` LOD).

### 5.1 Eat — ⚠ placeholder

Eat currently seeks the **world origin `(0, 0)`** as a stand-in "food source" and
refills hunger once the agent is moving toward it. **This is a known placeholder.**
The intended replacement (already flagged in `README.md` "next steps") is real food
resource entities registered in the spatial grid, located via a nearest-resource
query instead of a hardcoded point. When that lands, only the seek target changes;
the scoring and refill stay as specified.

### 5.2 Rest

Zeroes velocity and recovers energy in place. Fastest refill rate (`0.4`) because
resting is uninterrupted and should resolve quickly so the agent can return to other
business.

### 5.3 Socialise

Calls `nearest_ally(i)` and seeks toward it:

- Query the spatial grid for neighbours within radius **`200.0`** of the agent.
- Among them, pick the nearest agent with the **same `faction`** (skip self and
  other factions).
- If none found, the target defaults to the agent's own position (it effectively
  stays put and social does not meaningfully refill until an ally is near).

This is the one action coupling agents to each other, and the reason faction
assignment has behavioral weight.

### 5.4 Wander

The "needs are fine, just exist" behavior. Adds small random steering each tick and
caps speed at half the normal move speed so wandering reads as relaxed meandering,
not purposeful travel:

```
vel.x += (rand() - 0.5) * 8.0      // jitter = 8.0
vel.y += (rand() - 0.5) * 8.0
clamp_speed(i, move_speed * 0.5)   // = 20.0
```

### 5.5 Movement primitives

**`seek(target)`** points velocity straight at a target at full `move_speed`:

```
d = target - pos
vel = normalize(d) * move_speed    // move_speed = 40.0
```

**`clamp_speed(max)`** scales velocity down to `max` if it exceeds it (used by
wander). `move_speed` is an exposed tunable.

The RNG behind wander is a deterministic xorshift64 seeded per-sim, so a given seed
reproduces the same wandering — important for debugging and for any future replay or
save/load.

### 5.6 Liking — the hedonic reward signal ✅ implemented

✅ **Shipped** in both backends as a per-tick `liking` value, exposed via
`get_needs`.

The "want" that drove an action (§3) is **not** the *enjoyment* of completing it.
Following Berridge & Robinson, model **liking** as a separate, transient signal
emitted *when an action delivers* its need restoration:

```
liking = deficit_at_start * gain_this_tick
```

The `deficit_at_start` factor encodes **alliesthesia** — the well-documented effect
that the same reward feels better the more depleted you were (food is sublime when
starving, unremarkable when full). An agent eating at hunger `0.1` likes it far more
than one topping off at `0.9`, with no extra state.

Liking is dissociated from wanting on purpose, and feeds three systems:

- **Competence (§2.3):** sustained positive liking from successful actions is a
  natural input to the competence bump.
- **Learning (future):** liking is the reward signal a light reinforcement layer
  would use to bias an agent toward *where* and *with whom* good outcomes happened —
  e.g. remembering a productive food source — without any global pathfinding.
- **Narrative (`EMERGENT_NARRATIVE.md`):** a spike of liking is a candidate
  `milestone`/`achievement` event; chronic near-zero liking (acting but never
  satisfied) is the signature of a *struggling* agent and a source of tragedy
  beats.

Liking decays to zero the moment the action stops, so it is a per-tick output, not a
stored need — keep it out of the homeostatic arrays.

---

## 6. Level of detail (which agents actually think)

Distance from the camera focus point decides how much of the loop each agent runs.
Focus is set from GDScript each frame via `set_focus(x, y)`. Comparisons use
**squared distance** (no `sqrt`) for speed.

| LOD | Condition (`d` = dist from focus) | Per-tick behavior |
|-----|-----------------------------------|-------------------|
| **Near** | `d ≤ 600.0` (`near_dist`) | needs decay **+** utility AI **+** full movement |
| **Mid** | `600.0 < d ≤ 1500.0` (`mid_dist`) | needs decay **+** coarse drift (`pos += vel * delta * 0.5`), no AI decision |
| **Far** | `d > 1500.0` | needs decay only, no movement |

`near_dist` and `mid_dist` are tunables. The invariant that makes LOD invisible:
**needs decay identically at all three tiers.** Only *decision-making* and
*movement* are dropped at distance, never the underlying need state — so promotion
from `Far` back to `Near` never produces a discontinuity.

> **Known limitation — Far agents decay but can't act.** A `Far` agent gets hungry
> with no way to feed itself, so over long off-screen periods its needs bottom out.
> This is harmless today (no death is implemented), but it makes `Far` unsafe the
> moment starvation death is added: every agent that wanders off-screen would
> silently die. The planned fix replaces the "decay only" `Far` tier with
> **statistical, group-level simulation** of off-screen population — see
> `POPULATION_ABSTRACTION.md`. Until that lands, do **not** check death at `Far`.

---

## 7. The per-tick loop (authoritative order)

For reference, the exact order the simulation executes each tick:

1. `update_lod()` — recompute every agent's LOD from current focus.
2. `grid.rebuild()` — rebuild the spatial grid from current positions (cell size
   `64.0`) so neighbour queries this tick are correct.
3. For each agent `i`:
   1. Decay `hunger`, `energy`, `social` (always, all LODs).
   2. Branch on LOD:
      - `Near`: `choose_and_act(i)` then integrate `pos += vel * delta`.
      - `Mid`: integrate at half speed, no decision.
      - `Far`: nothing further.

Positions are then handed to the renderer in **one packed array per frame**
(`get_positions()` → `PackedVector2Array`) — never one cross-language call per
agent.

---

## 8. Inspection surface (for UI / debugging)

`get_needs(i)` returns a dictionary of `hunger`, `energy`, `social`, and `faction`
for a single agent — the hook for a character-inspector panel. This is the read-only
window into an agent's drives and is the natural place to later surface the memory
timeline from `EMERGENT_NARRATIVE.md`.

---

## 9. Constants reference

Single source of truth for the numbers used above (all exposed to GDScript unless
noted):

| Name | Value | Role |
|------|-------|------|
| `hunger_rate` | `0.02` | hunger decay / sec |
| `energy_rate` | `0.015` | energy decay / sec |
| `social_rate` | `0.01` | social decay / sec |
| `move_speed` | `40.0` | seek velocity; wander capped at half |
| idle threshold | `0.25` | below this max-urgency → wander |
| wander jitter | `8.0` | random steering magnitude |
| eat refill | `0.3` | hunger gained / sec while eating |
| rest refill | `0.4` | energy gained / sec while resting |
| social refill | `0.25` | social gained / sec while socialising |
| ally query radius | `200.0` | socialise neighbour search |
| grid cell size | `64.0` | spatial grid bucket size (not a tunable) |
| `near_dist` | `600.0` | Near/Mid LOD boundary |
| `mid_dist` | `1500.0` | Mid/Far LOD boundary |

**v1 — science-grounded (now shipped in both backends):**

| Name | Value | Role |
|------|-------|------|
| `competence_rate` | `0.005` | competence decay / sec (§2.3) |
| competence success gain | `0.05` | competence gained / sec on a successful action (§2.3) |
| `HORIZON` | `2.0` | allostatic look-ahead, seconds (§4.1) |
| `SALIENCE_GAIN` | `0.3` | incentive-salience cue weight (§4.1) |
| `sensory_radius` | `200.0` | cue-detection range; = ally query radius (§4.1) |

Setting `HORIZON = 0` and `SALIENCE_GAIN = 0` collapses v1 scoring back to the
v0 behavior, so the new motivation model can be toggled off without code changes.

---

## 10. Known placeholders & first extensions

**Shipped in this revision:**

- ✅ **v1 scoring** (allostasis + incentive salience), §4.1 — both backends.
- ✅ **Liking signal**, §5.6 — both backends.
- ✅ **Competence need**, §2.3 — both backends.

**Still to do**, in priority order, with the framework that motivates each:

1. **Real food sources.** Replace the "seek origin to eat" stub (§5.1) with food
   entities in the spatial grid and a nearest-resource query. Highest-value change;
   it is also what turns eat-cue salience from a placeholder (distance to origin)
   into a real cue. Everything else about Eat stays.
2. **Starvation / death consequence.** Wire a `hunger == 0.0` outcome (see
   `EMERGENT_NARRATIVE.md`'s `_handle_hunger`) so the survival drive has stakes.
   **Blocked on** off-screen abstraction (`POPULATION_ABSTRACTION.md`) — without it,
   death at `Far` LOD would silently kill the whole off-screen world.
3. **Social-cue salience in the GDScript fallback.** Currently Rust-only (no grid in
   the fallback — see §4.1 backend note). Add when/if the fallback needs parity.
4. **Richer social graph.** Promote `faction` from a flat id into tracked pairwise
   relationships; `nearest_ally` becomes "nearest *liked* agent." Pairs naturally
   with the renovated-pyramid mating/parenting motives (Kenrick et al.) once the
   reproduction layer in `EMERGENT_NARRATIVE.md` is live. This is also the
   substrate the governance layer builds on — see `GOVERNANCE_EMERGENCE.md`.
5. **Reinforcement from liking.** Use the §5.6 liking signal to bias agents toward
   places/partners that paid off (lightweight, no global planner).
6. **More needs.** Add per the §2.4 contract only when an action exists to satisfy
   each.

For the longer-range goal of what *kind of government* a society settles into, see
the companion spec `GOVERNANCE_EMERGENCE.md`. Whether each agent could be driven by
an **LLM/SLM** is captured as a parked, *good-to-have* investigation in
`LLM_AGENTS.md` — feasibility is uncertain and it is explicitly **not** on the
critical path.

---

## 11. References

Modern motivation science the layers are grounded in:

- **Drive reduction** (the baseline): Hull, C. L. (1943). *Principles of Behavior.*
- **Wanting vs. liking / incentive salience:** Berridge, K. C., & Robinson, T. E.
  (2016). "Liking, Wanting, and the Incentive-Sensitization Theory of Addiction."
  *American Psychologist.*
  <https://pmc.ncbi.nlm.nih.gov/articles/PMC5171207/>
- **Self-Determination Theory (autonomy, competence, relatedness):** Deci, E. L., &
  Ryan, R. M. — overview:
  <https://www.urmc.rochester.edu/community-health/patient-care/self-determination-theory>
- **Active inference / free-energy & allostasis:** Corcoran, A. W., et al. (2024),
  on self-efficacy and affect in active inference of allostasis.
  <https://pmc.ncbi.nlm.nih.gov/articles/PMC10839114/>
- **Renovated pyramid of needs (evolutionary motives):** Kenrick, D. T.,
  Griskevicius, V., Neuberg, S. L., & Schaller, M. (2010). "Renovating the Pyramid
  of Needs." *Perspectives on Psychological Science.*
  <https://journals.sagepub.com/doi/10.1177/1745691610369469>
