class_name ResonancePillar
extends StaticBody3D

## The resonance pillar entity — a stationary anchor spawned by
## [code]ResonancePillarAbility[/code] when its projectile impacts terrain.
##
## [b]Phase 1.4 skeleton.[/b] This file currently exists only to satisfy the
## architectural-prep requirement that a pillar expose a [method get_reactor]
## accessor, so reactor-lookup code (see [code]AoeAbility._deliver_aoe_at[/code],
## which does [code]body.get_reactor() if body.has_method("get_reactor") else null[/code]
## and skips on null) can treat pillars uniformly with characters without
## special-casing.
##
## [b]Phase 2.2[/b] will flesh this out with:
## [br]- real [code]ReactorCore[/code] instantiation (with
## [code]break_on_breach_deletes_host[/code] so a breached pillar frees itself)
## [br]- collision shape and visual mesh
## [br]- joining the [code]"characters"[/code] group so AoE scans pick it up
## [br]- signal subscriptions to the caster's Slot 1/2/3 abilities so the pillar
## mirrors their activations at its own position
## [br]- [method _exit_tree] disconnects to unwire those signals cleanly
##
## Until Phase 2.2 lands, [member _reactor] stays [code]null[/code] and
## [method get_reactor] returns [code]null[/code] — which is deliberately
## harmless given the null-check in every call site.

## The character that spawned this pillar. Attribution anchor for any
## effects the pillar applies on its caster's behalf. Populated by
## [code]ResonancePillarAbility[/code] on spawn (Phase 2.2).
var caster: Node = null

## The pillar's own [code]ReactorCore[/code]. Null in this skeleton; Phase 2.2
## will instantiate a real reactor here so the pillar is a valid damage target.
var _reactor: Node = null


## Duck-typed reactor accessor. Mirrors the contract that
## [code]CharacterBase[/code] exposes, so reactor-lookup code (e.g.
## [code]AoeAbility._deliver_aoe_at[/code]) can resolve a pillar's reactor
## the same way it resolves a character's. Returns [code]null[/code] until
## Phase 2.2 assigns a real [code]ReactorCore[/code] to [member _reactor];
## callers are expected to null-check the result.
func get_reactor() -> Node:
	return _reactor
