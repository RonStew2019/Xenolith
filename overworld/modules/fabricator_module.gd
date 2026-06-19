extends CarrierModule
class_name FabricatorModule
## Fabrication bay — speeds up mech construction.
##
## Install one (or more!) to reduce build times in the mech foundry.

# -- Properties ------------------------------------------------------------

## Multiplier applied to mech fabrication speed.
@export var build_speed: float = 1.0

# -- Overrides -------------------------------------------------------------

func get_module_type() -> StringName:
	return &"fabricator"
