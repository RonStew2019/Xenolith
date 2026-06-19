extends CarrierModule
class_name ReactorModule
## Power reactor — generates power for other modules.
##
## Reactors don't consume power; they produce it.  Without at least one
## reactor, no other modules can be installed (they'd exceed the power budget).

# -- Properties ------------------------------------------------------------

## How much power this reactor generates.
@export var power_output: int = 5

# -- Overrides -------------------------------------------------------------

func _init() -> void:
	power_cost = 0


func get_module_type() -> StringName:
	return &"reactor"
