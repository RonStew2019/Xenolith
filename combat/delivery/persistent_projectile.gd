extends Area3D
class_name PersistentProjectile
## Fire-and-forget projectile that anchors itself to terrain on impact,
## handing off to a [ResonancePillar] spawn at the impact position.
##
## Created at runtime by [code]ResonancePillarAbility[/code] (Phase 2.3) —
## not intended for manual instantiation. Unlike [Projectile] / [AoeProjectile],
## this projectile carries [b]no effect payload[/b]: the pillar spawn itself
## is the "payload". The caster is stored so it can be passed to the pillar
## as its attribution anchor.
##
## Collision semantics (differ from [Projectile] / [AoeProjectile]):
## [br]- Collides only with the default/terrain layer ([code]collision_mask = 1[/code]).
## [br]- Flies through bodies in the [code]"characters"[/code] group — they are
##   explicitly skipped in [method _on_body_entered] rather than anchoring on them.
## [br]- Other projectiles have [code]collision_layer = 0[/code] so they never
##   trigger [signal body_entered] here; no extra filtering required.
##
## Auto-destroys silently after [member _lifetime] seconds if nothing is hit
## (no pillar spawned on fizzle — matches the [Projectile] lifetime pattern).
## Single-anchor: a guard flag prevents double-spawn if two terrain bodies
## overlap the projectile in the same physics frame.

## The character that fired this projectile. Passed to the spawned pillar
## as its [code]caster[/code] (attribution anchor).
var _user: Node = null

## Normalised travel direction.
var _direction: Vector3 = Vector3.FORWARD

## Travel speed (metres / second).
var _speed: float = 25.0

## Seconds until silent auto-destroy (no pillar spawned on expiry).
var _lifetime: float = 4.0

## Guard flag — true once a valid terrain impact has been processed.
var _anchored: bool = false


## Configure before adding to the scene tree.
## Call this, then [code]add_child[/code], then set [code]global_position[/code].
## [br][b]Note:[/b] no effect payload — the pillar spawn is the payload.
func setup(
	user: Node,
	direction: Vector3,
	speed: float,
	lifetime: float,
) -> void:
	_user = user
	_direction = direction.normalized()
	_speed = speed
	_lifetime = lifetime


func _ready() -> void:
	# Don't be detectable by others; detect bodies on the default/terrain layer.
	# Characters live on a different layer and are additionally filtered by
	# group membership in _on_body_entered so the projectile flies through them.
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

	# -- Visual (emissive violet sphere — resonance theme) -----------------
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	mesh_inst.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.3, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.75, 0.35, 1.0)
	mat.emission_energy_multiplier = 4.0
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	# -- Lifetime timer (silent fizzle — no pillar on expiry) --------------
	var timer := Timer.new()
	timer.wait_time = _lifetime
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(queue_free)
	add_child(timer)

	# -- Hit detection -----------------------------------------------------
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += _direction * _speed * delta


## Handle a physics body entering our area.
## Characters are ignored (fly-through). Terrain bodies trigger pillar spawn.
func _on_body_entered(body: Node3D) -> void:
	# Single-anchor guard — prevent double-spawn on same-frame overlaps.
	if _anchored:
		return
	# Fly-through: characters are not valid anchor surfaces. Our collision_mask
	# should already exclude them, but this is a defensive check in case a
	# character body ever ends up on the default layer.
	if body.is_in_group("characters"):
		return
	# Defensive: never anchor on the firer (they shouldn't be on the terrain
	# layer anyway, but cheap to check).
	if body == _user:
		return

	_anchored = true
	_spawn_pillar_at(global_position)
	queue_free()


## Hand off to a [ResonancePillar] spawn at the impact position.
##
## [b]Phase 2.1 stub.[/b] The pillar is instantiated, its [code]caster[/code]
## field is populated, and it's added as a sibling into the current scene
## (not as a child of this projectile, which is about to [code]queue_free[/code]).
##
## [b]Phase 2.2[/b] will flesh out the pillar's [code]_ready[/code] to:
## [br]- Create its [code]ReactorCore[/code] child (weak reactor, max_heat=100,
##   max_integrity=1, break_on_breach_deletes_host=true)
## [br]- Add a collision shape (capsule ~0.5m × 2.5m)
## [br]- Add the emissive column visual
## [br]- Join the [code]"characters"[/code] group with [code]is_pillar = true[/code]
## [br]- Subscribe to the caster's Slot 1/2/3 ability signals
##
## This stub is safe to run against the current [ResonancePillar] skeleton:
## the skeleton's [code]_ready[/code] is the default, so instantiation won't
## error out even though the pillar is visually empty until 2.2 lands.
func _spawn_pillar_at(impact_position: Vector3) -> void:
	var tree := get_tree()
	if not tree or not tree.current_scene:
		return

	var pillar := ResonancePillar.new()
	pillar.caster = _user
	tree.current_scene.add_child(pillar)
	pillar.global_position = impact_position
