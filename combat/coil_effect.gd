extends StatusEffect
class_name CoilEffect
## Defensive stance — slows the user to half speed but actively cools the
## reactor at -15 heat/tick.
##
## Non-stackable, permanent duration (managed by TOGGLE ability lifecycle).
## Self-cleaning: restores [member CharacterBase.speed_multiplier] on removal.

## Fraction subtracted from [code]source.speed_multiplier[/code] while active.
const SPEED_PENALTY := 0.35


func _init(p_source: Node = null) -> void:
	super._init("Coil", -1.5, -1, p_source, false)


func on_apply(_reactor: Node) -> void:
	if is_instance_valid(source):
		source.speed_multiplier -= SPEED_PENALTY


func on_remove(_reactor: Node) -> void:
	if is_instance_valid(source):
		source.speed_multiplier += SPEED_PENALTY
