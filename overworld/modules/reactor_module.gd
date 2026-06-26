extends CarrierModule
class_name ReactorModule
## Power reactor — generates power for other modules.
##
## Reactors don't consume power; they produce it.  Without at least one
## reactor, no other modules can be installed (they'd exceed the power budget).

# -- Properties ------------------------------------------------------------

## How much power this reactor generates.
@export var power_output: int = 5

## How many additional module slots this reactor grants when installed.
@export var slot_bonus: int = 4

# -- Overrides -------------------------------------------------------------

func _init() -> void:
	power_cost = 0


func get_module_type() -> StringName:
	return &"reactor"


func on_install(carrier) -> void:
	carrier.max_slots += slot_bonus


func on_uninstall(carrier) -> void:
	carrier.max_slots -= slot_bonus
