extends "res://combat/abilities/ability.gd"
class_name AoeAbility
## Reusable base for abilities that deliver effects to every valid character
## inside a horizontal radius around an arbitrary spatial origin.
##
## Historically this was [code]AoeCasterAbility[/code] and always burst from
## the caster's own position. It has since been generalised: the delivery
## core is [method _deliver_aoe_at], which takes an explicit [code]origin[/code]
## so non-caster entities (e.g. resonance pillars, turrets, zones) can reuse
## the same scan+apply pipeline from their own positions while still
## attributing effects back to a [code]user[/code] Node.
##
## Handles the full AOE pipeline: scan the "characters" group, skip
## [code]user[/code] / dead / out-of-range, fetch each target's
## [ReactorCore], and apply fresh [StatusEffect] instances from
## [method create_other_effects].
##
## Subclasses only need to:
##   1. Set [member aoe_radius] (metres, horizontal).
##   2. Override [method create_other_effects] to return the effects each
##      target should receive.
##
## The default [method activate] override bursts from the caster
## ([code]user.global_position[/code]) via the [method _deliver_aoe] wrapper.
## Subclasses (or external callers such as a pillar replicating this
## ability) may call [method _deliver_aoe_at] directly with any origin.
##
## Self-effects ([method create_self_effects]) are handled normally by the
## parent [Ability] pipeline — they apply to the caster's own reactor.
##
## Supports all activation modes:
##   [b]INSTANT[/b]  — one burst per press.
##   [b]TOGGLE[/b]   — burst fires on activation; deactivation only removes
##                      self-effects (delivered AOE effects are fire-and-forget).
##   [b]HOLD[/b]     — same as TOGGLE for the initial burst.
##
## Effects returned by [method create_other_effects] receive [code]user[/code]
## as the [code]source[/code] argument, so directional effects (e.g.
## [KnockbackEffect]) can compute push vectors from origin → target in
## their [method StatusEffect.on_apply].

## Horizontal radius (metres) of the area-of-effect burst.
var aoe_radius: float = 5.0


func activate(user: Node) -> void:
	# Snapshot activation state so we know whether super triggers an
	# activation (TOGGLE/HOLD) or a deactivation (TOGGLE second press).
	var was_active := _active
	super.activate(user)

	# Deliver the AOE burst only when the ability transitions to active
	# (or fires instantly).  TOGGLE second-press / HOLD release paths
	# skip this so the burst is a one-shot per activation cycle.
	var just_activated := _active and not was_active
	if activation_mode == ActivationMode.INSTANT or just_activated:
		_deliver_aoe(user)


# -- Internals -------------------------------------------------------------

## Caster-centred delivery. Thin wrapper around [method _deliver_aoe_at]
## that uses the caster's own position as the burst origin. Preserved so
## existing subclasses (KnockbackAbility, etc.) keep working unchanged.
func _deliver_aoe(user: Node) -> void:
	_deliver_aoe_at(user.global_position, user)


## Scan for targets around [code]origin[/code] and apply other-effects to
## each valid one. [code]user[/code] is the attribution / self-exclusion
## anchor — it is passed to [method create_other_effects] and also used to
## skip the caster from the target list even when bursting from a remote
## origin (e.g. a pillar replicating an ability on behalf of its caster).
func _deliver_aoe_at(origin: Vector3, user: Node) -> void:
	var tree := user.get_tree()
	if not tree:
		return

	for node in tree.get_nodes_in_group("characters"):
		if node == user:
			continue
		var body := node as Node3D
		if not body:
			continue
		if body.get("_dead"):
			continue

		# Horizontal range check.
		var offset := body.global_position - origin
		offset.y = 0.0
		var dist := offset.length()
		if dist > aoe_radius or dist < 0.01:
			continue

		# Fetch target's reactor.
		var reactor: Node = body.get_reactor() if body.has_method("get_reactor") else null
		if not reactor:
			continue

		# Fresh effects per target — each instance is independent.
		var effects := create_other_effects(user)
		for effect in effects:
			reactor.apply_effect(effect)
