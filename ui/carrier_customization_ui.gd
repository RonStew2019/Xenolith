extends CanvasLayer
class_name CarrierCustomizationUI
## Top-level carrier customization overlay with tabbed navigation.
##
## Wraps [CarrierModulesUI], [BlueprintCreatorUI], and [HangarOverviewUI]
## in a full-screen modal with tab buttons.  Toggle open/close with Tab.
##
## Entirely programmatic -- no .tscn needed.
## Call [method bind_carrier] to wire all child screens.

# -- Signals ---------------------------------------------------------------

## Emitted when the overlay opens.
signal opened()

## Emitted when the overlay closes.
signal closed()

# -- Palette (matches ReactorHUD) -----------------------------------------

const BACKDROP_COLOR := Color(0.0, 0.0, 0.02, 0.65)
const PANEL_BG := Color(0.05, 0.05, 0.08, 0.92)
const BORDER_COLOR := Color(0.25, 0.3, 0.45, 0.6)
const LABEL_COLOR := Color(0.8, 0.85, 0.9)
const HEADER_COLOR := Color(0.5, 0.7, 1.0)
const ACCENT_COLOR := Color(0.2, 0.5, 1.0)
const DIM_COLOR := Color(0.45, 0.48, 0.55)

# Tab palette
const TAB_ACTIVE_BG := Color(0.1, 0.15, 0.25, 0.95)
const TAB_ACTIVE_BORDER := Color(0.3, 0.6, 1.0, 0.8)
const TAB_INACTIVE_BG := Color(0.06, 0.06, 0.1, 0.6)
const TAB_INACTIVE_BORDER := Color(0.2, 0.25, 0.38, 0.4)
const TAB_HOVER_BG := Color(0.1, 0.12, 0.2, 0.8)
const TAB_HOVER_BORDER := Color(0.3, 0.4, 0.6, 0.6)

# Animation
const FADE_DURATION := 0.15
const SCALE_FROM := 0.97
const SCALE_DURATION := 0.15

# Layout
const CORNER_RADIUS := 6
const TAB_CORNER := 4
const PANEL_MARGIN := 40.0
const TAB_HEIGHT := 34
const FONT_TAB := 14
const FONT_TITLE := 20
const FONT_HINT := 12

# -- Internal refs ---------------------------------------------------------

var _carrier: Carrier = null
var _is_open: bool = false

# Root control (child of this CanvasLayer)
var _root: Control
var _backdrop: ColorRect
var _main_panel: PanelContainer
var _content_container: Control

# Tab system
var _tab_buttons: Array[Button] = []
var _screens: Array[Control] = []
var _active_tab: int = 0

# Child screens
var _modules_ui: CarrierModulesUI
var _blueprint_ui: BlueprintCreatorUI
var _hangar_ui: HangarOverviewUI


func _ready() -> void:
	layer = 10  # Render above everything else
	_build_ui()
	_set_visible(false)
	# Auto-discover Carrier sibling if nobody called bind_carrier() yet.
	if _carrier == null and get_parent() != null:
		var carrier := get_parent().get_node_or_null("Carrier") as Carrier
		if carrier:
			bind_carrier(carrier)

# -- Binding ---------------------------------------------------------------

## Wire to a [Carrier] and pass references to all child screens.
func bind_carrier(carrier: Carrier) -> void:
	_carrier = carrier
	_modules_ui.bind_carrier(carrier)
	_blueprint_ui.bind_carrier(carrier)
	_hangar_ui.bind_carrier(carrier)

# -- Open / Close ----------------------------------------------------------

## Toggle the overlay open or closed.
func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


## Show the overlay.
func open() -> void:
	if _is_open:
		return
	_is_open = true
	_set_visible(true)
	_play_entrance()
	if _carrier:
		_carrier.is_moving = true  # Block carrier movement while open
	opened.emit()


## Hide the overlay.
func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_set_visible(false)
	if _carrier:
		_carrier.is_moving = false  # Re-enable carrier movement
	closed.emit()


func _set_visible(vis: bool) -> void:
	if _root:
		_root.visible = vis

# -- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_TAB:
		toggle()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and _is_open:
		close()
		get_viewport().set_input_as_handled()

