extends Control
class_name LoadoutMenu
## Loadout preset selection menu — full-screen modal overlay.
##
## Shows a centered panel with one styled button per loadout preset.
## The currently equipped preset is marked with a ● indicator and a
## cyan accent.  Supports keyboard navigation and Escape to close.
##
## Signal contract:
##   • [signal preset_selected] — player picked a preset.
##   • [signal menu_closed]     — player pressed Escape.
##
## Usage (by LoadoutConsole):
##   var menu := LoadoutMenu.new()
##   menu.setup(preset_names, current_preset)
##   menu.preset_selected.connect(_on_preset_selected)
##   menu.menu_closed.connect(_on_menu_closed)
##   hud_layer.add_child(menu)

signal preset_selected(preset_name: String)
signal menu_closed()

# ── Palette ──────────────────────────────────────────────────────────────

const BACKDROP_COLOR := Color(0.0, 0.0, 0.02, 0.65)

const PANEL_BG := Color(0.05, 0.05, 0.08, 0.92)
const PANEL_BORDER := Color(0.25, 0.3, 0.45, 0.6)
const PANEL_CORNER := 6

const TITLE_COLOR := Color(0.5, 0.7, 1.0)
const TITLE_FONT_SIZE := 20
const LABEL_COLOR := Color(0.8, 0.85, 0.9)
const HINT_COLOR := Color(0.45, 0.48, 0.55)
const HINT_FONT_SIZE := 13
const SEPARATOR_COLOR := Color(0.2, 0.24, 0.35, 0.5)

# Button palette — normal state
const BTN_BG_NORMAL := Color(0.08, 0.08, 0.12, 0.7)
const BTN_BORDER_NORMAL := Color(0.2, 0.25, 0.38, 0.5)
# Button palette — hover state
const BTN_BG_HOVER := Color(0.12, 0.14, 0.22, 0.9)
const BTN_BORDER_HOVER := Color(0.35, 0.45, 0.7, 0.8)
# Button palette — pressed state
const BTN_BG_PRESSED := Color(0.18, 0.22, 0.35, 0.95)
const BTN_BORDER_PRESSED := Color(0.5, 0.65, 0.95, 0.9)
# Button palette — active preset accent
const ACTIVE_ACCENT := Color(0.3, 0.7, 1.0)
const ACTIVE_BG := Color(0.06, 0.1, 0.18, 0.8)
const ACTIVE_BORDER := Color(0.3, 0.7, 1.0, 0.5)
# Focus ring (drawn on top of state style)
const FOCUS_BORDER := Color(0.4, 0.55, 0.85, 0.7)

# Button sizing
const BTN_FONT_SIZE := 15
const BTN_CORNER := 4
const BTN_MIN_WIDTH := 280.0
const BTN_MIN_HEIGHT := 38.0

# Animation
const FADE_DURATION := 0.15
const SCALE_FROM := 0.95
const SCALE_DURATION := 0.15

# ── Internal refs ────────────────────────────────────────────────────────

var _current: String = ""
var _preset_names: Array[String] = []
var _backdrop: ColorRect
var _panel: PanelContainer
var _focus_button: Button = null


## Populate the menu with available presets, highlighting the active one.
## Must be called before adding this node to the scene tree.
func setup(preset_names: Array[String], current_preset: String) -> void:
	_current = current_preset
	_preset_names = preset_names


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	# Defer entrance until first layout pass so panel.size is known.
	call_deferred("_after_layout")


func _after_layout() -> void:
	_play_entrance()
	if _focus_button:
		_focus_button.grab_focus()

# ── UI Construction ──────────────────────────────────────────────────────

