use godot::prelude::*;

mod agent_sim;
mod spatial_grid;

// This struct is the entry point Godot looks for. The `gdextension` macro
// wires it up; the `.gdextension` file in the Godot project points here.
struct AgentSimExtension;

#[gdextension]
unsafe impl ExtensionLibrary for AgentSimExtension {}
