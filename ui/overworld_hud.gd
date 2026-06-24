extends CanvasLayer
class_name OverworldHUD
## Strategic overworld HUD layer.
##
## Contains two always-visible panels for the hex grid strategic view:
##   • Hex Info Panel (bottom-left) — terrain, resource, and occupant data
##     for the hex under the mouse cursor.
##   • Carrier Status Panel (top-left) — hull, resources, hangar, modules,
##     and harvest state.
##
## Auto-discovers [HexGrid], [Carrier], and [ThreatManager] siblings in
## [method _ready].  Entirely programmatic — no .tscn needed for the UI
## nodes themselves.

# ── Palette (matches ReactorHUD / CarrierCustomizationUI) ────────────────

const PANEL_BG := Color(0.05, 0.05, 0.08, 0.85)
const LABEL_COLOR := Color(0.8, 0.85, 0.9)
const HEADER_COLOR := Color(0.5, 0.7, 1.0)
const BORDER_COLOR := Color(0.25, 0.3, 0.45, 0.6)
const ACCENT_COLOR := Color(0.2, 0.5, 1.0)
const DIM_COLOR := Color(0.45, 0.48, 0.55)
const BAR_BG := Color(0.12, 0.12, 0.18)

const HULL_FULL := Color(0.1, 0.9, 0.4)
const HULL_LOW := Color(0.9, 0.15, 0.15)

# ── Layout Constants ─────────────────────────────────────────────────────

const CORNER_RADIUS := 6
const PANEL_MARGIN := 16.0
const HEX_PANEL_WIDTH := 260.0
const HEX_PANEL_HEIGHT := 210.0
const CARRIER_PANEL_WIDTH := 250.0
const CARRIER_PANEL_HEIGHT := 310.0
const SWATCH_SIZE := Vector2(14, 14)
const SWATCH_RADIUS := 2

# ── Terrain Data ─────────────────────────────────────────────────────────

const TERRAIN_NAMES: Dictionary = {
	HexCell.TerrainType.MOUNTAIN:   "Mountain",
	HexCell.TerrainType.FLORA:      "Flora",
	HexCell.TerrainType.DESERT:     "Desert",
	HexCell.TerrainType.IRRADIATED: "Irradiated",
	HexCell.TerrainType.RESOURCE:   "Resource",
}

const TERRAIN_FLAVOR: Dictionary = {
	HexCell.TerrainType.MOUNTAIN:   "Decent cover, not choked",
	HexCell.TerrainType.FLORA:      "Dense — favors dogfighters",
	HexCell.TerrainType.DESERT:     "Wide open — favors bombers",
	HexCell.TerrainType.IRRADIATED: "Ambient overheating — hazardous",
	HexCell.TerrainType.RESOURCE:   "Harvestable resource node",
}

# ── Resource Colors ──────────────────────────────────────────────────────

const RES_COLORS: Dictionary = {
	&"metal":   Color(0.7, 0.7, 0.75),
	&"crystal": Color(0.1, 0.8, 0.9),
	&"fuel":    Color(1.0, 0.6, 0.2),
}

# ── Sibling References (auto-discovered) ─────────────────────────────────

var _hex_grid: HexGrid = null
var _carrier: Carrier = null

# ── Hex Info Panel Refs ──────────────────────────────────────────────────

var _hex_empty_label: Label
var _hex_terrain_row: HBoxContainer
var _hex_terrain_swatch_style: StyleBoxFlat
var _hex_terrain_name_label: Label
var _hex_flavor_label: Label
var _hex_resource_label: Label
var _hex_occupant_label: Label
var _hex_threat_label: Label
var _hex_coords_label: Label

# ── Carrier Panel Refs ───────────────────────────────────────────────────

var _hull_bar: ProgressBar
var _hull_label: Label
var _hull_fill: StyleBoxFlat
var _metal_label: Label
var _crystal_label: Label
var _fuel_label: Label
var _hangar_label: Label
var _slots_label: Label
var _power_label: Label
var _harvest_label: Label
var _harvest_tween: Tween
var _position_label: Label

