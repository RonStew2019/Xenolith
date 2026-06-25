extends Control
class_name BlueprintCreatorUI
## Blueprint designer and fabrication queue screen.
##
## Lets the player pick a chassis, name the blueprint, preview resource
## costs, queue builds, and monitor / cancel in-progress fabrication.
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
const WARNING_COLOR := Color(1.0, 0.85, 0.2)

# Button palette
const BTN_BG := Color(0.08, 0.08, 0.12, 0.7)
const BTN_BORDER := Color(0.2, 0.25, 0.38, 0.5)
const BTN_BG_HOVER := Color(0.12, 0.14, 0.22, 0.9)
const BTN_BG_DISABLED := Color(0.06, 0.06, 0.08, 0.5)
const BTN_COLOR_DISABLED := Color(0.35, 0.35, 0.4)
const SELECTED_BG := Color(0.08, 0.12, 0.22, 0.9)
const SELECTED_BORDER := Color(0.3, 0.6, 1.0, 0.8)

# Chassis stat icons / colours
const SPEED_COLOR := Color(0.3, 0.85, 1.0)
const HEAT_COLOR := Color(1.0, 0.6, 0.1)
const INTEGRITY_COLOR := Color(0.3, 0.85, 0.4)

# Progress bar
const BAR_BG := Color(0.12, 0.12, 0.18)
const BAR_FILL := Color(0.2, 0.5, 1.0)

# Layout
const CORNER_RADIUS := 4
const FONT_HEADER := 16
const FONT_NORMAL := 13
const FONT_SMALL := 11

# -- Internal refs ---------------------------------------------------------

var _carrier: Carrier = null
var _build_queue: BuildQueue = null
var _inventory: Inventory = null

var _selected_chassis: MechChassis = null
var _chassis_buttons: Dictionary = {}  # StringName -> Button
var _stats_label: Label
var _cost_label: Label
var _name_edit: LineEdit
var _queue_btn: Button
var _queue_status_label: Label

var _slots_container: VBoxContainer
var _queue_container: VBoxContainer
var _resource_label: Label

# Weapon slot selections: slot_name (StringName) -> weapon_id (StringName)
var _weapon_selections: Dictionary = {}

# Track queue entries for _process updates
var _queue_rows: Array[Dictionary] = []  # {panel, bar, progress_label, fill_style}


func _ready() -> void:
	_build_ui()

# -- Binding ---------------------------------------------------------------

## Wire to a [Carrier] and its sub-systems.
func bind_carrier(carrier: Carrier) -> void:
	if _carrier:
		_unbind()
	_carrier = carrier
	_build_queue = carrier.get_build_queue()
	_inventory = carrier.get_inventory()

	_build_queue.build_started.connect(_on_build_started)
	_build_queue.build_completed.connect(_on_build_completed)
	_build_queue.build_cancelled.connect(_on_build_cancelled)
	_inventory.resource_changed.connect(_on_resource_changed)

	_refresh_resources()
	_refresh_queue()
	_update_queue_button()


func _unbind() -> void:
	if _build_queue:
		_safe_disconnect(_build_queue.build_started, _on_build_started)
		_safe_disconnect(_build_queue.build_completed, _on_build_completed)
		_safe_disconnect(_build_queue.build_cancelled, _on_build_cancelled)
	if _inventory:
		_safe_disconnect(_inventory.resource_changed, _on_resource_changed)
	_carrier = null
	_build_queue = null
	_inventory = null


