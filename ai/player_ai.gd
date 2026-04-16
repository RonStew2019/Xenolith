extends AIController
class_name PlayerAI
## Full player-control controller extracted from [CloneMech].
##
## On [method on_enter] it builds the third-person camera pivot,
## attaches a HUD layer (reactor + ability bar + interaction prompt),
## and captures the mouse.  On [method on_exit] it tears them all
## down so another clone (or another controller) can take over.
##
## Mirrors [code]player.gd[/code]'s input handling: WASD + Space for
## movement, mouse look, LMB/RMB punches, 1-4 for ability activation,
## ESC to release the mouse.
##
## The camera pivot and HUD refs are written back onto the host
## ([code]host._camera_pivot[/code], [code]host._hud_layer[/code],
## [code]host._interaction_prompt[/code]) so external systems
## ([TunnelEffect], [ProjectileAbility]) still resolve them via
## [code]source._camera_pivot[/code] as before.

## Maps raw keycodes to loadout action strings for ability activation.
var _ability_keys: Dictionary = {
	KEY_1: "ability_1",
	KEY_2: "ability_2",
	KEY_3: "ability_3",
	KEY_4: "ability_4",
}


# ── Lifecycle ────────────────────────────────────────────────────────────

func on_enter() -> void:
	_build_camera()
	_build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func on_exit() -> void:
	if host._camera_pivot:
		host._camera_pivot.queue_free()
		host._camera_pivot = null
	if host._hud_layer:
		host._hud_layer.queue_free()
		host._hud_layer = null
	host._interaction_prompt = null


func tick(delta: float) -> void:
	if Input.is_action_just_pressed("jump") and host.is_on_floor():
		host.velocity.y = host.jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input_dir.x, 0.0, input_dir.y)
	if host._camera_pivot:
		direction = direction.rotated(Vector3.UP, host._camera_pivot.rotation.y).normalized()

	host._apply_movement(direction, delta)


# ── Camera / HUD construction (mirrors clone_mech.enable_player_control) ─

func _build_camera() -> void:
	# Camera pivot (matches player.tscn structure).
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	pivot.transform = Transform3D(
		Basis(Vector3(1, 0, 0), Vector3(0, 0.984808, -0.173648), Vector3(0, 0.173648, 0.984808)),
		Vector3(0, 1.6, 0)
	)
	host.add_child(pivot)
	host._camera_pivot = pivot

	var cam := Camera3D.new()
	cam.transform.origin = Vector3(0.5, 0, 2.2)
	pivot.add_child(cam)
	cam.make_current()


func _build_hud() -> void:
	var hud_layer := CanvasLayer.new()
	hud_layer.name = "HUDLayer"
	host.add_child(hud_layer)
	host._hud_layer = hud_layer

	var hud := ReactorHUD.new()
	hud.name = "ReactorHUD"
	hud_layer.add_child(hud)
	hud.bind_reactor(host._reactor)

	var prompt := InteractionPrompt.new()
	hud_layer.add_child(prompt)
	host._interaction_prompt = prompt

	var bar := AbilityBar.new()
	bar.bind(host._loadout, {
		"ability_1": "1",
		"ability_2": "2",
		"ability_3": "3",
		"ability_4": "4",
	})
	hud_layer.add_child(bar)


# ── Input ────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	# Mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		host._camera_pivot.rotation.y -= event.relative.x * host.mouse_sensitivity
		host._camera_pivot.rotation.x -= event.relative.y * host.mouse_sensitivity
		host._camera_pivot.rotation.x = clampf(
			host._camera_pivot.rotation.x,
			deg_to_rad(host.pitch_min_deg),
			deg_to_rad(host.pitch_max_deg),
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
			host._activate_ability(action)
		else:
			host._deactivate_ability(action)

	# Punch input
	if host._anim_tree:
		var l_active: bool = host._anim_tree.get("parameters/oneshot_l/active")
		var r_active: bool = host._anim_tree.get("parameters/oneshot_r/active")
		if not l_active and not r_active:
			if event.is_action_pressed("hook_left"):
				host._anim_tree.set(
					"parameters/oneshot_l/request",
					AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE,
				)
				host._stride_timer = 0.0
				host._schedule_punch_hit()
			elif event.is_action_pressed("cross_right"):
				host._anim_tree.set(
					"parameters/oneshot_r/request",
					AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE,
				)
				host._stride_timer = 0.0
				host._schedule_punch_hit()
