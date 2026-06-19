extends Node3D
class_name Carrier
## The player's mobile carrier on the hex overworld.
##
## A strategic-layer entity — part aircraft carrier, part oil rig, part
## nuclear plant.  Parks on hex cells, moves via click-to-move, and will
## eventually harvest resources and launch mechs.
##
## Does NOT handle combat — that's the mech layer's job.

# -- Signals ---------------------------------------------------------------

## Emitted after the carrier finishes moving to a new hex.
signal moved(from_hex: Vector2i, to_hex: Vector2i)

## Emitted when the carrier parks on a hex.
signal parked(hex_coords: Vector2i)

# -- Exported Stats --------------------------------------------------------

## Maximum hex distance the carrier can move per action.
@export var move_range: int = 2

## Current hull integrity.
@export var hull: float = 100.0

## Maximum hull integrity.
@export var max_hull: float = 100.0

# -- State -----------------------------------------------------------------

## Current axial position on the hex grid.
var current_hex: Vector2i = Vector2i.ZERO

## Reference to the parent hex grid.  Set via [method initialize] or
## auto-discovered in [method _ready].
var hex_grid: HexGrid = null

## Guards against input while a move tween is running.
var is_moving: bool = false

# -- Constants -------------------------------------------------------------

## Carrier body colour — teal / cyan so it pops against terrain.
const CARRIER_COLOR: Color = Color(0.2, 0.7, 0.8)

## Height offset so the carrier sits visibly on top of the hex prism.
const CARRIER_Y_OFFSET: float = 0.3

## Duration of the movement tween in seconds.
const MOVE_TWEEN_DURATION: float = 0.3

# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	_create_visual()
	# Auto-discover the HexGrid sibling if nobody called initialize() yet.
	if hex_grid == null and get_parent() != null:
		hex_grid = get_parent().get_node_or_null("HexGrid") as HexGrid
	if hex_grid != null and not _is_parked():
		_snap_to_hex(current_hex.x, current_hex.y)
		_park(current_hex.x, current_hex.y)


# -- Public API ------------------------------------------------------------

## Set up the carrier on a specific grid at a starting hex.
func initialize(grid: HexGrid, start_q: int = 0, start_r: int = 0) -> void:
	hex_grid = grid
	_snap_to_hex(start_q, start_r)
	_park(start_q, start_r)


## Move to the target hex with a smooth tween.
##
## Unparks from the current hex, tweens world position, then parks on the
## new hex.  Emits [signal moved] on completion.
func move_to_hex(target_q: int, target_r: int) -> void:
	if is_moving:
		return

	var from := current_hex
	_unpark()

	is_moving = true
	var target_world := hex_grid.axial_to_world(target_q, target_r)
	target_world.y = CARRIER_Y_OFFSET

	var tween := create_tween()
	tween.tween_property(self, "position", target_world, MOVE_TWEEN_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

	current_hex = Vector2i(target_q, target_r)
	is_moving = false
	_park(target_q, target_r)
	moved.emit(from, current_hex)


## Return all hexes reachable this turn (within [member move_range] and
## not blocked by another occupant).
func get_reachable_hexes() -> Array[HexCell]:
	if hex_grid == null:
		return [] as Array[HexCell]

	var candidates := hex_grid.get_cells_in_range(
		current_hex.x, current_hex.y, move_range
	)
	var reachable: Array[HexCell] = []
	for cell: HexCell in candidates:
		# Skip own hex and occupied hexes.
		if cell.axial_coords() == current_hex:
			continue
		if cell.occupant != null:
			continue
		reachable.append(cell)
	return reachable


# -- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if is_moving or hex_grid == null:
		return

	var target := _get_hex_under_mouse(mb)
	if target == current_hex:
		return

	var cell := hex_grid.get_cell(target.x, target.y)
	if cell == null:
		return  # Clicked outside the grid.
	if cell.occupant != null:
		return  # Hex already occupied.

	# Range check — use HexCell.distance_to() for correctness.
	var origin_cell := hex_grid.get_cell(current_hex.x, current_hex.y)
	if origin_cell == null:
		return
	if origin_cell.distance_to(cell) > move_range:
		return

	move_to_hex(target.x, target.y)


# -- Parking (private) ----------------------------------------------------

## Claim a hex cell by setting its occupant to this carrier.
func _park(q: int, r: int) -> void:
	var cell := hex_grid.get_cell(q, r)
	if cell != null:
		cell.occupant = self
	parked.emit(Vector2i(q, r))


## Release the currently occupied hex cell.
func _unpark() -> void:
	var cell := hex_grid.get_cell(current_hex.x, current_hex.y)
	if cell != null:
		cell.occupant = null


## Check whether we're already parked somewhere.
func _is_parked() -> bool:
	if hex_grid == null:
		return false
	var cell := hex_grid.get_cell(current_hex.x, current_hex.y)
	return cell != null and cell.occupant == self


# -- Movement Helpers (private) --------------------------------------------

## Teleport to a hex without tweening.  Used for initial placement.
func _snap_to_hex(q: int, r: int) -> void:
	current_hex = Vector2i(q, r)
	var world_pos := hex_grid.axial_to_world(q, r)
	position = Vector3(world_pos.x, CARRIER_Y_OFFSET, world_pos.z)


## Project the mouse click onto the Y=0 plane and convert to axial coords.
##
## Uses camera ray math — no physics bodies required.
func _get_hex_under_mouse(event: InputEventMouseButton) -> Vector2i:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return current_hex
	var from := camera.project_ray_origin(event.position)
	var dir := camera.project_ray_normal(event.position)
	# Intersect with the Y = 0 plane.
	if is_zero_approx(dir.y):
		return current_hex  # Ray parallel to ground — bail.
	var t := -from.y / dir.y
	var hit := from + dir * t
	return hex_grid.world_to_axial(hit)


# -- Visual Construction (private) ----------------------------------------

## Build a simple placeholder mesh so the carrier is visible on the grid.
##
## A squat teal box — nothing fancy, we'll swap in a real model later.
func _create_visual() -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 0.8, 1.2)
	mesh_instance.mesh = box
	# Shift the mesh up so its base sits at Y=0 of this node (which is
	# already at CARRIER_Y_OFFSET above the hex surface).
	mesh_instance.position.y = box.size.y / 2.0

	var mat := StandardMaterial3D.new()
	mat.albedo_color = CARRIER_COLOR
	mesh_instance.material_override = mat

	add_child(mesh_instance)
