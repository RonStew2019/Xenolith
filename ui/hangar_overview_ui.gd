extends Control
class_name HangarOverviewUI
## Hangar overview screen -- shows stored mechs with stats and scrap buttons.
##
## Entirely programmatic -- no .tscn needed.
## Call [method bind_carrier] to wire signals and populate the initial state.

# -- Palette (matches ReactorHUD) -----------------------------------------

const PANEL_BG := Color(0.05, 0.05, 0.08, 0.85)
const LABEL_COLOR := Color(0.8, 0.85, 0.9)
const HEADER_COLOR := Color(0.5, 0.7, 1.0)
const BORDER_COLOR := Color(0.25, 0.3, 0.45, 0.6)
const ACCENT_COLOR := Color(0.2, 0.5, 1.0)
const DIM_COLOR := Color(0.45, 0.48, 0.55)
const DANGER_COLOR := Color(0.9, 0.3, 0.3)
const SUCCESS_COLOR := Color(0.3, 0.85, 0.4)

# Button palette
const BTN_BG := Color(0.08, 0.08, 0.12, 0.7)
const BTN_BORDER := Color(0.2, 0.25, 0.38, 0.5)
const BTN_BG_HOVER := Color(0.12, 0.14, 0.22, 0.9)
const BTN_BG_DISABLED := Color(0.06, 0.06, 0.08, 0.5)
const BTN_COLOR_DISABLED := Color(0.35, 0.35, 0.4)

# Layout
const CORNER_RADIUS := 4
const FONT_HEADER := 16
const FONT_NORMAL := 13
const FONT_SMALL := 11

# -- Internal refs ---------------------------------------------------------

var _carrier: Carrier = null
var _hangar: Hangar = null
var _capacity_label: Label
var _mechs_container: VBoxContainer
var _empty_label: Label


func _ready() -> void:
	_build_ui()

# -- Binding ---------------------------------------------------------------

## Wire to a [Carrier]'s hangar and populate initial state.
func bind_carrier(carrier: Carrier) -> void:
	if _carrier:
		_unbind()
	_carrier = carrier
	_hangar = carrier.get_hangar()
	_hangar.mech_stored.connect(_on_mech_stored)
	_hangar.mech_removed.connect(_on_mech_removed)
	# Also listen for module changes (hangar capacity can change)
	_carrier.module_installed.connect(_on_module_changed)
	_carrier.module_uninstalled.connect(_on_module_changed)
	_rebuild_all()


func _unbind() -> void:
	if _hangar:
		_safe_disconnect(_hangar.mech_stored, _on_mech_stored)
		_safe_disconnect(_hangar.mech_removed, _on_mech_removed)
	if _carrier:
		_safe_disconnect(_carrier.module_installed, _on_module_changed)
		_safe_disconnect(_carrier.module_uninstalled, _on_module_changed)
	_carrier = null
	_hangar = null

# -- UI Construction -------------------------------------------------------

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	# -- Capacity header --
	_capacity_label = _make_label("Hangar: -- / -- mechs", LABEL_COLOR, FONT_NORMAL)
	root.add_child(_capacity_label)

	# -- Mech list --
	var list_header := _make_label("STORED MECHS", HEADER_COLOR, FONT_HEADER)
	root.add_child(list_header)

	_mechs_container = VBoxContainer.new()
	_mechs_container.add_theme_constant_override("separation", 6)
	root.add_child(_mechs_container)

	_empty_label = _make_label("Hangar is empty.", DIM_COLOR, FONT_NORMAL)
	_mechs_container.add_child(_empty_label)

# -- Mech Rows -------------------------------------------------------------

func _rebuild_mech_list() -> void:
	for child in _mechs_container.get_children():
		if child != _empty_label:
			child.queue_free()

	if not _hangar:
		_empty_label.visible = true
		return

	var mechs := _hangar.get_mechs()
	_empty_label.visible = mechs.is_empty()

	for i: int in mechs.size():
		var bp: MechBlueprint = mechs[i]
		var row := _build_mech_row(bp, i)
		_mechs_container.add_child(row)


