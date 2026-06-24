extends StatusEffect
class_name CryoEffect
## Movement-slowing debuff applied to an enemy target.
##
## Each stack reduces [member CharacterBase.speed_multiplier] by
## [constant SPEED_PENALTY] (40%).  Stackable — multiple cryo hits
## compound the slow.  Not refreshable (each hit adds its own stack
## rather than resetting the timer).
##
## Cryo weapons still heat the target's reactor mildly (+5.0/tick) so
## they aren't free utility — the user pays a small thermal cost on the
## target side.
##
## Self-cleaning: [method on_remove] restores the penalty via
## [code]is_instance_valid[/code] guard, so freed targets won't crash.

## Fraction subtracted from [code]target.speed_multiplier[/code] per stack.
const SPEED_PENALTY := 0.4


func _init(p_source: Node = null) -> void:
	super._init("Cryo", 5.0, 10, p_source, true, false, 0.0)


func on_apply(_reactor: Node) -> void:
	if is_instance_valid(target):
		target.speed_multiplier -= SPEED_PENALTY


func on_remove(_reactor: Node) -> void:
	if is_instance_valid(target):
		target.speed_multiplier += SPEED_PENALTY
