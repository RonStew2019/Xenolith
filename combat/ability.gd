extends RefCounted
class_name Ability
## Base class for abilities in the loadout system.
##
## An ability is a thin wrapper that ties a set of [StatusEffect]s to an
## input action.  Each effect targets either the user (SELF) or opponents
## (OTHER).  Self-effects are applied to the user's reactor when the
## ability activates; other-effects are made available to delivery
## mechanisms (melee modifiers, projectiles, areas, etc.).
##
## Punches are NOT abilities -- they are the universal base mechanic.
## Abilities modify punches by applying [MeleeModifierEffect]s (or other
## self-effects that hook into [signal CharacterBase.melee_strike]).
##
## [member activation_mode] determines how input maps to state:
##   INSTANT  -- fire once per press, no persistent state.
##   TOGGLE   -- press to activate, press again to deactivate.
##   HOLD     -- active while held, deactivates on release.
##
## The controller calls [method activate] on press and [method deactivate]
## on release for every ability.  The mode decides what actually happens.

enum ActivationMode {
	INSTANT,  ## Fire once, no persistent state (projectiles, one-shot buffs).
	TOGGLE,   ## Press on / press off (auras, stance switches).
	HOLD,     ## Active while held, stops on release.
}

## Human-readable name shown in UI / debug.
var ability_name: String = ""

## The input action this ability is bound to (e.g. "ability_1").
var input_action: String = ""

## How input translates to ability state.
var activation_mode: int = ActivationMode.INSTANT

## Whether the ability is currently active (TOGGLE / HOLD only).
var _active: bool = false

## Self-effects currently on the reactor, tracked for cleanup.
var _applied_effects: Array = []


## Override: return fresh [StatusEffect] instances to apply to the user.
func create_self_effects(_user: Node) -> Array:
	return []


## Override: return fresh [StatusEffect] instances for targets.
## Called by delivery mechanisms (melee modifiers, projectiles, etc.)
## each time delivery occurs, ensuring fresh mutable instances.
func create_other_effects(_user: Node) -> Array:
	return []


## Called when the bound input is pressed.
func activate(user: Node) -> void:
	var reactor := _get_reactor(user)
	if not reactor:
		return
	match activation_mode:
		ActivationMode.INSTANT:
			_apply_effects(user, reactor)
		ActivationMode.TOGGLE:
			if _active:
				_remove_effects(reactor)
				_active = false
			else:
				_apply_effects(user, reactor)
				_active = true
		ActivationMode.HOLD:
			if not _active:
				_apply_effects(user, reactor)
				_active = true


## Called when the bound input is released.
## Only HOLD abilities respond -- TOGGLE deactivates via [method activate].
func deactivate(user: Node) -> void:
	if not _active or activation_mode != ActivationMode.HOLD:
		return
	var reactor := _get_reactor(user)
	if reactor:
		_remove_effects(reactor)
	_active = false


## Force-remove applied effects regardless of mode (death, loadout swap).
func force_deactivate(user: Node) -> void:
	if not _active:
		return
	var reactor := _get_reactor(user)
	if reactor:
		_remove_effects(reactor)
	_applied_effects.clear()
	_active = false


func is_active() -> bool:
	return _active


## Return a fresh, independent copy of this ability bound to the same
## input action.  Works for any subclass whose _init takes a single
## optional String (the input action) — which all current abilities do.
func duplicate_ability() -> Ability:
	return get_script().new(input_action)


# -- Internals -------------------------------------------------------------

func _get_reactor(user: Node) -> Node:
	return user.get_reactor() if user.has_method("get_reactor") else null


func _apply_effects(user: Node, reactor: Node) -> void:
	var effects := create_self_effects(user)
	for effect in effects:
		reactor.apply_effect(effect)
	# INSTANT effects are fire-and-forget; their lifetime is self-managed.
	if activation_mode != ActivationMode.INSTANT:
		_applied_effects.append_array(effects)


func _remove_effects(reactor: Node) -> void:
	for effect in _applied_effects:
		reactor.remove_effect(effect)
	_applied_effects.clear()
