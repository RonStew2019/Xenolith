extends Node3D
class_name Teleporter
## Sci-fi teleporter pad that consumes flux from the player's inventory,
## charges over time with escalating visual effects, then transitions to a
## target scene.
##
## All visuals are built programmatically in [method _ready] — no .tscn
## required.  Follows the same proximity-detection pattern as [FluxNode]
## and [LoadoutConsole]: Area3D + [InteractionPrompt].

# -- Configuration ---------------------------------------------------------

## Scene file to load when the player activates a fully charged teleporter.
@export var target_scene: String = "res://Cave.tscn"
## Amount of flux (or other resource) consumed to begin charging.
@export var flux_cost: int = 100
## Seconds the teleporter takes to charge after flux is consumed.
@export var charge_time: float = 10.0
## Resource type consumed from the player's [Inventory].
@export var resource_type: StringName = &"flux"

# -- State Machine ---------------------------------------------------------

enum State { INACTIVE, CHARGING, READY }
var _state: int = State.INACTIVE
var _charge_elapsed: float = 0.0

# -- Palette & Dimensions -------------------------------------------------

const BASE_RADIUS := 1.5
const BASE_HEIGHT := 0.15
const RING_RADIUS := 1.7
const RING_HEIGHT := 0.08
const TRIM_RADIUS := 1.72
const TRIM_HEIGHT := 0.04
const PROXIMITY_RADIUS := 3.0

const BASE_COLOR := Color(0.1, 0.1, 0.12)
const RING_COLOR := Color(0.08, 0.08, 0.1)

const TRIM_INACTIVE_COLOR := Color(0.15, 0.15, 0.25)
const TRIM_ACTIVE_COLOR := Color(0.1, 0.8, 0.9)
const TRIM_INACTIVE_ENERGY := 0.3
const TRIM_CHARGING_ENERGY := 4.0
const TRIM_READY_ENERGY := 5.0

const LIGHT_COLOR := Color(0.1, 0.8, 0.9)
const LIGHT_READY_ENERGY := 1.5
const LIGHT_RANGE := 4.0

const ORB_RADIUS := 0.2
const ORB_BOB_SPEED := 2.0
const ORB_SPIN_SPEED := 1.5

# -- Node References (built in _ready) ------------------------------------

var _nearby_player: Node = null
var _trim_material: StandardMaterial3D
var _center_light: OmniLight3D
var _orb_instance: MeshInstance3D
var _orb_material: StandardMaterial3D

# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	_build_base_platform()
	_build_outer_ring()
	_build_emissive_trim()
	_build_center_light()
	_build_charge_orb()
	_build_proximity_area()


func _exit_tree() -> void:
	if _nearby_player and is_instance_valid(_nearby_player):
		var prompt = _nearby_player.get("_interaction_prompt")
		if prompt:
			prompt.hide_prompt()
		_nearby_player = null


func _process(delta: float) -> void:
	match _state:
		State.CHARGING:
			_process_charging(delta)
		State.READY:
			_process_ready(delta)


func _process_charging(delta: float) -> void:
	_charge_elapsed += delta
	var t: float = clampf(_charge_elapsed / charge_time, 0.0, 1.0)

	# Ramp emissive trim.
	var energy: float = lerpf(TRIM_INACTIVE_ENERGY, TRIM_CHARGING_ENERGY, t)
	_trim_material.emission = TRIM_ACTIVE_COLOR
	_trim_material.emission_energy_multiplier = energy

	# Ramp center light.
	_center_light.light_energy = lerpf(0.0, LIGHT_READY_ENERGY, t)

	# Fade in + animate charge orb.
	if _orb_instance:
		_orb_instance.visible = true
		_orb_material.albedo_color.a = t
		_orb_material.emission_energy_multiplier = lerpf(0.5, 4.0, t)
		_orb_instance.position.y = BASE_HEIGHT + 0.6 + sin(Time.get_ticks_msec() * 0.003) * 0.1
		_orb_instance.rotate_y(ORB_SPIN_SPEED * delta)

	# Update prompt if player is nearby.
	if _nearby_player and is_instance_valid(_nearby_player):
		var prompt = _nearby_player.get("_interaction_prompt")
		if prompt:
			var secs := int(ceil(charge_time - _charge_elapsed))
			prompt.show_prompt("", "Charging… %ds" % secs)

	# Transition when fully charged.
	if _charge_elapsed >= charge_time:
		_enter_ready()


