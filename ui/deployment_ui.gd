extends CanvasLayer
class_name DeploymentUI
## Full-screen deployment overlay — mech selection, pilot assignment, launch.
##
## Entirely programmatic — no .tscn needed.
## Opens when [signal DeploymentManager.deployment_started] fires;
## closes on launch or retreat.
##
## Auto-discovers a [DeploymentManager] sibling in [method _ready].

# -- Signals ---------------------------------------------------------------

## Emitted when the overlay opens.
signal opened()

## Emitted when the overlay closes.
signal closed()

# -- Palette (matches CarrierCustomizationUI / HangarOverviewUI) ----------

const BACKDROP_COLOR := Color(0.0, 0.0, 0.02, 0.65)
const PANEL_BG := Color(0.05, 0.05, 0.08, 0.92)
const BORDER_COLOR := Color(0.25, 0.3, 0.45, 0.6)
const LABEL_COLOR := Color(0.8, 0.85, 0.9)
const HEADER_COLOR := Color(0.5, 0.7, 1.0)
const ACCENT_COLOR := Color(0.2, 0.5, 1.0)
const DIM_COLOR := Color(0.45, 0.48, 0.55)
const DANGER_COLOR := Color(0.9, 0.3, 0.3)
const SUCCESS_COLOR := Color(0.3, 0.85, 0.4)

const WARNING_COLOR := Color(1.0, 0.7, 0.2)
const SELECTED_BG := Color(0.08, 0.12, 0.22, 0.95)
const SELECTED_BORDER := Color(0.3, 0.55, 1.0, 0.8)
const PILOT_BORDER := Color(0.9, 0.75, 0.15, 0.9)
const ROW_BG := Color(0.06, 0.06, 0.1, 0.8)

# Button palette
const BTN_BG := Color(0.08, 0.08, 0.12, 0.7)
const BTN_BORDER := Color(0.2, 0.25, 0.38, 0.5)
const BTN_BG_HOVER := Color(0.12, 0.14, 0.22, 0.9)
const BTN_BG_DISABLED := Color(0.06, 0.06, 0.08, 0.5)
const BTN_COLOR_DISABLED := Color(0.35, 0.35, 0.4)

# Animation
const FADE_DURATION := 0.15
const SCALE_FROM := 0.97
const SCALE_DURATION := 0.15

# Layout
const CORNER_RADIUS := 6
const CORNER_RADIUS_SM := 4
const PANEL_MARGIN := 40.0
const FONT_TITLE := 20
const FONT_HEADER := 16
const FONT_NORMAL := 13
const FONT_SMALL := 11
const FONT_HINT := 12
const ROW_HEIGHT := 64

# -- Internal refs ---------------------------------------------------------

var _deployment_manager: DeploymentManager = null
var _current_threat: ThreatEntity = null
var _is_open: bool = false

# Root control (child of this CanvasLayer)
var _root: Control
var _backdrop: ColorRect
var _main_panel: PanelContainer

# Threat info
var _threat_name_label: Label
var _threat_type_label: Label
var _threat_level_label: Label
var _threat_detail_label: Label

# Mech list
var _mechs_container: VBoxContainer
var _empty_label: Label

# Bottom bar
var _cost_label: Label
var _fuel_label: Label
var _deploy_all_btn: Button
var _clear_btn: Button
var _launch_btn: Button
var _retreat_btn: Button


func _ready() -> void:
	layer = 10  # Render above everything else
	_build_ui()
	_set_visible(false)
	# Auto-discover DeploymentManager sibling.
	if get_parent() != null:
		_deployment_manager = get_parent().get_node_or_null("DeploymentManager") as DeploymentManager
	if _deployment_manager == null:
		push_warning("[DeploymentUI] No DeploymentManager sibling found — UI disabled")
		return
	_deployment_manager.deployment_started.connect(_on_deployment_started)
	_deployment_manager.deployment_launched.connect(_on_deployment_launched)
	_deployment_manager.deployment_retreated.connect(_on_deployment_retreated)
	print("[DeploymentUI] Ready — listening for deployment events")

# -- Open / Close ----------------------------------------------------------

## Show the overlay and populate it for the given [param threat].
func open(threat: ThreatEntity) -> void:
	if _is_open:
		return
	_current_threat = threat
	_is_open = true
	_populate_threat_info(threat)
	_rebuild_mech_list()
	_update_cost_display()
	_set_visible(true)
	_play_entrance()
	print("[DeploymentUI] Opened for threat: %s" % threat.entity_name)
	opened.emit()


