class_name SwordBetaEntity
extends CelestialSwordEntity
## Defensive deployed sword — spawns a translucent blue spherical
## force-field barrier centred on the sword.
##
## The barrier is a thin spherical shell (20 m diameter = 10 m radius)
## built from a [ConcavePolygonShape3D] generated from a [SphereMesh]
## with [member ConcavePolygonShape3D.backface_collision] enabled so the
## shell blocks [CharacterBody3D] movement from both sides: characters
## inside cannot leave, and characters outside cannot enter.
##
## The barrier has [code]collision_layer = 1[/code] (default terrain layer)
## so standard character movement collides with it, and
## [code]collision_mask = 0[/code] (it doesn't need to detect anything).
##
## A preloaded [code]force_field.glb[/code] scene provides the visual
## (translucent blue sphere with emission baked into the glTF material).
## Override [method recall] to clean up the [StaticBody3D] before the
## entity frees itself.

## Preloaded force-field visual (translucent blue sphere with baked material).
const FORCE_FIELD_SCENE: PackedScene = preload("res://force_field.glb")

## Radius of the barrier sphere (metres).  20 m diameter = 10 m radius.
const BARRIER_RADIUS := 10.0

## Reference to the spawned [StaticBody3D] barrier for cleanup.
var _barrier: StaticBody3D = null


func _ready() -> void:
	super._ready()
	_spawn_barrier()


## Build the invisible spherical barrier and add it as a child.
func _spawn_barrier() -> void:
	_barrier = StaticBody3D.new()
	# Terrain layer so CharacterBody3D characters collide with the shell.
	_barrier.collision_layer = 1
	# The barrier doesn't need to detect anything itself.
	_barrier.collision_mask = 0

	# Generate a thin spherical shell from a SphereMesh's triangle faces.
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = BARRIER_RADIUS
	sphere_mesh.height = BARRIER_RADIUS * 2.0
	var trimesh_shape: ConcavePolygonShape3D = sphere_mesh.create_trimesh_shape()
	trimesh_shape.backface_collision = true

	var col := CollisionShape3D.new()
	col.shape = trimesh_shape
	_barrier.add_child(col)

	# Centre the barrier at the sword's mid-height (matches the base
	# entity's collision sphere y-offset).
	_barrier.position.y = 0.75
	add_child(_barrier)

	# -- Visible force-field from preloaded glTF --------------------------
	var visual := FORCE_FIELD_SCENE.instantiate()
	visual.position.y = 0.75
	add_child(visual)


## Clean up the barrier before the base recall logic emits [signal recalled]
## and frees the entity.
func recall() -> void:
	if _barrier and is_instance_valid(_barrier):
		_barrier.queue_free()
		_barrier = null
	super.recall()
