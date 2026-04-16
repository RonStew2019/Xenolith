extends AIController
class_name WanderAI
## Simple wander-within-radius controller. Alternates between idling
## for a random interval and skating to a random point around the
## position the host occupied when [method on_enter] fired.
##
## Extracted verbatim from the original [code]npc.gd[/code] so NPC
## behaviour is identical after the refactor.

enum State { IDLE, WALKING }

@export var wander_radius: float = 8.0
@export var idle_time_min: float = 1.0
@export var idle_time_max: float = 4.0
@export var arrival_threshold: float = 0.5

var _state: State = State.IDLE
var _idle_timer: float = 0.0
var _target_point: Vector3 = Vector3.ZERO
var _origin: Vector3 = Vector3.ZERO


func on_enter() -> void:
	_origin = host.global_position
	_enter_idle()


func tick(delta: float) -> void:
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
