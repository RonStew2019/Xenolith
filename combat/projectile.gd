extends Area3D
class_name Projectile
## Fire-and-forget projectile that carries [StatusEffect]s to the first
## character it contacts.
##
## Created at runtime by [ProjectileAbility] — not intended for manual
## instantiation.  On collision with a valid target, applies all carried
## effects to that target's [ReactorCore] and then frees itself.
##
## Exclusion rules:
##   • Skips the user who fired it (no self-hits).
##   • Skips dead targets ([code]_dead == true[/code]).
##   • Only hits nodes in the [code]"characters"[/code] group.
##
## Auto-destroys after [member _lifetime] seconds if nothing is hit.
## Single-hit: a guard flag prevents double-application if two bodies
## overlap the projectile in the same physics frame.

## The character that fired this projectile.
var _user: Node = null

## Normalised travel direction.
var _direction: Vector3 = Vector3.FORWARD

## Travel speed (metres / second).
var _speed: float = 30.0

## Effects to deliver on hit.
var _effects: Array = []

## Seconds until auto-destroy.
var _lifetime: float = 3.0

## Guard flag — true once a valid hit has been processed.
var _hit: bool = false


## Configure before adding to the scene tree.
## Call this, then [code]add_child[/code], then set [code]global_position[/code].
func setup(
	user: Node,
	direction: Vector3,
	effects: Array,
	speed: float,
	lifetime: float,
) -> void:
	_user = user
	_direction = direction.normalized()
	_effects = effects
	_speed = speed
	_lifetime = lifetime


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

	# -- Visual (emissive sphere) ------------------------------------------
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	mesh_inst.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.18)
	mat.emission_energy_multiplier = 4.0
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	# -- Lifetime timer ----------------------------------------------------
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


func _on_body_entered(body: Node3D) -> void:
	# Single-hit guard — prevent double-application.
	if _hit:
		return
	# Skip the user who fired this.
	if body == _user:
		return
	# Must be in the characters group.
	if not body.is_in_group("characters"):
		return
	# Skip dead targets.
	if body.get("_dead"):
		return

	# Fetch target's reactor.
	var reactor: Node = body.get_reactor() if body.has_method("get_reactor") else null
	if not reactor:
		return

	# Mark as hit, apply effects, destroy.
	_hit = true
	for effect in _effects:
		reactor.apply_effect(effect)
	queue_free()
