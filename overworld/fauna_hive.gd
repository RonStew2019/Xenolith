extends ThreatEntity
class_name FaunaHive
## A stationary fauna hive/nest on the hex overworld.
##
## Represents a destroyable objective in fauna engagements.  Does not move
## — [method take_turn] is intentionally empty.  Has an aggro range that
## can be wider than the standard 1-hex detection radius.

# -- Properties ------------------------------------------------------------

## Hex distance at which this hive detects the carrier and becomes agitated.
## Wider than the standard 1-hex detection range.
var aggro_range: int = 2

## Multiplier for fauna count/difficulty in the engagement combat arena.
var swarm_strength: float = 1.0

# -- Constants -------------------------------------------------------------

## Dark purple/magenta — organic, alien, menacing.
const HIVE_COLOR: Color = Color(0.6, 0.15, 0.5)

# -- Overrides -------------------------------------------------------------

## Fauna hives don't move.  They sit and wait.
func take_turn() -> void:
	pass


## Return the threat type identifier.
func get_threat_type() -> StringName:
	return &"fauna_hive"


## Create an organic-looking visual — a scaled sphere.
func _create_visual() -> void:
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 0.7
	mesh_instance.mesh = sphere
	# Squash it slightly to look like a mound/nest.
	mesh_instance.scale = Vector3(1.2, 0.8, 1.2)
	mesh_instance.position.y = sphere.height * 0.4
	mesh_instance.material_override = _make_material(HIVE_COLOR)
	add_child(mesh_instance)
	_visual = mesh_instance


# -- Public API ------------------------------------------------------------

## Check whether the carrier at [param carrier_hex] is within aggro range.
func is_carrier_in_aggro_range(carrier_hex: Vector2i) -> bool:
	if hex_grid == null:
		return false
	var hive_cell: HexCell = hex_grid.get_cell(current_hex.x, current_hex.y)
	var carrier_cell: HexCell = hex_grid.get_cell(carrier_hex.x, carrier_hex.y)
	if hive_cell == null or carrier_cell == null:
		return false
	return hive_cell.distance_to(carrier_cell) <= aggro_range
