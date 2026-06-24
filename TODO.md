# XENOLITH — Design Roadmap

> **The Pitch:** You pilot a mobile carrier — part aircraft carrier, part oil rig, part nuclear plant — across a hex-based Crater. Park on resource nodes, harvest materials, fabricate mechs, and when threats show up, launch your mechs to fight. You pilot one yourself.

---

## What We Keep

These existing systems carry forward largely intact:

- [x] **ReactorCore / Overheat system** — heat-as-damage is THE combat model, this stays
- [x] **CombatTickClock** — tick-driven combat processing stays
- [x] **StatusEffect base class** — effects are atomic, tick-synced, RefCounted — all good
- [x] **PunchEffect / MeleeModifierEffect** — melee foundation stays (dogfighter bread & butter)
- [x] **Death explosion pipeline** — mech destruction stays
- [x] **Procedural glTF character generation** — extend for different chassis types
- [x] **Ability base class** (INSTANT/TOGGLE/HOLD) — weapons are abilities
- [x] **Loadout system** — maps to weapon slots per chassis
- [x] **ReactorHUD / AbilityBar / FloatingNumber** — combat UI carries forward
- [x] **Projectile delivery** — foundation for bomber weapons

### Likely Cannibalized / Reworked
- [ ] `Cave.tscn` / `cave.gd` — old arena, replaced by hex overworld + engagement arenas
- [ ] `npc.gd` / `npc.tscn` — replaced by AI-controlled mechs and fauna
- [ ] `flux_node.gd` — old roguelike mechanic, probably goes away
- [ ] `teleporter.gd` — old traversal, replaced by carrier movement
- [ ] `inventory.gd` — rework into carrier resource system
- [ ] `loadout_console.gd` / `loadout_menu.gd` — rework into fabrication/hangar UI
- [ ] Many specific abilities (celestial sword, resonance pillar, tunnel, clone) — evaluate which fit the new vision vs. which were roguelike-specific

---

## Design Pillars

