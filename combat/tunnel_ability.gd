extends Ability
class_name TunnelAbility
## Place a pair of bi-directional tunnel entrances.
##
## INSTANT activation -- press to spawn two [TunnelNode]s: one at the
## player's feet, another 20 m in the camera's forward direction.
## Recasting despawns the old pair before spawning a new one.
## Walking near either entrance and pressing Q teleports to the other.
##
## This ability is pure utility -- no StatusEffects, no heat, no reactor
## interaction.  It overrides [method activate] entirely.

## Currently-placed tunnel entrances (null when none exist).
var _tunnel_a: Node3D = null
var _tunnel_b: Node3D = null

## Distance (metres) from the player to the second tunnel.
const PAIR_DISTANCE := 20.0

## Vertical offset from CharacterBody3D origin to capsule bottom (floor).
## Derived from player.tscn: CollisionShape3D.y (0.82) - CapsuleShape3D
## half-height (1.0) = -0.18.
const FEET_Y_OFFSET := -0.18


func _init(p_input: String = "ability_2") -> void:
	ability_name = "Tunnel"
	input_action = p_input
	activation_mode = ActivationMode.INSTANT


## Override -- skip the reactor/effect pipeline entirely.
func activate(user: Node) -> void:
	_despawn_tunnels()
	_spawn_tunnels(user)


## Override -- clean up tunnels even though INSTANT never sets _active.
func force_deactivate(_user: Node) -> void:
	_despawn_tunnels()


# -- Internals -------------------------------------------------------------

func _spawn_tunnels(user: Node) -> void:
	var scene_root := user.get_tree().current_scene

	# Horizontal forward from the camera pivot (pitch-flattened).
	var cam_forward: Vector3 = -user._camera_pivot.global_transform.basis.z
	var forward := Vector3(cam_forward.x, 0.0, cam_forward.z).normalized()

	# Floor Y: player origin sits below the capsule bottom by FEET_Y_OFFSET.
	var origin: Vector3 = user.global_position
	var floor_y: float = origin.y + FEET_Y_OFFSET

	# Tunnel A -- at the player's feet on the ground.
	_tunnel_a = TunnelNode.new()
	_tunnel_a.name = "TunnelA"
	scene_root.add_child(_tunnel_a)
	_tunnel_a.global_position = Vector3(origin.x, floor_y, origin.z)

	# Tunnel B -- 20 m ahead, same ground level.
	_tunnel_b = TunnelNode.new()
	_tunnel_b.name = "TunnelB"
	scene_root.add_child(_tunnel_b)
	var ahead: Vector3 = origin + forward * PAIR_DISTANCE
	_tunnel_b.global_position = Vector3(ahead.x, floor_y, ahead.z)

	# Link them together.
	_tunnel_a.partner = _tunnel_b
	_tunnel_b.partner = _tunnel_a


func _despawn_tunnels() -> void:
	if is_instance_valid(_tunnel_a):
		_tunnel_a.queue_free()
	_tunnel_a = null
	if is_instance_valid(_tunnel_b):
		_tunnel_b.queue_free()
	_tunnel_b = null
