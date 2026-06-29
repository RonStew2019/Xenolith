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
## [b]Defeat:[/b] player carrier's reactor is breached (including
## voluntary self-destruct).[br]
## [b]Draw:[/b] all fighters on both sides are destroyed while the
## carriers / hive remain standing — carrier shunts back, threat stays.[br]
## When all deployed mechs are destroyed the player enters spectator mode
## with a free-flying camera and may choose to scuttle the carrier.

# -- Signals ---------------------------------------------------------------

## The engagement ended in victory — enemy destroyed.
signal engagement_won()

## The engagement ended in defeat — carrier destroyed or all mechs lost.
signal engagement_lost()

## A deployed mech was destroyed in combat.
signal mech_destroyed(mech: MechBody, blueprint: MechBlueprint)

## The player's piloted mech was destroyed and control switched to another.
signal pilot_switched(new_pilot: MechBody, blueprint: MechBlueprint)

## A reserve mech was pulled from the hangar and deployed mid-combat.
signal reserve_deployed(mech: MechBody, blueprint: MechBlueprint)

## All player mechs have been destroyed — entering spectator mode.
signal all_mechs_lost()

## The engagement ended in a draw — all fighters on both sides destroyed.
signal engagement_draw()

## Emitted after victory or defeat resolution with a summary Dictionary.
signal engagement_resolved(result: Dictionary)

# -- Constants -------------------------------------------------------------

## Resource type used for deployment costs.
const FUEL_RESOURCE: StringName = &"fuel"

## Seconds to wait after victory/defeat before tearing down the arena.
const END_COMBAT_DELAY: float = 2.0

# -- State -----------------------------------------------------------------

## Whether an engagement is currently active.
var _is_engaged: bool = false

## The active combat arena.
var _arena: CombatArena = null

## Deployed [MechBody] entities in the arena (includes the piloted one).
var _deployed_targets: Array[MechBody] = []

## Parallel array — blueprint for each deployed target (same indices).
var _deployed_blueprints: Array[MechBlueprint] = []

## The [MechBody] the player is currently piloting.
var _piloted_mech: MechBody = null

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

## Reference to [ThreatManager] (auto-discovered sibling).
var _threat_manager: ThreatManager = null

## The [ThreatEntity] this engagement is fighting.
var _threat: ThreatEntity = null

## Running tally of fuel spent during this engagement.
var _fuel_spent: int = 0

## Count of mechs lost during this engagement.
var _mechs_lost: int = 0

## Total mechs deployed (initial + reserves).
var _total_deployed: int = 0

## Whether the player is spectating (all mechs lost, watching the battle).
var _spectating: bool = false

## The free-flying [SpectatorCamera] created when spectating.
var _spectator_camera: SpectatorCamera = null

## Spawned [FaunaMob] entities in the arena (tracked separately from mechs).
var _fauna_mobs: Array = []

## Count of fauna kills during this engagement.
var _fauna_kills: int = 0

## Enemy AI mechs deployed by enemy carriers (tracked separately).
var _enemy_mechs: Array[MechBody] = []

## Count of enemy mech kills during this engagement.
var _enemy_mech_kills: int = 0

## The in-combat HUD overlay (created on engagement start, freed on cleanup).
var _combat_hud: CombatHUD = null


# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	if get_parent() != null:
		_deployment_manager = get_parent().get_node_or_null(
			"DeploymentManager"
		) as DeploymentManager
		_carrier = get_parent().get_node_or_null("Carrier") as Carrier
		_threat_manager = get_parent().get_node_or_null(
			"ThreatManager"
		) as ThreatManager

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
	_total_deployed = deployed_mechs.size()
	_mechs_lost = 0

	# Pause threat spawning / movement while we're fighting.
	if _threat_manager != null:
		_threat_manager.set_process(false)
		print("[EngagementManager] ThreatManager paused")

	# -- Team assignment ---------------------------------------------------
	var enemy_t: CombatTarget = arena.get_enemy_target()
	if enemy_t:
		enemy_t.team = 1
	var carrier_t: CombatTarget = arena.get_player_carrier_target()
	if carrier_t:
		carrier_t.team = 0

	# -- Win / lose wiring -------------------------------------------------
	_connect_win_condition(enemy_t)
	_connect_lose_condition(carrier_t)

	# -- Spawn deployed mechs ----------------------------------------------
	# Rebuild spawn points for the actual team size so every mech gets a
	# unique position (avoids physics collisions from overlapping bodies).
	arena.build_spawn_points_for(deployed_mechs.size())
	var spawn_points: Array[Vector3] = arena.get_spawn_points()

	for bp: MechBlueprint in deployed_mechs:
		var is_pilot: bool = (bp == piloted_mech)
		var spawn_pos: Vector3 = _next_spawn_point(spawn_points)
		var target: MechBody = _create_mech_target(bp, spawn_pos, is_pilot)
		target.team = 0  # Player team.
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

	# -- Spawn threat-specific combatants ----------------------------------
	_fauna_mobs.clear()
	_fauna_kills = 0
	_enemy_mechs.clear()
	_enemy_mech_kills = 0
	var threat_type: StringName = _threat.get_threat_type() if _threat != null else &""
	if threat_type == &"fauna_hive":
		_spawn_fauna(arena)
	elif threat_type == &"enemy_carrier":
		_spawn_enemy_mechs(arena)

	# -- Combat HUD --------------------------------------------------------
	if _combat_hud != null:
		_combat_hud.queue_free()
	_combat_hud = CombatHUD.new()
	_combat_hud.name = "CombatHUD"
	add_child(_combat_hud)
	_combat_hud.setup(self, arena, _carrier)

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

	# Peek at the blueprint to determine fuel cost (before removing).
	var mechs: Array[MechBlueprint] = hangar.get_mechs()
	var bp: MechBlueprint = mechs[hangar_index]
	var fuel_cost: int = bp.chassis.deploy_fuel_cost if bp.chassis != null else 5

	# Fuel check.
	if not inventory.has_enough(FUEL_RESOURCE, fuel_cost):
		print("[EngagementManager] Not enough fuel for reserve (need %d)" % fuel_cost)
		return false

	# Pull mech, pay cost.
	bp = hangar.remove_mech(hangar_index)
	if bp == null:
		push_warning("[EngagementManager] Hangar.remove_mech returned null")
		return false
	inventory.remove_resource(FUEL_RESOURCE, fuel_cost)

	# Spawn into arena.
	var spawn_points: Array[Vector3] = _arena.get_spawn_points()
	var spawn_pos: Vector3 = _next_spawn_point(spawn_points)
	var target: MechBody = _create_mech_target(bp, spawn_pos, false)
	target.team = 0  # Player team.
	_arena.add_child(target)

	_deployed_targets.append(target)
	_deployed_blueprints.append(bp)
	target.get_reactor().reactor_breached.connect(
		_on_mech_breached.bind(target)
	)

	_fuel_spent += fuel_cost
	_total_deployed += 1

	print("[EngagementManager] Reserve deployed: %s (cost %d fuel)" % [
		bp.blueprint_name, fuel_cost,
	])
	reserve_deployed.emit(target, bp)
	return true


## Return the [MechBody] the player is currently piloting, or null.
func get_piloted_mech() -> MechBody:
	return _piloted_mech


## Return the [MechBlueprint] of the currently piloted mech, or null.
func get_piloted_blueprint() -> MechBlueprint:
	return _piloted_blueprint


## Return all deployed mechs that are still alive.
func get_alive_mechs() -> Array[MechBody]:
	var alive: Array[MechBody] = []
	for target: MechBody in _deployed_targets:
		if is_instance_valid(target) and not target._dead:
			alive.append(target)
	return alive


## Whether an engagement is currently running.
func is_engaged() -> bool:
	return _is_engaged


## Return the deployment fuel cost for the mech at [param hangar_index].
## Returns 0 if the index is invalid or carrier is unavailable.
func get_reserve_deploy_cost(hangar_index: int) -> int:
	if _carrier == null:
		return 0
	var hangar: Hangar = _carrier.get_hangar()
	var mechs: Array[MechBlueprint] = hangar.get_mechs()
	if hangar_index < 0 or hangar_index >= mechs.size():
		return 0
	var bp: MechBlueprint = mechs[hangar_index]
	return bp.chassis.deploy_fuel_cost if bp.chassis != null else 5


