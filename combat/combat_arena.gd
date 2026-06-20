extends Node3D
class_name CombatArena
## Procedural combat arena generator.
##
## Builds a terrain-appropriate 3D combat arena at runtime when the player
## launches into combat from the deployment screen.  Uses simple primitive
## meshes (BoxMesh, CylinderMesh, SphereMesh) with StaticBody3D collisions
## as cover and obstacles.
##
## Follows the same "build everything in code" pattern as [Cave].

# -- Signals ---------------------------------------------------------------

## Emitted after all arena geometry has been generated and is ready.
signal arena_ready()

## Emitted when combat ends (stubbed — for future engagement resolution).
signal arena_exited()

# -- Constants — Arena Layout ----------------------------------------------

## Arena ground-plane dimensions (X and Z).
const ARENA_SIZE: float = 80.0

## Half-size for placement math.
const ARENA_HALF: float = ARENA_SIZE / 2.0

## Ground plane thickness.
const GROUND_THICKNESS: float = 1.0

## How far from the arena edge the carrier / enemy are placed (Z axis).
const SPAWN_OFFSET_Z: float = 30.0

## Carrier visual size in the arena (bigger than overworld).
const CARRIER_BOX_SIZE := Vector3(4.0, 3.0, 4.0)

## Enemy visual scale multiplier vs. their overworld mesh.
const ENEMY_SCALE: float = 3.0

## Number of spawn point markers near the player carrier.
const SPAWN_POINT_COUNT: int = 4

## Spawn points spread (X) around the carrier.
const SPAWN_SPREAD_X: float = 6.0

## Spawn points Z offset from carrier (toward arena center).
const SPAWN_FORWARD_Z: float = 8.0

# -- Terrain Palettes ------------------------------------------------------

## Ground color per terrain type.
const GROUND_COLORS: Dictionary = {
	HexCell.TerrainType.MOUNTAIN:   Color(0.45, 0.42, 0.38),
	HexCell.TerrainType.FLORA:      Color(0.12, 0.35, 0.15),
	HexCell.TerrainType.DESERT:     Color(0.85, 0.75, 0.5),
	HexCell.TerrainType.IRRADIATED: Color(0.25, 0.08, 0.25),
	HexCell.TerrainType.RESOURCE:   Color(0.9, 0.7, 0.2),
}

## Obstacle color per terrain type.
const OBSTACLE_COLORS: Dictionary = {
	HexCell.TerrainType.MOUNTAIN:   Color(0.45, 0.42, 0.38),
	HexCell.TerrainType.FLORA:      Color(0.2, 0.55, 0.25),
	HexCell.TerrainType.DESERT:     Color(0.7, 0.6, 0.4),
	HexCell.TerrainType.IRRADIATED: Color(0.6, 0.15, 0.6),
	HexCell.TerrainType.RESOURCE:   Color(0.5, 0.5, 0.5),
}

## Obstacle count range [min, max] per terrain type.
const OBSTACLE_COUNTS: Dictionary = {
	HexCell.TerrainType.MOUNTAIN:   Vector2i(8, 12),
	HexCell.TerrainType.FLORA:      Vector2i(15, 20),
	HexCell.TerrainType.DESERT:     Vector2i(3, 5),
	HexCell.TerrainType.IRRADIATED: Vector2i(8, 10),
	HexCell.TerrainType.RESOURCE:   Vector2i(6, 8),
}

# -- Carrier / Enemy Colors ------------------------------------------------

## Player carrier teal (matches overworld Carrier.CARRIER_COLOR).
const CARRIER_COLOR: Color = Color(0.2, 0.7, 0.8)

## Fauna hive purple (matches FaunaHive.HIVE_COLOR).
const HIVE_COLOR: Color = Color(0.6, 0.15, 0.5)

## Enemy carrier red (matches EnemyCarrier.ENEMY_COLOR).
const ENEMY_CARRIER_COLOR: Color = Color(0.8, 0.2, 0.15)

# -- State -----------------------------------------------------------------

## The terrain type this arena was built for.
var _terrain_type: HexCell.TerrainType = HexCell.TerrainType.MOUNTAIN

## Cached spawn-point positions.
var _spawn_points: Array[Vector3] = []

## Reference to the threat that triggered this engagement.
var _threat: ThreatEntity = null

