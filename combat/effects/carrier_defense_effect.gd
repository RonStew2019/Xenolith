extends StatusEffect
class_name CarrierDefenseEffect
## Automated carrier defense turrets — applies heat to the nearest enemy each tick.
##
## Permanent effect (duration = -1) applied to the carrier's own [ReactorCore].
## Each tick, scans the [code]"characters"[/code] group for the nearest living
## enemy within [member defense_range] and applies a single-tick [PunchEffect]
## to that enemy's reactor.  The turret heat-per-shot scales with the total
## defense strength of all installed defense modules.
##
## The effect itself contributes zero heat to the carrier — defense turrets
## don't overheat the carrier's reactor.

## Maximum targeting distance (metres).
var defense_range: float = 12.0

## Heat applied per tick to the targeted enemy.
var defense_heat: float = 5.0

## Team of the carrier this effect belongs to (enemies are anything != this).
var _team: int = 0


func _init(
	p_defense_heat: float = 5.0,
	p_defense_range: float = 12.0,
	p_team: int = 0,
	p_source: Node = null,
) -> void:
	super._init("Carrier Defense", 0.0, -1, p_source)
	defense_heat = p_defense_heat
	defense_range = p_defense_range
	_team = p_team


func on_tick(reactor: Node) -> void:
	var carrier_node: Node = reactor.get_parent()
	if not carrier_node is Node3D:
		return

	var carrier_pos: Vector3 = (carrier_node as Node3D).global_position
	var tree: SceneTree = carrier_node.get_tree()
	if tree == null:
		return

	var best_target: Node = null
	var best_dist_sq: float = defense_range * defense_range

	for node: Node in tree.get_nodes_in_group("characters"):
		# Skip self.
		if node == carrier_node:
			continue
		# Skip same team.
		var node_team = node.get("team")
		if node_team != null and node_team == _team:
			continue
		# Skip dead.
		var dead = node.get("_dead")
		if dead:
			continue
		# Must have a reactor.
		if not node.has_method("get_reactor"):
			continue
		var target_reactor = node.get_reactor()
		if target_reactor == null:
			continue
		# Must be Node3D for distance check.
		if not node is Node3D:
			continue
		var dist_sq: float = carrier_pos.distance_squared_to(
			(node as Node3D).global_position
		)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_target = node

	if best_target != null:
		var target_reactor = best_target.get_reactor()
		if target_reactor != null:
			target_reactor.apply_effect(PunchEffect.new(defense_heat, 1, carrier_node))


## Defense effects are carrier-specific — not broadcastable.
func duplicate_for_broadcast(_new_source: Node) -> StatusEffect:
	return null
