extends StaticBody3D
class_name CombatTarget
## A [StaticBody3D] that participates in the combat pipeline.
##
## Attach a [ReactorCore] as a child; this script provides the
## [code]get_reactor()[/code] / [code]_dead[/code] interface that melee,
## projectiles, and AoE scans expect.
##
## The [ReactorCore] is NOT created here — the caller is responsible for
## building and adding a properly-configured ReactorCore child via
## [method setup_reactor] or by adding one manually before this node
## enters the tree.
##
## On [method _ready] the node joins the [code]"characters"[/code] group
## and locates its child ReactorCore.  When the reactor emits
## [signal ReactorCore.reactor_breached], [member _dead] is set to
## [code]true[/code] and the node is removed from the group so live
## scans skip it immediately.

# -- State -----------------------------------------------------------------

## Liveness gate required by the reactor-host contract (see
## [code]reactor_core.gd[/code]).  AoE / projectile / AI scanners read
## this via [code]node.get("_dead")[/code] to skip dead targets.
var _dead: bool = false

## Human-readable name for UI / debug (e.g. "Player Carrier", threat name).
var display_name: StringName = &""

## Cached reference to the child [ReactorCore].
var _reactor: ReactorCore = null


# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	add_to_group("characters")
	# Locate existing ReactorCore child (may have been added before _ready).
	for child in get_children():
		if child is ReactorCore:
			_reactor = child
			break
	if _reactor != null:
		_reactor.reactor_breached.connect(_on_reactor_breached)
	else:
		push_warning("CombatTarget '%s': no ReactorCore child found." % display_name)


# -- Public API ------------------------------------------------------------

## Returns the child [ReactorCore], or [code]null[/code] if none was added.
func get_reactor() -> Node:
	return _reactor


## Convenience — create, configure, and attach a [ReactorCore] child.
## Call BEFORE adding this node to the scene tree so the reactor's own
## [method _ready] observes the final values.
##
## [param p_max_integrity] — reactor integrity ceiling.[br]
## [param p_max_heat] — heat ceiling before overflow starts damaging integrity.
func setup_reactor(p_max_integrity: float, p_max_heat: float) -> ReactorCore:
	var reactor := ReactorCore.new()
	reactor.name = "ReactorCore"
	reactor.max_integrity = p_max_integrity
	reactor.max_heat = p_max_heat
	# DO NOT set break_on_breach_deletes_host — EngagementManager handles
	# destruction of arena targets.
	add_child(reactor)
	# If _ready already ran (late setup), wire up manually.
	if _reactor == null:
		_reactor = reactor
		_reactor.reactor_breached.connect(_on_reactor_breached)
	return reactor


# -- Internal --------------------------------------------------------------

func _on_reactor_breached() -> void:
	_dead = true
	if is_in_group("characters"):
		remove_from_group("characters")
