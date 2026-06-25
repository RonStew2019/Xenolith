extends Control
class_name CarrierModulesUI
## Module management screen — shows installed carrier modules with
## install/uninstall controls and a live power budget readout.
##
## Entirely programmatic — no .tscn needed.
## Call [method bind_carrier] to wire signals and populate the initial state.

# ── Palette (matches ReactorHUD) ─────────────────────────────────────────

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
const BTN_BORDER_HOVER := Color(0.35, 0.45, 0.7, 0.8)
const BTN_BG_DISABLED := Color(0.06, 0.06, 0.08, 0.5)
const BTN_COLOR_DISABLED := Color(0.35, 0.35, 0.4)

# Module-type accent colors
const TYPE_COLORS: Dictionary = {
	&"reactor": Color(1.0, 0.85, 0.2),
	&"fabricator": Color(0.9, 0.5, 0.1),
	&"hangar": Color(0.3, 0.7, 1.0),
	&"harvester": Color(0.3, 0.85, 0.4),
	&"defense": Color(0.7, 0.3, 0.9),
}
const FALLBACK_TYPE_COLOR := Color(0.5, 0.5, 0.55)

# Layout
const CORNER_RADIUS := 4
const PANEL_CORNER := 6
const FONT_HEADER := 16
const FONT_NORMAL := 13
const FONT_SMALL := 11

# ── Internal refs ────────────────────────────────────────────────────────

var _carrier: Carrier = null
var _power_label: Label
var _slots_label: Label
var _installed_container: VBoxContainer
var _install_container: VBoxContainer
var _empty_label: Label


func _ready() -> void:
	_build_ui()

# ── Binding ──────────────────────────────────────────────────────────────

## Wire to a [Carrier] and populate initial state.
func bind_carrier(carrier: Carrier) -> void:
	if _carrier:
		_unbind()
	_carrier = carrier
	carrier.module_installed.connect(_on_module_installed)
	carrier.module_uninstalled.connect(_on_module_uninstalled)
	_rebuild_all()


func _unbind() -> void:
	if not _carrier:
		return
	_safe_disconnect(_carrier.module_installed, _on_module_installed)
	_safe_disconnect(_carrier.module_uninstalled, _on_module_uninstalled)
	_carrier = null

# ── UI Construction ──────────────────────────────────────────────────────

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

	# ── Header section: power + slots ──
	var stats_panel := _make_section_panel()
	root.add_child(stats_panel)

	var stats_vbox := VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 4)
	stats_panel.add_child(stats_vbox)

	_power_label = _make_label("Power: -- / -- (-- available)", LABEL_COLOR, FONT_NORMAL)
	stats_vbox.add_child(_power_label)

	_slots_label = _make_label("Slots: -- / --", LABEL_COLOR, FONT_NORMAL)
	stats_vbox.add_child(_slots_label)

	# ── Installed modules section ──
	var installed_header := _make_label("INSTALLED MODULES", HEADER_COLOR, FONT_HEADER)
	root.add_child(installed_header)

	_installed_container = VBoxContainer.new()
	_installed_container.add_theme_constant_override("separation", 4)
	root.add_child(_installed_container)

	_empty_label = _make_label("No modules installed.", DIM_COLOR, FONT_NORMAL)
	_installed_container.add_child(_empty_label)

	# ── Install new modules section ──
	var install_header := _make_label("INSTALL MODULE", HEADER_COLOR, FONT_HEADER)
	root.add_child(install_header)

	_install_container = VBoxContainer.new()
	_install_container.add_theme_constant_override("separation", 4)
	root.add_child(_install_container)

	_build_install_buttons()

# ── Installed Module Rows ────────────────────────────────────────────────

func _rebuild_installed_list() -> void:
	# Clear existing rows (keep _empty_label)
	for child in _installed_container.get_children():
		if child != _empty_label:
			child.queue_free()

	if not _carrier:
		_empty_label.visible = true
		return

	var modules := _carrier.get_modules()
	_empty_label.visible = modules.is_empty()

	for i: int in modules.size():
		var module: CarrierModule = modules[i]
		var row := _build_module_row(module, i)
		_installed_container.add_child(row)


