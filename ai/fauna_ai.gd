extends AIController
class_name FaunaAI
## Ultra-simple combat controller for [FaunaMob] entities.
##
## Fauna are aggressive and mindless — they rush the nearest enemy and
## punch on contact.  No abilities, no flee, no heat management.
##
## Priorities (evaluated top-down each tick):
##   1. ATTACK — within punch reach: alternating punches.
##   2. SEEK   — chase nearest enemy at full speed.
##   3. IDLE   — no targets: brief wander, then seek again.

# -- Constants -------------------------------------------------------------

## Wander radius when idling with no targets.
const WANDER_RADIUS: float = 6.0

## Arrival distance for wander point.
const ARRIVAL_THRESHOLD: float = 0.5

# -- State -----------------------------------------------------------------

enum State { IDLE, WALKING, SEEK, ATTACK }

var _state: State = State.IDLE
var _origin: Vector3 = Vector3.ZERO

## Alternating punch hand.
var _next_punch_left: bool = true

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

	# --- Find nearest enemy ---
	var enemy := _find_nearest_enemy()

	if enemy:
		var to_enemy: Vector3 = enemy.global_position - host.global_position
		to_enemy.y = 0.0
		var dist := to_enemy.length()
		var dir := to_enemy.normalized() if dist > 0.01 else Vector3.ZERO

		# --- Priority 1: ATTACK (within punch reach) ---
		if dist <= host.punch_reach:
			_state = State.ATTACK
			if not host._is_action_locked():
				if host.try_fire_punch(_next_punch_left):
					_next_punch_left = not _next_punch_left
			# Keep closing slightly.
			host._apply_movement(dir * 0.3, delta)
			return

		# --- Priority 2: SEEK (rush toward enemy) ---
		_state = State.SEEK
		host._apply_movement(dir, delta)
		return

	# --- Priority 3: IDLE / wander (no targets) ---
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
	_idle_timer = randf_range(0.5, 2.0)


func _enter_walking() -> void:
	_state = State.WALKING
	_target_point = _pick_wander_point()


func _pick_wander_point() -> Vector3:
	var angle := randf() * TAU
	var dist := randf_range(WANDER_RADIUS * 0.3, WANDER_RADIUS)
	return _origin + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
