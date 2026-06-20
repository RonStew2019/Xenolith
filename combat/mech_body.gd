extends CharacterBase
class_name MechBody
## Runtime mech entity spawned into combat arenas.
##
## Configured from a [MechBlueprint] whose [MechChassis] drives speed,
## reactor heat cap, and reactor integrity.  Both Dogfighter and Bomber
## chassis produce a MechBody — stats are what differentiate them, not
## separate classes.
##
## Supports two modes:
##   • [b]Pilot[/b] — full player control: camera, mouse look, WASD
##     movement, jump, punch input (LMB/RMB), and ReactorHUD.
##   • [b]AI[/b] — idle with gravity.  An [AIController] can be attached
##     later for autonomous combat behavior.
##
## The procedural character model ([code]character.gltf[/code]) is loaded
## by [CharacterBase._setup_character].  All chassis types share the same
## model for now; per-chassis visuals arrive in a later phase.
##
## [b]Lifecycle:[/b] Call [method init] BEFORE adding this node to the
## scene tree so [method _ready] can read the blueprint and configure the
## reactor with the correct chassis stats.

# -- Exports ---------------------------------------------------------------

@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002
@export var pitch_min_deg: float = -60.0
@export var pitch_max_deg: float = 40.0

# -- State -----------------------------------------------------------------

## The blueprint this mech was fabricated from.
var blueprint: MechBlueprint

## Human-readable name for UI / debug (mirrors blueprint_name).
var display_name: StringName = &""

## Whether this mech is currently piloted by the player.
var is_pilot: bool = false

## Camera pivot for third-person view (only when piloted).
var _camera_pivot: Node3D

## HUD canvas layer (only when piloted).
var _hud_layer: CanvasLayer

## Slot → input-action mapping per chassis type.
## Hand slots are passive (on_equip only), so intentionally omitted.
const DOGFIGHTER_SLOT_INPUTS: Dictionary = {
	&"l_shoulder": "ability_1",
	&"r_shoulder": "ability_2",
}
const BOMBER_SLOT_INPUTS: Dictionary = {
	&"artillery": "ability_1",
}

## Maps keycodes to loadout action strings for ability dispatch.
var _ability_keys: Dictionary = {
	KEY_1: "ability_1",
	KEY_2: "ability_2",
}


# -- Initialisation --------------------------------------------------------

## Configure this mech from a blueprint.  Call BEFORE [method add_child]
## so [method _ready] has valid data.
##
## [param bp] — the [MechBlueprint] this mech is built from.[br]
## [param pilot] — [code]true[/code] if the player will pilot this mech.
func init(bp: MechBlueprint, pilot: bool) -> void:
	blueprint = bp
	is_pilot = pilot
	display_name = bp.blueprint_name if bp else &""
	if bp and bp.chassis:
		speed = bp.chassis.base_speed


# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	super._ready()          # CharacterBase: model, anim tree, reactor glow
	_create_collision_shape()
	_setup_reactor()
	_setup_loadout()
	if is_pilot:
		_setup_pilot_controls()


func _create_collision_shape() -> void:
	var col := CollisionShape3D.new()
	col.shape = CapsuleShape3D.new()
	col.transform.origin = Vector3(0, 0.82, 0)
	add_child(col)


func _setup_reactor() -> void:
	_reactor = ReactorCore.new()
	_reactor.name = "ReactorCore"
	if blueprint and blueprint.chassis:
		_reactor.max_integrity = blueprint.chassis.base_integrity
		_reactor.max_heat = blueprint.chassis.base_max_heat
	add_child(_reactor)
	_reactor.reactor_breached.connect(die)
	_bind_reactor_glow(_reactor)


func _setup_loadout() -> void:
	if blueprint == null or blueprint.chassis == null:
		return
	var slot_input_map: Dictionary = _get_slot_input_map()
	_loadout = Loadout.create_from_blueprint(blueprint, slot_input_map)
	_loadout.equip_all(self)


