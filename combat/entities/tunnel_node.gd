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

## True while a player is being tweened through this tunnel.
var _is_traveling: bool = false

## Reference to the active travel tween (for cleanup on early despawn).
var _travel_tween: Tween = null

## Reference to the player currently mid-travel (for cleanup on early despawn).
var _traveling_player: Node = null

## Reference to the destination tunnel during travel (for highlight cleanup).
var _travel_destination: TunnelNode = null

## Highlight ring shown on the destination tunnel while a player is traveling.
var _highlight: MeshInstance3D = null

## Inverted cone floating above the destination tunnel while a player is traveling.
var _highlight_cone: MeshInstance3D = null

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
	_build_highlight()


func _exit_tree() -> void:
	# If this node is the highlighted destination being freed, turn off the ring.
	hide_highlight()
	# If a player is mid-travel when this tunnel is freed, clean up safely.
	_abort_travel()
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

## Animate [param player] through the tunnel to the partner entrance.
## Three-phase tween: sink → underground travel → rise.
func travel(player: Node) -> void:
	if _is_traveling:
		return
	if not partner or not is_instance_valid(partner):
		return

	# Dismiss prompt and clear proximity before we begin.
	var prompt = player.get("_interaction_prompt")
	if prompt:
		prompt.hide_prompt()
	_nearby_player = null

	# Lock player movement for the duration of travel.  Unhandled input stays
	# enabled so the player can still look around (mouse look only touches
	# _camera_pivot rotation and doesn't need physics processing).
	_is_traveling = true
	_traveling_player = player
	_travel_destination = partner
	player.set_physics_process(false)

	# Light up the destination tunnel so the player can see where they're going.
	# Only show the highlight for player-controlled entities — AI clones
	# tunneling shouldn't flash the exit indicator.
	var _is_player_ctrl: bool = true
	if player.get("is_player_controlled") != null:
		_is_player_ctrl = player.is_player_controlled
	if _is_player_ctrl:
		partner.show_highlight()
	player.velocity = Vector3.ZERO

	# Waypoints.
	var sink_pos: Vector3 = global_position + Vector3.DOWN * 0.5
	var partner_underground: Vector3 = partner.global_position + Vector3.DOWN * 0.5
	var emerge_pos: Vector3 = partner.global_position + Vector3.UP * TRAVEL_Y_OFFSET

	# Speed-based underground travel duration.
	var travel_dist: float = global_position.distance_to(partner.global_position)
	var travel_duration: float = travel_dist / (player.speed * 1.75)

	var tween := player.create_tween()
	_travel_tween = tween

	# Phase 1: Sink into tunnel (parallel scale + position, ~0.3s).
	tween.tween_property(player._character, "scale", Vector3(0.3, 0.3, 0.3), 0.3)
	tween.parallel().tween_property(player, "global_position", sink_pos, 0.3)

	# Phase 2: Travel underground (sequential — starts after Phase 1 completes).
	tween.tween_property(player, "global_position", partner_underground, travel_duration)

	# Phase 3: Rise from partner tunnel (parallel scale + position, ~0.3s).
	tween.tween_property(player._character, "scale", Vector3.ONE, 0.3)
	tween.parallel().tween_property(player, "global_position", emerge_pos, 0.3)

	# Cleanup: re-enable player control (sequential — after Phase 3).
	tween.tween_callback(_finish_travel)


## Called when the travel tween completes normally.
func _finish_travel() -> void:
	if _traveling_player and is_instance_valid(_traveling_player):
		_traveling_player.set_physics_process(true)
	if _travel_destination and is_instance_valid(_travel_destination):
		_travel_destination.hide_highlight()
	_traveling_player = null
	_travel_destination = null
	_travel_tween = null
	_is_traveling = false


## Abort an in-progress travel, restoring the player to a safe state.
## Called from [method _exit_tree] when the tunnel is freed mid-travel.
func _abort_travel() -> void:
	if not _is_traveling:
		return

	# Kill the tween immediately.
	if _travel_tween and _travel_tween.is_valid():
		_travel_tween.kill()
	_travel_tween = null

	if _traveling_player and is_instance_valid(_traveling_player):
		# Restore model scale in case we were mid-shrink/grow.
		if _traveling_player._character:
			_traveling_player._character.scale = Vector3.ONE
		# If the player died while mid-travel (e.g. die() -> deactivate_all
		# -> queue_free tunnels), do NOT re-enable physics or reposition.
		# die() has already disabled physics and zeroed collision masks;
		# re-enabling would let the dead body resume movement with no
		# collision, falling through the world.
		if not _traveling_player._dead:
			# Try to surface the player at the partner; fall back to current pos.
			if partner and is_instance_valid(partner):
				_traveling_player.global_position = (
					partner.global_position + Vector3.UP * TRAVEL_Y_OFFSET
				)
			else:
				# No valid partner -- nudge upward so we're not stuck underground.
				_traveling_player.global_position.y += TRAVEL_Y_OFFSET + 0.5
			# Re-enable control.
			_traveling_player.set_physics_process(true)
	if _travel_destination and is_instance_valid(_travel_destination):
		_travel_destination.hide_highlight()
	_traveling_player = null
	_travel_destination = null
	_is_traveling = false


# -- Highlight API ---------------------------------------------------------

## Show the x-ray highlight ring on this tunnel entrance.
func show_highlight() -> void:
	if _highlight:
		_highlight.visible = true
	if _highlight_cone:
		_highlight_cone.visible = true


## Hide the x-ray highlight visuals on this tunnel entrance.
func hide_highlight() -> void:
	if _highlight:
		_highlight.visible = false
	if _highlight_cone:
		_highlight_cone.visible = false


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


func _build_highlight() -> void:
	_highlight = MeshInstance3D.new()

	var torus := TorusMesh.new()
	var major_radius := ENTRANCE_RADIUS + 0.1   # Centre of the tube ring.
	var minor_radius := 0.04                     # Tube thickness.
	torus.inner_radius = major_radius - minor_radius
	torus.outer_radius = major_radius + minor_radius
	torus.rings = 32
	torus.ring_segments = 8
	_highlight.mesh = torus

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.5, 0.0, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 10
	_highlight.material_override = mat

	_highlight.position = Vector3(0.0, 0.05, 0.0)
	_highlight.visible = false
	add_child(_highlight)

	# Inverted cone floating above the entrance, sharing the same material.
	_highlight_cone = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.3
	cone.height = 0.5
	cone.radial_segments = 16
	_highlight_cone.mesh = cone
	_highlight_cone.material_override = mat
	_highlight_cone.position = Vector3(0.0, 0.8, 0.0)
	_highlight_cone.rotation.x = PI
	_highlight_cone.visible = false
	add_child(_highlight_cone)


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
