extends StatusEffect
class_name PunchEffect
## Single-tick heat spike from a melee hit.

func _init(p_heat: float = 50.0, p_duration: int = 1, p_source: Node = null,
		p_armor_pen: float = 0.0) -> void:
	super._init("Punch", p_heat, p_duration, p_source)
	armor_penetration = p_armor_pen
