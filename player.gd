extends CharacterBase
## Third-person player controller with attack animations.
## WASD + Space for movement, LMB = left hook, RMB = right cross.
## Attacks overlay the upper body via OneShot nodes while the skate
## animation keeps running on the lower body.

@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002
@export var pitch_min_deg: float = -60.0
@export var pitch_max_deg: float = 40.0
@export var punch_apex_delay: float = 0.30  ## Seconds into swing before hit-check (matches animation apex)

@onready var _camera_pivot: Node3D = $CameraPivot

var _reactor: Node
var _loadout: Loadout
var _hud_layer: CanvasLayer
var _interaction_prompt: InteractionPrompt
var _ability_bar: AbilityBar
var current_preset: String = ""

## Maps raw keycodes to loadout action strings for ability activation.
## Extend this dictionary to bind more ability slots.
var _ability_keys: Dictionary = {
	KEY_1: "ability_1",
	KEY_2: "ability_2",
	KEY_3: "ability_3",
	KEY_4: "ability_4",
}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	super._ready()
	_setup_reactor()
	_setup_loadout()


func _setup_reactor() -> void:
	_reactor = ReactorCore.new()
	_reactor.name = "ReactorCore"
	add_child(_reactor)
	_reactor.reactor_breached.connect(die)
	_bind_reactor_glow(_reactor)

	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "HUDLayer"
	add_child(_hud_layer)

	var hud := ReactorHUD.new()
	hud.name = "ReactorHUD"
	_hud_layer.add_child(hud)
	hud.bind_reactor(_reactor)

	_interaction_prompt = InteractionPrompt.new()
	_hud_layer.add_child(_interaction_prompt)


func _setup_loadout() -> void:
	swap_loadout("Resonance Mk.I")


## Replace the current loadout with a named preset and rebuild the AbilityBar.
func swap_loadout(preset_name: String) -> void:
	if _loadout:
		_loadout.deactivate_all(self)
	if _ability_bar:
		_hud_layer.remove_child(_ability_bar)
		_ability_bar.queue_free()
		_ability_bar = null

	_loadout = LoadoutPresets.create_loadout(preset_name)
	current_preset = preset_name

	_ability_bar = AbilityBar.new()
	_ability_bar.bind(_loadout, { "ability_1": "1", "ability_2": "2", "ability_3": "3", "ability_4": "4" })
	_hud_layer.add_child(_ability_bar)


# -- Animation Extensions --------------------------------------------------

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


func _on_stride_updated(stride_val: float) -> void:
	if _anim_tree:
		_anim_tree.set("parameters/hook_l/blend_amount", stride_val)
		_anim_tree.set("parameters/cross_r/blend_amount", stride_val)


# -- Combat ----------------------------------------------------------------

## Schedule the hit-check to fire at the animation apex instead of frame-0.
func _schedule_punch_hit() -> void:
	if punch_apex_delay <= 0.0:
		execute_melee()
		return
	get_tree().create_timer(punch_apex_delay, false).timeout.connect(execute_melee)


## Activate an ability from the loadout by its input action.
func _activate_ability(action: String) -> void:
	var ability := _loadout.get_ability_for_action(action)
	if not ability:
		return
	ability.activate(self)


## Deactivate an ability (input released). Only matters for HOLD abilities.
func _deactivate_ability(action: String) -> void:
	var ability := _loadout.get_ability_for_action(action)
	if not ability:
		return
	ability.deactivate(self)


# -- Death -----------------------------------------------------------------

func _try_transfer_control() -> bool:
	var target := _find_living_clone_in_family()
	if not target:
		return false
	# Clean up our camera and HUD before the clone creates its own
	if _camera_pivot:
		_camera_pivot.queue_free()
		_camera_pivot = null
	if _hud_layer:
		_hud_layer.queue_free()
		_hud_layer = null
	# Tell the clone to take over
	target.enable_player_control()
	return true


func _on_died() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# -- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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

	# Ability keys: press -> activate, release -> deactivate (mode-aware).
	if event is InputEventKey and event.keycode in _ability_keys:
		var action: String = _ability_keys[event.keycode]
		if event.pressed:
			_activate_ability(action)
		else:
			_deactivate_ability(action)

	if _anim_tree:
		var l_active: bool = _anim_tree.get("parameters/oneshot_l/active")
		var r_active: bool = _anim_tree.get("parameters/oneshot_r/active")
		if not l_active and not r_active:
			if event.is_action_pressed("hook_left"):
				_anim_tree.set(
					"parameters/oneshot_l/request",
					AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE,
				)
				_stride_timer = 0.0
				_schedule_punch_hit()
			elif event.is_action_pressed("cross_right"):
				_anim_tree.set(
					"parameters/oneshot_r/request",
					AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE,
				)
				_stride_timer = 0.0
				_schedule_punch_hit()


# -- Movement --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input_dir.x, 0.0, input_dir.y)
	direction = direction.rotated(Vector3.UP, _camera_pivot.rotation.y).normalized()

	_apply_movement(direction, delta)
