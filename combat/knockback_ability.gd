extends AoeCasterAbility
class_name KnockbackAbility
## Fires an omnidirectional repulsor burst — every character within
## [member aoe_radius] metres is blasted away with a [KnockbackEffect].
## INSTANT: one press, one pulse, no persistent state.

func _init(p_input: String = "ability_2") -> void:
	ability_name = "Repulse"
	input_action = p_input
	activation_mode = ActivationMode.INSTANT
	aoe_radius = 5.5


func create_other_effects(user: Node) -> Array:
	return [KnockbackEffect.new(user)]