## Hide the overlay and clear state.
func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_current_threat = null
	_set_visible(false)
	print("[DeploymentUI] Closed")
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
	if key.keycode == KEY_ESCAPE and _is_open:
		_on_retreat_pressed()
		get_viewport().set_input_as_handled()

# -- Signal Handlers -------------------------------------------------------

func _on_deployment_started(threat: ThreatEntity) -> void:
	open(threat)


func _on_deployment_launched(
	_threat: ThreatEntity,
	_deployed: Array[MechBlueprint],
	_piloted: MechBlueprint,
) -> void:
	close()


func _on_deployment_retreated(_threat: ThreatEntity) -> void:
	close()

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
	_build_title_row(outer_vbox)

	# -- Separator --
	_add_separator(outer_vbox)

	# -- Threat info --
	_build_threat_info(outer_vbox)

	# -- Separator --
	_add_separator(outer_vbox)

	# -- Mech selection header --
	var mech_header := _make_label("SELECT MECHS FOR DEPLOYMENT", HEADER_COLOR, FONT_HEADER)
	outer_vbox.add_child(mech_header)

	# -- Mech list (scrollable) --
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(scroll)

	_mechs_container = VBoxContainer.new()
	_mechs_container.add_theme_constant_override("separation", 6)
	_mechs_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_mechs_container)

	_empty_label = _make_label("Hangar is empty — no mechs available.", DIM_COLOR, FONT_NORMAL)
	_mechs_container.add_child(_empty_label)

	# -- Separator --
	_add_separator(outer_vbox)

	# -- Bottom bar (cost + action buttons) --
	_build_bottom_bar(outer_vbox)


func _build_title_row(parent: VBoxContainer) -> void:
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	parent.add_child(title_row)

	var title := Label.new()
	title.text = "[!] ENGAGEMENT"
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", WARNING_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(title)

	var hint := Label.new()
	hint.text = "[Esc] Retreat"
	hint.add_theme_font_size_override("font_size", FONT_HINT)
	hint.add_theme_color_override("font_color", DIM_COLOR)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(hint)


