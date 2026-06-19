extends Node
class_name Hangar
## Manages the carrier's stored mechs.
##
## Lives as a child of [Carrier].  Capacity is determined by the sum of
## all installed [HangarModule]s' [member HangarModule.mech_capacity].
## Mechs are represented as [MechBlueprint] instances for now — actual
## mech scenes come later.

# -- Signals ---------------------------------------------------------------

## Emitted when a mech is successfully stored.
signal mech_stored(blueprint: MechBlueprint)

## Emitted when a mech is removed from storage.
signal mech_removed(blueprint: MechBlueprint)

# -- State -----------------------------------------------------------------

## The carrier this hangar belongs to.  Set in [method _ready].
var carrier: Carrier = null

## Stored mechs (represented as blueprints until we have real mech scenes).
var _mechs: Array[MechBlueprint] = []

# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	carrier = get_parent() as Carrier
	if carrier == null:
		push_warning("[Hangar] Parent is not a Carrier — hangar won't function.")

# -- Public API ------------------------------------------------------------

## Maximum mech capacity across all installed [HangarModule]s.
func get_max_capacity() -> int:
	if carrier == null:
		return 0
	var total: int = 0
	var hangars: Array[CarrierModule] = carrier.get_modules_by_type(&"hangar")
	for module: CarrierModule in hangars:
		total += (module as HangarModule).mech_capacity
	return total


## Number of mechs currently stored.
func get_mech_count() -> int:
	return _mechs.size()


## Return a copy of the stored mechs array.
func get_mechs() -> Array[MechBlueprint]:
	return _mechs.duplicate()


## Whether there's room for at least one more mech.
func can_store() -> bool:
	return get_mech_count() < get_max_capacity()


## Store a built mech.  Returns [code]false[/code] if at capacity.
func store_mech(blueprint: MechBlueprint) -> bool:
	if not can_store():
		print("[Hangar] Cannot store %s — at capacity (%d/%d)" \
			% [blueprint.blueprint_name, get_mech_count(), get_max_capacity()])
		return false
	_mechs.append(blueprint)
	print("[Hangar] Stored %s (%d/%d)" \
		% [blueprint.blueprint_name, get_mech_count(), get_max_capacity()])
	mech_stored.emit(blueprint)
	return true


## Remove and return the mech at [param index].
## Returns [code]null[/code] if the index is invalid.
func remove_mech(index: int) -> MechBlueprint:
	if index < 0 or index >= _mechs.size():
		print("[Hangar] Cannot remove — invalid index %d" % index)
		return null
	var blueprint: MechBlueprint = _mechs[index]
	_mechs.remove_at(index)
	print("[Hangar] Removed %s (%d/%d)" \
		% [blueprint.blueprint_name, get_mech_count(), get_max_capacity()])
	mech_removed.emit(blueprint)
	return blueprint
