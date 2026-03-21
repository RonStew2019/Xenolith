extends CharacterBody3D
## Third-person controller with animation blending.
## WASD + Space for movement, LMB = left hook, RMB = right cross.
## Attacks overlay the upper body via OneShot nodes while the skate
## animation keeps running on the lower body.

@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var rotation_speed: float = 10.0
@export var mouse_sensitivity: float = 0.002
@export var pitch_min_deg: float = -60.0
@export var pitch_max_deg: float = 40.0

@onready var _camera_pivot: Node3D = $CameraPivot

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _stride_timer: float = 0.0
var _stride_b: bool = false
var _character: Node3D
var _anim_tree: AnimationTree


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_setup_character()


# ── Character & Animation Setup ──────────────────────────────────────────

func _setup_character() -> void:
	# Instance the generated character model
	var char_scene := load("res://character.gltf") as PackedScene
	if not char_scene:
		push_error("Player: failed to load res://character.gltf")
		return
	_character = char_scene.instantiate()
	_character.rotation.y = PI  # glTF faces +Z, Godot forward is -Z
	add_child(_character)

	# Find the AnimationPlayer baked into the imported glTF scene
	var anim_player := _find_child_by_class(_character, &"AnimationPlayer") as AnimationPlayer
	if not anim_player:
		push_warning("Player: no AnimationPlayer found in character model")
		return

	# Map short names → full names (handles library prefixes like "lib/Skate")
	var anim_names: Dictionary = {}
	for full_name in anim_player.get_animation_list():
		anim_names[full_name.get_file()] = StringName(full_name)

	# Skate loops, attacks play once
	_set_loop_mode(anim_player, anim_names.get("Idle", ""), Animation.LOOP_LINEAR)
	_set_loop_mode(anim_player, anim_names.get("Skate", ""), Animation.LOOP_LINEAR)
	_set_loop_mode(anim_player, anim_names.get("SkateB", ""), Animation.LOOP_LINEAR)
	_set_loop_mode(anim_player, anim_names.get("JabLB", ""), Animation.LOOP_NONE)
	_set_loop_mode(anim_player, anim_names.get("JabRB", ""), Animation.LOOP_NONE)
	_set_loop_mode(anim_player, anim_names.get("JabL", ""), Animation.LOOP_NONE)
	_set_loop_mode(anim_player, anim_names.get("JabR", ""), Animation.LOOP_NONE)

	# ── Build the AnimationTree in code (robust against import path changes) ──
	_anim_tree = AnimationTree.new()
	_character.add_child(_anim_tree)
	_anim_tree.anim_player = _anim_tree.get_path_to(anim_player)

	var tree := AnimationNodeBlendTree.new()

	# Idle animation
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = anim_names.get("Idle", &"Idle")
	tree.add_node(&"idle", idle_node)

	# Skate A (original stance)
	var skate_a := AnimationNodeAnimation.new()
	skate_a.animation = anim_names.get("Skate", &"Skate")
	tree.add_node(&"skate_a", skate_a)

	# Skate B (mirrored stance)
	var skate_b := AnimationNodeAnimation.new()
	skate_b.animation = anim_names.get("SkateB", &"SkateB")
	tree.add_node(&"skate_b", skate_b)

	# Blend between Skate A and B (toggled by stride timer)
	var stride_blend := AnimationNodeBlend2.new()
	tree.add_node(&"skate_blend", stride_blend)
	tree.connect_node(&"skate_blend", 0, &"skate_a")
	tree.connect_node(&"skate_blend", 1, &"skate_b")

	# Blend between idle and skating
	var blend := AnimationNodeBlend2.new()
	tree.add_node(&"skate", blend)
	tree.connect_node(&"skate", 0, &"idle")
	tree.connect_node(&"skate", 1, &"skate_blend")

	
	# JabL uses a Blend2 to pick the correct variant for current stance
	var jab_l_a := AnimationNodeAnimation.new()
	jab_l_a.animation = anim_names.get("JabL", &"JabL")
	tree.add_node(&"jab_l_a", jab_l_a)
	var jab_l_b := AnimationNodeAnimation.new()
	jab_l_b.animation = anim_names.get("JabLB", &"JabLB")
	tree.add_node(&"jab_l_b", jab_l_b)
	var jab_l_blend := AnimationNodeBlend2.new()
	tree.add_node(&"hook_l", jab_l_blend)
	tree.connect_node(&"hook_l", 0, &"jab_l_a")
	tree.connect_node(&"hook_l", 1, &"jab_l_b")

	var oneshot_l := AnimationNodeOneShot.new()
	oneshot_l.fadein_time = 0.05
	oneshot_l.fadeout_time = 0.15
	_apply_upper_body_filter(oneshot_l, anim_player, anim_names.get("JabL", ""))
	tree.add_node(&"oneshot_l", oneshot_l)
	tree.connect_node(&"oneshot_l", 0, &"skate")     # base input
	tree.connect_node(&"oneshot_l", 1, &"hook_l")   # shot input

	# JabR OneShot: chains after left so both can coexist
	# JabR uses a Blend2 to pick the correct variant for current stance
	var jab_r_a := AnimationNodeAnimation.new()
	jab_r_a.animation = anim_names.get("JabR", &"JabR")
	tree.add_node(&"jab_r_a", jab_r_a)
	var jab_r_b := AnimationNodeAnimation.new()
	jab_r_b.animation = anim_names.get("JabRB", &"JabRB")
	tree.add_node(&"jab_r_b", jab_r_b)
	var jab_r_blend := AnimationNodeBlend2.new()
	tree.add_node(&"cross_r", jab_r_blend)
	tree.connect_node(&"cross_r", 0, &"jab_r_a")
	tree.connect_node(&"cross_r", 1, &"jab_r_b")

	var oneshot_r := AnimationNodeOneShot.new()
	oneshot_r.fadein_time = 0.05
	oneshot_r.fadeout_time = 0.15
	_apply_upper_body_filter(oneshot_r, anim_player, anim_names.get("JabR", ""))
	tree.add_node(&"oneshot_r", oneshot_r)
	tree.connect_node(&"oneshot_r", 0, &"oneshot_l")  # chain from L output
	tree.connect_node(&"oneshot_r", 1, &"cross_r")    # shot input

	# Wire to output
	tree.connect_node(&"output", 0, &"oneshot_r")

	_anim_tree.tree_root = tree
	_anim_tree.active = true


