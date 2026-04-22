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
## [b]Signal subscriptions:[/b] the pillar subscribes to its
## [member caster]'s Slot 1, Slot 2, and Slot 3 abilities and to its
## [signal CharacterBase.melee_strike] signal so the pillar replicates
## caster activations at its own position.
## [b]Every signal handler MUST begin with[/b]
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

## Reference to the pillar's visual mesh (emissive violet cylinder), stored
## so [method _flash_replication] can animate the emission intensity and the
## spawn tween can target it.
var _mesh_inst: MeshInstance3D = null

## Tween driving the spawn growth animation (scale.y 0→1 over 0.3 s).
## Stored so breach-during-spawn can kill it cleanly without leaving the
## pillar at a fractional scale.
var _spawn_tween: Tween = null

## Tween driving the current replication flash (emission energy pulse).
## Stored so rapid activations can kill the previous flash before starting
## a new one, preventing tween conflicts.
var _flash_tween: Tween = null

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

## Cached reference to the caster's Slot 2 ability ("ability_2"),
## subscribed in [method _ready] so the pillar can echo its activation
## pulse from its own position. Unlike Slot 1, there is no
## [code]_slot2_active[/code] mirror: Slot 2 (Repulse) is an activation
## pulse, not a sustained gate, so the subscription is to
## [signal Ability.activated] only and the whole replication decision
## lives inside [method _on_slot2_activated]. Left null when the caster
## has no Slot 2 binding at spawn time — subscription is then skipped
## gracefully and the pillar still functions as an inert reactor-host.
var _slot2_ability: Ability = null

