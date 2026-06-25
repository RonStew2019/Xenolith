extends Node
class_name TestLevelConfig
## Configures the hex overworld for a deterministic test scenario.
##
## Must be the FIRST child of HexOverworld so its [method _ready] runs
## before HexGrid, Carrier, ProgressionManager, and ThreatManager.
##
## Layout (axial coords, carrier at origin):
##   (0, 0)   — Carrier spawn
##   (0,-2)   — Metal node  (300 units) — on the main path north
##   (-1,-2)  — Crystal node (150 units) — one hex west of metal
##   (1,-3)   — Fuel node   (100 units) — one hex NE of metal, toward hive
##   (0,-4)   — Fauna hive (lone threat)
##
## Gameplay loop:  harvest resources (explore laterally) → build dogfighter
## + bomber → advance north → engage hive.
##
## Economy:
##   Dogfighter (basic preset):  60 metal, 20 crystal, 5 fuel deploy
##   Bomber (basic preset):      90 metal, 45 crystal, 8 fuel deploy
##   Total needed:              150 metal, 65 crystal, 13 fuel
##   Starting:                    0 metal,  0 crystal,  0 fuel
##   Resource nodes:            300 metal, 150 crystal, 100 fuel

## Metal node — on the main path, 2 hexes north of carrier.
const METAL_HEX := Vector2i(0, -2)
const METAL_AMOUNT: float = 300.0

## Crystal node — one hex west of metal, encourages lateral exploration.
const CRYSTAL_HEX := Vector2i(-1, -2)
const CRYSTAL_AMOUNT: float = 150.0

## Fuel node — one hex NE of metal, partway toward the hive.
const FUEL_HEX := Vector2i(1, -3)
const FUEL_AMOUNT: float = 100.0

## Coordinates of the single fauna hive (4 hexes north, past resources).
const HIVE_HEX := Vector2i(0, -4)


func _ready() -> void:
	var hex_grid := _sibling("HexGrid") as HexGrid
	var carrier := _sibling("Carrier") as Carrier
	var threat_mgr := _sibling("ThreatManager") as ThreatManager
	var progression_mgr := _sibling("ProgressionManager") as ProgressionManager

	# -- Deterministic grid: all MOUNTAIN except three RESOURCE nodes ------
	hex_grid.use_random_terrain = false
	for entry: Array in [
		[METAL_HEX,   &"metal",   METAL_AMOUNT],
		[CRYSTAL_HEX, &"crystal", CRYSTAL_AMOUNT],
		[FUEL_HEX,    &"fuel",    FUEL_AMOUNT],
	]:
		var coords: Vector2i = entry[0]
		hex_grid.terrain_overrides[coords] = HexCell.TerrainType.RESOURCE
		hex_grid.resource_overrides[coords] = {
			"type": entry[1], "amount": entry[2],
		}

	# -- Carrier starts empty — must harvest everything --------------------
	carrier.starting_metal = 0
	carrier.starting_crystal = 0
	carrier.starting_fuel = 0

	# -- Single fauna hive, no random spawning ------------------------------
	threat_mgr.test_mode = true
	threat_mgr.test_hive_positions = [HIVE_HEX]

	# -- Lock progression to EARLY phase ------------------------------------
	progression_mgr.test_mode = true

	# -- Deferred: install a free fabricator after carrier sets up defaults --
	_install_test_fabricator.call_deferred()

	print("[TestLevelConfig] Deterministic test level configured")


## Install a free fabricator so the player can build mechs immediately
## after harvesting.  Deferred because Carrier._ready() hasn't run yet
## (it's a later sibling in the scene tree).
func _install_test_fabricator() -> void:
	var carrier := _sibling("Carrier") as Carrier
	var fab := FabricatorModule.new()
	fab.module_name = &"Field Fabricator"
	fab.description = "Pre-installed fabrication bay for testing."
	fab.build_speed = 1.0
	fab.resource_costs = {}  # Free — it's a starting module.
	fab.power_cost = 1
	carrier.install_module(fab)
	print("[TestLevelConfig] Installed free fabricator")


## Shorthand for grabbing a sibling node.
func _sibling(node_name: String) -> Node:
	return get_parent().get_node(node_name)