### Rock-Paper-Scissors Triangle
| Role | Beats | Loses To | Character |
|------|-------|----------|-----------|
| **Bomber** | Carriers (long-range artillery) | Dogfighters (too slow to duel) | Slow, high damage, long range |
| **Dogfighter** | Bombers (too nimble to hit) | Carriers (can't penetrate armor) | Fast, low damage, short range |
| **Carrier** | Dogfighters (shrug off their attacks) | Bombers (can't dodge artillery) | Immobile, very durable |

> *"When I talk about dogfighters/bombers/carriers that's more spiritual than mechanical — we don't need missiles and A-10 warthogs."*

### Chassis Weapon Slots
| Chassis | Slots |
|---------|-------|
| **Dogfighter** | L-Hand, R-Hand, L-Shoulder, R-Shoulder (4) |
| **Bomber** | L-Hand, R-Hand, Artillery (3) |

### Terrain Types (Hex Overworld)
| Terrain | Character |
|---------|-----------|
| **Flora/Jungle** | Dense, choked — favors dogfighters? |
| **Desert** | Wide open, no cover — favors bombers? |
| **Irradiated** | Ambient overheating — pressure on everyone |
| **Mountains** | Default — decent cover, not choked |
| **Resource Nodes** | Harvestable — the reason you're here |

---

## Phase 1 — Hex Overworld & Carrier Core

*Get the carrier moving on a hex map. No combat yet — just the strategic layer.*

- [x] **Hex grid system**
  - [x] Hex tile data model (terrain type, resource node, occupant)
  - [x] Hex grid rendering (top-down or slight perspective)
  - [x] Terrain type visuals (flora, desert, irradiated, mountain, resource)
- [x] **Carrier entity**
  - [x] Carrier movement on hex grid (click-to-move or WASD)
  - [x] Carrier "parking" on a hex (occupying it)
  - [x] Basic carrier stats (speed, hull)
- [x] **Resource system**
  - [x] Resource node types and yields
  - [x] Harvesting mechanic (park on node → accumulate resources over time)
  - [x] Resource inventory (replaces old `inventory.gd`)
- [x] **Camera system for overworld**
  - [x] Top-down / strategic camera
  - [x] Zoom, pan, follow-carrier

---

## Phase 2 — Carrier Customization

*Build out your carrier with modular nodes.*

- [x] **Carrier node system**
  - [x] Node slot architecture (carrier has N slots for modules)
  - [x] **Fabricator node** — unlocks mech building, determines build speed
  - [x] **Hangar node** — stores fabricated mechs, determines max capacity
  - [x] **Harvester node** — determines harvest rate from resource nodes
  - [x] **Automated defense node** — passive defense strength
  - [x] **Reactor node** — powers the carrier, win condition target
- [x] **Fabrication / mech building**
  - [x] Mech blueprint system (chassis + weapon loadout = blueprint)
  - [x] Build queue (resources + time → mech in hangar)
  - [x] Chassis types (dogfighter, bomber) as blueprint foundation
- [x] **Carrier customization UI**
  - [x] Node placement / management screen
  - [x] Blueprint creation screen
  - [x] Hangar overview (see your mechs)

---

## Phase 3 — Engagement System

*Bridge between strategic layer and combat. The "scramble your jets" moment.*

- [x] **Threat system**
  - [x] Threat detection (something enters your hex or adjacent hexes)
  - [x] Threat types: fauna (early game), enemy carriers (mid/late)
  - [x] Enemy carrier AI — stronger = slower, weaker = faster (guerilla incentive)
  - [x] Fauna hive/nest as destroyable objective
- [x] **Deployment flow**
  - [x] Engagement trigger → deployment screen
  - [x] Choose which mechs from hangar to deploy (costs resources)
  - [x] Choose which mech YOU pilot
  - [x] Deploy into combat arena
- [x] **Combat arena generation**
  - [x] Arena reflects terrain type of the hex (jungle = dense, desert = open, etc.)
  - [x] Enemy carrier / hive placed as objective
  - [x] Your carrier present (defend its reactor)
- [x] **Mid-engagement mechanics**
  - [x] Deploy reserve mechs from hangar during combat
  - [x] When your mech is destroyed → choose another deployed mech to pilot
  - [x] Win condition: destroy enemy carrier reactor / hive
  - [x] Lose condition: your carrier reactor destroyed
- [x] **Engagement resolution**
  - [x] Return surviving mechs to hangar
  - [x] Resource cost accounting
  - [x] Return to overworld

---

## Phase 4 — Mech Combat (Adapt Existing Systems)

*This is where we cannibalize. Adapt the existing combat for the new chassis/weapon model.*

- [x] **Chassis system**
  - [x] Dogfighter CharacterBody3D (fast, nimble — adapt existing player controller)
  - [x] Bomber CharacterBody3D (slow, tanky)
  - [x] Chassis determines: speed, max heat, base armor, weapon slots
- [x] **Weapon slot system**
  - [x] Rework Loadout to be slot-based per chassis
  - [x] L-Hand, R-Hand slots (both chassis)
  - [x] L-Shoulder, R-Shoulder slots (dogfighter only)
  - [x] Artillery slot (bomber only)
  - [x] Weapons as abilities mapped to slots
- [x] **Weapons (heat-focused)**
  - [x] Most weapons = "empty" status effects that just add heat
  - [x] Short-range weapons (dogfighter bread & butter) — adapt melee/punch system
  - [x] Long-range weapons (bomber focus) — adapt projectile system
  - [x] Artillery weapon (bomber exclusive) — high damage, slow, AoE?
  - [ ] Special status effect weapons can come later (not primary concern)
- [x] **Procedural mech models**
  - [x] Extend `generate_character.py` for dogfighter silhouette
  - [x] Extend for bomber silhouette (bulkier, artillery mount)
  - [x] Visual distinction between chassis types
- [x] **AI mech behavior**
  - [x] Dogfighter AI (close gap, strafe, stay nimble)
  - [x] Bomber AI (maintain distance, line up artillery shots)
  - [x] Fauna AI (simpler, aggressive swarm behavior)
- [x] **Carrier combat target**
  - [x] Carrier as destructible entity in combat arena
  - [x] Reactor as targetable weak point
  - [x] Automated defense nodes active during combat
  - [x] Carrier armor (dogfighters bounce off, bombers penetrate)

---

## Phase 5 — UI Layer

*Strategic + combat UI.*

- [ ] **Overworld UI**
  - [x] Hex grid info panel (terrain type, resources, threats)
  - [x] Carrier status panel (nodes, resources, hangar count)
  - [x] Threat indicators on map
- [ ] **Deployment UI**
  - [ ] Mech selection screen (from hangar)
  - [ ] Pilot selection
  - [ ] Resource cost display
  - [ ] "Launch" button
- [ ] **Combat HUD** (adapt existing)
  - [ ] ReactorHUD — stays, per-mech heat display
  - [ ] AbilityBar — adapt for weapon slots
  - [ ] FloatingNumber — stays
  - [ ] "Switch mech" prompt on destruction
  - [ ] Reserve deployment button mid-combat
  - [ ] Enemy carrier health/reactor status
- [ ] **Fabrication UI**
  - [ ] Blueprint designer (chassis + weapons)
  - [ ] Build queue display
  - [ ] Hangar browser

---

## Phase 6 — Polish & Progression

*The stuff that makes it a game.*

- [ ] **Progression curve**
  - [ ] Early game: fauna threats, scavenge resources, build first mechs
  - [ ] Mid game: encounter weak enemy carriers, expand carrier
  - [ ] Late game: strong enemy carriers, fully kitted hangar
- [ ] **Economy balancing**
  - [ ] Resource costs for mech deployment (incentivize minimum force)
  - [ ] Build costs for mechs and carrier nodes
  - [ ] Harvest rates vs. consumption rates
- [ ] **Enemy carrier variety**
  - [ ] Weak/fast scout carriers
  - [ ] Strong/slow fortress carriers
  - [ ] Carrier loadout variety (different defense nodes, mech complements)
- [ ] **Special status effects (stretch)**
  - [ ] Beyond pure heat — once the core loop is solid
  - [ ] Poison, freeze, EMP, etc. as rare weapon mods

---

## Open Questions

> *To revisit as we build:*

- [ ] Is the overworld real-time or turn-based? (Hex + carriers suggests turn-based could work well)
- [ ] How does "ambient overheating" in irradiated hexes work — during overworld travel, during combat, or both?
- [ ] Fauna threat details — what's a hive look like? Swarms of small things? One big thing?
- [ ] Do carriers have their own ReactorCore using the existing overheat system, or a separate health model?
- [ ] Can you lose your carrier entirely, or is it game-over if reactor goes?
- [ ] Multiplayer? (PvP carrier battles would be natural but scope is huge)
- [ ] What does "guerilla play" look like mechanically? Hit-and-run harvesting? Stealth hexes?
