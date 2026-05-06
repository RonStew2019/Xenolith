extends Control
class_name InventoryHUD
## Bottom-left HUD panel showing the player's resource inventory.
##
## Builds the entire UI tree programmatically -- no .tscn needed.
## Call bind_inventory() to wire it to an Inventory node.
## Rows are created/updated dynamically as resources change.
## Shows a dim "Empty" label when the inventory has no resources.

# ── Palette (matches ReactorHUD) ─────────────────────────────────────────

const PANEL_BG := Color(0.05, 0.05, 0.08, 0.85)
const LABEL_COLOR := Color(0.8, 0.85, 0.9)
const HEADER_COLOR := Color(0.5, 0.7, 1.0)
const BORDER_COLOR := Color(0.25, 0.3, 0.45, 0.6)
const EMPTY_COLOR := Color(0.5, 0.5, 0.55, 0.5)

# ── Layout ───────────────────────────────────────────────────────────────

const MIN_PANEL_WIDTH := 200.0
const PANEL_HEIGHT := 160.0
const CORNER_RADIUS := 6
const SWATCH_SIZE := Vector2(14, 14)
const SWATCH_RADIUS := 2

# ── Resource Colors ──────────────────────────────────────────────────────

## Color map for known resource types. Unknown types use FALLBACK_COLOR.
const RESOURCE_COLORS: Dictionary = {
	&"flux": Color(0.1, 0.8, 0.9),
}
const FALLBACK_COLOR := Color(0.5, 0.5, 0.55)

# ── Flash animation ──────────────────────────────────────────────────────

const FLASH_COLOR := Color(1.4, 1.4, 1.4, 1.0)
const FLASH_DURATION := 0.3

# ── Internal refs ────────────────────────────────────────────────────────

var _inventory: Node = null
var _rows_container: VBoxContainer
var _empty_label: Label

## Maps resource StringName → { "row": HBoxContainer, "amount_label": Label }
var _resource_rows: Dictionary = {}
## Maps resource StringName → Tween (active flash tweens)
var _flash_tweens: Dictionary = {}


func _ready() -> void:
	_build_ui()

# ── Binding ──────────────────────────────────────────────────────────────

## Connect to an Inventory node's signals and populate initial state.
func bind_inventory(inventory: Node) -> void:
	if _inventory:
		_unbind()
	_inventory = inventory
	inventory.resource_changed.connect(_on_resource_changed)
	inventory.resource_added.connect(_on_resource_added)
	# Populate initial state
	var all: Dictionary = inventory.get_all_resources()
	for res_type: StringName in all:
		_on_resource_changed(res_type, all[res_type])


func _unbind() -> void:
	if not _inventory:
		return
	_safe_disconnect(_inventory.resource_changed, _on_resource_changed)
	_safe_disconnect(_inventory.resource_added, _on_resource_added)
	_inventory = null

# ── UI Construction ──────────────────────────────────────────────────────

func _build_ui() -> void:
	# Anchor bottom-left (where ReactorHUD used to live)
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 16.0
	offset_bottom = -16.0
	offset_top = offset_bottom - PANEL_HEIGHT
	offset_right = offset_left + MIN_PANEL_WIDTH + 24.0

	# Dark panel
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Header
	var header := _make_label("INVENTORY", HEADER_COLOR, 14)
	vbox.add_child(header)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	vbox.add_child(sep)

	# Rows container (resource rows are added/removed here dynamically)
	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 4)
	vbox.add_child(_rows_container)

	# Empty label (visible when no resources exist)
	_empty_label = _make_label("Empty", EMPTY_COLOR, 12)
	_rows_container.add_child(_empty_label)

# ── Signal Handlers ──────────────────────────────────────────────────────

func _on_resource_changed(resource_type: StringName, new_amount: int) -> void:
	if new_amount <= 0:
		_remove_row(resource_type)
	else:
		_upsert_row(resource_type, new_amount)
	_update_empty_visibility()


func _on_resource_added(resource_type: StringName, _amount_added: int) -> void:
	if resource_type in _resource_rows:
		_flash_row(resource_type)

# ── Row Management ───────────────────────────────────────────────────────

func _upsert_row(resource_type: StringName, amount: int) -> void:
	if resource_type in _resource_rows:
		# Update existing row
		_resource_rows[resource_type].amount_label.text = str(amount)
		return

	# --- Create new row ---
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	# Color swatch (small colored square representing the resource)
	var swatch_panel := PanelContainer.new()
	swatch_panel.custom_minimum_size = SWATCH_SIZE
	var swatch_style := StyleBoxFlat.new()
	swatch_style.bg_color = RESOURCE_COLORS.get(resource_type, FALLBACK_COLOR)
	_apply_corner_radius(swatch_style, SWATCH_RADIUS)
	swatch_panel.add_theme_stylebox_override("panel", swatch_style)
	row.add_child(swatch_panel)

	# Resource name
	var name_label := _make_label(
		String(resource_type).to_pascal_case(), LABEL_COLOR, 12
	)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# Amount (right-aligned)
	var amount_label := _make_label(str(amount), LABEL_COLOR, 12)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_label.custom_minimum_size.x = 40.0
	row.add_child(amount_label)

	_rows_container.add_child(row)
	_resource_rows[resource_type] = {
		"row": row,
		"amount_label": amount_label,
	}


func _remove_row(resource_type: StringName) -> void:
	if resource_type not in _resource_rows:
		return
	var data: Dictionary = _resource_rows[resource_type]
	data.row.queue_free()
	_resource_rows.erase(resource_type)
	# Kill any pending flash tween for this row
	_kill_flash_tween(resource_type)


func _update_empty_visibility() -> void:
	_empty_label.visible = _resource_rows.is_empty()

# ── Row Flash Animation ─────────────────────────────────────────────────

func _flash_row(resource_type: StringName) -> void:
	if resource_type not in _resource_rows:
		return
	var row: HBoxContainer = _resource_rows[resource_type].row
	_kill_flash_tween(resource_type)
	row.modulate = FLASH_COLOR
	var tw := create_tween()
	tw.tween_property(row, "modulate", Color.WHITE, FLASH_DURATION)
	_flash_tweens[resource_type] = tw


func _kill_flash_tween(resource_type: StringName) -> void:
	if resource_type in _flash_tweens:
		var tw: Tween = _flash_tweens[resource_type]
		if tw and tw.is_valid():
			tw.kill()
		_flash_tweens.erase(resource_type)

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


static func _safe_disconnect(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)
