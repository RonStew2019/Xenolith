extends Camera3D
class_name OverworldCamera
## Strategic top-down camera for the hex overworld.
##
## Provides smooth zoom (scroll wheel), pan (middle-mouse drag, WASD/arrows,
## edge-of-screen), and carrier-follow with re-center.  Drop this script
## onto a [Camera3D] node that is a sibling of the Carrier — it auto-discovers
## the follow target in [method _ready].
##
## All input uses raw key codes and mouse buttons so no InputMap setup is
## required.  The camera consumes its own events via [method _unhandled_input]
## so UI layers can intercept first.

# -- Zoom Configuration ---------------------------------------------------

## Minimum zoom distance (closest to ground).
@export var zoom_min: float = 8.0

## Maximum zoom distance (farthest from ground).
@export var zoom_max: float = 45.0

## Zoom change per scroll tick.
@export var zoom_speed: float = 2.0

## Lerp speed for smooth zoom transitions (higher = snappier).
@export var zoom_smoothing: float = 8.0

# -- Pan Configuration ----------------------------------------------------

## Keyboard pan speed in world units per second.
@export var pan_speed: float = 20.0

## Pixels from viewport edge that trigger edge-panning.
@export var edge_pan_margin: float = 30.0

## Edge-pan speed in world units per second.
@export var edge_pan_speed: float = 15.0

# -- Follow Configuration -------------------------------------------------

## Lerp speed when smoothly following the carrier.
@export var follow_smoothing: float = 5.0

# -- Bounds Configuration -------------------------------------------------
# Bounds removed — the map expands dynamically, so fixed clamping would
# trap the camera inside the initial grid.  The camera is free to follow
# the carrier anywhere.

# -- Constants -------------------------------------------------------------

## Default zoom distance.  sqrt(20² + 10²) — matches the original transform.
const DEFAULT_ZOOM: float = 22.360679774997898

## Unit offset direction from target to camera.
## Derived from the original transform: camera at (0, 20, 10) looking at
## origin.  Vector3(0, sin(63.43°), cos(63.43°)).
const OFFSET_DIR: Vector3 = Vector3(0.0, 0.894427, 0.447214)

# -- State -----------------------------------------------------------------

## World-space position the camera orbits around (Y = 0 plane).
var target_position: Vector3 = Vector3.ZERO

## The Node3D being followed (usually the Carrier).
var _follow_node: Node3D = null

## Whether follow mode is active.  Disabled by manual panning,
## re-enabled by pressing the re-center key.
var _is_following: bool = true

## Current interpolated zoom distance.
var _current_zoom: float = DEFAULT_ZOOM

## Desired zoom distance (scroll sets this, _current_zoom lerps toward it).
var _target_zoom: float = DEFAULT_ZOOM

## Whether a middle-mouse drag is in progress.
var _is_dragging: bool = false

## Ground-plane anchor for stable middle-mouse drag panning.
var _drag_ground_anchor: Vector3 = Vector3.ZERO

# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	# Auto-discover carrier sibling.
	if get_parent() != null:
		var carrier := get_parent().get_node_or_null("Carrier")
		if carrier is Node3D:
			set_follow_target(carrier as Node3D)
			target_position = Vector3(carrier.position.x, 0.0, carrier.position.z)
	_apply_transform()


func _process(delta: float) -> void:
	var zoom_weight: float = minf(zoom_smoothing * delta, 1.0)
	_current_zoom = lerpf(_current_zoom, _target_zoom, zoom_weight)

	# -- Keyboard pan --
	var pan_dir := _get_keyboard_pan_direction()
	if pan_dir != Vector2.ZERO:
		_is_following = false
		target_position.x += pan_dir.x * pan_speed * delta
		target_position.z += pan_dir.y * pan_speed * delta

	# -- Edge-of-screen pan --
	var edge_dir := _get_edge_pan_direction()
	if edge_dir != Vector2.ZERO:
		_is_following = false
		target_position.x += edge_dir.x * edge_pan_speed * delta
		target_position.z += edge_dir.y * edge_pan_speed * delta

	# -- Follow target --
	if _is_following and _follow_node != null:
		var goal := Vector3(_follow_node.position.x, 0.0, _follow_node.position.z)
		var follow_weight: float = minf(follow_smoothing * delta, 1.0)
		target_position = target_position.lerp(goal, follow_weight)

	_apply_transform()