## Reference to the player's carrier.
var _carrier: Carrier = null

# -- Public API ------------------------------------------------------------

## Configure and build the arena.  Call this immediately after [code]new()[/code].
##
## [param terrain] — terrain type of the engagement hex.[br]
## [param threat] — the enemy entity (FaunaHive or EnemyCarrier).[br]
## [param carrier] — the player's carrier.
func setup(terrain: HexCell.TerrainType, threat: ThreatEntity, carrier: Carrier) -> void:
	_terrain_type = terrain
	_threat = threat
	_carrier = carrier
	name = "CombatArena"
	_build_arena()


## Return the world-space spawn positions for deploying mechs.
func get_spawn_points() -> Array[Vector3]:
	return _spawn_points


## Return which terrain type this arena was generated for.
func get_terrain_type() -> HexCell.TerrainType:
	return _terrain_type


## Stub — ends combat, emits [signal arena_exited].
func exit_arena() -> void:
	print("[CombatArena] Exiting arena")
	arena_exited.emit()


# -- Build Pipeline --------------------------------------------------------

func _build_arena() -> void:
	_build_environment()
	_build_ground()
	_build_directional_light()
	_build_carrier_representation()
	_build_enemy_representation()
	_build_spawn_points()
	_build_obstacles()
	_build_camera()
	print("[CombatArena] Arena built — terrain: %s, %d spawn points" % [
		HexCell.TerrainType.keys()[_terrain_type], _spawn_points.size()
	])
	arena_ready.emit()


# ==========================================================================
#  ENVIRONMENT
# ==========================================================================

func _build_environment() -> void:
	var env := Environment.new()

	# Sky — simple procedural sky for outdoor arenas.
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()

	match _terrain_type:
		HexCell.TerrainType.DESERT:
			sky_mat.sky_top_color = Color(0.4, 0.55, 0.85)
			sky_mat.sky_horizon_color = Color(0.85, 0.8, 0.65)
			sky_mat.ground_horizon_color = Color(0.85, 0.75, 0.5)
			sky_mat.ground_bottom_color = Color(0.6, 0.5, 0.3)
		HexCell.TerrainType.IRRADIATED:
			sky_mat.sky_top_color = Color(0.15, 0.05, 0.2)
			sky_mat.sky_horizon_color = Color(0.35, 0.1, 0.35)
			sky_mat.ground_horizon_color = Color(0.25, 0.08, 0.25)
			sky_mat.ground_bottom_color = Color(0.1, 0.03, 0.1)
		HexCell.TerrainType.FLORA:
			sky_mat.sky_top_color = Color(0.3, 0.5, 0.7)
			sky_mat.sky_horizon_color = Color(0.55, 0.7, 0.55)
			sky_mat.ground_horizon_color = Color(0.2, 0.4, 0.2)
			sky_mat.ground_bottom_color = Color(0.1, 0.2, 0.1)
		_:
			sky_mat.sky_top_color = Color(0.35, 0.45, 0.65)
			sky_mat.sky_horizon_color = Color(0.6, 0.6, 0.65)
			sky_mat.ground_horizon_color = Color(0.45, 0.42, 0.38)
			sky_mat.ground_bottom_color = Color(0.3, 0.28, 0.25)

	sky.sky_material = sky_mat
	env.sky = sky

	# Ambient light.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.4

	# Tonemap — ACES (matches main.tscn).
	env.tonemap_mode = 3

	# Fog for irradiated terrain.
	if _terrain_type == HexCell.TerrainType.IRRADIATED:
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.015
		env.volumetric_fog_albedo = Color(0.2, 0.05, 0.25)
		env.glow_enabled = true
		env.glow_intensity = 1.0
		env.glow_bloom = 0.15

	var we := WorldEnvironment.new()
	we.environment = env
	we.name = "WorldEnvironment"
	add_child(we)


# ==========================================================================
#  GROUND
# ==========================================================================

func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"

	# Collision.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(ARENA_SIZE, GROUND_THICKNESS, ARENA_SIZE)
	col.shape = shape
	body.add_child(col)

	# Visual.
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(ARENA_SIZE, GROUND_THICKNESS, ARENA_SIZE)
	mesh_inst.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = GROUND_COLORS.get(_terrain_type, Color(0.4, 0.4, 0.4))
	mat.roughness = 0.85
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	# Position so top surface is at Y=0.
	body.position = Vector3(0.0, -GROUND_THICKNESS / 2.0, 0.0)
	add_child(body)


