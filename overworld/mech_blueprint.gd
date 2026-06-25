extends Resource
class_name MechBlueprint
## A mech blueprint — chassis + weapon loadout that can be queued for
## fabrication.
##
## Players design blueprints by picking a chassis and assigning weapons to
## its slots.  The blueprint goes into the [BuildQueue]; once fabricated
## the resulting mech (represented as this blueprint) is stored in the
## [Hangar].
##
## Weapon details are stub StringName references for now — actual Ability
## resources come in Phase 4.

# -- Properties ------------------------------------------------------------

## Human-readable name for this blueprint (e.g. &"Interceptor Mk I").
@export var blueprint_name: StringName = &""

## The chassis this blueprint is based on.
@export var chassis: MechChassis = null

## Maps slot name → weapon identifier.
## Keys must be valid entries from [member MechChassis.weapon_slots].
## e.g. {&"l_hand": &"laser_rifle", &"r_hand": &"plasma_sword"}
## Empty slots can be omitted or mapped to &"".
@export var weapon_assignments: Dictionary = {}

# -- Public API ------------------------------------------------------------

## Total resource cost to fabricate this blueprint.
##
## Chassis base cost plus per-weapon costs from [EconomyConfig].
func get_total_cost() -> Dictionary:
	var costs: Dictionary = {}
	if chassis != null:
		costs = chassis.resource_costs.duplicate()
	# Add weapon costs.
	for slot_name: StringName in weapon_assignments:
		var weapon_id: StringName = weapon_assignments[slot_name]
		if weapon_id == &"":
			continue
		var weapon_cost: Dictionary = EconomyConfig.get_weapon_cost(weapon_id)
		for res_type: StringName in weapon_cost:
			costs[res_type] = costs.get(res_type, 0) + weapon_cost[res_type]
	return costs


## Total build time in seconds (before fabricator speed multiplier).
##
## For now this is just the chassis build time.  Weapons may add to it
## later.
func get_build_time() -> float:
	if chassis == null:
		return 0.0
	return chassis.build_time