func _unhandled_input(event: InputEvent) -> void:
	# -- Zoom via scroll wheel --
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_target_zoom = clampf(_target_zoom - zoom_speed, zoom_min, zoom_max)
					get_viewport().set_input_as_handled()
				MOUSE_BUTTON_WHEEL_DOWN:
					_target_zoom = clampf(_target_zoom + zoom_speed, zoom_min, zoom_max)
					get_viewport().set_input_as_handled()
				MOUSE_BUTTON_MIDDLE:
					_is_dragging = true
					_is_following = false
					_drag_ground_anchor = _screen_to_ground(mb.position)
					get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_is_dragging = false

	# -- Middle-mouse drag pan --
	if event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		var ground_now := _screen_to_ground(mm.position)
		target_position += _drag_ground_anchor - ground_now
		_apply_transform()
		# Re-anchor after the camera moves so dragging stays stable.
		_drag_ground_anchor = _screen_to_ground(mm.position)
		get_viewport().set_input_as_handled()

	# -- Re-center on carrier (Home or F) --
	if event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		if key.keycode == KEY_HOME or key.keycode == KEY_F:
			_recenter_on_target()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_Y:
			if _is_following:
				_is_following = false
				print("[OverworldCamera] Free camera")
			else:
				_recenter_on_target()
			get_viewport().set_input_as_handled()


# -- Public API ------------------------------------------------------------

## Assign a follow target and enable following.
func set_follow_target(node: Node3D) -> void:
	_follow_node = node
	_is_following = true
	print("[OverworldCamera] Following: %s" % node.name)


## Snap follow mode back on (smooth lerp to target).
func recenter() -> void:
	_recenter_on_target()


# -- Private Helpers -------------------------------------------------------

## Re-enable following and log it.
func _recenter_on_target() -> void:
	if _follow_node == null:
		return
	_is_following = true
	print("[OverworldCamera] Re-centering on %s" % _follow_node.name)


## Position the camera at the correct offset from [member target_position]
## and orient it to look at that point.
func _apply_transform() -> void:
	position = target_position + OFFSET_DIR * _current_zoom
	look_at(target_position, Vector3.UP)


## Project a screen-space point onto the Y = 0 ground plane.
func _screen_to_ground(screen_pos: Vector2) -> Vector3:
	var from := project_ray_origin(screen_pos)
	var dir := project_ray_normal(screen_pos)
	if is_zero_approx(dir.y):
		return target_position
	var t: float = -from.y / dir.y
	return from + dir * t


## Read WASD / arrow keys and return a normalised XZ direction.
func _get_keyboard_pan_direction() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if dir.length_squared() > 0.0:
		return dir.normalized()
	return Vector2.ZERO


## Check if the mouse is near any viewport edge and return a pan direction.
func _get_edge_pan_direction() -> Vector2:
	if edge_pan_margin <= 0.0:
		return Vector2.ZERO

	var mouse_pos := get_viewport().get_mouse_position()
	var vp_size := get_viewport().get_visible_rect().size

	# Bail if the cursor is outside the viewport entirely.
	if mouse_pos.x < 0.0 or mouse_pos.y < 0.0 \
			or mouse_pos.x > vp_size.x or mouse_pos.y > vp_size.y:
		return Vector2.ZERO

	var dir := Vector2.ZERO
	if mouse_pos.x < edge_pan_margin:
		dir.x -= 1.0
	elif mouse_pos.x > vp_size.x - edge_pan_margin:
		dir.x += 1.0
	if mouse_pos.y < edge_pan_margin:
		dir.y -= 1.0
	elif mouse_pos.y > vp_size.y - edge_pan_margin:
		dir.y += 1.0
	if dir.length_squared() > 0.0:
		return dir.normalized()
	return Vector2.ZERO
