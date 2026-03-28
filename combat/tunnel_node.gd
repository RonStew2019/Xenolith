extends Node3D
class_name TunnelNode
## A tunnel entrance placed in the world by [TunnelAbility].
##
## Bi-directional: walking near either entrance and pressing Q teleports
## the player to the paired entrance.  Visual is a black disc flat on the
## ground ringed by stones, like a well opening.

# -- Partner ---------------------------------------------------------------

## The other end of this tunnel pair.
var partner: TunnelNode = null

# -- Proximity State -------------------------------------------------------

## The player body currently inside the proximity zone (or null).
var _nearby_player: Node = null

# -- Palette & Dimensions --------------------------------------------------

const ENTRANCE_COLOR := Color(0.02, 0.02, 0.02)
const ROCK_COLORS := [
	Color(0.30, 0.22, 0.14),
	Color(0.40, 0.38, 0.35),
	Color(0.28, 0.20, 0.12),
	Color(0.36, 0.30, 0.22),
]

const ENTRANCE_RADIUS := 0.55    ## Radius of the black disc (metres).
const ROCK_COUNT := 20           ## Number of stones lining the perimeter.
const PROXIMITY_RADIUS := 2.5    ## Interaction detection range.
const TRAVEL_Y_OFFSET := 0.5     ## Upward offset when teleporting to avoid clipping.


func _ready() -> void:
	_build_entrance()
	_build_rocks()
	_build_proximity_area()


func _exit_tree() -> void:
	# Hide the interaction prompt if the tunnel is removed while a player
	# is still inside the proximity zone.
	if _nearby_player and is_instance_valid(_nearby_player):
		var prompt = _nearby_player.get("_interaction_prompt")
		if prompt:
			prompt.hide_prompt()
		_nearby_player = null


func _unhandled_input(event: InputEvent) -> void:
	if not _nearby_player or not is_instance_valid(_nearby_player):
		return
	if not partner or not is_instance_valid(partner):
		return
	if event is InputEventKey and event.keycode == KEY_Q and event.pressed and not event.echo:
		travel(_nearby_player)
		get_viewport().set_input_as_handled()


# -- Public API ------------------------------------------------------------

## Teleport [param player] to the partner tunnel entrance.
func travel(player: Node) -> void:
	if not partner or not is_instance_valid(partner):
		return
	# Land slightly above the partner so the character doesn't clip.
	player.global_position = partner.global_position + Vector3.UP * TRAVEL_Y_OFFSET
	# Dismiss the prompt -- the player is leaving this tunnel's zone.
	var prompt = player.get("_interaction_prompt")
	if prompt:
		prompt.hide_prompt()
	_nearby_player = null


# -- Visual Construction ---------------------------------------------------

func _build_entrance() -> void:
	var mesh_inst := MeshInstance3D.new()
	# CylinderMesh configured as a filled disc -- renders as a true circle.
	var cyl := CylinderMesh.new()
	cyl.top_radius = ENTRANCE_RADIUS
	cyl.bottom_radius = ENTRANCE_RADIUS
	cyl.height = 0.02
	cyl.radial_segments = 32
	mesh_inst.mesh = cyl
	# Barely above the ground to avoid z-fighting with the terrain.
	mesh_inst.position = Vector3(0.0, 0.01, 0.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = ENTRANCE_COLOR
	mat.roughness = 1.0
	mesh_inst.material_override = mat
	add_child(mesh_inst)


func _build_rocks() -> void:
	# Stones arranged in a ring around the disc edge, like a well lining.
	# Sizes and rotations are varied per-rock using simple deterministic
	# offsets so the ring looks hand-placed, not perfectly uniform.
	var angle_step := TAU / float(ROCK_COUNT)

	# Per-rock variation seeds (deterministic, no RNG needed).
	# 20 entries each so every rock gets a unique offset.
	var size_vars := [
		0.0, 0.3, -0.2, 0.15, -0.25, 0.35, -0.1, 0.2, -0.3, 0.25,
		-0.15, 0.1, -0.35, 0.05, -0.05, 0.3, -0.2, 0.15, -0.25, 0.1,
	]
	var rot_offsets := [
		0.4, -0.3, 0.55, -0.45, 0.2, -0.6, 0.5, -0.15, 0.35, -0.5,
		0.25, -0.4, 0.6, -0.25, 0.15, -0.55, 0.45, -0.35, 0.3, -0.2,
	]

	for i in ROCK_COUNT:
		var angle := angle_step * float(i)
		# Place rocks on the disc perimeter with a slight outward nudge so
		# they straddle the edge.
		var ring_r := ENTRANCE_RADIUS + 0.08
		var px := cos(angle) * ring_r
		var pz := sin(angle) * ring_r

		# Alternate between medium and small rocks.
		var is_medium := (i % 3 != 2)
		var base_w: float
		var base_h: float
		var base_d: float
		if is_medium:
			base_w = 0.24
			base_h = 0.16
			base_d = 0.20
		else:
			base_w = 0.15
			base_h = 0.10
			base_d = 0.13

		# Apply per-rock size variation.
		var sv: float = size_vars[i] * 0.10
		var rock_size := Vector3(base_w + sv, base_h + sv * 0.5, base_d + sv * 0.8)

		var mesh_inst := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = rock_size
		mesh_inst.mesh = box
		mesh_inst.position = Vector3(px, rock_size.y * 0.5, pz)
		# Face outward from the centre plus a jitter offset.
		mesh_inst.rotation.y = angle + rot_offsets[i]

		var mat := StandardMaterial3D.new()
		mat.albedo_color = ROCK_COLORS[i % ROCK_COLORS.size()]
		mat.roughness = 0.85
		mesh_inst.material_override = mat
		add_child(mesh_inst)


# -- Proximity Area --------------------------------------------------------

func _build_proximity_area() -> void:
	var area := Area3D.new()
	area.collision_layer = 0    # Not detectable by others.
	area.collision_mask = 1     # Detect bodies on default layer (player).

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PROXIMITY_RADIUS
	col.shape = sphere
	area.add_child(col)
	add_child(area)

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not partner or not is_instance_valid(partner):
		return
	# Only respond to nodes that carry an InteractionPrompt (i.e. the player).
	var prompt = body.get("_interaction_prompt")
	if prompt:
		_nearby_player = body
		prompt.show_prompt("Q", "Travel")


func _on_body_exited(body: Node3D) -> void:
	if body == _nearby_player:
		var prompt = body.get("_interaction_prompt")
		if prompt:
			prompt.hide_prompt()
		_nearby_player = null
