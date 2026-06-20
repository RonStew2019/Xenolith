extends Ability
class_name PunchAmplifierAbility
## Passive hand weapon that amplifies melee strikes with extra heat.
##
## Applied via [method on_equip] — no activation key needed.  Adds a
## [MeleeModifierEffect] that injects an extra [PunchEffect] (+10 heat)
## into every melee strike while equipped.
##
## Designed for L-Hand / R-Hand weapon slots.  Since punches are the
## universal base mechanic, this weapon makes them hit harder without
## requiring any input from the player.

func _init(p_input: String = "") -> void:
	ability_name = "Punch Amplifier"
	input_action = p_input


## Apply the melee modifier immediately on equip (passive weapon).
## Sets [member _active] so [method force_deactivate] cleans up on death.
func on_equip(user: Node) -> void:
	var reactor := _get_reactor(user)
	if not reactor:
		return
	var effects := create_self_effects(user)
	for effect in effects:
		reactor.apply_effect(effect)
	_applied_effects.append_array(effects)
	_active = true


func create_self_effects(user: Node) -> Array:
	return [MeleeModifierEffect.new(
		func(event: MeleeEvent):
			event.effects.append(PunchEffect.new(10.0, 1, event.user)),
		"Punch Amplifier", 0.0, -1, user,
	)]
