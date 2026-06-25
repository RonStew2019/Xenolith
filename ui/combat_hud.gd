extends CanvasLayer
class_name CombatHUD
## In-combat HUD overlay — enemy reactor display, notifications, reserve panel.
##
## Entirely programmatic — no .tscn needed.
## Created by [EngagementManager] at the start of combat and freed on cleanup.
##
## Contains three sub-widgets:
## [br]1. [b]Enemy Reactor Display[/b] — top-left panel showing the enemy
##    target's integrity and heat bars.
## [br]2. [b]Notification Overlay[/b] — center-screen tween-animated messages
##    for mech destruction, pilot switching, victory, and defeat.
## [br]3. [b]Reserve Deployment Panel[/b] — togglable bottom-right panel for
##    deploying hangar mechs mid-combat (Tab key).

# -- Palette (matches DeploymentUI / ReactorHUD) --------------------------

const PANEL_BG := Color(0.05, 0.05, 0.08, 0.92)
const BORDER_COLOR := Color(0.25, 0.3, 0.45, 0.6)
const LABEL_COLOR := Color(0.8, 0.85, 0.9)
const HEADER_COLOR := Color(0.5, 0.7, 1.0)
const ACCENT_COLOR := Color(0.2, 0.5, 1.0)
const DIM_COLOR := Color(0.45, 0.48, 0.55)
const DANGER_COLOR := Color(0.9, 0.3, 0.3)
const SUCCESS_COLOR := Color(0.3, 0.85, 0.4)
const WARNING_COLOR := Color(1.0, 0.7, 0.2)

# Heat / integrity ramp (mirrors ReactorHUD)
const HEAT_COOL := Color(0.2, 0.5, 1.0)
const HEAT_WARM := Color(1.0, 0.85, 0.0)
const HEAT_HOT := Color(1.0, 0.4, 0.0)
const HEAT_CRIT := Color(1.0, 0.1, 0.1)
const INTEGRITY_FULL := Color(0.1, 0.9, 0.4)
const INTEGRITY_LOW := Color(0.9, 0.15, 0.15)
const BAR_BG := Color(0.12, 0.12, 0.18)

# Button palette
const BTN_BG := Color(0.08, 0.08, 0.12, 0.7)
const BTN_BORDER := Color(0.2, 0.25, 0.38, 0.5)
const BTN_BG_HOVER := Color(0.12, 0.14, 0.22, 0.9)
const BTN_BG_DISABLED := Color(0.06, 0.06, 0.08, 0.5)
const BTN_COLOR_DISABLED := Color(0.35, 0.35, 0.4)
const ROW_BG := Color(0.06, 0.06, 0.1, 0.8)

# Layout
const CORNER_RADIUS := 6
const CORNER_RADIUS_SM := 4
const FONT_TITLE := 20
const FONT_HEADER := 16
const FONT_NORMAL := 13
const FONT_SMALL := 11

# Reserve panel
const RESERVE_PANEL_WIDTH := 320.0
const RESERVE_PANEL_HEIGHT := 360.0

# Notification timing
const NOTIF_FADE_IN := 0.25
const NOTIF_LINGER := 2.5
const NOTIF_FADE_OUT := 0.5
const NOTIF_MINOR_LINGER := 1.5

# -- State -----------------------------------------------------------------

var _engagement_manager: EngagementManager = null
var _arena: CombatArena = null
var _carrier: Carrier = null

# Root control
var _root: Control

# Widget 1 — Enemy reactor display
var _enemy_panel: PanelContainer
var _enemy_name_label: Label
var _enemy_integrity_bar: ProgressBar
var _enemy_integrity_label: Label
var _enemy_integrity_fill: StyleBoxFlat
var _enemy_heat_bar: ProgressBar
var _enemy_heat_label: Label
var _enemy_heat_fill: StyleBoxFlat
var _enemy_reactor: Node = null

