extends StatusEffect
class_name EMPEffect
## Venting-suppression debuff that counteracts ambient cooling.
##
## Applies +3.0 heat per tick — exactly matching the permanent Ambient
## Venting effect's −3.0 cooling rate.  While active the target
## effectively cannot cool down, so any other heat sources push them
## steadily toward overflow.
##
## Non-stackable / refreshable: re-applying resets the 8-tick timer,
## keeping the suppression window open without piling extra heat.
##
## Armor penetration 0.5 — EMP disrupts internal systems rather than
## brute-forcing through plating, so it partially bypasses armor.
##
## No lifecycle hooks required; the base [StatusEffect] heat-per-tick
## system handles everything.


func _init(p_source: Node = null) -> void:
	super._init("EMP", 3.0, 8, p_source, false, true, 0.5)
