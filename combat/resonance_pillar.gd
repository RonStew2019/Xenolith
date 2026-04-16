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

# TODO — Phase 3.1 ("Pillar subscription wiring"): cached references to
# the caster's Slot 1 / Slot 2 / Slot 3 abilities will live here once
# signal subscriptions are wired. Expected fields:
#   var _slot1_ability: Ability = null   # Resonance — activated/deactivated
#   var _slot2_ability: Ability = null   # — activated
#   var _slot3_ability: Ability = null   # — activated
#   var _slot1_active: bool = false      # mirror of slot1.is_active(),
#                                        # driven by the activated/deactivated
#                                        # signals so the melee-strike handler
#                                        # can gate without polling.


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

	# -- Caster ability subscriptions --------------------------------------
	# TODO — Phase 3.1 ("Pillar subscription wiring"): after the reactor
	# is up and the pillar is in the tree, look up the caster's loadout
	# slots and connect:
	#   _slot1_ability = caster._loadout.get_ability_for_action("ability_1")
	#   _slot2_ability = caster._loadout.get_ability_for_action("ability_2")
	#   _slot3_ability = caster._loadout.get_ability_for_action("ability_3")
	#   _slot1_ability.activated.connect(_on_slot1_activated)
	#   _slot1_ability.deactivated.connect(_on_slot1_deactivated)
	#   _slot2_ability.activated.connect(_on_slot2_activated)
	#   _slot3_ability.activated.connect(_on_slot3_activated)
	#   caster.melee_strike.connect(_on_caster_melee_strike)
	# Seed _slot1_active from _slot1_ability.is_active() at subscription
	# time so the "Slot 1 toggle was already on when the pillar spawned"
	# case works. Every handler MUST begin with
	#   if not is_instance_valid(caster): return
	# (see class doc-comment).


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

	# TODO — Phase 3.1 ("Pillar subscription teardown"): disconnect the
	# four connections established in _ready, each guarded by
	# is_connected so repeat teardowns stay safe:
	#   if _slot1_ability and _slot1_ability.activated.is_connected(_on_slot1_activated):
	#       _slot1_ability.activated.disconnect(_on_slot1_activated)
	#   if _slot1_ability and _slot1_ability.deactivated.is_connected(_on_slot1_deactivated):
	#       _slot1_ability.deactivated.disconnect(_on_slot1_deactivated)
	#   if _slot2_ability and _slot2_ability.activated.is_connected(_on_slot2_activated):
	#       _slot2_ability.activated.disconnect(_on_slot2_activated)
	#   if _slot3_ability and _slot3_ability.activated.is_connected(_on_slot3_activated):
	#       _slot3_ability.activated.disconnect(_on_slot3_activated)
	#   if caster.melee_strike.is_connected(_on_caster_melee_strike):
	#       caster.melee_strike.disconnect(_on_caster_melee_strike)
	# Phase 3.1 owns the signal wiring; nothing to disconnect yet.
	pass
