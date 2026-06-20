extends Node
class_name EngagementManager
## Manages mid-combat flow: win/lose conditions, mech switching, and
## reserve deployment.
##
## Acts as the combat state machine once the player launches into an arena.
## Auto-discovers [DeploymentManager] and [Carrier] siblings in
## [method _ready].  Connects to
## [signal DeploymentManager.deployment_launched] to capture deployed mech
## data, then [signal DeploymentManager.combat_started] to spin up the
## engagement.
##
## [b]Victory:[/b] enemy target's reactor is breached.[br]
## [b]Defeat:[/b] player carrier's reactor is breached, OR all deployed
## mechs are destroyed with no reserves available.

# -- Signals ---------------------------------------------------------------

## The engagement ended in victory — enemy destroyed.
signal engagement_won()

## The engagement ended in defeat — carrier destroyed or all mechs lost.
signal engagement_lost()

## A deployed mech was destroyed in combat.
signal mech_destroyed(mech: CombatTarget, blueprint: MechBlueprint)

## The player's piloted mech was destroyed and control switched to another.
signal pilot_switched(new_pilot: CombatTarget, blueprint: MechBlueprint)

## A reserve mech was pulled from the hangar and deployed mid-combat.
signal reserve_deployed(mech: CombatTarget, blueprint: MechBlueprint)

# -- Constants -------------------------------------------------------------

## Fuel cost per reserve mech deployed mid-combat (mirrors
## [member DeploymentManager.DEPLOY_COST_PER_MECH]).
const DEPLOY_COST_PER_MECH: int = 5

## Resource type used for deployment costs.
const FUEL_RESOURCE: StringName = &"fuel"

## Mech placeholder box size — real models come in Phase 4.
const MECH_BOX_SIZE := Vector3(1.0, 2.0, 1.0)

## Piloted mech color — green so the player can spot themselves.
const PILOT_COLOR: Color = Color(0.2, 0.8, 0.3)

## AI-controlled mech color — blue.
const AI_MECH_COLOR: Color = Color(0.3, 0.5, 0.9)

## Seconds to wait after victory/defeat before tearing down the arena.
const END_COMBAT_DELAY: float = 2.0

# -- State -----------------------------------------------------------------

## Whether an engagement is currently active.
var _is_engaged: bool = false

## The active combat arena.
var _arena: CombatArena = null

## Deployed mech [CombatTarget]s in the arena (includes the piloted one).
var _deployed_targets: Array[CombatTarget] = []

## Parallel array — blueprint for each deployed target (same indices).
var _deployed_blueprints: Array[MechBlueprint] = []

## The [CombatTarget] the player is currently piloting.
var _piloted_mech: CombatTarget = null

## Blueprint of the currently piloted mech.
var _piloted_blueprint: MechBlueprint = null

## Pending data from [signal DeploymentManager.deployment_launched],
## cached until [signal DeploymentManager.combat_started] fires.
var _pending_deployed: Array[MechBlueprint] = []
var _pending_piloted: MechBlueprint = null

## Round-robin index into the arena's spawn points.
var _next_spawn_index: int = 0

## Reference to [DeploymentManager] (auto-discovered sibling).
var _deployment_manager: DeploymentManager = null

## Reference to [Carrier] (auto-discovered sibling).
var _carrier: Carrier = null


# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	if get_parent() != null:
		_deployment_manager = get_parent().get_node_or_null(
			"DeploymentManager"
		) as DeploymentManager
		_carrier = get_parent().get_node_or_null("Carrier") as Carrier

	if _deployment_manager == null:
		push_warning("[EngagementManager] No DeploymentManager sibling — disabled")
		return
	if _carrier == null:
		push_warning("[EngagementManager] No Carrier sibling — disabled")
		return

	_deployment_manager.deployment_launched.connect(_on_deployment_launched)
	_deployment_manager.combat_started.connect(_on_combat_started)
	print("[EngagementManager] Ready — listening for combat")


# -- Public API ------------------------------------------------------------

