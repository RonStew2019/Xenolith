extends CarrierModule
class_name HarvesterModule
## Resource harvester — boosts the carrier's extraction rate.
##
## Adds [member harvest_rate_bonus] to the carrier's [member Carrier.harvest_rate]
## on install and subtracts it on uninstall.  Stack multiple harvesters
## for faster extraction.

# -- Properties ------------------------------------------------------------

## Bonus added to the carrier's base harvest rate while installed.
@export var harvest_rate_bonus: float = 5.0

# -- Overrides -------------------------------------------------------------

func on_install(carrier: Carrier) -> void:
	carrier.harvest_rate += harvest_rate_bonus
	print("[Carrier] Harvester installed — harvest rate now %.1f" % carrier.harvest_rate)


func on_uninstall(carrier: Carrier) -> void:
	carrier.harvest_rate -= harvest_rate_bonus
	print("[Carrier] Harvester removed — harvest rate now %.1f" % carrier.harvest_rate)


func get_module_type() -> StringName:
	return &"harvester"
