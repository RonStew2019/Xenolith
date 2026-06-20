extends Ability
class_name ThermalFistAbility
## Heavy hand weapon that supercharges melee strikes with high heat.
##
## Applied via [method on_equip] — no activation key needed.  Adds a
## [MeleeModifierEffect] that injects an extra [PunchEffect] (+25 heat)
## into every melee strike while equipped.
##
## Upgraded variant of [PunchAmplifierAbility] (10 heat → 25 heat).
## Designed for L-Hand / R-Hand weapon slots on aggressive dogfighters
## that want to win trades in close quarters.

func _init(p_input: String = "") -> void:
	ability_name = "Thermal Fist"
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
			event.effects.append(PunchEffect.new(25.0, 1, event.user)),
		"Thermal Fist", 0.0, -1, user,
	)]
