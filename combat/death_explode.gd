class_name DeathExplode
## Splits a multi-surface skinned mesh into per-bone RigidBody3D debris.
##
## The character.gltf is one merged mesh with rigid single-bone vertex
## weighting.  This utility groups triangles by bone, builds a separate
## ArrayMesh for each group, and wraps it in a RigidBody3D ready to tumble.
##
## Usage:
##   var pieces := DeathExplode.explode(skeleton, mesh_instance)
##   for rb in pieces:
##       scene_root.add_child(rb)
##   DeathExplode.apply_burst(pieces, center)
##   DeathExplode.schedule_cleanup(pieces)

const DEBRIS_LIFETIME := 8.0
const FADE_DURATION := 2.0
const BURST_MIN := 1.5
const BURST_MAX := 4.0
const BURST_UP := 3.0
## Joint ellipsoids (surface 2) separate into standalone debris.
const JOINT_SURFACE_IDX := 2


## Split a skinned mesh into one RigidBody3D per bone.
## Returns the bodies — caller must add them to the scene tree.
static func explode(
	skeleton: Skeleton3D, mesh_inst: MeshInstance3D,
) -> Array[RigidBody3D]:
	var mesh := mesh_inst.mesh as ArrayMesh
	if not mesh or mesh.get_surface_count() == 0:
		push_warning("DeathExplode: no valid ArrayMesh on MeshInstance3D")
		return []

	var bone_count := skeleton.get_bone_count()
	var char_xform := mesh_inst.global_transform

	# Collect per-bone surface slices across ALL mesh surfaces.
	# bone_slices[bone_idx] is an Array of Dictionaries, one per surface
	# that has geometry skinned to that bone.
	var bone_slices: Array[Array] = []
	bone_slices.resize(bone_count)
	for i in bone_count:
		bone_slices[i] = []

	for surf_idx in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surf_idx)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var mat: Material = mesh_inst.get_active_material(surf_idx)

		var groups := _group_triangles_by_bone(bone_count, indices, joints)

		for bone_idx in bone_count:
			if groups.tri_lists[bone_idx].is_empty():
				continue
			bone_slices[bone_idx].append({
				"vert_map": groups.vert_maps[bone_idx],
				"tris": groups.tri_lists[bone_idx],
				"positions": positions,
				"normals": normals,
				"material": mat,
				"surface_idx": surf_idx,
			})

	var bodies: Array[RigidBody3D] = []
	for bone_idx in bone_count:
		if bone_slices[bone_idx].is_empty():
			continue
		var bone_pose := skeleton.global_transform \
			* skeleton.get_bone_global_pose(bone_idx)

		# Separate joint ellipsoids from the rest of the bone geometry.
		var main_slices: Array = []
		var joint_slices: Array = []
		for s in bone_slices[bone_idx]:
			if s["surface_idx"] == JOINT_SURFACE_IDX:
				joint_slices.append(s)
			else:
				main_slices.append(s)

		if not main_slices.is_empty():
			var piece := _build_piece_mesh_multi(main_slices, char_xform, bone_pose)
			bodies.append(_spawn_debris_body(piece, bone_pose))

		# Each joint ellipsoid becomes its own standalone debris body.
		for js in joint_slices:
			var piece := _build_piece_mesh_multi([js], char_xform, bone_pose)
			bodies.append(_spawn_debris_body(piece, bone_pose))

	return bodies


## Fling pieces outward from a center point with random torque.
static func apply_burst(bodies: Array[RigidBody3D], center: Vector3) -> void:
	for rb in bodies:
		var dir := (rb.global_position - center).normalized()
		if dir.is_zero_approx():
			dir = Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1)).normalized()
		var impulse := dir * randf_range(BURST_MIN, BURST_MAX)
		impulse.y += BURST_UP
		rb.apply_impulse(impulse)
		rb.apply_torque_impulse(Vector3(
			randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2),
		))