# Widget 2 — Notification overlay
var _notif_container: VBoxContainer
var _notif_primary: Label
var _notif_secondary: Label
var _notif_tween: Tween

# Widget 3 — Reserve deployment panel
var _reserve_panel: PanelContainer
var _reserve_root: Control  # Wrapper for mouse filter toggling
var _reserve_list: VBoxContainer
var _reserve_fuel_label: Label
var _reserve_empty_label: Label
var _reserve_open: bool = false
var _reserve_hint_label: Label


func _ready() -> void:
	layer = 10  # Match DeploymentUI
	_build_ui()
	_set_reserve_visible(false)


# -- Public API ------------------------------------------------------------

## Wire up all sub-widgets to their data sources.
## Called from [EngagementManager.begin_engagement] after arena setup.
func setup(engagement_mgr: EngagementManager, arena: CombatArena, carrier: Carrier) -> void:
	_engagement_manager = engagement_mgr
	_arena = arena
	_carrier = carrier

	# Widget 1 — bind enemy reactor
	var enemy: CombatTarget = arena.get_enemy_target()
	if enemy != null:
		_enemy_name_label.text = String(enemy.display_name) if enemy.display_name != &"" else "ENEMY"
		var reactor: Node = enemy.get_reactor()
		if reactor != null:
			_enemy_reactor = reactor
			reactor.integrity_changed.connect(_on_enemy_integrity_changed)
			reactor.heat_changed.connect(_on_enemy_heat_changed)
			# Initial update
			_on_enemy_integrity_changed(reactor.integrity, reactor.max_integrity)
			_on_enemy_heat_changed(reactor.heat, reactor.max_heat)
	else:
		_enemy_panel.visible = false

	# Widget 2 — bind engagement signals for notifications
	engagement_mgr.mech_destroyed.connect(_on_mech_destroyed)
	engagement_mgr.pilot_switched.connect(_on_pilot_switched)
	engagement_mgr.engagement_won.connect(_on_engagement_won)
	engagement_mgr.engagement_lost.connect(_on_engagement_lost)
	engagement_mgr.reserve_deployed.connect(_on_reserve_deployed)

	# Widget 3 — initial populate
	_rebuild_reserve_list()


# -- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_TAB:
		_toggle_reserve_panel()
		get_viewport().set_input_as_handled()


# -- Widget 1: Enemy Reactor Display — Signal Handlers ---------------------

func _on_enemy_integrity_changed(current: float, maximum: float) -> void:
	_enemy_integrity_bar.max_value = maximum
	_enemy_integrity_bar.value = current
	_enemy_integrity_label.text = "%d / %d" % [ceili(current), ceili(maximum)]
	var ratio := current / maxf(maximum, 0.001)
	_enemy_integrity_fill.bg_color = INTEGRITY_LOW.lerp(INTEGRITY_FULL, ratio)


func _on_enemy_heat_changed(current: float, maximum: float) -> void:
	_enemy_heat_bar.max_value = maximum
	_enemy_heat_bar.value = clampf(current, 0.0, maximum)
	_enemy_heat_label.text = "%d / %d" % [ceili(current), ceili(maximum)]
	var ratio := clampf(current / maxf(maximum, 0.001), 0.0, 1.0)
	_enemy_heat_fill.bg_color = _heat_color_ramp(ratio)


# -- Widget 2: Notification Overlay — Signal Handlers ----------------------

func _on_mech_destroyed(mech: MechBody, blueprint: MechBlueprint) -> void:
	var mech_name: String = String(blueprint.blueprint_name) if blueprint != null else "Unknown"
	_show_notification("Mech Lost: %s" % mech_name, DANGER_COLOR, FONT_HEADER, "", Color.WHITE, NOTIF_MINOR_LINGER)


