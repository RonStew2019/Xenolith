extends Node3D
class_name ThreatEntity
## Base class for all threatening entities on the hex overworld.
##
## Tracks hex position, renders a coloured mesh placeholder, and claims
## its hex cell via [member HexCell.occupant] — which naturally blocks
## carrier movement through that hex.
##
## Subclasses override [method take_turn], [method get_threat_type], and
## [method _create_visual] to specialize behaviour.

# -- Signals ---------------------------------------------------------------

## Emitted when this entity is about to be removed from the grid.
signal removed()

# -- Properties ------------------------------------------------------------

## Display name shown in UI and debug output.
var entity_name: StringName = &""

## How dangerous this threat is.  Higher values mean harder engagements.
var threat_level: float = 1.0

## Current axial position on the hex grid.
var current_hex: Vector2i = Vector2i.ZERO

## Reference to the hex grid this entity lives on.
var hex_grid: HexGrid = null

## The mesh visual for this entity.  Created by [method _create_visual].
var _visual: MeshInstance3D = null

# -- Constants -------------------------------------------------------------

## Height offset — same as the carrier, sits on top of the hex prism.
const ENTITY_Y_OFFSET: float = 0.3

# -- Public API ------------------------------------------------------------

## Place this entity on the grid at [param start_q], [param start_r].
##
## Snaps position, claims the hex cell, and creates the visual mesh.
func initialize(grid: HexGrid, start_q: int, start_r: int) -> void:
	hex_grid = grid
	_create_visual()
	_snap_to_hex(start_q, start_r)
	print("[%s] Initialized at (%d, %d)" % [entity_name, start_q, start_r])


## Virtual — called by [ThreatManager] each threat turn.
##
## Override in subclasses to add movement, spawning, etc.
func take_turn() -> void:
	pass


## Virtual — return a [StringName] identifying the threat type.
##
## Override in subclasses: [code]&"fauna_hive"[/code],
## [code]&"enemy_carrier"[/code], etc.
func get_threat_type() -> StringName:
	return &""


## Remove this entity from the grid: unclaim hex, emit signal, free.
func remove_from_grid() -> void:
	var cell: HexCell = hex_grid.get_cell(current_hex.x, current_hex.y) if hex_grid != null else null
	if cell != null and cell.occupant == self:
		cell.occupant = null
	print("[%s] Removed from grid at (%d, %d)" % [entity_name, current_hex.x, current_hex.y])
	removed.emit()
	queue_free()


# -- Private Helpers -------------------------------------------------------

## Teleport to a hex, update [member current_hex], and claim the cell.
func _snap_to_hex(q: int, r: int) -> void:
	# Release old cell if we had one.
	if hex_grid != null:
		var old_cell: HexCell = hex_grid.get_cell(current_hex.x, current_hex.y)
		if old_cell != null and old_cell.occupant == self:
			old_cell.occupant = null

	current_hex = Vector2i(q, r)

	if hex_grid != null:
		var world_pos: Vector3 = hex_grid.axial_to_world(q, r)
		position = Vector3(world_pos.x, ENTITY_Y_OFFSET, world_pos.z)
		# Claim new cell.
		var new_cell: HexCell = hex_grid.get_cell(q, r)
		if new_cell != null:
			new_cell.occupant = self


## Virtual — create a mesh visual for this entity.
##
## Override in subclasses for different shapes/colours.
func _create_visual() -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.6, 0.8)
	mesh_instance.mesh = box
	mesh_instance.position.y = box.size.y / 2.0
	mesh_instance.material_override = _make_material(Color.MAGENTA)
	add_child(mesh_instance)
	_visual = mesh_instance


## Create a simple unshaded [StandardMaterial3D] with the given colour.
func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat
