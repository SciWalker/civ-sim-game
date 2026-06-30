extends Camera2D
class_name WorldCamera
## Free-roaming camera. There are no map edges and no mode switches — you pan
## anywhere in the single continuous world. WASD/arrows to move, scroll to zoom,
## middle-mouse drag to pan.

@export var pan_speed: float = 600.0
@export var zoom_step: float = 0.1
@export var zoom_min: float = 0.2
@export var zoom_max: float = 4.0

var _dragging := false

func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		dir.x += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		dir.y += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		dir.y -= 1
	# Divide by zoom so pan speed feels constant at any zoom level.
	global_position += dir.normalized() * pan_speed * delta / zoom.x

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_apply_zoom(zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_apply_zoom(-zoom_step)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		global_position -= event.relative / zoom.x

func _apply_zoom(amount: float) -> void:
	var z := clampf(zoom.x + amount, zoom_min, zoom_max)
	zoom = Vector2(z, z)