# ==========================================================================
#  DIRECTIONAL LIGHT
# ==========================================================================

func _build_directional_light() -> void:
	var light := DirectionalLight3D.new()
	light.name = "SunLight"
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)

	match _terrain_type:
		HexCell.TerrainType.DESERT:
			light.light_color = Color(1.0, 0.95, 0.8)
			light.light_energy = 1.4
		HexCell.TerrainType.IRRADIATED:
			light.light_color = Color(0.6, 0.4, 0.7)
			light.light_energy = 0.6
		HexCell.TerrainType.FLORA:
			light.light_color = Color(0.9, 0.95, 0.85)
			light.light_energy = 0.9
		_:
			light.light_color = Color(1.0, 0.98, 0.95)
			light.light_energy = 1.0

	add_child(light)


# ==========================================================================
#  CARRIER REPRESENTATION (Player Side)
# ==========================================================================

func _build_carrier_representation() -> void:
	var body := StaticBody3D.new()
	body.name = "PlayerCarrier"

	# Collision.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = CARRIER_BOX_SIZE
	col.shape = shape
	col.position.y = CARRIER_BOX_SIZE.y / 2.0
	body.add_child(col)

	# Visual.
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = CARRIER_BOX_SIZE
	mesh_inst.mesh = box
	mesh_inst.position.y = CARRIER_BOX_SIZE.y / 2.0
	mesh_inst.material_override = _make_material(CARRIER_COLOR)
	body.add_child(mesh_inst)

	# Place at one end of the arena (positive Z).
	body.position = Vector3(0.0, 0.0, SPAWN_OFFSET_Z)
	add_child(body)


# ==========================================================================
#  ENEMY REPRESENTATION
# ==========================================================================

func _build_enemy_representation() -> void:
	var body := StaticBody3D.new()
	body.name = "Enemy"

	var threat_type: StringName = _threat.get_threat_type() if _threat != null else &""

	if threat_type == &"fauna_hive":
		_build_hive_visual(body)
	elif threat_type == &"enemy_carrier":
		_build_enemy_carrier_visual(body)
	else:
		# Fallback — generic red box.
		_build_enemy_carrier_visual(body)

	# Place at the opposite end of the arena (negative Z).
	body.position = Vector3(0.0, 0.0, -SPAWN_OFFSET_Z)
	add_child(body)


func _build_hive_visual(parent: StaticBody3D) -> void:
	## Scaled-up version of FaunaHive._create_visual: purple squashed sphere.
	var sphere := SphereMesh.new()
	sphere.radius = 0.5 * ENEMY_SCALE
	sphere.height = 0.7 * ENEMY_SCALE

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = sphere
	mesh_inst.scale = Vector3(1.2, 0.8, 1.2)
	mesh_inst.position.y = sphere.height * 0.4
	mesh_inst.material_override = _make_material(HIVE_COLOR)
	parent.add_child(mesh_inst)

	# Collision — use a sphere shape that roughly fits the squashed visual.
	var col := CollisionShape3D.new()
	var col_shape := SphereShape3D.new()
	col_shape.radius = sphere.radius * 1.0
	col.shape = col_shape
	col.position.y = sphere.height * 0.4
	parent.add_child(col)


func _build_enemy_carrier_visual(parent: StaticBody3D) -> void:
	## Scaled-up version of EnemyCarrier._create_visual: red box.
	var box_size := Vector3(1.0, 0.7, 1.0) * ENEMY_SCALE

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mesh_inst.mesh = box
	mesh_inst.position.y = box_size.y / 2.0
	mesh_inst.material_override = _make_material(ENEMY_CARRIER_COLOR)
	parent.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	col.position.y = box_size.y / 2.0
	parent.add_child(col)


# ==========================================================================
#  SPAWN POINTS
# ==========================================================================

