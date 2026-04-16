extends StatusEffect
class_name ResonantPunchEffect
## Damage over time effect that increases heat when re-applied.
##
## Applies [member weight] heat per tick (default 4.0) via the normal
## [StatusEffect] weight system.  If the target reactor 

var _reactor: Node


func _init(p_source: Node = null) -> void:
	super._init("Resonance", 1.6, 25, p_source, false, true)


func on_apply(reactor: Node) -> void:
	_reactor = reactor
	reactor.effect_applied.connect(_on_refreshed)


func on_remove(reactor: Node) -> void:
	if reactor.effect_applied.is_connected(_on_refreshed):
		reactor.effect_applied.disconnect(_on_refreshed)
	_reactor = null


func _on_refreshed(effect: StatusEffect, refreshed: bool) -> void:
	if effect.effect_name == "Resonance" && refreshed:
		set_heat(get_heat() + 0.4)
