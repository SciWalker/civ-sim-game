# Tech Stack

**Status: RECOMMENDED / partially in place.** Items marked ✅ are already used in the
project; ⭐ are recommended additions not yet wired in. Scope is **single-player** for
now (multiplayer is explicitly deferred). **Rendering is decided: height-field 2.5D**
— 3D visuals over a 2D-plane simulation (§6).

---

## The stack at a glance

| Layer | Choice | Status | Why |
|-------|--------|--------|-----|
| Engine / renderer | **Godot 4.x** (Forward+, Vulkan) | ✅ | Integrated desktop engine; its own renderer already drives the game. |
| Hot simulation | **Rust** via GDExtension (`godot-rust` / `gdext`) | ✅ | Data-oriented flat-array sim; the performance core. |
| Sim fallback | **GDScript** mirror (`GDScriptAgentSim.gd`) | ✅ | Runs with no Rust build; keep at API parity. |
| Gameplay scripting | **GDScript** | ✅ | UI, camera, world streaming, inspectors — fast iteration. |
| Modeling / art | **Blender → glTF** | ⭐ | 3D modeling (decision §6); export glTF, import to Godot. |
| Persistence | **SQLite** | ⭐ | The world + agents + lineage + history are a queryable database. |
| Source control | **Git + Git LFS** | ⭐ | LFS for binary art assets. |
| Build / test | **Cargo** + `cargo test` (sim), **GUT** (GDScript) | ⭐ | Determinism/balance tests in Rust; scene/script tests in GUT. |

Short form: **Godot 4 + GDScript + Rust (GDExtension) + Blender + SQLite**, with
Git/LFS around it. Rendering is **height-field 2.5D** (3D look, 2D sim).

---

## 1. Engine & rendering — Godot 4.x ✅

Godot is the runtime: rendering, scene/node system, input, UI, asset import, save/load
glue. The Forward+ renderer (Vulkan, desktop default) is the right choice for a 3D
desktop game with many dynamic lights (clustered lighting). Agents are drawn via
**MultiMesh GPU instancing** so thousands of them cost a handful of draw calls — the
technique, not the engine, sets the scale ceiling.

**Pending 3D switch:** the renderer currently uses `MultiMeshInstance2D`
(`AgentRenderer.gd`). The height-field 2.5D decision (§6) means moving to
**`MultiMeshInstance3D`** and placing each agent on the terrain surface by sampling the
height field: `(x, y)` → `(x, h(x, y), y)`. This is an implementation task, not yet
done.

Because MultiMesh has **no built-in frustum culling or mesh-LOD**, 3D makes those
mandatory rather than optional for large counts: cull off-screen instances and swap
distant agents to cheap **billboard/imposter** LODs. Budget for this from the start —
it's the main cost difference 3D introduces over 2D.

Three.js / a web stack was considered and rejected: it's a browser rendering library,
not an engine, and adopting it would mean abandoning the Godot project and porting the
Rust sim to WASM for no graphics capability we don't already have. Revisit only if
browser deployment becomes a hard requirement.

## 2. Simulation — Rust core + GDScript fallback ✅

The hot loop lives in Rust (`seamless_sim/rust/src/agent_sim.rs`) as flat parallel
arrays (data-oriented). Rust is reserved for what shows up in the profiler — the
per-tick agent loop, spatial queries, and (later) the cohort statistics of
`POPULATION_ABSTRACTION.md`. The GDScript mirror (`GDScriptAgentSim.gd`) keeps the
**same public API** so the game runs with no Rust build; maintain parity unless a
difference is intentional and documented (see `AGENT_CHARACTERS.md`).

## 3. Gameplay scripting — GDScript ✅

Everything that isn't the hot loop: camera, chunk streaming, HUD, the character
inspector, governance/narrative UI. GDScript is chosen for iteration speed; promote a
piece to Rust only when measured cost justifies it.

## 4. Modeling & art — Blender → glTF ⭐

Godot is not a modeling tool. Model in **Blender**, export **glTF**, import to Godot
(strong, well-supported pipeline). Keep agent meshes **low-poly** — at tens of
thousands of instances, polycount per agent multiplies fast, so a few hundred tris
plus imposters at distance (§1) is the target. Reserve detailed models for the
camera-near tier and unique/tracked figures.

## 5. Persistence — SQLite ⭐

This is the main missing piece, and the project's data shape *is* a database:

