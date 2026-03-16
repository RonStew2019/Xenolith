extends CharacterBody3D
## Third-person capsule controller with mouse look. WASD + Space + Mouse.

@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var rotation_speed: float = 10.0
@export var mouse_sensitivity: float = 0.002
@export var pitch_min_deg: float = -60.0
@export var pitch_max_deg: float = 40.0

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _camera_pivot: Node3D = $CameraPivot

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_camera_pivot.rotation.y -= event.relative.x * mouse_sensitivity
		_camera_pivot.rotation.x -= event.relative.y * mouse_sensitivity
		_camera_pivot.rotation.x = clampf(
			_camera_pivot.rotation.x,
			deg_to_rad(pitch_min_deg),
			deg_to_rad(pitch_max_deg),
		)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input_dir.x, 0.0, input_dir.y)
	direction = direction.rotated(Vector3.UP, _camera_pivot.rotation.y).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		var target_angle := atan2(direction.x, direction.z)
		_mesh.rotation.y = lerp_angle(_mesh.rotation.y, target_angle, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
