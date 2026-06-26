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

## Float accumulator — only whole units are deposited into [Inventory].
var _harvest_accumulator: float = 0.0

## Reference to the carrier's child [Inventory] node.
var _inventory: Inventory = null

## Installed carrier modules.  Each element is a [CarrierModule] or null.
var _modules: Array[CarrierModule] = []

## Reference to the carrier's child [Hangar] node.
var _hangar: Hangar = null

## Reference to the carrier's child [BuildQueue] node.
var _build_queue: BuildQueue = null

# -- Constants -------------------------------------------------------------

## Carrier body colour — teal / cyan so it pops against terrain.
const CARRIER_COLOR: Color = Color(0.2, 0.7, 0.8)

## Height offset so the carrier sits visibly on top of the hex prism.
const CARRIER_Y_OFFSET: float = 0.3

## Duration of the movement tween in seconds.
const MOVE_TWEEN_DURATION: float = 0.3

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
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if is_moving or hex_grid == null:
		return

	var target := _get_hex_under_mouse(mb)
	if target == current_hex:
		return

	var cell := hex_grid.get_cell(target.x, target.y)
	if cell == null:
		return  # Clicked outside the grid.
	if cell.occupant != null and not cell.occupant is ThreatEntity:
		return  # Hex occupied by non-threat entity.

	# Range check — use HexCell.distance_to() for correctness.
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
