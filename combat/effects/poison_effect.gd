extends StatusEffect
class_name PoisonEffect
## Persistent heat-over-time that clears when the target's heat reaches zero.
##
## Applies [member weight] heat per tick (default 1.0) via the normal
## [StatusEffect] weight system.  Hooks [signal ReactorCore.heat_changed]
## to self-remove the moment heat drops to zero.

var _reactor: Node


func _init(p_source: Node = null) -> void:
	super._init("Poison", 0.1, -1, p_source, true, false)


func on_apply(reactor: Node) -> void:
	_reactor = reactor
	reactor.heat_changed.connect(_on_heat_changed)


func on_remove(reactor: Node) -> void:
	if reactor.heat_changed.is_connected(_on_heat_changed):
		reactor.heat_changed.disconnect(_on_heat_changed)
	_reactor = null


func _on_heat_changed(current: float, _maximum: float) -> void:
	if is_zero_approx(current) and _reactor:
		_reactor.remove_effect(self)
