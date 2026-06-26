extends Camera3D
class_name SpectatorCamera
## Free-flying spectator camera for observing the arena after all mechs
## are destroyed.
##
## Provides WASD movement relative to the camera's facing direction and
## mouse look when the mouse is captured.  Click to capture the mouse for
## camera control; press [kbd]Escape[/kbd] to release it (e.g. to interact
## with the self-destruct button).
##
## Created by [EngagementManager] when the last player mech dies.

# -- Constants -------------------------------------------------------------

const MOVE_SPEED := 25.0
const MOUSE_SENSITIVITY := 0.002
const PITCH_LIMIT_DEG := 85.0

# -- State -----------------------------------------------------------------

var _yaw: float = 0.0
var _pitch: float = 0.0


func _ready() -> void:
	current = true
	# Derive initial yaw / pitch from current rotation so the camera
	# doesn't snap when first created.
	_yaw = rotation.y
	_pitch = rotation.x


# -- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Mouse look — only when captured.
	if event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch -= event.relative.y * MOUSE_SENSITIVITY
		_pitch = clampf(
			_pitch,
			deg_to_rad(-PITCH_LIMIT_DEG),
			deg_to_rad(PITCH_LIMIT_DEG),
		)
		rotation = Vector3(_pitch, _yaw, 0.0)
		get_viewport().set_input_as_handled()

	# ESC → release cursor for UI interaction.
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Click → capture cursor for camera control.
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()


# -- Movement --------------------------------------------------------------

func _process(delta: float) -> void:
	var input_dir := Vector3.ZERO

	if Input.is_action_pressed("move_forward"):
		input_dir.z -= 1.0
	if Input.is_action_pressed("move_back"):
		input_dir.z += 1.0
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0
	if Input.is_action_pressed("jump"):
		input_dir.y += 1.0
	if Input.is_key_pressed(KEY_CTRL):
		input_dir.y -= 1.0

	if input_dir != Vector3.ZERO:
		input_dir = input_dir.normalized()
		position += (basis * input_dir) * MOVE_SPEED * delta
