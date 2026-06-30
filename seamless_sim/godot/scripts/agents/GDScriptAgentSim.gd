extends RefCounted
class_name GDScriptAgentSim
## A pure-GDScript mirror of the Rust AgentSim's public API. Lets you run and
## test the whole project before (or without) compiling the Rust extension.
## Comfortably handles a couple thousand agents; for tens of thousands, compile
## the Rust crate, which exposes the identical method names so nothing else
## changes.

var _pos := PackedFloat32Array()
var _vel := PackedFloat32Array()
var _hunger := PackedFloat32Array()
var _energy := PackedFloat32Array()
var _social := PackedFloat32Array()          # relatedness (SDT)
var _competence := PackedFloat32Array()       # capability (SDT); restored by success
var _liking := PackedFloat32Array()           # per-tick hedonic reward (alliesthesia)
var _faction := PackedInt32Array()
var _count := 0

var _focus := Vector2.ZERO
const NEAR_DIST2 := 600.0 * 600.0
const MOVE_SPEED := 40.0

# Need decay rates (per second). Hunger fastest, competence slowest.
const HUNGER_RATE := 0.02
const ENERGY_RATE := 0.015
const SOCIAL_RATE := 0.01
const COMPETENCE_RATE := 0.005

# v1 motivation tunables (see specs/AGENT_CHARACTERS.md §4.1).
# horizon = allostatic look-ahead; salience_gain = incentive-salience cue weight.
# Set both to 0.0 to recover the v0 reactive drive-reduction behaviour.
const HORIZON := 2.0
const SALIENCE_GAIN := 0.3
const SENSORY_RADIUS := 200.0
# NOTE: this fallback has no spatial grid, so it computes eat-cue salience (food
# at the origin placeholder) but not social-cue salience. The Rust backend does
# both. See spec §10 "Backend differences".

func spawn_agent(x: float, y: float, faction: int) -> int:
	_pos.append(x); _pos.append(y)
	_vel.append(0.0); _vel.append(0.0)
	_hunger.append(1.0)
	_energy.append(1.0)
	_social.append(1.0)
	_competence.append(1.0)
	_liking.append(0.0)
	_faction.append(faction)
	var id := _count
	_count += 1
	return id

func spawn_many(n: int, min_x: float, min_y: float, max_x: float, max_y: float, faction: int) -> void:
	for i in n:
		spawn_agent(
			randf_range(min_x, max_x),
			randf_range(min_y, max_y),
			faction
		)

func set_focus(x: float, y: float) -> void:
	_focus = Vector2(x, y)

func agent_count() -> int:
	return _count

func tick(delta: float) -> void:
	for i in _count:
		# Needs decay everywhere, all LODs (keeps off-screen state consistent).
		_hunger[i] = maxf(_hunger[i] - HUNGER_RATE * delta, 0.0)
		_energy[i] = maxf(_energy[i] - ENERGY_RATE * delta, 0.0)
		_social[i] = maxf(_social[i] - SOCIAL_RATE * delta, 0.0)
		_competence[i] = maxf(_competence[i] - COMPETENCE_RATE * delta, 0.0)

		# Only full-sim agents near the camera run AI + movement (LOD).
		var dx := _pos[i * 2] - _focus.x
		var dy := _pos[i * 2 + 1] - _focus.y
		if dx * dx + dy * dy > NEAR_DIST2:
			continue

		_liking[i] = 0.0 # per-tick output, set below if an action pays off

		var h := _hunger[i]
		var e := _energy[i]
		var s := _social[i]

		# v1 utility AI: score = deficit + allostatic anticipation + cue salience.
		var eat_def := 1.0 - h
		var rest_def := 1.0 - e
		var soc_def := 1.0 - s

		var eat_ant := HUNGER_RATE * HORIZON
		var rest_ant := ENERGY_RATE * HORIZON
		var soc_ant := SOCIAL_RATE * HORIZON

		# Eat cue = food source (placeholder at origin). Closer food pulls harder.
		var food_d := sqrt(_pos[i * 2] * _pos[i * 2] + _pos[i * 2 + 1] * _pos[i * 2 + 1])
		var eat_cue := maxf(1.0 - food_d / SENSORY_RADIUS, 0.0)

		var eat := eat_def + eat_ant + SALIENCE_GAIN * eat_cue
		var rest := rest_def + rest_ant
		var soc := soc_def + soc_ant # no spatial grid here -> no social cue term
		var m := maxf(eat, maxf(rest, soc))

		var gain := 0.0
		var success := false
		if m < 0.25:
			# Inside the homeostatic comfort band -> wander.
			_vel[i * 2] += randf_range(-4.0, 4.0)
			_vel[i * 2 + 1] += randf_range(-4.0, 4.0)
		elif m == eat:
			_seek(i, 0.0, 0.0)
			gain = minf(0.3 * delta, 1.0 - h)
			_hunger[i] = h + gain
			_liking[i] = eat_def * gain # alliesthesia: better when hungrier
			success = true
		elif m == rest:
			_vel[i * 2] = 0.0; _vel[i * 2 + 1] = 0.0
			gain = minf(0.4 * delta, 1.0 - e)
			_energy[i] = e + gain
			_liking[i] = rest_def * gain
			success = true
		else:
			gain = minf(0.25 * delta, 1.0 - s)
			_social[i] = s + gain
			_liking[i] = soc_def * gain
			success = true

		# Competence (SDT): restored only by successful action.
		if success:
			_competence[i] = minf(_competence[i] + 0.05 * delta, 1.0)

		_pos[i * 2] += _vel[i * 2] * delta
		_pos[i * 2 + 1] += _vel[i * 2 + 1] * delta

func _seek(i: int, tx: float, ty: float) -> void:
	var dx := tx - _pos[i * 2]
	var dy := ty - _pos[i * 2 + 1]
	var len := maxf(sqrt(dx * dx + dy * dy), 0.001)
	_vel[i * 2] = dx / len * MOVE_SPEED
	_vel[i * 2 + 1] = dy / len * MOVE_SPEED

func get_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(_count)
	for i in _count:
		out[i] = Vector2(_pos[i * 2], _pos[i * 2 + 1])
	return out

func get_needs(i: int) -> Dictionary:
	if i < 0 or i >= _count:
		return {}
	return {
		"hunger": _hunger[i],
		"energy": _energy[i],
		"social": _social[i],
		"competence": _competence[i],
		"liking": _liking[i],
		"faction": _faction[i],
	}
