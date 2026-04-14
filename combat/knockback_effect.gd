extends StatusEffect
class_name KnockbackEffect
## Physically pushes the target character away from [member source] over
## multiple ticks with linear decay.
##
## Source-agnostic: the push direction is computed purely from [code]source
## .global_position[/code] → target [code]global_position[/code] at the
## moment the effect is applied.  Works identically whether the source is a
## player (melee punch), an AI clone, or a world object (resonance pillar).
##
## Stackable — multiple knockbacks from different sources compound.
## Each instance is self-contained and self-cleaning.

## Horizontal push speed on the first tick (m/s).  Decays linearly to
## zero over [member duration] ticks.
const DEFAULT_INITIAL_SPEED := 15.0

## Default number of ticks the push lasts.
const DEFAULT_DURATION := 3

## Default heat per tick (low — displacement is the primary effect).
const DEFAULT_HEAT := 10

## Upward component added to the push direction before re-normalizing.
## 0 = purely horizontal, 1 = ~45° launch.  Gives a satisfying arc
## without sending targets into orbit.
const DEFAULT_LAUNCH_Y := 0.4

## Cached push unit-vector (horizontal + upward, computed on apply).
var _push_direction: Vector3 = Vector3.ZERO

## Cached reference to the target [CharacterBody3D].
var _target: CharacterBody3D = null

## Initial push speed, stored so the decay curve can reference it.
var _initial_speed: float = DEFAULT_INITIAL_SPEED

## Total duration captured at apply time (needed for linear decay fraction).
var _total_duration: int = DEFAULT_DURATION

## Whether the initial upward launch has already been applied.
## The Y impulse is only added on the first tick to prevent vertical
## velocity from accumulating across the full knockback duration.
var _launched: bool = false


func _init(
	p_source: Node = null,
	p_initial_speed: float = DEFAULT_INITIAL_SPEED,
	p_duration: int = DEFAULT_DURATION,
	p_heat: float = DEFAULT_HEAT,
) -> void:
	# stackable = true, refreshable = false, show_dmg = true
	super._init("Knockback", p_heat, p_duration, p_source, true, false, true)
	_initial_speed = p_initial_speed
	_total_duration = p_duration


func on_apply(reactor: Node) -> void:
	# Cache the target CharacterBody3D (parent of the ReactorCore node).
	var parent := reactor.get_parent()
	if parent is CharacterBody3D:
		_target = parent
	else:
		_target = null

	# Lock the target's horizontal movement so input doesn't overwrite
	# our velocity impulses.  The counter is stackable-safe.
	if _target:
		_target.movement_lock_count += 1

	# Compute horizontal push direction: source → target.
	if _target and is_instance_valid(source):
		var diff : Vector3 = _target.global_position - source.global_position
		diff.y = 0.0
		if diff.length_squared() > 0.001:
			_push_direction = diff.normalized()
		else:
			# Source and target overlap — fall back to target's facing.
			_push_direction = -_target.global_transform.basis.z
			_push_direction.y = 0.0
			_push_direction = _push_direction.normalized()
		# Add upward launch component and re-normalize so total magnitude
		# stays controlled by _initial_speed.
		_push_direction.y = DEFAULT_LAUNCH_Y
		_push_direction = _push_direction.normalized()
	else:
		# No valid source or target — nothing to push against.
		_push_direction = Vector3.ZERO


func on_tick(_reactor: Node) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if _push_direction.is_zero_approx():
		return
	if _total_duration <= 0:
		return

	# Linear decay: full strength on the first tick, fading to near-zero.
	# `duration` has NOT been decremented yet when on_tick runs, so it
	# counts down from _total_duration → 1 across the effect's lifetime.
	var fraction: float = float(duration) / float(_total_duration)
	var impulse: Vector3 = _push_direction * _initial_speed * fraction
	if _launched:
		# After the first tick, strip the vertical component so gravity
		# handles the arc naturally.  Only horizontal push decays.
		impulse.y = 0.0
	else:
		_launched = true
	_target.velocity += impulse


func on_remove(_reactor: Node) -> void:
	# Dampen residual upward velocity so the target doesn't spike
	# vertically once the movement lock is released.  Only clamp
	# positive Y (still rising); negative Y (falling) is left alone
	# so we don't freeze the target mid-air.
	if _target and is_instance_valid(_target):
		if _target.velocity.y > 0.0:
			_target.velocity.y = 0.0

	# Release the movement lock before dropping our reference.
	if _target and is_instance_valid(_target):
		_target.movement_lock_count -= 1
	_target = null
	_push_direction = Vector3.ZERO
