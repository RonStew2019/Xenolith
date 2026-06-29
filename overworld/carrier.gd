extends Node3D
class_name Carrier
## The player's mobile carrier on the hex overworld.
##
## A strategic-layer entity — part aircraft carrier, part oil rig, part
## nuclear plant.  Parks on hex cells, moves via click-to-move, and will
## eventually harvest resources and launch mechs.
##
## Does NOT handle combat — that's the mech layer's job.

# -- Signals ---------------------------------------------------------------

## Emitted after the carrier finishes moving to a new hex.
signal moved(from_hex: Vector2i, to_hex: Vector2i)

## Emitted when the carrier parks on a hex.
signal parked(hex_coords: Vector2i)

## Emitted when the carrier begins harvesting a resource node.
signal harvesting_started(resource_type: StringName)

## Emitted when harvesting stops (moved away or node depleted).
signal harvesting_stopped()

## Emitted each frame while harvesting, reporting the type and amount gained.
signal harvest_tick(resource_type: StringName, amount: float)

## Emitted when a module is installed in a slot.
signal module_installed(module: CarrierModule, slot_index: int)

## Emitted when a module is removed from a slot.
signal module_uninstalled(module: CarrierModule, slot_index: int)

## Emitted when a multi-hex auto-move route begins.
signal auto_move_started(path: Array[Vector2i])

## Emitted when auto-move completes (reached destination) or is cancelled.
signal auto_move_ended()

# -- Exported Stats --------------------------------------------------------

## Maximum hex distance the carrier can move per action.
@export var move_range: int = 1

## Current hull integrity.
@export var hull: float = 100.0

## Maximum hull integrity.
@export var max_hull: float = 100.0

## Resources harvested per second while parked on a RESOURCE hex.
## Base is 0.0 — all harvest rate comes from [HarvesterModule] bonuses.
@export var harvest_rate: float = 0.0

## Maximum number of module slots on the carrier.
@export var max_slots: int = 4

## Starting metal — enough for one dogfighter build by default.
@export var starting_metal: int = 50

## Starting crystal — supplements the first chassis.
@export var starting_crystal: int = 20

## Starting fuel — covers an initial deployment or two.
@export var starting_fuel: int = 20

## Phase-based harvest rate multiplier applied on top of module bonuses.
var harvest_rate_multiplier: float = 1.0

# -- State -----------------------------------------------------------------

## Current axial position on the hex grid.
var current_hex: Vector2i = Vector2i.ZERO

## Previous hex position — used for shunting back on a draw.
var previous_hex: Vector2i = Vector2i.ZERO

## Reference to the parent hex grid.  Set via [method initialize] or
## auto-discovered in [method _ready].
var hex_grid: HexGrid = null

## Guards against input while a move tween is running.
var is_moving: bool = false

## Whether the carrier is currently harvesting a resource node.
var _is_harvesting: bool = false

## The hex cell currently being harvested, or null.
var _harvest_cell: HexCell = null

## Resource amount when harvesting began — used for progress calculation.
var _harvest_start_amount: float = 0.0

## Seconds remaining before the carrier can move again.
var _move_cooldown: float = 0.0

## Float accumulator — only whole units are deposited into [Inventory].
var _harvest_accumulator: float = 0.0

## Reference to the carrier's child [Inventory] node.
var _inventory: Inventory = null

## Queued path of hex coords for auto-move. Empty = no auto-move in progress.
var _move_queue: Array[Vector2i] = []

## Whether the carrier is currently executing an auto-move path.
var _auto_moving: bool = false

## Installed carrier modules.  Each element is a [CarrierModule] or null.
var _modules: Array[CarrierModule] = []

## Reference to the carrier's child [Hangar] node.
var _hangar: Hangar = null

## Reference to the carrier's child [BuildQueue] node.
var _build_queue: BuildQueue = null

## Visual ring placed on the destination hex during auto-move.
var _destination_indicator: MeshInstance3D = null

## Elapsed time accumulator for destination indicator pulse.
var _dest_pulse_time: float = 0.0

