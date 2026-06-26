extends Node3D
class_name HexGrid
## Generates, stores, and renders a flat-top hex grid on the XZ plane.
##
## Hexes are addressed by axial coordinates (q, r).  The grid starts as a
## hexagonal shape with [member grid_radius] rings around the origin, then
## dynamically expands as the player carrier moves near the frontier.
##
## Terrain is assigned via [FastNoiseLite] for spatially coherent biomes:
## contiguous forests, mountain ranges, deserts, irradiated zones, etc.
##
## Flat-top hex math reference (size = outer radius, center-to-vertex):
##   Width  = 2 * size
##   Height = sqrt(3) * size
##   Horizontal spacing = 1.5 * size
##   Vertical spacing   = sqrt(3) * size
##   x = size * 1.5 * q
##   z = size * sqrt(3) * (r + q / 2.0)

# -- Signals ---------------------------------------------------------------

## Emitted after dynamic expansion generates new cells.
## Includes coordinates of any new RESOURCE cells for hive placement.
signal grid_expanded(new_cell_count: int, new_resource_coords: Array[Vector2i])

# -- Configuration --------------------------------------------------------

## Number of rings around the origin hex for initial generation.
## Total cells ≈ 3r²+3r+1.
@export var grid_radius: int = 5

## Outer radius of each hex (center to vertex), in world units.
@export var cell_size: float = 2.0

## When [code]false[/code], all cells default to [constant HexCell.TerrainType.MOUNTAIN]
## unless overridden by [member terrain_overrides].  No noise-based biomes
## are generated.  Used by [TestLevelConfig] for deterministic scenarios.
@export var use_random_terrain: bool = true

## Seed for noise-based terrain generation.  0 = randomize each run.
@export var world_seed: int = 0

## How many rings ahead of the carrier to pre-generate when expanding.
@export var expansion_radius: int = 5

## Maps [code]Vector2i(q, r)[/code] → [constant HexCell.TerrainType].
## Cells whose coords appear here use the specified terrain instead of
## noise-based selection (or the MOUNTAIN default when
## [member use_random_terrain] is [code]false[/code]).
var terrain_overrides: Dictionary = {}

## Maps [code]Vector2i(q, r)[/code] → [code]{ "type": &"metal", "amount": 300.0 }[/code].
## Applied after terrain selection for RESOURCE cells, overriding the
## noise-based resource type and amount.
var resource_overrides: Dictionary = {}

# -- Terrain colours -------------------------------------------------------

const TERRAIN_COLORS: Dictionary = {
	HexCell.TerrainType.MOUNTAIN:   Color(0.45, 0.42, 0.38),
	HexCell.TerrainType.FLORA:      Color(0.2, 0.55, 0.25),
	HexCell.TerrainType.DESERT:     Color(0.85, 0.75, 0.5),
	HexCell.TerrainType.IRRADIATED: Color(0.6, 0.15, 0.6),
	HexCell.TerrainType.RESOURCE:   Color(0.9, 0.7, 0.2),  # fallback for unknown types
}

## Per-resource-type colours for RESOURCE hexes.  Matches InventoryHUD palette.
const RESOURCE_TYPE_COLORS: Dictionary = {
	&"metal":   Color(0.55, 0.62, 0.7),   # blue-silver / industrial steel
	&"crystal": Color(0.6, 0.3, 0.9),     # violet / precious
	&"fuel":    Color(0.9, 0.55, 0.15),   # amber / warm orange
}

## The six axial-coordinate direction vectors for flat-top hexes.
const HEX_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

## Mesh scale factor (< 1.0 leaves a visible gap between hexes).
const HEX_MESH_SCALE: float = 0.95

## Height of the hex prism sides, giving slight 3D depth.
const HEX_PRISM_HEIGHT: float = 0.15

# -- State -----------------------------------------------------------------

## All cells keyed by [code]Vector2i(q, r)[/code].
var cells: Dictionary = {}

