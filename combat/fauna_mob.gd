extends CharacterBase
class_name FaunaMob
## Simple fauna creature spawned in combat arenas by [EngagementManager].
##
## Much simpler than [MechBody] — no blueprint, no loadout, no weapons.
## Uses a procedural mesh (purple-ish squashed sphere) instead of the
## glTF character model.  Punches in melee as its only attack.
##
## Always on the enemy team ([code]team = 1[/code]).  Controlled by
## [FaunaAI] which rushes the nearest enemy and punches on contact.

# -- Constants -------------------------------------------------------------

## Dark purple — organic, alien, matching the hive.
const FAUNA_COLOR: Color = Color(0.5, 0.12, 0.45)

## Lighter belly shade for a bit of visual interest.
const FAUNA_BELLY_COLOR: Color = Color(0.65, 0.2, 0.55)

# -- State -----------------------------------------------------------------

## Human-readable name for UI / debug.
var display_name: StringName = &""

## Active AI controller.
var _active_controller: AIController

## HP value — set in [method init], consumed by [method _setup_reactor].
var _fauna_hp: float = 40.0


# ── Initialisation ────────────────────────────────────────────────────────

## Configure this fauna mob's stats.  Call BEFORE [method add_child]
## so [method _ready] has valid data.
##
## [param display_name_] — name shown in debug / UI.[br]
## [param hp] — max integrity (also used as max heat).[br]
## [param speed_] — movement speed.
func init(display_name_: StringName, hp: float, speed_: float) -> void:
	display_name = display_name_
	_fauna_hp = hp
	speed = speed_
	# Fauna are small and light — shorter reach, weaker punches.
	punch_reach = 1.5
	punch_weight = 20.0
	punch_apex_delay = 0.0  # No swing animation — instant hit.
	team = 1  # Enemy team.


# ── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	super._ready()  # CharacterBase: model, anim tree, reactor glow, group
	_create_collision_shape()
	_setup_reactor()
	set_controller(FaunaAI.new())


func _physics_process(delta: float) -> void:
	if _active_controller:
		_active_controller.tick(delta)
	else:
		_apply_movement(Vector3.ZERO, delta)


# ── Character Setup (override — no glTF model) ───────────────────────────

## Build a simple procedural mesh instead of loading the character glTF.
## Fauna are small squashed spheres — no skeleton, no animation tree.
func _setup_character() -> void:
	_character = Node3D.new()
	_character.name = "FaunaModel"
	add_child(_character)

	# Main body — squashed sphere.
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.5
	mesh_inst.mesh = sphere
	mesh_inst.scale = Vector3(1.0, 0.7, 1.0)
	mesh_inst.position.y = 0.25

	var mat := StandardMaterial3D.new()
	mat.albedo_color = FAUNA_COLOR
	mat.roughness = 0.8
	mesh_inst.material_override = mat
	_character.add_child(mesh_inst)


## Override — skip reactor glow (no glTF mesh surfaces to glow).
func _setup_reactor_glow() -> void:
	pass


# ── Collision ────────────────────────────────────────────────────────────

func _create_collision_shape() -> void:
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 0.6
	col.shape = capsule
	col.transform.origin = Vector3(0, 0.3, 0)
	add_child(col)


# ── Reactor ──────────────────────────────────────────────────────────────

func _setup_reactor() -> void:
	_reactor = ReactorCore.new()
	_reactor.name = "ReactorCore"
	_reactor.max_integrity = _fauna_hp
	_reactor.max_heat = _fauna_hp
	add_child(_reactor)
	_reactor.reactor_breached.connect(die)


# ── AI Controller ────────────────────────────────────────────────────────

## Hot-swap controller (same pattern as [CloneMech.set_controller]).
func set_controller(new_controller: AIController) -> void:
	if _active_controller:
		_active_controller.on_exit()
		_active_controller.queue_free()
		_active_controller = null
	if new_controller:
		_active_controller = new_controller
		new_controller.host = self
		add_child(new_controller)
		new_controller.on_enter()


# ── Punch (no animation tree) ───────────────────────────────────────────

## Fauna always punch immediately — no animation lock.
func _is_action_locked() -> bool:
	return false


## Override — fire a punch without needing an animation tree.
## Returns true so AI can advance alternation state.
func try_fire_punch(_left: bool) -> bool:
	_schedule_punch_hit()
	return true


# ── Death ────────────────────────────────────────────────────────────────

## Simple death — no skeleton to explode, just clean up.
func _explode_character() -> void:
	if _character:
		_character.queue_free()
		_character = null
	_anim_tree = null


func _on_died() -> void:
	if _active_controller:
		_active_controller.on_exit()
		_active_controller.queue_free()
		_active_controller = null
