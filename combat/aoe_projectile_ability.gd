extends "res://combat/projectile_ability.gd"
class_name AoeProjectileAbility
## Reusable base for abilities that fire an [AoeProjectile] — a projectile
## that detonates in an area on impact instead of hitting a single target.
##
## Subclasses only need to:
##   1. Override [method create_other_effects] to define the AoE payload.
##   2. (Optional) Tune [member explosion_radius], [member explode_on_expiry],
##      and the inherited [code]projectile_*[/code] knobs.
##
## Inherits aim direction, spawn position, and activation mode logic from
## [ProjectileAbility].  The only difference is that [method _fire_projectile]
## spawns an [AoeProjectile] instead of a single-target [Projectile].
##
## Effects returned by [method create_other_effects] are wrapped in a
## factory [Callable] so the [AoeProjectile] can create fresh, independent
## instances per target — the same pattern [AoeCasterAbility] uses.

## Horizontal blast radius (metres) passed to the spawned [AoeProjectile].
var explosion_radius: float = 6.0

## Whether lifetime expiry triggers detonation ([code]true[/code]) or
## silent removal ([code]false[/code]).
var explode_on_expiry: bool = true


## Spawn an [AoeProjectile] instead of a single-target [Projectile].
func _fire_projectile(user: Node) -> void:
	var tree := user.get_tree()
	if not tree:
		return

	var direction := _get_aim_direction(user)

	# Capture a factory callable so the AoeProjectile can create fresh
	# effect instances per target (same pattern as AoeCasterAbility).
	var factory := func() -> Array: return create_other_effects(user)

	var proj := AoeProjectile.new()
	proj.setup(
		user,
		direction,
		factory,
		projectile_speed,
		projectile_lifetime,
		explosion_radius,
		explode_on_expiry,
	)

	# Add to tree first so global_position is valid.
	tree.current_scene.add_child(proj)
	proj.global_position = _get_spawn_position(user, direction)