func _get_slot_input_map() -> Dictionary:
	if blueprint == null or blueprint.chassis == null:
		return {}
	match blueprint.chassis.chassis_name:
		&"Dogfighter":
			return DOGFIGHTER_SLOT_INPUTS.duplicate()
		&"Bomber":
			return BOMBER_SLOT_INPUTS.duplicate()
		_:
			return {}


func _build_key_labels() -> Dictionary:
	var labels := {}
	for keycode: int in _ability_keys:
		var action: String = _ability_keys[keycode]
		labels[action] = action.replace("ability_", "")
	return labels


# -- Pilot Controls --------------------------------------------------------

## Build camera, capture mouse, and create the ReactorHUD.
## Called from [method _ready] when [member is_pilot] is true, or later
## via [method enable_pilot_controls] when the player switches to this mech
## mid-combat.
func _setup_pilot_controls() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Third-person camera rig.
	_camera_pivot = Node3D.new()
	_camera_pivot.name = "CameraPivot"
	_camera_pivot.position = Vector3(0, 1.5, 0)
	_camera_pivot.rotation.x = deg_to_rad(-15.0)
	add_child(_camera_pivot)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0, 0, 5)
	cam.current = true
	_camera_pivot.add_child(cam)

	# HUD layer.
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "HUDLayer"
	add_child(_hud_layer)

	var hud := ReactorHUD.new()
	hud.name = "ReactorHUD"
	_hud_layer.add_child(hud)
	hud.bind_reactor(_reactor)

	# AbilityBar for active (keyed) weapon slots.
	if _loadout:
		var ability_bar := AbilityBar.new()
		ability_bar.name = "AbilityBar"
		ability_bar.bind(_loadout, _build_key_labels())
		_hud_layer.add_child(ability_bar)


## Tear down camera and HUD.  Safe to call when not piloted (no-ops).
func _teardown_pilot_controls() -> void:
	is_pilot = false
	if _camera_pivot:
		_camera_pivot.queue_free()
		_camera_pivot = null
	if _hud_layer:
		_hud_layer.queue_free()
		_hud_layer = null


## Promote an AI mech to player-piloted status mid-combat.
## Used by [EngagementManager] when the current pilot mech is destroyed.
func enable_pilot_controls() -> void:
	if is_pilot:
		return
	is_pilot = true
	_setup_pilot_controls()


# -- Animation Extensions (mirrors player.gd / clone_mech.gd) -------------

func _configure_animation_loops(anim_player: AnimationPlayer) -> void:
	_set_loop_mode(anim_player, _anim_names.get("JabLB", ""), Animation.LOOP_NONE)
	_set_loop_mode(anim_player, _anim_names.get("JabRB", ""), Animation.LOOP_NONE)
	_set_loop_mode(anim_player, _anim_names.get("JabL", ""), Animation.LOOP_NONE)
	_set_loop_mode(anim_player, _anim_names.get("JabR", ""), Animation.LOOP_NONE)


