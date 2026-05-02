class_name SwordAlphaEntity
extends CelestialSwordEntity
## Offensive deployed sword — pulses [PunchEffect] damage to nearby enemies
## every 1 second (10 combat ticks).
##
## Extends the base [CelestialSwordEntity] with a larger 10 m influence
## radius and a tick-driven AoE damage pulse.  Every 10 ticks, all valid
## characters overlapping the Area3D receive a [PunchEffect] (50 heat,
## 1 tick duration) attributed to the [member caster].
##
## [b]Filtering:[/b] Skips the caster, dead characters, sword entities,
## pillars, and anything without a [code]get_reactor()[/code] method.
##
## Connects to [CombatTickClock] on ready and disconnects on tree exit
## to avoid orphan callbacks.

## Radius of the damage pulse sphere (metres).
const PULSE_RADIUS := 10.0

## Number of combat ticks between damage pulses (10 ticks = 1 second).
const TICKS_PER_PULSE := 10

## Heat dealt per pulse to each target.
const PULSE_HEAT := 50.0

## Duration (in ticks) of the [PunchEffect] applied per pulse.
const PULSE_DURATION := 1

## Internal tick counter — resets to 0 after each pulse.
var _tick_count: int = 0


func _ready() -> void:
	super._ready()
	# Override the base 5 m influence sphere to our larger pulse radius.
	# The base creates a single CollisionShape3D child with a SphereShape3D.
	for child in get_children():
		if child is CollisionShape3D and child.shape is SphereShape3D:
			child.shape.radius = PULSE_RADIUS
			break
	# Subscribe to the global combat tick clock.
	var clock := _get_tick_clock()
	if clock:
		clock.tick.connect(_on_combat_tick)
	# Disconnect cleanly when removed from the tree.
	tree_exiting.connect(_on_tree_exiting)


## Increment the tick counter and fire a damage pulse every
## [constant TICKS_PER_PULSE] ticks.
func _on_combat_tick() -> void:
	_tick_count += 1
	if _tick_count < TICKS_PER_PULSE:
		return
	_tick_count = 0
	_pulse_damage()


## Apply [PunchEffect] to every valid overlapping body.
func _pulse_damage() -> void:
	for body in get_overlapping_bodies():
		if body == caster:
			continue
		if body.get("_dead"):
			continue
		if body.get("is_sword_entity") or body.get("is_pillar"):
			continue
		if not body.has_method("get_reactor"):
			continue
		var reactor = body.get_reactor()
		if reactor:
			reactor.apply_effect(PunchEffect.new(PULSE_HEAT, PULSE_DURATION, caster))


## Disconnect from [CombatTickClock] when leaving the tree.
func _on_tree_exiting() -> void:
	var clock := _get_tick_clock()
	if clock and clock.tick.is_connected(_on_combat_tick):
		clock.tick.disconnect(_on_combat_tick)


## Helper — safely fetch the [CombatTickClock] autoload.
func _get_tick_clock() -> Node:
	var tree := get_tree()
	if tree and tree.root.has_node("CombatTickClock"):
		return tree.root.get_node("CombatTickClock")
	return null
