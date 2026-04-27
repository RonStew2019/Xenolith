extends StatusEffect
class_name SelfRepairEffect
## Passive self-repair nanites that slowly restore integrity.
##
## Generates a small amount of waste heat (weight) as a trade-off.
## [ReactorCore] automatically applies this effect when heat < max_heat
## and integrity < max_integrity, and removes it when either condition
## becomes false.  The effect itself heals unconditionally each tick —
## all gating logic lives in the reactor.

## How much integrity is restored each tick (when conditions are met).
var repair_per_tick: float = 5.0


func _init(
	p_weight: float = 1.0,
	p_duration: int = -1,
	p_source: Node = null,
	p_repair_per_tick: float = 5.0,
) -> void:
	super._init("Self Repair", p_weight, p_duration, p_source)
	repair_per_tick = p_repair_per_tick


func on_tick(reactor: Node) -> void:
	reactor.integrity += repair_per_tick


## Reactor-internal effect, never inflicted externally — should never be broadcast.
func duplicate_for_broadcast(_new_source: Node) -> StatusEffect:
	return null
