extends Resource
class_name MechChassis
## Defines a mech chassis type — the structural foundation of every mech.
##
## Chassis determine weapon slot layout, base stats, build cost, and build
## time.  Designed as a Resource for serialization and reuse across
## blueprints.
##
## Example chassis: Dogfighter (fast, nimble, 4 slots) vs Bomber (slow,
## tanky, 3 slots with artillery).

# -- Properties ------------------------------------------------------------

## Display name (e.g. &"Dogfighter", &"Bomber").
@export var chassis_name: StringName = &""

## Flavour text for UI tooltips.
@export var description: String = ""

## Weapon slot identifiers this chassis supports.
## e.g. [&"l_hand", &"r_hand", &"l_shoulder", &"r_shoulder"]
@export var weapon_slots: Array[StringName] = []

## Base movement speed — higher = faster mech.
@export var base_speed: float = 7.0

## Maximum heat before the mech overheats.
@export var base_max_heat: float = 100.0

## Starting hull integrity (hit points).
@export var base_integrity: float = 100.0

## Resources required to fabricate this chassis.
## Keys are resource type StringNames, values are integer amounts.
## e.g. {&"metal": 50, &"crystal": 20}
@export var resource_costs: Dictionary = {}

## Base seconds to build (before fabricator speed multiplier).
@export var build_time: float = 20.0
