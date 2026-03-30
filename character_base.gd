extends CharacterBody3D
class_name CharacterBase
## Base class for character.gltf-backed entities.
## Handles model loading, locomotion animation tree, and movement helpers.
## Subclasses (Player, NPC, etc.) provide their own input or AI.

## Emitted when a melee strike connects, BEFORE effects are applied.
## Listeners (e.g. [MeleeModifierEffect]) can mutate the [MeleeEvent]:
## append effects, replace defaults, or cancel the strike entirely.
signal melee_strike(event: MeleeEvent)

@export var speed: float = 5.0
@export var speed_multiplier: float = 1.0
@export var rotation_speed: float = 10.0
@export var punch_reach: float = 2.5
@export var punch_weight: float = 50.0

## Surface index of the reactor orb in the imported glTF mesh.
const REACTOR_SURFACE_IDX: int = 4
## Surface index of the Joint (ball joint) material.
const JOINT_SURFACE_IDX: int = 2
## Maximum emission energy when heat is at 100%.  Tune for visual punch.
## At 0% heat the orb is dark; at 100% it blazes at this energy level.
const REACTOR_MAX_INTENSITY: float = 8.0
## Peak emission energy for joint ellipsoids at 100% heat.
const JOINT_MAX_INTENSITY: float = 4.0
## Peak energy for the reactor point light at 100% heat.
const REACTOR_LIGHT_MAX_ENERGY: float = 2.0
## How far the reactor light reaches (metres).
const REACTOR_LIGHT_RANGE: float = 1.5
## Warm golden ember tint matching the ceramic theme.
const REACTOR_LIGHT_COLOR: Color = Color(1.0, 0.55, 0.18)

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _stride_timer: float = 0.0
var _stride_b: bool = false
var _dead: bool = false
var _character: Node3D
var _anim_tree: AnimationTree
var _anim_names: Dictionary = {}
var _reactor_material: StandardMaterial3D
var _joint_material: StandardMaterial3D
var _reactor_light: OmniLight3D


func _ready() -> void:
	add_to_group("characters")
	_setup_character()
	_setup_reactor_glow()


# ── Character & Animation Setup ──────────────────────────────────────────

func _setup_character() -> void:
	var char_scene := load("res://character.gltf") as PackedScene
	if not char_scene:
		push_error("CharacterBase: failed to load res://character.gltf")
		return
	_character = char_scene.instantiate()
	_character.rotation.y = PI  # glTF faces +Z, Godot forward is -Z
	add_child(_character)

	var anim_player := _find_child_by_class(_character, &"AnimationPlayer") as AnimationPlayer
	if not anim_player:
		push_warning("CharacterBase: no AnimationPlayer found in character model")
		return

	for full_name in anim_player.get_animation_list():
		_anim_names[full_name.get_file()] = StringName(full_name)

	_set_loop_mode(anim_player, _anim_names.get("Idle", ""), Animation.LOOP_LINEAR)
	_set_loop_mode(anim_player, _anim_names.get("Skate", ""), Animation.LOOP_LINEAR)
	_set_loop_mode(anim_player, _anim_names.get("SkateB", ""), Animation.LOOP_LINEAR)
	_configure_animation_loops(anim_player)

	_anim_tree = AnimationTree.new()
	_character.add_child(_anim_tree)
	_anim_tree.anim_player = _anim_tree.get_path_to(anim_player)

	var tree := AnimationNodeBlendTree.new()
	var last_node := _build_locomotion_tree(tree)
	last_node = _extend_anim_tree(tree, anim_player, last_node)
	tree.connect_node(&"output", 0, last_node)

	_anim_tree.tree_root = tree
	_anim_tree.active = true


func _build_locomotion_tree(tree: AnimationNodeBlendTree) -> StringName:
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = _anim_names.get("Idle", &"Idle")
	tree.add_node(&"idle", idle_node)

	var skate_a := AnimationNodeAnimation.new()
	skate_a.animation = _anim_names.get("Skate", &"Skate")
	tree.add_node(&"skate_a", skate_a)

	var skate_b := AnimationNodeAnimation.new()
	skate_b.animation = _anim_names.get("SkateB", &"SkateB")
	tree.add_node(&"skate_b", skate_b)

	var stride_blend := AnimationNodeBlend2.new()
	tree.add_node(&"skate_blend", stride_blend)
	tree.connect_node(&"skate_blend", 0, &"skate_a")
	tree.connect_node(&"skate_blend", 1, &"skate_b")

	var blend := AnimationNodeBlend2.new()
	tree.add_node(&"skate", blend)
	tree.connect_node(&"skate", 0, &"idle")
	tree.connect_node(&"skate", 1, &"skate_blend")

	return &"skate"


