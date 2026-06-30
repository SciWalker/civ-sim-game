// The heart of the simulation. Agents are NOT objects — they are indices into
// parallel flat arrays. This data-oriented layout is what lets us scale to
// thousands of agents: the data is cache-friendly and we never pay per-object
// overhead. This is the same approach Songs of Syx uses to hit tens of thousands.

use godot::prelude::*;
use crate::spatial_grid::SpatialGrid;

// Level of detail. Agents far from the camera tick on cheaper logic.
#[derive(Clone, Copy, PartialEq)]
enum Lod {
    Near, // full simulation: needs + utility AI + movement
    Mid,  // coarse: needs decay + simple drift
    Far,  // abstract: needs decay only, no movement
}

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct AgentSim {
    // --- Flat component arrays. Index i is the same agent across all of these. ---
    pos: Vec<f32>,        // interleaved x,y : [x0,y0, x1,y1, ...]
    vel: Vec<f32>,        // interleaved x,y velocity
    hunger: Vec<f32>,     // 1.0 = full, 0.0 = starving
    energy: Vec<f32>,     // 1.0 = rested, 0.0 = exhausted
    social: Vec<f32>,     // 1.0 = content, 0.0 = lonely (relatedness, SDT)
    competence: Vec<f32>, // 1.0 = capable, 0.0 = failing (SDT). Restored by success.
    liking: Vec<f32>,     // per-tick hedonic reward output (alliesthesia). Not a need.
    faction: Vec<i32>,    // faction id, -1 = none
    lod: Vec<Lod>,
    count: usize,

    // --- Shared systems ---
    grid: SpatialGrid,
    neighbours: Vec<u32>, // scratch buffer reused across queries
    rng_state: u64,       // tiny xorshift rng, deterministic & fast

    // --- Tunables (exposed to GDScript so you can balance without recompiling) ---
    hunger_rate: f32,
    energy_rate: f32,
    social_rate: f32,
    competence_rate: f32, // competence decays slowest of all needs
    move_speed: f32,

    // --- v1 motivation tunables (see specs/AGENT_CHARACTERS.md §4.1) ---
    // horizon = allostasis look-ahead; salience_gain = incentive-salience weight.
    // Set both to 0.0 to recover the v0 reactive drive-reduction behaviour.
    horizon: f32,
    salience_gain: f32,
    sensory_radius: f32,

    // Camera focus point, set from GDScript each frame, drives LOD.
    focus_x: f32,
    focus_y: f32,
    near_dist: f32,
    mid_dist: f32,

    base: Base<RefCounted>,
}

#[godot_api]
impl AgentSim {
    // Constructor callable from GDScript: AgentSim.create()
    #[func]
    fn create() -> Gd<AgentSim> {
        Gd::from_init_fn(|base| Self {
            pos: Vec::new(),
            vel: Vec::new(),
            hunger: Vec::new(),
            energy: Vec::new(),
            social: Vec::new(),
            competence: Vec::new(),
            liking: Vec::new(),
            faction: Vec::new(),
            lod: Vec::new(),
            count: 0,
            grid: SpatialGrid::new(64.0),
            neighbours: Vec::with_capacity(64),
            rng_state: 0x9E3779B97F4A7C15,
            hunger_rate: 0.02,
            energy_rate: 0.015,
            social_rate: 0.01,
            competence_rate: 0.005,
            move_speed: 40.0,
            horizon: 2.0,
            salience_gain: 0.3,
            sensory_radius: 200.0,
            focus_x: 0.0,
            focus_y: 0.0,
            near_dist: 600.0,
            mid_dist: 1500.0,
            base,
        })
    }

    #[inline]
    fn next_rand(&mut self) -> f32 {
        // xorshift64 -> [0,1)
        let mut x = self.rng_state;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.rng_state = x;
        (x >> 40) as f32 / (1u64 << 24) as f32
    }

    // Spawn one agent at a position. Returns its index (its stable id).
    #[func]
    fn spawn_agent(&mut self, x: f32, y: f32, faction: i32) -> i64 {
        self.pos.push(x);
        self.pos.push(y);
        self.vel.push(0.0);
        self.vel.push(0.0);
        self.hunger.push(1.0);
        self.energy.push(1.0);
        self.social.push(1.0);
        self.competence.push(1.0);
        self.liking.push(0.0);
        self.faction.push(faction);
        self.lod.push(Lod::Far);
        let id = self.count;
        self.count += 1;
        id as i64
    }

    // Bulk spawn for stress testing: scatter N agents in a box.
    #[func]
    fn spawn_many(&mut self, n: i64, min_x: f32, min_y: f32, max_x: f32, max_y: f32, faction: i32) {
        for _ in 0..n {
            let x = min_x + self.next_rand() * (max_x - min_x);
            let y = min_y + self.next_rand() * (max_y - min_y);
            self.spawn_agent(x, y, faction);
        }
    }

