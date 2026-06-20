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

# -- Configuration ---------------------------------------------------------

## Seconds between threat turns.
var turn_interval: float = 5.0

## Maximum simultaneous threats on the map.
var max_threats: int = 6

## Spawn a new threat every N turns.
var spawn_interval_turns: int = 5

## Number of initial fauna hives placed in [method _ready].
const INITIAL_HIVE_COUNT: int = 3

## Turns before enemy carriers start spawning (give player breathing room).
const ENEMY_CARRIER_START_TURN: int = 10

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

	# 3. Periodic spawning.
	if _turns_elapsed % spawn_interval_turns == 0 and _threats.size() < max_threats:
		_spawn_random_threat()

	print("[ThreatManager] Turn %d — %d active threats" % [_turns_elapsed, _threats.size()])


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


# -- Spawning --------------------------------------------------------------

## Place initial fauna hives on random non-edge, non-resource,
## non-carrier hexes.
func _spawn_initial_hives() -> void:
	var interior: Array[Vector2i] = _get_interior_hexes()
	for i: int in range(INITIAL_HIVE_COUNT):
		var hex: Vector2i = _get_random_empty_hex(interior)
		if hex == Vector2i(-999, -999):
			break  # No more valid hexes.
		spawn_fauna_hive(hex.x, hex.y)


## Create and place a [FaunaHive] at the given hex.
func spawn_fauna_hive(q: int, r: int) -> FaunaHive:
	var hive := FaunaHive.new()
	hive.entity_name = &"Fauna Hive"
	hive.threat_level = 1.0 + randf() * 1.5
	hive.swarm_strength = 1.0 + randf() * 0.5
	hive.name = "FaunaHive_%d_%d" % [q, r]

	get_parent().add_child(hive)
	hive.initialize(hex_grid, q, r)
	hive.removed.connect(_on_threat_removed.bind(hive))
	_threats.append(hive)
	threat_spawned.emit(hive)
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


## Spawn a random threat — fauna hive or enemy carrier depending on
## how many turns have elapsed.
func _spawn_random_threat() -> void:
	var edge_hexes: Array[Vector2i] = _get_edge_hexes()
	var hex: Vector2i = _get_random_empty_hex(edge_hexes)
	if hex == Vector2i(-999, -999):
		print("[ThreatManager] No empty edge hexes for spawning")
		return

	if _turns_elapsed >= ENEMY_CARRIER_START_TURN and randf() > 0.4:
		# Mid/late game — spawn enemy carrier with escalating strength.
		var strength_val: float = 1.0 + (float(_turns_elapsed) / 20.0) * 4.0
		strength_val = clampf(strength_val, 1.0, 10.0)
		spawn_enemy_carrier(hex.x, hex.y, strength_val)
	else:
		# Early game — more fauna.
		spawn_fauna_hive(hex.x, hex.y)


# -- Public API ------------------------------------------------------------

## Remove a threat from tracking and from the grid.
func remove_threat(threat: ThreatEntity) -> void:
	_threats.erase(threat)
	threat_removed.emit(threat)
	threat.remove_from_grid()
	print("[ThreatManager] Removed %s — %d threats remain" % [threat.entity_name, _threats.size()])


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

## Return hexes on the outermost ring of the grid (distance == grid_radius).
func _get_edge_hexes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var radius: int = hex_grid.grid_radius
	for coords: Vector2i in hex_grid.cells:
		var cell: HexCell = hex_grid.cells[coords]
		# A cell is on the edge if max(|q|, |r|, |s|) == radius.
		var s: int = -cell.q - cell.r
		if maxi(absi(cell.q), maxi(absi(cell.r), absi(s))) == radius:
			result.append(coords)
	return result


## Return interior hexes (not on edge, not on the carrier's starting hex).
func _get_interior_hexes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var radius: int = hex_grid.grid_radius
	for coords: Vector2i in hex_grid.cells:
		var cell: HexCell = hex_grid.cells[coords]
		var s: int = -cell.q - cell.r
		var ring: int = maxi(absi(cell.q), maxi(absi(cell.r), absi(s)))
		# Skip edge, skip origin (carrier start), skip resource hexes.
		if ring >= radius:
			continue
		if coords == Vector2i.ZERO:
			continue
		if cell.terrain == HexCell.TerrainType.RESOURCE:
			continue
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