# ── State ────────────────────────────────────────────────────────────────

## Axial coords of the hex currently under the mouse, or sentinel (-999,-999).
var _hovered_hex: Vector2i = Vector2i(-999, -999)

## Root control filling the viewport — all panels are children of this.
var _root: Control


# ── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	# Auto-discover siblings.
	if get_parent() != null:
		_hex_grid = get_parent().get_node_or_null("HexGrid") as HexGrid
		_carrier = get_parent().get_node_or_null("Carrier") as Carrier

	_build_ui()

	if _carrier != null:
		_bind_carrier(_carrier)


func _process(_delta: float) -> void:
	_update_hex_info_from_mouse()


# ── UI Root ──────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_hex_info_panel()
	_build_carrier_panel()


# ── Hex Info Panel — Construction ────────────────────────────────────────

func _build_hex_info_panel() -> void:
	var wrapper := Control.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	wrapper.offset_left = PANEL_MARGIN
	wrapper.offset_bottom = -PANEL_MARGIN
	wrapper.offset_top = -PANEL_MARGIN - HEX_PANEL_HEIGHT
	wrapper.offset_right = PANEL_MARGIN + HEX_PANEL_WIDTH
	_root.add_child(wrapper)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	wrapper.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Header
	vbox.add_child(_make_label("HEX INFO", HEADER_COLOR, 14))
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	vbox.add_child(sep)

	# Terrain row — color swatch + terrain name
	_hex_terrain_row = HBoxContainer.new()
	_hex_terrain_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hex_terrain_row.add_theme_constant_override("separation", 8)
	_hex_terrain_row.visible = false
	vbox.add_child(_hex_terrain_row)

	var swatch := PanelContainer.new()
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.custom_minimum_size = SWATCH_SIZE
	_hex_terrain_swatch_style = StyleBoxFlat.new()
	_hex_terrain_swatch_style.bg_color = Color.GRAY
	_apply_corner_radius(_hex_terrain_swatch_style, SWATCH_RADIUS)
	swatch.add_theme_stylebox_override("panel", _hex_terrain_swatch_style)
	_hex_terrain_row.add_child(swatch)

	_hex_terrain_name_label = _make_label("Terrain", LABEL_COLOR, 13)
	_hex_terrain_row.add_child(_hex_terrain_name_label)

	# Flavor text
	_hex_flavor_label = _make_label("", DIM_COLOR, 11)
	_hex_flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hex_flavor_label.visible = false
	vbox.add_child(_hex_flavor_label)

	# Resource info (visible only on RESOURCE terrain)
	_hex_resource_label = _make_label("", RES_COLORS[&"metal"], 12)
	_hex_resource_label.visible = false
	vbox.add_child(_hex_resource_label)

	# Occupant
	_hex_occupant_label = _make_label("", LABEL_COLOR, 12)
	_hex_occupant_label.visible = false
	vbox.add_child(_hex_occupant_label)

	# Threat level (visible only when occupant is ThreatEntity)
	_hex_threat_label = _make_label("", Color(1.0, 0.4, 0.3), 12)
	_hex_threat_label.visible = false
	vbox.add_child(_hex_threat_label)

	# Coordinates (dim)
	_hex_coords_label = _make_label("", DIM_COLOR, 10)
	_hex_coords_label.visible = false
	vbox.add_child(_hex_coords_label)

	# Empty / placeholder
	_hex_empty_label = _make_label("Hover over a hex...", DIM_COLOR, 12)
	vbox.add_child(_hex_empty_label)


# ── Hex Info Panel — Update ──────────────────────────────────────────────

