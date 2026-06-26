extends Node
class_name GameLevelConfig
## Configures the hex overworld for a standard game with noise-based biomes,
## dynamic map expansion, and escalating threats.
##
## Must be the FIRST child of HexOverworld so its _ready() runs before
## other nodes initialize.
##
## Unlike TestLevelConfig, this lets the default systems do their job:
##   • HexGrid generates noise-based terrain (spatially coherent biomes)
##   • The map expands dynamically as the carrier explores
##   • ThreatManager spawns initial fauna hives and periodic threats
##   • ProgressionManager drives EARLY → MID → LATE escalation

func _ready() -> void:
	var hex_grid := get_parent().get_node_or_null("HexGrid") as HexGrid
	var carrier := get_parent().get_node_or_null("Carrier") as Carrier

	if hex_grid != null:
		# Initial visible area — the map will grow beyond this as the
		# carrier explores.
		hex_grid.grid_radius = 7
		# Generate 5 rings ahead of the carrier so the frontier is
		# never visible to the player.
		hex_grid.expansion_radius = 5
		# Seed 0 = randomize each run.  Set a fixed value for
		# reproducible maps during testing.
		hex_grid.world_seed = 0

	# Reasonable starting resources — enough to build one mech quickly.
	if carrier != null:
		carrier.starting_metal = 80
		carrier.starting_crystal = 30
		carrier.starting_fuel = 25

	# Everything else uses defaults:
	# - use_random_terrain = true (noise-based biomes + resource nodes)
	# - ThreatManager.test_mode = false (real spawning)
	# - ProgressionManager.test_mode = false (real phase progression)

	print("[GameLevelConfig] Standard game configured (initial radius %d, expansion %d)" \
		% [hex_grid.grid_radius if hex_grid else -1,
		   hex_grid.expansion_radius if hex_grid else -1])
