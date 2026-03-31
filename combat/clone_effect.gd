extends StatusEffect
class_name CloneEffect
## Single-tick pulse that spawns three [CloneMech] entities and splits the
## source mech's reactor capacity evenly across all four bodies (parent + 3
## clones).
##
## Each clone receives a [StatTransferOnDeathEffect] so that when it dies
## its reactor capacity is automatically returned to the parent.  Control
## transfer is handled by [method CloneMech._try_transfer_control].
##
## Stackable: a clone can clone itself (multi-generational splits).

## Number of clones to spawn per activation.
const CLONE_COUNT := 3

## Spawn radius in metres — clones appear in a ring around the source.
const SPAWN_RADIUS := 2.0


func _init(p_source: Node = null) -> void:
	super._init("Clone", 0.0, 1, p_source, true)


func on_apply(reactor: Node) -> void:
	if not is_instance_valid(source):
		push_warning("CloneEffect: source is null or freed — aborting spawn.")
		return

	# -- 1. Calculate the split (parent + clones) -------------------------
	var entity_count := CLONE_COUNT + 1
	var new_max_heat : float = reactor.max_heat / entity_count
	var new_max_integrity : float = reactor.max_integrity / entity_count

	# -- 2. Reduce the parent's reactor capacity --------------------------
	reactor.max_heat = new_max_heat
	reactor.max_integrity = new_max_integrity
	# Clamp integrity to new ceiling; leave current heat untouched.
	reactor.integrity = minf(reactor.integrity, reactor.max_integrity)

	# -- 3. Spawn clones in a ring around the source ----------------------
	var scene_root := source.get_tree().current_scene
	for i in CLONE_COUNT:
		var clone := CloneMech.new()
		clone.name = "Clone_%s_%d" % [source.name, i]
		scene_root.add_child(clone)

		# Position 120° apart at SPAWN_RADIUS metres.
		var angle := (TAU / float(CLONE_COUNT)) * i
		var offset := Vector3(cos(angle) * SPAWN_RADIUS, 0.0, sin(angle) * SPAWN_RADIUS)
		clone.global_position = source.global_position + offset

		# ReactorCore._ready() has already fired (add_child is synchronous),
		# setting integrity = max_integrity (1000) and heat = 0.  Override
		# the defaults with the split values and reset integrity to match.
		var clone_reactor := clone.get_reactor()
		if clone_reactor:
			clone_reactor.max_heat = new_max_heat
			clone_reactor.max_integrity = new_max_integrity
			clone_reactor.integrity = new_max_integrity
			clone_reactor.heat = 0.0

			# Apply stat-transfer-on-death so dying clones return capacity.
			var transfer := StatTransferOnDeathEffect.new(source, source)
			clone_reactor.apply_effect(transfer)

		# Wire up the family tree (vars on CharacterBase).
		clone.clone_parent = source
		source.clone_children.append(clone)
