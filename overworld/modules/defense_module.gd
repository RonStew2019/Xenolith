extends CarrierModule
class_name DefenseModule
## Passive defense system — increases carrier survivability.
##
## Provides a flat [member defense_strength] rating while installed.
## Multiple defense modules stack additively.

# -- Properties ------------------------------------------------------------

## Passive defense rating provided by this module.
@export var defense_strength: float = 10.0

# -- Overrides -------------------------------------------------------------

func get_module_type() -> StringName:
	return &"defense"
