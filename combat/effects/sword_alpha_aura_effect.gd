extends CelestialSwordAuraEffect
class_name SwordAlphaAuraEffect
## Offensive recalled-sword aura — adds a bleed-on-hit modifier to the
## wielder's melee strikes while active.
##
## Each melee strike appends a stackable [b]Bleed[/b] effect (2.5 heat/tick
## for 10 ticks) to the [MeleeEvent].  Multiple strikes stack independent
## bleeds on the target, punishing sustained aggression.
##
## The modifier is applied as a child [MeleeModifierEffect] on the same
## reactor and cleaned up automatically when this aura is removed.

## Reference kept so [method on_remove] can cleanly unregister the modifier.
var _melee_modifier: MeleeModifierEffect = null


func _init(
	p_aura_name: String = "Sword Alpha Aura",
	p_source: Node = null,
) -> void:
	super._init(p_aura_name, p_source)


func on_apply(reactor: Node) -> void:
	_melee_modifier = MeleeModifierEffect.new(
		func(event: MeleeEvent) -> void:
			event.effects.append(
				StatusEffect.new("Bleed", 2.5, 10, event.user, true, false)
			),
		"Alpha Bleed Modifier",
		0.0,
		-1,
		source,
	)
	reactor.apply_effect(_melee_modifier)


func on_remove(reactor: Node) -> void:
	if _melee_modifier != null:
		reactor.remove_effect(_melee_modifier)
		_melee_modifier = null
