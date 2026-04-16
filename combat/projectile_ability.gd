extends "res://combat/ability.gd"
class_name ProjectileAbility
## Reusable base for abilities that fire a [Projectile] carrying
## [StatusEffect]s to the first character it hits.
##
## Subclasses only need to:
##   1. Override [method create_other_effects] to define the payload.
##   2. (Optional) Tune the [code]projectile_*[/code] knobs.
##
## Self-effects ([method create_self_effects]) are handled normally by the
## parent [Ability] pipeline — they apply to the caster's own reactor.
##
## Supports all activation modes:
##   [b]INSTANT[/b]  — one shot per press (most common for projectiles).
##   [b]TOGGLE[/b]   — fires on activation; deactivation only removes
##                      self-effects (in-flight projectiles are fire-and-forget).
##   [b]HOLD[/b]     — fires when pressed; release removes self-effects.
##
## Aim direction is resolved with a three-tier priority:
##   1. Camera forward — pitch-aware [code]_camera_pivot[/code] (player).
##   2. Model forward  — yaw-derived [code]_character[/code] facing (AI/clones).
##   3. Node forward   — fallback [code]-basis.z[/code].
##
## Effects returned by [method create_other_effects] should set their
## [code]source[/code] to [code]user[/code] for attribution.

## Travel speed in metres per second.
var projectile_speed: float = 30.0

## Seconds before the projectile auto-destroys if it hits nothing.
var projectile_lifetime: float = 3.0

## Vertical offset from user origin (metres).  ~1.0 ≈ chest height.
var projectile_spawn_height: float = 1.0

## Horizontal forward offset to clear the user's collision shape.
var projectile_spawn_offset: float = 1.0


func activate(user: Node) -> void:
	# Snapshot activation state so we know whether super triggers an
	# activation (TOGGLE/HOLD) or a deactivation (TOGGLE second press).
	var was_active := _active
	super.activate(user)

	# Fire only when the ability transitions to active (or fires instantly).
	# TOGGLE second-press / HOLD release paths skip this.
	var just_activated := _active and not was_active
	if activation_mode == ActivationMode.INSTANT or just_activated:
		_fire_projectile(user)


# -- Internals -------------------------------------------------------------

## Spawn a [Projectile] and add it to the scene tree.
func _fire_projectile(user: Node) -> void:
	var tree := user.get_tree()
	if not tree:
		return

	var direction := _get_aim_direction(user)
	var effects := create_other_effects(user)

	var proj := Projectile.new()
	proj.setup(user, direction, effects, projectile_speed, projectile_lifetime)

	# Add to tree first so global_position is valid.
	tree.current_scene.add_child(proj)
	proj.global_position = _get_spawn_position(user, direction)


## Resolve aim direction — camera → model → node fallback.
func _get_aim_direction(user: Node) -> Vector3:
	# Player: camera forward (pitch-aware so you can aim up/down).
	var pivot = user.get("_camera_pivot")
	if pivot and is_instance_valid(pivot):
		return -pivot.global_transform.basis.z

	# AI / Clone: model forward (horizontal).
	var character = user.get("_character")
	if character and is_instance_valid(character):
		var yaw: float = character.rotation.y
		return Vector3(sin(yaw), 0.0, cos(yaw)).normalized()

	# Ultimate fallback.
	return -user.global_transform.basis.z


## Compute spawn position: chest height + horizontal forward offset.
## Uses only the horizontal component of [param direction] for the forward
## offset so aiming steeply up/down doesn't push the spawn underground.
func _get_spawn_position(user: Node, direction: Vector3) -> Vector3:
	var pos : Vector3 = user.global_position + Vector3.UP * projectile_spawn_height
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() > 0.001:
		pos += flat.normalized() * projectile_spawn_offset
	return pos
