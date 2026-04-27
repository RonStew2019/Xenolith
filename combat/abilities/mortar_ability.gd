extends "res://combat/abilities/aoe_projectile_ability.gd"
class_name MortarAbility
## Fires a slower AoE projectile that explodes on impact, dealing 25 heat
## to every character in the blast radius.
##
## INSTANT mode — one shot per key press.
##
## Tuning:
##   speed     = 20 m/s  (slower than Blaster's 30)
##   radius    = 6.0 m   (wide blast)
##   lifetime  = 4.0 s   (longer flight before auto-detonate)
##   payload   = [PunchEffect] 25 heat per target

func _init(p_input: String = "ability_4") -> void:
	ability_name = "Mortar"
	input_action = p_input
	activation_mode = ActivationMode.INSTANT
	projectile_speed = 20.0
	projectile_lifetime = 4.0
	explosion_radius = 6.0


func create_self_effects(user: Node) -> Array:
	return [StatusEffect.new("Mortar Cost", 12.0, 1, user, true, false)]


func create_other_effects(user: Node) -> Array:
	return [PunchEffect.new(25.0, 1, user)]
