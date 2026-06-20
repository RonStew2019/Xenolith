extends ProjectileAbility
class_name ScatterBlasterAbility
## Fast, lightweight shoulder weapon for close-range harassment.
##
## INSTANT mode — one shot per key press.  Deals 15 heat on impact with
## only a 4-heat self-cost, making it highly spammable at short range.
##
## Short [member projectile_lifetime] (1.5 s) limits effective range —
## bolts fizzle before reaching distant targets.  High
## [member projectile_speed] (35 m/s) keeps shots snappy up close.
##
## Designed for L-Shoulder / R-Shoulder weapon slots on dogfighter chassis.

func _init(p_input: String = "ability_1") -> void:
	ability_name = "Scatter Blaster"
	input_action = p_input
	activation_mode = ActivationMode.INSTANT
	projectile_speed = 35.0
	projectile_lifetime = 1.5


func create_self_effects(user: Node) -> Array:
	return [StatusEffect.new("Scatter Blaster Cost", 4.0, 1, user, true, false)]


func create_other_effects(user: Node) -> Array:
	return [PunchEffect.new(15.0, 1, user)]