func _apply_upper_body_filter(oneshot: AnimationNodeOneShot, ap: AnimationPlayer, anim_name: String) -> void:
	"""Enable filter on a OneShot node.  Auto-discovers track paths from the
	attack animation so we don't have to hard-code skeleton paths."""
	if not anim_name or not ap.has_animation(anim_name):
		return
	oneshot.filter_enabled = true
	var anim := ap.get_animation(anim_name)
	for i in anim.get_track_count():
		oneshot.set_filter_path(anim.track_get_path(i), true)


func _set_loop_mode(ap: AnimationPlayer, anim_name: String, mode: Animation.LoopMode) -> void:
	if anim_name and ap.has_animation(anim_name):
		ap.get_animation(anim_name).loop_mode = mode


func _find_child_by_class(root: Node, class_name_: StringName) -> Node:
	for child in root.get_children():
		if child.is_class(class_name_):
			return child
		var found := _find_child_by_class(child, class_name_)
		if found:
			return found
	return null


# ── Input ─────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	# Mouse look (only while captured)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_camera_pivot.rotation.y -= event.relative.x * mouse_sensitivity
		_camera_pivot.rotation.x -= event.relative.y * mouse_sensitivity
		_camera_pivot.rotation.x = clampf(
			_camera_pivot.rotation.x,
			deg_to_rad(pitch_min_deg),
			deg_to_rad(pitch_max_deg),
		)

	# Escape → free cursor
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Click to re-capture (only when cursor is free — don't attack)
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return

	# Attacks (only fires when cursor is captured, thanks to the return above)
	# Block new punches while either fist is still swinging
	if _anim_tree:
		var l_active: bool = _anim_tree.get("parameters/oneshot_l/active")
		var r_active: bool = _anim_tree.get("parameters/oneshot_r/active")
		if not l_active and not r_active:
			if event.is_action_pressed("hook_left"):
				_anim_tree.set(
					"parameters/oneshot_l/request",
					AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE,
				)
				_stride_b = false  # opposite foot leads
				_stride_timer = 0.0
			elif event.is_action_pressed("cross_right"):
				_anim_tree.set(
					"parameters/oneshot_r/request",
					AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE,
				)
				_stride_b = true  # opposite foot leads
				_stride_timer = 0.0


# ── Movement ──────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Blend idle ↔ skate based on whether we're moving
	var is_moving := input_dir.length() > 0.1
	if _anim_tree:
		var move_blend: float = 1.0 if is_moving else 0.0
		_anim_tree.set("parameters/skate/blend_amount",
			lerp(float(_anim_tree.get("parameters/skate/blend_amount")), move_blend, 8.0 * delta))
		# Alternate stride every 1s while moving (pause during punches)
		var punching := bool(_anim_tree.get("parameters/oneshot_l/active")) or bool(_anim_tree.get("parameters/oneshot_r/active"))
		if is_moving and not punching:
			_stride_timer += delta
			if _stride_timer >= 1.0:
				_stride_timer -= 1.0
				_stride_b = not _stride_b
		elif not is_moving and not punching:
			_stride_timer = 0.0
			_stride_b = false
		var stride_val: float = 1.0 if _stride_b else 0.0
		_anim_tree.set("parameters/skate_blend/blend_amount",
			lerp(float(_anim_tree.get("parameters/skate_blend/blend_amount")), stride_val, 6.0 * delta))
		# Sync jab variants to current stride
		_anim_tree.set("parameters/hook_l/blend_amount", stride_val)
		_anim_tree.set("parameters/cross_r/blend_amount", stride_val)
	var direction := Vector3(input_dir.x, 0.0, input_dir.y)
	direction = direction.rotated(Vector3.UP, _camera_pivot.rotation.y).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		if _character:
			var target_angle := atan2(direction.x, direction.z)
			_character.rotation.y = lerp_angle(
				_character.rotation.y, target_angle, rotation_speed * delta
			)
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
