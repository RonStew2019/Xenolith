extends Node
class_name ThreatManager
## Central coordinator for threats on the hex overworld.
##
## Manages spawning, turn processing, and threat detection.  Runs on a
## timer — every [member turn_interval] seconds, all threats take a turn,
## detection is checked, and new threats may spawn.
##
## Auto-discovers [HexGrid] and [Carrier] siblings in [method _ready].

# -- Signals ---------------------------------------------------------------

## A threat is within detection range of the player carrier.
signal threat_detected(threat: ThreatEntity)

## A new threat has appeared on the map.
signal threat_spawned(threat: ThreatEntity)

## A threat has been removed from the map.
signal threat_removed(threat: ThreatEntity)

## A threat occupies the SAME hex as the carrier — direct confrontation.
signal engagement_triggered(threat: ThreatEntity)

## Emitted after each threat turn is processed.
signal turn_processed(turn_number: int)

# -- Configuration ---------------------------------------------------------

## Seconds between threat turns.
var turn_interval: float = 5.0

## Maximum simultaneous threats on the map.
var max_threats: int = 6

## Spawn a new threat every N turns.
var spawn_interval_turns: int = 5

## Number of initial fauna hives placed in [method _ready].
## Configurable by [ProgressionManager] before the first frame.
var initial_hive_count: int = 3

## Probability (0.0–1.0) of spawning an enemy carrier vs a fauna hive.
## Controlled by [ProgressionManager] based on current phase.
var enemy_carrier_chance: float = 0.0

## Minimum enemy carrier strength when spawning.
var carrier_strength_min: float = 1.0

## Maximum enemy carrier strength when spawning.
var carrier_strength_max: float = 10.0

## Minimum fauna [member FaunaHive.threat_level] when spawning.
var fauna_threat_level_min: float = 1.0

## Maximum fauna [member FaunaHive.threat_level] when spawning.
var fauna_threat_level_max: float = 2.5

## Minimum fauna [member FaunaHive.swarm_strength] when spawning.
var fauna_swarm_strength_min: float = 1.0

## Maximum fauna [member FaunaHive.swarm_strength] when spawning.
var fauna_swarm_strength_max: float = 1.5

## Resource amount multiplier for hexes guarded by a fauna hive.
## Creates risk/reward — the richest nodes are the dangerous ones.
var hive_resource_multiplier: float = 4.0

## Probability (0.0–1.0) of a newly generated resource node spawning
## with a fauna hive guard.  Only checked during dynamic map expansion.
var hive_spawn_chance: float = 0.3

## Minimum hex distance from the carrier for expansion-spawned hives.
## Prevents ambush-spawns right next to the player.
const HIVE_SAFE_RADIUS: int = 2

## When [code]true[/code], disables random spawning and places hives only
## at the positions listed in [member test_hive_positions].
var test_mode: bool = false

## Explicit hive coordinates used when [member test_mode] is enabled.
var test_hive_positions: Array[Vector2i] = []

## Default detection range (same hex + adjacent = 1).
const DETECTION_RANGE: int = 1

# -- State -----------------------------------------------------------------

## Active threats currently on the map.
var _threats: Array[ThreatEntity] = []

## Timer accumulator for turn processing.
var _turn_timer: float = 0.0

## Total turns processed since the manager started.
var _turns_elapsed: int = 0

## Reference to the hex grid (auto-discovered).
var hex_grid: HexGrid = null

## Reference to the player carrier (auto-discovered).
var carrier: Carrier = null

# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	# Auto-discover siblings.
	if get_parent() != null:
		hex_grid = get_parent().get_node_or_null("HexGrid") as HexGrid
		carrier = get_parent().get_node_or_null("Carrier") as Carrier

	if hex_grid == null:
		push_warning("[ThreatManager] No HexGrid sibling found — threats disabled")
		return
	if carrier == null:
		push_warning("[ThreatManager] No Carrier sibling found — threats disabled")
		return

	# React to carrier movement immediately (don't wait for next turn).
	carrier.moved.connect(_on_carrier_moved)

	# Spawn hives on newly explored resource nodes.
	hex_grid.grid_expanded.connect(_on_grid_expanded)

	# Wait one frame so the grid has generated its cells.
	await get_tree().process_frame
	_spawn_initial_hives()
	print("[ThreatManager] Ready — %d initial hives placed" % _threats.size())


func _process(delta: float) -> void:
	if hex_grid == null or carrier == null:
		return

	_turn_timer += delta
	if _turn_timer >= turn_interval:
		_turn_timer -= turn_interval
		_process_turn()


# -- Turn Processing -------------------------------------------------------

## Run one threat turn: move threats, check detection, maybe spawn.
func _process_turn() -> void:
	_turns_elapsed += 1

	# 1. Let every threat act.
	for threat: ThreatEntity in _threats:
		threat.take_turn()

	# 2. Detection pass.
	_check_detection()

	# 3. Periodic spawning (disabled in test mode).
	if not test_mode and _turns_elapsed % spawn_interval_turns == 0 and _threats.size() < max_threats:
		_spawn_random_threat()

	print("[ThreatManager] Turn %d — %d active threats" % [_turns_elapsed, _threats.size()])
	turn_processed.emit(_turns_elapsed)