## Fade out and free debris after DEBRIS_LIFETIME seconds.
static func schedule_cleanup(bodies: Array[RigidBody3D]) -> void:
	for rb in bodies:
		if not rb.is_inside_tree():
			continue
		rb.get_tree().create_timer(DEBRIS_LIFETIME).timeout.connect(
			_fade_and_free.bind(rb),
		)


# ── Internals ────────────────────────────────────────────────────────────

## Group triangle indices by which bone owns the first vertex of each tri.
## Returns { vert_maps: Array[Dictionary], tri_lists: Array[Array] }.
static func _group_triangles_by_bone(
	bone_count: int, indices: PackedInt32Array, joints: PackedInt32Array,
) -> Dictionary:
	var vert_maps: Array[Dictionary] = []
	var tri_lists: Array[Array] = []
	vert_maps.resize(bone_count)
	tri_lists.resize(bone_count)
	for i in bone_count:
		vert_maps[i] = {}
		tri_lists[i] = []

	for t in range(0, indices.size(), 3):
		# joints is flat — 4 ints per vertex; first int is the bone index.
		var bone_idx: int = joints[indices[t] * 4]
		for offset in 3:
			var vi := indices[t + offset]
			if not vert_maps[bone_idx].has(vi):
				vert_maps[bone_idx][vi] = vert_maps[bone_idx].size()
		tri_lists[bone_idx].append([
			vert_maps[bone_idx][indices[t]],
			vert_maps[bone_idx][indices[t + 1]],
			vert_maps[bone_idx][indices[t + 2]],
		])

	return { "vert_maps": vert_maps, "tri_lists": tri_lists }


## Build an ArrayMesh for one bone from one or more surface slices.
## Each slice carries its own positions, normals, tris, and material.
static func _build_piece_mesh_multi(
	slices: Array,
	char_xform: Transform3D,
	bone_pose: Transform3D,
) -> ArrayMesh:
	var piece := ArrayMesh.new()
	var inv_bone := bone_pose.inverse()

	for entry in slices:
		var vert_map: Dictionary = entry["vert_map"]
		var tris: Array = entry["tris"]
		var positions: PackedVector3Array = entry["positions"]
		var normals: PackedVector3Array = entry["normals"]
		var mat: Material = entry["material"]

		var new_pos := PackedVector3Array()
		var new_norm := PackedVector3Array()
		new_pos.resize(vert_map.size())
		new_norm.resize(vert_map.size())

		for old_vi in vert_map:
			var new_vi: int = vert_map[old_vi]
			new_pos[new_vi] = inv_bone * (char_xform * positions[old_vi])
			new_norm[new_vi] = (
				inv_bone.basis * (char_xform.basis * normals[old_vi])
			).normalized()

		var new_idx := PackedInt32Array()
		for tri in tris:
			new_idx.append(tri[0])
			new_idx.append(tri[1])
			new_idx.append(tri[2])

		var surf := []
		surf.resize(Mesh.ARRAY_MAX)
		surf[Mesh.ARRAY_VERTEX] = new_pos
		surf[Mesh.ARRAY_NORMAL] = new_norm
		surf[Mesh.ARRAY_INDEX] = new_idx

		piece.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surf)
		if mat:
			piece.surface_set_material(piece.get_surface_count() - 1, mat)

	return piece


## Wrap a piece mesh in a RigidBody3D with convex collision.
static func _spawn_debris_body(
	piece_mesh: ArrayMesh, pose: Transform3D,
) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.global_transform = pose

	var mi := MeshInstance3D.new()
	mi.mesh = piece_mesh
	rb.add_child(mi)

	var col := CollisionShape3D.new()
	col.shape = piece_mesh.create_convex_shape()
	rb.add_child(col)

	return rb


static func _fade_and_free(rb: RigidBody3D) -> void:
	if not is_instance_valid(rb):
		return
	var tw := rb.create_tween()
	for child in rb.get_children():
		if child is MeshInstance3D:
			tw.parallel().tween_property(child, "transparency", 1.0, FADE_DURATION)
	tw.tween_callback(rb.queue_free)
