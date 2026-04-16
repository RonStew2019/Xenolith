class_name ResonancePillar
extends StaticBody3D

## The resonance pillar entity — a stationary anchor spawned by
## [code]ResonancePillarAbility[/code] when its projectile impacts terrain.
##
## A pillar is a real reactor-hosting entity (NOT a character): it joins
## the [code]"characters"[/code] group so AoE, projectile, melee, and AI
## scans pick it up uniformly with mechs, and carries an
## [member is_pillar] marker so those scanners can still exclude it from
## mech-only code paths (see resonance_pillar.md Q2 Option A).
##
## Its hosted [ReactorCore] is deliberately fragile (low [code]max_integrity[/code])
## and self-deletes the pillar on breach via
## [member ReactorCore.break_on_breach_deletes_host], so this host does
## not need a bespoke [code]die()[/code] handler — a single tick of
## sustained overheat is enough to free it.
##
## [b]Forward reference — Phase 3.1+:[/b] subsequent phases will connect
## this pillar to its [member caster]'s Slot 1 / Slot 2 / Slot 3 abilities
## and to its [signal CharacterBase.melee_strike] signal so the pillar can
## replicate caster activations at its own position. [b]Every signal
## handler added in Phase 3.1+ MUST begin with[/b]
## [code]if not is_instance_valid(caster): return[/code] to guard against
## the caster being freed before pillar teardown completes.

## The character that spawned this pillar. Attribution anchor for any
## effects the pillar applies on its caster's behalf. Populated by
## [code]PersistentProjectile._spawn_pillar_at[/code] BEFORE the pillar
## is added to the scene tree, so [method _ready] can rely on this being
## non-null.
var caster: Node = null

## The pillar's own [ReactorCore], instantiated as a child in [method _ready].
## Exposed via [method get_reactor] for the duck-typed reactor lookups
## scattered through the combat pipeline ([code]AoeAbility[/code],
## [code]Projectile[/code], [code]AoeProjectile[/code],
## [code]CounterHitEffect[/code], etc.).
var _reactor: ReactorCore = null

## Liveness gate required by the reactor-host contract (see
## [code]reactor_core.gd[/code] lines ~36-41). AoE / projectile / AI
## scanners read this via [code]node.get("_dead")[/code] to skip dead
## targets — a missing property reads as null/falsy, so hosts that can
## die MUST expose this. Pillars stay [code]false[/code] until their
## reactor is breached, at which point
## [member ReactorCore.break_on_breach_deletes_host] frees the host
## directly (no transitional dying state needed).
var _dead: bool = false

## Marker that lets character-only filters (mech AI selection, loadout
## UI, melee target preference, etc.) exclude pillars from
## [code]"characters"[/code] group scans. Characters never set this, so
## an absent / false read on a group member means "this is a real mech"
## (Q2 Option A in resonance_pillar.md).
var is_pillar: bool = true

## Cached reference to the caster's Slot 1 ability ("ability_1"),
## subscribed in [method _ready] so the pillar can mirror its active
## state. Left null when the caster has no Slot 1 binding at spawn
## time — subscription is then skipped gracefully and the pillar still
## functions as an inert reactor-host.
var _slot1_ability: Ability = null

## Mirror of [code]_slot1_ability.is_active()[/code], driven by the
## [signal Ability.activated] / [signal Ability.deactivated] signals
## so [method _on_caster_melee_strike] (Phase 3.2 body) can gate
## without polling the ability each hit. Seeded from
## [method Ability.is_active] at subscription time so a pillar spawned
## while the Slot 1 toggle is already ON starts out with this true.
var _slot1_active: bool = false

# TODO — Phase 4.1 / 5.1: cached references to the caster's Slot 2 and
# Slot 3 abilities will live here when their subscriptions are wired.
# Expected fields:
#   var _slot2_ability: Ability = null   # — activated
#   var _slot3_ability: Ability = null   # — activated


