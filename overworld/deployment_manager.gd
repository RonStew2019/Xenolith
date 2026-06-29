extends Node
class_name DeploymentManager
## Coordinates the deployment flow when a threat engages the player carrier.
##
## Listens for [signal ThreatManager.engagement_triggered], pauses the
## carrier, tracks mech selection and fuel costs, and ultimately launches
## the player into combat (or lets them retreat).
##
## Auto-discovers [ThreatManager] and [Carrier] siblings in [method _ready].
## The actual combat arena is stubbed — this is a coordinator, not a UI.

# -- Signals ---------------------------------------------------------------

## The deployment flow has started — UI should open.
signal deployment_started(threat: ThreatEntity)

## Player confirmed launch — mechs are deployed, fuel spent.
signal deployment_launched(threat: ThreatEntity, deployed_mechs: Array[MechBlueprint], piloted_mech: MechBlueprint)

## Player chose to retreat instead of fighting.
signal deployment_retreated(threat: ThreatEntity)

## Combat arena has been created and the player is in combat.
signal combat_started(arena: CombatArena)

## Combat has ended and the overworld is restored.
signal combat_ended()

# -- Constants -------------------------------------------------------------

## Resource type used for deployment costs.
const FUEL_RESOURCE: StringName = &"fuel"

## Overworld node names to pause (PROCESS_MODE_DISABLED) during combat.
## Camera3D, DeploymentManager, and EngagementManager stay active.
const _PAUSE_ON_COMBAT := [&"Carrier", &"HexGrid", &"ProgressionManager", &"ThreatIndicatorManager", &"PauseController", &"OverworldHUD"]

# -- State -----------------------------------------------------------------

## The threat currently being engaged (null when idle).
var _current_threat: ThreatEntity = null

## Hangar indices of mechs selected for this deployment.
var _selected_indices: Array[int] = []

## Index (within the hangar) of the mech the player will pilot.
## -1 means no pilot chosen yet.
var _pilot_index: int = -1

## Whether the deployment flow is currently active.
var _is_deploying: bool = false

## The active combat arena instance, or null when not in combat.
var _arena: CombatArena = null

## Reference to the threat manager (auto-discovered).
var _threat_manager: ThreatManager = null

## Reference to the player carrier (auto-discovered).
var carrier: Carrier = null

# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	# Auto-discover siblings — same pattern as ThreatManager.
	if get_parent() != null:
		_threat_manager = get_parent().get_node_or_null("ThreatManager") as ThreatManager
		carrier = get_parent().get_node_or_null("Carrier") as Carrier

	if _threat_manager == null:
		push_warning("[DeploymentManager] No ThreatManager sibling found — deployment disabled")
		return
	if carrier == null:
		push_warning("[DeploymentManager] No Carrier sibling found — deployment disabled")
		return

	_threat_manager.engagement_triggered.connect(_on_engagement_triggered)
	print("[DeploymentManager] Ready — listening for engagements")

# -- Public API ------------------------------------------------------------

## Start the deployment flow for the given [param threat].
##
## Pauses carrier movement and emits [signal deployment_started] so the
## UI layer can open the deployment screen.
func begin_deployment(threat: ThreatEntity) -> void:
	_is_deploying = true
	_current_threat = threat
	_selected_indices.clear()
	_pilot_index = -1

	if carrier != null:
		carrier.is_moving = true

	print("[DeploymentManager] Deployment started — threat: %s (level %.1f)" % [
		threat.entity_name, threat.threat_level
	])
	deployment_started.emit(threat)


## Toggle a mech at [param hangar_index] into or out of the selection.
##
## If the mech was the designated pilot and gets deselected, the pilot
## index is cleared.
func select_mech(hangar_index: int) -> void:
	if not _is_deploying:
		push_warning("[DeploymentManager] select_mech called outside deployment flow")
		return

	var idx: int = _selected_indices.find(hangar_index)
	if idx >= 0:
		# Deselect.
		_selected_indices.remove_at(idx)
		if _pilot_index == hangar_index:
			_pilot_index = -1
		print("[DeploymentManager] Deselected mech at hangar index %d" % hangar_index)
	else:
		# Select.
		_selected_indices.append(hangar_index)
		print("[DeploymentManager] Selected mech at hangar index %d" % hangar_index)


