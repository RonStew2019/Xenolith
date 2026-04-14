extends Ability
class_name ResonantPunchAbility
## Charges your fists with resonant energy — every melee strike applies a
## [ResonantPunchEffect] (1.6 heat/tick for 25 ticks, escalating +0.4 on
## refresh) on top of the normal punch damage.  Toggle on/off.

func _init(p_input: String = "ability_1") -> void:
	ability_name = "Resonance"
	input_action = p_input
	activation_mode = ActivationMode.TOGGLE


func create_self_effects(user: Node) -> Array:
	return [MeleeModifierEffect.new(
		func(event: MeleeEvent):
			event.effects.append(ResonantPunchEffect.new(event.user)),
		"Resonance", 0.65, -1, user,
	)]