func _ready() -> void:
	# -- Group membership (Q2 Option A) -----------------------------------
	# Pillars join "characters" so AoE / projectile / melee / AI scans pick
	# them up uniformly with mechs. The [member is_pillar] marker is the
	# discriminator for any code path that needs character-only behaviour
	# (e.g. AI target preference, loadout UI) — those readers do
	# `if body.get("is_pillar"): continue` to filter pillars back out.
	add_to_group("characters")

	# -- ReactorCore child -------------------------------------------------
	# Configure the reactor's @export properties BEFORE add_child so its
	# own _ready() observes the final values when it seeds
	#   integrity = max_integrity
	# and connects to the CombatTickClock. Fragile by design: max_integrity
	# of 1.0 means a single tick of sustained overheat (heat >= max_heat)
	# breaches the reactor, and break_on_breach_deletes_host = true makes
	# the breach free this host directly (no CharacterBase.die required).
	var reactor := ReactorCore.new()
	reactor.name = "ReactorCore"
	reactor.max_heat = 100.0
	reactor.max_integrity = 1.0
	reactor.break_on_breach_deletes_host = true
	add_child(reactor)
	_reactor = reactor

	# -- Collision shape ---------------------------------------------------
	# Capsule, 0.5 m radius × 2.5 m total height. Local-positioned with a
	# +height/2 Y offset so the pillar's FOOT sits at global_position (the
	# impact point set by PersistentProjectile AFTER add_child returns),
	# rather than its centre being there. Safe to use local offsets here
	# because global_position is not yet set at _ready time.
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 2.5
	var col := CollisionShape3D.new()
	col.shape = capsule
	col.position.y = capsule.height * 0.5
	add_child(col)

	# -- Visual mesh (emissive resonance-violet column) --------------------
	# Cylinder matching the capsule's footprint and height. Albedo /
	# emission colours mirror PersistentProjectile so visually the
	# projectile "becomes" the pillar on impact. Same +height/2 Y offset
	# so the column stands ON the impact point.
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 2.5
	mesh_inst.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.3, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.75, 0.35, 1.0)
	mat.emission_energy_multiplier = 4.0
	mesh_inst.material_override = mat
	mesh_inst.position.y = cyl.height * 0.5
	add_child(mesh_inst)

	# -- Caster ability subscriptions (Phase 3.1) -------------------------
	# Mirror the caster's Slot 1 toggle state and listen for their melee
	# strikes so Phase 3.2 can echo the resonance payload from the pillar's
	# own position. Each hop is guarded so a caster without a _loadout, a
	# missing Slot 1 binding, or a missing melee_strike signal produces a
	# push_warning and a graceful skip — the pillar still functions as an
	# inert reactor-host in those degenerate cases.
	if not is_instance_valid(caster):
		push_warning("ResonancePillar: caster is null at _ready; skipping ability subscriptions.")
		return
	var loadout = caster.get("_loadout")
	if loadout == null:
		push_warning("ResonancePillar: caster has no _loadout; skipping Slot 1 subscription.")
	else:
		_slot1_ability = loadout.get_ability_for_action("ability_1")
		if _slot1_ability == null:
			push_warning("ResonancePillar: caster has no ability bound to \"ability_1\"; skipping Slot 1 subscription.")
		else:
			# Seed from the ability's live state BEFORE connecting so the
			# "toggle was already ON when the pillar spawned" case works
			# — there will be no activated signal for the already-active
			# state, so we have to read it directly.
			_slot1_active = _slot1_ability.is_active()
			_slot1_ability.activated.connect(_on_slot1_activated)
			_slot1_ability.deactivated.connect(_on_slot1_deactivated)
	if caster.has_signal("melee_strike"):
		caster.melee_strike.connect(_on_caster_melee_strike)
	else:
		push_warning("ResonancePillar: caster has no melee_strike signal; skipping strike subscription.")


