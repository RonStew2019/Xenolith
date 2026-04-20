extends Node
class_name ReactorCore
## Manages a reactor: structural integrity and heat accumulation.
##
## Attach as a child of any host node that wants to participate in the
## combat pipeline -- characters, resonance pillars, turrets, destructible
## props.  Connects to the global [CombatTickClock] autoload for
## synchronized tick processing.
##
## Each tick, heat increases by the sum of every active effect's weight.
## Heat is allowed to exceed [member max_heat].  Every tick that it stays
## above max, the excess is subtracted from integrity (sustained breach).
## Damage stops once cooling brings heat back below max.
##
## ── Reactor host interface contract ──────────────────────────────────────
##
## ReactorCore itself is parent-type-agnostic: it never touches
## [CharacterBody3D]-specific members (no [code]velocity[/code], no
## [code]movement_lock_count[/code]).  The only parent-dependent code paths
## are [method _fragile_break] ([code]host.queue_free()[/code] -- any Node
## suffices) and [method _spawn_damage_number] (guards [code]is Node3D[/code]
## and silently skips otherwise).
##
## However, the BROADER combat pipeline (AoE scans, projectile hits, melee
## targeting, counter-hit broadcasts, AI target selection) reaches into
## reactor-hosting nodes through a small conventional interface.  To be a
## first-class target / participant, a host node must provide:
##
## [b]Required[/b]
##   • Extends [Node3D] -- for [code]global_position[/code] spatial queries.
##   • [code]get_reactor() -> ReactorCore[/code] -- reactor lookup.  Callers:
##     [Ability._get_reactor], [AoeAbility._deliver_aoe_at],
##     [AoeProjectile._detonate], [Projectile._on_body_entered],
##     [CounterHitEffect.on_remove], [CharacterBase.execute_melee],
##     [StatTransferOnDeathEffect._find_reactor].
##   • [code]_dead: bool[/code] property -- liveness gate.  Scanners read it
##     via [code]node.get("_dead")[/code], so a MISSING property reads as
##     null / falsy and the host appears "alive forever".  Hosts that can
##     die MUST expose this flag and set it true before being freed (or be
##     removed from the [code]"characters"[/code] group first).  Readers:
##     [AoeAbility], [AoeProjectile], [Projectile], [CounterHitEffect],
##     [combat_ai._find_nearest_enemy].
##   • Group membership: [code]"characters"[/code] -- AoE / projectile / AI
##     scans iterate this group.  Non-character hosts (e.g. resonance
##     pillars) should still join it and set an [code]is_pillar = true[/code]
##     marker property so mech-only filters can exclude them (see
##     resonance_pillar.md Q2 Option A).
##
## [b]Optional -- enables extra integrations[/b]
##   • [code]clone_parent: Node[/code] -- read by [StatTransferOnDeathEffect]
##     to walk a family tree on death.  Not needed for pillars.
##   • Custom death handler -- ReactorCore can self-destruct the host on
##     breach via [member break_on_breach_deletes_host] (runs
##     [method shutdown] then [method Node.queue_free]s the parent).  Only
##     override externally if you need a bespoke death transition (see
##     [CharacterBase.die] for the character variant).
##
## [b]Per-effect sub-contracts[/b] -- INDIVIDUAL [StatusEffect] subclasses
## may require richer host interfaces than the minimum above.  Notably
## [KnockbackEffect] requires a [CharacterBody3D] host
## ([code]velocity[/code] + [code]movement_lock_count[/code]).  Such
## contracts are the caller's responsibility to honour -- don't apply an
## effect to a host that can't support it.  ReactorCore does not enforce.

# -- Signals ---------------------------------------------------------------

signal integrity_changed(current: float, maximum: float)
signal heat_changed(current: float, maximum: float)
signal effect_applied(effect: StatusEffect, is_refresh: bool)
signal effect_removed(effect: StatusEffect)
signal reactor_breached
signal heat_overflowed(amount: float)
## Emitted the tick heat crosses from below [member max_heat] to at-or-above.
signal overheat_started
## Emitted the tick heat drops back below [member max_heat].
signal overheat_ended

# -- Configuration ---------------------------------------------------------

@export var max_integrity: float = 1000.0:
	set(value):
		max_integrity = value
		if not is_node_ready():
			return
		# Clamp integrity to new ceiling.
		var clamped := clampf(integrity, 0.0, max_integrity)
		if not is_equal_approx(integrity, clamped):
			integrity = clamped          # Setter emits integrity_changed
		else:
			# Value unchanged but max changed — still notify listeners.
			integrity_changed.emit(integrity, max_integrity)

@export var max_heat: float = 1000.0:
	set(value):
		max_heat = value
		if not is_node_ready():
			return
		# Re-trigger heat setter to re-evaluate overheat and emit signal
		# with the updated max.  (Heat is NOT clamped — overheat is allowed.)
		heat = heat

