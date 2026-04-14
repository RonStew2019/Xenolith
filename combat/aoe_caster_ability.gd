extends Ability
class_name AoeCasterAbility
## Reusable base for abilities that deliver effects in an area around the
## caster.  Handles the full AOE pipeline: scan the "characters" group,
## skip self / dead / out-of-range, fetch each target's [ReactorCore],
## and apply fresh [StatusEffect] instances from [method create_other_effects].
##
## Subclasses only need to:
##   1. Set [member aoe_radius] (metres, horizontal).
##   2. Override [method create_other_effects] to return the effects each
##      target should receive.
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
## [KnockbackEffect]) can compute push vectors from caster → target in
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

## Scan for targets and apply other-effects to each valid one.
func _deliver_aoe(user: Node) -> void:
	var tree := user.get_tree()
	if not tree:
		return

	var origin: Vector3 = user.global_position
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
