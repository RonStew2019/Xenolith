extends Node3D
class_name Cave
## Programmatic cave level builder — a destination level for flux teleportation.
##
## Constructs a large CSG-based cave environment at runtime with bioluminescent
## lighting, glow crystals, FluxNode pickups, and atmospheric fog.
## All geometry uses CSGCombiner3D with use_collision = true for automatic
## physics collision — no manual StaticBody3D needed.

# -- Layout Constants ------------------------------------------------------

## Overall rock mass dimensions.
const ROCK_SIZE := Vector3(60.0, 30.0, 60.0)

## Main chamber (spawn area) — large sphere subtraction near center.
const MAIN_CHAMBER_POS := Vector3(0.0, 6.0, 0.0)
const MAIN_CHAMBER_RADIUS := 12.0

## Secondary chamber — offset to one side.
const SECONDARY_CHAMBER_POS := Vector3(22.0, 6.5, 0.0)
const SECONDARY_CHAMBER_RADIUS := 10.0

## Tunnel connecting main and secondary chambers.
const TUNNEL_POS := Vector3(11.0, 5.5, 0.0)
const TUNNEL_SIZE := Vector3(14.0, 5.0, 3.5)

## Alcove / dead-end off the main chamber (reward spot).
const ALCOVE_POS := Vector3(-8.0, 5.5, -14.0)
const ALCOVE_RADIUS := 6.0

## Short tunnel to alcove.
const ALCOVE_TUNNEL_POS := Vector3(-4.0, 5.0, -8.0)
const ALCOVE_TUNNEL_SIZE := Vector3(3.0, 4.5, 10.0)

## Vertical chimney in secondary chamber.
const CHIMNEY_POS := Vector3(22.0, 12.0, 0.0)
const CHIMNEY_RADIUS := 3.0
const CHIMNEY_HEIGHT := 12.0

# -- Material Colors -------------------------------------------------------

const ROCK_COLOR := Color(0.18, 0.15, 0.13)
const ROCK_ROUGHNESS := 0.9
const ROCK_METALLIC := 0.0

const BG_COLOR := Color(0.02, 0.02, 0.03)
const AMBIENT_COLOR := Color(0.06, 0.06, 0.08)
const FOG_COLOR := Color(0.05, 0.05, 0.08)

# -- Light Palette ---------------------------------------------------------

const TEAL := Color(0.2, 0.6, 0.7)
const AMBER := Color(0.7, 0.4, 0.15)
const PURPLE := Color(0.3, 0.2, 0.5)
const CYAN := Color(0.15, 0.7, 0.8)

# -- Crystal Config --------------------------------------------------------

const CRYSTAL_COLORS: Array = [
	Color(0.1, 0.8, 0.9),   # cyan
	Color(0.5, 0.2, 0.8),   # purple
	Color(0.8, 0.5, 0.1),   # amber
]

# -- Flux Node positions ---------------------------------------------------

const FLUX_POSITIONS: Array = [
	Vector3(-4.0, -4.0, 3.0),    # main chamber 1
	Vector3(3.0, -4.0, -3.0),    # main chamber 2
	Vector3(11.0, 3.5, 0.0),     # tunnel
	Vector3(22.0, -2.0, -3.0),   # secondary chamber
	Vector3(-8.0, 1.0, -14.0),   # alcove (exploration reward)
]

# -- Build -----------------------------------------------------------------

func _ready() -> void:
	_build_safety_floor()
	_build_environment()
	_build_cave_geometry()
	_build_lights()
	_build_crystals()
	_build_flux_nodes()
	_build_markers()
	_build_killbox()


# ==========================================================================
#  ENVIRONMENT
# ==========================================================================

func _build_environment() -> void:
	var env := Environment.new()
	# Dark background — no sky.
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG_COLOR

	# Minimal ambient light — cave should feel dark.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = 0.05

	# Tonemap — filmic.
	env.tonemap_mode = 3  # ACES — matches main.tscn

	# Volumetric fog for atmosphere.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = FOG_COLOR
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)

	# Glow for emissive crystals.
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.1

	var we := WorldEnvironment.new()
	we.environment = env
	we.name = "WorldEnvironment"
	add_child(we)


# ==========================================================================
#  CAVE GEOMETRY (CSG)
# ==========================================================================

