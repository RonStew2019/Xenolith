extends AIController
class_name CombatAI
## Priority-based combat controller extracted from [CloneMech].
##
## Priorities (evaluated top-down each tick):
##   1. FLEE    — reactor heat >= [constant FLEE_HEAT_RATIO]: tunnel away
##                and engage Coil to cool down.
##   2. CLONE   — off-cooldown and reactor big enough: spawn a sub-clone.
##   3. ATTACK  — within [code]host.punch_reach[/code]: alternating hooks
##                via [method CharacterBase.try_fire_punch].
##   4. ENGAGE  — within [constant ENGAGE_RANGE]: activate ability_1 (Envenom).
##   5. SEEK    — chase the nearest non-family enemy; disengage Envenom
##                beyond [constant DISENGAGE_RANGE].
##   6. IDLE    — no targets: fall back to wander-within-radius around
##                the host's spawn position.
##
## Hosts without a [Loadout] (e.g. plain NPCs) cleanly skip every
## ability-activation branch — the controller still seeks, attempts to
## punch (no-op without a punch anim tree), and falls back to wandering.
##
## Family filtering: clones ignore every character sharing the same
## [code]clone_parent[/code] root ancestor.

## -- Tunables ------------------------------------------------------------

@export var wander_radius: float = 8.0
@export var idle_time_min: float = 1.0
@export var idle_time_max: float = 4.0
@export var arrival_threshold: float = 0.5

const TUNNEL_COOLDOWN_SECS: float = 10.0
const CLONE_COOLDOWN_SECS: float = 15.0
const ENGAGE_RANGE: float = 5.0
const DISENGAGE_RANGE: float = 15.0
const FLEE_HEAT_RATIO: float = 0.80

## -- State ---------------------------------------------------------------

enum State { IDLE, WALKING, SEEK, ENGAGE, ATTACK, FLEE, CLONE }

var _state: State = State.IDLE
var _idle_timer: float = 0.0
var _target_point: Vector3 = Vector3.ZERO
var _origin: Vector3 = Vector3.ZERO

var _next_punch_left: bool = true
var _tunnel_cooldown: float = 0.0
var _clone_cooldown: float = 0.0


# ── Lifecycle ────────────────────────────────────────────────────────────

func on_enter() -> void:
	_origin = host.global_position
	_enter_idle()


