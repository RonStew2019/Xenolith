extends CarrierModule
class_name EngineModule
## Propulsion engine — reduces the carrier's movement cooldown.
##
## Engines don't have install/uninstall side effects because the carrier
## computes its movement cooldown dynamically from the full module list
## every time it moves.  More engines = faster carrier.
##
## Formula: max(1.0, 2.0 * total_modules - 5.0 * engine_count)

# -- Overrides -------------------------------------------------------------

func _init() -> void:
	module_name = &"Engine"
	description = "Propulsion module — reduces time between carrier moves."
	power_cost = 1


func get_module_type() -> StringName:
	return &"engine"