func _extend_anim_tree(
	tree: AnimationNodeBlendTree,
	anim_player: AnimationPlayer,
	base_output: StringName,
) -> StringName:
	var jab_l_a := AnimationNodeAnimation.new()
	jab_l_a.animation = _anim_names.get("JabL", &"JabL")
	tree.add_node(&"jab_l_a", jab_l_a)

	var jab_l_b := AnimationNodeAnimation.new()
	jab_l_b.animation = _anim_names.get("JabLB", &"JabLB")
	tree.add_node(&"jab_l_b", jab_l_b)

	var jab_l_blend := AnimationNodeBlend2.new()
	tree.add_node(&"hook_l", jab_l_blend)
	tree.connect_node(&"hook_l", 0, &"jab_l_a")
	tree.connect_node(&"hook_l", 1, &"jab_l_b")

	var oneshot_l := AnimationNodeOneShot.new()
	oneshot_l.fadein_time = 0.05
	oneshot_l.fadeout_time = 0.15
	_apply_upper_body_filter(oneshot_l, anim_player, _anim_names.get("JabL", ""))
	tree.add_node(&"oneshot_l", oneshot_l)
	tree.connect_node(&"oneshot_l", 0, base_output)
	tree.connect_node(&"oneshot_l", 1, &"hook_l")

	var jab_r_a := AnimationNodeAnimation.new()
	jab_r_a.animation = _anim_names.get("JabR", &"JabR")
	tree.add_node(&"jab_r_a", jab_r_a)

	var jab_r_b := AnimationNodeAnimation.new()
	jab_r_b.animation = _anim_names.get("JabRB", &"JabRB")
	tree.add_node(&"jab_r_b", jab_r_b)

	var jab_r_blend := AnimationNodeBlend2.new()
	tree.add_node(&"cross_r", jab_r_blend)
	tree.connect_node(&"cross_r", 0, &"jab_r_a")
	tree.connect_node(&"cross_r", 1, &"jab_r_b")

	var oneshot_r := AnimationNodeOneShot.new()
	oneshot_r.fadein_time = 0.05
	oneshot_r.fadeout_time = 0.15
	_apply_upper_body_filter(oneshot_r, anim_player, _anim_names.get("JabR", ""))
	tree.add_node(&"oneshot_r", oneshot_r)
	tree.connect_node(&"oneshot_r", 0, &"oneshot_l")
	tree.connect_node(&"oneshot_r", 1, &"cross_r")

	return &"oneshot_r"


func _is_action_locked() -> bool:
	if not _anim_tree:
		return false
	return bool(_anim_tree.get("parameters/oneshot_l/active")) \
		or bool(_anim_tree.get("parameters/oneshot_r/active"))


## Fire a left or right punch animation and schedule the apex hit.
## Returns [code]true[/code] so callers can track alternation state.
func try_fire_punch(left: bool) -> bool:
	if not _anim_tree:
		return false
	var param: String = "parameters/oneshot_l/request" if left \
		else "parameters/oneshot_r/request"
	_anim_tree.set(param, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_stride_timer = 0.0
	_schedule_punch_hit()
	return true


func _on_stride_updated(stride_val: float) -> void:
	if _anim_tree:
		_anim_tree.set("parameters/hook_l/blend_amount", stride_val)
		_anim_tree.set("parameters/cross_r/blend_amount", stride_val)


# -- Death -----------------------------------------------------------------

func _on_died() -> void:
	_teardown_pilot_controls()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# -- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_pilot or _dead:
		return

	if event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_camera_pivot.rotation.y -= event.relative.x * mouse_sensitivity
		_camera_pivot.rotation.x -= event.relative.y * mouse_sensitivity
		_camera_pivot.rotation.x = clampf(
			_camera_pivot.rotation.x,
			deg_to_rad(pitch_min_deg),
			deg_to_rad(pitch_max_deg),
		)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return

	# Ability key dispatch — press → activate, release → deactivate.
	if event is InputEventKey and event.keycode in _ability_keys:
		var action: String = _ability_keys[event.keycode]
		if event.pressed:
			_activate_ability(action)
		else:
			_deactivate_ability(action)

	# Punch input — LMB = left hook, RMB = right cross.
	if _anim_tree:
		var l_active: bool = _anim_tree.get("parameters/oneshot_l/active")
		var r_active: bool = _anim_tree.get("parameters/oneshot_r/active")
		if not l_active and not r_active:
			if event.is_action_pressed("hook_left"):
				try_fire_punch(true)
			elif event.is_action_pressed("cross_right"):
				try_fire_punch(false)


# -- Movement --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_pilot:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity

		var input_dir := Input.get_vector(
			"move_left", "move_right", "move_forward", "move_back"
		)
		var direction := Vector3(input_dir.x, 0.0, input_dir.y)
		if _camera_pivot:
			direction = direction.rotated(
				Vector3.UP, _camera_pivot.rotation.y
			).normalized()

		_apply_movement(direction, delta)
	else:
		# AI mode — just apply gravity and idle animation.
		_apply_movement(Vector3.ZERO, delta)
