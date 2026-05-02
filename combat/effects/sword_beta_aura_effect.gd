extends CelestialSwordAuraEffect
class_name SwordBetaAuraEffect
## Defensive recalled-sword aura — passively cools the wielder's reactor
## at -0.1 heat per tick while active.
##
## No lifecycle overrides required — the base [StatusEffect] heat system
## applies the cooling automatically each tick.


func _init(
	p_aura_name: String = "Sword Beta Aura",
	p_source: Node = null,
) -> void:
	super._init(p_aura_name, p_source)
	heat = -0.1
