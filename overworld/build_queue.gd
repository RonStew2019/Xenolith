extends Node
class_name BuildQueue
## Processes the carrier's mech fabrication queue.
##
## Lives as a child of [Carrier].  Each frame, advances the first queued
## build by [code]delta * fabrication_speed[/code].  Fabrication speed is
## the sum of all installed [FabricatorModule] build speeds — if no
## fabricator is installed, nothing gets built.
##
## Completed mechs are stored in the carrier's [Hangar] automatically.

# -- Signals ---------------------------------------------------------------

## Emitted when a new blueprint enters the queue.
signal build_started(blueprint: MechBlueprint)

## Emitted every frame while the first item is being fabricated.
signal build_progress(blueprint: MechBlueprint, progress: float, total: float)

## Emitted when a mech finishes building and enters the hangar.
signal build_completed(blueprint: MechBlueprint)

## Emitted when a queued build is cancelled and resources are refunded.
signal build_cancelled(blueprint: MechBlueprint)

# -- State -----------------------------------------------------------------

## The carrier this build queue belongs to.  Set in [method _ready].
var carrier: Carrier = null

## Each entry: {blueprint: MechBlueprint, progress: float, build_time: float}
var _queue: Array[Dictionary] = []

# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	carrier = get_parent() as Carrier
	if carrier == null:
		push_warning("[BuildQueue] Parent is not a Carrier — build queue won't function.")


func _process(delta: float) -> void:
	if _queue.is_empty():
		return
	var speed: float = get_fabrication_speed()
	if speed <= 0.0:
		return

	var entry: Dictionary = _queue[0]
	entry.progress += delta * speed
	var blueprint: MechBlueprint = entry.blueprint
	build_progress.emit(blueprint, entry.progress, entry.build_time)

	if entry.progress >= entry.build_time:
		_queue.remove_at(0)
		_deliver_to_hangar(blueprint)

# -- Public API ------------------------------------------------------------

## Queue a blueprint for fabrication.
##
## Immediately deducts resources from the carrier's inventory.  Returns
## [code]false[/code] if the carrier can't afford it, if there's no room
## in the hangar (counting already-queued builds), or if no fabricator
## module is installed.
func queue_build(blueprint: MechBlueprint) -> bool:
	if carrier == null:
		return false

	# Sanity: need at least one fabricator installed.
	if get_fabrication_speed() <= 0.0:
		print("[BuildQueue] Cannot build — no fabricator module installed")
		return false

	# Check hangar capacity (current mechs + already-queued builds).
	var hangar: Hangar = carrier.get_hangar()
	var pending: int = hangar.get_mech_count() + _queue.size()
	if pending >= hangar.get_max_capacity():
		print("[BuildQueue] Cannot build %s — hangar full (%d pending, %d capacity)" \
			% [blueprint.blueprint_name, pending, hangar.get_max_capacity()])
		return false

	# Check and deduct resources.
	var costs: Dictionary = blueprint.get_total_cost()
	var inventory: Inventory = carrier.get_inventory()
	for resource_type: StringName in costs:
		if not inventory.has_enough(resource_type, costs[resource_type]):
			print("[BuildQueue] Cannot build %s — not enough %s (need %d, have %d)" \
				% [blueprint.blueprint_name, resource_type,
				   costs[resource_type], inventory.get_amount(resource_type)])
			return false

	# All checks passed — deduct resources.
	for resource_type: StringName in costs:
		inventory.remove_resource(resource_type, costs[resource_type])

	var entry: Dictionary = {
		blueprint = blueprint,
		progress = 0.0,
		build_time = blueprint.get_build_time(),
	}
	_queue.append(entry)
	print("[BuildQueue] Queued %s (%.1fs build time, speed %.1fx)" \
		% [blueprint.blueprint_name, entry.build_time, get_fabrication_speed()])
	build_started.emit(blueprint)
	return true


## Cancel and refund the build at [param index] in the queue.
## Returns [code]false[/code] if the index is invalid.
func cancel_build(index: int) -> bool:
	if index < 0 or index >= _queue.size():
		print("[BuildQueue] Cannot cancel — invalid index %d" % index)
		return false

	var entry: Dictionary = _queue[index]
	var blueprint: MechBlueprint = entry.blueprint
	_queue.remove_at(index)

	# Refund resources.
	var costs: Dictionary = blueprint.get_total_cost()
	var inventory: Inventory = carrier.get_inventory()
	for resource_type: StringName in costs:
		inventory.add_resource(resource_type, costs[resource_type])

	print("[BuildQueue] Cancelled %s — resources refunded" % blueprint.blueprint_name)
	build_cancelled.emit(blueprint)
	return true


## Return a shallow copy of the queue.
func get_queue() -> Array[Dictionary]:
	return _queue.duplicate()


## Number of builds currently queued.
func get_queue_size() -> int:
	return _queue.size()


## Total fabrication speed from all installed [FabricatorModule]s.
## Returns [code]0.0[/code] if no fabricator is installed.
func get_fabrication_speed() -> float:
	if carrier == null:
		return 0.0
	var total: float = 0.0
	var fabricators: Array[CarrierModule] = carrier.get_modules_by_type(&"fabricator")
	for module: CarrierModule in fabricators:
		total += (module as FabricatorModule).build_speed
	return total

# -- Private ---------------------------------------------------------------

## Deliver a completed mech to the hangar.
func _deliver_to_hangar(blueprint: MechBlueprint) -> void:
	var hangar: Hangar = carrier.get_hangar()
	if hangar.store_mech(blueprint):
		print("[BuildQueue] Build complete — %s delivered to hangar" % blueprint.blueprint_name)
	else:
		# This shouldn't happen if we checked capacity at queue time, but
		# modules can be uninstalled mid-build so handle it gracefully.
		print("[BuildQueue] Build complete but hangar full — %s lost!" % blueprint.blueprint_name)
	build_completed.emit(blueprint)
