extends StatusEffect
class_name SwordGammaSlowEffect
## Area slow applied by a deployed Gamma [CelestialSwordEntity] to
## characters within its radius.
##
## Pure movement debuff — no heat component.  Permanent duration (-1),
## non-stackable and non-refreshable so the same sword entity cannot
## double-apply the slow to a single target.
##
## Uses [member StatusEffect.target] (auto-set by [ReactorCore]) to
## manipulate [member CharacterBase.speed_multiplier].

## Fraction subtracted from [code]target.speed_multiplier[/code] while active.
const SPEED_PENALTY := 0.35


func _init(p_source: Node = null) -> void:
	super._init("Gamma Slow", 0.0, -1, p_source, false, false)


func on_apply(_reactor: Node) -> void:
	if is_instance_valid(target):
		target.speed_multiplier -= SPEED_PENALTY


func on_remove(_reactor: Node) -> void:
	if is_instance_valid(target):
		target.speed_multiplier += SPEED_PENALTY


## Area debuffs must not be bounced by reflector-style effects.
func duplicate_for_broadcast(_new_source: Node) -> StatusEffect:
	return null
