extends "res://combat/abilities/aoe_projectile_ability.gd"
class_name ArtilleryMortarAbility
## Bomber-exclusive heavy artillery weapon — devastating AoE at long range.
##
## INSTANT mode — one shot per key press.  Fires a slow, long-range
## projectile that detonates in a wide 8 m blast, dealing 50 heat to every
## target caught in the explosion.  20-heat self-cost reflects the weapon's
## sheer destructive power.
##
## Tuning:
##   speed     = 15 m/s  (slow, telegraphed arc)
##   radius    = 8.0 m   (large blast zone)
##   lifetime  = 5.0 s   (long flight for maximum reach)
##   payload   = [PunchEffect] 50 heat per target
##
## Designed for the Bomber's Artillery weapon slot.

func _init(p_input: String = "ability_1") -> void:
	ability_name = "Artillery Mortar"
	input_action = p_input
	activation_mode = ActivationMode.INSTANT
	projectile_speed = 15.0
	projectile_lifetime = 5.0
	explosion_radius = 8.0


func create_self_effects(user: Node) -> Array:
	return [StatusEffect.new("Artillery Mortar Cost", 20.0, 1, user, true, false)]


func create_other_effects(user: Node) -> Array:
	# armor_penetration = 0.9 — bomber artillery pierces carrier armor.
	return [PunchEffect.new(50.0, 1, user, 0.9)]
