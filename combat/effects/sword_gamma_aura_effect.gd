extends CelestialSwordAuraEffect
class_name SwordGammaAuraEffect
## Mobility recalled-sword aura — grants the wielder +20% movement speed
## while active.
##
## Follows the same [member CharacterBase.speed_multiplier] pattern as
## [CoilEffect]: applies the bonus on apply, reverts it on remove with an
## [method is_instance_valid] guard for safe teardown.

## Fraction added to [code]speed_multiplier[/code] while active.
const SPEED_BONUS := 0.35

## Cached reference to the character node for safe cleanup.
var _character: Node = null


func _init(
	p_aura_name: String = "Sword Gamma Aura",
	p_source: Node = null,
) -> void:
	super._init(p_aura_name, p_source)


func on_apply(reactor: Node) -> void:
	_character = reactor.get_parent()
	if is_instance_valid(_character):
		_character.speed_multiplier += SPEED_BONUS


func on_remove(_reactor: Node) -> void:
	if is_instance_valid(_character):
		_character.speed_multiplier -= SPEED_BONUS
	_character = null
