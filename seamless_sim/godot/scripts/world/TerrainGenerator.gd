extends RefCounted
class_name TerrainGenerator
## Organic biome generation from layered noise. No biome IDs hardcoded into a
## map — biomes emerge from the interaction of elevation and moisture, exactly
## like the real world. Same coordinate always yields the same biome, so the
## infinite world is deterministic and needs no storage until modified.

# Biome atlas column indices (row 0 of your tileset).
const WATER := 0
const SAND := 1
const GRASS := 2
const FOREST := 3
const ROCK := 4
const SNOW := 5

var _elevation := FastNoiseLite.new()
var _moisture := FastNoiseLite.new()

func _init(seed: int = 1337) -> void:
	_elevation.noise_type = FastNoiseLite.TYPE_PERLIN
	_elevation.seed = seed
	_elevation.frequency = 0.008
	_elevation.fractal_octaves = 4

	_moisture.noise_type = FastNoiseLite.TYPE_PERLIN
	_moisture.seed = seed + 99
	_moisture.frequency = 0.012
	_moisture.fractal_octaves = 3

## Returns the biome atlas column for a tile in world tile-coordinates.
func biome_at(tx: int, ty: int) -> int:
	# Noise returns roughly [-1, 1]; remap to [0, 1].
	var e := (_elevation.get_noise_2d(tx, ty) + 1.0) * 0.5
	var m := (_moisture.get_noise_2d(tx, ty) + 1.0) * 0.5

	if e < 0.30:
		return WATER
	if e < 0.35:
		return SAND
	if e > 0.78:
		return SNOW
	if e > 0.68:
		return ROCK
	# Mid elevations: moisture decides grass vs forest.
	if m > 0.55:
		return FOREST
	return GRASS

## Elevation in [0,1] — useful later for movement cost, farming suitability, etc.
func elevation_at(tx: int, ty: int) -> float:
	return (_elevation.get_noise_2d(tx, ty) + 1.0) * 0.5