func _on_pilot_switched(new_pilot: MechBody, blueprint: MechBlueprint) -> void:
	var mech_name: String = String(blueprint.blueprint_name) if blueprint != null else "Unknown"
	_show_notification(
		"MECH DESTROYED", DANGER_COLOR, FONT_TITLE,
		"Switching to: %s" % mech_name, WARNING_COLOR, NOTIF_LINGER,
	)


func _on_engagement_won() -> void:
	_show_notification("VICTORY", SUCCESS_COLOR, 28, "", Color.WHITE, NOTIF_LINGER + 1.0)
	# Close reserve panel on combat end
	if _reserve_open:
		_toggle_reserve_panel()


func _on_engagement_lost() -> void:
	_show_notification("DEFEAT", DANGER_COLOR, 28, "", Color.WHITE, NOTIF_LINGER + 1.0)
	if _reserve_open:
		_toggle_reserve_panel()


func _on_reserve_deployed(mech: MechBody, blueprint: MechBlueprint) -> void:
	_rebuild_reserve_list()


# -- Widget 2: Notification Animation --------------------------------------

func _show_notification(
	primary_text: String, primary_color: Color, primary_size: int,
	secondary_text: String, secondary_color: Color,
	linger: float,
) -> void:
	# Kill previous notification tween
	if _notif_tween != null and _notif_tween.is_valid():
		_notif_tween.kill()

	_notif_primary.text = primary_text
	_notif_primary.add_theme_color_override("font_color", primary_color)
	_notif_primary.add_theme_font_size_override("font_size", primary_size)

	if secondary_text != "":
		_notif_secondary.text = secondary_text
		_notif_secondary.add_theme_color_override("font_color", secondary_color)
		_notif_secondary.visible = true
	else:
		_notif_secondary.visible = false

	_notif_container.modulate.a = 0.0
	_notif_container.visible = true

	_notif_tween = create_tween()
	_notif_tween.tween_property(_notif_container, "modulate:a", 1.0, NOTIF_FADE_IN)
	_notif_tween.tween_interval(linger)
	_notif_tween.tween_property(_notif_container, "modulate:a", 0.0, NOTIF_FADE_OUT)
	_notif_tween.tween_callback(_notif_container.set.bind("visible", false))


# -- Widget 3: Reserve Panel — Toggle & Rebuild ----------------------------

func _toggle_reserve_panel() -> void:
	_reserve_open = not _reserve_open
	if _reserve_open:
		_rebuild_reserve_list()
		_set_reserve_visible(true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_set_reserve_visible(false)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_reserve_visible(vis: bool) -> void:
	_reserve_root.visible = vis
	# When open, stop mouse events from passing through.
	# When closed, ignore everything.
	_reserve_root.mouse_filter = Control.MOUSE_FILTER_STOP if vis else Control.MOUSE_FILTER_IGNORE


func _rebuild_reserve_list() -> void:
	# Clear old rows (keep permanent children)
	for child in _reserve_list.get_children():
		if child != _reserve_empty_label and child != _reserve_fuel_label:
			child.queue_free()

	if _carrier == null:
		_reserve_empty_label.visible = true
		_reserve_empty_label.text = "No carrier connection."
		return

	var hangar: Hangar = _carrier.get_hangar()
	var inventory: Inventory = _carrier.get_inventory()
	var mechs: Array[MechBlueprint] = hangar.get_mechs()

	# Fuel display
	var fuel: int = inventory.get_amount(&"fuel")
	_reserve_fuel_label.text = "Fuel: %d" % fuel
	var any_affordable: bool = false

	_reserve_empty_label.visible = mechs.is_empty()

	for i: int in mechs.size():
		var bp: MechBlueprint = mechs[i]
		var mech_cost: int = bp.chassis.deploy_fuel_cost if bp.chassis != null else 5
		var can_afford: bool = inventory.has_enough(&"fuel", mech_cost)
		if can_afford:
			any_affordable = true
		var row := _build_reserve_row(bp, i, can_afford, mech_cost)
		_reserve_list.add_child(row)

	_reserve_fuel_label.add_theme_color_override(
		"font_color", LABEL_COLOR if any_affordable or mechs.is_empty() else DANGER_COLOR
	)


func _build_reserve_row(bp: MechBlueprint, index: int, can_afford: bool, fuel_cost: int = 5) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ROW_BG
	_apply_corner_radius(style, CORNER_RADIUS_SM)
	_apply_border(style, 1, BORDER_COLOR)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	# Mech info (left side)
	var info_vbox := VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 2)
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_lbl := _make_label(String(bp.blueprint_name), LABEL_COLOR, FONT_NORMAL)
	info_vbox.add_child(name_lbl)

	if bp.chassis != null:
		var chassis_text := "Chassis: %s" % String(bp.chassis.chassis_name)
		var chassis_lbl := _make_label(chassis_text, DIM_COLOR, FONT_SMALL)
		info_vbox.add_child(chassis_lbl)

	# Fuel cost label
	var cost_lbl := _make_label("%d fuel" % fuel_cost, DIM_COLOR, FONT_SMALL)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_lbl.custom_minimum_size.x = 60.0
	hbox.add_child(cost_lbl)

	# Deploy button (right side)
	var deploy_btn := _make_button("Deploy", ACCENT_COLOR)
	deploy_btn.custom_minimum_size = Vector2(72, 28)
	deploy_btn.disabled = not can_afford
	deploy_btn.pressed.connect(_on_deploy_reserve_pressed.bind(index))
	hbox.add_child(deploy_btn)

	return panel