## Designate which selected mech the player will pilot.
##
## If [param hangar_index] isn't already selected, it gets auto-selected.
func set_pilot(hangar_index: int) -> void:
	if not _is_deploying:
		push_warning("[DeploymentManager] set_pilot called outside deployment flow")
		return

	if hangar_index not in _selected_indices:
		select_mech(hangar_index)

	_pilot_index = hangar_index
	print("[DeploymentManager] Pilot set to hangar index %d" % hangar_index)


## Select all mechs in the hangar for deployment.
func select_all() -> void:
	if not _is_deploying or carrier == null:
		return
	var hangar: Hangar = carrier.get_hangar()
	_selected_indices.clear()
	for i: int in range(hangar.get_mech_count()):
		_selected_indices.append(i)
	# Auto-set pilot to first mech if not already set.
	if _pilot_index < 0 and not _selected_indices.is_empty():
		_pilot_index = _selected_indices[0]
	print("[DeploymentManager] Selected all %d mechs" % _selected_indices.size())


## Deselect all mechs.
func deselect_all() -> void:
	if not _is_deploying:
		return
	_selected_indices.clear()
	_pilot_index = -1
	print("[DeploymentManager] Deselected all mechs")


## Return the currently selected hangar indices.
func get_selected_indices() -> Array[int]:
	return _selected_indices


## Return the hangar index of the mech the player will pilot (-1 if none).
func get_pilot_index() -> int:
	return _pilot_index


## Total fuel cost for the current selection.
##
## Sums the [member MechChassis.deploy_fuel_cost] of each selected mech's
## chassis.  Falls back to 5 if a blueprint has no chassis set.
func get_deploy_cost() -> int:
	var total: int = 0
	if carrier == null:
		return 0
	var hangar: Hangar = carrier.get_hangar()
	var mechs: Array[MechBlueprint] = hangar.get_mechs()
	for idx: int in _selected_indices:
		if idx >= 0 and idx < mechs.size():
			var bp: MechBlueprint = mechs[idx]
			if bp.chassis != null:
				total += bp.chassis.deploy_fuel_cost
			else:
				total += 5  # fallback
	return total


## Whether the carrier's inventory can cover [method get_deploy_cost].
func can_afford_deployment() -> bool:
	if carrier == null:
		return false
	return carrier.get_inventory().has_enough(FUEL_RESOURCE, get_deploy_cost())


## Whether all launch prerequisites are met:
## at least one mech selected, pilot chosen, and fuel affordable.
func can_launch() -> bool:
	return (
		_is_deploying
		and _selected_indices.size() > 0
		and _pilot_index >= 0
		and can_afford_deployment()
	)