func _process(_delta: float) -> void:
	if not _build_queue or _build_queue.get_queue_size() == 0:
		return
	_refresh_queue_progress()

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

	# -- Resources readout --
	_resource_label = _make_label("Resources: --", LABEL_COLOR, FONT_NORMAL)
	root.add_child(_resource_label)

	# -- Chassis selection --
	var chassis_header := _make_label("SELECT CHASSIS", HEADER_COLOR, FONT_HEADER)
	root.add_child(chassis_header)

	var chassis_row := HBoxContainer.new()
	chassis_row.add_theme_constant_override("separation", 8)
	root.add_child(chassis_row)

	_add_chassis_button(chassis_row, ChassisPresets.dogfighter_chassis())
	_add_chassis_button(chassis_row, ChassisPresets.bomber_chassis())

	# -- Selected chassis stats --
	_stats_label = _make_label("Select a chassis above.", DIM_COLOR, FONT_NORMAL)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_stats_label)

	# -- Weapon slots (placeholder) --
	var slots_header := _make_label("WEAPON SLOTS", HEADER_COLOR, FONT_HEADER)
	root.add_child(slots_header)

	_slots_container = VBoxContainer.new()
	_slots_container.add_theme_constant_override("separation", 4)
	root.add_child(_slots_container)

	var slots_placeholder := _make_label("Select a chassis to view slots.", DIM_COLOR, FONT_SMALL)
	_slots_container.add_child(slots_placeholder)

	# -- Blueprint name + queue --
	var build_header := _make_label("BUILD", HEADER_COLOR, FONT_HEADER)
	root.add_child(build_header)

	var build_row := HBoxContainer.new()
	build_row.add_theme_constant_override("separation", 8)
	root.add_child(build_row)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Blueprint name..."
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size = Vector2(0, 30)
	_name_edit.add_theme_color_override("font_color", LABEL_COLOR)
	_name_edit.add_theme_color_override("font_placeholder_color", DIM_COLOR)
	_name_edit.add_theme_font_size_override("font_size", FONT_NORMAL)
	var edit_style := StyleBoxFlat.new()
	edit_style.bg_color = Color(0.06, 0.06, 0.1, 0.8)
	_apply_corner_radius(edit_style, CORNER_RADIUS)
	_apply_border(edit_style, 1, BORDER_COLOR)
	edit_style.content_margin_left = 8.0
	edit_style.content_margin_right = 8.0
	edit_style.content_margin_top = 4.0
	edit_style.content_margin_bottom = 4.0
	_name_edit.add_theme_stylebox_override("normal", edit_style)
	build_row.add_child(_name_edit)

	_queue_btn = _make_button("Queue Build", ACCENT_COLOR)
	_queue_btn.disabled = true
	_queue_btn.pressed.connect(_on_queue_pressed)
	build_row.add_child(_queue_btn)

	_cost_label = _make_label("", DIM_COLOR, FONT_SMALL)
	root.add_child(_cost_label)

	_queue_status_label = _make_label("", DIM_COLOR, FONT_SMALL)
	root.add_child(_queue_status_label)

	# -- Build queue list --
	var queue_header := _make_label("BUILD QUEUE", HEADER_COLOR, FONT_HEADER)
	root.add_child(queue_header)

	_queue_container = VBoxContainer.new()
	_queue_container.add_theme_constant_override("separation", 4)
	root.add_child(_queue_container)

# -- Chassis Buttons -------------------------------------------------------

func _add_chassis_button(parent: HBoxContainer, chassis: MechChassis) -> void:
	var btn := Button.new()
	btn.text = String(chassis.chassis_name)
	btn.custom_minimum_size = Vector2(140, 36)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	_apply_button_styles(btn, ACCENT_COLOR)
	btn.pressed.connect(_on_chassis_selected.bind(chassis))
	parent.add_child(btn)
	_chassis_buttons[chassis.chassis_name] = btn


func _on_chassis_selected(chassis: MechChassis) -> void:
	_selected_chassis = chassis

	# Update button highlight
	for cname: StringName in _chassis_buttons:
		var btn: Button = _chassis_buttons[cname]
		if cname == chassis.chassis_name:
			var sel_style := StyleBoxFlat.new()
			sel_style.bg_color = SELECTED_BG
			_apply_corner_radius(sel_style, CORNER_RADIUS)
			_apply_border(sel_style, 1, SELECTED_BORDER)
			_apply_btn_margins(sel_style)
			btn.add_theme_stylebox_override("normal", sel_style)
			btn.add_theme_color_override("font_color", Color.WHITE)
		else:
			_apply_button_styles(btn, ACCENT_COLOR)

	_update_stats_display(chassis)
	_update_slots_display(chassis)
	_update_cost_display(chassis)
	_update_queue_button()


func _update_stats_display(chassis: MechChassis) -> void:
	var text := "%s\n" % String(chassis.chassis_name)
	text += "Speed: %.0f  |  Max Heat: %.0f  |  Integrity: %.0f\n" \
		% [chassis.base_speed, chassis.base_max_heat, chassis.base_integrity]
	text += "Slots: %d  |  Build Time: %.0fs" \
		% [chassis.weapon_slots.size(), chassis.build_time]
	if chassis.description != "":
		text += "\n%s" % chassis.description
	_stats_label.text = text
	_stats_label.add_theme_color_override("font_color", LABEL_COLOR)


