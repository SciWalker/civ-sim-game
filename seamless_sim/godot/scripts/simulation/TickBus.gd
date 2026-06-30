extends Node
## Global simulation heartbeat. Everything that must stay in sync subscribes
## to these signals rather than polling. Autoloaded as "TickBus".
##
## We run the simulation on a FIXED timestep (independent of render framerate)
## so the world behaves identically whether you're at 30 or 144 fps. Rendering
## interpolates between the last two sim states for smoothness.

signal sim_tick(delta: float)        ## fired every fixed simulation step
signal day_passed(day: int)          ## fired once per in-game day
signal season_changed(season: int)   ## 0=spring 1=summer 2=autumn 3=winter

const SIM_HZ: float = 20.0                  ## simulation steps per second
const SIM_DT: float = 1.0 / SIM_HZ
const TICKS_PER_DAY: int = 400              ## ~20s real-time per day at 1x speed

var time_scale: float = 1.0                 ## 0 = paused, 1 = normal, >1 = fast
var _accumulator: float = 0.0
var _tick_count: int = 0
var _day: int = 0

func _process(delta: float) -> void:
	if time_scale <= 0.0:
		return
	_accumulator += delta * time_scale
	# Drain the accumulator in fixed steps. Cap iterations to avoid a spiral
	# of death if the game hitches.
	var steps := 0
	while _accumulator >= SIM_DT and steps < 8:
		_accumulator -= SIM_DT
		_advance_one_tick()
		steps += 1

func _advance_one_tick() -> void:
	sim_tick.emit(SIM_DT)
	_tick_count += 1
	if _tick_count % TICKS_PER_DAY == 0:
		_day += 1
		day_passed.emit(_day)
		var season := _day / 30 % 4
		if _day % 30 == 0:
			season_changed.emit(season)

func current_day() -> int:
	return _day

func set_paused(p: bool) -> void:
	time_scale = 0.0 if p else 1.0
