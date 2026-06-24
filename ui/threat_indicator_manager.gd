extends Node3D
class_name ThreatIndicatorManager
## Manages 3D threat indicators floating above threat entities on the hex grid.
##
## Auto-discovers a [ThreatManager] sibling in [method _ready] and connects
## to its [signal ThreatManager.threat_spawned], [signal ThreatManager.threat_removed],
## and [signal ThreatManager.threat_detected] signals.
##
## Each tracked threat gets a billboarded diamond marker + name label that
## follows the entity's position.  Color-coded by threat type, scaled by
## threat level, with a brief pulse animation on detection.

# -- Constants -------------------------------------------------------------

## Height above the threat entity's position for the indicator.
const INDICATOR_Y_OFFSET := 2.5

## Fauna hive marker color — dark purple, matches [constant FaunaHive.HIVE_COLOR].
const FAUNA_COLOR := Color(0.6, 0.15, 0.5)

## Enemy carrier marker color — angry red, matches [constant EnemyCarrier.ENEMY_COLOR].
const ENEMY_COLOR := Color(0.8, 0.2, 0.15)

## Fallback for unknown threat types.
const DEFAULT_COLOR := Color(1.0, 0.5, 0.0)

## Diamond marker font size (Label3D units).
const MARKER_FONT_SIZE := 64

## Entity name font size (Label3D units).
const NAME_FONT_SIZE := 28

## Label3D pixel size — controls world-space scaling of text.
const MARKER_PIXEL_SIZE := 0.01

## Scale multiplier applied to threat_level to derive indicator base scale.
const BASE_SCALE_FACTOR := 0.4

## Minimum indicator scale (weak threats don't disappear).
const MIN_SCALE := 0.5

## Maximum indicator scale (cap for very strong threats).
const MAX_SCALE := 2.0

## Duration of the detection pulse "grow" phase.
const PULSE_UP_DURATION := 0.15

## Duration of the detection pulse "shrink" phase.
const PULSE_DOWN_DURATION := 0.25

## How much larger the indicator grows during a pulse.
const PULSE_SCALE_MULT := 1.5

# -- State -----------------------------------------------------------------

## Reference to the sibling [ThreatManager] (auto-discovered).
var _threat_manager: Node = null

## Maps [ThreatEntity] -> [Node3D] indicator container.
var _indicators: Dictionary = {}

# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	if get_parent() != null:
		_threat_manager = get_parent().get_node_or_null("ThreatManager")

	if _threat_manager == null:
		push_warning("[ThreatIndicatorManager] No ThreatManager sibling found")
		return

	_threat_manager.threat_spawned.connect(_on_threat_spawned)
	_threat_manager.threat_removed.connect(_on_threat_removed)
	_threat_manager.threat_detected.connect(_on_threat_detected)

	# Pick up any threats that were spawned before we connected.
	for threat: ThreatEntity in _threat_manager.get_threats():
		_on_threat_spawned(threat)


func _process(_delta: float) -> void:
	var stale: Array = []
	for threat: ThreatEntity in _indicators:
		if not is_instance_valid(threat):
			stale.append(threat)
			continue
		var indicator: Node3D = _indicators[threat]
		indicator.global_position = threat.global_position + Vector3(0.0, INDICATOR_Y_OFFSET, 0.0)

	# Clean up indicators whose threat entities were freed unexpectedly.
	for threat in stale:
		var indicator: Node3D = _indicators[threat]
		_indicators.erase(threat)
		if is_instance_valid(indicator):
			indicator.queue_free()


# -- Signal Handlers -------------------------------------------------------

func _on_threat_spawned(threat: ThreatEntity) -> void:
	if threat in _indicators:
		return  # Already tracking.

	var color := _get_threat_color(threat)
	var container := Node3D.new()
	container.name = "Indicator_%s" % threat.name

	# Diamond marker
	var marker := Label3D.new()
	marker.text = String.chr(0x25C6)  # BLACK DIAMOND (U+25C6)
	marker.font_size = MARKER_FONT_SIZE
	marker.modulate = color
	marker.outline_modulate = color.darkened(0.5)
	marker.outline_size = 8
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.fixed_size = false
	marker.pixel_size = MARKER_PIXEL_SIZE
	container.add_child(marker)

	# Entity name below the marker
	var name_lbl := Label3D.new()
	name_lbl.text = String(threat.entity_name)
	name_lbl.font_size = NAME_FONT_SIZE
	name_lbl.modulate = color
	name_lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	name_lbl.outline_size = 6
	name_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_lbl.no_depth_test = true
	name_lbl.fixed_size = false
	name_lbl.pixel_size = MARKER_PIXEL_SIZE
	name_lbl.position.y = -0.5
	container.add_child(name_lbl)

	# Scale by threat level
	var base_scale := clampf(threat.threat_level * BASE_SCALE_FACTOR, MIN_SCALE, MAX_SCALE)
	container.scale = Vector3.ONE * base_scale

	# Initial position
	if is_instance_valid(threat):
		container.global_position = threat.global_position + Vector3(0.0, INDICATOR_Y_OFFSET, 0.0)

	add_child(container)
	_indicators[threat] = container


func _on_threat_removed(threat: ThreatEntity) -> void:
	if threat not in _indicators:
		return
	var indicator: Node3D = _indicators[threat]
	_indicators.erase(threat)
	if is_instance_valid(indicator):
		indicator.queue_free()


func _on_threat_detected(threat: ThreatEntity) -> void:
	if threat not in _indicators:
		return
	var indicator: Node3D = _indicators[threat]
	if not is_instance_valid(indicator):
		return

	# Brief scale pulse — grow then return to normal.
	var original_scale := indicator.scale
	var pulse_scale := original_scale * PULSE_SCALE_MULT
	var tween := create_tween()
	tween.tween_property(indicator, "scale", pulse_scale, PULSE_UP_DURATION)
	tween.tween_property(indicator, "scale", original_scale, PULSE_DOWN_DURATION)


# -- Helpers ---------------------------------------------------------------

## Return the display color for a threat based on its type.
func _get_threat_color(threat: ThreatEntity) -> Color:
	var threat_type := threat.get_threat_type()
	if threat_type == &"fauna_hive":
		return FAUNA_COLOR
	elif threat_type == &"enemy_carrier":
		return ENEMY_COLOR
	return DEFAULT_COLOR