# -- UI Construction -------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# -- Backdrop --
	_backdrop = ColorRect.new()
	_backdrop.color = BACKDROP_COLOR
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_backdrop)

	# -- Main panel (centered with margins) --
	_main_panel = PanelContainer.new()
	_main_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_main_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_panel.offset_left = PANEL_MARGIN
	_main_panel.offset_top = PANEL_MARGIN
	_main_panel.offset_right = -PANEL_MARGIN
	_main_panel.offset_bottom = -PANEL_MARGIN
	_root.add_child(_main_panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 8)
	_main_panel.add_child(outer_vbox)

	# -- Title row --
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	outer_vbox.add_child(title_row)

	var title := Label.new()
	title.text = "CARRIER CUSTOMIZATION"
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(title)

	var hint := Label.new()
	hint.text = "[Tab] Close    [Esc] Close"
	hint.add_theme_font_size_override("font_size", FONT_HINT)
	hint.add_theme_color_override("font_color", DIM_COLOR)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(hint)

	# -- Separator --
	var sep := ColorRect.new()
	sep.color = Color(0.2, 0.24, 0.35, 0.5)
	sep.custom_minimum_size = Vector2(0, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer_vbox.add_child(sep)

	# -- Tab bar --
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 4)
	outer_vbox.add_child(tab_bar)

	_add_tab_button(tab_bar, "Modules", 0)
	_add_tab_button(tab_bar, "Blueprints", 1)
	_add_tab_button(tab_bar, "Hangar", 2)

	# Spacer to push tabs left
	var tab_spacer := Control.new()
	tab_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_bar.add_child(tab_spacer)

	# -- Content area --
	_content_container = Control.new()
	_content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_container.clip_contents = true
	outer_vbox.add_child(_content_container)

	# -- Create screens --
	_modules_ui = CarrierModulesUI.new()
	_content_container.add_child(_modules_ui)
	_screens.append(_modules_ui)

	_blueprint_ui = BlueprintCreatorUI.new()
	_content_container.add_child(_blueprint_ui)
	_screens.append(_blueprint_ui)

	_hangar_ui = HangarOverviewUI.new()
	_content_container.add_child(_hangar_ui)
	_screens.append(_hangar_ui)

	# Show default tab
	_switch_tab(0)

# -- Tab System ------------------------------------------------------------

func _add_tab_button(parent: HBoxContainer, label: String, index: int) -> void:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(100, TAB_HEIGHT)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.add_theme_font_size_override("font_size", FONT_TAB)
	btn.pressed.connect(_on_tab_pressed.bind(index))
	parent.add_child(btn)
	_tab_buttons.append(btn)


func _on_tab_pressed(index: int) -> void:
	_switch_tab(index)


func _switch_tab(index: int) -> void:
	_active_tab = index
	# Show/hide screens
	for i: int in _screens.size():
		_screens[i].visible = (i == index)

	# Update tab button styles
	for i: int in _tab_buttons.size():
		_style_tab_button(_tab_buttons[i], i == index)


func _style_tab_button(btn: Button, is_active: bool) -> void:
	# Normal state
	var normal := StyleBoxFlat.new()
	normal.bg_color = TAB_ACTIVE_BG if is_active else TAB_INACTIVE_BG
	_apply_corner_radius(normal, TAB_CORNER)
	_apply_border(normal, 1, TAB_ACTIVE_BORDER if is_active else TAB_INACTIVE_BORDER)
	_apply_btn_margins(normal)
	btn.add_theme_stylebox_override("normal", normal)

	# Hover state
	var hover := StyleBoxFlat.new()
	hover.bg_color = TAB_ACTIVE_BG if is_active else TAB_HOVER_BG
	_apply_corner_radius(hover, TAB_CORNER)
	_apply_border(hover, 1, TAB_ACTIVE_BORDER if is_active else TAB_HOVER_BORDER)
	_apply_btn_margins(hover)
	btn.add_theme_stylebox_override("hover", hover)

	# Pressed
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = TAB_ACTIVE_BG
	_apply_corner_radius(pressed, TAB_CORNER)
	_apply_border(pressed, 1, TAB_ACTIVE_BORDER)
	_apply_btn_margins(pressed)
	btn.add_theme_stylebox_override("pressed", pressed)

	# Font color
	btn.add_theme_color_override("font_color", Color.WHITE if is_active else LABEL_COLOR)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)

# -- Entrance Animation ----------------------------------------------------

func _play_entrance() -> void:
	_backdrop.modulate.a = 0.0
	_main_panel.modulate.a = 0.0
	_main_panel.pivot_offset = _main_panel.size / 2.0
	_main_panel.scale = Vector2(SCALE_FROM, SCALE_FROM)

	var tween := _root.create_tween().set_parallel(true)
	tween.tween_property(_backdrop, "modulate:a", 1.0, FADE_DURATION)
	tween.tween_property(_main_panel, "modulate:a", 1.0, FADE_DURATION)
	tween.tween_property(_main_panel, "scale", Vector2.ONE, SCALE_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

# -- Style Factories -------------------------------------------------------

func _make_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	_apply_corner_radius(s, CORNER_RADIUS)
	s.content_margin_left = 20.0
	s.content_margin_right = 20.0
	s.content_margin_top = 16.0
	s.content_margin_bottom = 16.0
	_apply_border(s, 1, BORDER_COLOR)
	return s


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
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