func _on_deploy_reserve_pressed(hangar_index: int) -> void:
	if _engagement_manager == null:
		return
	var success: bool = _engagement_manager.deploy_reserve(hangar_index)
	if success:
		_rebuild_reserve_list()


# -- UI Construction -------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_enemy_display()
	_build_notification_overlay()
	_build_reserve_panel()


# -- Widget 1: Enemy Reactor Display Build ---------------------------------

func _build_enemy_display() -> void:
	_enemy_panel = PanelContainer.new()
	_enemy_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_enemy_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_enemy_panel.offset_left = 16.0
	_enemy_panel.offset_top = 16.0
	_enemy_panel.offset_right = 16.0 + 280.0
	_enemy_panel.offset_bottom = 16.0 + 120.0
	_enemy_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_enemy_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_panel.add_child(vbox)

	# Enemy name header
	_enemy_name_label = _make_label("ENEMY", HEADER_COLOR, FONT_HEADER)
	vbox.add_child(_enemy_name_label)

	var sep := _make_separator()
	vbox.add_child(sep)

	# Integrity bar row
	var int_row := _build_bar_row("INTEGRITY", INTEGRITY_FULL)
	vbox.add_child(int_row.container)
	_enemy_integrity_bar = int_row.bar
	_enemy_integrity_label = int_row.value_label
	_enemy_integrity_fill = int_row.fill_style

	# Heat bar row
	var heat_row := _build_bar_row("HEAT", HEAT_COOL)
	vbox.add_child(heat_row.container)
	_enemy_heat_bar = heat_row.bar
	_enemy_heat_label = heat_row.value_label
	_enemy_heat_fill = heat_row.fill_style


# -- Widget 2: Notification Overlay Build ----------------------------------

func _build_notification_overlay() -> void:
	_notif_container = VBoxContainer.new()
	_notif_container.set_anchors_preset(Control.PRESET_CENTER)
	_notif_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notif_container.grow_vertical = Control.GROW_DIRECTION_BOTH
	_notif_container.add_theme_constant_override("separation", 6)
	_notif_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notif_container.visible = false
	_root.add_child(_notif_container)

	_notif_primary = Label.new()
	_notif_primary.text = ""
	_notif_primary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notif_primary.add_theme_color_override("font_color", DANGER_COLOR)
	_notif_primary.add_theme_font_size_override("font_size", FONT_TITLE)
	_notif_primary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notif_container.add_child(_notif_primary)

	_notif_secondary = Label.new()
	_notif_secondary.text = ""
	_notif_secondary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notif_secondary.add_theme_color_override("font_color", WARNING_COLOR)
	_notif_secondary.add_theme_font_size_override("font_size", FONT_HEADER)
	_notif_secondary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notif_secondary.visible = false
	_notif_container.add_child(_notif_secondary)