func _build_threat_info(parent: VBoxContainer) -> void:
	var info_panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.04, 0.85)
	_apply_corner_radius(style, CORNER_RADIUS_SM)
	_apply_border(style, 1, WARNING_COLOR.darkened(0.5))
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	info_panel.add_theme_stylebox_override("panel", style)
	parent.add_child(info_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	info_panel.add_child(vbox)

	_threat_name_label = _make_label("--", WARNING_COLOR, FONT_HEADER)
	vbox.add_child(_threat_name_label)

	var detail_row := HBoxContainer.new()
	detail_row.add_theme_constant_override("separation", 20)
	vbox.add_child(detail_row)

	_threat_type_label = _make_label("Type: --", DIM_COLOR, FONT_NORMAL)
	detail_row.add_child(_threat_type_label)

	_threat_level_label = _make_label("Threat Level: --", LABEL_COLOR, FONT_NORMAL)
	detail_row.add_child(_threat_level_label)

	_threat_detail_label = _make_label("", DIM_COLOR, FONT_NORMAL)
	detail_row.add_child(_threat_detail_label)


func _build_bottom_bar(parent: VBoxContainer) -> void:
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	parent.add_child(bottom)

	# Cost info (left side)
	var cost_vbox := VBoxContainer.new()
	cost_vbox.add_theme_constant_override("separation", 2)
	cost_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(cost_vbox)

	_cost_label = _make_label("Deployment Cost: 0 fuel", LABEL_COLOR, FONT_NORMAL)
	cost_vbox.add_child(_cost_label)

	_fuel_label = _make_label("You have: -- fuel", DIM_COLOR, FONT_SMALL)
	cost_vbox.add_child(_fuel_label)

	# Bulk-selection buttons
	_deploy_all_btn = _make_button("DEPLOY ALL", SUCCESS_COLOR)
	_deploy_all_btn.custom_minimum_size = Vector2(110, 36)
	_deploy_all_btn.pressed.connect(_on_deploy_all_pressed)
	bottom.add_child(_deploy_all_btn)

	_clear_btn = _make_button("CLEAR", DIM_COLOR)
	_clear_btn.custom_minimum_size = Vector2(80, 36)
	_clear_btn.pressed.connect(_on_clear_pressed)
	bottom.add_child(_clear_btn)

	# Action buttons (right side)
	_retreat_btn = _make_button("RETREAT", DANGER_COLOR)
	_retreat_btn.custom_minimum_size = Vector2(120, 36)
	_retreat_btn.pressed.connect(_on_retreat_pressed)
	bottom.add_child(_retreat_btn)

	_launch_btn = _make_button("LAUNCH", ACCENT_COLOR)
	_launch_btn.custom_minimum_size = Vector2(120, 36)
	_launch_btn.pressed.connect(_on_launch_pressed)
	bottom.add_child(_launch_btn)

# -- Threat Info -----------------------------------------------------------

func _populate_threat_info(threat: ThreatEntity) -> void:
	_threat_name_label.text = String(threat.entity_name) if threat.entity_name != &"" else "Unknown Threat"

	var threat_type: StringName = threat.get_threat_type()
	var type_display: String = "Unknown"
	if threat_type == &"fauna_hive":
		type_display = "Fauna Hive"
	elif threat_type == &"enemy_carrier":
		type_display = "Enemy Carrier"
	_threat_type_label.text = "Type: %s" % type_display

	_threat_level_label.text = "Threat Level: %.1f" % threat.threat_level

	# Type-specific detail
	if threat is FaunaHive:
		var hive := threat as FaunaHive
		_threat_detail_label.text = "Swarm Strength: %.1f" % hive.swarm_strength
		_threat_detail_label.add_theme_color_override("font_color", WARNING_COLOR.darkened(0.2))
		_threat_detail_label.visible = true
	elif threat is EnemyCarrier:
		var ec := threat as EnemyCarrier
		_threat_detail_label.text = "Strength: %.1f" % ec.strength
		_threat_detail_label.add_theme_color_override("font_color", DANGER_COLOR.darkened(0.1))
		_threat_detail_label.visible = true
	else:
		_threat_detail_label.visible = false

# -- Mech List -------------------------------------------------------------

func _rebuild_mech_list() -> void:
	# Clear old rows (keep the _empty_label)
	for child in _mechs_container.get_children():
		if child != _empty_label:
			child.queue_free()

	if _deployment_manager == null or _deployment_manager.carrier == null:
		_empty_label.visible = true
		return

	var hangar: Hangar = _deployment_manager.carrier.get_hangar()
	var mechs: Array[MechBlueprint] = hangar.get_mechs()
	_empty_label.visible = mechs.is_empty()

	var selected: Array[int] = _deployment_manager.get_selected_indices()
	var pilot_idx: int = _deployment_manager.get_pilot_index()

	for i: int in mechs.size():
		var bp: MechBlueprint = mechs[i]
		var is_selected: bool = i in selected
		var is_pilot: bool = i == pilot_idx
		var row := _build_mech_row(bp, i, is_selected, is_pilot)
		_mechs_container.add_child(row)


func _build_mech_row(
	bp: MechBlueprint,
	index: int,
	is_selected: bool,
	is_pilot: bool,
) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()

	# Visual state based on selection / pilot status
	if is_pilot:
		style.bg_color = SELECTED_BG.lightened(0.05)
		_apply_border(style, 2, PILOT_BORDER)
	elif is_selected:
		style.bg_color = SELECTED_BG
		_apply_border(style, 1, SELECTED_BORDER)
	else:
		style.bg_color = ROW_BG
		_apply_border(style, 1, BORDER_COLOR)

	_apply_corner_radius(style, CORNER_RADIUS_SM)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Top row: deploy toggle + name + pilot indicator + pilot button
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	vbox.add_child(top_row)

	# Deploy toggle button
	var deploy_btn: Button
	if is_selected:
		deploy_btn = _make_button("[x] Selected", ACCENT_COLOR)
	else:
		deploy_btn = _make_button("Deploy", DIM_COLOR)
	deploy_btn.custom_minimum_size = Vector2(90, 26)
	deploy_btn.pressed.connect(_on_deploy_toggled.bind(index))
	top_row.add_child(deploy_btn)

	# Mech name
	var name_color: Color = Color.WHITE if is_selected else LABEL_COLOR
	var name_lbl := _make_label(String(bp.blueprint_name), name_color, FONT_NORMAL)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(name_lbl)

	# Pilot indicator (only when this mech is the pilot)
	if is_pilot:
		var pilot_indicator := _make_label("[*] PILOT", WARNING_COLOR, FONT_NORMAL)
		top_row.add_child(pilot_indicator)

	# Pilot assignment button (only shown when mech is selected)
	if is_selected:
		var pilot_btn: Button
		if is_pilot:
			pilot_btn = _make_button("Piloting", WARNING_COLOR)
		else:
			pilot_btn = _make_button("Set Pilot", DIM_COLOR)
		pilot_btn.custom_minimum_size = Vector2(80, 26)
		pilot_btn.pressed.connect(_on_pilot_pressed.bind(index))
		top_row.add_child(pilot_btn)

	# Chassis stats line
	if bp.chassis:
		var stats_text := "Chassis: %s  |  Speed: %.0f  |  Heat Cap: %.0f  |  Integrity: %.0f" \
			% [String(bp.chassis.chassis_name), bp.chassis.base_speed,
			   bp.chassis.base_max_heat, bp.chassis.base_integrity]
		var stats_lbl := _make_label(stats_text, DIM_COLOR, FONT_SMALL)
		vbox.add_child(stats_lbl)

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
		var no_chassis := _make_label("(No chassis data)", DIM_COLOR, FONT_SMALL)
		vbox.add_child(no_chassis)

	return panel

# -- Cost Display ----------------------------------------------------------

func _update_cost_display() -> void:
	if _deployment_manager == null:
		return

	var cost: int = _deployment_manager.get_deploy_cost()
	var can_afford: bool = _deployment_manager.can_afford_deployment()
	var can_launch: bool = _deployment_manager.can_launch()

	# Cost label
	var cost_color: Color = DANGER_COLOR if (cost > 0 and not can_afford) else LABEL_COLOR
	_cost_label.text = "Deployment Cost: %d fuel" % cost
	_cost_label.add_theme_color_override("font_color", cost_color)

	# Fuel label
	var fuel_amount: int = 0
	if _deployment_manager.carrier != null:
		fuel_amount = _deployment_manager.carrier.get_inventory().get_amount(
			DeploymentManager.FUEL_RESOURCE
		)
	_fuel_label.text = "You have: %d fuel" % fuel_amount

	# Launch button state
	_launch_btn.disabled = not can_launch

# -- Actions ---------------------------------------------------------------

func _on_deploy_toggled(index: int) -> void:
	if _deployment_manager == null:
		return
	_deployment_manager.select_mech(index)
	_refresh()
	print("[DeploymentUI] Toggled mech selection at index %d" % index)


func _on_pilot_pressed(index: int) -> void:
	if _deployment_manager == null:
		return
	_deployment_manager.set_pilot(index)
	_refresh()
	print("[DeploymentUI] Set pilot to index %d" % index)


func _on_deploy_all_pressed() -> void:
	if _deployment_manager == null:
		return
	_deployment_manager.select_all()
	_refresh()
	print("[DeploymentUI] Deploy All — selected every mech")


func _on_clear_pressed() -> void:
	if _deployment_manager == null:
		return
	_deployment_manager.deselect_all()
	_refresh()
	print("[DeploymentUI] Clear — deselected all mechs")


func _on_launch_pressed() -> void:
	if _deployment_manager == null:
		return
	if not _deployment_manager.can_launch():
		push_warning("[DeploymentUI] Launch pressed but can_launch() is false")
		return
	print("[DeploymentUI] Launching deployment!")
	_deployment_manager.launch()


func _on_retreat_pressed() -> void:
	if _deployment_manager == null:
		return
	print("[DeploymentUI] Retreating from engagement")
	_deployment_manager.retreat()

# -- Refresh ---------------------------------------------------------------

## Rebuild mech rows and update cost/button state after any selection change.
func _refresh() -> void:
	_rebuild_mech_list()
	_update_cost_display()

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


func _make_label(text: String, color: Color, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _make_button(text: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 28)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	var normal := StyleBoxFlat.new()
	normal.bg_color = BTN_BG
	_apply_corner_radius(normal, CORNER_RADIUS_SM)
	_apply_border(normal, 1, BTN_BORDER)
	_apply_btn_margins(normal)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = BTN_BG_HOVER
	_apply_corner_radius(hover, CORNER_RADIUS_SM)
	_apply_border(hover, 1, accent.darkened(0.2))
	_apply_btn_margins(hover)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = accent.darkened(0.6)
	_apply_corner_radius(pressed, CORNER_RADIUS_SM)
	_apply_border(pressed, 1, accent)
	_apply_btn_margins(pressed)
	btn.add_theme_stylebox_override("pressed", pressed)

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = BTN_BG_DISABLED
	_apply_corner_radius(disabled, CORNER_RADIUS_SM)
	_apply_border(disabled, 1, Color(0.15, 0.15, 0.2, 0.4))
	_apply_btn_margins(disabled)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_color_override("font_color", LABEL_COLOR)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", accent)
	btn.add_theme_color_override("font_disabled_color", BTN_COLOR_DISABLED)
	btn.add_theme_font_size_override("font_size", FONT_NORMAL)

	return btn


func _add_separator(parent: VBoxContainer) -> void:
	var sep := ColorRect.new()
	sep.color = Color(0.2, 0.24, 0.35, 0.5)
	sep.custom_minimum_size = Vector2(0, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sep)


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
