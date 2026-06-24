extends "res://combat/abilities/aoe_projectile_ability.gd"
class_name EMPMortarAbility
## AoE mortar that disrupts enemy reactor venting across a wide blast.
##
## INSTANT mode — one shot per key press.  Fires a slow, wide-radius
## projectile that detonates on impact, dealing 15 heat and applying an
## [EMPEffect] (+3.0 heat/tick for 8 ticks) to every target in the blast.
## 15-heat self-cost reflects the weapon's strategic power.
##
## The [EMPEffect] exactly counteracts the target's ambient venting
## (−3.0 heat/tick), effectively preventing cooling for the duration.
## Lower direct damage than a standard mortar but devastating when
## combined with other heat sources — targets caught in the blast cannot
## shed heat until the EMP wears off.
##
## Tuning:
##   speed     = 18 m/s  (slow, telegraphed arc)
##   radius    = 7.0 m   (wide AoE — slightly larger than Mortar's 6.0)
##   lifetime  = 4.5 s   (long range for area denial)
##   payload   = [PunchEffect] 15 heat + [EMPEffect] per target
##
## Designed for L-Shoulder / R-Shoulder / Artillery weapon slots.

func _init(p_input: String = "ability_1") -> void:
	ability_name = "EMP Mortar"
	input_action = p_input
	activation_mode = ActivationMode.INSTANT
	projectile_speed = 18.0
	projectile_lifetime = 4.5
	explosion_radius = 7.0


func create_self_effects(user: Node) -> Array:
	return [StatusEffect.new("EMP Mortar Cost", 15.0, 1, user, true, false)]


func create_other_effects(user: Node) -> Array:
	return [PunchEffect.new(15.0, 1, user), EMPEffect.new(user)]