func _build_spawn_points() -> void:
	_spawn_points.clear()
	for i: int in range(SPAWN_POINT_COUNT):
		var marker := Marker3D.new()
		marker.name = "SpawnPoint%d" % i
		# Spread evenly along X, slightly forward of the carrier.
		var t: float = float(i) / float(SPAWN_POINT_COUNT - 1) if SPAWN_POINT_COUNT > 1 else 0.5
		var x: float = lerpf(-SPAWN_SPREAD_X, SPAWN_SPREAD_X, t)
		var z: float = SPAWN_OFFSET_Z - SPAWN_FORWARD_Z
		marker.position = Vector3(x, 0.0, z)
		add_child(marker)
		_spawn_points.append(marker.position)


# ==========================================================================
#  CAMERA
# ==========================================================================

func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "CombatCamera"
	# Elevated perspective looking toward arena center.
	cam.position = Vector3(0.0, 35.0, 45.0)
	cam.rotation_degrees = Vector3(-40.0, 0.0, 0.0)
	cam.fov = 60.0
	cam.current = true
	add_child(cam)


# ==========================================================================
#  TERRAIN-SPECIFIC OBSTACLES
# ==========================================================================

func _build_obstacles() -> void:
	var count_range: Vector2i = OBSTACLE_COUNTS.get(_terrain_type, Vector2i(6, 8))
	var count: int = randi_range(count_range.x, count_range.y)
	var color: Color = OBSTACLE_COLORS.get(_terrain_type, Color(0.5, 0.5, 0.5))

	match _terrain_type:
		HexCell.TerrainType.MOUNTAIN:
			_build_mountain_obstacles(count, color)
		HexCell.TerrainType.FLORA:
			_build_flora_obstacles(count, color)
		HexCell.TerrainType.DESERT:
			_build_desert_obstacles(count, color)
		HexCell.TerrainType.IRRADIATED:
			_build_irradiated_obstacles(count, color)
		HexCell.TerrainType.RESOURCE:
			_build_resource_obstacles(count, color)


## Mountain — rocky pillars (cylinders) and boulders (spheres). Decent cover.
func _build_mountain_obstacles(count: int, color: Color) -> void:
	for i: int in range(count):
		var pos: Vector3 = _random_obstacle_position()
		if i % 2 == 0:
			# Rocky pillar.
			var radius: float = randf_range(0.8, 1.5)
			var height: float = randf_range(2.0, 5.0)
			_add_cylinder_obstacle("Pillar%d" % i, pos, radius, height, color)
		else:
			# Boulder.
			var radius: float = randf_range(1.0, 2.5)
			_add_sphere_obstacle("Boulder%d" % i, pos, radius, color)


## Flora — tall thin cylinders (trees) and low wide boxes (undergrowth). Dense.
func _build_flora_obstacles(count: int, color: Color) -> void:
	var trunk_color := Color(0.35, 0.25, 0.15)  # Brown trunks.
	var undergrowth_color := Color(0.15, 0.4, 0.12)  # Dark green undergrowth.
	for i: int in range(count):
		var pos: Vector3 = _random_obstacle_position()
		if i % 3 != 0:
			# Tree — tall, thin cylinder.
			var radius: float = randf_range(0.3, 0.6)
			var height: float = randf_range(4.0, 8.0)
			_add_cylinder_obstacle("Tree%d" % i, pos, radius, height, trunk_color)
			# Canopy — sphere on top.
			var canopy_pos := Vector3(pos.x, height * 0.8, pos.z)
			var canopy_radius: float = randf_range(1.5, 3.0)
			_add_sphere_obstacle("Canopy%d" % i, canopy_pos, canopy_radius, color, false)
		else:
			# Undergrowth — low, wide box.
			var half := Vector3(randf_range(1.5, 3.0), randf_range(0.4, 0.8), randf_range(1.5, 3.0))
			_add_box_obstacle("Undergrowth%d" % i, pos, half * 2.0, undergrowth_color)


## Desert — a few scattered large boulders. Wide open.
func _build_desert_obstacles(count: int, color: Color) -> void:
	for i: int in range(count):
		var pos: Vector3 = _random_obstacle_position()
		var radius: float = randf_range(2.0, 4.0)
		_add_sphere_obstacle("Rock%d" % i, pos, radius, color)


