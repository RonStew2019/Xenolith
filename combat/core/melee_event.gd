extends RefCounted
class_name MeleeEvent
## Mutable context object emitted with [signal CharacterBase.melee_strike].
##
## Status effects (especially [MeleeModifierEffect]s) can inspect and
## mutate this event before the effects are applied.  Use cases:
##   • Append extra effects    → event.effects.append(my_poison)
##   • Replace default effects → event.effects.clear(); event.effects.append(…)
##   • Cancel the strike       → event.cancelled = true

## The character performing the melee strike.
var user: Node = null

## The character being struck.
var target: Node = null

## Status effects that will be applied to [member target]'s reactor.
## Pre-populated with the default [PunchEffect]; modify freely.
var effects: Array = []

## Set to true to abort the strike entirely (no effects applied).
var cancelled: bool = false
