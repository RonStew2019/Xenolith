extends Ability
class_name CoilAbility
## Defensive stance toggle.  While active, applies a [CoilEffect] that
## halves movement speed and cools the reactor at -15 heat/tick.
## Press to engage, press again to disengage.
##
## Self-effects:
##   • A [CoilEffect] (permanent duration, -15 heat/tick, non-stackable)
##     that reduces [member CharacterBase.speed_multiplier] on apply and
##     restores it on removal.


func _init(p_input: String = "ability_3") -> void:
	ability_name = "Coil"
	input_action = p_input
	activation_mode = ActivationMode.TOGGLE


func create_self_effects(user: Node) -> Array:
	return [CoilEffect.new(user)]
