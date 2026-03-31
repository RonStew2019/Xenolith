extends StatusEffect
class_name StatTransferOnDeathEffect
## Transfers the host reactor's stats to a designated target's reactor when
## the host dies ([signal ReactorCore.reactor_breached]).
##
## On death the host's [member ReactorCore.max_heat],
## [member ReactorCore.max_integrity], remaining
## [member ReactorCore.integrity], and current [member ReactorCore.heat]
## are added to the target's reactor (integrity clamped to the new max).
##
## Permanent duration (-1) — lives until the host dies or the effect is
## manually removed.  Zero heat — purely reactive, no tick cost.
##
## Stackable: multiple instances with different targets can coexist
## (e.g. two vampires both receiving stats when the same enemy dies).

## The entity whose reactor receives the transferred stats on death.
var target: Node = null

## Cached reference to the reactor this effect is applied to (ReactorCore).
var _host_reactor: Node = null


func _init(
	p_target: Node = null,
	p_source: Node = null,
	p_heat: float = 0.0,
	p_duration: int = -1,
	p_is_show_dmg: bool = true,
) -> void:
	super._init("StatTransferOnDeath", p_heat, p_duration, p_source, false, true, p_is_show_dmg)
	target = p_target


func on_apply(reactor: Node) -> void:
	_host_reactor = reactor
	if not reactor.reactor_breached.is_connected(_on_reactor_breached):
		reactor.reactor_breached.connect(_on_reactor_breached, CONNECT_ONE_SHOT)


func on_remove(reactor: Node) -> void:
	if is_instance_valid(reactor) and reactor.reactor_breached.is_connected(_on_reactor_breached):
		reactor.reactor_breached.disconnect(_on_reactor_breached)
	_host_reactor = null


## Callback fired when the host reactor breaches (integrity reaches zero).
func _on_reactor_breached() -> void:
	_transfer_stats()


## Performs the actual stat transfer from the host reactor to the target's
## reactor.  Guards against the target being null, freed, or already dead.
func _transfer_stats() -> void:
	if not is_instance_valid(target):
		return
	if not is_instance_valid(_host_reactor):
		return

	var target_reactor := _find_reactor(target)
	if target_reactor == null:
		return

	# Don't transfer to an already-dead reactor.
	if target_reactor.integrity <= 0.0:
		return

	target_reactor.max_heat += _host_reactor.max_heat
	target_reactor.max_integrity += _host_reactor.max_integrity
	target_reactor.integrity = minf(
		target_reactor.integrity + _host_reactor.integrity,
		target_reactor.max_integrity
	)


## Locate a [ReactorCore] on the given node.
## Tries [method get_reactor] first (codebase convention), then checks if the
## node itself is a [ReactorCore], then searches immediate children.
static func _find_reactor(node: Node) -> Node:
	if node.has_method("get_reactor"):
		return node.get_reactor()
	if node is ReactorCore:
		return node
	for child in node.get_children():
		if child is ReactorCore:
			return child
	return null