# -- Constants -------------------------------------------------------------

## Carrier body colour — teal / cyan so it pops against terrain.
const CARRIER_COLOR: Color = Color(0.2, 0.7, 0.8)

## Height offset so the carrier sits visibly on top of the hex prism.
const CARRIER_Y_OFFSET: float = 0.3

## Duration of the movement tween in seconds.
const MOVE_TWEEN_DURATION: float = 0.3

## Color for the auto-move destination ring indicator.
const DEST_INDICATOR_COLOR: Color = Color(0.3, 0.85, 1.0)

## Y position of the destination ring — just above the ground to avoid z-fighting.
const DEST_INDICATOR_Y: float = 0.02

## Pulse speed (radians per second) for the destination indicator.
const DEST_PULSE_SPEED: float = 3.0

## Minimum alpha during the pulse cycle.
const DEST_PULSE_ALPHA_MIN: float = 0.3

## Maximum alpha during the pulse cycle.
const DEST_PULSE_ALPHA_MAX: float = 0.8

# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	_create_visual()
	_setup_inventory()
	_setup_hangar()
	_setup_build_queue()
	# Auto-discover the HexGrid sibling if nobody called initialize() yet.
	if hex_grid == null and get_parent() != null:
		hex_grid = get_parent().get_node_or_null("HexGrid") as HexGrid
	if hex_grid != null and not _is_parked():
		_snap_to_hex(current_hex.x, current_hex.y)
		_park(current_hex.x, current_hex.y)
	_install_default_modules()


func _process(delta: float) -> void:
	if _move_cooldown > 0.0:
		_move_cooldown -= delta

	# Pulse the destination indicator if it exists.
	if _destination_indicator != null:
		_dest_pulse_time += delta
		var t: float = (sin(_dest_pulse_time * DEST_PULSE_SPEED) + 1.0) * 0.5
		var alpha: float = lerpf(DEST_PULSE_ALPHA_MIN, DEST_PULSE_ALPHA_MAX, t)
		var mat: StandardMaterial3D = _destination_indicator.material_override
		if mat != null:
			mat.albedo_color.a = alpha

	# Auto-move: advance to next queued hex when cooldown expires
	if _auto_moving and not is_moving and _move_cooldown <= 0.0 and not _move_queue.is_empty():
		var next_hex: Vector2i = _move_queue[0]
		var next_cell := hex_grid.get_cell(next_hex.x, next_hex.y) if hex_grid else null
		# Abort if the next cell is blocked (something moved into it)
		if next_cell == null or (next_cell.occupant != null and next_cell.occupant != self and not next_cell.occupant is ThreatEntity):
			cancel_auto_move()
		else:
			_move_queue.remove_at(0)
			move_to_hex(next_hex.x, next_hex.y)
			if _move_queue.is_empty():
				_auto_moving = false
				_remove_destination_indicator()
				auto_move_ended.emit()

	if not _is_harvesting or _harvest_cell == null:
		return

	# Drain from hex, accumulate float, deposit whole units.
	var drain: float = minf(harvest_rate * harvest_rate_multiplier * delta, _harvest_cell.resource_amount)
	_harvest_cell.resource_amount -= drain
	_harvest_accumulator += drain
	harvest_tick.emit(_harvest_cell.resource_type, drain)

	# Deposit whole units into inventory.
	var whole_units: int = int(_harvest_accumulator)
	if whole_units > 0:
		_inventory.add_resource(_harvest_cell.resource_type, whole_units)
		_harvest_accumulator -= float(whole_units)

	# Check for depletion.
	if _harvest_cell.resource_amount <= 0.0:
		_harvest_cell.resource_amount = 0.0
		# Flush any remaining fractional accumulator.
		var leftover: int = int(ceilf(_harvest_accumulator))
		if leftover > 0:
			_inventory.add_resource(_harvest_cell.resource_type, leftover)
		_harvest_accumulator = 0.0
		print("[Carrier] Harvest complete — node depleted")
		_stop_harvesting()