func _build_mech_row(bp: MechBlueprint, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.1, 0.8)
	_apply_corner_radius(style, CORNER_RADIUS)
	_apply_border(style, 1, BORDER_COLOR)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Top row: name + scrap button
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	vbox.add_child(top_row)

	var name_lbl := _make_label(String(bp.blueprint_name), LABEL_COLOR, FONT_NORMAL)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(name_lbl)

	var scrap_btn := _make_button("Scrap", DANGER_COLOR)
	scrap_btn.pressed.connect(_on_scrap_pressed.bind(index))
	top_row.add_child(scrap_btn)

	# Chassis info
	if bp.chassis:
		var chassis_text := "Chassis: %s  |  Speed: %.0f  |  Heat: %.0f  |  Integrity: %.0f" \
			% [String(bp.chassis.chassis_name), bp.chassis.base_speed,
			   bp.chassis.base_max_heat, bp.chassis.base_integrity]
		var chassis_lbl := _make_label(chassis_text, DIM_COLOR, FONT_SMALL)
		vbox.add_child(chassis_lbl)

		# Weapon assignments
		if not bp.weapon_assignments.is_empty():
			var weapon_parts: PackedStringArray = []
			for slot: StringName in bp.weapon_assignments:
				var weapon: StringName = bp.weapon_assignments[slot]
				var weapon_display := String(weapon) if weapon != &"" else "empty"
				weapon_parts.append("%s: %s" % [String(slot).to_pascal_case(), weapon_display])
			var weapons_lbl := _make_label("Weapons: %s" % ", ".join(weapon_parts), DIM_COLOR, FONT_SMALL)
			vbox.add_child(weapons_lbl)
		else:
			var no_weapons := _make_label("Weapons: None assigned", DIM_COLOR, FONT_SMALL)
			vbox.add_child(no_weapons)
	else:
		var no_chassis := _make_label("(No chassis data)", DIM_COLOR, FONT_SMALL)
		vbox.add_child(no_chassis)

	return panel


func _on_scrap_pressed(index: int) -> void:
	if not _hangar:
		return
	_hangar.remove_mech(index)

# -- Signal Handlers -------------------------------------------------------

func _on_mech_stored(_bp: MechBlueprint) -> void:
	_rebuild_all()


func _on_mech_removed(_bp: MechBlueprint) -> void:
	_rebuild_all()


func _on_module_changed(_module: CarrierModule, _slot_index: int) -> void:
	_update_capacity_label()

# -- Refresh ---------------------------------------------------------------

## Public entry point — call when the screen becomes visible.
func refresh() -> void:
	_rebuild_all()


func _rebuild_all() -> void:
	_update_capacity_label()
	_rebuild_mech_list()


func _update_capacity_label() -> void:
	if not _hangar:
		return
	var count := _hangar.get_mech_count()
	var capacity := _hangar.get_max_capacity()
	_capacity_label.text = "Hangar: %d / %d mechs" % [count, capacity]
	if count >= capacity:
		_capacity_label.add_theme_color_override("font_color", DANGER_COLOR)
	else:
		_capacity_label.add_theme_color_override("font_color", LABEL_COLOR)

# -- Style Factories -------------------------------------------------------

func _make_button(text: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 28)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	var normal := StyleBoxFlat.new()
	normal.bg_color = BTN_BG
	_apply_corner_radius(normal, CORNER_RADIUS)
	_apply_border(normal, 1, BTN_BORDER)
	_apply_btn_margins(normal)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = BTN_BG_HOVER
	_apply_corner_radius(hover, CORNER_RADIUS)
	_apply_border(hover, 1, accent.darkened(0.2))
	_apply_btn_margins(hover)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = accent.darkened(0.6)
	_apply_corner_radius(pressed, CORNER_RADIUS)
	_apply_border(pressed, 1, accent)
	_apply_btn_margins(pressed)
	btn.add_theme_stylebox_override("pressed", pressed)

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = BTN_BG_DISABLED
	_apply_corner_radius(disabled, CORNER_RADIUS)
	_apply_border(disabled, 1, Color(0.15, 0.15, 0.2, 0.4))
	_apply_btn_margins(disabled)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_color_override("font_color", LABEL_COLOR)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", accent)
	btn.add_theme_color_override("font_disabled_color", BTN_COLOR_DISABLED)
	btn.add_theme_font_size_override("font_size", FONT_NORMAL)

	return btn


func _make_label(text: String, color: Color, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", font_size)
	return lbl


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
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0


static func _safe_disconnect(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)
