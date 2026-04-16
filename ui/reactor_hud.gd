extends Control
class_name ReactorHUD
## Heads-up display for a ReactorCore.
##
## Builds the entire UI tree programmatically -- no .tscn needed.
## Call bind_reactor() to wire it to a reactor instance.
## Includes color-ramped heat gauge (blue -> yellow -> red),
## integrity bar (green -> red), pressure readout, and breach flash.

# ── Palette ──────────────────────────────────────────────────────────────

const HEAT_COOL = Color(0.2, 0.5, 1.0)
const HEAT_WARM = Color(1.0, 0.85, 0.0)
const HEAT_HOT = Color(1.0, 0.4, 0.0)
const HEAT_CRIT = Color(1.0, 0.1, 0.1)

const INTEGRITY_FULL = Color(0.1, 0.9, 0.4)
const INTEGRITY_LOW = Color(0.9, 0.15, 0.15)

const PANEL_BG = Color(0.05, 0.05, 0.08, 0.85)
const LABEL_COLOR = Color(0.8, 0.85, 0.9)
const HEADER_COLOR = Color(0.5, 0.7, 1.0)
const BAR_BG = Color(0.12, 0.12, 0.18)

# ── Internal refs ────────────────────────────────────────────────────────

var _reactor: Node = null

var _integrity_bar: ProgressBar
var _integrity_label: Label
var _integrity_fill: StyleBoxFlat

var _heat_bar: ProgressBar
var _heat_label: Label
var _heat_fill: StyleBoxFlat

var _pressure_label: Label
var _effects_label: Label
var _flash_tween: Tween


func _ready() -> void:
	_build_ui()

# ── Binding ──────────────────────────────────────────────────────────────

func bind_reactor(reactor: Node) -> void:
	if _reactor:
		_unbind()
	_reactor = reactor
	_reactor.integrity_changed.connect(_on_integrity_changed)
	_reactor.heat_changed.connect(_on_heat_changed)
	_reactor.effect_applied.connect(_on_effect_applied)
	_reactor.effect_removed.connect(_on_effect_removed)
	_reactor.heat_overflowed.connect(_on_heat_overflowed)
	_refresh()


func _unbind() -> void:
	if not _reactor:
		return
	_safe_disconnect(_reactor.integrity_changed, _on_integrity_changed)
	_safe_disconnect(_reactor.heat_changed, _on_heat_changed)
	_safe_disconnect(_reactor.effect_applied, _on_effect_applied)
	_safe_disconnect(_reactor.effect_removed, _on_effect_removed)
	_safe_disconnect(_reactor.heat_overflowed, _on_heat_overflowed)
	_reactor = null

# ── UI Construction ──────────────────────────────────────────────────────

func _build_ui() -> void:
	# Anchor bottom-left
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 16.0
	offset_bottom = -16.0
	offset_top = offset_bottom - 148.0
	offset_right = offset_left + 296.0

	# Dark panel
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Header
	var header := _make_label("REACTOR", HEADER_COLOR, 14)
	vbox.add_child(header)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	vbox.add_child(sep)

	# Integrity row
	var int_row := _build_bar_row("INTEGRITY", INTEGRITY_FULL)
	vbox.add_child(int_row.container)
	_integrity_bar = int_row.bar
	_integrity_label = int_row.value_label
	_integrity_fill = int_row.fill_style

	# Heat row
	var heat_row := _build_bar_row("HEAT", HEAT_COOL)
	vbox.add_child(heat_row.container)
	_heat_bar = heat_row.bar
	_heat_label = heat_row.value_label
	_heat_fill = heat_row.fill_style

	# Info footer
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 8)
	vbox.add_child(info)

	_pressure_label = _make_label("+0.0/tick", LABEL_COLOR, 11)
	info.add_child(_pressure_label)

	_effects_label = _make_label("0 effects", LABEL_COLOR.darkened(0.3), 11)
	_effects_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effects_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info.add_child(_effects_label)


func _build_bar_row(title: String, fill_color: Color) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl := _make_label(title, LABEL_COLOR, 12)
	lbl.custom_minimum_size.x = 76.0
	row.add_child(lbl)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(120, 18)
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
	val_lbl.custom_minimum_size.x = 60.0
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)

	return {
		"container": row,
		"bar": bar,
		"value_label": val_lbl,
		"fill_style": fill,
	}

# ── Signal Handlers ──────────────────────────────────────────────────────

func _on_integrity_changed(current: float, maximum: float) -> void:
	_integrity_bar.max_value = maximum
	_integrity_bar.value = current
	_integrity_label.text = "%d / %d" % [ceili(current), ceili(maximum)]
	var ratio := current / maxf(maximum, 0.001)
	_integrity_fill.bg_color = INTEGRITY_LOW.lerp(INTEGRITY_FULL, ratio)


func _on_heat_changed(current: float, maximum: float) -> void:
	_heat_bar.max_value = maximum
	_heat_bar.value = clampf(current, 0.0, maximum)
	_heat_label.text = "%d / %d" % [ceili(current), ceili(maximum)]
	var ratio := clampf(current / maxf(maximum, 0.001), 0.0, 1.0)
	_heat_fill.bg_color = _heat_color_ramp(ratio)
	_update_pressure()


func _on_effect_applied(_effect: Variant, _is_refresh: bool) -> void:
	_update_effects_count()


func _on_effect_removed(_effect: Variant) -> void:
	_update_effects_count()


func _on_heat_overflowed(_amount: float) -> void:
	_flash(Color(1.0, 0.2, 0.1, 0.4))

# ── Helpers ──────────────────────────────────────────────────────────────

func _update_pressure() -> void:
	if not _reactor:
		return
	var p: float = _reactor.get_heat_pressure()
	var sign_char := "+" if p >= 0.0 else ""
	_pressure_label.text = "%s%.1f/tick" % [sign_char, p]


func _update_effects_count() -> void:
	if not _reactor:
		return
	var n: int = _reactor.get_effect_count()
	_effects_label.text = "%d effect%s" % [n, "" if n == 1 else "s"]


func _heat_color_ramp(ratio: float) -> Color:
	if ratio < 0.33:
		return HEAT_COOL.lerp(HEAT_WARM, ratio / 0.33)
	if ratio < 0.66:
		return HEAT_WARM.lerp(HEAT_HOT, (ratio - 0.33) / 0.33)
	return HEAT_HOT.lerp(HEAT_CRIT, (ratio - 0.66) / 0.34)


func _flash(color: Color) -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	modulate = Color.WHITE + color
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", Color.WHITE, 0.35)


func _refresh() -> void:
	if not _reactor or not is_instance_valid(_reactor):
		return
	_on_integrity_changed(_reactor.integrity, _reactor.max_integrity)
	_on_heat_changed(_reactor.heat, _reactor.max_heat)
	_update_effects_count()

# ── Style Factories ──────────────────────────────────────────────────────

func _make_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	_apply_corner_radius(s, 6)
	s.content_margin_left = 12.0
	s.content_margin_right = 12.0
	s.content_margin_top = 8.0
	s.content_margin_bottom = 8.0
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = Color(0.25, 0.3, 0.45, 0.6)
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


static func _safe_disconnect(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)