- An **infinite, chunked world** with only modified chunks worth storing.
- **Thousands of agents** with needs, identity, and position.
- **Lineage and event logs** (`EMERGENT_NARRATIVE.md`) — family trees and per-agent
  histories that players will *query* ("who are this agent's descendants?",
  "what happened in Panomke valley in year 60?").
- **Cohort statistics** (`POPULATION_ABSTRACTION.md`) for off-screen population.

SQLite fits all of this far better than hand-rolled serialization: it's a single file,
transactional save/load, and—critically—**queryable**, which the genealogy and history
features need natively. Plan:

- **Tables:** `agents` (stable id, identity, current needs snapshot), `lineage`
  (parent/child edges), `events` (agent_id, tick, type, data — the memory log),
  `cohorts` (aggregate stats), `chunks` (modified terrain blobs), `world_meta`
  (seed, tick, version).
- **Runtime vs. storage:** the live sim stays in flat arrays in memory for speed;
  SQLite is the **save/load and query store**, written on save and on significant
  events, not every tick.
- **Access:** query from the Rust side (e.g. `rusqlite`) for bulk sim data, or via a
  Godot SQLite addon for editor/UI-side queries. Decide one owner to avoid two writers.
- **Schema versioning:** keep a `world_meta.version` and migrate on load — saves must
  survive spec changes.

## 6. ✅ Decided: height-field 2.5D

The game renders in **3D over a 2D-plane simulation** — "height-field 2.5D." Art is
authored in **Blender → glTF** (§4); the renderer moves from `MultiMeshInstance2D` to
`MultiMeshInstance3D` (§1).

**The model:**

- The world has a **terrain height field** `h(x, y)` — an elevation value per world
  position, naturally produced by the existing layered-noise terrain
  (`TerrainGenerator.gd` / `ChunkManager.gd`). This gives hills, valleys, slopes, and
  cliffs.
- The **simulation stays 2D.** The flat-array `pos` remains `x, y`; agents move on the
  plane exactly as today. `agent_sim.rs` is unchanged by this decision.
- **Rendering samples the height field** to place each agent on the surface:
  `(x, y)` → `(x, h(x, y), y)`. The terrain mesh is the visible 3D world; agents and
  props sit on it.

**What this deliberately is *not*:** continuous volumetric movement/pathfinding (agents
flying or navigating true 3D space) and stacked z-levels (multi-floor / underground).
Both were considered and rejected for now — they'd require pervasive `z`-axis changes
to the sim and 3D pathfinding, against the data-oriented scale goal. If a specific
vertical feature (caves, multi-story buildings, flight) is ever wanted, scope it then
as a targeted addition rather than going volumetric by default.

**Consequences to budget for:**

- **Manual culling & LOD are mandatory.** MultiMesh won't cull or LOD for us, so
  distant agents drop to billboard/imposters and off-screen instances are culled (§1).
- **Low-poly art discipline.** Keep agent meshes small; detail goes to near and
  tracked figures only (§4).
- **Optional sim hook (⚠ proposed, not decided):** slope from the height field could
  modulate movement cost (uphill is slower) — a small, optional read of `h` in the
  movement step. This is the one place 2.5D *could* touch the sim; leave it out until
  wanted, and document it in `AGENT_CHARACTERS.md` if added.

This keeps the existing data-oriented sim intact while giving the game a real 3D look
with terrain elevation.

---

## 7. Tooling

- **Git + Git LFS** — code in Git, binary art (sprites/models/textures) in LFS.
- **Cargo** — Rust build; `cargo test` for sim determinism and balance (the seeded
  xorshift RNG makes the sim reproducible and therefore unit-testable).
- **GUT** (Godot Unit Test) — GDScript scene/script tests.
- **Profiling** — Godot's built-in profiler for frame cost; Rust profiling (e.g.
  Tracy/criterion) for the sim loop. Profile at 3k / 10k / 30k agents before adding
  features, per the README's guidance.

---

## 8. What's deferred

- **Multiplayer** — out of scope for now. If revisited, it forces deterministic
  lockstep, which constrains the whole sim (shared seeded RNG, determinism-safe loops)
  and the LLM/SLM idea (`LLM_AGENTS.md`). Design it in from the start *if* it returns;
  do not retrofit.
- **LLM/SLM agents** — parked good-to-have (`LLM_AGENTS.md`).
