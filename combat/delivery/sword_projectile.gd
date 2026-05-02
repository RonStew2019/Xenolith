extends Area3D
class_name SwordProjectile
## Fire-and-forget projectile that spawns a [CelestialSwordEntity] on
## terrain impact OR lifetime expiry.
##
## Created at runtime by [CelestialSwordAbility] — not intended for
## manual instantiation. Unlike [PersistentProjectile] (which silently
## fizzles on lifetime expiry), this projectile ALWAYS spawns a sword:
## either at the terrain impact point or at its current position when
## the lifetime timer runs out. This guarantees the sword is placed in
## the world every time the ability is used.
##
## Collision semantics (same as [PersistentProjectile]):
## [br]- Collides only with the default/terrain layer ([code]collision_mask = 1[/code]).
## [br]- Flies through bodies in the [code]"characters"[/code] group.
## [br]- Other projectiles have [code]collision_layer = 0[/code] so they
##   never trigger [signal body_entered] here.
##
## Single-spawn: a guard flag prevents double-spawn if terrain impact and
## lifetime expiry overlap in the same physics frame.

## The character that fired this projectile. Passed to the spawned sword
## as its [code]caster[/code] (attribution anchor).
var _user: Node = null

## Normalised travel direction.
var _direction: Vector3 = Vector3.FORWARD

## Travel speed (metres / second).
var _speed: float = 30.0

## Seconds until auto-spawn at current position (not a silent fizzle).
var _lifetime: float = 3.0

## Display name for the spawned sword entity (e.g. "Sword Alpha").
var _sword_name: String = ""

## Back-reference to the [CelestialSwordAbility] that fired this
## projectile. Passed through to the spawned [CelestialSwordEntity] so
## the ability can track its deployed sword.
var _owning_ability = null

## Factory callable that creates the per-sword entity.  Signature:
## [code]() -> CelestialSwordEntity[/code].  Falls back to the generic
## base entity when not set or not valid.
var _entity_factory: Callable = Callable()

## Guard flag — true once a sword has been spawned (terrain impact or
## lifetime expiry). Prevents double-spawn on same-frame overlaps.
var _spawned: bool = false


## Configure before adding to the scene tree.
## Call this, then [code]add_child[/code], then set [code]global_position[/code].
func setup(
	user: Node,
	direction: Vector3,
	speed: float,
	lifetime: float,
	sword_name: String,
	owning_ability,
	entity_factory: Callable = Callable(),
) -> void:
	_user = user
	_direction = direction.normalized()
	_speed = speed
	_lifetime = lifetime
	_sword_name = sword_name
	_owning_ability = owning_ability
	_entity_factory = entity_factory


func _ready() -> void:
	# Don't be detectable by others; detect bodies on the default/terrain layer.
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

	# -- Visual (emissive gold sphere — celestial sword theme) -------------
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	mesh_inst.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.3)
	mat.emission_energy_multiplier = 4.0
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	# -- Lifetime timer (spawns sword on expiry, NOT a silent fizzle) ------
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


## Handle a physics body entering our area.
## Characters are ignored (fly-through). Terrain bodies trigger sword spawn.
func _on_body_entered(body: Node3D) -> void:
	# Single-spawn guard — prevent double-spawn on same-frame overlaps.
	if _spawned:
		return
	# Fly-through: characters are not valid impact surfaces.
	if body.is_in_group("characters"):
		return
	# Defensive: never anchor on the firer.
	if body == _user:
		return

	_spawned = true
	_spawn_sword_at(global_position)
	queue_free()


## Handle lifetime expiry — spawn sword at current position.
## Unlike [PersistentProjectile], this is NOT a silent fizzle.
func _on_lifetime_expired() -> void:
	if _spawned:
		return

	_spawned = true
	_spawn_sword_at(global_position)
	queue_free()


## Spawn a [CelestialSwordEntity] at the given position, configured with
## the caster, sword name, and owning ability references from this
## projectile.
func _spawn_sword_at(spawn_position: Vector3) -> void:
	var tree := get_tree()
	if not tree or not tree.current_scene:
		return

	var sword: CelestialSwordEntity
	if _entity_factory.is_valid():
		sword = _entity_factory.call()
	else:
		sword = CelestialSwordEntity.new()
	sword.caster = _user
	sword.sword_name = _sword_name
	sword.owning_ability = _owning_ability
	tree.current_scene.add_child(sword)
	sword.global_position = spawn_position