func _build_module_row(module: CarrierModule, slot_index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.1, 0.8)
	_apply_corner_radius(style, CORNER_RADIUS)
	_apply_border(style, 1, BORDER_COLOR)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	# Type color swatch
	var swatch := PanelContainer.new()
	swatch.custom_minimum_size = Vector2(6, 0)
	var swatch_style := StyleBoxFlat.new()
	var mod_type := module.get_module_type()
	swatch_style.bg_color = TYPE_COLORS.get(mod_type, FALLBACK_TYPE_COLOR)
	_apply_corner_radius(swatch_style, 2)
	swatch.add_theme_stylebox_override("panel", swatch_style)
	hbox.add_child(swatch)

	# Info column
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var name_label := _make_label(String(module.module_name), LABEL_COLOR, FONT_NORMAL)
	info.add_child(name_label)

	var detail_text := _get_module_detail(module)
	var detail_label := _make_label(detail_text, DIM_COLOR, FONT_SMALL)
	info.add_child(detail_label)

	# Power cost badge
	var power_text := ""
	if module is ReactorModule:
		power_text = "+%d " % (module as ReactorModule).power_output
	else:
		power_text = "-%d " % module.power_cost
	var power_lbl := _make_label(power_text, _get_power_label_color(module), FONT_NORMAL)
	power_lbl.custom_minimum_size.x = 50.0
	power_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(power_lbl)

	# Uninstall button
	var btn := _make_button("Uninstall", DANGER_COLOR)
	btn.pressed.connect(_on_uninstall_pressed.bind(slot_index))
	hbox.add_child(btn)

	return panel


func _get_module_detail(module: CarrierModule) -> String:
	if module is ReactorModule:
		return "Generates %d power" % (module as ReactorModule).power_output
	if module is FabricatorModule:
		return "Build speed: %.1fx" % (module as FabricatorModule).build_speed
	if module is HangarModule:
		return "Mech capacity: %d" % (module as HangarModule).mech_capacity
	if module is HarvesterModule:
		return "Harvest bonus: +%.1f/s" % (module as HarvesterModule).harvest_rate_bonus
	if module is DefenseModule:
		return "Defense: +%.1f" % (module as DefenseModule).defense_strength
	return module.description if module.description != "" else String(module.get_module_type())


func _get_power_label_color(module: CarrierModule) -> Color:
	if module is ReactorModule:
		return TYPE_COLORS[&"reactor"]
	return DIM_COLOR

# ── Install Buttons ──────────────────────────────────────────────────────

func _build_install_buttons() -> void:
	for child in _install_container.get_children():
		child.queue_free()

	# Each installable module type with default stats + cost from EconomyConfig
	var templates: Array[Dictionary] = [
		{
			"label": "Reactor  (+5 )  —  %s" % _format_cost(EconomyConfig.reactor_module_cost()),
			"factory": _make_reactor,
			"costs": EconomyConfig.reactor_module_cost(),
		},
		{
			"label": "Fabricator  (1.0x speed)  —  %s" % _format_cost(EconomyConfig.fabricator_module_cost()),
			"factory": _make_fabricator,
			"costs": EconomyConfig.fabricator_module_cost(),
		},
		{
			"label": "Hangar  (4 slots)  —  %s" % _format_cost(EconomyConfig.hangar_module_cost()),
			"factory": _make_hangar_module,
			"costs": EconomyConfig.hangar_module_cost(),
		},
		{
			"label": "Harvester  (+5.0/s)  —  %s" % _format_cost(EconomyConfig.harvester_module_cost()),
			"factory": _make_harvester,
			"costs": EconomyConfig.harvester_module_cost(),
		},
		{
			"label": "Defense  (+10.0)  —  %s" % _format_cost(EconomyConfig.defense_module_cost()),
			"factory": _make_defense,
			"costs": EconomyConfig.defense_module_cost(),
		},
	]

	for tmpl: Dictionary in templates:
		var btn := _make_button(tmpl.label, ACCENT_COLOR)
		btn.pressed.connect(_on_install_pressed.bind(tmpl.factory))
		_install_container.add_child(btn)


func _update_install_button_states() -> void:
	if not _carrier:
		return
	var slots_full: bool = _carrier.get_module_count() >= _carrier.max_slots
	var inventory: Inventory = _carrier.get_inventory()

	# Cost lookup per button label prefix — mirrors the template order.
	var cost_map: Array[Dictionary] = [
		EconomyConfig.reactor_module_cost(),
		EconomyConfig.fabricator_module_cost(),
		EconomyConfig.hangar_module_cost(),
		EconomyConfig.harvester_module_cost(),
		EconomyConfig.defense_module_cost(),
	]

	var btn_index: int = 0
	for child in _install_container.get_children():
		if child is Button:
			var cannot_afford: bool = false
			if btn_index < cost_map.size() and inventory != null:
				var costs: Dictionary = cost_map[btn_index]
				for res_type: StringName in costs:
					if not inventory.has_enough(res_type, costs[res_type]):
						cannot_afford = true
						break
			child.disabled = slots_full or cannot_afford
			btn_index += 1


# ── Module Factories (for install buttons) ───────────────────────────────

func _make_reactor() -> CarrierModule:
	var m := ReactorModule.new()
	m.module_name = &"Reactor"
	m.description = "Additional power reactor."
	m.power_output = 5
	m.resource_costs = EconomyConfig.reactor_module_cost()
	return m

