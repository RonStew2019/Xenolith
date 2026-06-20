extends AIController
class_name BomberAI
## Priority-based combat controller for Bomber-chassis [MechBody] units.
##
## Bombers are slow, ranged combatants that maintain distance and fire
## artillery mortars from optimal range.  They backpedal when enemies
## close in and only punch as a last resort.
##
## Priorities (evaluated top-down each tick):
##   1. FLEE      — reactor heat >= 80%: stop firing, move away.
##   2. BACKPEDAL — enemy within 8m: retreat to gain distance.
##   3. FIRE      — enemy between 15-40m: face and fire artillery.
##   4. APPROACH  — enemy beyond 40m: move closer into range.
##   5. PUNCH     — cornered within punch reach: throw punches.
##   6. IDLE      — no targets: wander around spawn origin.

# -- Constants -------------------------------------------------------------

## If an enemy is closer than this, backpedal away.
const BACKPEDAL_RANGE: float = 8.0

## Optimal artillery range — minimum.
const OPTIMAL_MIN: float = 15.0

## Optimal artillery range — maximum.
const OPTIMAL_MAX: float = 40.0

## Minimum seconds between artillery shots.
const FIRE_COOLDOWN: float = 2.0

## Heat ratio threshold for flee behavior.
const FLEE_HEAT_RATIO: float = 0.80

## Wander radius when idling with no targets.
const WANDER_RADIUS: float = 8.0

## Arrival distance for wander point.
const ARRIVAL_THRESHOLD: float = 0.5

# -- State -----------------------------------------------------------------

enum State { IDLE, WALKING, SEEK, FIRE, BACKPEDAL, FLEE, PUNCH }

var _state: State = State.IDLE
var _origin: Vector3 = Vector3.ZERO

## Alternating punch hand (last resort).
var _next_punch_left: bool = true

## Cooldown timer between artillery shots.
var _fire_cd: float = 0.0

## Wander sub-state.
var _idle_timer: float = 0.0
var _target_point: Vector3 = Vector3.ZERO


# ── Lifecycle ────────────────────────────────────────────────────────────

func on_enter() -> void:
	_origin = host.global_position
	_enter_idle()


func tick(delta: float) -> void:
	if host._dead:
		return

	# Tick fire cooldown.
	if _fire_cd > 0.0:
		_fire_cd -= delta

	var reactor: Node = host._reactor

	# --- Priority 1: FLEE (heat dangerously high) ---
	if reactor and reactor.max_heat > 0.0:
		var heat_ratio: float = reactor.heat / reactor.max_heat
		if heat_ratio >= FLEE_HEAT_RATIO:
			_state = State.FLEE
			var enemy := _find_nearest_enemy()
			if enemy:
				var away: Vector3 = (host.global_position - enemy.global_position)
				away.y = 0.0
				if away.length() > 0.01:
					host._apply_movement(away.normalized(), delta)
				else:
					host._apply_movement(Vector3.BACK, delta)
			else:
				host._apply_movement(Vector3.ZERO, delta)
			return

	# --- Find nearest enemy ---
	var enemy := _find_nearest_enemy()

	if enemy:
		var to_enemy: Vector3 = enemy.global_position - host.global_position
		to_enemy.y = 0.0
		var dist := to_enemy.length()
		var dir := to_enemy.normalized() if dist > 0.01 else Vector3.ZERO

		# --- Priority 2: BACKPEDAL (enemy too close, but not in punch range) ---
		if dist < BACKPEDAL_RANGE and dist > host.punch_reach:
			_state = State.BACKPEDAL
			# Move away from the enemy.
			host._apply_movement(-dir, delta)
			return

		# --- Priority 3: FIRE (enemy in optimal range) ---
		if dist >= OPTIMAL_MIN and dist <= OPTIMAL_MAX:
			_state = State.FIRE
			# Face the enemy but hold position.
			host._apply_movement(dir * 0.05, delta)
			# Fire when cooldown is ready.
			if _fire_cd <= 0.0:
				host._activate_ability("ability_1")
				_fire_cd = FIRE_COOLDOWN
			return

		# --- Priority 4: APPROACH (enemy too far) ---
		if dist > OPTIMAL_MAX:
			_state = State.SEEK
			host._apply_movement(dir, delta)
			return

		# --- Priority 5: PUNCH (cornered within reach) ---
		if dist <= host.punch_reach:
			_state = State.PUNCH
			if not host._is_action_locked():
				if host.try_fire_punch(_next_punch_left):
					_next_punch_left = not _next_punch_left
			# Try to back away even while punching.
			host._apply_movement(-dir * 0.5, delta)
			return

		# Between punch reach and BACKPEDAL_RANGE — keep backing up.
		_state = State.BACKPEDAL
		host._apply_movement(-dir, delta)
		return

	# --- Priority 6: IDLE / wander (no targets) ---
	match _state:
		State.IDLE:
			_idle_timer -= delta
			if _idle_timer <= 0.0:
				_enter_walking()
			host._apply_movement(Vector3.ZERO, delta)
		State.WALKING:
			var to_target := _target_point - host.global_position
			to_target.y = 0.0
			if to_target.length() < ARRIVAL_THRESHOLD:
				_enter_idle()
				host._apply_movement(Vector3.ZERO, delta)
			else:
				host._apply_movement(to_target.normalized(), delta)
		_:
			# Was in combat but lost target — go idle.
			_enter_idle()
			host._apply_movement(Vector3.ZERO, delta)


# ── Helpers ──────────────────────────────────────────────────────────────

func _find_nearest_enemy() -> Node:
	var best: Node = null
	var best_dist := INF
	for node in host.get_tree().get_nodes_in_group("characters"):
		if node == host:
			continue
		if node.get("_dead"):
			continue
		if node.get("team") == host.team:
			continue
		var dist := host.global_position.distance_to(node.global_position)
		if dist < best_dist:
			best = node
			best_dist = dist
	return best


# ── Wander fallback ──────────────────────────────────────────────────────

func _enter_idle() -> void:
	_state = State.IDLE
	_idle_timer = randf_range(1.0, 4.0)


func _enter_walking() -> void:
	_state = State.WALKING
	_target_point = _pick_wander_point()


func _pick_wander_point() -> Vector3:
	var angle := randf() * TAU
	var dist := randf_range(WANDER_RADIUS * 0.3, WANDER_RADIUS)
	return _origin + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