func _build_cave_geometry() -> void:
	var combiner := CSGCombiner3D.new()
	combiner.name = "CaveGeometry"
	combiner.use_collision = true
	add_child(combiner)

	# Rock material.
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = ROCK_COLOR
	rock_mat.roughness = ROCK_ROUGHNESS
	rock_mat.metallic = ROCK_METALLIC

	# --- Solid rock mass ---
	var rock := CSGBox3D.new()
	rock.name = "RockMass"
	rock.size = ROCK_SIZE
	rock.position = Vector3(0.0, 0.0, 0.0)  # center at y=0, spans y=-15 to y=15
	rock.material = rock_mat
	combiner.add_child(rock)

	# --- Main chamber (sphere subtraction) ---
	_add_sphere_carve(combiner, "MainChamber", MAIN_CHAMBER_POS, MAIN_CHAMBER_RADIUS)

	# --- Secondary chamber ---
	_add_sphere_carve(combiner, "SecondaryChamber", SECONDARY_CHAMBER_POS, SECONDARY_CHAMBER_RADIUS)

	# --- Tunnel connecting main → secondary ---
	_add_box_carve(combiner, "Tunnel", TUNNEL_POS, TUNNEL_SIZE)

	# --- Alcove (dead-end) ---
	_add_sphere_carve(combiner, "Alcove", ALCOVE_POS, ALCOVE_RADIUS)

	# --- Short passage to alcove ---
	_add_box_carve(combiner, "AlcoveTunnel", ALCOVE_TUNNEL_POS, ALCOVE_TUNNEL_SIZE)

	# --- Vertical chimney in secondary chamber ---
	var chimney := CSGCylinder3D.new()
	chimney.name = "Chimney"
	chimney.operation = CSGShape3D.OPERATION_SUBTRACTION
	chimney.radius = CHIMNEY_RADIUS
	chimney.height = CHIMNEY_HEIGHT
	chimney.position = CHIMNEY_POS
	chimney.sides = 16
	combiner.add_child(chimney)

	# --- Additional carving for organic feel ---
	# Small bubble off main chamber ceiling.
	_add_sphere_carve(combiner, "CeilingBubble", Vector3(3.0, 10.0, 4.0), 4.0)
	# Floor depression in secondary chamber.
	_add_sphere_carve(combiner, "FloorDip", Vector3(20.0, 3.0, 3.0), 5.0)
	# Widen tunnel entrance on main chamber side.
	_add_sphere_carve(combiner, "TunnelMouth1", Vector3(5.5, 5.5, 0.0), 4.0)
	# Widen tunnel entrance on secondary side.
	_add_sphere_carve(combiner, "TunnelMouth2", Vector3(16.5, 6.0, 0.0), 4.5)


func _add_sphere_carve(parent: Node, node_name: String, pos: Vector3, radius: float) -> void:
	var sphere := CSGSphere3D.new()
	sphere.name = node_name
	sphere.operation = CSGShape3D.OPERATION_SUBTRACTION
	sphere.radius = radius
	sphere.radial_segments = 24
	sphere.rings = 12
	sphere.position = pos
	parent.add_child(sphere)


func _add_box_carve(parent: Node, node_name: String, pos: Vector3, box_size: Vector3) -> void:
	var box := CSGBox3D.new()
	box.name = node_name
	box.operation = CSGShape3D.OPERATION_SUBTRACTION
	box.size = box_size
	box.position = pos
	parent.add_child(box)


# ==========================================================================
#  LIGHTING — Bioluminescent Cave
# ==========================================================================

func _build_lights() -> void:
	# Main chamber — teal glow (3 lights spread around).
	_add_light("MainLight1", Vector3(-3.0, 7.5, 2.0), TEAL, 0.6, 8.0, true)
	_add_light("MainLight2", Vector3(2.0, 6.0, -4.0), TEAL, 0.5, 7.0, false)
	_add_light("MainLight3", Vector3(0.0, 9.0, 0.0), CYAN, 0.4, 9.0, true)

	# Secondary chamber — warm amber.
	_add_light("SecLight1", Vector3(20.0, 7.0, -2.0), AMBER, 0.5, 7.0, true)
	_add_light("SecLight2", Vector3(24.0, 9.0, 2.0), AMBER, 0.4, 6.0, false)

	# Tunnel — dim purple/blue.
	_add_light("TunnelLight", Vector3(11.0, 6.5, 0.0), PURPLE, 0.3, 5.0, false)

	# Alcove — brighter cyan (reward area).
	_add_light("AlcoveLight", Vector3(-8.0, 6.5, -14.0), CYAN, 0.7, 6.0, true)

	# Chimney top — faint teal from above.
	_add_light("ChimneyLight", Vector3(22.0, 14.0, 0.0), TEAL, 0.3, 5.0, false)