# -- Public API ------------------------------------------------------------

## Return the carrier's [Inventory] node.
func get_inventory() -> Inventory:
	return _inventory


## Return the carrier's [Hangar] node.
func get_hangar() -> Hangar:
	return _hangar


## Return the carrier's [BuildQueue] node.
func get_build_queue() -> BuildQueue:
	return _build_queue


## Return the amount of resource remaining on the current harvest node, or 0.0.
func get_harvest_remaining() -> float:
	if _is_harvesting and _harvest_cell != null:
		return _harvest_cell.resource_amount
	return 0.0


## Return the starting resource amount of the current harvest node, or 0.0.
func get_harvest_max() -> float:
	if _is_harvesting:
		return _harvest_start_amount
	return 0.0


## Return the seconds remaining before the carrier can move again.
func get_move_cooldown_remaining() -> float:
	return maxf(0.0, _move_cooldown)


## Compute the current movement cooldown in seconds based on installed modules.
## Formula: max(1.0, 2.0 * total_modules - 5.0 * engine_count)
func get_move_interval() -> float:
	var total: int = get_module_count()
	var engines: int = get_modules_by_type(&"engine").size()
	return maxf(1.0, 2.0 * total - 5.0 * engines)


## Set up the carrier on a specific grid at a starting hex.
func initialize(grid: HexGrid, start_q: int = 0, start_r: int = 0) -> void:
	hex_grid = grid
	_snap_to_hex(start_q, start_r)
	_park(start_q, start_r)


