// A uniform spatial hash grid. This is the single most important data structure
// for scaling: it lets any agent ask "who is near me?" without scanning all
// other agents. Without it, agent interactions are O(n^2) and you stall at a
// few hundred agents. With it, neighbour queries are roughly O(1).

use std::collections::HashMap;

pub struct SpatialGrid {
    cell_size: f32,
    // Maps a cell coordinate to the list of agent indices currently in it.
    cells: HashMap<(i32, i32), Vec<u32>>,
}

impl SpatialGrid {
    pub fn new(cell_size: f32) -> Self {
        Self {
            cell_size,
            cells: HashMap::new(),
        }
    }

    #[inline]
    fn cell_of(&self, x: f32, y: f32) -> (i32, i32) {
        (
            (x / self.cell_size).floor() as i32,
            (y / self.cell_size).floor() as i32,
        )
    }

    // Rebuild the grid from scratch each tick. For sub-5k agents this is cheap
    // and far simpler than incremental updates. Revisit only if profiling says so.
    pub fn rebuild(&mut self, positions: &[f32], count: usize) {
        for v in self.cells.values_mut() {
            v.clear();
        }
        for i in 0..count {
            let x = positions[i * 2];
            let y = positions[i * 2 + 1];
            let cell = self.cell_of(x, y);
            self.cells.entry(cell).or_default().push(i as u32);
        }
    }

    // Return all agent indices within `radius` of (x, y). Checks only the cells
    // overlapping the query circle, not the whole world.
    pub fn query(&self, x: f32, y: f32, radius: f32, out: &mut Vec<u32>) {
        out.clear();
        let r_cells = (radius / self.cell_size).ceil() as i32;
        let (cx, cy) = self.cell_of(x, y);
        for dy in -r_cells..=r_cells {
            for dx in -r_cells..=r_cells {
                if let Some(ids) = self.cells.get(&(cx + dx, cy + dy)) {
                    out.extend_from_slice(ids);
                }
            }
        }
    }
}
