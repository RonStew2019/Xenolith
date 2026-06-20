extends ProjectileAbility
class_name HeatCannonAbility
## Fires a heat bolt from shoulder or artillery mounts.
##
## INSTANT mode — one shot per key press.  Deals 40 heat on impact with
## a 10-heat self-cost per shot.  Slightly slower and longer-ranged than
## the [BlasterAbility] to reflect its role as a mounted weapon.
##
## Designed for L-Shoulder / R-Shoulder / Artillery weapon slots.

func _init(p_input: String = "ability_1") -> void:
	ability_name = "Heat Cannon"
	input_action = p_input
	activation_mode = ActivationMode.INSTANT
	projectile_speed = 25.0
	projectile_lifetime = 4.0


func create_self_effects(user: Node) -> Array:
	return [StatusEffect.new("Heat Cannon Cost", 10.0, 1, user, true, false)]


func create_other_effects(user: Node) -> Array:
	return [PunchEffect.new(40.0, 1, user)]