# -- Detection -------------------------------------------------------------

## Check every threat against the carrier's position.
##
## Standard detection range is [constant DETECTION_RANGE] hex.
## [FaunaHive]s use their own [member FaunaHive.aggro_range] instead.
func _check_detection() -> void:
	if carrier == null or hex_grid == null:
		return

	var carrier_cell: HexCell = hex_grid.get_cell(carrier.current_hex.x, carrier.current_hex.y)
	if carrier_cell == null:
		return

	for threat: ThreatEntity in _threats:
		var threat_cell: HexCell = hex_grid.get_cell(threat.current_hex.x, threat.current_hex.y)
		if threat_cell == null:
			continue

		var dist: int = carrier_cell.distance_to(threat_cell)

		# Same hex → engagement.
		if dist == 0:
			print("[ThreatManager] ENGAGEMENT — %s on carrier hex!" % threat.entity_name)
			engagement_triggered.emit(threat)
			continue

		# Check detection range (hive aggro vs standard).
		var detection_radius: int = DETECTION_RANGE
		if threat is FaunaHive:
			detection_radius = (threat as FaunaHive).aggro_range

		if dist <= detection_radius:
			threat_detected.emit(threat)


## Re-check detection when the carrier moves (don't wait for next turn).
func _on_carrier_moved(_from_hex: Vector2i, _to_hex: Vector2i) -> void:
	_check_detection()


## Probabilistically guard newly generated resource nodes with fauna hives.
##
## Called when the map expands ahead of the carrier.  Each new resource
## node has a [member hive_spawn_chance] probability of getting a hive
## (with the standard yield boost).  Nodes too close to the carrier
## ([constant HIVE_SAFE_RADIUS]) are skipped to avoid cheap ambushes.
func _on_grid_expanded(_new_cell_count: int, new_resource_coords: Array[Vector2i]) -> void:
	if test_mode or new_resource_coords.is_empty():
		return

	var carrier_cell: HexCell = hex_grid.get_cell(carrier.current_hex.x, carrier.current_hex.y)

	for coords: Vector2i in new_resource_coords:
		if _threats.size() >= max_threats:
			break
		if randf() > hive_spawn_chance:
			continue

		# Don't spawn right next to the player.
		if carrier_cell != null:
			var cell: HexCell = hex_grid.get_cell(coords.x, coords.y)
			if cell != null and carrier_cell.distance_to(cell) <= HIVE_SAFE_RADIUS:
				continue

		spawn_fauna_hive(coords.x, coords.y)


# -- Spawning --------------------------------------------------------------

## Place initial fauna hives on random unguarded resource hexes.
## The guarded nodes get a boosted yield — risk meets reward.
func _spawn_initial_hives() -> void:
	if test_mode:
		for pos: Vector2i in test_hive_positions:
			spawn_fauna_hive(pos.x, pos.y)
		return
	var resource_hexes: Array[Vector2i] = _get_unguarded_resource_hexes()
	for i: int in range(initial_hive_count):
		var hex: Vector2i = _get_random_empty_hex(resource_hexes)
		if hex == Vector2i(-999, -999):
			print("[ThreatManager] No unguarded resource hexes left for initial hive %d" % i)
			break
		spawn_fauna_hive(hex.x, hex.y)


## Create and place a [FaunaHive] at the given hex.
##
## If the hex is a RESOURCE cell, boosts its [member HexCell.resource_amount]
## by [member hive_resource_multiplier] — guarded nodes are the juicy ones.
func spawn_fauna_hive(q: int, r: int) -> FaunaHive:
	var hive := FaunaHive.new()
	hive.entity_name = &"Fauna Hive"
	hive.threat_level = randf_range(fauna_threat_level_min, fauna_threat_level_max)
	hive.swarm_strength = randf_range(fauna_swarm_strength_min, fauna_swarm_strength_max)
	hive.name = "FaunaHive_%d_%d" % [q, r]

	get_parent().add_child(hive)
	hive.initialize(hex_grid, q, r)
	hive.removed.connect(_on_threat_removed.bind(hive))
	_threats.append(hive)
	threat_spawned.emit(hive)

	# Boost resource yield on guarded resource nodes.
	var cell := hex_grid.get_cell(q, r)
	if cell != null and cell.terrain == HexCell.TerrainType.RESOURCE:
		var old_amount := cell.resource_amount
		cell.resource_amount *= hive_resource_multiplier
		print("[ThreatManager] Boosted resource at (%d, %d): %.0f → %.0f" % [q, r, old_amount, cell.resource_amount])

	print("[ThreatManager] Spawned fauna hive at (%d, %d)" % [q, r])
	return hive


