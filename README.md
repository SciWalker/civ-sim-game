# Seamless Colony Sim — Scaffolding

A starting framework for a RimWorld-like colony sim with:

- **One seamless world** — infinite chunked terrain, no map transitions, free-roaming camera.
- **Thousands of agents** — flat-array (ECS-style) data model, batched MultiMesh rendering.
- **Organic behaviour** — utility AI (no hardcoded event scripts); needs drive actions.
- **LOD simulation** — near agents fully simulated, far agents abstracted, transitions invisible.
- **Hybrid runtime** — gameplay in GDScript, hot simulation loop in Rust (with a pure-GDScript fallback so it runs immediately).

---

## Run it right now (no Rust needed)

1. Install **Godot 4.3+**.
2. Open the `godot/` folder as a project.
3. Assign a `TileSet` to chunks (see *Terrain setup* below) — or comment out the
   `set_cell` loop in `ChunkManager._build_chunk` to run agents-only first.
4. Press **F5**.

It runs on the GDScript fallback sim (the HUD shows `Backend: GDScript`).
Expect a smooth few thousand agents depending on your machine.

---

## Enable the Rust backend (for real scale)

1. Install Rust: <https://rustup.rs>
2. Build the extension:
   ```bash
   cd rust
   cargo build --release        # or: cargo build   (debug, faster compile)
   ```
   This produces `target/release/libagent_sim.so` (or `.dll` / `.dylib`).
3. Restart Godot. It auto-loads `godot/agent_sim.gdextension`.
4. The HUD now shows `Backend: Rust`. Push `AGENT_COUNT` (in
   `AgentRenderer.gd`) up to 10k–40k and watch the FPS.

The Rust class exposes the **same method names** as the GDScript fallback, so
nothing else in the project changes when you switch.

---

## Project layout

```
godot/
├── project.godot                 Godot project + autoload registration
├── agent_sim.gdextension         Links the compiled Rust lib to Godot
├── scenes/
│   └── Main.tscn                 Wires camera, chunks, agents, HUD
└── scripts/
    ├── simulation/
    │   └── TickBus.gd            Fixed-step global heartbeat (autoload)
    ├── world/
    │   ├── ChunkManager.gd       Streams terrain chunks around the camera
    │   └── TerrainGenerator.gd   Layered-noise organic biomes
    ├── agents/
    │   ├── AgentRenderer.gd      Pulls positions from sim -> MultiMesh
    │   └── GDScriptAgentSim.gd   Pure-GDScript fallback sim
    └── ui/
        ├── WorldCamera.gd        Free pan/zoom, no map edges
        └── DebugHUD.gd           FPS / agent / chunk readout + time controls

rust/
├── Cargo.toml
└── src/
    ├── lib.rs                    GDExtension entry point
    ├── agent_sim.rs             Flat-array agents, needs, utility AI, LOD
    └── spatial_grid.rs          O(1) neighbour queries
```

---

## Terrain setup (one-time)

`ChunkManager` expects a `TileSet` whose atlas row 0 holds biome tiles in this
column order: `0 water, 1 sand, 2 grass, 3 forest, 4 rock, 5 snow`.

1. Make a `TileSet` resource with a 16×16 atlas containing those tiles.
2. In `ChunkManager._build_chunk`, uncomment the `layer.tile_set = preload(...)`
   line and point it at your resource.

Until then, comment out the inner `set_cell` loop to test agents on a blank
background.

---

## The architecture in one paragraph

`TickBus` fires a fixed-step `sim_tick` 20×/second regardless of framerate.
`AgentRenderer` forwards each tick to the simulation (Rust or GDScript), which
decays every agent's needs, assigns each a LOD based on distance from the camera
focus, and — for near agents only — runs utility AI to pick the most urgent
action and move. Positions come back as one packed array and are drawn in a
single MultiMesh batch. Meanwhile `ChunkManager` streams terrain in/out around
the free-roaming `WorldCamera`, so the world is one continuous space with no
transitions. Agents persist (at low LOD) even where no terrain chunk is loaded.

---

## Suggested next steps

1. **Profile first.** Find your FPS ceiling at 3k / 10k / 30k agents in each
   backend before adding features. This tells you where the real limits are.
2. **Real food sources.** Replace the "seek origin to eat" placeholder with
   actual resource entities in the spatial grid.
3. **Social graph & factions.** Promote `faction` into emergent groups: track
   pairwise relationships, let groups crystallise from proximity + kinship.
4. **Persistence.** Serialize modified chunks + the agent arrays to disk so the
   infinite world survives save/load.
5. **Player interaction.** Zone painting and an agent inspector (the Rust sim
   already exposes `get_needs(i)` for the inspector panel).
