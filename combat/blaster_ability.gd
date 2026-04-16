extends ProjectileAbility
class_name BlasterAbility
## Fires a single heat bolt that deals 30 heat on impact.
## INSTANT mode — one shot per key press, no persistent state.
##
## Payload: a [PunchEffect] (single-tick heat spike) carried by the
## [Projectile] and applied to the first character it contacts.
## Uses 30 heat (vs melee's 50) to reflect the range advantage.

func _init(p_input: String = "ability_3") -> void:
	ability_name = "Blaster"
	input_action = p_input
	activation_mode = ActivationMode.INSTANT
	projectile_speed = 30.0
	projectile_lifetime = 3.0


func create_self_effects(user: Node) -> Array:
	return [StatusEffect.new("Blaster Cost", 7.0, 1, user, true, false)]


func create_other_effects(user: Node) -> Array:
	return [PunchEffect.new(30.0, 1, user)]