@export var enable_ambient_venting: bool = true

## If true, the moment integrity hits zero the reactor bypasses the normal
## CharacterBase [code]die()[/code] pipeline and instead tears itself down and
## [method Node.queue_free]s its host node directly.  Used by lightweight
## reactor-hosting entities (e.g. Resonance Pillars) whose host does not
## implement [code]CharacterBase[/code].
##
## [signal reactor_breached] is still emitted first so VFX / stat-transfer /
## UI listeners can react; we only skip the external death handler.
@export var break_on_breach_deletes_host: bool = false

# -- State -----------------------------------------------------------------

var integrity: float = 0.0:
	set(value):
		var clamped := clampf(value, 0.0, max_integrity)
		if is_equal_approx(integrity, clamped):
			return
		integrity = clamped
		integrity_changed.emit(integrity, max_integrity)
		if integrity <= 0.0:
			reactor_breached.emit()
			# Fragile reactors (e.g. Resonance Pillars) do not have a
			# CharacterBase host with a die() handler; free the host directly.
			# reactor_breached is still emitted above so VFX / stat-transfer
			# listeners can react before teardown.
			if break_on_breach_deletes_host and not _is_shutdown:
				_fragile_break()

var heat: float = 0.0:
	set(value):
		var was_overheating := _is_overheating
		heat = maxf(value, 0.0)
		_is_overheating = heat >= max_heat
		heat_changed.emit(heat, max_heat)
		if _is_overheating and not was_overheating:
			overheat_started.emit()
		elif not _is_overheating and was_overheating:
			overheat_ended.emit()

var _effects: Array = []
var _self_repair_effect: SelfRepairEffect = null
var _is_overheating: bool = false
var _is_shutdown: bool = false

## Maps tracked StatusEffects to { label: FloatingNumber, total: float }.
var _damage_numbers: Dictionary = {}

# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	var clock := get_node_or_null("/root/CombatTickClock")
	if clock and clock.has_signal("tick"):
		clock.tick.connect(_on_combat_tick)
	else:
		push_warning("ReactorCore: CombatTickClock autoload not found.")
	integrity = max_integrity
	heat = 0.0
	if enable_ambient_venting:
		apply_effect(StatusEffect.new("Ambient Venting", -3.0, -1, null))
	# Connect self-repair event handling after init so the assignments
	# above don't trigger premature apply/remove logic.
	overheat_started.connect(_on_overheat_started)
	overheat_ended.connect(_on_overheat_ended)
	integrity_changed.connect(_on_integrity_changed_for_self_repair)

# -- Public API ------------------------------------------------------------

func apply_effect(effect: StatusEffect) -> void:
	var existing_instance = get_effect_by_name(effect.effect_name)
	if existing_instance && effect.is_refreshable:
		existing_instance.set_duration(effect.get_duration())
		effect_applied.emit(effect, true)
		return
	if existing_instance && !effect.is_stackable:
		return
	_effects.append(effect)
	effect.target = get_parent()
	effect.on_apply(self)
	effect_applied.emit(effect, false)
	_spawn_damage_number(effect)


func remove_effect(effect: StatusEffect) -> void:
	var idx := _effects.find(effect)
	if idx == -1:
		return
	_effects.remove_at(idx)
	effect.on_remove(self)
	effect_removed.emit(effect)
	_retire_damage_number(effect)
	if effect == _self_repair_effect:
		_self_repair_effect = null


func remove_effects_by_name(target_name: String) -> void:
	var to_remove := []
	for effect in _effects:
		if effect.effect_name == target_name:
			to_remove.append(effect)
	for effect in to_remove:
		remove_effect(effect)


func remove_effects_by_source(source_node: Node) -> void:
	var to_remove := []
	for effect in _effects:
		if effect.source == source_node:
			to_remove.append(effect)
	for effect in to_remove:
		remove_effect(effect)


func clear_effects() -> void:
	var snapshot := _effects.duplicate()
	for effect in snapshot:
		remove_effect(effect)
	_self_repair_effect = null


## Full teardown for a destroyed mech.  Cleans up every effect (calling
## [method StatusEffect.on_remove] on each), retires lingering damage
## numbers, disconnects from [CombatTickClock], and zeroes heat.
## Safe to call multiple times — subsequent calls are no-ops.
func shutdown() -> void:
	if _is_shutdown:
		return
	_is_shutdown = true

	# 1. Remove every active effect (triggers on_remove + damage-number retire).
	clear_effects()

	# 2. Safety net: retire any damage numbers not covered by clear_effects().
	for effect in _damage_numbers:
		var entry: Dictionary = _damage_numbers[effect]
		var label: Node = entry.label
		if is_instance_valid(label) and label.has_method("start_expire_sequence"):
			label.start_expire_sequence()
	_damage_numbers.clear()

	# 3. Disconnect from the tick clock so the dead reactor stops processing.
	var clock := get_node_or_null("/root/CombatTickClock")
	if clock and clock.has_signal("tick") and clock.tick.is_connected(_on_combat_tick):
		clock.tick.disconnect(_on_combat_tick)

	# 4. Zero heat to prevent lingering overheat signals.
	heat = 0.0