## Kick off the engagement.  Spawns mech targets in the arena and wires
## reactor-breach listeners for win/lose/mech-death conditions.
##
## [param arena] — the active [CombatArena].[br]
## [param deployed_mechs] — blueprints of every mech the player deployed.[br]
## [param piloted_mech] — the blueprint the player chose to pilot.
func begin_engagement(
	arena: CombatArena,
	deployed_mechs: Array[MechBlueprint],
	piloted_mech: MechBlueprint,
) -> void:
	if _is_engaged:
		push_warning("[EngagementManager] Already engaged — ignoring")
		return

	_is_engaged = true
	_arena = arena
	_deployed_targets.clear()
	_deployed_blueprints.clear()
	_next_spawn_index = 0

	# -- Win / lose wiring -------------------------------------------------
	_connect_win_condition(arena.get_enemy_target())
	_connect_lose_condition(arena.get_player_carrier_target())

	# -- Spawn deployed mechs ----------------------------------------------
	var spawn_points: Array[Vector3] = arena.get_spawn_points()

	for bp: MechBlueprint in deployed_mechs:
		var is_pilot: bool = (bp == piloted_mech)
		var spawn_pos: Vector3 = _next_spawn_point(spawn_points)
		var target: CombatTarget = _create_mech_target(bp, spawn_pos, is_pilot)
		arena.add_child(target)

		_deployed_targets.append(target)
		_deployed_blueprints.append(bp)

		if is_pilot:
			_piloted_mech = target
			_piloted_blueprint = bp

		target.get_reactor().reactor_breached.connect(
			_on_mech_breached.bind(target)
		)

		print("[EngagementManager] Deployed %s at spawn %d%s" % [
			bp.blueprint_name,
			_next_spawn_index - 1,
			" (PILOTED)" if is_pilot else "",
		])

	if _piloted_mech == null:
		push_warning("[EngagementManager] No piloted mech in deployed array!")

	print("[EngagementManager] Engagement started — %d mechs vs %s" % [
		_deployed_targets.size(),
		arena.get_enemy_target().display_name if arena.get_enemy_target() else "??",
	])


## Deploy a reserve mech from the carrier's hangar mid-combat.
##
## [param hangar_index] — index into [method Hangar.get_mechs].[br]
## Returns [code]true[/code] if the mech was successfully deployed.
func deploy_reserve(hangar_index: int) -> bool:
	if not _is_engaged:
		push_warning("[EngagementManager] deploy_reserve outside engagement")
		return false
	if _arena == null or _carrier == null:
		push_warning("[EngagementManager] Missing arena or carrier")
		return false

	var hangar: Hangar = _carrier.get_hangar()
	var inventory: Inventory = _carrier.get_inventory()

	# Bounds check.
	if hangar_index < 0 or hangar_index >= hangar.get_mech_count():
		push_warning("[EngagementManager] Invalid hangar index %d (count %d)" % [
			hangar_index, hangar.get_mech_count(),
		])
		return false

	# Fuel check.
	if not inventory.has_enough(FUEL_RESOURCE, DEPLOY_COST_PER_MECH):
		print("[EngagementManager] Not enough fuel for reserve (need %d)" % DEPLOY_COST_PER_MECH)
		return false

	# Pull mech, pay cost.
	var bp: MechBlueprint = hangar.remove_mech(hangar_index)
	if bp == null:
		push_warning("[EngagementManager] Hangar.remove_mech returned null")
		return false
	inventory.remove_resource(FUEL_RESOURCE, DEPLOY_COST_PER_MECH)

	# Spawn into arena.
	var spawn_points: Array[Vector3] = _arena.get_spawn_points()
	var spawn_pos: Vector3 = _next_spawn_point(spawn_points)
	var target: CombatTarget = _create_mech_target(bp, spawn_pos, false)
	_arena.add_child(target)

	_deployed_targets.append(target)
	_deployed_blueprints.append(bp)
	target.get_reactor().reactor_breached.connect(
		_on_mech_breached.bind(target)
	)

	print("[EngagementManager] Reserve deployed: %s (cost %d fuel)" % [
		bp.blueprint_name, DEPLOY_COST_PER_MECH,
	])
	reserve_deployed.emit(target, bp)
	return true


## Return the [CombatTarget] the player is currently piloting, or null.
func get_piloted_mech() -> CombatTarget:
	return _piloted_mech


## Return the [MechBlueprint] of the currently piloted mech, or null.
func get_piloted_blueprint() -> MechBlueprint:
	return _piloted_blueprint


## Return all deployed mech targets that are still alive.
func get_alive_mechs() -> Array[CombatTarget]:
	var alive: Array[CombatTarget] = []
	for target: CombatTarget in _deployed_targets:
		if is_instance_valid(target) and not target._dead:
			alive.append(target)
	return alive


## Whether an engagement is currently running.
func is_engaged() -> bool:
	return _is_engaged


# -- Mech Construction (private) ------------------------------------------

## Build a placeholder [CombatTarget] for a deployed mech.
##
## A simple colored box — real mech models arrive in Phase 4.
func _create_mech_target(
	bp: MechBlueprint, pos: Vector3, is_pilot: bool,
) -> CombatTarget:
	var target := CombatTarget.new()
	target.name = str(bp.blueprint_name)
	target.display_name = bp.blueprint_name

	# Reactor stats from chassis.
	var integ: float = bp.chassis.base_integrity if bp.chassis != null else 100.0
	var heat_cap: float = bp.chassis.base_max_heat if bp.chassis != null else 100.0
	target.setup_reactor(integ, heat_cap)

	# Collision.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = MECH_BOX_SIZE
	col.shape = shape
	col.position.y = MECH_BOX_SIZE.y / 2.0
	target.add_child(col)

	# Visual.
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = MECH_BOX_SIZE
	mesh_inst.mesh = box
	mesh_inst.position.y = MECH_BOX_SIZE.y / 2.0
	mesh_inst.material_override = _make_mech_material(
		PILOT_COLOR if is_pilot else AI_MECH_COLOR
	)
	target.add_child(mesh_inst)

	target.position = pos
	return target


## Cycle through spawn points, wrapping around if we exhaust them.
func _next_spawn_point(spawn_points: Array[Vector3]) -> Vector3:
	if spawn_points.is_empty():
		push_warning("[EngagementManager] No spawn points — using origin")
		return Vector3.ZERO
	var pos: Vector3 = spawn_points[_next_spawn_index % spawn_points.size()]
	_next_spawn_index += 1
	return pos


## Create a [StandardMaterial3D] with the given color.
func _make_mech_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	return mat


# -- Win / Lose Wiring (private) ------------------------------------------

func _connect_win_condition(enemy: CombatTarget) -> void:
	if enemy != null and enemy.get_reactor() != null:
		enemy.get_reactor().reactor_breached.connect(_on_enemy_breached)
	else:
		push_warning("[EngagementManager] Enemy has no reactor — win condition disabled")


func _connect_lose_condition(player_carrier: CombatTarget) -> void:
	if player_carrier != null and player_carrier.get_reactor() != null:
		player_carrier.get_reactor().reactor_breached.connect(_on_carrier_breached)
	else:
		push_warning("[EngagementManager] Carrier has no reactor — lose condition disabled")


# -- Reactor Breach Handlers -----------------------------------------------

func _on_enemy_breached() -> void:
	if not _is_engaged:
		return
	print("[EngagementManager] *** VICTORY — enemy target destroyed! ***")
	_resolve_victory()


func _on_carrier_breached() -> void:
	if not _is_engaged:
		return
	print("[EngagementManager] *** DEFEAT — player carrier destroyed! ***")
	_resolve_defeat()


func _on_mech_breached(target: CombatTarget) -> void:
	if not _is_engaged:
		return

	var bp: MechBlueprint = _blueprint_for(target)
	var mech_name: String = bp.blueprint_name if bp != null else "Unknown"
	print("[EngagementManager] Mech destroyed: %s" % mech_name)
	mech_destroyed.emit(target, bp)

	# If it's the piloted mech, try switching to the next alive one.
	if target == _piloted_mech:
		_piloted_mech = null
		_piloted_blueprint = null
		if not _try_switch_pilot():
			print("[EngagementManager] No mechs remaining — defeat!")
			_resolve_defeat()