func _add_light(light_name: String, pos: Vector3, color: Color, energy: float, light_range: float, shadows: bool) -> void:
	var light := OmniLight3D.new()
	light.name = light_name
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = shadows
	light.omni_attenuation = 1.2
	add_child(light)


# ==========================================================================
#  GLOW CRYSTALS (Decorative)
# ==========================================================================

func _build_crystals() -> void:
	# Crystal placement data: [position, rotation_degrees, color_index, scale_y]
	var crystal_data: Array = [
		# Main chamber crystals.
		[Vector3(-5.0, -4.8, 1.0), Vector3(10, 0, -15), 0, 0.4],
		[Vector3(-6.0, -4.5, -2.0), Vector3(-5, 20, 10), 0, 0.5],
		[Vector3(4.0, -4.9, 5.0), Vector3(8, -10, 20), 2, 0.35],
		[Vector3(1.0, 7.5, -5.0), Vector3(45, 0, 30), 0, 0.3],
		# Tunnel crystals.
		[Vector3(9.0, 3.3, -1.2), Vector3(-10, 0, 5), 1, 0.3],
		[Vector3(13.0, 6.8, 0.8), Vector3(40, 15, -20), 1, 0.25],
		# Secondary chamber.
		[Vector3(19.0, -2.3, -3.0), Vector3(5, 30, -10), 2, 0.45],
		[Vector3(24.0, 8.0, 1.0), Vector3(50, -20, 15), 2, 0.35],
		[Vector3(21.0, -2.2, 4.0), Vector3(-8, 10, 5), 2, 0.3],
		# Alcove crystals — more dense, rewarding exploration.
		[Vector3(-7.0, 1.2, -13.0), Vector3(5, 0, -10), 0, 0.5],
		[Vector3(-9.0, 1.4, -15.0), Vector3(-15, 25, 10), 0, 0.6],
		[Vector3(-8.0, 4.0, -14.5), Vector3(35, -10, 20), 0, 0.4],
	]

	for data in crystal_data:
		_add_crystal(data[0], data[1], data[2], data[3])


func _add_crystal(pos: Vector3, rot_deg: Vector3, color_idx: int, scale_y: float) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, scale_y, 0.08)
	mesh_inst.mesh = box
	mesh_inst.position = pos
	mesh_inst.rotation_degrees = rot_deg

	var color: Color = CRYSTAL_COLORS[color_idx]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.metallic = 0.2
	mat.roughness = 0.4
	mesh_inst.material_override = mat
	add_child(mesh_inst)


# ==========================================================================
#  FLUX NODES
# ==========================================================================

func _build_flux_nodes() -> void:
	var flux_script: Script = preload("res://flux_node.gd")
	for i in range(FLUX_POSITIONS.size()):
		var node := Node3D.new()
		node.name = "FluxNode%d" % (i + 1)
		node.set_script(flux_script)
		node.position = FLUX_POSITIONS[i]
		add_child(node)


# ==========================================================================
#  MARKERS
# ==========================================================================

func _build_markers() -> void:
	# Spawn point — center of main chamber, slightly above floor.
	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.position = Vector3(0.0, -4.5, 0.0)
	add_child(spawn)

	# Teleporter spawn — secondary chamber, for exit teleporter later.
	var teleporter := Marker3D.new()
	teleporter.name = "TeleporterSpawn"
	teleporter.position = Vector3(22.0, -2.0, 3.0)
	add_child(teleporter)


# ==========================================================================
#  KILLBOX
# ==========================================================================

func _build_safety_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "SafetyFloor"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(80.0, 1.0, 80.0)
	col.shape = shape
	body.position = Vector3(0.0, -14.5, 0.0)  # just above rock bottom
	body.add_child(col)
	add_child(body)


func _build_killbox() -> void:
	var killbox_script: Script = preload("res://killbox.gd")

	var area := Area3D.new()
	area.name = "Killbox"
	area.position = Vector3(0.0, -30.0, 0.0)
	area.set_script(killbox_script)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200.0, 2.0, 200.0)
	col.shape = shape
	area.add_child(col)
	add_child(area)
