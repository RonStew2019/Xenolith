extends CharacterBase
class_name CloneMech
## Dual-mode entity: AI combat by default, switchable to full player control.
##
## Spawned by [CloneAbility].  AI behavior lives in swappable
## [AIController] children — [CombatAI] by default, [PlayerAI] when
## the user takes over via [method enable_player_control].  Swap at
## any time with [method set_controller].
##
## The combat controller fights autonomously using a priority-based
## state machine: FLEE (tunnel away at high heat) > CLONE (spawn
## sub-clones when able) > ATTACK (punch in melee range) > ENGAGE
## (activate ability_1 within 5m) > SEEK (chase nearest enemy) >
## IDLE (wander when no targets exist).  Clones only attack non-family
## characters (those not sharing the same root ancestor).
##
## When the controlling player dies, [method enable_player_control] is
## called on a surviving family member and the clone becomes the new
## player avatar — camera, HUD, and all.  The camera pivot and HUD
## layer are owned by [PlayerAI] but mirrored onto the host fields
## ([member _camera_pivot], [member _hud_layer]) so external systems
## ([TunnelEffect], [ProjectileAbility]) can still find them.
##
## Clones copy the parent's full ability loadout (including CloneAbility
## itself) so multi-generational cloning is possible.  Reactor capacity
## return on death is handled by [StatTransferOnDeathEffect], applied by
## [CloneEffect].

# -- Exports ---------------------------------------------------------------

@export var mouse_sensitivity: float = 0.002
@export var pitch_min_deg: float = -60.0
@export var pitch_max_deg: float = 40.0
@export var jump_velocity: float = 4.5
@export var punch_apex_delay: float = 0.30

# -- State -----------------------------------------------------------------

var _reactor: Node
var _loadout: Loadout
var _hud_layer: CanvasLayer          ## owned by PlayerAI; null while AI-controlled
var _camera_pivot: Node3D            ## owned by PlayerAI; null while AI-controlled (needed by TunnelEffect!)
var _interaction_prompt: InteractionPrompt  ## owned by PlayerAI; null while AI-controlled

var _active_controller: AIController


## Convenience flag — true while a [PlayerAI] is the active controller.
## Kept as a property (not a raw var) so external references
## (e.g. [code]tunnel_node.gd[/code]) continue to work unchanged.
var is_player_controlled: bool:
	get:
		return _active_controller is PlayerAI


# ── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	super._ready()  # CharacterBase: loads model, animations, reactor glow
	_create_collision_shape()
	_setup_reactor()
	_setup_loadout()
	set_controller(CombatAI.new())


func _create_collision_shape() -> void:
	var col := CollisionShape3D.new()
	col.shape = CapsuleShape3D.new()
	col.transform.origin = Vector3(0, 0.82, 0)
	add_child(col)


func _setup_reactor() -> void:
	_reactor = ReactorCore.new()
	_reactor.name = "ReactorCore"
	_reactor.enable_ambient_venting = true  # Instead of suppressing venting we'll add weight to status transfer to parent
	add_child(_reactor)
	_reactor.reactor_breached.connect(die)
	_bind_reactor_glow(_reactor)


func _setup_loadout() -> void:
	_loadout = Loadout.new()
	if clone_parent and clone_parent.get("_loadout"):
		_loadout = clone_parent._loadout.duplicate_loadout()
	else:
		# Fallback for orphan clones (shouldn't happen, but safety)
		_loadout.add_ability(EnvenomAbility.new("ability_1"))
		_loadout.add_ability(TunnelAbility.new("ability_2"))
		_loadout.add_ability(CoilAbility.new("ability_3"))
		_loadout.add_ability(CloneAbility.new("ability_4"))


# ── AI delegation & swap API ─────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _active_controller:
		_active_controller.tick(delta)


## Hot-swap this clone's active controller. The outgoing controller's
## [method AIController.on_exit] runs before the incoming controller's
## [method AIController.on_enter].  Pass [code]null[/code] to detach
## the current controller without replacing it (used by
## [method _try_transfer_control] to release the PlayerAI before the
## receiving clone spins up its own).
func set_controller(new_controller: AIController) -> void:
	if _active_controller:
		_active_controller.on_exit()
		_active_controller.queue_free()
		_active_controller = null
	if new_controller:
		_active_controller = new_controller
		new_controller.host = self
		add_child(new_controller)
		new_controller.on_enter()


# ── Animation Extensions (mirrors player.gd) ────────────────────────────

func _configure_animation_loops(anim_player: AnimationPlayer) -> void:
	_set_loop_mode(anim_player, _anim_names.get("JabLB", ""), Animation.LOOP_NONE)
	_set_loop_mode(anim_player, _anim_names.get("JabRB", ""), Animation.LOOP_NONE)
	_set_loop_mode(anim_player, _anim_names.get("JabL", ""), Animation.LOOP_NONE)
	_set_loop_mode(anim_player, _anim_names.get("JabR", ""), Animation.LOOP_NONE)


