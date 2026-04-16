Resonance Pillar — Implementation Plan

══════════════════════════════════════════



│ Goal: Replace MortarAbility in the "Resonance Mk.I" loadout with ResonancePillarAbility — a projectile that anchors

│  on terrain as a persistent pillar with its own weak reactor, subscribes via signals to the caster's Slot 1/2/3 abi

│ lities, and replicates each ability's behavior from its own position while paying the heat cost on its own reactor.

│

│ Scope: Touches Ability layer, StatusEffect/ReactorCore layer, and introduces a new non-character combat entity. Cro

│ ss-cutting.

│

│ Ownership: Ability Agent (primary), Status Effect Agent (reactor behavior, cost-effect conventions), no Character A

│ gent involvement.



────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────



Phase 0 — Design decisions (RESOLVED)

─────────────────────────────────────



All six open design questions were resolved by the user before Phase 1 began. Bake these answers into the relevant later-phase items.



\[x] Q1 — Pillar-on-caster-death: **Pillars despawn when the caster dies.** `ResonancePillarAbility.force_deactivate` iterates and frees owned pillars; `CharacterBase.die()` → `Loadout.deactivate_all` propagates this automatically.

\[x] Q2 — Pillar group membership: **Option A — pillars join the "characters" group with an `is_pillar = true` marker.** AI/loadout/melee/AoE code paths filter on the flag rather than introducing a new group. Smaller blast radius on existing code.

\[x] Q3 — Weak reactor tuning: **max_heat = 100, max_integrity = 1.** Any overflow instantly deletes the pillar (no integrity-damage phase), via the `break_on_breach_deletes_host` flag from Phase 1.3.

\[x] Q4 — Counter-hit cost-effect: **No separate cost effect — the cost is inherent in `CounterHitEffect` itself.** `CounterHitEffect` already contributes `10.0 heat/tick × 10 ticks = 100 total heat`, which at pillar `max_heat = 100` (Q3) means a pillar that replicates Counter-Hit will breach at or near the effect's expiry. This is **emergent by design**: pillars genuinely spend themselves on Counter-Hit replication. Phase 5.1 implementers should NOT try to "fix" the pillar dying from this — it's the intended cost model.

\[x] Q5 — Resonance melee replication cost: **20.0 heat, 1-tick, applied to the pillar's own reactor on each landed caster melee strike** while Slot 1 is active. Triggered by a **landed hit** (not a whiff) — the `melee_strike` handler must gate on hit confirmation (see Phase 3.2 edge-case note).

\[x] Q6 — KnockbackEffect source attribution when pillar replicates: **`KnockbackEffect.new(pillar)` — pillar is the source for both push-direction computation AND kill attribution.** Kills attributed to pillars are acceptable. No source-splitting refactor needed on `KnockbackEffect`.



────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────



Phase 1 — Architectural prep (foundations for everything else)

──────────────────────────────────────────────────────────────



These are reusable refactors that stand on their own and unblock pillar work. Do these first so Phase 2+ becomes smaller, cleaner changes.



1.1 — Generalize AoeCasterAbility → AoeAbility

Agent: Ability Agent



\[x] Rename combat/aoe\_caster\_ability.gd → combat/aoe\_ability.gd (class AoeAbility)

\[x] Refactor \_deliver\_aoe(user) → \_deliver\_aoe\_at(origin: Vector3, user: Node) where:

&#x20; ◦ origin is the spatial center of the burst (horizontal range check uses this)

&#x20; ◦ user is the caster (kept for self-exclusion via if node == user, attribution, and create\_other\_effects(user))

\[x] Add a thin wrapper \_deliver\_aoe(user) → \_deliver\_aoe\_at(user.global\_position, user) so existing subclasses keep working without modification

\[x] Update KnockbackAbility (and any other subclasses) to continue extending AoeAbility — no behavior change

\[x] Update doc-comments to reflect the new generalized pattern

\[x] Verify: Knockback, Counter-Hit AoE, and any other existing AoE ability still behave identically in-game



1.2 — Add ability lifecycle signals to Ability base class

Agent: Ability Agent



