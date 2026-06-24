extends Ability
class_name VenomFistAbility
## Passive hand weapon that coats melee strikes in persistent venom.
##
## Applied via [method on_equip] — no activation key needed.  Adds a
## [MeleeModifierEffect] that injects a [PoisonEffect] into every melee
## strike while equipped.  Each punch applies a new poison stack, so
## rapid punching compounds the heat-over-time pressure.
##
## [PoisonEffect] deals +0.1 heat/tick permanently until the target's
## heat drops to zero.  Multiple stacks from consecutive punches pile up.
##
## Designed for L-Hand / R-Hand weapon slots.

func _init(p_input: String = "") -> void:
	ability_name = "Venom Fist"
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
			event.effects.append(PoisonEffect.new(event.user)),
		"Venom Fist", 0.0, -1, user,
	)]