## Irradiated — rocks + glowing hazard pillars with emissive material.
func _build_irradiated_obstacles(count: int, color: Color) -> void:
	var hazard_color := Color(0.2, 0.9, 0.3)  # Toxic green glow.
	for i: int in range(count):
		var pos: Vector3 = _random_obstacle_position()
		if i % 3 == 0:
			# Glowing hazard pillar.
			var radius: float = randf_range(0.5, 1.0)
			var height: float = randf_range(3.0, 6.0)
			_add_cylinder_obstacle("HazardPillar%d" % i, pos, radius, height, hazard_color, true)
		else:
			# Irradiated rock.
			var radius: float = randf_range(1.0, 2.5)
			_add_sphere_obstacle("IrrRock%d" % i, pos, radius, color)


## Resource — mining equipment: tall box "derricks" and cylinder "tanks".
func _build_resource_obstacles(count: int, color: Color) -> void:
	var metal_color := Color(0.55, 0.55, 0.5)  # Grey metal.
	for i: int in range(count):
		var pos: Vector3 = _random_obstacle_position()
		if i % 2 == 0:
			# Derrick — tall, narrow box.
			var size := Vector3(randf_range(1.0, 1.5), randf_range(4.0, 7.0), randf_range(1.0, 1.5))
			_add_box_obstacle("Derrick%d" % i, pos, size, metal_color)
		else:
			# Tank — wide, short cylinder.
			var radius: float = randf_range(1.5, 2.5)
			var height: float = randf_range(2.0, 3.5)
			_add_cylinder_obstacle("Tank%d" % i, pos, radius, height, metal_color)


# ==========================================================================
#  OBSTACLE PRIMITIVES
# ==========================================================================

## Add a cylinder obstacle (StaticBody3D + MeshInstance3D + CollisionShape3D).
func _add_cylinder_obstacle(
	obstacle_name: String, pos: Vector3, radius: float, height: float,
	color: Color, emissive: bool = false
) -> void:
	var body := StaticBody3D.new()
	body.name = obstacle_name

	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	mesh_inst.mesh = cyl
	mesh_inst.position.y = height / 2.0
	mesh_inst.material_override = _make_material(color, emissive)
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	col.position.y = height / 2.0
	body.add_child(col)

	body.position = pos
	add_child(body)


## Add a sphere obstacle (StaticBody3D + MeshInstance3D + CollisionShape3D).
##
## [param has_collision] — set to [code]false[/code] for decorative-only
## spheres (e.g. tree canopies that shouldn't block movement).
func _add_sphere_obstacle(
	obstacle_name: String, pos: Vector3, radius: float,
	color: Color, has_collision: bool = true
) -> void:
	var body := StaticBody3D.new()
	body.name = obstacle_name

	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh_inst.mesh = sphere
	mesh_inst.position.y = radius
	mesh_inst.material_override = _make_material(color)
	body.add_child(mesh_inst)

	if has_collision:
		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = radius
		col.shape = shape
		col.position.y = radius
		body.add_child(col)

	body.position = pos
	add_child(body)


## Add a box obstacle (StaticBody3D + MeshInstance3D + CollisionShape3D).
func _add_box_obstacle(
	obstacle_name: String, pos: Vector3, box_size: Vector3, color: Color
) -> void:
	var body := StaticBody3D.new()
	body.name = obstacle_name

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mesh_inst.mesh = box
	mesh_inst.position.y = box_size.y / 2.0
	mesh_inst.material_override = _make_material(color)
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	col.position.y = box_size.y / 2.0
	body.add_child(col)

	body.position = pos
	add_child(body)


# ==========================================================================
#  HELPERS
# ==========================================================================

## Generate a random obstacle position in the middle zone of the arena.
##
## Avoids the carrier spawn zone (positive Z) and enemy zone (negative Z),
## keeping obstacles in the -20..+20 Z band and spread across X.
func _random_obstacle_position() -> Vector3:
	var x: float = randf_range(-ARENA_HALF * 0.8, ARENA_HALF * 0.8)
	var z: float = randf_range(-SPAWN_OFFSET_Z * 0.6, SPAWN_OFFSET_Z * 0.6)
	return Vector3(x, 0.0, z)


## Create a [StandardMaterial3D] with the given color.
##
## If [param emissive] is [code]true[/code], the material also emits light
## (used for irradiated hazard pillars).
func _make_material(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.5
	return mat