## Create and place an [EnemyCarrier] at the given hex with the given
## combat strength.
func spawn_enemy_carrier(q: int, r: int, strength_val: float) -> EnemyCarrier:
	var enemy := EnemyCarrier.new()
	enemy.entity_name = &"Enemy Carrier"
	enemy.set_strength(strength_val)
	enemy.threat_level = strength_val
	enemy._target_carrier = carrier
	enemy.name = "EnemyCarrier_%d_%d" % [q, r]

	get_parent().add_child(enemy)
	enemy.initialize(hex_grid, q, r)
	enemy.removed.connect(_on_threat_removed.bind(enemy))
	_threats.append(enemy)
	threat_spawned.emit(enemy)
	print("[ThreatManager] Spawned enemy carrier at (%d, %d), strength %.1f" % [q, r, strength_val])
	return enemy


## Periodically spawn an enemy carrier on a frontier hex.
##
## Fauna hives are placed at map generation only — guarding high-yield
## resource nodes.  Unguarded nodes stay safe.
## [member enemy_carrier_chance] gates this: early phase (0.0) means no
## periodic threats at all; mid/late phases ramp it up.
func _spawn_random_threat() -> void:
	if enemy_carrier_chance <= 0.0:
		return
	var edge_hexes: Array[Vector2i] = _get_edge_hexes()
	var hex: Vector2i = _get_random_empty_hex(edge_hexes)
	if hex == Vector2i(-999, -999):
		print("[ThreatManager] No empty edge hexes for enemy carrier")
		return
	var strength_val: float = randf_range(carrier_strength_min, carrier_strength_max)
	spawn_enemy_carrier(hex.x, hex.y, strength_val)


# -- Public API ------------------------------------------------------------

## Remove a threat from tracking and from the grid.
func remove_threat(threat: ThreatEntity) -> void:
	_threats.erase(threat)
	threat_removed.emit(threat)
	threat.remove_from_grid()
	print("[ThreatManager] Removed %s — %d threats remain" % [threat.entity_name, _threats.size()])


## Return the number of turns elapsed since the manager started.
func get_turns_elapsed() -> int:
	return _turns_elapsed


## Return a copy of the active threats array.
func get_threats() -> Array[ThreatEntity]:
	return _threats.duplicate()


## Return all threats within [param range_val] hexes of [param hex].
func get_nearby_threats(hex: Vector2i, range_val: int) -> Array[ThreatEntity]:
	var result: Array[ThreatEntity] = []
	var origin_cell: HexCell = hex_grid.get_cell(hex.x, hex.y) if hex_grid != null else null
	if origin_cell == null:
		return result

	for threat: ThreatEntity in _threats:
		var threat_cell: HexCell = hex_grid.get_cell(threat.current_hex.x, threat.current_hex.y)
		if threat_cell == null:
			continue
		if origin_cell.distance_to(threat_cell) <= range_val:
			result.append(threat)
	return result


# -- Hex Helpers (private) -------------------------------------------------

## Return hexes on the frontier of the currently-generated map.
##
## A cell is on the frontier if it has fewer than 6 neighbours in
## [member HexGrid.cells].  Works for both fixed-radius and dynamically
## expanding grids.
func _get_edge_hexes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coords: Vector2i in hex_grid.cells:
		var neighbor_count: int = 0
		for dir: Vector2i in HexGrid.HEX_DIRECTIONS:
			if Vector2i(coords.x + dir.x, coords.y + dir.y) in hex_grid.cells:
				neighbor_count += 1
		if neighbor_count < 6:
			result.append(coords)
	return result


## Return all RESOURCE hexes with no occupant, excluding the carrier's
## current hex.  Used for fauna hive placement — both initial and periodic.
func _get_unguarded_resource_hexes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var carrier_hex: Vector2i = carrier.current_hex if carrier != null else Vector2i(-999, -999)
	for coords: Vector2i in hex_grid.cells:
		if coords == carrier_hex:
			continue
		var cell: HexCell = hex_grid.cells[coords]
		if cell.terrain == HexCell.TerrainType.RESOURCE and cell.occupant == null:
			result.append(coords)
	return result


## Pick a random unoccupied hex from [param candidates].
##
## Returns [code]Vector2i(-999, -999)[/code] as a sentinel if none found.
func _get_random_empty_hex(candidates: Array[Vector2i]) -> Vector2i:
	if candidates.is_empty():
		return Vector2i(-999, -999)

	# Shuffle a copy to avoid bias.
	var shuffled: Array[Vector2i] = candidates.duplicate()
	shuffled.shuffle()

	for coords: Vector2i in shuffled:
		var cell: HexCell = hex_grid.get_cell(coords.x, coords.y)
		if cell != null and cell.occupant == null:
			return coords
	return Vector2i(-999, -999)


## Cleanup callback when a threat signals [signal ThreatEntity.removed].
##
## Guarded — only acts if the threat is still tracked.  This prevents
## double-emission when [method remove_threat] already did the cleanup
## before [method ThreatEntity.remove_from_grid] fires the signal.
func _on_threat_removed(threat: ThreatEntity) -> void:
	if threat in _threats:
		_threats.erase(threat)
		threat_removed.emit(threat)
