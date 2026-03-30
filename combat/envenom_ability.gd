extends Ability
class_name EnvenomAbility
## Coats your fists in venom -- every melee strike applies a [PoisonEffect]
## (1 heat/tick until the target's heat reaches zero) on top of the
## normal punch damage.  Toggle on/off.

func _init(p_input: String = "ability_1") -> void:
	ability_name = "Envenom"
	input_action = p_input
	activation_mode = ActivationMode.TOGGLE


func create_self_effects(user: Node) -> Array:
	return [MeleeModifierEffect.new(
		func(event: MeleeEvent):
			event.effects.append(PoisonEffect.new(event.user)),
		"Envenom", 0.65, -1, user,
	)]
