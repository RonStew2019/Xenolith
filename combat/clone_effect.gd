extends StatusEffect
class_name CloneEffect
## Single-tick pulse that spawns three [CloneMech] entities and splits the
## source mech's reactor capacity evenly across all four bodies (parent + 3
## clones).
##
## Each clone receives a [StatTransferOnDeathEffect] so that when it dies
## its reactor capacity is automatically returned to the parent.  Control
## transfer is handled by [method CloneMech._try_transfer_control].
##
## Stackable: a clone can clone itself (multi-generational splits).

## Number of clones to spawn per activation.
const CLONE_COUNT := 3

## Spawn radius in metres — clones appear in a ring around the source.
const SPAWN_RADIUS := 2.0

## Angle nudges (radians) tried when the preferred position is blocked.
## ≈ 0°, ±30°, ±60° from the ideal angle.
const _ANGLE_NUDGES: Array[float] = [0.0, 0.52, -0.52, 1.05, -1.05]

## Extra radius (metres) added on top of SPAWN_RADIUS when closer positions
## are all blocked.  Tried in order, giving radii of 2, 3, 4, 5, 6 m.
const _RADIUS_STEPS: Array[float] = [0.0, 1.0, 2.0, 3.0, 4.0]

## Minimum safe distance between two capsule centres to avoid overlap.
## Capsule radius is 0.5m × 2 = 1.0m diameter, plus 0.1m tolerance.
const _MIN_SAFE_DISTANCE := 1.1

## Capsule centre Y-offset — must match CloneMech._create_collision_shape().
const _CAPSULE_Y_OFFSET := 0.82


func _init(p_source: Node = null) -> void:
	super._init("Clone", 75.0, 1, p_source, true)


func on_apply(reactor: Node) -> void:
	if not is_instance_valid(source):
		push_warning("CloneEffect: source is null or freed — aborting spawn.")
		return

	# -- 1. Calculate the split (parent + clones) -------------------------
	var entity_count := CLONE_COUNT + 1
	var new_max_heat : float = reactor.max_heat / entity_count
	var new_max_integrity : float = reactor.max_integrity / entity_count

	# -- 2. Reduce the parent's reactor capacity --------------------------
	reactor.max_heat = new_max_heat
	reactor.max_integrity = new_max_integrity
	# Clamp integrity to new ceiling; leave current heat untouched.
	reactor.integrity = minf(reactor.integrity, reactor.max_integrity)

	# -- 3. Spawn clones in a ring around the source ----------------------
	var scene_root := source.get_tree().current_scene

	# Prepare a physics shape query to validate each spawn position.
	# Uses a capsule identical to CloneMech._create_collision_shape().
	var space_state : PhysicsDirectSpaceState3D = source.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()          # defaults: radius 0.5, height 2.0
	query.shape = capsule
	query.collision_mask = source.collision_mask
	query.exclude = [source.get_rid()]

	# Track positions committed this batch so later clones can avoid
	# earlier ones that the physics server hasn't registered yet.
	var batch_positions: Array[Vector3] = []

	for i in CLONE_COUNT:
		var clone := CloneMech.new()
		clone.name = "Clone_%s_%d" % [source.name, i]

		# Wire up the family tree BEFORE add_child so that
		# _ready() → _setup_loadout() can see clone_parent.
		clone.clone_parent = source
		source.clone_children.append(clone)

		# Find a collision-free spawn position before entering the tree.
		var base_angle := (TAU / float(CLONE_COUNT)) * i
		var spawn_pos := _find_clear_position(
			base_angle, source.global_position, space_state, query,
			batch_positions
		)
		batch_positions.append(spawn_pos)

		scene_root.add_child(clone)
		clone.global_position = spawn_pos

		# ReactorCore._ready() has already fired (add_child is synchronous),
		# setting integrity = max_integrity (1000) and heat = 0.  Override
		# the defaults with the split values and reset integrity to match.
		var clone_reactor := clone.get_reactor()
		if clone_reactor:
			clone_reactor.max_heat = new_max_heat
			clone_reactor.max_integrity = new_max_integrity
			clone_reactor.integrity = new_max_integrity
			clone_reactor.heat = 0.0

			# Apply stat-transfer-on-death so dying clones return capacity.
			var transfer := StatTransferOnDeathEffect.new(source, source, 2, -1)
			clone_reactor.apply_effect(transfer)


## Find the nearest unobstructed position for a clone, starting from
## [param base_angle] at [constant SPAWN_RADIUS] around [param origin].
## Tries progressively wider angles and radii.  Also checks against
## [param batch_positions] to avoid overlapping clones spawned earlier
## in the same batch (physics server hasn't registered them yet).
## If all candidates are blocked, places the clone at the outermost
## radius in the preferred direction — never at [param origin] itself.
func _find_clear_position(
	base_angle: float,
	origin: Vector3,
	space_state: PhysicsDirectSpaceState3D,
	query: PhysicsShapeQueryParameters3D,
	batch_positions: Array[Vector3] = [],
) -> Vector3:
	for radius_offset in _RADIUS_STEPS:
		var radius := SPAWN_RADIUS + radius_offset
		for nudge in _ANGLE_NUDGES:
			var angle := base_angle + nudge
			var candidate := origin + Vector3(
				cos(angle) * radius, 0.0, sin(angle) * radius
			)
			# Place the query capsule at the candidate, offset to match the
			# collision-shape centre height.
			query.transform = Transform3D(
				Basis.IDENTITY,
				candidate + Vector3(0.0, _CAPSULE_Y_OFFSET, 0.0)
			)
			# Reject if the physics world has a collision at this spot.
			if not space_state.intersect_shape(query, 1).is_empty():
				continue
			# Reject if too close to any clone already placed in this batch.
			if _overlaps_batch(candidate, batch_positions):
				continue
			return candidate
	# Every candidate blocked — place at outermost radius in the preferred
	# direction.  Never return origin itself (guaranteed overlap).
	var max_radius := SPAWN_RADIUS + _RADIUS_STEPS[-1] + _MIN_SAFE_DISTANCE
	return origin + Vector3(
		cos(base_angle) * max_radius, 0.0, sin(base_angle) * max_radius
	)


## Returns true if [param candidate] is within [constant _MIN_SAFE_DISTANCE]
## of any position in [param batch_positions] (horizontal distance only).
static func _overlaps_batch(
	candidate: Vector3, batch_positions: Array[Vector3]
) -> bool:
	for pos in batch_positions:
		var dx := candidate.x - pos.x
		var dz := candidate.z - pos.z
		if dx * dx + dz * dz < _MIN_SAFE_DISTANCE * _MIN_SAFE_DISTANCE:
			return true
	return false


## Spawns and tracks an AI clone — reflection copy would alias the clone reference.
func duplicate_for_broadcast(_new_source: Node) -> StatusEffect:
	return null
