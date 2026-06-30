extends MultiMeshInstance2D
class_name AgentRenderer
## Renders all agents in a single batched draw call via MultiMesh. This is the
## rendering equivalent of the flat-array data model: drawing 3,000 agents costs
## ~one draw call instead of 3,000 nodes. Positions come from the Rust sim each
## tick as one packed array (the only language-boundary crossing per frame).
##
## If the Rust extension isn't compiled yet, it transparently falls back to a
## pure-GDScript sim so you can run the project immediately.

const AGENT_COUNT := 3000
const WORLD_HALF := 4000.0   ## spawn agents within +/- this range

var _sim                      ## either the Rust AgentSim or the GDScript fallback
var _using_rust := false

@export var camera_path: NodePath
var _camera: Camera2D

func _ready() -> void:
	_camera = get_node_or_null(camera_path)
	_setup_multimesh()
	_setup_sim()
	TickBus.sim_tick.connect(_on_sim_tick)

func _setup_multimesh() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	# A small quad mesh as the per-agent sprite. Swap for a textured quad later.
	var quad := QuadMesh.new()
	quad.size = Vector2(6, 6)
	mm.mesh = quad
	mm.instance_count = AGENT_COUNT
	multimesh = mm

func _setup_sim() -> void:
	# Try the Rust class first; fall back to GDScript if not present.
	if ClassDB.class_exists("AgentSim"):
		_sim = ClassDB.instantiate("AgentSim").create()
		_using_rust = true
	else:
		_sim = GDScriptAgentSim.new()
		_using_rust = false
		push_warning("Rust AgentSim not found — using slower GDScript fallback. "
			+ "Compile the Rust crate for full performance.")

	# Two factions scattered across the world.
	_sim.spawn_many(AGENT_COUNT / 2, -WORLD_HALF, -WORLD_HALF, WORLD_HALF, WORLD_HALF, 0)
	_sim.spawn_many(AGENT_COUNT / 2, -WORLD_HALF, -WORLD_HALF, WORLD_HALF, WORLD_HALF, 1)

func _on_sim_tick(delta: float) -> void:
	if _camera:
		_sim.set_focus(_camera.global_position.x, _camera.global_position.y)
	_sim.tick(delta)

func _process(_delta: float) -> void:
	# Render every frame using the latest sim positions.
	var positions: PackedVector2Array = _sim.get_positions()
	var n: int = min(positions.size(), multimesh.instance_count)
	for i in n:
		var t := Transform2D(0.0, positions[i])
		multimesh.set_instance_transform_2d(i, t)
		# Tint by faction parity for a quick visual read.
		multimesh.set_instance_color(i, Color(0.4, 0.8, 1.0) if i % 2 == 0 else Color(1.0, 0.6, 0.3))

func is_using_rust() -> bool:
	return _using_rust

func sim() -> Variant:
	return _sim