# -- Widget 3: Reserve Deployment Panel Build ------------------------------

func _build_reserve_panel() -> void:
	# Wrapper Control for mouse filter toggling
	_reserve_root = Control.new()
	_reserve_root.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_reserve_root.offset_right = -16.0
	_reserve_root.offset_bottom = -16.0
	_reserve_root.offset_left = -16.0 - RESERVE_PANEL_WIDTH
	_reserve_root.offset_top = -16.0 - RESERVE_PANEL_HEIGHT
	_reserve_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_reserve_root)

	_reserve_panel = PanelContainer.new()
	_reserve_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_reserve_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reserve_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_reserve_root.add_child(_reserve_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_reserve_panel.add_child(vbox)

	# Header row
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	vbox.add_child(header_row)

	var header := _make_label("RESERVE DEPLOYMENT", HEADER_COLOR, FONT_HEADER)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header)

	_reserve_hint_label = _make_label("[Tab] Close", DIM_COLOR, FONT_SMALL)
	header_row.add_child(_reserve_hint_label)

	vbox.add_child(_make_separator())

	# Fuel display
	_reserve_fuel_label = _make_label("Fuel: --", LABEL_COLOR, FONT_NORMAL)
	vbox.add_child(_reserve_fuel_label)

	vbox.add_child(_make_separator())

	# Scrollable mech list
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_reserve_list = VBoxContainer.new()
	_reserve_list.add_theme_constant_override("separation", 4)
	_reserve_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_reserve_list)

	_reserve_empty_label = _make_label("No reserves available.", DIM_COLOR, FONT_NORMAL)
	_reserve_list.add_child(_reserve_empty_label)


# -- Bar Row Builder (shared by enemy display) -----------------------------

func _build_bar_row(title: String, fill_color: Color) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lbl := _make_label(title, LABEL_COLOR, FONT_SMALL)
	lbl.custom_minimum_size.x = 68.0
	row.add_child(lbl)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(100, 16)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _make_bar_bg())

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	_apply_corner_radius(fill, 3)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)

	var val_lbl := _make_label("--", LABEL_COLOR, FONT_SMALL)
	val_lbl.custom_minimum_size.x = 56.0
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)

	return {
		"container": row,
		"bar": bar,
		"value_label": val_lbl,
		"fill_style": fill,
	}


# -- Color Ramp (mirrors ReactorHUD._heat_color_ramp) ---------------------

func _heat_color_ramp(ratio: float) -> Color:
	if ratio < 0.33:
		return HEAT_COOL.lerp(HEAT_WARM, ratio / 0.33)
	if ratio < 0.66:
		return HEAT_WARM.lerp(HEAT_HOT, (ratio - 0.33) / 0.33)
	return HEAT_HOT.lerp(HEAT_CRIT, (ratio - 0.66) / 0.34)


# -- Style Factories -------------------------------------------------------

func _make_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	_apply_corner_radius(s, CORNER_RADIUS)
	s.content_margin_left = 12.0
	s.content_margin_right = 12.0
	s.content_margin_top = 8.0
	s.content_margin_bottom = 8.0
	_apply_border(s, 1, BORDER_COLOR)
	return s


func _make_bar_bg() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BAR_BG
	_apply_corner_radius(s, 3)
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


func _make_separator() -> ColorRect:
	var sep := ColorRect.new()
	sep.color = Color(0.2, 0.24, 0.35, 0.5)
	sep.custom_minimum_size = Vector2(0, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep


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