    #[func]
    fn set_focus(&mut self, x: f32, y: f32) {
        self.focus_x = x;
        self.focus_y = y;
    }

    #[func]
    fn agent_count(&self) -> i64 {
        self.count as i64
    }

    // Assign LOD per agent based on distance from camera focus.
    fn update_lod(&mut self) {
        let near2 = self.near_dist * self.near_dist;
        let mid2 = self.mid_dist * self.mid_dist;
        for i in 0..self.count {
            let dx = self.pos[i * 2] - self.focus_x;
            let dy = self.pos[i * 2 + 1] - self.focus_y;
            let d2 = dx * dx + dy * dy;
            self.lod[i] = if d2 <= near2 {
                Lod::Near
            } else if d2 <= mid2 {
                Lod::Mid
            } else {
                Lod::Far
            };
        }
    }

    // Utility AI (v1). Behaviour still emerges from which need is most urgent,
    // but each action's score now adds two science-grounded terms on top of the
    // raw homeostatic deficit (see specs/AGENT_CHARACTERS.md §4.1):
    //   * anticipation = decay_rate * horizon  (allostasis: act before the cliff)
    //   * salience      = gain * cue_proximity  (incentive "wanting": nearby cues pull)
    // Completing an action also emits a transient "liking" reward (alliesthesia)
    // and, on success, restores competence. Set horizon = salience_gain = 0 to get
    // the old v0 reactive behaviour back.
    #[inline]
    fn choose_and_act(&mut self, i: usize, delta: f32) {
        self.liking[i] = 0.0; // per-tick output, recomputed below if an action pays off

        let hunger = self.hunger[i];
        let energy = self.energy[i];
        let social = self.social[i];

        // Homeostatic error (deficit from set point).
        let eat_def = 1.0 - hunger;
        let rest_def = 1.0 - energy;
        let soc_def = 1.0 - social;

        // Allostatic anticipation: faster-decaying needs pull earlier.
        let eat_ant = self.hunger_rate * self.horizon;
        let rest_ant = self.energy_rate * self.horizon;
        let soc_ant = self.social_rate * self.horizon;

        // Incentive salience: a relevant cue within sensory_radius amplifies wanting.
        // Eat cue = nearest food source (placeholder: world origin). Rest has no
        // external cue (you can rest anywhere). Social cue = nearest ally.
        let fx = self.pos[i * 2];
        let fy = self.pos[i * 2 + 1];
        let food_d = (fx * fx + fy * fy).sqrt();
        let eat_cue = (1.0 - food_d / self.sensory_radius).max(0.0);
        let (ax, ay, ally_d) = self.nearest_ally(i);
        let soc_cue = if ally_d.is_finite() {
            (1.0 - ally_d / self.sensory_radius).max(0.0)
        } else {
            0.0
        };

        let eat_score = eat_def + eat_ant + self.salience_gain * eat_cue;
        let rest_score = rest_def + rest_ant;
        let social_score = soc_def + soc_ant + self.salience_gain * soc_cue;

        let max = eat_score.max(rest_score).max(social_score);

        let mut success = false;
        if max < 0.25 {
            // All needs reasonably met (inside the homeostatic comfort band) -> wander.
            self.wander(i, delta);
        } else if max == eat_score {
            // Seek food: drift toward origin (placeholder "food source") & refill.
            self.seek(i, 0.0, 0.0, delta);
            let gain = (0.3 * delta).min(1.0 - hunger);
            self.hunger[i] = hunger + gain;
            self.liking[i] = eat_def * gain; // alliesthesia: better when hungrier
            success = true;
        } else if max == rest_score {
            // Rest in place, recover energy.
            self.vel[i * 2] = 0.0;
            self.vel[i * 2 + 1] = 0.0;
            let gain = (0.4 * delta).min(1.0 - energy);
            self.energy[i] = energy + gain;
            self.liking[i] = rest_def * gain;
            success = true;
        } else if ally_d.is_finite() {
            // Socialise: move toward nearest same-faction neighbour.
            self.seek(i, ax, ay, delta);
            let gain = (0.25 * delta).min(1.0 - social);
            self.social[i] = social + gain;
            self.liking[i] = soc_def * gain;
            success = true;
        } else {
            // Wanted company but no ally in range: action fails, drift to look for one.
            self.wander(i, delta);
        }

        // Competence (SDT): restored only by successful action; decays elsewhere.
        if success {
            self.competence[i] = (self.competence[i] + 0.05 * delta).min(1.0);
        }
    }

