extends Node3D
class_name HexGrid
## Generates, stores, and renders a flat-top hex grid on the XZ plane.
##
## Hexes are addressed by axial coordinates (q, r).  The grid is generated
## as a hexagonal shape with [member grid_radius] rings around the origin.
## Each hex gets a coloured [MeshInstance3D] child and a backing [HexCell]
## data object stored in [member cells].
##
## Flat-top hex math reference (size = outer radius, center-to-vertex):
##   Width  = 2 * size
##   Height = sqrt(3) * size
##   Horizontal spacing = 1.5 * size
##   Vertical spacing   = sqrt(3) * size
##   x = size * 1.5 * q
##   z = size * sqrt(3) * (r + q / 2.0)

# -- Configuration --------------------------------------------------------

## Number of rings around the origin hex.  Total cells ≈ 3r²+3r+1.
@export var grid_radius: int = 5

## Outer radius of each hex (center to vertex), in world units.
@export var cell_size: float = 2.0

# -- Terrain colours -------------------------------------------------------

const TERRAIN_COLORS: Dictionary = {
	HexCell.TerrainType.MOUNTAIN:   Color(0.45, 0.42, 0.38),
	HexCell.TerrainType.FLORA:      Color(0.2, 0.55, 0.25),
	HexCell.TerrainType.DESERT:     Color(0.85, 0.75, 0.5),
	HexCell.TerrainType.IRRADIATED: Color(0.6, 0.15, 0.6),
	HexCell.TerrainType.RESOURCE:   Color(0.9, 0.7, 0.2),
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

# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	_generate_grid()
	_render_grid()


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


# -- Grid Generation (private) --------------------------------------------

func _generate_grid() -> void:
	for q: int in range(-grid_radius, grid_radius + 1):
		var r_min: int = maxi(-grid_radius, -q - grid_radius)
		var r_max: int = mini(grid_radius, -q + grid_radius)
		for r: int in range(r_min, r_max + 1):
			var terrain := _pick_terrain()
			var cell := HexCell.new(q, r, terrain)
			if terrain == HexCell.TerrainType.RESOURCE:
				cell.resource_amount = randf_range(50.0, 150.0)
				cell.resource_type = _pick_resource_type()
			cells[Vector2i(q, r)] = cell


func _pick_terrain() -> HexCell.TerrainType:
	var roll := randf()
	# ~15% resource, ~15% flora, ~10% desert, ~5% irradiated, ~55% mountain
	if roll < 0.15:
		return HexCell.TerrainType.RESOURCE
	elif roll < 0.30:
		return HexCell.TerrainType.FLORA
	elif roll < 0.40:
		return HexCell.TerrainType.DESERT
	elif roll < 0.45:
		return HexCell.TerrainType.IRRADIATED
	return HexCell.TerrainType.MOUNTAIN


## Pick a weighted-random resource subtype for RESOURCE hexes.
##
## Distribution: ~50% metal, ~30% crystal, ~20% fuel.
func _pick_resource_type() -> StringName:
	var roll := randf()
	if roll < 0.5:
		return &"metal"
	elif roll < 0.8:
		return &"crystal"
	return &"fuel"


# -- Rendering (private) --------------------------------------------------

func _render_grid() -> void:
	for coords: Vector2i in cells:
		var cell: HexCell = cells[coords]
		var world_pos := axial_to_world(cell.q, cell.r)
		var mesh_instance := _create_hex_mesh(cell.terrain)
		mesh_instance.position = world_pos
		add_child(mesh_instance)


func _create_hex_mesh(terrain: HexCell.TerrainType) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	var scaled_size: float = cell_size * HEX_MESH_SCALE

	# Build top face + side walls.
	var top_verts := _hex_vertices(scaled_size, HEX_PRISM_HEIGHT)
	_add_top_face(mesh, top_verts)
	_add_side_faces(mesh, scaled_size, HEX_PRISM_HEIGHT)

	mesh_instance.mesh = mesh
	mesh_instance.material_override = _make_material(terrain)
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


func _make_material(terrain: HexCell.TerrainType) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = TERRAIN_COLORS.get(terrain, Color.MAGENTA)
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
