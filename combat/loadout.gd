extends RefCounted
class_name Loadout
## A character's equipped set of [Ability] instances.
##
## The controller owns a Loadout and queries it by input action to decide
## what to activate.  Think of it as the bridge between input and combat.

var _abilities: Array = []

## Maps slot [StringName] → [Ability] for chassis-based weapon layouts.
## Abilities in slots are also present in [member _abilities] for
## backward compatibility with the flat API.
var _slots: Dictionary = {}


func add_ability(ability: Ability) -> void:
	_abilities.append(ability)


func remove_ability(ability: Ability) -> void:
	_abilities.erase(ability)


## Assign an [Ability] to a named weapon slot.
## Also adds the ability to the flat [member _abilities] array.
func set_slot(slot_name: StringName, ability: Ability) -> void:
	# Remove any existing ability in this slot first.
	var old: Ability = _slots.get(slot_name)
	if old != null:
		_abilities.erase(old)
	_slots[slot_name] = ability
	if ability not in _abilities:
		_abilities.append(ability)


## Return the [Ability] assigned to [param slot_name], or [code]null[/code].
func get_slot(slot_name: StringName) -> Ability:
	return _slots.get(slot_name)


## Return all populated slot names.
func get_slot_names() -> Array:
	return _slots.keys()


## Remove the ability from a slot (and from the flat array).
func clear_slot(slot_name: StringName) -> void:
	var ability: Ability = _slots.get(slot_name)
	if ability != null:
		_abilities.erase(ability)
	_slots.erase(slot_name)


## Call [method Ability.on_equip] on every ability in the loadout.
## Should be called once after the loadout is created and assigned to a
## character, so abilities that need initial state (e.g. passive buffs)
## can set themselves up with a reference to their user.
func equip_all(user: Node) -> void:
	for ability in _abilities:
		ability.on_equip(user)


## Force-deactivate every ability in this loadout.
## Called when the owning mech dies so TOGGLE/HOLD self-effects are
## properly removed from the reactor before it shuts down.
func deactivate_all(user: Node) -> void:
	for ability in get_abilities():
		ability.force_deactivate(user)


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
## Slot assignments are preserved on the copy.
func duplicate_loadout() -> Loadout:
	var copy := Loadout.new()
	var ability_map: Dictionary = {}  # old → new, for slot reassignment
	for ability in _abilities:
		var dup := ability.duplicate_ability()
		copy.add_ability(dup)
		ability_map[ability] = dup
	for slot_name: StringName in _slots:
		var orig: Ability = _slots[slot_name]
		if orig in ability_map:
			copy._slots[slot_name] = ability_map[orig]
	return copy


# -- Static Factories -------------------------------------------------------

## Build a [Loadout] from a [MechBlueprint], mapping each populated weapon
## slot to an [Ability] via [WeaponRegistry].
##
## [param bp] — the blueprint whose [member MechBlueprint.weapon_assignments]
## are read.[br]
## [param slot_input_map] — maps slot [StringName]s to input action strings
## (e.g. [code]{&"l_shoulder": "ability_1"}[/code]).  Slots not present in
## this map produce passive abilities (empty [member Ability.input_action]).
static func create_from_blueprint(
	bp: MechBlueprint, slot_input_map: Dictionary,
) -> Loadout:
	var loadout := Loadout.new()
	if bp == null or bp.chassis == null:
		return loadout
	for slot_name: StringName in bp.chassis.weapon_slots:
		var weapon_id = bp.weapon_assignments.get(slot_name, &"")
		if weapon_id == &"":
			continue
		var ability: Ability = WeaponRegistry.create_weapon(
			StringName(weapon_id), slot_name,
		)
		if ability == null:
			continue
		ability.input_action = slot_input_map.get(slot_name, "")
		loadout.set_slot(slot_name, ability)
	return loadout