## Move to the target hex with a smooth tween.
##
## Unparks from the current hex, tweens world position, then parks on the
## new hex.  Emits [signal moved] on completion.
func move_to_hex(target_q: int, target_r: int) -> void:
	if is_moving:
		return

	previous_hex = current_hex
	var from := current_hex
	_stop_harvesting()
	_unpark()

	is_moving = true
	var target_world := hex_grid.axial_to_world(target_q, target_r)
	target_world.y = CARRIER_Y_OFFSET

	var tween := create_tween()
	tween.tween_property(self, "position", target_world, MOVE_TWEEN_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

	current_hex = Vector2i(target_q, target_r)
	is_moving = false
	_park(target_q, target_r)
	moved.emit(from, current_hex)
	_move_cooldown = get_move_interval()


## Return all hexes reachable this turn (within [member move_range] and
## not blocked by another occupant).
func get_reachable_hexes() -> Array[HexCell]:
	if hex_grid == null:
		return [] as Array[HexCell]

	var candidates := hex_grid.get_cells_in_range(
		current_hex.x, current_hex.y, move_range
	)
	var reachable: Array[HexCell] = []
	for cell: HexCell in candidates:
		# Skip own hex and hexes occupied by non-threats (e.g. another carrier).
		if cell.axial_coords() == current_hex:
			continue
		if cell.occupant != null and not cell.occupant is ThreatEntity:
			continue
		reachable.append(cell)
	return reachable


## Start auto-moving along a path of hex coordinates.
## The path should NOT include the current hex.
func start_auto_move(path: Array[Vector2i]) -> void:
	if path.is_empty():
		return
	_move_queue = path.duplicate()
	_auto_moving = true
	# Show a glowing ring on the final destination hex.
	_create_destination_indicator(path[path.size() - 1])
	auto_move_started.emit(path)
	# Immediately start the first move if ready
	if not is_moving and _move_cooldown <= 0.0:
		var next_hex: Vector2i = _move_queue.pop_front()
		move_to_hex(next_hex.x, next_hex.y)
		if _move_queue.is_empty():
			_auto_moving = false
			_remove_destination_indicator()
			auto_move_ended.emit()


## Cancel any in-progress auto-move. The carrier stops at its current hex.
func cancel_auto_move() -> void:
	if not _auto_moving:
		return
	_move_queue.clear()
	_auto_moving = false
	_remove_destination_indicator()
	auto_move_ended.emit()
	print("[Carrier] Auto-move cancelled")


## Return whether the carrier is currently in auto-move mode.
func is_auto_moving() -> bool:
	return _auto_moving


# -- Module API ------------------------------------------------------------

## Install a module in the next free slot.
##
## Returns [code]false[/code] if all slots are full or if installing
## would exceed the carrier's power budget.
func install_module(module: CarrierModule) -> bool:
	if get_module_count() >= max_slots:
		print("[Carrier] Cannot install %s — no free slots" % module.module_name)
		return false
	if not has_power_for(module):
		print("[Carrier] Cannot install %s — insufficient power (need %d, available %d)" \
			% [module.module_name, module.power_cost, get_available_power()])
		return false
	# Check resource costs (empty dict = free, e.g. default starting modules).
	if not module.resource_costs.is_empty() and _inventory != null:
		for res_type: StringName in module.resource_costs:
			var needed: int = module.resource_costs[res_type]
			if not _inventory.has_enough(res_type, needed):
				print("[Carrier] Cannot install %s — not enough %s (need %d, have %d)" \
					% [module.module_name, res_type, needed, _inventory.get_amount(res_type)])
				return false
		# Deduct resources.
		for res_type: StringName in module.resource_costs:
			_inventory.remove_resource(res_type, module.resource_costs[res_type])
		print("[Carrier] Spent resources for %s" % module.module_name)

	_modules.append(module)
	var slot_index: int = _modules.size() - 1
	module.on_install(self)
	print("[Carrier] Installed %s in slot %d" % [module.module_name, slot_index])
	module_installed.emit(module, slot_index)
	return true


## Remove and return the module at [param slot_index].
##
## Returns [code]null[/code] if the index is out of range.
func uninstall_module(slot_index: int) -> CarrierModule:
	if slot_index < 0 or slot_index >= _modules.size():
		print("[Carrier] Cannot uninstall — invalid slot %d" % slot_index)
		return null

	var module: CarrierModule = _modules[slot_index]
	_modules.remove_at(slot_index)
	module.on_uninstall(self)
	print("[Carrier] Uninstalled %s from slot %d" % [module.module_name, slot_index])
	module_uninstalled.emit(module, slot_index)
	return module


## Return the module at [param slot_index], or [code]null[/code] if empty.
func get_module(slot_index: int) -> CarrierModule:
	if slot_index < 0 or slot_index >= _modules.size():
		return null
	return _modules[slot_index]


## Return a copy of the installed modules array.
func get_modules() -> Array[CarrierModule]:
	return _modules.duplicate()


## Return the number of slots currently occupied.
func get_module_count() -> int:
	return _modules.size()


## Return all installed modules matching [param type].
func get_modules_by_type(type: StringName) -> Array[CarrierModule]:
	var result: Array[CarrierModule] = []
	for module: CarrierModule in _modules:
		if module.get_module_type() == type:
			result.append(module)
	return result


## Total power generated by all installed [ReactorModule]s.
func get_total_power_output() -> int:
	var total: int = 0
	for module: CarrierModule in _modules:
		if module is ReactorModule:
			total += (module as ReactorModule).power_output
	return total


## Total power consumed by all installed non-reactor modules.
func get_total_power_cost() -> int:
	var total: int = 0
	for module: CarrierModule in _modules:
		total += module.power_cost
	return total


## Remaining power headroom (output minus cost).
func get_available_power() -> int:
	return get_total_power_output() - get_total_power_cost()


## Check whether installing [param module] would stay within the power budget.
func has_power_for(module: CarrierModule) -> bool:
	return get_available_power() >= module.power_cost


# -- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if hex_grid == null:
		return

	# Right-click cancels auto-move
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if _auto_moving:
			cancel_auto_move()
		return

	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return

	var target := _get_hex_under_mouse(mb)
	if target == current_hex:
		return

	var cell := hex_grid.get_cell(target.x, target.y)
	if cell == null:
		return

	# Ctrl+click: plot multi-hex route
	if mb.ctrl_pressed:
		var path: Array[Vector2i] = hex_grid.find_path(current_hex, target)
		if not path.is_empty():
			start_auto_move(path)
		return

	# Normal click: single adjacent move (existing behavior)
	if _auto_moving or is_moving or _move_cooldown > 0.0:
		return
	if cell.occupant != null and not cell.occupant is ThreatEntity:
		return
	var origin_cell := hex_grid.get_cell(current_hex.x, current_hex.y)
	if origin_cell == null:
		return
	if origin_cell.distance_to(cell) > move_range:
		return
	move_to_hex(target.x, target.y)


# -- Parking (private) ----------------------------------------------------

## Claim a hex cell by setting its occupant to this carrier.
func _park(q: int, r: int) -> void:
	var cell := hex_grid.get_cell(q, r)
	if cell != null:
		cell.occupant = self
	parked.emit(Vector2i(q, r))
	# Kick off harvesting if we just parked on a resource node.
	if cell != null and cell.terrain == HexCell.TerrainType.RESOURCE \
			and cell.resource_amount > 0.0 and cell.resource_type != &"":
		_start_harvesting(cell)


## Release the currently occupied hex cell.
func _unpark() -> void:
	var cell := hex_grid.get_cell(current_hex.x, current_hex.y)
	if cell != null:
		cell.occupant = null


## Check whether we're already parked somewhere.
func _is_parked() -> bool:
	if hex_grid == null:
		return false
	var cell := hex_grid.get_cell(current_hex.x, current_hex.y)
	return cell != null and cell.occupant == self


# -- Harvesting (private) -------------------------------------------------

## Begin harvesting the given [HexCell].
func _start_harvesting(cell: HexCell) -> void:
	_harvest_cell = cell
	_harvest_start_amount = cell.resource_amount
	_harvest_accumulator = 0.0
	_is_harvesting = true
	print("[Carrier] Harvesting %s... (%.1f remaining)" % [cell.resource_type, cell.resource_amount])
	harvesting_started.emit(cell.resource_type)


## Stop any active harvesting session.
func _stop_harvesting() -> void:
	if not _is_harvesting:
		return
	_is_harvesting = false
	_harvest_cell = null
	_harvest_accumulator = 0.0
	harvesting_stopped.emit()


# -- Child Node Setup (private) --------------------------------------------

## Create and attach the carrier's [Inventory] child node.
##
## Seeds the inventory with enough resources for one dogfighter build
## (30 metal + 10 crystal) plus a first deployment (5 fuel), with some
## slack so the player isn't immediately stranded.
func _setup_inventory() -> void:
	_inventory = Inventory.new()
	_inventory.name = "Inventory"
	add_child(_inventory)
	# Starting resources — configurable via exports or TestLevelConfig.
	if starting_metal > 0:
		_inventory.add_resource(&"metal", starting_metal)
	if starting_crystal > 0:
		_inventory.add_resource(&"crystal", starting_crystal)
	if starting_fuel > 0:
		_inventory.add_resource(&"fuel", starting_fuel)


## Create and attach the carrier's [Hangar] child node.
func _setup_hangar() -> void:
	_hangar = Hangar.new()
	_hangar.name = "Hangar"
	add_child(_hangar)


## Create and attach the carrier's [BuildQueue] child node.
func _setup_build_queue() -> void:
	_build_queue = BuildQueue.new()
	_build_queue.name = "BuildQueue"
	add_child(_build_queue)


## Teleport back to [member previous_hex].  Used after a draw to vacate
## the contested hex so the threat entity keeps its position.
func shunt_back() -> void:
	if hex_grid == null:
		return
	_stop_harvesting()
	_unpark()
	_snap_to_hex(previous_hex.x, previous_hex.y)
	_park(previous_hex.x, previous_hex.y)


# -- Movement Helpers (private) --------------------------------------------

## Teleport to a hex without tweening.  Used for initial placement.
func _snap_to_hex(q: int, r: int) -> void:
	current_hex = Vector2i(q, r)
	var world_pos := hex_grid.axial_to_world(q, r)
	position = Vector3(world_pos.x, CARRIER_Y_OFFSET, world_pos.z)


## Project the mouse click onto the Y=0 plane and convert to axial coords.
##
## Uses camera ray math — no physics bodies required.
func _get_hex_under_mouse(event: InputEventMouseButton) -> Vector2i:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return current_hex
	var from := camera.project_ray_origin(event.position)
	var dir := camera.project_ray_normal(event.position)
	# Intersect with the Y = 0 plane.
	if is_zero_approx(dir.y):
		return current_hex  # Ray parallel to ground — bail.
	var t := -from.y / dir.y
	var hit := from + dir * t
	return hex_grid.world_to_axial(hit)


# -- Default Modules (private) --------------------------------------------

## Install the carrier's starting loadout so it's functional out of the gate.
func _install_default_modules() -> void:
	var default_reactor := ReactorModule.new()
	default_reactor.module_name = &"Standard Reactor"
	default_reactor.description = "The carrier's stock reactor. Keeps the lights on."
	default_reactor.power_output = 5
	default_reactor.slot_bonus = 2  # Starter is weaker than purchased reactors
	install_module(default_reactor)

	var default_harvester := HarvesterModule.new()
	default_harvester.module_name = &"Basic Harvester"
	default_harvester.description = "Standard resource extraction equipment."
	default_harvester.harvest_rate_bonus = 5.0
	install_module(default_harvester)

	var default_hangar := HangarModule.new()
	default_hangar.module_name = &"Basic Hangar"
	default_hangar.description = "Standard mech storage bay."
	default_hangar.mech_capacity = 4
	install_module(default_hangar)


# -- Destination Indicator (private) --------------------------------------

## Create a glowing ring on the target hex to show the auto-move destination.
##
## The ring is parented to the overworld scene root (carrier's parent) so it
## stays fixed in world space while the carrier moves toward it.
func _create_destination_indicator(target_hex: Vector2i) -> void:
	_remove_destination_indicator()  # Clean up any stale indicator.

	var mesh_instance := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.4
	torus.outer_radius = 1.8
	torus.rings = 32
	torus.ring_segments = 32
	mesh_instance.mesh = torus

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(DEST_INDICATOR_COLOR, DEST_PULSE_ALPHA_MAX)
	mat.emission_enabled = true
	mat.emission = DEST_INDICATOR_COLOR
	mat.emission_energy_multiplier = 1.5
	mat.no_depth_test = true
	mat.render_priority = 1
	mesh_instance.material_override = mat

	# Position at the destination hex, just above the ground plane.
	# TorusMesh lies flat in the XZ plane by default — no rotation needed.
	var world_pos := hex_grid.axial_to_world(target_hex.x, target_hex.y)
	mesh_instance.position = Vector3(world_pos.x, DEST_INDICATOR_Y, world_pos.z)

	# Parent to the overworld root so the ring stays in place.
	if get_parent() != null:
		get_parent().add_child(mesh_instance)
	else:
		add_child(mesh_instance)

	_destination_indicator = mesh_instance
	_dest_pulse_time = 0.0
	print("[Carrier] Destination indicator placed at hex %s" % str(target_hex))


## Remove and free the destination indicator if it exists.
func _remove_destination_indicator() -> void:
	if _destination_indicator != null:
		_destination_indicator.queue_free()
		_destination_indicator = null
		_dest_pulse_time = 0.0


# -- Visual Construction (private) ----------------------------------------

## Build a simple placeholder mesh so the carrier is visible on the grid.
##
## A squat teal box — nothing fancy, we'll swap in a real model later.
func _create_visual() -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 0.8, 1.2)
	mesh_instance.mesh = box
	# Shift the mesh up so its base sits at Y=0 of this node (which is
	# already at CARRIER_Y_OFFSET above the hex surface).
	mesh_instance.position.y = box.size.y / 2.0

	var mat := StandardMaterial3D.new()
	mat.albedo_color = CARRIER_COLOR
	mesh_instance.material_override = mat

	add_child(mesh_instance)