## Noise generator for biome selection (low frequency, large blobs).
var _biome_noise: FastNoiseLite = null

## Noise generator for resource placement (separate seed from biomes).
var _resource_noise: FastNoiseLite = null

## Noise generator for resource sub-type clustering.
var _resource_type_noise: FastNoiseLite = null

# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	_setup_noise()
	_generate_grid()
	# Connect to carrier for dynamic expansion.
	var carrier := get_parent().get_node_or_null("Carrier") as Carrier
	if carrier != null:
		carrier.moved.connect(_on_carrier_moved)
		# Pre-generate around the carrier's starting position so there's
		# never a visible frontier right next to the player.
		expand_around(carrier.current_hex.x, carrier.current_hex.y, expansion_radius)


# -- Public API ------------------------------------------------------------

## Return the [HexCell] at axial coordinates, or [code]null[/code].
func get_cell(q: int, r: int) -> HexCell:
	return cells.get(Vector2i(q, r))


## Return up to 6 adjacent [HexCell]s that exist in the grid.
func get_neighbors(q: int, r: int) -> Array[HexCell]:
	var result: Array[HexCell] = []
	for dir: Vector2i in HEX_DIRECTIONS:
		var neighbor: HexCell = cells.get(Vector2i(q + dir.x, r + dir.y))
		if neighbor != null:
			result.append(neighbor)
	return result


## Return every [HexCell] within [param dist] hex steps of (q, r).
func get_cells_in_range(q: int, r: int, dist: int) -> Array[HexCell]:
	var result: Array[HexCell] = []
	for dq: int in range(-dist, dist + 1):
		var r_min: int = maxi(-dist, -dq - dist)
		var r_max: int = mini(dist, -dq + dist)
		for dr: int in range(r_min, r_max + 1):
			var cell: HexCell = cells.get(Vector2i(q + dq, r + dr))
			if cell != null:
				result.append(cell)
	return result


## Convert axial hex coordinates to a world-space [Vector3] (Y = 0).
func axial_to_world(q: int, r: int) -> Vector3:
	var x: float = cell_size * 1.5 * q
	var z: float = cell_size * sqrt(3.0) * (r + q / 2.0)
	return Vector3(x, 0.0, z)


## Convert a world-space position to the nearest axial coordinates.
func world_to_axial(world_pos: Vector3) -> Vector2i:
	# Reverse the flat-top conversion to get fractional axial coords.
	var fq: float = world_pos.x / (cell_size * 1.5)
	var fr: float = world_pos.z / (cell_size * sqrt(3.0)) - fq / 2.0
	return _axial_round(fq, fr)


## Generate all cells within [param radius] hex distance of
## ([param center_q], [param center_r]) that don't already exist.
## Returns the number of new cells created.
func expand_around(center_q: int, center_r: int, radius: int) -> int:
	var new_count := 0
	var new_resource_coords: Array[Vector2i] = []
	for dq: int in range(-radius, radius + 1):
		var r_min: int = maxi(-radius, -dq - radius)
		var r_max: int = mini(radius, -dq + radius)
		for dr: int in range(r_min, r_max + 1):
			var q: int = center_q + dq
			var r: int = center_r + dr
			var coords := Vector2i(q, r)
			if coords not in cells:
				var cell := _generate_cell(q, r)
				new_count += 1
				if cell.terrain == HexCell.TerrainType.RESOURCE:
					new_resource_coords.append(coords)
	if new_count > 0:
		grid_expanded.emit(new_count, new_resource_coords)
	return new_count


# -- Noise Setup (private) ------------------------------------------------

## Create and configure [FastNoiseLite] instances for terrain generation.
func _setup_noise() -> void:
	var effective_seed: int = world_seed if world_seed != 0 else randi()

	_biome_noise = FastNoiseLite.new()
	_biome_noise.seed = effective_seed
	_biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_biome_noise.frequency = 0.04
	_biome_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_biome_noise.fractal_octaves = 3

	_resource_noise = FastNoiseLite.new()
	_resource_noise.seed = effective_seed + 1337
	_resource_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_resource_noise.frequency = 0.08

	_resource_type_noise = FastNoiseLite.new()
	_resource_type_noise.seed = effective_seed + 42
	_resource_type_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_resource_type_noise.frequency = 0.06