func _process_ready(delta: float) -> void:
	# Pulse the trim and light.
	var pulse: float = (sin(Time.get_ticks_msec() * 0.005) + 1.0) * 0.5  # 0→1
	_trim_material.emission_energy_multiplier = lerpf(TRIM_CHARGING_ENERGY, TRIM_READY_ENERGY, pulse)
	_center_light.light_energy = lerpf(LIGHT_READY_ENERGY * 0.7, LIGHT_READY_ENERGY, pulse)

	# Bob the orb.
	if _orb_instance:
		_orb_instance.position.y = BASE_HEIGHT + 0.6 + sin(Time.get_ticks_msec() * 0.003) * 0.15
		_orb_instance.rotate_y(ORB_SPIN_SPEED * delta)


# -- State Transitions -----------------------------------------------------

func _enter_charging() -> void:
	_state = State.CHARGING
	_charge_elapsed = 0.0
	print("[Teleporter] Charging started — %s flux consumed." % flux_cost)


func _enter_ready() -> void:
	_state = State.READY
	# Snap visuals to full brightness.
	_trim_material.emission = TRIM_ACTIVE_COLOR
	_trim_material.emission_energy_multiplier = TRIM_READY_ENERGY
	_center_light.light_energy = LIGHT_READY_ENERGY
	if _orb_instance:
		_orb_material.albedo_color.a = 1.0
		_orb_material.emission_energy_multiplier = 5.0

	# Update prompt if player is nearby.
	if _nearby_player and is_instance_valid(_nearby_player):
		var prompt = _nearby_player.get("_interaction_prompt")
		if prompt:
			prompt.show_prompt("X", "Teleport")
	print("[Teleporter] Fully charged — ready to teleport.")


# -- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _nearby_player or not is_instance_valid(_nearby_player):
		return
	if not (event is InputEventKey and event.keycode == KEY_X and event.pressed and not event.echo):
		return

	match _state:
		State.INACTIVE:
			_try_charge()
			get_viewport().set_input_as_handled()
		State.CHARGING:
			# Already charging — ignore.
			get_viewport().set_input_as_handled()
		State.READY:
			get_viewport().set_input_as_handled()
			_teleport()


func _try_charge() -> void:
	var inventory: Inventory = _nearby_player.get_node_or_null("Inventory")
	if not inventory:
		print("[Teleporter] No inventory found on player.")
		return
	if not inventory.has_enough(resource_type, flux_cost):
		print("[Teleporter] Not enough %s — need %d, have %d." % [
			resource_type, flux_cost, inventory.get_amount(resource_type)])
		return

	inventory.remove_resource(resource_type, flux_cost)
	_enter_charging()

	# Hide the charge prompt during charging.
	var prompt = _nearby_player.get("_interaction_prompt")
	if prompt:
		prompt.show_prompt("", "Charging… %ds" % int(charge_time))


func _teleport() -> void:
	print("[Teleporter] Teleporting to %s" % target_scene)
	get_tree().change_scene_to_file(target_scene)


# -- Proximity Area --------------------------------------------------------

func _build_proximity_area() -> void:
	var area := Area3D.new()
	area.collision_layer = 0   # Not detectable by others.
	area.collision_mask = 1    # Detect bodies on default layer (player).

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PROXIMITY_RADIUS
	col.shape = sphere
	# Center the detection sphere at pad height so it feels natural.
	col.position = Vector3(0.0, 1.0, 0.0)
	area.add_child(col)
	add_child(area)

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	var prompt = body.get("_interaction_prompt")
	if not prompt:
		return
	_nearby_player = body
	_update_prompt_for_state()


