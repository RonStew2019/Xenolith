extends CharacterBase
class_name CloneMech
## Dual-mode entity: AI wander by default, switchable to full player control.
##
## Spawned by [CloneAbility].  Wanders aimlessly until the controlling
## player dies, at which point [method enable_player_control] is called
## and the clone becomes the new player avatar — camera, HUD, and all.
##
## Clones carry a full ability loadout (including CloneAbility itself)
## so multi-generational cloning is possible.  Reactor capacity return on
## death is handled by [StatTransferOnDeathEffect], applied by [CloneEffect].

# -- Exports ---------------------------------------------------------------

@export var mouse_sensitivity: float = 0.002
@export var pitch_min_deg: float = -60.0
@export var pitch_max_deg: float = 40.0
@export var jump_velocity: float = 4.5
@export var punch_apex_delay: float = 0.30

# -- Wander AI configuration ----------------------------------------------

@export var wander_radius: float = 8.0
@export var idle_time_min: float = 1.0
@export var idle_time_max: float = 4.0
@export var arrival_threshold: float = 0.5

# -- State -----------------------------------------------------------------

## When true this clone responds to player input; otherwise it wanders.
var is_player_controlled: bool = false

var _reactor: Node
var _loadout: Loadout
var _hud_layer: CanvasLayer          ## null until player-controlled
var _camera_pivot: Node3D            ## null until player-controlled (needed by TunnelEffect!)
var _interaction_prompt: InteractionPrompt  ## null until player-controlled

## Wander AI state (mirrors npc.gd).
enum State { IDLE, WALKING }
var _state: State = State.IDLE
var _idle_timer: float = 0.0
var _target_point: Vector3 = Vector3.ZERO
var _origin: Vector3 = Vector3.ZERO

## Maps raw keycodes to loadout action strings for ability activation.
var _ability_keys: Dictionary = {
	KEY_1: "ability_1",
	KEY_2: "ability_2",
	KEY_3: "ability_3",
	KEY_4: "ability_4",
}


# ── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	super._ready()  # CharacterBase: loads model, animations, reactor glow
	_create_collision_shape()
	_setup_reactor()
	_setup_loadout()
	_origin = global_position
	_enter_idle()


func _create_collision_shape() -> void:
	var col := CollisionShape3D.new()
	col.shape = CapsuleShape3D.new()
	col.transform.origin = Vector3(0, 0.82, 0)
	add_child(col)


func _setup_reactor() -> void:
	_reactor = ReactorCore.new()
	_reactor.name = "ReactorCore"
	_reactor.enable_ambient_venting = false  # Clones overheat naturally!
	add_child(_reactor)
	_reactor.reactor_breached.connect(die)
	_bind_reactor_glow(_reactor)


func _setup_loadout() -> void:
	_loadout = Loadout.new()
	_loadout.add_ability(EnvenomAbility.new("ability_1"))
	_loadout.add_ability(TunnelAbility.new("ability_2"))
	_loadout.add_ability(CoilAbility.new("ability_3"))
	_loadout.add_ability(CloneAbility.new("ability_4"))


# ── Physics (dual-mode) ─────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if is_player_controlled:
		_player_physics(delta)
	else:
		_ai_physics(delta)


# -- Player-controlled movement (mirrors player.gd) -----------------------

func _player_physics(delta: float) -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input_dir.x, 0.0, input_dir.y)
	if _camera_pivot:
		direction = direction.rotated(Vector3.UP, _camera_pivot.rotation.y).normalized()

	_apply_movement(direction, delta)


# -- AI wander (mirrors npc.gd) -------------------------------------------

func _ai_physics(delta: float) -> void:
	match _state:
		State.IDLE:
			_idle_timer -= delta
			if _idle_timer <= 0.0:
				_enter_walking()
			_apply_movement(Vector3.ZERO, delta)

		State.WALKING:
			var to_target := _target_point - global_position
			to_target.y = 0.0
			if to_target.length() < arrival_threshold:
				_enter_idle()
				_apply_movement(Vector3.ZERO, delta)
			else:
				_apply_movement(to_target.normalized(), delta)


func _enter_idle() -> void:
	_state = State.IDLE
	_idle_timer = randf_range(idle_time_min, idle_time_max)


func _enter_walking() -> void:
	_state = State.WALKING
	_target_point = _pick_wander_point()


func _pick_wander_point() -> Vector3:
	var angle := randf() * TAU
	var dist := randf_range(wander_radius * 0.3, wander_radius)
	return _origin + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


# ── Input (player-controlled only) ──────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not is_player_controlled:
		return

	# Mouse look
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

	# Punch input
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


# ── Animation Extensions (mirrors player.gd) ────────────────────────────

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


# ── Combat ───────────────────────────────────────────────────────────────

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


# ── Player Control Transfer ─────────────────────────────────────────────

## Switch this clone from AI wander to full player control.
## Creates camera, HUD, captures mouse — the player now inhabits this body.
func enable_player_control() -> void:
	is_player_controlled = true

	# Create camera pivot (matching player.tscn structure)
	_camera_pivot = Node3D.new()
	_camera_pivot.name = "CameraPivot"
	_camera_pivot.transform = Transform3D(
		Basis(Vector3(1, 0, 0), Vector3(0, 0.984808, -0.173648), Vector3(0, 0.173648, 0.984808)),
		Vector3(0, 1.6, 0)
	)
	add_child(_camera_pivot)

	var cam := Camera3D.new()
	cam.transform.origin = Vector3(0.5, 0, 2.2)
	_camera_pivot.add_child(cam)
	cam.make_current()

	# Create HUD layer
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "HUDLayer"
	add_child(_hud_layer)

	var hud := ReactorHUD.new()
	hud.name = "ReactorHUD"
	_hud_layer.add_child(hud)
	hud.bind_reactor(_reactor)

	_interaction_prompt = InteractionPrompt.new()
	_hud_layer.add_child(_interaction_prompt)

	var bar := AbilityBar.new()
	bar.bind(_loadout, {
		"ability_1": "1",
		"ability_2": "2",
		"ability_3": "3",
		"ability_4": "4",
	})
	_hud_layer.add_child(bar)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Transfer control to a living clone when this clone dies.
func _try_transfer_control() -> bool:
	if not is_player_controlled:
		return false
	var target := _find_living_clone_in_family()
	if not target:
		return false
	# Clean up our camera/HUD
	if _camera_pivot:
		_camera_pivot.queue_free()
		_camera_pivot = null
	if _hud_layer:
		_hud_layer.queue_free()
		_hud_layer = null
	is_player_controlled = false
	target.enable_player_control()
	return true


# ── Death ────────────────────────────────────────────────────────────────

func _on_died() -> void:
	if clone_parent and is_instance_valid(clone_parent):
		clone_parent.clone_children.erase(self)
	if is_player_controlled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
