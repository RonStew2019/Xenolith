extends Ability
class_name CloneAbility
## Spawn three clone mechs that split reactor capacity with the caster.
##
## INSTANT activation — each press spawns 3 AI-controlled [CloneMech]
## copies via a [CloneEffect].  The caster's [member ReactorCore.max_heat]
## and [member ReactorCore.max_integrity] are divided evenly across the
## caster and all clones.  Clones have no ambient venting, so they
## overheat naturally as a built-in lifetime limit.
##
## Multi-generational: clones carry this ability in their loadout and
## can spawn their own clones, further subdividing capacity.
##
## Self-effects:
##   • A [CloneEffect] (single-tick pulse, 0 heat) that handles spawning
##     and stat splitting.

func _init(p_input: String = "ability_4") -> void:
	ability_name = "Clone"
	input_action = p_input
	activation_mode = ActivationMode.INSTANT


func create_self_effects(user: Node) -> Array:
	return [CloneEffect.new(user)]
