extends StatusEffect
class_name TunnelEffect
## Manages a bi-directional tunnel pair's full lifecycle.
##
## Spawns two linked [TunnelNode] entrances on apply — one at the player's
## feet, another [constant PAIR_DISTANCE] metres ahead — and frees them on
## remove.  The "ahead" direction is resolved with a three-tier priority:
##   1. Movement direction — horizontal velocity of the [CharacterBody3D].
##   2. Camera forward  — pitch-flattened camera-pivot Z (stationary player).
##   3. Model forward   — yaw-derived facing (AI clones with no camera).
##
## Stackable: multiple tunnel pairs can coexist.  Each instance expires
## after 100 ticks (~10 seconds), auto-despawning its pair via
## [method on_remove].
##
## Contributes 75 heat/tick for its duration, making sustained tunnel
## usage a serious reactor commitment.

## Distance (metres) from the player to the second tunnel.
const PAIR_DISTANCE := 20.0

## Fallback distances tried when the preferred tunnel-B position is blocked.
## Progresses from full distance down to a minimum safe distance.
const _DISTANCE_STEPS: PackedFloat64Array = [20.0, 15.0, 10.0, 5.0, 3.0]

## Capsule centre Y-offset for collision checks (matches player collision shape).
const _CAPSULE_Y_OFFSET := 0.82

## Vertical offset from CharacterBody3D origin to capsule bottom (floor).
## Derived from player.tscn: CollisionShape3D.y (0.82) - CapsuleShape3D
## half-height (1.0) = -0.18.
const FEET_Y_OFFSET := -0.18

## Currently-placed tunnel entrances (null when none exist).
var _tunnel_a: Node3D = null
var _tunnel_b: Node3D = null


func _init(p_source: Node = null) -> void:
	super._init("Tunnel", 1.0, 300, p_source, true, false)


func on_apply(_reactor: Node) -> void:
	var scene_root := source.get_tree().current_scene

	# Horizontal forward direction — three-tier priority.
	var forward: Vector3

	# Priority 1: movement direction (when the player is moving).
	var hvel := Vector3(source.velocity.x, 0.0, source.velocity.z)
	if hvel.length() > 0.1:
		forward = hvel.normalized()
	elif source._camera_pivot:
		# Priority 2: camera forward (stationary but camera exists).
		var cam_forward: Vector3 = -source._camera_pivot.global_transform.basis.z
		forward = Vector3(cam_forward.x, 0.0, cam_forward.z).normalized()
	else:
		# Priority 3: model forward (AI clones with no camera pivot).
		var yaw: float = source._character.rotation.y if source._character else source.rotation.y
		forward = Vector3(sin(yaw), 0.0, cos(yaw)).normalized()

	# Floor Y derived from capsule geometry.
	var origin: Vector3 = source.global_position
	var floor_y: float = origin.y + FEET_Y_OFFSET

	# Tunnel A -- at the player's feet on the ground.
	_tunnel_a = TunnelNode.new()
	_tunnel_a.name = "TunnelA"
	scene_root.add_child(_tunnel_a)
	_tunnel_a.global_position = Vector3(origin.x, floor_y, origin.z)

	# Tunnel B -- ahead of the player, same ground level.
	# Check the emerge position (where the player surfaces) for collisions.
	# If blocked, try progressively shorter distances.
	var ahead: Vector3 = _find_clear_tunnel_b(origin, forward, source)
	_tunnel_b = TunnelNode.new()
	_tunnel_b.name = "TunnelB"
	scene_root.add_child(_tunnel_b)
	_tunnel_b.global_position = Vector3(ahead.x, floor_y, ahead.z)

	# Link them together.
	_tunnel_a.partner = _tunnel_b
	_tunnel_b.partner = _tunnel_a

	# Immediately send the player through tunnel A → B.
	_tunnel_a.travel(source)


## Find a collision-free position for tunnel B by checking the emerge point
## (where the player will surface after travel) at progressively shorter
## distances.  Uses the source's capsule dimensions for the check.
## Returns the world-space XZ position for tunnel B (Y is set by caller).
func _find_clear_tunnel_b(
	origin: Vector3,
	forward: Vector3,
	p_source: Node,
) -> Vector3:
	var space_state: PhysicsDirectSpaceState3D = p_source.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()  # defaults: radius 0.5, height 2.0
	query.shape = capsule
	query.collision_mask = p_source.collision_mask
	query.exclude = [p_source.get_rid()]

	for dist in _DISTANCE_STEPS:
		var candidate: Vector3 = origin + forward * dist
		# Check at the emerge position (capsule centre height + travel offset).
		var emerge_centre := candidate + Vector3(
			0.0, _CAPSULE_Y_OFFSET + TunnelNode.TRAVEL_Y_OFFSET, 0.0
		)
		query.transform = Transform3D(Basis.IDENTITY, emerge_centre)
		if space_state.intersect_shape(query, 1).is_empty():
			return candidate

	# All distances blocked -- use the shortest fallback distance.
	return origin + forward * _DISTANCE_STEPS[-1]


func on_remove(_reactor: Node) -> void:
	if is_instance_valid(_tunnel_a):
		_tunnel_a.queue_free()
	_tunnel_a = null
	if is_instance_valid(_tunnel_b):
		_tunnel_b.queue_free()
	_tunnel_b = null