func _on_body_exited(body: Node3D) -> void:
	if body == _nearby_player:
		var prompt = body.get("_interaction_prompt")
		if prompt:
			prompt.hide_prompt()
		_nearby_player = null


func _update_prompt_for_state() -> void:
	if not _nearby_player or not is_instance_valid(_nearby_player):
		return
	var prompt = _nearby_player.get("_interaction_prompt")
	if not prompt:
		return

	match _state:
		State.INACTIVE:
			prompt.show_prompt("X", "Charge (%d %s)" % [flux_cost, resource_type.capitalize()])
		State.CHARGING:
			var secs := int(ceil(charge_time - _charge_elapsed))
			prompt.show_prompt("", "Charging… %ds" % secs)
		State.READY:
			prompt.show_prompt("X", "Teleport")


# -- Visual Construction ---------------------------------------------------

func _build_base_platform() -> void:
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = BASE_RADIUS
	cyl.bottom_radius = BASE_RADIUS
	cyl.height = BASE_HEIGHT
	mesh_inst.mesh = cyl
	mesh_inst.position = Vector3(0.0, BASE_HEIGHT * 0.5, 0.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = BASE_COLOR
	mat.metallic = 0.8
	mat.roughness = 0.3
	mesh_inst.material_override = mat
	add_child(mesh_inst)


func _build_outer_ring() -> void:
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = RING_RADIUS
	cyl.bottom_radius = RING_RADIUS
	cyl.height = RING_HEIGHT
	mesh_inst.mesh = cyl
	mesh_inst.position = Vector3(0.0, RING_HEIGHT * 0.5, 0.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = RING_COLOR
	mat.metallic = 0.85
	mat.roughness = 0.25
	mesh_inst.material_override = mat
	add_child(mesh_inst)


func _build_emissive_trim() -> void:
	# Thin ring around the edge that glows.  Uses a TorusMesh for a proper
	# ring shape (Godot 4.x).  Falls back to a flat cylinder if TorusMesh
	# isn't available in the engine build.
	var mesh_inst := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = BASE_RADIUS - 0.02
	torus.outer_radius = TRIM_RADIUS
	torus.rings = 32
	torus.ring_segments = 12
	mesh_inst.mesh = torus
	mesh_inst.position = Vector3(0.0, BASE_HEIGHT + 0.02, 0.0)

	_trim_material = StandardMaterial3D.new()
	_trim_material.albedo_color = TRIM_INACTIVE_COLOR
	_trim_material.emission_enabled = true
	_trim_material.emission = TRIM_INACTIVE_COLOR
	_trim_material.emission_energy_multiplier = TRIM_INACTIVE_ENERGY
	mesh_inst.material_override = _trim_material
	add_child(mesh_inst)


func _build_center_light() -> void:
	_center_light = OmniLight3D.new()
	_center_light.light_color = LIGHT_COLOR
	_center_light.light_energy = 0.0   # Starts off.
	_center_light.omni_range = LIGHT_RANGE
	_center_light.position = Vector3(0.0, BASE_HEIGHT + 1.0, 0.0)
	add_child(_center_light)


func _build_charge_orb() -> void:
	_orb_instance = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = ORB_RADIUS
	sphere.height = ORB_RADIUS * 2.0
	_orb_instance.mesh = sphere
	_orb_instance.position = Vector3(0.0, BASE_HEIGHT + 0.6, 0.0)
	_orb_instance.visible = false  # Hidden until charging starts.

	_orb_material = StandardMaterial3D.new()
	_orb_material.albedo_color = Color(0.1, 0.8, 0.9, 0.0)
	_orb_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_orb_material.emission_enabled = true
	_orb_material.emission = TRIM_ACTIVE_COLOR
	_orb_material.emission_energy_multiplier = 0.5
	_orb_instance.material_override = _orb_material
	add_child(_orb_instance)
