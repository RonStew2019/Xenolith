extends Node3D
class_name FluxNode
## Collectible world object that grants a configurable resource on pickup.
##
## Walk within range and press X to collect.  The node removes itself from
## the scene tree after collection.  Follows the same proximity-detection
## pattern as [LoadoutConsole]: Area3D + [InteractionPrompt].
##
## All visuals are built programmatically — no .tscn required.

# -- Configuration ---------------------------------------------------------

## Resource type added to the player's [Inventory] on collection.
@export var resource_type: StringName = &"flux"
## Amount of the resource granted per pickup.
@export var resource_amount: int = 100

# -- Palette & Dimensions --------------------------------------------------

const SPHERE_RADIUS := 0.3
const SPHERE_COLOR := Color(0.1, 0.8, 0.9)
const EMISSION_ENERGY := 3.0
const LIGHT_ENERGY := 0.8
const LIGHT_RANGE := 2.5
const PROXIMITY_RADIUS := 2.5
const BOB_AMPLITUDE := 0.15
const BOB_SPEED := 0.002       # multiplied by ticks_msec
const SPIN_SPEED := 0.8        # radians per second

# -- State -----------------------------------------------------------------

var _nearby_player: Node = null
var _mesh_instance: MeshInstance3D
var _base_y: float = 0.0


func _ready() -> void:
	_base_y = position.y
	_build_mesh()
	_build_light()
	_build_proximity_area()


func _exit_tree() -> void:
	if _nearby_player and is_instance_valid(_nearby_player):
		var prompt = _nearby_player.get("_interaction_prompt")
		if prompt:
			prompt.hide_prompt()
		_nearby_player = null


func _process(delta: float) -> void:
	# Gentle vertical bob.
	var t := Time.get_ticks_msec() * BOB_SPEED
	position.y = _base_y + sin(t) * BOB_AMPLITUDE

	# Slow spin.
	if _mesh_instance:
		_mesh_instance.rotate_y(SPIN_SPEED * delta)


# -- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _nearby_player or not is_instance_valid(_nearby_player):
		return
	if event is InputEventKey and event.keycode == KEY_X and event.pressed and not event.echo:
		_collect()
		get_viewport().set_input_as_handled()


# -- Collection ------------------------------------------------------------

func _collect() -> void:
	# Find or create the player's Inventory node.
	var inventory: Inventory = _nearby_player.get_node_or_null("Inventory")
	if not inventory:
		inventory = Inventory.new()
		inventory.name = "Inventory"
		_nearby_player.add_child(inventory)

	inventory.add_resource(resource_type, resource_amount)
	print("[FluxNode] Collected %d %s (total: %d)" % [
		resource_amount,
		resource_type,
		inventory.get_amount(resource_type),
	])
	queue_free()


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
		prompt.show_prompt("X", "Collect")


func _on_body_exited(body: Node3D) -> void:
	if body == _nearby_player:
		var prompt = body.get("_interaction_prompt")
		if prompt:
			prompt.hide_prompt()
		_nearby_player = null


# -- Visual Construction ---------------------------------------------------

func _build_mesh() -> void:
	_mesh_instance = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = SPHERE_RADIUS
	sphere.height = SPHERE_RADIUS * 2.0
	_mesh_instance.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = SPHERE_COLOR
	mat.emission_enabled = true
	mat.emission = SPHERE_COLOR
	mat.emission_energy_multiplier = EMISSION_ENERGY
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


func _build_light() -> void:
	var light := OmniLight3D.new()
	light.light_color = SPHERE_COLOR
	light.light_energy = LIGHT_ENERGY
	light.omni_range = LIGHT_RANGE
	add_child(light)
