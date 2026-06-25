extends ThreatEntity
class_name EnemyCarrier
## A hostile carrier that stalks the player across the hex grid.
##
## KEY MECHANIC: stronger carriers are SLOWER.  High-strength enemies
## lumber toward you giving time to prepare, while weak fast scouts
## punish turtling — rewarding guerrilla play.
##
## Strength → speed mapping (linear interpolation):
##   strength 1.0  → move_interval = 2 (fastest)
##   strength 5.0  → move_interval = 5 (moderate)
##   strength 10.0 → move_interval = 8 (slowest)

# -- Properties ------------------------------------------------------------

## Combat power — determines difficulty and mech complement in engagement.
var strength: float = 1.0

## Archetype (scout/standard/fortress) — set automatically by [method set_strength].
var archetype: EnemyCarrierArchetype = null

## Turns between moves.  Higher = slower.  Derived from [member strength]
## via [method set_strength].
var move_interval: int = 2

## Internal turn counter — resets to 0 after each move.
var _turns_since_move: int = 0

## Reference to the player carrier, set by [ThreatManager] after spawn.
var _target_carrier: Carrier = null

# -- Constants -------------------------------------------------------------

## Angry red — the enemy is clearly hostile.
const ENEMY_COLOR: Color = Color(0.8, 0.2, 0.15)

## Weakest carriers move every 2 turns (fastest).
const MIN_MOVE_INTERVAL: int = 2

## Strongest carriers move every 8 turns (slowest).
const MAX_MOVE_INTERVAL: int = 8

# -- Overrides -------------------------------------------------------------

## Increment turn counter; move one hex toward the player when ready.
func take_turn() -> void:
	_turns_since_move += 1
	if _turns_since_move >= move_interval:
		_turns_since_move = 0
		if _target_carrier != null:
			_move_toward_carrier(_target_carrier.current_hex)


## Return the threat type identifier.
func get_threat_type() -> StringName:
	return &"enemy_carrier"


## Create a tinted box whose color and scale come from the archetype.
func _create_visual() -> void:
	var color: Color = archetype.color if archetype != null else ENEMY_COLOR
	var scale_factor: Vector3 = archetype.box_scale if archetype != null else Vector3.ONE
	var base_size := Vector3(1.0, 0.7, 1.0) * scale_factor
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = base_size
	mesh_instance.mesh = box
	mesh_instance.position.y = base_size.y / 2.0
	mesh_instance.material_override = _make_material(color)
	add_child(mesh_instance)
	_visual = mesh_instance


# -- Public API ------------------------------------------------------------

## Set combat strength and compute [member move_interval] from it.
##
## Uses linear interpolation between [constant MIN_MOVE_INTERVAL] and
## [constant MAX_MOVE_INTERVAL] based on strength 1.0–10.0.
func set_strength(value: float) -> void:
	strength = value
	archetype = EnemyCarrierArchetype.for_strength(value)
	var t: float = clampf((strength - 1.0) / 9.0, 0.0, 1.0)
	move_interval = roundi(lerpf(float(MIN_MOVE_INTERVAL), float(MAX_MOVE_INTERVAL), t))
	print("[EnemyCarrier] Strength %.1f → %s, move every %d turns" % [
		strength, archetype.archetype_name, move_interval,
	])


# -- Private Helpers -------------------------------------------------------

## Move one hex toward [param target_hex], picking the best unoccupied
## neighbor.  If all neighbors toward the target are blocked, skip.
func _move_toward_carrier(target_hex: Vector2i) -> void:
	if hex_grid == null:
		return

	var neighbors: Array[HexCell] = hex_grid.get_neighbors(current_hex.x, current_hex.y)
	if neighbors.is_empty():
		return

	# Find the unoccupied neighbor closest to the target.
	var target_cell: HexCell = hex_grid.get_cell(target_hex.x, target_hex.y)
	if target_cell == null:
		return

	var best_cell: HexCell = null
	var best_dist: int = 999

	for cell: HexCell in neighbors:
		if cell.occupant != null:
			continue
		var dist: int = cell.distance_to(target_cell)
		if dist < best_dist:
			best_dist = dist
			best_cell = cell

	if best_cell == null:
		return  # All paths blocked — wait.

	var from: Vector2i = current_hex
	_snap_to_hex(best_cell.q, best_cell.r)
	print("[EnemyCarrier] Moved (%d,%d) → (%d,%d)" % [from.x, from.y, current_hex.x, current_hex.y])