## Raycast from the current mouse position onto the Y=0 ground plane and
## show info for whatever hex the cursor is over.
func _update_hex_info_from_mouse() -> void:
	if _hex_grid == null:
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)

	if is_zero_approx(dir.y):
		if _hovered_hex != Vector2i(-999, -999):
			_hovered_hex = Vector2i(-999, -999)
			_clear_hex_info()
		return

	var t := -from.y / dir.y
	var hit := from + dir * t
	var axial := _hex_grid.world_to_axial(hit)

	var cell := _hex_grid.get_cell(axial.x, axial.y)
	if cell == null:
		if _hovered_hex != Vector2i(-999, -999):
			_hovered_hex = Vector2i(-999, -999)
			_clear_hex_info()
		return

	_hovered_hex = axial
	_show_hex_info(cell)


## Populate the hex info panel with data from [param cell].
func _show_hex_info(cell: HexCell) -> void:
	_hex_empty_label.visible = false

	# Terrain
	_hex_terrain_row.visible = true
	_hex_terrain_swatch_style.bg_color = HexGrid.TERRAIN_COLORS.get(
		cell.terrain, Color.GRAY
	)
	_hex_terrain_name_label.text = TERRAIN_NAMES.get(cell.terrain, "Unknown")

	# Flavor
	_hex_flavor_label.visible = true
	_hex_flavor_label.text = TERRAIN_FLAVOR.get(cell.terrain, "")

	# Resource (only on RESOURCE terrain with a valid subtype)
	if cell.terrain == HexCell.TerrainType.RESOURCE \
			and cell.resource_type != &"":
		_hex_resource_label.visible = true
		var res_name := String(cell.resource_type).to_pascal_case()
		_hex_resource_label.text = "%s: %.0f remaining" % [
			res_name, cell.resource_amount
		]
		_hex_resource_label.add_theme_color_override(
			"font_color",
			RES_COLORS.get(cell.resource_type, LABEL_COLOR)
		)
	else:
		_hex_resource_label.visible = false

	# Occupant
	if cell.occupant != null:
		_hex_occupant_label.visible = true
		if cell.occupant is Carrier:
			_hex_occupant_label.text = "Occupant: Your Carrier"
		elif cell.occupant is ThreatEntity:
			var threat := cell.occupant as ThreatEntity
			_hex_occupant_label.text = "Occupant: %s" % threat.entity_name
		else:
			_hex_occupant_label.text = "Occupant: %s" % cell.occupant.name
	else:
		_hex_occupant_label.visible = false

	# Threat level
	if cell.occupant is ThreatEntity:
		_hex_threat_label.visible = true
		var threat := cell.occupant as ThreatEntity
		_hex_threat_label.text = "!! Threat Level: %.1f" % threat.threat_level
	else:
		_hex_threat_label.visible = false

	# Coordinates
	_hex_coords_label.visible = true
	_hex_coords_label.text = "(%d, %d)" % [cell.q, cell.r]


## Reset the hex info panel to the empty/placeholder state.
func _clear_hex_info() -> void:
	_hex_empty_label.visible = true
	_hex_terrain_row.visible = false
	_hex_flavor_label.visible = false
	_hex_resource_label.visible = false
	_hex_occupant_label.visible = false
	_hex_threat_label.visible = false
	_hex_coords_label.visible = false


# ── Carrier Status Panel — Construction ──────────────────────────────────

