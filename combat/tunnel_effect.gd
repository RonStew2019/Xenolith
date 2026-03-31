extends StatusEffect
class_name TunnelEffect
## Manages a bi-directional tunnel pair's full lifecycle.
##
## Spawns two linked [TunnelNode] entrances on apply — one at the player's
## feet, another [constant PAIR_DISTANCE] metres in the camera's forward
## direction — and frees them on remove.
##
## Stackable: multiple tunnel pairs can coexist.  Each instance expires
## after 100 ticks (~10 seconds), auto-despawning its pair via
## [method on_remove].
##
## Contributes 75 heat/tick for its duration, making sustained tunnel
## usage a serious reactor commitment.

## Distance (metres) from the player to the second tunnel.
const PAIR_DISTANCE := 20.0

## Vertical offset from CharacterBody3D origin to capsule bottom (floor).
## Derived from player.tscn: CollisionShape3D.y (0.82) - CapsuleShape3D
## half-height (1.0) = -0.18.
const FEET_Y_OFFSET := -0.18

## Currently-placed tunnel entrances (null when none exist).
var _tunnel_a: Node3D = null
var _tunnel_b: Node3D = null


func _init(p_source: Node = null) -> void:
	super._init("Tunnel", 1.0, 300, p_source, true)


func on_apply(_reactor: Node) -> void:
	var scene_root := source.get_tree().current_scene

	# Horizontal forward direction (pitch-flattened).
	var forward: Vector3
	if source._camera_pivot:
		var cam_forward: Vector3 = -source._camera_pivot.global_transform.basis.z
		forward = Vector3(cam_forward.x, 0.0, cam_forward.z).normalized()
	else:
		# AI clones have no camera pivot — derive forward from model facing.
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

	# Tunnel B -- PAIR_DISTANCE metres ahead, same ground level.
	_tunnel_b = TunnelNode.new()
	_tunnel_b.name = "TunnelB"
	scene_root.add_child(_tunnel_b)
	var ahead: Vector3 = origin + forward * PAIR_DISTANCE
	_tunnel_b.global_position = Vector3(ahead.x, floor_y, ahead.z)

	# Link them together.
	_tunnel_a.partner = _tunnel_b
	_tunnel_b.partner = _tunnel_a

	# Immediately send the player through tunnel A → B.
	_tunnel_a.travel(source)


func on_remove(_reactor: Node) -> void:
	if is_instance_valid(_tunnel_a):
		_tunnel_a.queue_free()
	_tunnel_a = null
	if is_instance_valid(_tunnel_b):
		_tunnel_b.queue_free()
	_tunnel_b = null
