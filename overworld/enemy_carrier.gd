extends ThreatEntity
class_name EnemyCarrier
## A hostile carrier that stalks the player across the hex grid.
##
## KEY MECHANIC: stronger carriers are SLOWER.  High-strength enemies
## lumber toward you giving time to prepare, while weak fast scouts
## punish turtling — rewarding guerrilla play.
##
## Speed is derived from the archetype's virtual module counts using the
## same formula as the player carrier:
##   cooldown_seconds = max(1.0, 2.0 * total_modules - 5.0 * engine_modules)
##   move_interval    = ceil(cooldown_seconds / 5.0)   (turns)
##
## Resulting intervals:
##   Scout    → 1 turn  (fast!)
##   Standard → 1 turn  (nimble)
##   Fortress → 3 turns (slow)

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

## Set combat strength and compute [member move_interval] from archetype modules.
##
## Uses the same formula as the player carrier, converted to turns:
##   cooldown_seconds = max(1.0, 2.0 * total_modules - 5.0 * engine_modules)
##   move_interval    = ceil(cooldown_seconds / 5.0)
func set_strength(value: float) -> void:
	strength = value
	archetype = EnemyCarrierArchetype.for_strength(value)
	# Use the same formula as the player carrier, converted to turns.
	# Turn interval is ~5 seconds, so divide by 5 and round up.
	var cooldown_seconds: float = maxf(1.0, 2.0 * archetype.total_modules - 5.0 * archetype.engine_modules)
	move_interval = maxi(1, ceili(cooldown_seconds / 5.0))
	print("[EnemyCarrier] Strength %.1f → %s, cooldown %.1fs → move every %d turns" % [
		strength, archetype.archetype_name, cooldown_seconds, move_interval,
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
