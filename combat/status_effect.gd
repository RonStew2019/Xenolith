extends RefCounted
class_name StatusEffect
## Base class for status effects applied to a [ReactorCore].
##
## Each effect contributes [member heat] heat per tick and lasts for
## [member duration] ticks.  Subclass and override the lifecycle methods
## ([method on_apply] / [method on_tick] / [method on_remove]) for
## custom behaviour — stacking, escalation, area denial, whatever.
##
## Quick-reference:
##   duration  >  0  → finite, decremented each tick, removed at 0
##   duration  <  0  → permanent, stays until manually removed
##   duration ==  1  → single-tick pulse (applied, ticked once, removed)
##   heat   >  0  → heats the reactor
##   heat   <  0  → cools the reactor

## Human-readable identifier (used by remove_effects_by_name).
var effect_name: String = ""

## Heat contributed per tick. Negative values cool the reactor.
var heat: float = 0.0

## Remaining ticks.
## Positive → decremented each tick, removed when it reaches 0.
## Negative → permanent (stays until [method ReactorCore.remove_effect]).
var duration: int = -1

## The node that applied this effect (may be null for environmental).
var source: Node = null

## Can multiple copies of the effect exist simultaneously
var is_stackable: bool = false

## Do subsequent applications reset duration
var is_refreshable: bool = false


func _init(
	p_name: String = "",
	p_heat: float = 0.0,
	p_duration: int = -1,
	p_source: Node = null,
	p_is_stackable = false,
	p_is_refreshable: bool = true
) -> void:
	effect_name = p_name
	heat = p_heat
	duration = p_duration
	source = p_source
	is_stackable = p_is_stackable
	is_refreshable = p_is_refreshable


## Called once when the effect is first applied to a reactor.
func on_apply(_reactor: Node) -> void:
	pass


## Called every combat tick while the effect is active.
func on_tick(_reactor: Node) -> void:
	pass


## Called when the effect expires or is manually removed.
func on_remove(_reactor: Node) -> void:
	pass


## True when duration has counted down to zero.
func is_expired() -> bool:
	return duration == 0

func get_heat() -> float:
	return heat

func set_heat(p_heat: float) -> void:
	heat = p_heat

func get_duration() -> int:
	return duration

func set_duration(p_duration) -> void:
	duration = p_duration
