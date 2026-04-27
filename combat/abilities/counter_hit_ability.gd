extends Ability
class_name CounterHitAbility
## INSTANT self-applied tracker.  For 10 ticks, records every effect that
## hits the caster; on expiry, broadcasts copies to every character
## within 10m.  All broadcast logic lives in [CounterHitEffect]; this
## ability is just the button that applies it.

func _init(p_input: String = "ability_3") -> void:
	ability_name = "Counter-Hit"
	input_action = p_input
	activation_mode = ActivationMode.INSTANT


func create_self_effects(user: Node) -> Array:
	return [CounterHitEffect.new(user)]