# -- Mech Construction (private) ------------------------------------------

## Build a [MechBody] for a deployed mech, configured from the blueprint's
## chassis stats (speed, reactor heat/integrity).
func _create_mech_target(
	bp: MechBlueprint, pos: Vector3, is_pilot: bool,
) -> MechBody:
	var mech := MechBody.new()
	mech.name = str(bp.blueprint_name)
	mech.init(bp, is_pilot)
	mech.position = pos
	return mech


## Cycle through spawn points, wrapping around if we exhaust them.
func _next_spawn_point(spawn_points: Array[Vector3]) -> Vector3:
	if spawn_points.is_empty():
		push_warning("[EngagementManager] No spawn points — using origin")
		return Vector3.ZERO
	var pos: Vector3 = spawn_points[_next_spawn_index % spawn_points.size()]
	_next_spawn_index += 1
	return pos


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


func _on_mech_breached(target: MechBody) -> void:
	if not _is_engaged:
		return

	var bp: MechBlueprint = _blueprint_for(target)
	var mech_name: String = bp.blueprint_name if bp != null else "Unknown"
	print("[EngagementManager] Mech destroyed: %s" % mech_name)
	_mechs_lost += 1
	mech_destroyed.emit(target, bp)

	# If it's the piloted mech, try switching to the next alive one.
	if target == _piloted_mech:
		_piloted_mech = null
		_piloted_blueprint = null
		if not _try_switch_pilot():
			# All player mechs dead — check if enemies are also all dead.
			if _check_draw():
				return  # Draw resolved — skip spectator mode.
			print("[EngagementManager] No mechs remaining — entering spectator mode")
			_enter_spectator_mode()


# -- Pilot Switching (private) --------------------------------------------

## Try to hand control to the next alive mech.
## Returns [code]true[/code] if a switch occurred, [code]false[/code] if
## no mechs remain.
func _try_switch_pilot() -> bool:
	var alive: Array[MechBody] = get_alive_mechs()
	if alive.is_empty():
		return false

	_piloted_mech = alive[0]
	_piloted_blueprint = _blueprint_for(_piloted_mech)

	# Promote the AI mech to player-piloted mode.
	_piloted_mech.enable_pilot_controls()

	var pilot_name: String = _piloted_blueprint.blueprint_name \
		if _piloted_blueprint != null else "Unknown"
	print("[EngagementManager] Pilot switched to: %s" % pilot_name)
	pilot_switched.emit(_piloted_mech, _piloted_blueprint)
	return true


# -- Fauna Spawning (private) ---------------------------------------------

## Spawn [FaunaMob] entities near the enemy hive for fauna_hive engagements.
## Fauna count scales with the hive's [member FaunaHive.swarm_strength].
func _spawn_fauna(arena: CombatArena) -> void:
	var ss: float = 1.0
	if _threat != null and _threat.get("swarm_strength") != null:
		ss = _threat.swarm_strength
	var fauna_count: int = clampi(int(ss * 4.0), 2, 8)
	var hp: float = ss * 40.0
	var fauna_speed: float = 7.0

	# Place fauna near the enemy (negative Z in arena).
	var enemy_pos: Vector3 = arena.get_enemy_target().position if arena.get_enemy_target() != null else Vector3(0.0, 0.0, -CombatArena.SPAWN_OFFSET_Z)

	for i: int in range(fauna_count):
		var fauna := FaunaMob.new()
		fauna.name = "Fauna_%d" % i
		fauna.init(&"Fauna Creature", hp, fauna_speed)

		# Spread fauna around the hive with some randomness.
		var angle: float = TAU * float(i) / float(fauna_count)
		var offset: float = randf_range(3.0, 6.0)
		var spawn_pos := Vector3(
			enemy_pos.x + cos(angle) * offset,
			0.0,
			enemy_pos.z + sin(angle) * offset,
		)
		fauna.position = spawn_pos

		arena.add_child(fauna)
		_fauna_mobs.append(fauna)

		# Wire up breach handler.
		fauna.get_reactor().reactor_breached.connect(
			_on_fauna_breached.bind(fauna)
		)

	print("[EngagementManager] Spawned %d fauna mobs (HP=%.0f each)" % [fauna_count, hp])