## Validate, pay costs, extract mechs from the hangar, and fire.
##
## Emits [signal deployment_launched] with the deployed [MechBlueprint]
## array and the piloted mech, then ends the deployment flow.
func launch() -> void:
	if not can_launch():
		push_warning("[DeploymentManager] launch() called but can_launch() is false")
		return

	# Pay fuel.
	var cost: int = get_deploy_cost()
	var inventory: Inventory = carrier.get_inventory()
	inventory.remove_resource(FUEL_RESOURCE, cost)
	print("[DeploymentManager] Spent %d fuel for %d mechs" % [cost, _selected_indices.size()])

	# Pull mechs from hangar — remove highest indices first so lower
	# indices stay valid during removal.
	var sorted_indices: Array[int] = _selected_indices.duplicate()
	sorted_indices.sort()
	sorted_indices.reverse()

	var deployed_mechs: Array[MechBlueprint] = []
	var piloted_mech: MechBlueprint = null
	var hangar: Hangar = carrier.get_hangar()

	for idx: int in sorted_indices:
		var mech: MechBlueprint = hangar.remove_mech(idx)
		deployed_mechs.append(mech)
		if idx == _pilot_index:
			piloted_mech = mech

	# reverse so they're back in ascending selection order
	deployed_mechs.reverse()

	var threat: ThreatEntity = _current_threat

	# --- Combat Arena Transition ---
	var terrain_type: HexCell.TerrainType = HexCell.TerrainType.MOUNTAIN
	if threat.hex_grid != null:
		var hex: HexCell = threat.hex_grid.get_cell(threat.current_hex.x, threat.current_hex.y)
		if hex != null:
			terrain_type = hex.terrain

	_arena = CombatArena.new()
	_arena.setup(terrain_type, threat, carrier)

	# If the game is paused (via PauseController), unpause before combat
	# so we don't enter the arena frozen.
	var tree := get_tree()
	if tree != null and tree.paused:
		tree.paused = false
		print("[DeploymentManager] Unpaused tree before entering combat")

	# Hide all overworld siblings so only the arena is visible.
	var parent_node: Node = get_parent()
	if parent_node != null:
		for child: Node in parent_node.get_children():
			if child is Node3D:
				(child as Node3D).visible = false
			elif child is CanvasLayer:
				(child as CanvasLayer).visible = false
		# Pause overworld processing nodes that shouldn't run during combat.
		for node_name: StringName in _PAUSE_ON_COMBAT:
			var n: Node = parent_node.get_node_or_null(NodePath(node_name))
			if n != null:
				n.process_mode = Node.PROCESS_MODE_DISABLED
		parent_node.add_child(_arena)

	var terrain_name: String = HexCell.TerrainType.keys()[terrain_type]
	print("[DeploymentManager] LAUNCHED into combat arena! Terrain: %s" % terrain_name)
	deployment_launched.emit(threat, deployed_mechs, piloted_mech)
	combat_started.emit(_arena)
	_end_deployment()


## Retreat from the current engagement without fighting.
##
## Emits [signal deployment_retreated] and cleans up state.
func retreat() -> void:
	if not _is_deploying:
		push_warning("[DeploymentManager] retreat() called outside deployment flow")
		return

	var threat: ThreatEntity = _current_threat
	print("[DeploymentManager] Retreated from threat")
	deployment_retreated.emit(threat)
	_end_deployment()

## End the current combat, tear down the arena, and restore the overworld.
##
## Stubbed for future engagement resolution — currently just cleans up.
func end_combat() -> void:
	if _arena == null:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var parent_node: Node = get_parent()
	if parent_node != null:
		# Unpause overworld processing nodes.
		for node_name: StringName in _PAUSE_ON_COMBAT:
			var n: Node = parent_node.get_node_or_null(NodePath(node_name))
			if n != null:
				n.process_mode = Node.PROCESS_MODE_INHERIT
		# PauseController needs PROCESS_MODE_ALWAYS (not INHERIT) to
		# receive input while the tree is paused.
		var pause_ctrl: Node = parent_node.get_node_or_null("PauseController")
		if pause_ctrl != null:
			pause_ctrl.process_mode = Node.PROCESS_MODE_ALWAYS
		# Show all overworld siblings again.
		for child: Node in parent_node.get_children():
			if child == _arena:
				continue
			if child is Node3D:
				(child as Node3D).visible = true
			elif child is CanvasLayer:
				(child as CanvasLayer).visible = true
		# Recenter the overworld camera on the carrier.
		var cam: Node = parent_node.get_node_or_null("Camera3D")
		if cam != null and cam.has_method("recenter"):
			cam.recenter()
	_arena.queue_free()
	_arena = null
	print("[DeploymentManager] Combat ended — returning to overworld")
	combat_ended.emit()


# -- Private ---------------------------------------------------------------

## Clear all deployment state and unpause the carrier.
func _end_deployment() -> void:
	_current_threat = null
	_selected_indices.clear()
	_pilot_index = -1
	_is_deploying = false

	if carrier != null:
		carrier.is_moving = false

	print("[DeploymentManager] Deployment flow ended — carrier unpaused")


## Handler for [signal ThreatManager.engagement_triggered].
##
## Guards against re-entry if we're already mid-deployment.
func _on_engagement_triggered(threat: ThreatEntity) -> void:
	if _is_deploying:
		print("[DeploymentManager] Already deploying — ignoring engagement with %s" % threat.entity_name)
		return
	begin_deployment(threat)
