extends HBoxContainer
class_name AbilityBar
## Row of ability slots showing key labels and active state.
##
## Each slot is a hollow-bordered box with the bound key inside it.
## When the ability is active (toggled on / held), the box fills
## with a translucent blue.  Polls [method Ability.is_active] each
## frame -- dead simple, zero signals needed.

const SLOT_SIZE := Vector2(40, 40)
const BORDER_WIDTH := 2
const CORNER_RADIUS := 4

const BORDER_COLOR := Color(0.5, 0.6, 0.75, 0.8)
const ACTIVE_FILL := Color(0.2, 0.5, 1.0, 0.3)
const INACTIVE_FILL := Color(0.0, 0.0, 0.0, 0.0)
const LABEL_COLOR := Color(0.8, 0.85, 0.9)
const LABEL_FONT_SIZE := 18

var _slots: Array = []  # Array of { ability: Ability, style: StyleBoxFlat }


func _ready() -> void:
	# Anchor bottom-right, float above and away from screen edge.
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -40.0
	offset_top = offset_bottom - SLOT_SIZE.y
	offset_right = -40.0
	add_theme_constant_override("separation", 6)


## Wire up the bar to a [Loadout].
## [param key_labels] maps input action strings to display text,
## e.g. [code]{"ability_1": "1"}[/code].
func bind(loadout: Loadout, key_labels: Dictionary) -> void:
	for ability in loadout.get_abilities():
		var key_text: String = key_labels.get(ability.input_action, "?")
		_add_slot(ability, key_text)


func _process(_delta: float) -> void:
	for slot in _slots:
		var active: bool = slot.ability.is_active()
		slot.style.bg_color = ACTIVE_FILL if active else INACTIVE_FILL


func _add_slot(ability: Ability, key_text: String) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = SLOT_SIZE

	var style := _make_slot_style()
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = key_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	panel.add_child(label)

	add_child(panel)
	_slots.append({ "ability": ability, "style": style })


func _make_slot_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = INACTIVE_FILL
	s.border_color = BORDER_COLOR
	s.border_width_left = BORDER_WIDTH
	s.border_width_top = BORDER_WIDTH
	s.border_width_right = BORDER_WIDTH
	s.border_width_bottom = BORDER_WIDTH
	s.corner_radius_top_left = CORNER_RADIUS
	s.corner_radius_top_right = CORNER_RADIUS
	s.corner_radius_bottom_left = CORNER_RADIUS
	s.corner_radius_bottom_right = CORNER_RADIUS
	return s