func _build_carrier_panel() -> void:
	var wrapper := Control.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.set_anchors_preset(Control.PRESET_TOP_LEFT)
	wrapper.offset_left = PANEL_MARGIN
	wrapper.offset_top = PANEL_MARGIN
	wrapper.offset_right = PANEL_MARGIN + CARRIER_PANEL_WIDTH
	wrapper.offset_bottom = PANEL_MARGIN + CARRIER_PANEL_HEIGHT
	_root.add_child(wrapper)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	wrapper.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Header
	vbox.add_child(_make_label("CARRIER STATUS", HEADER_COLOR, 14))
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	vbox.add_child(sep)

	# Hull bar
	var hull_row := _build_bar_row("HULL", HULL_FULL)
	vbox.add_child(hull_row.container)
	_hull_bar = hull_row.bar
	_hull_label = hull_row.value_label
	_hull_fill = hull_row.fill_style

	# Separator before resources
	var sep2 := HSeparator.new()
	sep2.add_theme_constant_override("separation", 2)
	vbox.add_child(sep2)

	# Resources header
	vbox.add_child(_make_label("RESOURCES", DIM_COLOR, 11))

	_metal_label = _build_resource_row(vbox, "Metal", RES_COLORS[&"metal"])
	_crystal_label = _build_resource_row(vbox, "Crystal", RES_COLORS[&"crystal"])
	_fuel_label = _build_resource_row(vbox, "Fuel", RES_COLORS[&"fuel"])

	# Separator before fleet info
	var sep3 := HSeparator.new()
	sep3.add_theme_constant_override("separation", 2)
	vbox.add_child(sep3)

	# Hangar / Modules / Power
	_hangar_label = _make_label("Mechs: 0/0", LABEL_COLOR, 12)
	vbox.add_child(_hangar_label)

	_slots_label = _make_label("Slots: 0/0", LABEL_COLOR, 12)
	vbox.add_child(_slots_label)

	_power_label = _make_label("Power: 0/0", LABEL_COLOR, 12)
	vbox.add_child(_power_label)

	# Harvest indicator (hidden until harvesting begins)
	_harvest_label = _make_label("", ACCENT_COLOR, 12)
	_harvest_label.visible = false
	vbox.add_child(_harvest_label)

	# Current hex position (dim)
	_position_label = _make_label("Hex: (0, 0)", DIM_COLOR, 10)
	vbox.add_child(_position_label)


## Build a resource row with a color swatch, name label, and amount label.
## Returns the amount [Label] so callers can store a reference for updates.
func _build_resource_row(parent: VBoxContainer, res_name: String, color: Color) -> Label:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	# Color swatch
	var swatch := PanelContainer.new()
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.custom_minimum_size = SWATCH_SIZE
	var swatch_style := StyleBoxFlat.new()
	swatch_style.bg_color = color
	_apply_corner_radius(swatch_style, SWATCH_RADIUS)
	swatch.add_theme_stylebox_override("panel", swatch_style)
	row.add_child(swatch)

	# Name
	var name_lbl := _make_label(res_name, LABEL_COLOR, 12)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	# Amount (right-aligned)
	var amount_lbl := _make_label("0", LABEL_COLOR, 12)
	amount_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_lbl.custom_minimum_size.x = 40.0
	row.add_child(amount_lbl)

	return amount_lbl


## Build a labelled progress-bar row (title + bar + value text).
## Returns a Dictionary with keys: container, bar, value_label, fill_style.
func _build_bar_row(title: String, fill_color: Color) -> Dictionary:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)

	var lbl := _make_label(title, LABEL_COLOR, 12)
	lbl.custom_minimum_size.x = 52.0
	row.add_child(lbl)

	var bar := ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(100, 16)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.add_theme_stylebox_override("background", _make_bar_bg())

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	_apply_corner_radius(fill, 3)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)

	var val_lbl := _make_label("--", LABEL_COLOR, 12)
	val_lbl.custom_minimum_size.x = 54.0
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)

	return {
		"container": row,
		"bar": bar,
		"value_label": val_lbl,
		"fill_style": fill,
	}


# ── Carrier Binding ──────────────────────────────────────────────────────

## Connect to all relevant carrier, inventory, and hangar signals.
func _bind_carrier(carrier: Carrier) -> void:
	carrier.moved.connect(_on_carrier_moved)
	carrier.harvesting_started.connect(_on_harvesting_started)
	carrier.harvesting_stopped.connect(_on_harvesting_stopped)
	carrier.module_installed.connect(_on_module_changed)
	carrier.module_uninstalled.connect(_on_module_changed)

	var inventory := carrier.get_inventory()
	if inventory != null:
		inventory.resource_changed.connect(_on_resource_changed)

	var hangar := carrier.get_hangar()
	if hangar != null:
		hangar.mech_stored.connect(_on_hangar_changed)
		hangar.mech_removed.connect(_on_hangar_changed)

	_refresh_all()


