extends RefCounted
class_name Loadout
## A character's equipped set of [Ability] instances.
##
## The controller owns a Loadout and queries it by input action to decide
## what to activate.  Think of it as the bridge between input and combat.

var _abilities: Array = []


func add_ability(ability: Ability) -> void:
	_abilities.append(ability)


func remove_ability(ability: Ability) -> void:
	_abilities.erase(ability)


## Return the first ability mapped to [param action], or null.
func get_ability_for_action(action: String) -> Ability:
	for ability in _abilities:
		if ability.input_action == action:
			return ability
	return null


## Snapshot of current abilities (safe to iterate while mutating).
func get_abilities() -> Array:
	return _abilities.duplicate()


## Return a new Loadout with independent copies of every ability.
## Each clone gets its own ability instances (fresh _active / _applied_effects).
func duplicate_loadout() -> Loadout:
	var copy := Loadout.new()
	for ability in _abilities:
		copy.add_ability(ability.duplicate_ability())
	return copy
