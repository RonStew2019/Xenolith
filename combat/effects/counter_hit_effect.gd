extends StatusEffect
class_name CounterHitEffect
## Tracks every incoming status effect for 10 ticks, then on expiry
## broadcasts copies of those effects to every character within 10m.
## A defensive "turn your damage against your neighbors" ability.
##
## Self-applied: the caster slaps this on themselves.  During its 10-tick
## lifetime, every non-refresh status effect applied to the caster's
## [ReactorCore] is recorded.  When Counter-Hit expires (or is manually
## removed), each recorded effect is duplicated via its own
## [method StatusEffect.duplicate_for_broadcast] (which subclasses override
## to control or refuse) and applied to every other living character within
## 10m horizontally.  Effects that opt out (e.g. [TunnelEffect],
## [CloneEffect]) are skipped.  The clones'
## [member StatusEffect.source] is the original Counter-Hit caster, so
## damage numbers and kill attribution land on the right mech.

## Horizontal radius (metres) of the broadcast burst on expiry.
const AOE_RADIUS: float = 10.0

## Effects recorded during our lifetime, in apply-order.  Each entry is a
## dictionary: { "effect": StatusEffect, "duration": int }.  We snapshot
## the duration at apply-time so the broadcast replays the original full
## duration regardless of how far the recorded effect ticked down during
## our 10-tick window.  Cleared on remove.
var _recorded: Array = []

## Cached reactor reference so we can disconnect cleanly even if the
## caller tears down the parent before us.
var _reactor: Node = null


func _init(p_source: Node = null) -> void:
	super._init("Counter-Hit", 10.0, 10, p_source, false, true)


func on_apply(reactor: Node) -> void:
	_reactor = reactor
	# Defensive init — declaration default should already cover this,
	# but a recycled instance could arrive with stale state.
	if _recorded == null:
		_recorded = []
	else:
		_recorded.clear()

	if reactor.has_signal("effect_applied"):
		if not reactor.effect_applied.is_connected(_on_effect_applied):
			reactor.effect_applied.connect(_on_effect_applied)


func on_remove(reactor: Node) -> void:
	# 1. Disconnect first so the broadcast we're about to do can't
	#    feed back into our own recorder.
	if is_instance_valid(_reactor) and _reactor.has_signal("effect_applied"):
		if _reactor.effect_applied.is_connected(_on_effect_applied):
			_reactor.effect_applied.disconnect(_on_effect_applied)
	_reactor = null

	# 2. Caster == target for a self-applied Counter-Hit.  Use
	#    reactor.get_parent() to stay aligned with AoeAbility.
	var caster := reactor.get_parent()
	if not caster:
		_recorded.clear()
		return
	var tree := caster.get_tree()
	if not tree:
		_recorded.clear()
		return

	var origin: Vector3 = caster.global_position
	for node in tree.get_nodes_in_group("characters"):
		if node == caster:
			continue
		var body := node as Node3D
		if not body:
			continue
		if body.get("_dead"):
			continue

		# Horizontal range check (mirrors AoeAbility._deliver_aoe_at).
		var offset := body.global_position - origin
		offset.y = 0.0
		var dist := offset.length()
		if dist > AOE_RADIUS or dist < 0.01:
			continue

		var target_reactor: Node = body.get_reactor() if body.has_method("get_reactor") else null
		if not target_reactor:
			continue

		# Fresh clone per target so each victim's ReactorCore owns an
		# independent RefCounted instance.
		for entry in _recorded:
			var fresh: StatusEffect = entry.effect.duplicate_for_broadcast(source)
			if fresh == null:
				continue  # Effect opted out of being broadcast.
			fresh.duration = entry.duration  # Restore the originally-applied duration.
			target_reactor.apply_effect(fresh)

	_recorded.clear()


## Records every fresh status effect applied to our reactor while we're
## active.  Skips refreshes (existing-effect duration bumps) and skips
## the Counter-Hit instance itself as belt-and-braces defence.
func _on_effect_applied(effect: StatusEffect, is_refresh: bool) -> void:
	# Never record our own application event.
	if effect == self:
		return
	# Refreshes aren't fresh effects — they're duration bumps on an
	# already-active instance.  Recording them would double-count.
	if is_refresh:
		return
	# Extra safety: never record another Counter-Hit (non-stackable
	# means this shouldn't happen, but cheap to guard).
	if effect.effect_name == effect_name:
		return
	# Environmental effects (Ambient Venting, SelfRepair) have no source —
	# nothing to "reflect back" semantically.
	if effect.source == null:
		return
	# Self-applied effects (our own toggles, modifiers) shouldn't be reflected.
	# `target` is set by ReactorCore.apply_effect during on_apply, before any
	# signals fire, so it's reliably populated here.
	if effect.source == target:
		return
	_recorded.append({ "effect": effect, "duration": effect.duration })


## Reflectors must not reflect themselves — would cause cascading recursive broadcasts.
func duplicate_for_broadcast(_new_source: Node) -> StatusEffect:
	return null
