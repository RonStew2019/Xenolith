extends RefCounted
class_name HexCell
## A single hex tile on the overworld grid.
##
## Uses axial coordinates [member q] and [member r].  The third cube axis
## is derived: [code]s = -q - r[/code].  Terrain type determines strategic
## properties (cover, heat pressure, harvestable resources, etc.).
##
## Flat-top hex orientation — width along X, pointy edges along Z.

## Terrain types for the hex overworld.
enum TerrainType {
	MOUNTAIN,   ## Default — decent cover, not choked.
	FLORA,      ## Dense jungle — favors dogfighters.
	DESERT,     ## Wide open, no cover — favors bombers.
	IRRADIATED, ## Ambient overheating — pressure on everyone.
	RESOURCE,   ## Harvestable resource node.
}

## The three harvestable resource types.
const RESOURCE_TYPES: Array[StringName] = [&"metal", &"crystal", &"fuel"]

## Axial coordinate Q (column).
var q: int = 0

## Axial coordinate R (row).
var r: int = 0

## The terrain type of this hex.
var terrain: TerrainType = TerrainType.MOUNTAIN

## The entity currently occupying this hex (e.g. a carrier), or null.
var occupant: Node = null

## Resource subtype — one of [constant RESOURCE_TYPES], or [code]&""[/code]
## if this hex has no harvestable resource.
var resource_type: StringName = &""

## How much harvestable resource remains on this hex.
var resource_amount: float = 0.0


func _init(p_q: int = 0, p_r: int = 0, p_terrain: TerrainType = TerrainType.MOUNTAIN) -> void:
	q = p_q
	r = p_r
	terrain = p_terrain


## Derive the third cube-coordinate axis: [code]s = -q - r[/code].
func cube_s() -> int:
	return -q - r


## Return axial coords as a [Vector2i] for dictionary keys, etc.
func axial_coords() -> Vector2i:
	return Vector2i(q, r)


## Hex distance to [param other] using cube coordinates.
##
## [code]dist = max(|q1-q2|, |r1-r2|, |s1-s2|)[/code]
func distance_to(other: HexCell) -> int:
	var dq := absi(q - other.q)
	var dr := absi(r - other.r)
	var ds := absi(cube_s() - other.cube_s())
	return maxi(dq, maxi(dr, ds))