func _on_fauna_breached(fauna: FaunaMob) -> void:
	if not _is_engaged:
		return
	_fauna_kills += 1
	print("[EngagementManager] Fauna killed (%d total)" % _fauna_kills)
	_check_draw()


# -- Enemy Mech Spawning (private) ----------------------------------------

## Spawn AI-controlled enemy mechs from the carrier's archetype complement.
func _spawn_enemy_mechs(arena: CombatArena) -> void:
	var enemy_carrier: EnemyCarrier = _threat as EnemyCarrier
	if enemy_carrier == null or enemy_carrier.archetype == null:
		print("[EngagementManager] No archetype on enemy carrier — skipping mech spawn")
		return

	var complement: Array[Dictionary] = enemy_carrier.archetype.mech_complement
	if complement.is_empty():
		return

	var enemy_pos: Vector3 = arena.get_enemy_target().position \
		if arena.get_enemy_target() != null \
		else Vector3(0.0, 0.0, -CombatArena.SPAWN_OFFSET_Z)

	var mech_count: int = complement.size()
	for i: int in range(mech_count):
		var entry: Dictionary = complement[i]
		var chassis_id: StringName = entry.get("chassis", &"dogfighter")
		var preset: StringName = entry.get("weapon_preset", &"basic")
		var bp: MechBlueprint = _build_enemy_blueprint(chassis_id, preset, i)

		# Spread around the enemy carrier.
		var angle: float = TAU * float(i) / float(mech_count)
		var offset: float = randf_range(4.0, 8.0)
		var spawn_pos := Vector3(
			enemy_pos.x + cos(angle) * offset,
			0.0,
			enemy_pos.z + sin(angle) * offset,
		)

		var mech: MechBody = _create_mech_target(bp, spawn_pos, false)
		mech.team = 1  # Enemy team.
		arena.add_child(mech)
		_enemy_mechs.append(mech)

		mech.get_reactor().reactor_breached.connect(
			_on_enemy_mech_breached.bind(mech)
		)

		print("[EngagementManager] Enemy mech deployed: %s at (%.1f, %.1f)" % [
			bp.blueprint_name, spawn_pos.x, spawn_pos.z,
		])

	print("[EngagementManager] Spawned %d enemy mechs for %s" % [
		mech_count, enemy_carrier.archetype.display_name,
	])


## Build a [MechBlueprint] for an enemy AI mech based on chassis + preset.
func _build_enemy_blueprint(
	chassis_id: StringName, preset: StringName, index: int,
) -> MechBlueprint:
	if preset == &"basic":
		if chassis_id == &"bomber":
			var bp := ChassisPresets.basic_bomber_blueprint()
			bp.blueprint_name = &"Enemy Bomber %d" % index
			return bp
		else:
			var bp := ChassisPresets.basic_dogfighter_blueprint()
			bp.blueprint_name = &"Enemy Dogfighter %d" % index
			return bp

	# Status-effect preset — equip nasty weapons.
	if chassis_id == &"bomber":
		var bp := MechBlueprint.new()
		bp.blueprint_name = &"Enemy Bomber %d" % index
		bp.chassis = ChassisPresets.bomber_chassis()
		bp.weapon_assignments = {
			&"l_hand": &"thermal_fist",
			&"r_hand": &"thermal_fist",
			&"artillery": &"emp_mortar",
		}
		return bp
	else:
		var bp := MechBlueprint.new()
		bp.blueprint_name = &"Enemy Dogfighter %d" % index
		bp.chassis = ChassisPresets.dogfighter_chassis()
		bp.weapon_assignments = {
			&"l_hand": &"venom_fist",
			&"r_hand": &"venom_fist",
			&"l_shoulder": &"cryo_cannon",
			&"r_shoulder": &"cryo_cannon",
		}
		return bp


func _on_enemy_mech_breached(mech: MechBody) -> void:
	if not _is_engaged:
		return
	_enemy_mech_kills += 1
	print("[EngagementManager] Enemy mech destroyed (%d total)" % _enemy_mech_kills)
	_check_draw()


