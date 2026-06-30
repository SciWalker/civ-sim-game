extends CanvasLayer
class_name DebugHUD
## On-screen diagnostics + time controls. Press 1/2/3 for speed, Space to pause.
## This is your profiling window: watch FPS as you change AGENT_COUNT to find
## your machine's ceiling in each backend (GDScript vs Rust).

@export var agent_renderer_path: NodePath
@export var chunk_manager_path: NodePath

var _label: Label
var _renderer: AgentRenderer
var _chunks: ChunkManager

func _ready() -> void:
	_renderer = get_node_or_null(agent_renderer_path)
	_chunks = get_node_or_null(chunk_manager_path)

	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)

func _process(_delta: float) -> void:
	var backend := "Rust" if (_renderer and _renderer.is_using_rust()) else "GDScript"
	var agents := 0
	if _renderer and _renderer.sim():
		agents = _renderer.sim().agent_count()
	var chunks := 0
	if _chunks:
		chunks = _chunks.loaded_chunk_count()

	_label.text = "FPS: %d\nAgents: %d\nBackend: %s\nChunks loaded: %d\nDay: %d  Speed: %.0fx\n[WASD] pan  [scroll] zoom  [space] pause  [1/2/3] speed" % [
		Engine.get_frames_per_second(),
		agents,
		backend,
		chunks,
		TickBus.current_day(),
		TickBus.time_scale,
	]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				TickBus.set_paused(TickBus.time_scale > 0.0)
			KEY_1:
				TickBus.time_scale = 1.0
			KEY_2:
				TickBus.time_scale = 3.0
			KEY_3:
				TickBus.time_scale = 8.0
