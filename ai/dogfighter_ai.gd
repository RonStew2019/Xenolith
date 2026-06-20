extends AIController
class_name DogfighterAI
## Priority-based combat controller for Dogfighter-chassis [MechBody] units.
##
## Dogfighters are nimble close-range brawlers that close the gap quickly,
## fire scatter blasters on approach, and strafe while punching in melee.
##
## Priorities (evaluated top-down each tick):
##   1. FLEE    — reactor heat >= 85%: disengage and cool down.
##   2. ATTACK  — within punch reach: alternating hooks + strafing.
##   3. ENGAGE  — within 15m: fire scatter blasters, keep closing.
##   4. SEEK    — chase nearest enemy.
##   5. IDLE    — no targets: wander around spawn origin.

# -- Constants -------------------------------------------------------------

## Range at which scatter blasters are activated and we start closing in.
const ENGAGE_RANGE: float = 15.0

## Heat ratio threshold for flee behavior.
const FLEE_HEAT_RATIO: float = 0.85

## Seconds between flipping strafe direction in ATTACK state.
const STRAFE_SWITCH_TIME: float = 1.5

## Wander radius when idling with no targets.
const WANDER_RADIUS: float = 8.0

## Arrival distance for wander point.
const ARRIVAL_THRESHOLD: float = 0.5

# -- State -----------------------------------------------------------------

enum State { IDLE, WALKING, SEEK, ENGAGE, ATTACK, FLEE }

var _state: State = State.IDLE
var _origin: Vector3 = Vector3.ZERO

## Alternating punch hand.
var _next_punch_left: bool = true

## Strafe direction: +1 = right, -1 = left.
var _strafe_dir: float = 1.0

## Timer tracking strafe flips.
var _strafe_timer: float = 0.0

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

		# --- Priority 2: ATTACK (within punch reach) ---
		if dist <= host.punch_reach:
			_state = State.ATTACK
			# Strafe perpendicular to enemy direction.
			_strafe_timer += delta
			if _strafe_timer >= STRAFE_SWITCH_TIME:
				_strafe_timer = 0.0
				_strafe_dir = -_strafe_dir

			var strafe := dir.cross(Vector3.UP) * _strafe_dir
			# Mix a bit of closing direction so we don't drift out of range.
			var move_dir := (strafe * 0.7 + dir * 0.3).normalized()
			host._apply_movement(move_dir, delta)

			if not host._is_action_locked():
				if host.try_fire_punch(_next_punch_left):
					_next_punch_left = not _next_punch_left
			return

		# --- Priority 3: ENGAGE (within scatter blaster range) ---
		if dist <= ENGAGE_RANGE:
			_state = State.ENGAGE
			# Fire scatter blasters while closing.
			host._activate_ability("ability_1")
			host._activate_ability("ability_2")
			host._apply_movement(dir, delta)
			return

		# --- Priority 4: SEEK (chase the target) ---
		_state = State.SEEK
		# Deactivate blasters when out of range.
		host._deactivate_ability("ability_1")
		host._deactivate_ability("ability_2")
		host._apply_movement(dir, delta)
		return

	# --- Priority 5: IDLE / wander (no targets) ---
	host._deactivate_ability("ability_1")
	host._deactivate_ability("ability_2")
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
