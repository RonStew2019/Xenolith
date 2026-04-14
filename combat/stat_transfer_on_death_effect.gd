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

## Guard flag to prevent double-transfer if both the signal and on_remove()
## attempt the transfer (e.g. shutdown() removes the effect after breach).
var _transferred: bool = false


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
	# If the reactor breached but the signal callback was disconnected
	# before it could fire (e.g. shutdown() removed us first), transfer now.
	if not _transferred and is_instance_valid(reactor) and reactor.integrity <= 0.0:
		_transferred = true
		_transfer_stats()
	if is_instance_valid(reactor) and reactor.reactor_breached.is_connected(_on_reactor_breached):
		reactor.reactor_breached.disconnect(_on_reactor_breached)
	_host_reactor = null


## Callback fired when the host reactor breaches (integrity reaches zero).
func _on_reactor_breached() -> void:
	if not _transferred:
		_transferred = true
		_transfer_stats()


## Performs the actual stat transfer from the host reactor to the resolved
## target's reactor.  If the direct [member target] is invalid or dead,
## walks up the [code]clone_parent[/code] ancestry chain to find the nearest
## living ancestor — ensuring grandchildren with dead parents still return
## stats to grandparents (or further up the chain).
func _transfer_stats() -> void:
	if not is_instance_valid(_host_reactor):
		return

	var resolved: Node = _resolve_target()
	if resolved == null:
		return

	var resolved_reactor := _find_reactor(resolved)
	if resolved_reactor == null:
		return

	resolved_reactor.max_heat += _host_reactor.max_heat
	resolved_reactor.max_integrity += _host_reactor.max_integrity
	resolved_reactor.integrity = minf(
		resolved_reactor.integrity + _host_reactor.integrity,
		resolved_reactor.max_integrity
	)


## Resolve the transfer target.  Returns the direct [member target] when it
## is still valid and alive, otherwise walks up the [code]clone_parent[/code]
## chain from the host mech to find the nearest living ancestor.  Returns
## [code]null[/code] when every ancestor in the chain is dead or freed.
func _resolve_target() -> Node:
	# Fast path: direct target is alive — no traversal needed.
	if is_instance_valid(target):
		var tr := _find_reactor(target)
		if tr and tr.integrity > 0.0:
			return target

	# Fallback: walk up the clone_parent chain from the host mech.
	var host: Node = _host_reactor.get_parent()
	if not is_instance_valid(host):
		return null

	var ancestor: Node = host.get("clone_parent")
	while is_instance_valid(ancestor):
		var ar := _find_reactor(ancestor)
		if ar and ar.integrity > 0.0:
			return ancestor
		ancestor = ancestor.get("clone_parent")

	return null


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