## Duck-typed reactor accessor. Mirrors the contract that
## [CharacterBase] exposes, so reactor-lookup code (e.g.
## [code]AoeAbility._deliver_aoe_at[/code],
## [code]Projectile._on_body_entered[/code],
## [code]AoeProjectile._detonate[/code],
## [code]CounterHitEffect.on_remove[/code]) can resolve a pillar's
## reactor the same way it resolves a character's. Returns the
## [ReactorCore] instantiated in [method _ready]; only [code]null[/code]
## if called before the pillar has entered the tree.
func get_reactor() -> Node:
	return _reactor


## Clean up caster signal subscriptions on pillar destruction.
##
## Runs on every pillar teardown — normal reactor-breach deletion (via
## [member ReactorCore.break_on_breach_deletes_host]),
## [code]ResonancePillarAbility.force_deactivate[/code]-driven cleanup
## on caster death / loadout swap, scene change, etc. Safe to call
## multiple times and safe if [member caster] has already been freed:
## the early-out below handles the freed-caster case, and every
## disconnect added in Phase 3.1+ will be additionally guarded by
## [code]is_connected[/code] so a double-teardown is also a no-op.
func _exit_tree() -> void:
	# Defensive guard: if the caster was freed before us, its signals are
	# gone with it — there is nothing to disconnect, and touching the
	# stale reference would crash. Bail out cleanly.
	if not is_instance_valid(caster):
		return

	# Disconnect the three Slot 1 / melee-strike subscriptions established
	# in _ready. Each hop is guarded by is_connected so a double teardown
	# (e.g. _exit_tree firing after force_deactivate-driven cleanup) stays
	# a safe no-op. The _slot1_ability truthy check also handles the
	# "caster had no Slot 1 binding at spawn" case — subscription was
	# skipped in _ready, so there is nothing to disconnect here either.
	if _slot1_ability and _slot1_ability.activated.is_connected(_on_slot1_activated):
		_slot1_ability.activated.disconnect(_on_slot1_activated)
	if _slot1_ability and _slot1_ability.deactivated.is_connected(_on_slot1_deactivated):
		_slot1_ability.deactivated.disconnect(_on_slot1_deactivated)
	if caster.has_signal("melee_strike") and caster.melee_strike.is_connected(_on_caster_melee_strike):
		caster.melee_strike.disconnect(_on_caster_melee_strike)
	# NOTE — Phase 4.1 / 5.1: when Slot 2 and Slot 3 subscriptions land,
	# add matching is_connected-guarded disconnects here for their
	# activated signals (deactivated is not needed for those slots — see
	# their phase notes in resonance_pillar.md).


## Handler: caster's Slot 1 ability just transitioned to active.
## Flips the local [member _slot1_active] mirror so the Phase 3.2 body of
## [method _on_caster_melee_strike] can cheaply gate on the toggle
## without polling [method Ability.is_active] on every strike.
func _on_slot1_activated(_user: Node) -> void:
	if not is_instance_valid(caster):
		return
	_slot1_active = true


## Handler: caster's Slot 1 ability just transitioned to inactive.
## Flips [member _slot1_active] off so subsequent melee strikes stop
## echoing resonance from this pillar's position.
func _on_slot1_deactivated(_user: Node) -> void:
	if not is_instance_valid(caster):
		return
	_slot1_active = false


## Handler: the caster's [signal CharacterBase.melee_strike] fired.
## Phase 3.1 stub — signal wiring is live and the liveness + Slot 1 gate
## is in place, but the actual resonance echo (AoE delivery from the
## pillar's position and the 20.0-heat replication cost on the pillar's
## own reactor, gated on landed-vs-whiff) is Phase 3.2 territory. For
## now this function is intentionally a no-op past the gates.
func _on_caster_melee_strike(event: MeleeEvent) -> void:
	if not is_instance_valid(caster):
		return
	if not _slot1_active:
		return
	# TODO — Phase 3.2: deliver AoE at pillar.global_position, pay 20.0 heat cost, gate on landed hit