## Cached reference to the caster's Slot 3 ability ("ability_3"),
## subscribed in [method _ready] so the pillar can echo its activation
## by self-applying the same [CounterHitEffect] to its own reactor.
## Like Slot 2, Counter-Hit is INSTANT so only the [signal Ability.activated]
## signal is connected — no deactivated mirror or active-state tracking
## needed. Left null when the caster has no Slot 3 binding at spawn time.
var _slot3_ability: Ability = null


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
	_mesh_inst = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 2.5
	_mesh_inst.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.3, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.75, 0.35, 1.0)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_mesh_inst.material_override = mat
	_mesh_inst.position.y = cyl.height * 0.5
	add_child(_mesh_inst)

	# -- Spawn growth animation (Phase 7.1 item 2) ------------------------
	# Animate the pillar rising from the ground by tweening scale.y from
	# near-zero to 1.0 over 0.3 s. We scale the entire pillar node (mesh +
	# collision) — 0.3 s is short enough that the brief collision under-size
	# has no gameplay impact, and scaling only the mesh would leave a
	# collision-visible-mismatch that looks worse than a brief size ramp.
	scale.y = 0.01  # near-zero avoids division-by-zero in physics
	_spawn_tween = create_tween()
	_spawn_tween.tween_property(self, "scale:y", .65, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# -- Breach-delete flash subscription (Phase 7.1 item 3) --------------
	# reactor_breached fires BEFORE _fragile_break queue_frees the host,
	# so the handler has time to spawn a sibling flash node.
	_reactor.reactor_breached.connect(_on_reactor_breached)

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
		# -- Slot 2 (Repulse) subscription (Phase 4.1) ---------------------
		# Repulse is INSTANT, so only the activated signal fires — no
		# deactivated connection or _slot2_active mirror needed.
		_slot2_ability = loadout.get_ability_for_action("ability_2")
		if _slot2_ability == null:
			push_warning("ResonancePillar: caster has no ability bound to \"ability_2\"; skipping Slot 2 subscription.")
		else:
			_slot2_ability.activated.connect(_on_slot2_activated)
		# -- Slot 3 (Counter-Hit) subscription (Phase 5.1) -----------------
		# Counter-Hit is INSTANT, so only the activated signal fires — no
		# deactivated connection or _slot3_active mirror needed. On
		# activation, the handler self-applies CounterHitEffect to the
		# pillar's own reactor. No separate cost: the effect itself
		# contributes 10 heat/tick × 10 ticks = 100 total heat, which at
		# pillar max_heat = 100 will breach the pillar at or near expiry.
		# This is by design (Q4) — pillars spend themselves on Counter-Hit.
		_slot3_ability = loadout.get_ability_for_action("ability_3")
		if _slot3_ability == null:
			push_warning("ResonancePillar: caster has no ability bound to \"ability_3\"; skipping Slot 3 subscription.")
		else:
			_slot3_ability.activated.connect(_on_slot3_activated)
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

	# Disconnect the Slot 1 / Slot 2 / melee-strike subscriptions established
	# in _ready. Each hop is guarded by is_connected so a double teardown
	# (e.g. _exit_tree firing after force_deactivate-driven cleanup) stays
	# a safe no-op. The _slotN_ability truthy checks also handle the
	# "caster had no binding at spawn" case — subscription was skipped in
	# _ready, so there is nothing to disconnect here either.
	if _slot1_ability and _slot1_ability.activated.is_connected(_on_slot1_activated):
		_slot1_ability.activated.disconnect(_on_slot1_activated)
	if _slot1_ability and _slot1_ability.deactivated.is_connected(_on_slot1_deactivated):
		_slot1_ability.deactivated.disconnect(_on_slot1_deactivated)
	if caster.has_signal("melee_strike") and caster.melee_strike.is_connected(_on_caster_melee_strike):
		caster.melee_strike.disconnect(_on_caster_melee_strike)
	if _slot2_ability and _slot2_ability.activated.is_connected(_on_slot2_activated):
		_slot2_ability.activated.disconnect(_on_slot2_activated)
	if _slot3_ability and _slot3_ability.activated.is_connected(_on_slot3_activated):
		_slot3_ability.activated.disconnect(_on_slot3_activated)


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


## Handler: the caster's Slot 2 (Repulse) ability just activated —
## replicate the knockback burst from this pillar's position.
##
## [b]Reaction, not modification.[/b] The caster's own Repulse fires
## normally from their position via [KnockbackAbility] → [AoeAbility]
## — this handler adds an ADDITIONAL burst centred on the pillar.
## The two are purely additive: a target within range of both the caster
## and a pillar will eat two [KnockbackEffect]s (one from each origin).
##
## [b]Source = self (the pillar).[/b] [code]KnockbackEffect.new(self)[/code]
## means the push direction is computed as "away from the pillar's
## [code]global_position[/code]" and kill attribution flows to the pillar,
## not the caster.  This is per Q6 in resonance_pillar.md — the pillar
## is the emitter, so it owns direction and credit.
##
## [b]Pillar skip.[/b] The [code]is_pillar[/code] check prevents deployed
## pillars from knockback-chaining each other.  Without this, two pillars
## in range would each apply [KnockbackEffect] to the other, and if
## either pillar's knockback somehow triggered further activations, an
## infinite cascade could follow.
##
## [b]Cost semantics.[/b] 18.0-heat replication cost (1-tick, stackable,
## non-refreshable) is applied to the pillar's OWN reactor — same
## magnitude as [code]KnockbackAbility.create_self_effects[/code].
## Source = self so the cost is attributed to the pillar.  Fires
## unconditionally even if the AoE scan finds zero valid targets: the
## pillar still "pulsed" and still pays (same convention as the Slot 1
## handler).
##
## [b]Order of operations.[/b] AoE delivery happens BEFORE cost
## application, so if the cost pushes the pillar's reactor over
## [member ReactorCore.max_heat] (triggering the instant-deletion
## path), the knockback has already been dispatched to targets.
func _on_slot2_activated(_user: Node) -> void:
	if not is_instance_valid(caster):
		return
	_flash_replication()

	# -- AoE knockback delivery at the pillar's position ------------------
	# Radius = 5.5 (matching KnockbackAbility.aoe_radius). Origin = this
	# pillar's global position. Effects attributed to self (the pillar) so
	# push direction is away-from-pillar and kill credit stays with it.
	var aoe_radius := 5.5
	var origin := global_position
	var tree := get_tree()
	if tree:
		for node in tree.get_nodes_in_group("characters"):
			if node == caster:
				continue
			var body := node as Node3D
			if not body:
				continue
			if body.get("_dead"):
				continue
			# Pillar→pillar cascade guard — prevents knockback chaining
			# between deployed pillars.
			if body.get("is_pillar"):
				continue

			# Horizontal range check (Y-ignored, matches AoeAbility).
			var offset := body.global_position - origin
			offset.y = 0.0
			var dist := offset.length()
			if dist > aoe_radius or dist < 0.01:
				continue

			# Fetch target's reactor via the duck-typed accessor.
			var reactor: Node = body.get_reactor() if body.has_method("get_reactor") else null
			if not reactor:
				continue

			# Fresh KnockbackEffect per target — source = self (the
			# pillar) so push direction is away-from-pillar and kill
			# attribution goes to the pillar (Q6).
			reactor.apply_effect(KnockbackEffect.new(self))

	# -- Pay the replication cost ------------------------------------------
	# 18.0 heat, 1-tick, applied to THIS pillar's reactor. Matches
	# KnockbackAbility.create_self_effects cost magnitude. Source = self
	# so the cost is attributed to the pillar. Fired unconditionally.
	_reactor.apply_effect(StatusEffect.new("Repulse Cost", 18.0, 1, self, true, false))


## Handler: the caster's Slot 3 (Counter-Hit) ability just activated —
## apply [CounterHitEffect] to the pillar's own reactor.
##
## [b]Reaction, not modification.[/b] The caster's own Counter-Hit fires
## normally, self-applying [CounterHitEffect] to the caster's reactor via
## [CounterHitAbility.create_self_effects]. This handler adds an ADDITIONAL
## [CounterHitEffect] on the pillar's reactor, so the pillar independently
## records effects applied to it for 10 ticks and broadcasts copies to
## characters within 10m of the pillar on expiry.
##
## [b]Source = caster.[/b] [code]CounterHitEffect.new(caster)[/code] means
## kill attribution on the broadcast copies flows to the caster. The
## broadcast origin is [code]reactor.get_parent()[/code] (the pillar), so
## the 10m AoE is correctly centred on the pillar's position.
##
## [b]No separate cost (Q4).[/b] [CounterHitEffect] itself contributes
## [code]10.0 heat/tick × 10 ticks = 100 total heat[/code]. At pillar
## [code]max_heat = 100[/code] (Q3), this will breach the pillar at or
## near the effect's expiry. This is the intended cost model — the pillar
## genuinely spends itself to replicate Counter-Hit. Do NOT add cooling
## or reduce the effect's heat to "save" the pillar.
##
## [b]Caster's own Counter-Hit is additive.[/b] Both the caster and the
## pillar independently record and broadcast — a target within 10m of
## both will receive two broadcast waves (one from each origin).
func _on_slot3_activated(_user: Node) -> void:
	if not is_instance_valid(caster):
		return
	_flash_replication()
	# Apply CounterHitEffect to the pillar's own reactor. Source = caster
	# so kill attribution on broadcast copies flows to the caster.
	# No separate cost effect — CounterHitEffect IS the cost (see Q4).
	_reactor.apply_effect(CounterHitEffect.new(caster))


## Handler: the caster's [signal CharacterBase.melee_strike] fired —
## echo the Slot 1 Resonance payload from this pillar's position.
##
## [b]Reaction, not modification.[/b] [CharacterBase] emits
## [signal melee_strike] mid-strike with a fully-populated [MeleeEvent];
## by the time we run, prior listeners (e.g. [MeleeModifierEffect]s) have
## had their chance to mutate the event, and the character's own strike
## resolution is already committed to applying [member MeleeEvent.effects]
## to [member MeleeEvent.target]. This handler does NOT touch the event
## — it only fires a secondary resonance AoE burst from the pillar's own
## position so the pillar appears to "echo" the caster's resonance reach.
##
## [b]Landed-hit gate (per resonance_pillar.md Q5).[/b] Inspecting
## [code]character_base.gd[/code] lines ~396-413, [signal melee_strike]
## is only emitted after [code]_find_melee_target[/code] returns a
## non-null target, so [code]event.target == null[/code] is effectively
## impossible at signal time — we still defensively check it. The more
## meaningful gate is [member MeleeEvent.cancelled]: a prior listener
## (e.g. a [MeleeModifierEffect]) may have aborted the strike, and if
## the caster's strike is cancelled the pillar's echo must skip too.
## [b]No new[/b] [MeleeEvent] [b]field is needed[/b] — the existing
## cancelled / target semantics already satisfy "landed hit".
##
## [b]Scan shape.[/b] The loop below mirrors [code]AoeAbility._deliver_aoe_at[/code]
## intentionally (get_tree → "characters" group → self-skip → _dead skip
## → horizontal-range skip → get_reactor → apply_effect) so a future
## reader can diff the two side-by-side. The one deliberate divergence
## is the [member is_pillar] skip: this is the first scan in the
## codebase that explicitly filters pillars out of "characters", and
## without it multiple deployed pillars would resonance-chain each
## other infinitely via their own reactors.
##
## [b]Cost semantics.[/b] The 20.0-heat replication cost is applied to
## the pillar's OWN reactor (attribution = self, i.e. the pillar), not
## the caster's — the pillar is the one emitting, so it's the one that
## pays. [code]is_stackable=true[/code] so multiple strikes landing in
## the same tick don't collapse into a single cost entry;
## [code]is_refreshable=false[/code] matches the convention used by
## [code]KnockbackAbility.create_self_effects[/code] for 1-tick cost
## effects. The cost fires regardless of hit count — even if the AoE
## scan finds zero valid targets (e.g. only the caster was in range and
## got self-skipped), the pillar still "resonated" and still pays.
## This matches the caster's own Resonance pattern, where activation-
## cost effects fire on toggle regardless of who happens to be nearby.
##
## [b]Order of operations.[/b] AoE delivery happens BEFORE the cost is
## applied, so if this single strike pushes the pillar over
## [member ReactorCore.max_heat] on the same tick (triggering the
## [member ReactorCore.break_on_breach_deletes_host] instant-deletion
## path), the echo has already been dispatched to targets before the
## pillar vanishes.
func _on_caster_melee_strike(event: MeleeEvent) -> void:
	if not is_instance_valid(caster):
		return
	if not _slot1_active:
		return
	# Landed-hit gate (Q5): skip whiffs and listener-cancelled strikes.
	# target == null is defensive — character_base.gd only emits
	# melee_strike after a non-null target has been resolved — but a
	# prior MeleeModifierEffect may have set cancelled = true, in which
	# case the echo must skip too. No new MeleeEvent field is required;
	# the existing semantics already satisfy "landed hit".
	if event.cancelled or event.target == null:
		return
	_flash_replication()

	# -- AoE delivery at the pillar's position ----------------------------
	# Inlined copy of AoeAbility._deliver_aoe_at's scan+apply loop with
	# one deliberate addition: the is_pillar skip, which prevents pillars
	# from resonance-chaining each other when multiple are deployed.
	# Radius = 10.0 m horizontal (Resonance's canonical reach). Origin =
	# this pillar's global position. Effects are attributed to the
	# caster (source = caster) so escalation-on-refresh and kill credit
	# flow back to them, matching the caster's own Resonance punches.
	var aoe_radius := 10.0
	var origin := global_position
	var tree := get_tree()
	if tree:
		for node in tree.get_nodes_in_group("characters"):
			if node == caster:
				continue
			var body := node as Node3D
			if not body:
				continue
			if body.get("_dead"):
				continue
			# Pillar→pillar cascade guard — see doc-comment above. This
			# is the one divergence from AoeAbility._deliver_aoe_at.
			if body.get("is_pillar"):
				continue

			# Horizontal range check (Y-ignored, matches AoeAbility).
			var offset := body.global_position - origin
			offset.y = 0.0
			var dist := offset.length()
			if dist > aoe_radius or dist < 0.01:
				continue

			# Fetch target's reactor via the duck-typed accessor.
			var reactor: Node = body.get_reactor() if body.has_method("get_reactor") else null
			if not reactor:
				continue

			# Fresh effect per target — each instance is independent.
			# Source = caster so escalation-on-refresh still attributes
			# back to the caster and merges with their own Resonance
			# stacks rather than forking a pillar-sourced lineage.
			reactor.apply_effect(ResonantPunchEffect.new(caster))

	# -- Pay the replication cost (Q5) ------------------------------------
	# 20.0 heat, 1-tick, applied to THIS pillar's reactor. Source = self
	# so attribution for the self-heat is the pillar, not the caster.
	# is_stackable = true so multiple strikes in the same tick don't
	# collapse; is_refreshable = false mirrors KnockbackAbility's 1-tick
	# cost-effect convention. Fired unconditionally — even if the AoE
	# above found zero valid targets, the pillar still resonated.
	_reactor.apply_effect(StatusEffect.new("Resonance Replication Cost", 20.0, 1, self, true, false))


## Handler: the pillar's reactor has been breached — spawn a brief
## expanding resonance-violet flash sphere as a sibling node before the
## pillar is queue_freed by [method ReactorCore._fragile_break].
##
## The flash is added to the scene tree as a direct child of the current
## scene (NOT as a child of the pillar, since the pillar is about to be
## freed). A scale-up tween provides the "expanding" feel, and a Timer
## auto-frees the flash after the animation completes.
func _on_reactor_breached() -> void:
	# Kill any in-progress spawn tween so scale doesn't fight.
	if _spawn_tween and _spawn_tween.is_valid():
		_spawn_tween.kill()

	var tree := get_tree()
	if not tree or not tree.current_scene:
		return

	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	flash.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.3, 1.0, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.75, 0.35, 1.0)
	mat.emission_energy_multiplier = 8.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	flash.material_override = mat

	# Start small and expand — gives the "burst" feel.
	flash.scale = Vector3(0.3, 0.3, 0.3)

	tree.current_scene.add_child(flash)
	flash.global_position = global_position + Vector3(0.0, 1.25, 0.0)  # Centre of pillar

	# Expand tween: scale up to full size over 0.15 s.
	var expand_tween := tree.create_tween()
	expand_tween.tween_property(flash, "scale", Vector3(1.8, 1.8, 1.8), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Auto-free after the expand finishes.
	var timer := Timer.new()
	timer.wait_time = 0.2
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(flash.queue_free)
	flash.add_child(timer)


## Brief emission-energy pulse on the pillar's mesh to visually signal
## that the pillar just replicated an ability. Tweens emission energy
## from 12.0 → 4.0 over 0.2 s. Kills any in-progress flash tween first
## so rapid activations don't conflict.
func _flash_replication() -> void:
	if not is_instance_valid(_mesh_inst):
		return
	var mat: StandardMaterial3D = _mesh_inst.material_override as StandardMaterial3D
	if not mat:
		return

	# Kill previous flash tween if still running.
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()

	# Spike emission energy high and tween it back to resting value.
	mat.emission_energy_multiplier = 12.0
	_flash_tween = create_tween()
	_flash_tween.tween_property(mat, "emission_energy_multiplier", 4.0, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
