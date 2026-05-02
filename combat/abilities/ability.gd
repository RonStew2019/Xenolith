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
##
## [b]Lifecycle signals[/b] -- [signal activated] and [signal deactivated]
## fire on genuine state transitions only, so external listeners (e.g. the
## ResonancePillar mirroring Slot 1/2/3 behaviour) can track active state
## without bookkeeping of their own.  The contract per mode is:
##
##   INSTANT -- [signal activated] fires every successful press.
##              [signal deactivated] never fires (there is no "off" state).
##   TOGGLE  -- [signal activated] fires on the false -> true press.
##              [signal deactivated] fires on the true -> false second press
##              (dispatched from inside [method activate]).
##   HOLD    -- [signal activated] fires on the false -> true press.
##              Repeat presses while already active are idempotent and emit
##              nothing.  [signal deactivated] fires on release via
##              [method deactivate] only when [member _active] actually
##              transitions true -> false.
##
## [method force_deactivate] emits [signal deactivated] iff the ability was
## active at call time; calling it on an inactive ability is a silent no-op.
## If [method activate] cannot resolve the user's reactor it bails before
## any state change and emits nothing.

## Emitted whenever the ability genuinely transitions to active (or fires,
## for INSTANT).  Never emitted on idempotent re-presses.
signal activated(user: Node)

## Emitted whenever the ability genuinely transitions from active to
## inactive (TOGGLE second-press, HOLD release, or [method force_deactivate]
## on a previously-active ability).  Never emitted for INSTANT abilities.
signal deactivated(user: Node)

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


## Called once when the ability is first equipped in a loadout on a specific
## user.  Override for abilities that need to set up initial state (e.g.
## passive buffs that exist before the first activation).
## Base implementation is a no-op.
func on_equip(_user: Node) -> void:
	pass


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
			activated.emit(user)
		ActivationMode.TOGGLE:
			if _active:
				_remove_effects(reactor)
				_active = false
				deactivated.emit(user)
			else:
				_apply_effects(user, reactor)
				_active = true
				activated.emit(user)
		ActivationMode.HOLD:
			if not _active:
				_apply_effects(user, reactor)
				_active = true
				activated.emit(user)


## Called when the bound input is released.
## Only HOLD abilities respond -- TOGGLE deactivates via [method activate].
func deactivate(user: Node) -> void:
	if not _active or activation_mode != ActivationMode.HOLD:
		return
	var reactor := _get_reactor(user)
	if reactor:
		_remove_effects(reactor)
	_active = false
	deactivated.emit(user)


## Force-remove applied effects regardless of mode (death, loadout swap).
func force_deactivate(user: Node) -> void:
	if not _active:
		return
	var reactor := _get_reactor(user)
	if reactor:
		_remove_effects(reactor)
	_applied_effects.clear()
	_active = false
	deactivated.emit(user)


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