# -- Grid Generation (private) --------------------------------------------

## Build the initial hex grid using [member grid_radius].
func _generate_grid() -> void:
	for q: int in range(-grid_radius, grid_radius + 1):
		var r_min: int = maxi(-grid_radius, -q - grid_radius)
		var r_max: int = mini(grid_radius, -q + grid_radius)
		for r: int in range(r_min, r_max + 1):
			_generate_cell(q, r)


## Create a single cell: pick terrain, assign resources, render mesh.
## Skips silently if the cell already exists at these coords.
func _generate_cell(q: int, r: int) -> HexCell:
	var coords := Vector2i(q, r)
	if coords in cells:
		return cells[coords]

	var terrain := _pick_terrain_at(q, r)
	var cell := HexCell.new(q, r, terrain)

	if terrain == HexCell.TerrainType.RESOURCE:
		if coords in resource_overrides:
			var res_data: Dictionary = resource_overrides[coords]
			cell.resource_type = res_data.get("type", &"metal")
			cell.resource_amount = res_data.get("amount", 100.0)
		elif use_random_terrain:
			cell.resource_type = _pick_resource_type_at(q, r)
			cell.resource_amount = _pick_resource_amount()

	cells[coords] = cell

	# Render immediately — each cell owns its own MeshInstance3D.
	var mesh_instance := _create_hex_mesh(cell)
	mesh_instance.position = axial_to_world(q, r)
	add_child(mesh_instance)
	return cell


## Noise-based terrain selection.  Samples [FastNoiseLite] at the hex's
## world position so nearby hexes get similar terrain → contiguous biomes.
func _pick_terrain_at(q: int, r: int) -> HexCell.TerrainType:
	var coords := Vector2i(q, r)

	# Explicit overrides always win.
	if coords in terrain_overrides:
		return terrain_overrides[coords] as HexCell.TerrainType

	# Non-random mode: all MOUNTAIN (used by test level).
	if not use_random_terrain:
		return HexCell.TerrainType.MOUNTAIN

	# Sample noise at world position for spatial coherence.
	var world_pos := axial_to_world(q, r)
	var noise_val := _biome_noise.get_noise_2d(world_pos.x, world_pos.z)

	# Resource layer — independent noise so resource clusters don't
	# perfectly align with biome boundaries.
	var resource_val := _resource_noise.get_noise_2d(world_pos.x, world_pos.z)
	if resource_val > 0.45:  # ~20% of hexes
		return HexCell.TerrainType.RESOURCE

	# Map biome noise [-1, 1] to terrain in contiguous bands.
	# Tuned to roughly approximate the old percentage distribution
	# but now with spatial coherence:
	#   FLORA ~12%  |  DESERT ~12%  |  IRRADIATED ~6%  |  MOUNTAIN ~40%  |  RESOURCE ~30%
	if noise_val < -0.35:
		return HexCell.TerrainType.FLORA
	elif noise_val < -0.05:
		return HexCell.TerrainType.DESERT
	elif noise_val < 0.10:
		return HexCell.TerrainType.IRRADIATED
	return HexCell.TerrainType.MOUNTAIN


## Pick a resource sub-type using noise for mild spatial clustering.
## Metal-rich zones, crystal veins, fuel deposits — not purely random.
func _pick_resource_type_at(q: int, r: int) -> StringName:
	var world_pos := axial_to_world(q, r)
	var val := _resource_type_noise.get_noise_2d(world_pos.x, world_pos.z)
	# [-1, 1] → metal / crystal / fuel bands (~50 / 30 / 20 split).
	if val < -0.1:
		return &"metal"
	elif val < 0.4:
		return &"crystal"
	return &"fuel"