# -- Draw Detection (private) ----------------------------------------------

## Return [code]true[/code] if every enemy combatant (fauna mobs and enemy
## mechs — NOT the enemy target itself) is dead.
func _all_enemy_combatants_dead() -> bool:
	for mob in _fauna_mobs:
		if is_instance_valid(mob) and not mob._dead:
			return false
	for mech in _enemy_mechs:
		if is_instance_valid(mech) and not mech._dead:
			return false
	# If there were no combatants at all, don't treat it as "all dead".
	return not _fauna_mobs.is_empty() or not _enemy_mechs.is_empty()


## Check whether both sides have lost all fighters.  If so, resolves the
## engagement as a draw and returns [code]true[/code].
func _check_draw() -> bool:
	if not _is_engaged:
		return false
	if not get_alive_mechs().is_empty():
		return false
	if not _all_enemy_combatants_dead():
		return false
	# Both sides wiped — it's a draw.
	_resolve_draw()
	return true


# -- Spectator Mode (private) ----------------------------------------------

## Enter spectator mode when the last player mech is destroyed.
## Spawns a free-flying camera and emits [signal all_mechs_lost].
func _enter_spectator_mode() -> void:
	_spectating = true
	# Spawn the spectator camera on the next frame so the dying mech's
	# camera teardown (queue_free) has a chance to complete.
	call_deferred("_spawn_spectator_camera")
	all_mechs_lost.emit()


## Create a [SpectatorCamera] in the arena, positioned for a good overview.
func _spawn_spectator_camera() -> void:
	if _arena == null:
		return
	_spectator_camera = SpectatorCamera.new()
	_spectator_camera.name = "SpectatorCamera"
	# Position elevated, looking at the arena center (matches CombatCamera).
	_spectator_camera.position = Vector3(0.0, 35.0, 45.0)
	_spectator_camera.rotation_degrees = Vector3(-40.0, 0.0, 0.0)
	_spectator_camera.fov = 60.0
	_arena.add_child(_spectator_camera)


# -- Self-Destruct (public) ------------------------------------------------

## Force-breach the player carrier's reactor, triggering the normal
## [method _on_carrier_breached] → [method _resolve_defeat] flow.
## Intended for voluntary surrender when spectating.
func self_destruct_carrier() -> void:
	if not _is_engaged or _arena == null:
		return
	var carrier_target: CombatTarget = _arena.get_player_carrier_target()
	if carrier_target == null:
		return
	var reactor: Node = carrier_target.get_reactor()
	if reactor == null:
		return
	print("[EngagementManager] *** SELF-DESTRUCT — scuttling carrier! ***")
	# Setting integrity to 0 triggers the setter's reactor_breached signal,
	# which fires _on_carrier_breached() → _resolve_defeat().
	reactor.integrity = 0.0


# -- Resolution (private) -------------------------------------------------

func _resolve_draw() -> void:
	_is_engaged = false
	print("[EngagementManager] *** DRAW — all fighters destroyed on both sides ***")

	# Shunt the player carrier back to its previous hex — it was the
	# aggressor that moved onto the contested hex.
	if _carrier != null:
		_carrier.shunt_back()
		print("[EngagementManager] Carrier shunted back to %s" % str(_carrier.previous_hex))

	# Threat stays alive on its hex — player can try again later.

	var result: Dictionary = _build_result_draw()
	engagement_resolved.emit(result)
	engagement_draw.emit()

	# Brief pause so the player can read the notification.
	await get_tree().create_timer(END_COMBAT_DELAY).timeout
	_cleanup()


func _resolve_victory() -> void:
	_is_engaged = false

	# Return surviving mechs to the hangar.
	var hangar: Hangar = _carrier.get_hangar() if _carrier != null else null
	var returned: int = 0
	for i: int in range(_deployed_targets.size()):
		var target: MechBody = _deployed_targets[i]
		if is_instance_valid(target) and not target._dead:
			var bp: MechBlueprint = _deployed_blueprints[i]
			if hangar != null and bp != null:
				hangar.store_mech(bp)
				returned += 1

	# Remove the defeated threat from the overworld.
	if _threat != null and _threat_manager != null:
		_threat_manager.remove_threat(_threat)
		print("[EngagementManager] Threat '%s' removed from overworld" % _threat.entity_name)

	var result: Dictionary = _build_result(true, returned)
	print("[EngagementManager] Victory — %d mech(s) returned to hangar" % returned)
	engagement_resolved.emit(result)
	engagement_won.emit()

	# Brief pause so the player can bask in glory.
	await get_tree().create_timer(END_COMBAT_DELAY).timeout
	_cleanup()


