extends ProjectileAbility
class_name CryoCannonAbility
## Shoulder-mounted cryo weapon that fires bolts inflicting cold and slow.
##
## INSTANT mode — one shot per key press.  Deals 20 heat on impact plus
## a [CryoEffect] that reduces the target's speed by 40% for 10 ticks.
## 8-heat self-cost per shot.
##
## Moderate speed (22 m/s) and decent range (3.5 s lifetime) position it
## between the fast-firing [BlasterAbility] and the sluggish mortars.
## Perfect for dogfighters harassing bombers — the slow debuff makes
## fleeing targets easier to chase down and finish in melee.
##
## Designed for L-Shoulder / R-Shoulder weapon slots.

func _init(p_input: String = "ability_1") -> void:
	ability_name = "Cryo Cannon"
	input_action = p_input
	activation_mode = ActivationMode.INSTANT
	projectile_speed = 22.0
	projectile_lifetime = 3.5


func create_self_effects(user: Node) -> Array:
	return [StatusEffect.new("Cryo Cannon Cost", 8.0, 1, user, true, false)]


func create_other_effects(user: Node) -> Array:
	return [PunchEffect.new(20.0, 1, user), CryoEffect.new(user)]
