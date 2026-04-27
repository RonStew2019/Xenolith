extends Ability
class_name TunnelAbility
## Place a pair of bi-directional tunnel entrances.
##
## INSTANT activation — each press spawns a new pair of linked
## [TunnelNode]s via a [TunnelEffect] (handles spawning on
## [method StatusEffect.on_apply] and despawning on
## [method StatusEffect.on_remove]).  Tunnels are stackable — multiple
## pairs can coexist — and each pair auto-expires after 100 ticks
## (~10 seconds).
##
## Self-effects:
##   • A [TunnelEffect] (100-tick duration, 75 heat/tick) that owns the
##     tunnel pair and carries the heat cost.


func _init(p_input: String = "ability_2") -> void:
	ability_name = "Tunnel"
	input_action = p_input
	activation_mode = ActivationMode.INSTANT


func create_self_effects(user: Node) -> Array:
	return [TunnelEffect.new(user)]


## Hard cleanup on death or loadout swap — destroy tunnels unconditionally.
func force_deactivate(user: Node) -> void:
	var reactor := _get_reactor(user)
	if reactor:
		reactor.remove_effects_by_name("Tunnel")
	_applied_effects.clear()
