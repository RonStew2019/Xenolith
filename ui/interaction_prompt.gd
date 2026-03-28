extends Control
class_name InteractionPrompt
## Reusable screen-space interaction prompt.
##
## Shows a "[Key] Action" prompt center-bottom of the screen with a
## quick fade-in/out tween.  Starts hidden.  Entirely programmatic —
## no .tscn needed.
##
## Usage:
##   prompt.show_prompt("Q", "Travel")   # displays "[Q] Travel"
##   prompt.hide_prompt()                 # fades out

# ── Palette ──────────────────────────────────────────────────────────────

const PANEL_BG := Color(0.05, 0.05, 0.08, 0.85)
const BORDER_COLOR := Color(0.25, 0.3, 0.45, 0.6)
const LABEL_COLOR := Color(0.8, 0.85, 0.9)
const KEY_COLOR := Color(0.5, 0.7, 1.0)
const KEY_BOX_BG := Color(0.12, 0.14, 0.22, 0.9)
const KEY_BOX_BORDER := Color(0.4, 0.5, 0.7, 0.7)

# ── Layout ───────────────────────────────────────────────────────────────

const CORNER_RADIUS := 6
const KEY_CORNER_RADIUS := 4
const KEY_FONT_SIZE := 16
const ACTION_FONT_SIZE := 15
const FADE_DURATION := 0.15
const BOTTOM_OFFSET := 150.0

# ── Internal refs ────────────────────────────────────────────────────────

var _key_label: Label
var _action_label: Label
var _fade_tween: Tween


func _ready() -> void:
	_build_ui()
	# Start hidden
	modulate.a = 0.0
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# ── Public API ───────────────────────────────────────────────────────────

## Show the prompt with the given key and action text.
## e.g. show_prompt("Q", "Travel") displays "[Q] Travel".
func show_prompt(key_text: String, action_text: String) -> void:
	_key_label.text = key_text
	_action_label.text = action_text
	visible = true
	_fade_to(1.0)


## Hide the prompt with a quick fade-out.
func hide_prompt() -> void:
	_fade_to(0.0)

# ── UI Construction ──────────────────────────────────────────────────────

func _build_ui() -> void:
	# Anchor center-bottom, offset upward
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -BOTTOM_OFFSET
	offset_top = offset_bottom - 44.0
	offset_left = -120.0
	offset_right = 120.0

	# Dark panel
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	# Key box — small bordered panel containing the key letter
	var key_panel := PanelContainer.new()
	key_panel.custom_minimum_size = Vector2(30, 28)
	key_panel.add_theme_stylebox_override("panel", _make_key_box_style())
	key_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(key_panel)

	_key_label = Label.new()
	_key_label.text = "?"
	_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_key_label.add_theme_color_override("font_color", KEY_COLOR)
	_key_label.add_theme_font_size_override("font_size", KEY_FONT_SIZE)
	_key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_panel.add_child(_key_label)

	# Action text
	_action_label = Label.new()
	_action_label.text = ""
	_action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_action_label.add_theme_color_override("font_color", LABEL_COLOR)
	_action_label.add_theme_font_size_override("font_size", ACTION_FONT_SIZE)
	_action_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_action_label)

# ── Animation ────────────────────────────────────────────────────────────

func _fade_to(target_alpha: float) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", target_alpha, FADE_DURATION)
	if target_alpha == 0.0:
		_fade_tween.tween_callback(_on_fade_out_finished)


func _on_fade_out_finished() -> void:
	visible = false

# ── Style Factories ──────────────────────────────────────────────────────

func _make_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	_apply_corner_radius(s, CORNER_RADIUS)
	s.content_margin_left = 14.0
	s.content_margin_right = 14.0
	s.content_margin_top = 8.0
	s.content_margin_bottom = 8.0
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = BORDER_COLOR
	return s


func _make_key_box_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = KEY_BOX_BG
	_apply_corner_radius(s, KEY_CORNER_RADIUS)
	s.content_margin_left = 6.0
	s.content_margin_right = 6.0
	s.content_margin_top = 2.0
	s.content_margin_bottom = 2.0
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = KEY_BOX_BORDER
	return s


static func _apply_corner_radius(style: StyleBoxFlat, r: int) -> void:
	style.corner_radius_top_left = r
	style.corner_radius_top_right = r
	style.corner_radius_bottom_left = r
	style.corner_radius_bottom_right = r
