extends Area3D
class_name AoeProjectile
## Fire-and-forget AoE projectile that detonates on impact (or lifetime
## expiry), applying [StatusEffect]s to every character in the blast radius.
##
## Created at runtime by [AoeProjectileAbility] — not intended for manual
## instantiation.  On collision with any physics body (wall, terrain,
## character) it triggers [method _detonate], which scans all nodes in the
## [code]"characters"[/code] group within [member _explosion_radius], skips
## the firer and dead targets, then applies a fresh set of effects to each
## valid target's [ReactorCore].
##
## Exclusion rules (same as [AoeCasterAbility]):
##   • Skips the user who fired it (no self-hits).
##   • Skips dead targets ([code]_dead == true[/code]).
##   • Horizontal-only range check.
##
## [member _explode_on_expiry] controls whether lifetime expiry triggers
## detonation ([code]true[/code]) or silent removal ([code]false[/code]).
##
## Visual: emissive orange-red sphere in flight, brief translucent flash
## sphere on detonation.

## The character that fired this projectile.
var _user: Node = null

## Normalised travel direction.
var _direction: Vector3 = Vector3.FORWARD

## Travel speed (metres / second).
var _speed: float = 20.0

## Callable that returns a fresh [code]Array[/code] of [StatusEffect]
## instances — called once per target so each gets independent copies.
var _effect_factory: Callable

## Seconds until auto-destroy / auto-detonate.
var _lifetime: float = 4.0

## Horizontal blast radius in metres.
var _explosion_radius: float = 6.0

## If true, lifetime expiry triggers detonation; otherwise silently frees.
var _explode_on_expiry: bool = true

## Guard flag — true once detonation has been processed.
var _detonated: bool = false


## Configure before adding to the scene tree.
## Call this, then [code]add_child[/code], then set [code]global_position[/code].
func setup(
	user: Node,
	direction: Vector3,
	effect_factory: Callable,
	speed: float,
	lifetime: float,
	explosion_radius: float,
	explode_on_expiry: bool = true,
) -> void:
	_user = user
	_direction = direction.normalized()
	_effect_factory = effect_factory
	_speed = speed
	_lifetime = lifetime
	_explosion_radius = explosion_radius
	_explode_on_expiry = explode_on_expiry


func _ready() -> void:
	# Don't be detectable by others; detect bodies on default layer.
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false

	# -- Collision shape (small sphere) ------------------------------------
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	# -- Visual (emissive orange-red sphere, slightly larger than Projectile)
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	mesh_inst.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.35, 0.12)
	mat.emission_energy_multiplier = 5.0
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	# -- Lifetime timer ----------------------------------------------------
	var timer := Timer.new()
	timer.wait_time = _lifetime
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(_on_lifetime_expired)
	add_child(timer)

	# -- Hit detection -----------------------------------------------------
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += _direction * _speed * delta


func _on_body_entered(body: Node3D) -> void:
	if _detonated:
		return
	# Don't detonate on the user who fired it.
	if body == _user:
		return
	_detonate()


func _on_lifetime_expired() -> void:
	if _detonated:
		return
	if _explode_on_expiry:
		_detonate()
	else:
		queue_free()


## Scan for targets in the blast radius and apply fresh effects to each.
func _detonate() -> void:
	_detonated = true

	var tree := get_tree()
	if tree:
		var origin := global_position
		for node in tree.get_nodes_in_group("characters"):
			if node == _user:
				continue
			var body := node as Node3D
			if not body:
				continue
			if body.get("_dead"):
				continue

			# Horizontal range check (same as AoeCasterAbility).
			var offset := body.global_position - origin
			offset.y = 0.0
			if offset.length() > _explosion_radius:
				continue

			# Fetch target's reactor.
			var reactor: Node = body.get_reactor() if body.has_method("get_reactor") else null
			if not reactor:
				continue

			# Fresh effects per target — each instance is independent.
			var effects: Array = _effect_factory.call()
			for effect in effects:
				reactor.apply_effect(effect)

	_spawn_explosion_flash()
	queue_free()


## Spawn a brief translucent flash sphere at the detonation point.
## The flash is added as a sibling in the scene tree (not a child of this
## projectile) so it survives [method queue_free].
func _spawn_explosion_flash() -> void:
	var tree := get_tree()
	if not tree or not tree.current_scene:
		return

	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = _explosion_radius * 0.5
	sphere.height = _explosion_radius
	flash.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.1, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.15)
	mat.emission_energy_multiplier = 8.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	flash.material_override = mat

	tree.current_scene.add_child(flash)
	flash.global_position = global_position

	# Auto-free after a brief flash.
	var timer := Timer.new()
	timer.wait_time = 0.15
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(flash.queue_free)
	flash.add_child(timer)