    #[inline]
    fn wander(&mut self, i: usize, _delta: f32) {
        // Small random steering changes -> organic meandering.
        let jitter = 8.0;
        self.vel[i * 2] += (self.next_rand() - 0.5) * jitter;
        self.vel[i * 2 + 1] += (self.next_rand() - 0.5) * jitter;
        self.clamp_speed(i, self.move_speed * 0.5);
    }

    #[inline]
    fn seek(&mut self, i: usize, tx: f32, ty: f32, _delta: f32) {
        let dx = tx - self.pos[i * 2];
        let dy = ty - self.pos[i * 2 + 1];
        let len = (dx * dx + dy * dy).sqrt().max(0.001);
        self.vel[i * 2] = dx / len * self.move_speed;
        self.vel[i * 2 + 1] = dy / len * self.move_speed;
    }

    #[inline]
    fn clamp_speed(&mut self, i: usize, max: f32) {
        let vx = self.vel[i * 2];
        let vy = self.vel[i * 2 + 1];
        let s = (vx * vx + vy * vy).sqrt();
        if s > max {
            self.vel[i * 2] = vx / s * max;
            self.vel[i * 2 + 1] = vy / s * max;
        }
    }

    // Find the nearest neighbour sharing this agent's faction.
    // Returns (x, y, distance); distance is f32::INFINITY when none is in range,
    // which the caller uses both as the "no ally" flag and to compute cue salience.
    fn nearest_ally(&mut self, i: usize) -> (f32, f32, f32) {
        let x = self.pos[i * 2];
        let y = self.pos[i * 2 + 1];
        let fac = self.faction[i];
        self.grid.query(x, y, self.sensory_radius, &mut self.neighbours);
        let mut best = (x, y);
        let mut best_d2 = f32::INFINITY;
        for &j in self.neighbours.iter() {
            let j = j as usize;
            if j == i || self.faction[j] != fac {
                continue;
            }
            let dx = self.pos[j * 2] - x;
            let dy = self.pos[j * 2 + 1] - y;
            let d2 = dx * dx + dy * dy;
            if d2 < best_d2 {
                best_d2 = d2;
                best = (self.pos[j * 2], self.pos[j * 2 + 1]);
            }
        }
        (best.0, best.1, best_d2.sqrt())
    }

    // The main tick. Called once per frame from GDScript with the frame delta.
    #[func]
    fn tick(&mut self, delta: f32) {
        self.update_lod();
        self.grid.rebuild(&self.pos, self.count);

        for i in 0..self.count {
            // Needs decay everywhere, at all LODs — that's what keeps far-away
            // agents' state consistent so promotion to Near is seamless.
            self.hunger[i] = (self.hunger[i] - self.hunger_rate * delta).max(0.0);
            self.energy[i] = (self.energy[i] - self.energy_rate * delta).max(0.0);
            self.social[i] = (self.social[i] - self.social_rate * delta).max(0.0);
            // Competence decays everywhere too, so a long-idle agent slowly loses
            // its sense of mastery until it succeeds at something again.
            self.competence[i] =
                (self.competence[i] - self.competence_rate * delta).max(0.0);

            match self.lod[i] {
                Lod::Near => {
                    self.choose_and_act(i, delta);
                    self.pos[i * 2] += self.vel[i * 2] * delta;
                    self.pos[i * 2 + 1] += self.vel[i * 2 + 1] * delta;
                }
                Lod::Mid => {
                    // Coarse: keep drifting on current velocity, no AI decision.
                    self.pos[i * 2] += self.vel[i * 2] * delta * 0.5;
                    self.pos[i * 2 + 1] += self.vel[i * 2 + 1] * delta * 0.5;
                }
                Lod::Far => {
                    // Abstract: no movement, needs already decayed above.
                }
            }
        }
    }

    // Hand positions back to Godot as one packed array for MultiMeshInstance2D.
    // Crossing the language boundary once per frame with a packed buffer is the
    // efficient pattern — never call into Rust once per agent.
    #[func]
    fn get_positions(&self) -> PackedVector2Array {
        let mut out = PackedVector2Array::new();
        out.resize(self.count);
        let slice = out.as_mut_slice();
        for i in 0..self.count {
            slice[i] = Vector2::new(self.pos[i * 2], self.pos[i * 2 + 1]);
        }
        out
    }

    // Expose a single agent's needs for the inspector UI.
    #[func]
    fn get_needs(&self, i: i64) -> Dictionary {
        let i = i as usize;
        let mut d = Dictionary::new();
        if i < self.count {
            d.set("hunger", self.hunger[i]);
            d.set("energy", self.energy[i]);
            d.set("social", self.social[i]);
            d.set("competence", self.competence[i]);
            d.set("liking", self.liking[i]);
            d.set("faction", self.faction[i]);
        }
        d
    }
}