func tick(delta: float) -> void:
	# Tick cooldowns.
	if _tunnel_cooldown > 0.0:
		_tunnel_cooldown -= delta
	if _clone_cooldown > 0.0:
		_clone_cooldown -= delta

	var reactor: Node = host._reactor

	# --- Priority 1: FLEE (heat dangerously high) ---
	if reactor and reactor.max_heat > 0.0:
		var heat_ratio: float = reactor.heat / reactor.max_heat
		if heat_ratio >= FLEE_HEAT_RATIO and _tunnel_cooldown <= 0.0:
			var tunnel_ability := _get_ability("ability_2")
			if tunnel_ability and not tunnel_ability.is_active():
				host._activate_ability("ability_2")
				_tunnel_cooldown = TUNNEL_COOLDOWN_SECS
				# Engage Coil to cool down after fleeing.
				var coil := _get_ability("ability_3")
				if coil and not coil.is_active():
					host._activate_ability("ability_3")
				host._apply_movement(Vector3.ZERO, delta)
				return

	# --- Find nearest enemy ---
	var enemy := _find_nearest_enemy()

	if enemy:
		var to_enemy: Vector3 = enemy.global_position - host.global_position
		to_enemy.y = 0.0
		var dist := to_enemy.length()
		var dir := to_enemy.normalized() if dist > 0.01 else Vector3.ZERO

		# --- Priority 2: CLONE (reactor has enough capacity) ---
		if _clone_cooldown <= 0.0 and reactor and reactor.max_heat > 100.0:
			var clone_ability := _get_ability("ability_4")
			if clone_ability and not clone_ability.is_active():
				host._activate_ability("ability_4")
				_clone_cooldown = CLONE_COOLDOWN_SECS

		# --- Priority 3: ATTACK (within punch reach) ---
		if dist <= host.punch_reach:
			_state = State.ATTACK
			# Disengage Coil so we fight at full speed.
			var coil := _get_ability("ability_3")
			if coil and coil.is_active():
				host._activate_ability("ability_3")
			# try_fire_punch returns false on hosts with no swing anim
			# (plain NPCs); only flip alternation on a real swing.
			if not host._is_action_locked():
				if host.try_fire_punch(_next_punch_left):
					_next_punch_left = not _next_punch_left
			# Keep closing in slightly so we don't drift out of range.
			host._apply_movement(dir * 0.3, delta)
			return

		# --- Priority 4: ENGAGE (within 5m, activate ability_1) ---
		if dist <= ENGAGE_RANGE:
			_state = State.ENGAGE
			# Disengage Coil so we fight at full speed.
			var coil := _get_ability("ability_3")
			if coil and coil.is_active():
				host._activate_ability("ability_3")
			var envenom := _get_ability("ability_1")
			if envenom and not envenom.is_active():
				host._activate_ability("ability_1")
			host._apply_movement(dir, delta)
			return

		# --- Priority 5: SEEK (chase the target) ---
		_state = State.SEEK
		# Disengage Envenom if we've drifted far from the target.
		if dist >= DISENGAGE_RANGE:
			var envenom := _get_ability("ability_1")
			if envenom and envenom.is_active():
				host._activate_ability("ability_1")
		host._apply_movement(dir, delta)
		return

	# --- Priority 6: IDLE / wander (no targets) ---
	# Disengage Envenom if it's still active with no target.
	var envenom := _get_ability("ability_1")
	if envenom and envenom.is_active():
		host._activate_ability("ability_1")
	match _state:
		State.IDLE:
			_idle_timer -= delta
			if _idle_timer <= 0.0:
				_enter_walking()
			host._apply_movement(Vector3.ZERO, delta)
		State.WALKING:
			var to_target := _target_point - host.global_position
			to_target.y = 0.0
			if to_target.length() < arrival_threshold:
				_enter_idle()
				host._apply_movement(Vector3.ZERO, delta)
			else:
				host._apply_movement(to_target.normalized(), delta)
		_:
			# Was in combat but lost target — go idle.
			_enter_idle()
			host._apply_movement(Vector3.ZERO, delta)


# ── Helpers ──────────────────────────────────────────────────────────────

## Loadout-safe ability lookup. Returns null when the host has no loadout
## (plain NPCs) so callers can naturally skip ability branches.
func _get_ability(action: String) -> Ability:
	if host._loadout == null:
		return null
	return host._loadout.get_ability_for_action(action)


# ── Wander fallback ──────────────────────────────────────────────────────

func _enter_idle() -> void:
	_state = State.IDLE
	_idle_timer = randf_range(idle_time_min, idle_time_max)


func _enter_walking() -> void:
	_state = State.WALKING
	_target_point = _pick_wander_point()


func _pick_wander_point() -> Vector3:
	var angle := randf() * TAU
	var dist := randf_range(wander_radius * 0.3, wander_radius)
	return _origin + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


# ── Family / enemy queries ──────────────────────────────────────────────

## Walk up the [code]clone_parent[/code] chain to find the root ancestor.
func _get_family_root(node: Node) -> Node:
	var root := node
	while root.get("clone_parent") and is_instance_valid(root.clone_parent):
		root = root.clone_parent
	return root


## Returns true if [param other] shares the host's family tree.
func _is_family(other: Node) -> bool:
	var my_root := _get_family_root(host)
	var other_root := _get_family_root(other)
	return my_root == other_root


## Scan the "characters" group for the closest non-family, non-dead enemy.
func _find_nearest_enemy() -> Node:
	var best: Node = null
	var best_dist := INF
	for node in host.get_tree().get_nodes_in_group("characters"):
		if node == host or _is_family(node):
			continue
		if node.get("_dead"):
			continue
		var dist := host.global_position.distance_to(node.global_position)
		if dist < best_dist:
			best = node
			best_dist = dist
	return best
