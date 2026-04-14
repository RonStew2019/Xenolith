extends Node3D
class_name LoadoutConsole
## In-world terminal that lets the player switch loadout presets.
##
## Walk within range and press E to open the [LoadoutMenu].  Selecting a
## preset calls [method Player.swap_loadout] and closes the menu.
## Escape cancels.  Follows the same proximity-detection pattern as
## [TunnelNode]: Area3D + InteractionPrompt.

# -- Palette & Dimensions --------------------------------------------------

const PEDESTAL_COLOR := Color(0.12, 0.12, 0.14)
const PANEL_COLOR := Color(0.1, 0.6, 0.8)
const PEDESTAL_WIDTH := 0.6
const PEDESTAL_HEIGHT := 1.0
const PANEL_THICKNESS := 0.04
const PROXIMITY_RADIUS := 2.5

# -- State -----------------------------------------------------------------

var _nearby_player: Node = null
var _menu: LoadoutMenu = null


func _ready() -> void:
	_build_pedestal()
	_build_top_panel()
	_build_light()
	_build_collision()
	_build_proximity_area()


func _exit_tree() -> void:
	if _nearby_player and is_instance_valid(_nearby_player):
		var prompt = _nearby_player.get("_interaction_prompt")
		if prompt:
			prompt.hide_prompt()
		_nearby_player = null
	_close_menu()


func _unhandled_input(event: InputEvent) -> void:
	if not _nearby_player or not is_instance_valid(_nearby_player):
		return
	if _menu:
		return  # Menu already open — let it handle its own input.
	if event is InputEventKey and event.keycode == KEY_E and event.pressed and not event.echo:
		_open_menu()
		get_viewport().set_input_as_handled()


# -- Menu Management -------------------------------------------------------

func _open_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_menu = LoadoutMenu.new()
	var names := LoadoutPresets.get_preset_names()
	var current: String = _nearby_player.current_preset if _nearby_player.get("current_preset") != null else ""
	_menu.setup(names, current)

	_menu.preset_selected.connect(_on_preset_selected)
	_menu.menu_closed.connect(_on_menu_closed)

	_nearby_player._hud_layer.add_child(_menu)


func _on_preset_selected(preset_name: String) -> void:
	if _nearby_player and is_instance_valid(_nearby_player):
		_nearby_player.swap_loadout(preset_name)
	_close_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_menu_closed() -> void:
	_close_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _close_menu() -> void:
	if _menu and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null


# -- Proximity Area --------------------------------------------------------

func _build_proximity_area() -> void:
	var area := Area3D.new()
	area.collision_layer = 0   # Not detectable by others.
	area.collision_mask = 1    # Detect bodies on default layer (player).

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PROXIMITY_RADIUS
	col.shape = sphere
	area.add_child(col)
	add_child(area)

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	var prompt = body.get("_interaction_prompt")
	if prompt:
		_nearby_player = body
		prompt.show_prompt("E", "Change Loadout")


func _on_body_exited(body: Node3D) -> void:
	if body == _nearby_player:
		var prompt = body.get("_interaction_prompt")
		if prompt:
			prompt.hide_prompt()
		# Close menu if player walks away while it's open.
		if _menu:
			_close_menu()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_nearby_player = null


# -- Visual Construction ---------------------------------------------------

func _build_pedestal() -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(PEDESTAL_WIDTH, PEDESTAL_HEIGHT, PEDESTAL_WIDTH)
	mesh_inst.mesh = box
	mesh_inst.position = Vector3(0.0, PEDESTAL_HEIGHT / 2.0, 0.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = PEDESTAL_COLOR
	mat.metallic = 0.8
	mat.roughness = 0.3
	mesh_inst.material_override = mat
	add_child(mesh_inst)


func _build_top_panel() -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(PEDESTAL_WIDTH - 0.1, PANEL_THICKNESS, PEDESTAL_WIDTH - 0.1)
	mesh_inst.mesh = box
	mesh_inst.position = Vector3(0.0, PEDESTAL_HEIGHT + PANEL_THICKNESS / 2.0, 0.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = PANEL_COLOR
	mat.emission_enabled = true
	mat.emission = PANEL_COLOR
	mat.emission_energy_multiplier = 3.0
	mesh_inst.material_override = mat
	add_child(mesh_inst)


func _build_light() -> void:
	var light := OmniLight3D.new()
	light.light_color = PANEL_COLOR
	light.light_energy = 0.6
	light.omni_range = 2.0
	light.position = Vector3(0.0, PEDESTAL_HEIGHT + 0.3, 0.0)
	add_child(light)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(PEDESTAL_WIDTH, PEDESTAL_HEIGHT, PEDESTAL_WIDTH)
	col.shape = shape
	col.position = Vector3(0.0, PEDESTAL_HEIGHT / 2.0, 0.0)
	body.add_child(col)
	add_child(body)