func _configure_animation_loops(_anim_player: AnimationPlayer) -> void:
	pass


func _extend_anim_tree(
	_tree: AnimationNodeBlendTree,
	_anim_player: AnimationPlayer,
	base_output: StringName,
) -> StringName:
	return base_output


# ── Reactor Glow ──────────────────────────────────────────────────────────

## Finds the reactor orb surface material and duplicates it so we can
## modify emission_energy_multiplier at runtime without touching the
## shared imported resource.
func _setup_reactor_glow() -> void:
	if not _character:
		return
	var skeleton := _find_child_by_class(_character, &"Skeleton3D") as Skeleton3D
	if not skeleton:
		return
	var mesh_inst: MeshInstance3D = null
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			mesh_inst = child
			break
	if not mesh_inst:
		return
	var mat := mesh_inst.get_active_material(REACTOR_SURFACE_IDX)
	if mat is StandardMaterial3D:
		_reactor_material = mat.duplicate() as StandardMaterial3D
		_reactor_material.emission_energy_multiplier = 0.0
		mesh_inst.set_surface_override_material(REACTOR_SURFACE_IDX, _reactor_material)

	# Duplicate the Joint (ball joint) material so we can drive its emission too.
	var joint_mat := mesh_inst.get_active_material(JOINT_SURFACE_IDX)
	if joint_mat is StandardMaterial3D:
		_joint_material = joint_mat.duplicate() as StandardMaterial3D
		_joint_material.emission_energy_multiplier = 0.0
		mesh_inst.set_surface_override_material(JOINT_SURFACE_IDX, _joint_material)

	# Attach a point light to the Spine bone so it follows the orb.
	var spine_idx := skeleton.find_bone("Spine")
	if spine_idx >= 0:
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = "Spine"
		skeleton.add_child(attachment)
		_reactor_light = OmniLight3D.new()
		_reactor_light.light_color = REACTOR_LIGHT_COLOR
		_reactor_light.light_energy = 0.0
		_reactor_light.omni_range = REACTOR_LIGHT_RANGE
		_reactor_light.omni_attenuation = 1.5
		_reactor_light.shadow_enabled = false
		# Offset from Spine bone to reactor orb centre (model space).
		_reactor_light.position = Vector3(0.0, 0.11, 0.12)
		attachment.add_child(_reactor_light)


## Bind a ReactorCore node so the orb glow tracks its heat level.
func _bind_reactor_glow(reactor: Node) -> void:
	if reactor and reactor.has_signal("heat_changed"):
		reactor.heat_changed.connect(_on_reactor_heat_changed)