func _update_slots_display(chassis: MechChassis) -> void:
	for child in _slots_container.get_children():
		child.queue_free()
	_weapon_selections.clear()

	if chassis.weapon_slots.is_empty():
		var lbl := _make_label("No weapon slots.", DIM_COLOR, FONT_SMALL)
		_slots_container.add_child(lbl)
		return

	var weapon_ids := WeaponRegistry.get_all_weapon_ids()

	for slot_name: StringName in chassis.weapon_slots:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var slot_lbl := _make_label(String(slot_name).to_pascal_case(), LABEL_COLOR, FONT_NORMAL)
		slot_lbl.custom_minimum_size.x = 120.0
		row.add_child(slot_lbl)

		var opt := OptionButton.new()
		opt.custom_minimum_size = Vector2(180, 30)
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opt.focus_mode = Control.FOCUS_NONE
		opt.add_theme_font_size_override("font_size", FONT_NORMAL)
		opt.add_theme_color_override("font_color", LABEL_COLOR)
		opt.add_theme_color_override("font_hover_color", Color.WHITE)
		var opt_style := StyleBoxFlat.new()
		opt_style.bg_color = BTN_BG
		_apply_corner_radius(opt_style, CORNER_RADIUS)
		_apply_border(opt_style, 1, BTN_BORDER)
		_apply_btn_margins(opt_style)
		opt.add_theme_stylebox_override("normal", opt_style)

		# First item is "(none)"
		opt.add_item("(none)")
		for wid: StringName in weapon_ids:
			opt.add_item(String(wid).to_pascal_case())
		opt.selected = 0

		opt.item_selected.connect(_on_weapon_slot_changed.bind(slot_name, weapon_ids))
		row.add_child(opt)

		_slots_container.add_child(row)


func _on_weapon_slot_changed(index: int, slot_name: StringName, weapon_ids: Array[StringName]) -> void:
	if index == 0:
		_weapon_selections.erase(slot_name)
	else:
		_weapon_selections[slot_name] = weapon_ids[index - 1]
	# Refresh cost display to include weapon costs.
	if _selected_chassis != null:
		_update_cost_display(_selected_chassis)
		_update_queue_button()


func _update_cost_display(chassis: MechChassis) -> void:
	# Build total cost including weapons.
	var total_costs: Dictionary = chassis.resource_costs.duplicate()
	for slot_name: StringName in _weapon_selections:
		var weapon_id: StringName = _weapon_selections[slot_name]
		if weapon_id == &"":
			continue
		var weapon_cost: Dictionary = EconomyConfig.get_weapon_cost(weapon_id)
		for res_type: StringName in weapon_cost:
			total_costs[res_type] = total_costs.get(res_type, 0) + weapon_cost[res_type]

	if total_costs.is_empty():
		_cost_label.text = "Cost: Free"
		_cost_label.add_theme_color_override("font_color", SUCCESS_COLOR)
		return

	var parts: PackedStringArray = []
	var can_afford := true
	for res_type: StringName in total_costs:
		var needed: int = total_costs[res_type]
		var have: int = _inventory.get_amount(res_type) if _inventory else 0
		parts.append("%s: %d/%d" % [String(res_type).to_pascal_case(), have, needed])
		if have < needed:
			can_afford = false

	_cost_label.text = "Cost: %s" % "  ".join(parts)
	_cost_label.add_theme_color_override("font_color", SUCCESS_COLOR if can_afford else DANGER_COLOR)

# -- Queue Button Logic ----------------------------------------------------

func _update_queue_button() -> void:
	if not _carrier or not _build_queue or not _selected_chassis:
		_queue_btn.disabled = true
		_queue_status_label.text = ""
		return

	var reasons: PackedStringArray = []

	# Check fabricator
	if _build_queue.get_fabrication_speed() <= 0.0:
		reasons.append("No fabricator installed")

	# Check resources — use total cost (chassis + weapons)
	var costs: Dictionary = _selected_chassis.resource_costs.duplicate()
	for slot_name: StringName in _weapon_selections:
		var weapon_id: StringName = _weapon_selections[slot_name]
		if weapon_id == &"":
			continue
		var weapon_cost: Dictionary = EconomyConfig.get_weapon_cost(weapon_id)
		for res_type: StringName in weapon_cost:
			costs[res_type] = costs.get(res_type, 0) + weapon_cost[res_type]
	if _inventory:
		for res_type: StringName in costs:
			if not _inventory.has_enough(res_type, costs[res_type]):
				reasons.append("Not enough %s" % String(res_type))

	# Check hangar capacity
	var hangar: Hangar = _carrier.get_hangar()
	var pending: int = hangar.get_mech_count() + _build_queue.get_queue_size()
	if pending >= hangar.get_max_capacity():
		reasons.append("Hangar full")

	_queue_btn.disabled = not reasons.is_empty()
	if reasons.is_empty():
		_queue_status_label.text = "Ready to build (speed: %.1fx)" % _build_queue.get_fabrication_speed()
		_queue_status_label.add_theme_color_override("font_color", SUCCESS_COLOR)
	else:
		_queue_status_label.text = ", ".join(reasons)
		_queue_status_label.add_theme_color_override("font_color", DANGER_COLOR)


