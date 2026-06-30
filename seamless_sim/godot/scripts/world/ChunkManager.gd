extends Node2D
class_name ChunkManager
## Streams terrain chunks in and out around the camera so the world feels
## infinite and seamless — there is only ever ONE coordinate space, no map
## transitions. Chunks far from view are freed; chunks near view are generated
## on demand.
##
## This handles only TERRAIN. Agents live in the Rust sim in world coordinates
## and are unaffected by which chunks are currently loaded — they keep existing
## (at low LOD) even where no chunk is rendered.

const CHUNK_SIZE: int = 32          ## tiles per chunk side
const TILE_SIZE: int = 16           ## pixels per tile
const LOAD_RADIUS: int = 3          ## chunks loaded around camera, each axis

const CHUNK_PX: int = CHUNK_SIZE * TILE_SIZE

@export var camera_path: NodePath

var _loaded: Dictionary = {}        ## Vector2i -> Node2D (the chunk)
var _camera: Camera2D
var _terrain := TerrainGenerator.new()

func _ready() -> void:
	_camera = get_node_or_null(camera_path)

func _process(_delta: float) -> void:
	if _camera == null:
		return
	var center := _world_to_chunk(_camera.global_position)
	_ensure_loaded(center)
	_unload_far(center)

func _world_to_chunk(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / CHUNK_PX),
		floori(world_pos.y / CHUNK_PX)
	)

func _ensure_loaded(center: Vector2i) -> void:
	for cy in range(center.y - LOAD_RADIUS, center.y + LOAD_RADIUS + 1):
		for cx in range(center.x - LOAD_RADIUS, center.x + LOAD_RADIUS + 1):
			var key := Vector2i(cx, cy)
			if not _loaded.has(key):
				_loaded[key] = _build_chunk(key)

func _unload_far(center: Vector2i) -> void:
	var to_free: Array = []
	for key in _loaded.keys():
		if absi(key.x - center.x) > LOAD_RADIUS or absi(key.y - center.y) > LOAD_RADIUS:
			to_free.append(key)
	for key in to_free:
		_loaded[key].queue_free()
		_loaded.erase(key)

func _build_chunk(coord: Vector2i) -> Node2D:
	# Each chunk is its own TileMapLayer positioned in world space.
	var layer := TileMapLayer.new()
	layer.position = Vector2(coord.x * CHUNK_PX, coord.y * CHUNK_PX)
	# NOTE: assign a TileSet resource in the editor or load one here.
	# layer.tile_set = preload("res://assets/terrain_tileset.tres")
	for ty in CHUNK_SIZE:
		for tx in CHUNK_SIZE:
			var world_tx := coord.x * CHUNK_SIZE + tx
			var world_ty := coord.y * CHUNK_SIZE + ty
			var biome := _terrain.biome_at(world_tx, world_ty)
			layer.set_cell(Vector2i(tx, ty), 0, Vector2i(biome, 0))
	add_child(layer)
	return layer

func loaded_chunk_count() -> int:
	return _loaded.size()
