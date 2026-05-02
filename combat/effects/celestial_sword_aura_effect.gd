extends StatusEffect
class_name CelestialSwordAuraEffect
## Passive self-buff representing a recalled celestial sword granting its
## wielder a passive benefit.
##
## Part of the **Celestial Armory** loadout — three sword abilities that
## toggle between a passive aura (this effect, applied to the wielder's
## reactor) and a deployed sword entity ([CelestialSwordEntity]) placed in
## the world.  When a sword is recalled, the ability removes the entity and
## applies this aura; when deployed, the ability removes this aura and
## spawns the entity.
##
## [b]Skeleton:[/b] This base aura carries no heat and does nothing in its
## lifecycle hooks — per-sword variants (Flame, Frost, etc.) will override
## the stubs below to implement their specific passive benefits.
##
## [b]Non-stackable:[/b] Each aura is [code]is_stackable = false[/code], so
## ReactorCore will silently reject a duplicate with the same
## [member effect_name].  This guards against signal-race bugs that could
## otherwise apply the same sword's aura twice.  Different swords' auras
## still coexist naturally because they carry distinct names (e.g.
## "Sword Alpha Aura" vs "Sword Beta Aura").
##
## [b]Permanent:[/b] Duration is [code]-1[/code] — the aura persists until
## the owning ability manually removes it (on deploy or on ability swap).
##
## [b]Not broadcastable:[/b] [method duplicate_for_broadcast] returns
## [code]null[/code] — auras are personal buffs and must not be reflected
## or echoed by effects like [CounterHitEffect].

## Identifier for which sword's aura this is (e.g. "Sword of Flame Aura").
## Set via the constructor and readable externally so abilities can locate
## a specific sword's aura with [method ReactorCore.remove_effects_by_name].
var aura_name: String = "Celestial Sword Aura"


func _init(
	p_aura_name: String = "Celestial Sword Aura",
	p_source: Node = null,
) -> void:
	super._init(p_aura_name, 0.0, -1, p_source, false, false)
	aura_name = p_aura_name


## Called once when the aura is first applied to the wielder's reactor.
## Override in per-sword subclasses to initialise passive buffs (e.g.
## register melee modifiers, adjust stats, spawn persistent VFX on the
## wielder).
func on_apply(_reactor: Node) -> void:
	# TODO: Per-sword passive setup goes here.
	pass


## Called every combat tick while the aura is active.
## Override in per-sword subclasses for periodic passive effects (e.g.
## gradual cooling, passive regen, proximity aura pulses).
func on_tick(_reactor: Node) -> void:
	# TODO: Per-sword per-tick logic goes here.
	pass


## Called when the aura is removed (sword deployed or ability swapped).
## Override in per-sword subclasses to tear down whatever [method on_apply]
## set up — remove melee modifiers, revert stats, despawn VFX, etc.
func on_remove(_reactor: Node) -> void:
	# TODO: Per-sword passive teardown goes here.
	pass


## Auras are personal — they must not be copied by reflector-style effects
## (e.g. [CounterHitEffect] broadcast). Returning [code]null[/code] opts
## this effect out of broadcast duplication entirely.
func duplicate_for_broadcast(_new_source: Node) -> StatusEffect:
	return null