func _make_fabricator() -> CarrierModule:
	var m := FabricatorModule.new()
	m.module_name = &"Fabricator"
	m.description = "Mech fabrication bay."
	m.build_speed = 1.0
	m.resource_costs = EconomyConfig.fabricator_module_cost()
	return m

func _make_hangar_module() -> CarrierModule:
	var m := HangarModule.new()
	m.module_name = &"Hangar Bay"
	m.description = "Mech storage bay."
	m.mech_capacity = 4
	m.resource_costs = EconomyConfig.hangar_module_cost()
	return m

func _make_harvester() -> CarrierModule:
	var m := HarvesterModule.new()
	m.module_name = &"Harvester"
	m.description = "Resource harvesting equipment."
	m.harvest_rate_bonus = 5.0
	m.resource_costs = EconomyConfig.harvester_module_cost()
	return m

func _make_defense() -> CarrierModule:
	var m := DefenseModule.new()
	m.module_name = &"Defense Grid"
	m.description = "Passive defense system."
	m.defense_strength = 10.0
	m.resource_costs = EconomyConfig.defense_module_cost()
	return m

# ── Signal Handlers ──────────────────────────────────────────────────────

func _on_module_installed(_module: CarrierModule, _slot_index: int) -> void:
	_rebuild_all()


func _on_module_uninstalled(_module: CarrierModule, _slot_index: int) -> void:
	_rebuild_all()


func _on_uninstall_pressed(slot_index: int) -> void:
	if not _carrier:
		return
	_carrier.uninstall_module(slot_index)


func _on_install_pressed(factory: Callable) -> void:
	if not _carrier:
		return
	var module: CarrierModule = factory.call()
	if not _carrier.has_power_for(module) and not (module is ReactorModule):
		print("[CarrierModulesUI] Not enough power for %s" % module.module_name)
		return
	# Carrier.install_module() handles resource cost validation & deduction.
	_carrier.install_module(module)

# ── Refresh ──────────────────────────────────────────────────────────────

func _rebuild_all() -> void:
	_update_power_label()
	_update_slots_label()
	_rebuild_installed_list()
	_update_install_button_states()


func _update_power_label() -> void:
	if not _carrier:
		return
	var output := _carrier.get_total_power_output()
	var cost := _carrier.get_total_power_cost()
	var available := _carrier.get_available_power()
	_power_label.text = "Power: %d used / %d generated (%d available)" % [cost, output, available]
	# Color code based on remaining power
	if available <= 0:
		_power_label.add_theme_color_override("font_color", DANGER_COLOR)
	elif available <= 1:
		_power_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		_power_label.add_theme_color_override("font_color", LABEL_COLOR)


func _update_slots_label() -> void:
	if not _carrier:
		return
	var used := _carrier.get_module_count()
	var total := _carrier.max_slots
	_slots_label.text = "Slots: %d / %d" % [used, total]
	if used >= total:
		_slots_label.add_theme_color_override("font_color", DANGER_COLOR)
	else:
		_slots_label.add_theme_color_override("font_color", LABEL_COLOR)

# ── Style Factories ──────────────────────────────────────────────────────

func _make_section_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.1, 0.6)
	_apply_corner_radius(style, CORNER_RADIUS)
	_apply_border(style, 1, BORDER_COLOR)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_button(text: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 30)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	# Normal
	var normal := StyleBoxFlat.new()
	normal.bg_color = BTN_BG
	_apply_corner_radius(normal, CORNER_RADIUS)
	_apply_border(normal, 1, BTN_BORDER)
	_apply_btn_margins(normal)
	btn.add_theme_stylebox_override("normal", normal)

	# Hover
	var hover := StyleBoxFlat.new()
	hover.bg_color = BTN_BG_HOVER
	_apply_corner_radius(hover, CORNER_RADIUS)
	_apply_border(hover, 1, accent.darkened(0.2))
	_apply_btn_margins(hover)
	btn.add_theme_stylebox_override("hover", hover)

	# Pressed
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = accent.darkened(0.6)
	_apply_corner_radius(pressed, CORNER_RADIUS)
	_apply_border(pressed, 1, accent)
	_apply_btn_margins(pressed)
	btn.add_theme_stylebox_override("pressed", pressed)

	# Disabled
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


## Format a resource cost dictionary as a human-readable string.
## e.g. {&"metal": 40, &"crystal": 20} → "40 Metal, 20 Crystal"
static func _format_cost(costs: Dictionary) -> String:
	if costs.is_empty():
		return "Free"
	var parts: PackedStringArray = []
	for res_type: StringName in costs:
		parts.append("%d %s" % [costs[res_type], String(res_type).capitalize()])
	return ", ".join(parts)


static func _safe_disconnect(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)