# -- Pilot Switching (private) --------------------------------------------

## Try to hand control to the next alive mech.
## Returns [code]true[/code] if a switch occurred, [code]false[/code] if
## no mechs remain.
func _try_switch_pilot() -> bool:
	var alive: Array[CombatTarget] = get_alive_mechs()
	if alive.is_empty():
		return false

	_piloted_mech = alive[0]
	_piloted_blueprint = _blueprint_for(_piloted_mech)

	# Repaint the new pilot green so it stands out.
	_recolor_mech(_piloted_mech, PILOT_COLOR)

	var pilot_name: String = _piloted_blueprint.blueprint_name \
		if _piloted_blueprint != null else "Unknown"
	print("[EngagementManager] Pilot switched to: %s" % pilot_name)
	pilot_switched.emit(_piloted_mech, _piloted_blueprint)
	return true


## Swap the material color on a mech target's [MeshInstance3D] child.
func _recolor_mech(target: CombatTarget, color: Color) -> void:
	for child: Node in target.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = _make_mech_material(color)
			break


# -- Resolution (private) -------------------------------------------------

func _resolve_victory() -> void:
	_is_engaged = false

	# Return surviving mechs to the hangar.
	var hangar: Hangar = _carrier.get_hangar() if _carrier != null else null
	var returned: int = 0
	for i: int in range(_deployed_targets.size()):
		var target: CombatTarget = _deployed_targets[i]
		if is_instance_valid(target) and not target._dead:
			var bp: MechBlueprint = _deployed_blueprints[i]
			if hangar != null and bp != null:
				hangar.store_mech(bp)
				returned += 1

	print("[EngagementManager] Victory — %d mech(s) returned to hangar" % returned)
	engagement_won.emit()

	# Brief pause so the player can bask in glory.
	await get_tree().create_timer(END_COMBAT_DELAY).timeout
	_cleanup()


func _resolve_defeat() -> void:
	_is_engaged = false

	# All deployed mechs are lost — nothing goes back to the hangar.
	print("[EngagementManager] Defeat — all deployed mechs lost")
	engagement_lost.emit()

	# Brief pause so the player can process the L.
	await get_tree().create_timer(END_COMBAT_DELAY).timeout
	_cleanup()


func _cleanup() -> void:
	_deployed_targets.clear()
	_deployed_blueprints.clear()
	_piloted_mech = null
	_piloted_blueprint = null
	_arena = null
	_next_spawn_index = 0

	if _deployment_manager != null:
		_deployment_manager.end_combat()

	print("[EngagementManager] Cleaned up — returning to overworld")


# -- Helpers (private) -----------------------------------------------------

## Look up the blueprint for a given [CombatTarget] by parallel-array index.
func _blueprint_for(target: CombatTarget) -> MechBlueprint:
	var idx: int = _deployed_targets.find(target)
	if idx >= 0 and idx < _deployed_blueprints.size():
		return _deployed_blueprints[idx]
	return null


# -- DeploymentManager Signal Handlers -------------------------------------

func _on_deployment_launched(
	_threat: ThreatEntity,
	deployed_mechs: Array[MechBlueprint],
	piloted_mech: MechBlueprint,
) -> void:
	# Stash until combat_started fires with the arena reference.
	_pending_deployed = deployed_mechs.duplicate()
	_pending_piloted = piloted_mech
	print("[EngagementManager] Received deployment — %d mechs, pilot: %s" % [
		deployed_mechs.size(),
		piloted_mech.blueprint_name if piloted_mech != null else "none",
	])


func _on_combat_started(arena: CombatArena) -> void:
	begin_engagement(arena, _pending_deployed, _pending_piloted)
	_pending_deployed.clear()
	_pending_piloted = null
