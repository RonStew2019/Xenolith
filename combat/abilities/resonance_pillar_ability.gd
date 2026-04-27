extends ProjectileAbility
class_name ResonancePillarAbility
## Slot 4 of the "Resonance Mk.I" loadout.
##
## INSTANT-mode projectile ability: fires a [PersistentProjectile] that
## carries [b]no effect payload[/b] — the projectile's job is to anchor
## itself to terrain on impact and hand off to a [ResonancePillar] spawn
## at the impact position. The pillar spawn [i]is[/i] the payload.
##
## [b]Cost:[/b] 15.0 heat (1-tick [StatusEffect]) applied to the caster's
## own reactor on each press, matching the existing cost-effect pattern
## used by [MortarAbility] / [BlasterAbility].
##
## [b]Cleanup — Q1 (resonance_pillar.md):[/b] pillars despawn on caster
## death / loadout swap. Spawned pillars are tracked here via [WeakRef]
## so [method force_deactivate] can iterate and [code]queue_free[/code]
## each one that's still alive. Natural teardown (reactor breach via
## [member ReactorCore.break_on_breach_deletes_host]) leaves a stale ref
## in the list — the [code]get_ref[/code] / [code]is_instance_valid[/code]
## guard in [method force_deactivate] handles it cleanly.
##
## [b]Tracking mechanism:[/b] we connect to each projectile's
## [signal Node.tree_exiting] signal. That signal fires BEFORE the node
## actually leaves the tree, so any pillar the projectile spawned in
## [code]_on_body_entered[/code] (via [code]_spawn_pillar_at[/code], which
## adds the pillar to the scene before [code]queue_free[/code]) is still
## findable via the [code]"characters"[/code] group that pillars join in
## [code]ResonancePillar._ready[/code]. We filter by
## [code]caster == user[/code] and dedupe against the existing list so
## fizzled (lifetime-expired, no-impact) projectiles silently no-op and
## multi-pillar scenarios track each new pillar exactly once.
##
## [b]Forward reference — Phase 3/4/5:[/b] the spawned pillar subscribes
## to its caster's Slot 1 / Slot 2 / Slot 3 ability signals and replicates
## their behavior from the pillar's own position. All of that wiring
## lives on [ResonancePillar] itself — this ability is [b]only[/b]
## responsible for spawn-and-cleanup lifecycle.

## Pillars this ability has spawned for any user, tracked as [WeakRef]s
## so natural breach-deletion of a pillar doesn't leave a dangling strong
## reference. Iterated (and cleared) in [method force_deactivate].
var _spawned_pillars: Array = []


func _init(p_input: String = "ability_4") -> void:
	ability_name = "Resonance Pillar"
	input_action = p_input
	activation_mode = ActivationMode.INSTANT
	projectile_speed = 25.0
	projectile_lifetime = 4.0


func create_self_effects(user: Node) -> Array:
	return [StatusEffect.new("Pillar Cost", 15.0, 1, user, true, false)]


# -- Overrides -------------------------------------------------------------

## Override the base [method ProjectileAbility._fire_projectile] to spawn
## a [PersistentProjectile] (no effect payload) rather than the default
## [Projectile] (which carries a [code]create_other_effects[/code] payload
## to the first character hit). Aim direction and spawn position reuse
## the base-class helpers so pillars spawn from the same chest-height /
## forward-offset position as every other projectile.
func _fire_projectile(user: Node) -> void:
	var tree := user.get_tree()
	if not tree:
		return

	var direction := _get_aim_direction(user)

	var proj := PersistentProjectile.new()
	proj.setup(user, direction, projectile_speed, projectile_lifetime)

	# Add to tree first so global_position is valid.
	tree.current_scene.add_child(proj)
	proj.global_position = _get_spawn_position(user, direction)

	# Register pillar-tracking hook: when the projectile exits the tree
	# (terrain impact OR lifetime fizzle), scan for any newly-spawned
	# pillar it produced and claim it for force_deactivate cleanup.
	# Using tree_exiting (not tree_exited) so the pillar — which was
	# added to the scene inside _on_body_entered BEFORE queue_free ran —
	# is still present in the tree at callback time.
	proj.tree_exiting.connect(_on_projectile_exiting.bind(user))


## Force-remove all pillars this ability has spawned for the user, then
## delegate to the base class for [code]_active[/code] /
## [code]_applied_effects[/code] bookkeeping. Called by
## [method Loadout.deactivate_all] on caster death / loadout swap
## (Q1 in resonance_pillar.md).
##
## Stale [WeakRef]s (pillars that already self-destructed via reactor
## breach) are filtered out by the [code]get_ref[/code] /
## [code]is_instance_valid[/code] guard. The tracked list is cleared
## unconditionally afterwards so subsequent reactivations start fresh.
func force_deactivate(user: Node) -> void:
	for weak in _spawned_pillars:
		var pillar: Node = weak.get_ref()
		if pillar and is_instance_valid(pillar) and not pillar.is_queued_for_deletion():
			pillar.queue_free()
	_spawned_pillars.clear()
	super.force_deactivate(user)


# -- Internals -------------------------------------------------------------

## Handler for each spawned [PersistentProjectile]'s [signal Node.tree_exiting].
## Scans the [code]"characters"[/code] group for any [ResonancePillar]
## whose [member ResonancePillar.caster] matches [param user] and that
## isn't already tracked, appending it as a [WeakRef]. Fizzled projectiles
## (no impact → no pillar) find nothing untracked and no-op.
func _on_projectile_exiting(user: Node) -> void:
	if not is_instance_valid(user):
		return
	var tree := user.get_tree()
	if not tree:
		return
	for node in tree.get_nodes_in_group("characters"):
		if not (node is ResonancePillar):
			continue
		var pillar: ResonancePillar = node
		if pillar.caster != user:
			continue
		if _is_pillar_tracked(pillar):
			continue
		_spawned_pillars.append(weakref(pillar))


## Linear scan of [member _spawned_pillars] for an existing [WeakRef]
## pointing at [param pillar]. Stale refs ([code]get_ref[/code] returns
## null) compare unequal to the live pillar and are skipped cleanly.
func _is_pillar_tracked(pillar: ResonancePillar) -> bool:
	for weak in _spawned_pillars:
		if weak.get_ref() == pillar:
			return true
	return false
