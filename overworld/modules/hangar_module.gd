extends CarrierModule
class_name HangarModule
## Hangar bay — stores mechs between deployments.
##
## Each hangar module adds [member mech_capacity] slots for mech storage.

# -- Properties ------------------------------------------------------------

## Maximum number of mechs this hangar can hold.
@export var mech_capacity: int = 4

# -- Overrides -------------------------------------------------------------

func get_module_type() -> StringName:
	return &"hangar"
