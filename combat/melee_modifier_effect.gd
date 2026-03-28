extends StatusEffect
class_name MeleeModifierEffect
## A status effect that hooks into [signal CharacterBase.melee_strike]
## to modify melee attacks while active.
##
## Pass a [Callable] that receives a [MeleeEvent] and can mutate it
## freely — append extra effects, replace defaults, adjust weights,
## or cancel the strike.  The callable runs synchronously before the
## effects are applied to the target.
##
## Example — poison on hit for 50 ticks:
## [codeblock]
## var modifier := MeleeModifierEffect.new(
##     func(event: MeleeEvent):
##         event.effects.append(StatusEffect.new("Poison", 3.0, 5, event.user)),
##     "Poison Fists", 0.0, 50,
## )
## user.get_reactor().apply_effect(modifier)
## [/codeblock]

## Callable with signature: func(event: MeleeEvent) -> void
var _on_strike: Callable

var _character: Node


func _init(
	p_on_strike: Callable = Callable(),
	p_name: String = "Melee Modifier",
	p_weight: float = 0.0,
	p_duration: int = -1,
	p_source: Node = null,
) -> void:
	super._init(p_name, p_weight, p_duration, p_source)
	_on_strike = p_on_strike


func on_apply(reactor: Node) -> void:
	_character = reactor.get_parent()
	if _character and _character.has_signal("melee_strike"):
		_character.melee_strike.connect(_handle_strike)


func on_remove(_reactor: Node) -> void:
	if is_instance_valid(_character) and _character.has_signal("melee_strike"):
		if _character.melee_strike.is_connected(_handle_strike):
			_character.melee_strike.disconnect(_handle_strike)
	_character = null


func _handle_strike(event: MeleeEvent) -> void:
	if _on_strike.is_valid():
		_on_strike.call(event)