func _build_ui() -> void:
	# -- Backdrop --
	_backdrop = ColorRect.new()
	_backdrop.color = BACKDROP_COLOR
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	# -- Centered panel --
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	# -- Title --
	var title := Label.new()
	title.text = "SELECT LOADOUT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	# -- Separator --
	var sep := ColorRect.new()
	sep.color = SEPARATOR_COLOR
	sep.custom_minimum_size = Vector2(0, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# -- Top spacer --
	var spacer_top := Control.new()
	spacer_top.custom_minimum_size = Vector2(0, 2)
	vbox.add_child(spacer_top)

	# -- Preset buttons --
	for pname in _preset_names:
		var is_active := (pname == _current)
		var btn := _make_preset_button(pname, is_active)
		vbox.add_child(btn)
		if is_active:
			_focus_button = btn

	# Fallback: focus the first button if no current match.
	if _focus_button == null:
		for child in vbox.get_children():
			if child is Button:
				_focus_button = child
				break

	# -- Bottom spacer --
	var spacer_bottom := Control.new()
	spacer_bottom.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(spacer_bottom)

	# -- Cancel hint --
	var hint := Label.new()
	hint.text = "[Esc] Cancel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	hint.add_theme_color_override("font_color", HINT_COLOR)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hint)

# ── Button Factory ───────────────────────────────────────────────────────

func _make_preset_button(preset_name: String, is_active: bool) -> Button:
	var btn := Button.new()
	btn.text = ("●  %s" % preset_name) if is_active else preset_name
	btn.custom_minimum_size = Vector2(BTN_MIN_WIDTH, BTN_MIN_HEIGHT)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	# State-dependent StyleBoxFlat overrides
	btn.add_theme_stylebox_override("normal", _make_btn_normal(is_active))
	btn.add_theme_stylebox_override("hover", _make_btn_hover(is_active))
	btn.add_theme_stylebox_override("pressed", _make_btn_pressed())
	btn.add_theme_stylebox_override("focus", _make_btn_focus(is_active))

	# Font color overrides
	var font_color := ACTIVE_ACCENT if is_active else LABEL_COLOR
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", TITLE_COLOR)
	btn.add_theme_color_override("font_focus_color", font_color)
	btn.add_theme_font_size_override("font_size", BTN_FONT_SIZE)

	btn.pressed.connect(_on_preset_pressed.bind(preset_name))
	return btn


func _on_preset_pressed(pname: String) -> void:
	preset_selected.emit(pname)

# ── Input ────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
		menu_closed.emit()
		get_viewport().set_input_as_handled()

# ── Entrance Animation ───────────────────────────────────────────────────

func _play_entrance() -> void:
	# Start invisible and slightly scaled down.
	_backdrop.modulate.a = 0.0
	_panel.modulate.a = 0.0
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2(SCALE_FROM, SCALE_FROM)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(_backdrop, "modulate:a", 1.0, FADE_DURATION)
	tween.tween_property(_panel, "modulate:a", 1.0, FADE_DURATION)
	tween.tween_property(_panel, "scale", Vector2.ONE, SCALE_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

# ── Style Factories ──────────────────────────────────────────────────────

func _make_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	_apply_corner_radius(s, PANEL_CORNER)
	s.content_margin_left = 20.0
	s.content_margin_right = 20.0
	s.content_margin_top = 16.0
	s.content_margin_bottom = 14.0
	_apply_border(s, 1, PANEL_BORDER)
	return s


func _make_btn_normal(is_active: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = ACTIVE_BG if is_active else BTN_BG_NORMAL
	_apply_border(s, 1, ACTIVE_BORDER if is_active else BTN_BORDER_NORMAL)
	_apply_corner_radius(s, BTN_CORNER)
	_apply_btn_margins(s)
	return s


func _make_btn_hover(is_active: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BTN_BG_HOVER
	_apply_border(s, 1, ACTIVE_ACCENT if is_active else BTN_BORDER_HOVER)
	_apply_corner_radius(s, BTN_CORNER)
	_apply_btn_margins(s)
	return s


func _make_btn_pressed() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BTN_BG_PRESSED
	_apply_border(s, 1, BTN_BORDER_PRESSED)
	_apply_corner_radius(s, BTN_CORNER)
	_apply_btn_margins(s)
	return s


## Focus ring — border-only overlay drawn on top of the state style.
func _make_btn_focus(is_active: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	_apply_border(s, 1, ACTIVE_ACCENT if is_active else FOCUS_BORDER)
	_apply_corner_radius(s, BTN_CORNER)
	_apply_btn_margins(s)
	return s

# ── Static Helpers ───────────────────────────────────────────────────────

static func _apply_corner_radius(style: StyleBoxFlat, r: int) -> void:
	style.corner_radius_top_left = r
	style.corner_radius_top_right = r
	style.corner_radius_bottom_left = r
	style.corner_radius_bottom_right = r


static func _apply_border(style: StyleBoxFlat, width: int, color: Color) -> void:
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.border_color = color


static func _apply_btn_margins(style: StyleBoxFlat) -> void:
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