func _on_queue_pressed() -> void:
	if not _carrier or not _build_queue or not _selected_chassis:
		return

	var bp := MechBlueprint.new()
	var name_text := _name_edit.text.strip_edges()
	if name_text == "":
		name_text = String(_selected_chassis.chassis_name)
	bp.blueprint_name = StringName(name_text)
	bp.chassis = _selected_chassis
	bp.weapon_assignments = _weapon_selections.duplicate()

	if _build_queue.queue_build(bp):
		_name_edit.text = ""
		# Refresh happens via signal

# -- Build Queue Display ---------------------------------------------------

func _refresh_queue() -> void:
	for child in _queue_container.get_children():
		child.queue_free()
	_queue_rows.clear()

	if not _build_queue:
		return

	var queue := _build_queue.get_queue()
	if queue.is_empty():
		var empty_lbl := _make_label("No builds in progress.", DIM_COLOR, FONT_SMALL)
		_queue_container.add_child(empty_lbl)
		return

	for i: int in queue.size():
		var entry: Dictionary = queue[i]
		var bp: MechBlueprint = entry.blueprint
		var row := _build_queue_row(bp, entry.progress, entry.build_time, i)
		_queue_container.add_child(row.panel)
		_queue_rows.append(row)


func _build_queue_row(bp: MechBlueprint, progress: float, build_time: float, index: int) -> Dictionary:
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

	# Name
	var name_lbl := _make_label(String(bp.blueprint_name), LABEL_COLOR, FONT_NORMAL)
	name_lbl.custom_minimum_size.x = 120.0
	hbox.add_child(name_lbl)

	# Progress bar
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(120, 16)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = build_time
	bar.value = progress
	bar.add_theme_stylebox_override("background", _make_bar_bg())
	var fill := StyleBoxFlat.new()
	fill.bg_color = BAR_FILL
	_apply_corner_radius(fill, 3)
	bar.add_theme_stylebox_override("fill", fill)
	hbox.add_child(bar)

	# Progress text
	var pct := (progress / maxf(build_time, 0.001)) * 100.0
	var progress_lbl := _make_label("%d%%" % int(pct), LABEL_COLOR, FONT_SMALL)
	progress_lbl.custom_minimum_size.x = 40.0
	progress_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(progress_lbl)

	# Cancel button
	var cancel_btn := _make_button("Cancel", DANGER_COLOR)
	cancel_btn.pressed.connect(_on_cancel_pressed.bind(index))
	hbox.add_child(cancel_btn)

	return {
		"panel": panel,
		"bar": bar,
		"progress_label": progress_lbl,
		"fill_style": fill,
		"build_time": build_time,
	}


func _refresh_queue_progress() -> void:
	if not _build_queue:
		return
	var queue := _build_queue.get_queue()
	# If sizes diverged, do a full rebuild
	if queue.size() != _queue_rows.size():
		_refresh_queue()
		return

	for i: int in queue.size():
		var entry: Dictionary = queue[i]
		var row: Dictionary = _queue_rows[i]
		row.bar.value = entry.progress
		var pct: float = (entry.progress / maxf(row.build_time, 0.001)) * 100.0
		row.progress_label.text = "%d%%" % int(pct)


func _on_cancel_pressed(index: int) -> void:
	if not _build_queue:
		return
	_build_queue.cancel_build(index)

# -- Signal Handlers -------------------------------------------------------

func _on_build_started(_bp: MechBlueprint) -> void:
	_refresh_queue()
	_update_queue_button()
	_refresh_resources()


func _on_build_completed(_bp: MechBlueprint) -> void:
	_refresh_queue()
	_update_queue_button()


func _on_build_cancelled(_bp: MechBlueprint) -> void:
	_refresh_queue()
	_update_queue_button()
	_refresh_resources()


func _on_resource_changed(_resource_type: StringName, _new_amount: int) -> void:
	_refresh_resources()
	if _selected_chassis:
		_update_cost_display(_selected_chassis)
	_update_queue_button()

# -- Resource Display ------------------------------------------------------

func _refresh_resources() -> void:
	if not _inventory:
		_resource_label.text = "Resources: --"
		return
	var all: Dictionary = _inventory.get_all_resources()
	if all.is_empty():
		_resource_label.text = "Resources: None"
		return
	var parts: PackedStringArray = []
	for res_type: StringName in all:
		parts.append("%s: %d" % [String(res_type).to_pascal_case(), all[res_type]])
	_resource_label.text = "Resources: %s" % "  |  ".join(parts)

# -- Style Factories -------------------------------------------------------

func _make_bar_bg() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BAR_BG
	_apply_corner_radius(s, 3)
	return s


func _make_button(text: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 30)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_button_styles(btn, accent)
	return btn


func _apply_button_styles(btn: Button, accent: Color) -> void:
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