## Fragile-reactor teardown.  Called from the [member integrity] setter when
## [member break_on_breach_deletes_host] is true and integrity hits zero.
## Runs the full [method shutdown] sequence (fires [code]on_remove[/code] for
## every active effect, retires damage numbers, disconnects from the tick
## clock, zeros heat), then [method Node.queue_free]s the host node.
##
## Safe to invoke mid-tick: [method shutdown] is idempotent, and
## [method Node.queue_free] defers actual destruction to end-of-frame so the
## currently-executing tick handler completes cleanly.
func _fragile_break() -> void:
	shutdown()
	var host := get_parent()
	if is_instance_valid(host) and not host.is_queued_for_deletion():
		# Mark the host dead so same-tick AoE / projectile / AI scans skip
		# it during the end-of-frame grace period before queue_free takes
		# effect.  set() silently no-ops if the host lacks a _dead property.
		host.set("_dead", true)
		host.queue_free()


func get_heat_pressure() -> float:
	var total := 0.0
	for effect in _effects:
		total += effect.heat
	return total


func get_effects() -> Array:
	return _effects.duplicate()

func get_effect_by_name(EffectName: String) -> StatusEffect:
	for effect in _effects:
		if effect.effect_name == EffectName:
			return effect
	return null

func get_effect_count() -> int:
	return _effects.size()

# -- Tick Processing -------------------------------------------------------

func _on_combat_tick() -> void:
	# Snapshot so signal-driven effect adds/removes during on_tick are safe.
	var snapshot := _effects.duplicate()
	var heat_delta := 0.0
	for effect in snapshot:
		effect.on_tick(self)
		heat_delta += effect.heat

	if not is_zero_approx(heat_delta):
		heat += heat_delta

	_update_damage_numbers()

	# Sustained breach: every tick above max, the excess damages integrity.
	if heat > max_heat:
		var overflow := heat - max_heat
		heat_overflowed.emit(overflow)
		integrity -= overflow

	var expired := []
	for effect in _effects:
		if effect.duration > 0:
			effect.duration -= 1
		if effect.is_expired():
			expired.append(effect)

	for effect in expired:
		remove_effect(effect)

# -- Damage Numbers --------------------------------------------------------

## Spawn a living [FloatingNumber] for hostile effects applied by another
## character.  The number tracks cumulative heat and only begins its fade
## sequence when the effect is removed.
func _spawn_damage_number(effect: StatusEffect) -> void:
	if effect.heat <= 0.0:
		return
	if effect.source == null or effect.source == get_parent():
		return
	var target := get_parent()
	if not target is Node3D:
		return
	var label := FloatingNumber.new()
	label.text = "+%d" % ceili(effect.heat)
	target.add_child(label)
	label.position = Vector3.UP * 2.2 + Vector3(
		randf_range(-0.25, 0.25),
		randf_range(-0.1, 0.1),
		randf_range(-0.25, 0.25),
	)
	_damage_numbers[effect] = { "label": label, "total": 0.0 }


## Accumulate each tracked effect's weight and update its label.
func _update_damage_numbers() -> void:
	for effect in _damage_numbers:
		var entry: Dictionary = _damage_numbers[effect]
		entry.total += effect.heat
		var label: Node = entry.label
		if is_instance_valid(label):
			label.text = "+%d" % ceili(entry.total)


## Kick off the fade sequence and stop tracking.
func _retire_damage_number(effect: StatusEffect) -> void:
	if not _damage_numbers.has(effect):
		return
	var entry: Dictionary = _damage_numbers[effect]
	var label: Node = entry.label
	if is_instance_valid(label) and label.has_method("start_expire_sequence"):
		label.start_expire_sequence()
	_damage_numbers.erase(effect)

# -- Self-Repair Management (event-driven) ---------------------------------

func _on_overheat_started() -> void:
	if _self_repair_effect != null:
		remove_effect(_self_repair_effect)


func _on_overheat_ended() -> void:
	if _self_repair_effect == null and integrity < max_integrity:
		_self_repair_effect = SelfRepairEffect.new()
		apply_effect(_self_repair_effect)


func _on_integrity_changed_for_self_repair(current: float, maximum: float) -> void:
	if current >= maximum and _self_repair_effect != null:
		remove_effect(_self_repair_effect)
	elif current < maximum and _self_repair_effect == null and not _is_overheating:
		_self_repair_effect = SelfRepairEffect.new()
		apply_effect(_self_repair_effect)