func _on_reactor_heat_changed(current: float, maximum: float) -> void:
	var ratio := clampf(current / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
	_update_reactor_glow(ratio)


## Set the reactor orb emission energy from a 0-1 heat ratio.
## 0.0 = cold/dark, 1.0 = full intensity (REACTOR_MAX_INTENSITY).
func _update_reactor_glow(ratio: float) -> void:
	if _reactor_material:
		_reactor_material.emission_energy_multiplier = REACTOR_MAX_INTENSITY * ratio
	if _joint_material:
		_joint_material.emission_energy_multiplier = JOINT_MAX_INTENSITY * ratio
	if _reactor_light:
		_reactor_light.light_energy = REACTOR_LIGHT_MAX_ENERGY * ratio


# ── Movement Helpers ─────────────────────────────────────────────────────

func _apply_movement(direction: Vector3, delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var is_moving := direction.length() > 0.1

	var effective_speed := speed * speed_multiplier

	if is_moving:
		velocity.x = direction.x * effective_speed
		velocity.z = direction.z * effective_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, effective_speed)
		velocity.z = move_toward(velocity.z, 0.0, effective_speed)

	if is_moving and _character:
		var target_angle := atan2(direction.x, direction.z)
		_character.rotation.y = lerp_angle(
			_character.rotation.y, target_angle, rotation_speed * delta
		)

	_update_locomotion_anim(is_moving, delta)
	move_and_slide()


func _update_locomotion_anim(is_moving: bool, delta: float) -> void:
	if not _anim_tree:
		return

	var move_blend: float = 1.0 if is_moving else 0.0
	_anim_tree.set("parameters/skate/blend_amount",
		lerp(float(_anim_tree.get("parameters/skate/blend_amount")), move_blend, 8.0 * delta))

	var locked := _is_action_locked()
	if is_moving and not locked:
		_stride_timer += delta
		if _stride_timer >= 5.0:
			_stride_timer = 0.0
			_stride_b = not _stride_b
	elif not is_moving and not locked:
		_stride_timer = 0.0
		_stride_b = false

	var stride_val: float = 1.0 if _stride_b else 0.0
	_anim_tree.set("parameters/skate_blend/blend_amount",
		lerp(float(_anim_tree.get("parameters/skate_blend/blend_amount")), stride_val, 6.0 * delta))
	_on_stride_updated(stride_val)


func _is_action_locked() -> bool:
	return false


func _on_stride_updated(_stride_val: float) -> void:
	pass


# ── Death ────────────────────────────────────────────────────────────────

## Kill this character: disable controls, explode into debris.
func die() -> void:
	if _dead:
		return
	_dead = true

	set_physics_process(false)
	set_process_unhandled_input(false)
	remove_from_group("characters")
	collision_layer = 0
	collision_mask = 0

	_explode_character()
	_on_died()


func _explode_character() -> void:
	if not _character:
		return

	var skeleton := _find_child_by_class(_character, &"Skeleton3D") as Skeleton3D
	if not skeleton:
		push_warning("CharacterBase.die: no Skeleton3D found")
		return

	var mesh_inst: MeshInstance3D = null
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			mesh_inst = child
			break

	if not mesh_inst:
		push_warning("CharacterBase.die: no MeshInstance3D under Skeleton3D")
		return

	var bodies := DeathExplode.explode(skeleton, mesh_inst)
	var scene_root := get_parent()
	for rb in bodies:
		scene_root.add_child(rb)
	DeathExplode.apply_burst(bodies, global_position)
	DeathExplode.schedule_cleanup(bodies)

	_anim_tree = null
	_character.queue_free()
	_character = null


## Override in subclasses for controller-specific cleanup.
func _on_died() -> void:
	pass


# ── Combat Helpers ───────────────────────────────────────────────────────────────

func get_reactor() -> Node:
	return get_node_or_null("ReactorCore")


## Execute a melee strike: find a target in range, build a [MeleeEvent]
## pre-loaded with the default [PunchEffect], emit [signal melee_strike]
## so status effects can mutate it, then apply the final effects.
func execute_melee() -> void:
	if _dead:
		return
	var target := _find_melee_target(punch_reach)
	if not target:
		return
	var target_reactor: Node = target.get_reactor() if target.has_method("get_reactor") else null
	if not target_reactor:
		return

	var event := MeleeEvent.new()
	event.user = self
	event.target = target
	event.effects.append(PunchEffect.new(punch_weight, 1, self))

	melee_strike.emit(event)

	if event.cancelled:
		return
	for effect in event.effects:
		target_reactor.apply_effect(effect)


func _find_melee_target(reach: float) -> Node:
	if not _character:
		return null
	var my_pos := global_position
	var forward := Vector3(
		sin(_character.rotation.y), 0.0, cos(_character.rotation.y)
	).normalized()

	var best: Node3D = null
	var best_dist := reach + 1.0
	for node in get_tree().get_nodes_in_group("characters"):
		if node == self:
			continue
		var body := node as Node3D
		if not body:
			continue
		var to_target := body.global_position - my_pos
		to_target.y = 0.0
		var dist := to_target.length()
		if dist > reach or dist < 0.01:
			continue
		if forward.dot(to_target.normalized()) < 0.5:
			continue
		if dist < best_dist:
			best = body
			best_dist = dist
	return best


# ── Utilities ────────────────────────────────────────────────────────────

func _apply_upper_body_filter(
	oneshot: AnimationNodeOneShot, ap: AnimationPlayer, anim_name: String,
) -> void:
	if not anim_name or not ap.has_animation(anim_name):
		return
	oneshot.filter_enabled = true
	var anim := ap.get_animation(anim_name)
	for i in anim.get_track_count():
		oneshot.set_filter_path(anim.track_get_path(i), true)


func _set_loop_mode(
	ap: AnimationPlayer, anim_name: String, mode: Animation.LoopMode,
) -> void:
	if anim_name and ap.has_animation(anim_name):
		ap.get_animation(anim_name).loop_mode = mode


func _find_child_by_class(root: Node, class_name_: StringName) -> Node:
	for child in root.get_children():
		if child.is_class(class_name_):
			return child
		var found := _find_child_by_class(child, class_name_)
		if found:
			return found
	return null