## Pick resource amount — slight random variation.
func _pick_resource_amount() -> float:
	return randf_range(50.0, 150.0)


# -- Dynamic Expansion (private) ------------------------------------------

## Expand the grid around the carrier's new position after each move.
func _on_carrier_moved(_from: Vector2i, to: Vector2i) -> void:
	expand_around(to.x, to.y, expansion_radius)


# -- Rendering (private) --------------------------------------------------

func _create_hex_mesh(cell: HexCell) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	var scaled_size: float = cell_size * HEX_MESH_SCALE

	# Build top face + side walls.
	var top_verts := _hex_vertices(scaled_size, HEX_PRISM_HEIGHT)
	_add_top_face(mesh, top_verts)
	_add_side_faces(mesh, scaled_size, HEX_PRISM_HEIGHT)

	mesh_instance.mesh = mesh
	mesh_instance.material_override = _make_material(cell)
	return mesh_instance


## Return the 6 vertex positions for a flat-top hex at [param height].
func _hex_vertices(size: float, height: float) -> PackedVector3Array:
	var verts := PackedVector3Array()
	for i: int in range(6):
		var angle_deg: float = 60.0 * i
		var angle_rad: float = deg_to_rad(angle_deg)
		verts.append(Vector3(
			size * cos(angle_rad),
			height,
			size * sin(angle_rad),
		))
	return verts


## Add the top hexagonal face as a triangle fan (surface 0).
func _add_top_face(mesh: ArrayMesh, verts: PackedVector3Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0.0, verts[0].y, 0.0)
	for i: int in range(6):
		var next: int = (i + 1) % 6
		st.set_normal(Vector3.UP)
		st.add_vertex(center)
		st.set_normal(Vector3.UP)
		st.add_vertex(verts[i])
		st.set_normal(Vector3.UP)
		st.add_vertex(verts[next])
	st.commit(mesh)


## Add the side walls of the hex prism (surface 1).
func _add_side_faces(mesh: ArrayMesh, size: float, height: float) -> void:
	var top_verts := _hex_vertices(size, height)
	var bot_verts := _hex_vertices(size, 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(6):
		var next: int = (i + 1) % 6
		# Outward-facing normal for this edge.
		var edge_mid := (top_verts[i] + top_verts[next]) * 0.5
		var normal := Vector3(edge_mid.x, 0.0, edge_mid.z).normalized()
		# Two triangles per quad.
		st.set_normal(normal)
		st.add_vertex(top_verts[i])
		st.set_normal(normal)
		st.add_vertex(bot_verts[i])
		st.set_normal(normal)
		st.add_vertex(bot_verts[next])

		st.set_normal(normal)
		st.add_vertex(top_verts[i])
		st.set_normal(normal)
		st.add_vertex(bot_verts[next])
		st.set_normal(normal)
		st.add_vertex(top_verts[next])
	st.commit(mesh)


func _make_material(cell: HexCell) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if cell.terrain == HexCell.TerrainType.RESOURCE:
		mat.albedo_color = RESOURCE_TYPE_COLORS.get(
			cell.resource_type,
			TERRAIN_COLORS[HexCell.TerrainType.RESOURCE],
		)
	else:
		mat.albedo_color = TERRAIN_COLORS.get(cell.terrain, Color.MAGENTA)
	return mat


# -- Hex Math Helpers (private) -------------------------------------------

## Round fractional axial coordinates to the nearest hex.
func _axial_round(fq: float, fr: float) -> Vector2i:
	var fs: float = -fq - fr
	var rq: int = roundi(fq)
	var rr: int = roundi(fr)
	var rs: int = roundi(fs)
	var q_diff: float = absf(rq - fq)
	var r_diff: float = absf(rr - fr)
	var s_diff: float = absf(rs - fs)
	# Fix the component with the largest rounding error.
	if q_diff > r_diff and q_diff > s_diff:
		rq = -rr - rs
	elif r_diff > s_diff:
		rr = -rq - rs
	return Vector2i(rq, rr)