\[x] Add two signals to combat/ability.gd:

&#x20;gdscript ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

signal activated(user: Node)    # emitted on INSTANT fire and on TOGGLE/HOLD transition-to-active

signal deactivated(user: Node)  # emitted on TOGGLE second-press, HOLD release, or force\_deactivate

────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

\[x] Emit activated from activate():

&#x20; ◦ INSTANT: always emit

&#x20; ◦ TOGGLE: emit only on transition false → true

&#x20; ◦ HOLD: emit only on transition false → true

\[x] Emit deactivated from deactivate() (HOLD release path only where \_active goes true→false) and from force\_deactivate() (only when it actually deactivates a previously-active ability)

\[x] For TOGGLE abilities, the second-press deactivation path inside activate() must also emit deactivated

\[x] Confirm no existing listeners break (there shouldn't be any — signals are new)

\[x] Document the signal contract in the class doc-comment



1.3 — Introduce a "fragile reactor" behavior variant

Agent: Status Effect Agent



\[x] Decide: add a flag break\_on\_breach\_deletes\_host: bool = false to ReactorCore, OR create a FragileReactorCore subclass. Recommendation: a simple boolean flag on the base class, no subclass needed.

\[x] When the flag is set and reactor\_breached would fire, the reactor instead calls get\_parent().queue\_free() directly (skipping the normal integrity-damage → death pipeline that presumes a CharacterBase host with die())

\[x] Ensure fragile reactors still register/deregister with CombatTickClock correctly

\[x] Ensure all existing effect lifecycle (on\_apply/on\_tick/on\_remove) fires normally before deletion

\[x] Verify: a pillar can have this flag set, take a single heat-overflow tick, and vanish cleanly without the node tree complaining about dangling refs



1.4 — Define how non-character nodes can host a reactor

Agent: Status Effect Agent (+ light Ability Agent coordination)



\[ ] Current code paths that reach into a target assume CharacterBase-style interface: .get\_reactor(), \_dead property, global\_position, "characters" group membership. Document the minimum interface a reactor-hosting node must provide.

\[ ] Make sure ReactorCore.apply\_effect does not require the parent to be a CharacterBody3D or have a velocity field (currently KnockbackEffect assumes this — but Knockback shouldn't target pillars anyway; see Phase 5.2)

\[ ] Add a get\_reactor() method to whatever pillar class ends up hosting a reactor so apply\_effect-via-reactor-lookup code (e.g. AoeAbility.\_deliver\_aoe\_at) works uniformly



────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────



Phase 2 — Pillar entity \& projectile

────────────────────────────────────



2.1 — PersistentProjectile (new)

Agent: Ability Agent



\[ ] Create combat/persistent\_projectile.gd (class PersistentProjectile extends Area3D)

\[ ] Based on Projectile / AoeProjectile but with different collision semantics:

&#x20; ◦ collision\_mask = 1 (default/terrain layer only — NOT layer containing characters/other projectiles)

&#x20; ◦ On body\_entered with terrain: anchor at impact point, hand off to a ResonancePillar spawn, self-free

&#x20; ◦ Ignores bodies in the "characters" group (flies through them) — verify by checking groups before deciding to anchor

&#x20; ◦ Ignores other projectiles (they're on layer 0 already; collision\_mask exclusion is sufficient)

\[ ] Lifetime timer: if nothing hit within lifetime seconds, fizzle silently (no pillar spawned) — matches Projectile pattern

\[ ] Visual: small emissive orb in-flight, distinct color from other projectiles (suggest violet/cyan to match "resonance")

\[ ] setup(user, direction, speed, lifetime) — no effect payload needed; pillar spawn is the "payload"



2.2 — ResonancePillar (new scene entity)

Agent: Ability Agent (primary) + Status Effect Agent (reactor integration)



\[ ] Create combat/resonance\_pillar.gd (class ResonancePillar extends StaticBody3D — static so physics doesn't move it)

\[ ] Fields:

&#x20; ◦ caster: Node — the character that spawned this pillar

&#x20; ◦ \_reactor: ReactorCore — weak reactor with break\_on\_breach\_deletes\_host = true

&#x20; ◦ Cached references to caster abilities it listens to (Slot 1, Slot 2, Slot 3)

\[ ] \_ready():

&#x20; ◦ Add itself to the "characters" group with is\_pillar = true marker (per Q2, Option A)

&#x20; ◦ Create ReactorCore child with max\_heat = 100, max\_integrity = 1, break\_on\_breach\_deletes\_host = true (per Q3)

&#x20; ◦ Create collision shape (capsule or cylinder, \~0.5m radius × 2.5m height)

&#x20; ◦ Create visual mesh (emissive vertical column, same resonance color as projectile)

&#x20; ◦ Subscribe to caster's ability signals (see Phase 4)

\[ ] get\_reactor() -> Node — returns \_reactor so existing reactor-lookup code works

\[ ] \_exit\_tree(): disconnect all caster signals cleanly (handle both normal deletion and caster-already-freed)

\[ ] Defensive: every signal handler must is\_instance\_valid(caster) check at entry



2.3 — ResonancePillarAbility (slot 4)

Agent: Ability Agent



\[ ] Create combat/resonance\_pillar\_ability.gd (class ResonancePillarAbility extends ProjectileAbility)

\[ ] \_init: activation\_mode = INSTANT, projectile\_speed = 25.0, projectile\_lifetime = 4.0, ability\_name = "Resonance Pillar"

\[ ] create\_self\_effects(user): a "Pillar Cost" 1-tick effect (heat value TBD, suggest 15.0) — uses the existing cost-effect pattern

\[ ] Override \_fire\_projectile(user) to spawn PersistentProjectile instead of Projectile (since base ProjectileAbility.\_fire\_projectile spawns Projectile with effect payload — we don't want that)

\[ ] force\_deactivate(user): per Q1, optionally iterate owned pillars and free them on loadout swap / caster death. This is the one place we need pillar tracking on the ability — suggest the ability keeps a WeakRef-backed list of spawned pillars it can iterate for cleanup.



────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────



Phase 3 — Slot 1 (Resonance) replication via signals

────────────────────────────────────────────────────



Architectural note: User explicitly specified signal-based approach. No registry. Pillar subscribes to BOTH (a) caster's Slot 1 ability active-state signals AND (b) caster's melee\_strike signal. Gates on both.



3.1 — Pillar subscription wiring

Agent: Ability Agent



\[ ] In ResonancePillar.\_ready(), after caster is set:

&#x20; ◦ Look up caster's Slot 1 ability via caster.\_loadout.get\_ability\_for\_action("ability\_1")

&#x20; ◦ Connect to its activated and deactivated signals → maintain local \_slot1\_active: bool

&#x20; ◦ Seed \_slot1\_active with the ability's current is\_active() at subscription time (so toggle-already-on case works)

&#x20; ◦ Connect to caster.melee\_strike signal

\[ ] In \_exit\_tree(): disconnect all three connections with is\_connected guards



3.2 — Melee-strike handler (the "apply resonance around self" behavior)

Agent: Ability Agent (logic) + Status Effect Agent (cost effect creation)



\[ ] When caster's melee\_strike fires AND \_slot1\_active is true:

&#x20; ◦ Use the new \_deliver\_aoe\_at(pillar.global\_position, caster, 10.0, create\_resonant\_punch\_effect\_factory) helper (or call an equivalent from AoeAbility as a static/utility)

&#x20; ◦ Skip the caster, skip dead targets, skip other pillars (per Q2/Phase 5)

&#x20; ◦ Apply ResonantPunchEffect.new(caster) to each valid target's reactor (source = caster, so escalation-on-refresh still attributes to caster)

\[ ] Pay the cost: apply a 1-tick StatusEffect.new("Resonance Replication Cost", 20.0, 1, pillar, true, false) to the pillar's own reactor (per Q5 — 20.0 confirmed)

\[ ] Important: the MeleeEvent has already been emitted and effects applied by the time our handler runs — we're a reaction to a successful melee strike. Not modifying the strike, just echoing its resonance payload from pillar positions. Document this clearly.

\[ ] Gating on landed hits (per Q5): the pillar-echo only fires when the caster's melee strike actually connects. Inspect MeleeEvent to determine landed-vs-whiff — if MeleeEvent doesn't already expose this, coordinate with the status effect agent to add the minimum needed (e.g. event.target != null after resolution, or a bool flag). Do NOT echo on whiffs.



────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────



Phase 4 — Slot 2 (Repulse) replication via signals

──────────────────────────────────────────────────



4.1 — Pillar subscription to Slot 2 activation

Agent: Ability Agent



\[ ] In ResonancePillar.\_ready(): look up caster's Slot 2 ability, connect to its activated signal

\[ ] Handler: call a \_deliver\_aoe\_at(pillar.global\_position, caster, 5.5, knockback\_effect\_factory) using the Phase 1.1 helper

&#x20; ◦ Origin: pillar position (so push direction is away-from-pillar)

&#x20; ◦ User param: caster (so caster is still self-excluded and attribution flows correctly; other pillars excluded per Q2)

&#x20; ◦ Effect factory: KnockbackEffect.new(pillar) (per Q6 — pillar is source for both push-direction and kill attribution)

\[ ] Pay the cost: apply the same "Repulse Cost" 18.0 heat 1-tick effect to the pillar's own reactor (reuse the exact construction KnockbackAbility.create\_self\_effects uses)

\[ ] Caster's own Repulse still fires normally (additive behavior — option 2a confirmed)



4.2 — Interaction with the existing KnockbackEffect

Agent: Status Effect Agent



\[ ] KnockbackEffect currently assumes parent is CharacterBody3D and uses \_target.velocity += impulse and \_target.movement\_lock\_count. Confirm these are only ever called on reactor-hosts that ARE CharacterBody3D. The only new application path from pillars targets characters (pillars use the effect against other characters, not against themselves), so this should be fine, but double-check.

\[ ] Confirm pillars are NOT valid knockback targets (they're StaticBody3D, have no velocity). Per Q2 resolution, AoE filtering should skip pillars when delivering knockback.



────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────



Phase 5 — Slot 3 (Counter-Hit) replication via signals

──────────────────────────────────────────────────────



5.1 — Pillar subscription to Slot 3 activation

Agent: Ability Agent (wiring) + Status Effect Agent (CounterHitEffect behavior verification)



\[ ] In ResonancePillar.\_ready(): look up caster's Slot 3 ability, connect to its activated signal

\[ ] Handler: apply CounterHitEffect.new(caster) directly to the pillar's own reactor

&#x20; ◦ Source = caster (so kill attribution on the reflected broadcast goes to caster)

&#x20; ◦ The pillar's CounterHitEffect will then record any effects applied to the pillar's reactor for 10 ticks and broadcast them to characters within 10m of the pillar on expiry — exactly the behavior we want, for free

\[ ] No separate cost needed (per Q4): CounterHitEffect itself contributes 10 heat/tick × 10 ticks = 100 total heat. At pillar max_heat = 100 (Q3), Counter-Hit replication will typically breach the pillar at or near effect expiry. This is the intended cost model — do NOT try to reduce CounterHitEffect's heat or add cooling to "save" the pillar. Pillars genuinely spend themselves to replicate Counter-Hit.

\[ ] Caster's own counter-hit still fires normally on self (additive)



5.2 — Pillars must be valid targets for AoE and melee

Agent: Status Effect Agent (+ Ability Agent coordination)



\[ ] Per Q2 (Option A): pillars join "characters" group with is\_pillar = true marker

\[ ] Update AoeAbility.\_deliver\_aoe\_at to NOT skip pillars (currently it just scans "characters"; pillars being in that group means they get hit naturally — good)

\[ ] Update Projectile.\_on\_body\_entered to allow pillar hits (it currently requires "characters" group — pillar being in it means it's naturally hittable)

\[ ] KnockbackEffect: filter out pillars from being valid targets (they're not CharacterBody3D; the effect would no-op but we should skip cleanly). Cleanest: add an is\_pillar check in \_deliver\_aoe\_at before the reactor lookup, OR have KnockbackEffect.on\_apply early-return gracefully when target is not a CharacterBody3D.

\[ ] Melee targeting: audit character\_base.gd around line 396-413 (where melee\_strike.emit fires) — does melee hit-resolution target characters via raycast/area, and will it naturally hit pillars? Decide if pillars should be punch-able (feels like yes — landing a melee on your own pillar is absurd but on an enemy's pillar is valid).

\[ ] AI targeting audit: CombatAI should treat enemy pillars as viable low-priority targets (or ignore them entirely — design call). Flag this as a separate smaller follow-up task; out of scope for this plan but note the interaction exists.

\[ ] \_find\_living\_clone\_in\_family() / clone family-tree traversal: must ignore pillars. Verify by code inspection.



────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────



Phase 6 — Loadout swap \& integration

────────────────────────────────────



6.1 — Wire into LoadoutPresets

Agent: Ability Agent



\[ ] In combat/loadout\_presets.gd, replace MortarAbility.new("ability\_4") with ResonancePillarAbility.new("ability\_4") in the "Resonance Mk.I" branch

\[ ] Keep MortarAbility in the codebase (it's still referenced by "Xenolith Mk.I"? — verify; if not, it can stay as a reusable option for future presets or be archived)



6.2 — Cleanup paths

Agent: Ability Agent



\[ ] On caster loadout swap: Loadout.deactivate\_all(user) already calls force\_deactivate on every ability. Ensure ResonancePillarAbility.force\_deactivate frees all owned pillars (per Q1 decision).

\[ ] On caster death (per Q1 — pillars despawn): CharacterBase.die() path flows into loadout deactivation → ResonancePillarAbility.force\_deactivate → pillars freed. Verify the chain actually fires end-to-end.

\[ ] On pillar self-overheat-breach: break\_on\_breach\_deletes\_host frees the pillar node; its \_exit\_tree() disconnects signals cleanly. Verify no dangling WeakRef issues in the ability's pillar-list.



────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────



Phase 7 — Polish \& verification

───────────────────────────────



7.1 — Visual polish

\[ ] Pillar emissive column (resonance color)

\[ ] Spawn animation on terrain impact (quick vertical growth tween)

\[ ] Breach-delete flash (brief expanding sphere, similar to AoeProjectile.\_spawn\_explosion\_flash)

\[ ] Replication-trigger flash on the pillar when it fires Repulse / Resonance melee AoE / receives Counter-Hit (helps legibility)



7.2 — End-to-end scenario tests

\[ ] Fire 3 pillars around an NPC cluster. Toggle Resonance (Slot 1) on. Punch. Confirm: NPCs take resonance from each pillar's 10m radius + from the caster's direct strike.

\[ ] Press Repulse with 3 pillars surrounding an NPC. Confirm: NPC gets pushed out of each pillar's radius correctly; caster's own burst also fires.

\[ ] Press Counter-Hit with 3 pillars. Have enemies AoE the caster AND the pillars. Wait 10 ticks. Confirm: caster broadcasts recorded-on-self effects from caster position; each pillar independently broadcasts what it recorded from its position.

\[ ] Force a pillar to overheat by spamming abilities near it. Confirm: pillar instant-deletes, no integrity-damage phase, no dangling signal subscriptions, no errors in log.

\[ ] Swap loadout mid-battle with pillars active. Confirm: pillars cleanly despawn, Resonance Mk.I can be re-selected and new pillars can be placed.

\[ ] Caster dies with pillars active. Confirm behavior matches Q1 resolution (despawn or persist).



7.3 — UI considerations (flag for UI Agent later, not in scope now)

\[ ] AbilityBar currently shows active state for TOGGLE abilities — does it need anything for ResonancePillarAbility (INSTANT)? Probably not.

\[ ] Pillar-count HUD element? (Would need pillar-list access on the ability — WeakRef list from 2.3 would support it.) Out of scope for this plan.

\[ ] Floating numbers from pillar-origin AoE will naturally show at each pillar's position — confirm existing FloatingNumber spawn logic uses the target's position (not the source's), so this works automatically.