func _extend_anim_tree(
	tree: AnimationNodeBlendTree,
	anim_player: AnimationPlayer,
	base_output: StringName,
) -> StringName:
	var jab_l_a := AnimationNodeAnimation.new()
	jab_l_a.animation = _anim_names.get("JabL", &"JabL")
	tree.add_node(&"jab_l_a", jab_l_a)

	var jab_l_b := AnimationNodeAnimation.new()
	jab_l_b.animation = _anim_names.get("JabLB", &"JabLB")
	tree.add_node(&"jab_l_b", jab_l_b)

	var jab_l_blend := AnimationNodeBlend2.new()
	tree.add_node(&"hook_l", jab_l_blend)
	tree.connect_node(&"hook_l", 0, &"jab_l_a")
	tree.connect_node(&"hook_l", 1, &"jab_l_b")

	var oneshot_l := AnimationNodeOneShot.new()
	oneshot_l.fadein_time = 0.05
	oneshot_l.fadeout_time = 0.15
	_apply_upper_body_filter(oneshot_l, anim_player, _anim_names.get("JabL", ""))
	tree.add_node(&"oneshot_l", oneshot_l)
	tree.connect_node(&"oneshot_l", 0, base_output)
	tree.connect_node(&"oneshot_l", 1, &"hook_l")

	var jab_r_a := AnimationNodeAnimation.new()
	jab_r_a.animation = _anim_names.get("JabR", &"JabR")
	tree.add_node(&"jab_r_a", jab_r_a)

	var jab_r_b := AnimationNodeAnimation.new()
	jab_r_b.animation = _anim_names.get("JabRB", &"JabRB")
	tree.add_node(&"jab_r_b", jab_r_b)

	var jab_r_blend := AnimationNodeBlend2.new()
	tree.add_node(&"cross_r", jab_r_blend)
	tree.connect_node(&"cross_r", 0, &"jab_r_a")
	tree.connect_node(&"cross_r", 1, &"jab_r_b")

	var oneshot_r := AnimationNodeOneShot.new()
	oneshot_r.fadein_time = 0.05
	oneshot_r.fadeout_time = 0.15
	_apply_upper_body_filter(oneshot_r, anim_player, _anim_names.get("JabR", ""))
	tree.add_node(&"oneshot_r", oneshot_r)
	tree.connect_node(&"oneshot_r", 0, &"oneshot_l")
	tree.connect_node(&"oneshot_r", 1, &"cross_r")

	return &"oneshot_r"


func _is_action_locked() -> bool:
	if not _anim_tree:
		return false
	return bool(_anim_tree.get("parameters/oneshot_l/active")) \
		or bool(_anim_tree.get("parameters/oneshot_r/active"))


func _on_stride_updated(stride_val: float) -> void:
	if _anim_tree:
		_anim_tree.set("parameters/hook_l/blend_amount", stride_val)
		_anim_tree.set("parameters/cross_r/blend_amount", stride_val)


# ── Combat helpers (called by AIControllers) ───────────────────────────

## Schedule the hit-check to fire at the animation apex instead of frame-0.
func _schedule_punch_hit() -> void:
	if punch_apex_delay <= 0.0:
		execute_melee()
		return
	get_tree().create_timer(punch_apex_delay, false).timeout.connect(execute_melee)


## Activate an ability from the loadout by its input action.
func _activate_ability(action: String) -> void:
	var ability := _loadout.get_ability_for_action(action)
	if not ability:
		return
	ability.activate(self)


## Deactivate an ability (input released). Only matters for HOLD abilities.
func _deactivate_ability(action: String) -> void:
	var ability := _loadout.get_ability_for_action(action)
	if not ability:
		return
	ability.deactivate(self)


# ── Player Control Transfer ─────────────────────────────────────────────

## Switch this clone from AI to full player control by swapping in a
## fresh [PlayerAI].  Its [method PlayerAI.on_enter] builds the camera,
## HUD, and captures the mouse.
func enable_player_control() -> void:
	set_controller(PlayerAI.new())


## Transfer control to a living clone when this clone dies.
## Tears down our own PlayerAI (camera/HUD via its on_exit) before the
## receiving clone spins up its own, so we don't double-up on inputs.
func _try_transfer_control() -> bool:
	if not is_player_controlled:
		return false
	var target := _find_living_clone_in_family()
	if not target:
		return false
	# Release our PlayerAI (camera/HUD cleanup happens in on_exit).
	set_controller(null)
	target.enable_player_control()
	return true


# ── Death ────────────────────────────────────────────────────────────────

## Override [method CharacterBase.die] to perform structural family-tree
## cleanup (re-parent orphans, erase self from parent) BEFORE the reactor
## shuts down and triggers [StatTransferOnDeathEffect].  This ensures the
## [code]clone_parent[/code] chain is intact for ancestor-walking fallback.
func die() -> void:
	if _dead:
		return
	_reparent_orphan_children()
	if clone_parent and is_instance_valid(clone_parent):
		clone_parent.clone_children.erase(self)
	super.die()


## Re-parent our living clone children to our own [member clone_parent]
## (their grandparent) so the family tree stays connected after we die.
## Keeps [method _find_living_clone_in_family] and
## [StatTransferOnDeathEffect] ancestor-walking working correctly for
## multi-generational clones.
func _reparent_orphan_children() -> void:
	var grandparent: Node = clone_parent if is_instance_valid(clone_parent) else null
	for child in clone_children.duplicate():
		if is_instance_valid(child):
			child.clone_parent = grandparent
			if grandparent:
				grandparent.clone_children.append(child)
	clone_children.clear()


func _on_died() -> void:
	# Only reached when control wasn't transferred to a living clone.
	# super.die() already disabled _unhandled_input on this body, but our
	# input handlers now live on the PlayerAI child — stop them too so
	# the dead shell doesn't keep rotating its camera / firing abilities.
	if _active_controller:
		_active_controller.set_process_unhandled_input(false)
	# If we were the player at time of death, release the mouse.
	if is_player_controlled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
