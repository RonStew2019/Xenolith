class_name SwordGammaEntity
extends CelestialSwordEntity
## Mobility deployed sword — applies [SwordGammaSlowEffect] to enemies
## within a 10 m radius and removes it when they leave.
##
## Extends the base [CelestialSwordEntity] with a larger influence sphere
## and body-entered / body-exited tracking.  Each valid character that
## enters the zone receives a [SwordGammaSlowEffect] (−20 % movespeed),
## which is removed when they exit or when the sword is recalled.
##
## Tracks applied effects in a [Dictionary] mapping body → effect instance
## so the exact effect reference can be removed on exit or recall, even if
## the target has other effects with the same name.

## Radius of the slow zone (metres).
const SLOW_RADIUS := 10.0

## Maps body [Node] → [SwordGammaSlowEffect] instance for clean removal.
var _slowed_bodies: Dictionary = {}


func _ready() -> void:
	super._ready()
	# Override the base 5 m influence sphere to our larger slow radius.
	for child in get_children():
		if child is CollisionShape3D and child.shape is SphereShape3D:
			child.shape.radius = SLOW_RADIUS
			break
	# Subscribe to body-exited as well (base only connects body_entered).
	body_exited.connect(_on_body_exited)


## Override the base stub to apply the slow effect to valid targets.
func _on_body_entered(body: Node3D) -> void:
	if not _is_valid_target(body):
		return
	var reactor = body.get_reactor()
	if not reactor:
		return
	var slow := SwordGammaSlowEffect.new(caster)
	reactor.apply_effect(slow)
	_slowed_bodies[body] = slow


## Remove the slow effect when a body leaves the zone.
func _on_body_exited(body: Node3D) -> void:
	if not _slowed_bodies.has(body):
		return
	var slow: SwordGammaSlowEffect = _slowed_bodies[body]
	_slowed_bodies.erase(body)
	if not is_instance_valid(body):
		return
	if not body.has_method("get_reactor"):
		return
	var reactor = body.get_reactor()
	if reactor:
		reactor.remove_effect(slow)


## On recall, remove all active slow effects before the entity is freed.
func recall() -> void:
	for body in _slowed_bodies.keys():
		if not is_instance_valid(body):
			continue
		if not body.has_method("get_reactor"):
			continue
		var reactor = body.get_reactor()
		if reactor:
			var slow: SwordGammaSlowEffect = _slowed_bodies[body]
			reactor.remove_effect(slow)
	_slowed_bodies.clear()
	super.recall()


## Shared target validation for both enter and exit paths.
func _is_valid_target(body: Node3D) -> bool:
	if body == caster:
		return false
	if body.get("_dead"):
		return false
	if body.get("is_sword_entity") or body.get("is_pillar"):
		return false
	if not body.has_method("get_reactor"):
		return false
	return true