## Push every section of the carrier panel to current values.
func _refresh_all() -> void:
	if _carrier == null:
		return
	_refresh_hull()
	_refresh_resources()
	_refresh_hangar()
	_refresh_modules()
	_refresh_position()


func _refresh_hull() -> void:
	if _carrier == null:
		return
	_hull_bar.max_value = _carrier.max_hull
	_hull_bar.value = _carrier.hull
	_hull_label.text = "%d / %d" % [ceili(_carrier.hull), ceili(_carrier.max_hull)]
	var ratio := _carrier.hull / maxf(_carrier.max_hull, 0.001)
	_hull_fill.bg_color = HULL_LOW.lerp(HULL_FULL, ratio)


func _refresh_resources() -> void:
	if _carrier == null:
		return
	var inventory := _carrier.get_inventory()
	if inventory == null:
		return
	_metal_label.text = str(inventory.get_amount(&"metal"))
	_crystal_label.text = str(inventory.get_amount(&"crystal"))
	_fuel_label.text = str(inventory.get_amount(&"fuel"))


func _refresh_hangar() -> void:
	if _carrier == null:
		return
	var hangar := _carrier.get_hangar()
	if hangar == null:
		return
	_hangar_label.text = "Mechs: %d/%d" % [
		hangar.get_mech_count(), hangar.get_max_capacity()
	]


func _refresh_modules() -> void:
	if _carrier == null:
		return
	_slots_label.text = "Slots: %d/%d" % [
		_carrier.get_module_count(), _carrier.max_slots
	]
	_power_label.text = "Power: %d/%d" % [
		_carrier.get_total_power_cost(), _carrier.get_total_power_output()
	]


func _refresh_position() -> void:
	if _carrier == null:
		return
	_position_label.text = "Hex: (%d, %d)" % [
		_carrier.current_hex.x, _carrier.current_hex.y
	]


# ── Carrier Signal Handlers ──────────────────────────────────────────────

func _on_carrier_moved(_from: Vector2i, _to: Vector2i) -> void:
	_refresh_hull()
	_refresh_position()


func _on_resource_changed(_resource_type: StringName, _new_amount: int) -> void:
	_refresh_resources()


func _on_hangar_changed(_blueprint: Variant) -> void:
	_refresh_hangar()


func _on_module_changed(_module: Variant, _slot: int) -> void:
	_refresh_modules()
	_refresh_hangar()  # Capacity may have changed if a HangarModule was added/removed.


func _on_harvesting_started(resource_type: StringName) -> void:
	var res_name := String(resource_type).to_pascal_case()
	_harvest_label.text = ">> Harvesting %s..." % res_name
	_harvest_label.visible = true
	_start_harvest_pulse()


func _on_harvesting_stopped() -> void:
	_harvest_label.visible = false
	_stop_harvest_pulse()


func _start_harvest_pulse() -> void:
	_stop_harvest_pulse()
	_harvest_tween = create_tween().set_loops()
	_harvest_tween.tween_property(_harvest_label, "modulate:a", 0.4, 0.8)
	_harvest_tween.tween_property(_harvest_label, "modulate:a", 1.0, 0.8)


func _stop_harvest_pulse() -> void:
	if _harvest_tween and _harvest_tween.is_valid():
		_harvest_tween.kill()
	_harvest_label.modulate.a = 1.0


# ── Style Factories ──────────────────────────────────────────────────────

func _make_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	_apply_corner_radius(s, CORNER_RADIUS)
	s.content_margin_left = 12.0
	s.content_margin_right = 12.0
	s.content_margin_top = 8.0
	s.content_margin_bottom = 8.0
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = BORDER_COLOR
	return s


func _make_bar_bg() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BAR_BG
	_apply_corner_radius(s, 3)
	return s


func _make_label(lbl_text: String, color: Color, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.text = lbl_text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", font_size)
	return lbl


static func _apply_corner_radius(style: StyleBoxFlat, r: int) -> void:
	style.corner_radius_top_left = r
	style.corner_radius_top_right = r
	style.corner_radius_bottom_left = r
	style.corner_radius_bottom_right = r