func _resolve_defeat() -> void:
	_is_engaged = false

	# All deployed mechs are lost — nothing goes back to the hangar.
	var result: Dictionary = _build_result(false, 0)
	print("[EngagementManager] Defeat — all deployed mechs lost")
	engagement_resolved.emit(result)
	engagement_lost.emit()

	# Brief pause so the player can process the L.
	await get_tree().create_timer(END_COMBAT_DELAY).timeout
	_cleanup()


func _cleanup() -> void:
	if _combat_hud != null:
		_combat_hud.queue_free()
		_combat_hud = null

	if _spectator_camera != null:
		_spectator_camera.queue_free()
		_spectator_camera = null
	_spectating = false

	_deployed_targets.clear()
	_deployed_blueprints.clear()
	_fauna_mobs.clear()
	_fauna_kills = 0
	_enemy_mechs.clear()
	_enemy_mech_kills = 0
	_piloted_mech = null
	_piloted_blueprint = null
	_arena = null
	_next_spawn_index = 0

	# Resume threat spawning / movement now that combat is over.
	if _threat_manager != null:
		_threat_manager.set_process(true)
		print("[EngagementManager] ThreatManager resumed")

	_threat = null
	_fuel_spent = 0
	_mechs_lost = 0
	_total_deployed = 0

	if _deployment_manager != null:
		_deployment_manager.end_combat()

	print("[EngagementManager] Cleaned up — returning to overworld")


# -- Helpers (private) -----------------------------------------------------

## Build the post-engagement result summary.
func _build_result(victory: bool, mechs_returned: int) -> Dictionary:
	return {
		"victory": victory,
		"draw": false,
		"threat_name": _threat.entity_name if _threat != null else &"Unknown",
		"threat_type": _threat.get_threat_type() if _threat != null else &"",
		"fuel_spent": _fuel_spent,
		"mechs_deployed": _total_deployed,
		"mechs_lost": _mechs_lost,
		"mechs_survived": mechs_returned,
	}


## Build the post-engagement result summary for a draw.
func _build_result_draw() -> Dictionary:
	return {
		"victory": false,
		"draw": true,
		"threat_name": _threat.entity_name if _threat != null else &"Unknown",
		"threat_type": _threat.get_threat_type() if _threat != null else &"",
		"fuel_spent": _fuel_spent,
		"mechs_deployed": _total_deployed,
		"mechs_lost": _mechs_lost,
		"mechs_survived": 0,
	}


## Look up the blueprint for a given [MechBody] by parallel-array index.
func _blueprint_for(target: MechBody) -> MechBlueprint:
	var idx: int = _deployed_targets.find(target)
	if idx >= 0 and idx < _deployed_blueprints.size():
		return _deployed_blueprints[idx]
	return null


# -- DeploymentManager Signal Handlers -------------------------------------

func _on_deployment_launched(
	threat: ThreatEntity,
	deployed_mechs: Array[MechBlueprint],
	piloted_mech: MechBlueprint,
) -> void:
	# Stash until combat_started fires with the arena reference.
	_pending_deployed = deployed_mechs.duplicate()
	_pending_piloted = piloted_mech
	_threat = threat
	_fuel_spent = 0
	for mech: MechBlueprint in deployed_mechs:
		if mech.chassis != null:
			_fuel_spent += mech.chassis.deploy_fuel_cost
		else:
			_fuel_spent += 5
	print("[EngagementManager] Received deployment — %d mechs, pilot: %s" % [
		deployed_mechs.size(),
		piloted_mech.blueprint_name if piloted_mech != null else "none",
	])


func _on_combat_started(arena: CombatArena) -> void:
	begin_engagement(arena, _pending_deployed, _pending_piloted)
	_pending_deployed.clear()
	_pending_piloted = null
