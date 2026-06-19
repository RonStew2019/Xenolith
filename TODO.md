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
- [ ] **Camera system for overworld**
  - [ ] Top-down / strategic camera
  - [ ] Zoom, pan, follow-carrier

---

## Phase 2 — Carrier Customization

*Build out your carrier with modular nodes.*

- [ ] **Carrier node system**
  - [ ] Node slot architecture (carrier has N slots for modules)
  - [ ] **Fabricator node** — unlocks mech building, determines build speed
  - [ ] **Hangar node** — stores fabricated mechs, determines max capacity
  - [ ] **Harvester node** — determines harvest rate from resource nodes
  - [ ] **Automated defense node** — passive defense strength
  - [ ] **Reactor node** — powers the carrier, win condition target
- [ ] **Fabrication / mech building**
  - [ ] Mech blueprint system (chassis + weapon loadout = blueprint)
  - [ ] Build queue (resources + time → mech in hangar)
  - [ ] Chassis types (dogfighter, bomber) as blueprint foundation
- [ ] **Carrier customization UI**
  - [ ] Node placement / management screen
  - [ ] Blueprint creation screen
  - [ ] Hangar overview (see your mechs)

---

## Phase 3 — Engagement System

*Bridge between strategic layer and combat. The "scramble your jets" moment.*

- [ ] **Threat system**
  - [ ] Threat detection (something enters your hex or adjacent hexes)
  - [ ] Threat types: fauna (early game), enemy carriers (mid/late)
  - [ ] Enemy carrier AI — stronger = slower, weaker = faster (guerilla incentive)
  - [ ] Fauna hive/nest as destroyable objective
- [ ] **Deployment flow**
  - [ ] Engagement trigger → deployment screen
  - [ ] Choose which mechs from hangar to deploy (costs resources)
  - [ ] Choose which mech YOU pilot
  - [ ] Deploy into combat arena
- [ ] **Combat arena generation**
  - [ ] Arena reflects terrain type of the hex (jungle = dense, desert = open, etc.)
  - [ ] Enemy carrier / hive placed as objective
  - [ ] Your carrier present (defend its reactor)
- [ ] **Mid-engagement mechanics**
  - [ ] Deploy reserve mechs from hangar during combat
  - [ ] When your mech is destroyed → choose another deployed mech to pilot
  - [ ] Win condition: destroy enemy carrier reactor / hive
  - [ ] Lose condition: your carrier reactor destroyed
- [ ] **Engagement resolution**
  - [ ] Return surviving mechs to hangar
  - [ ] Resource cost accounting
  - [ ] Return to overworld

---

## Phase 4 — Mech Combat (Adapt Existing Systems)

*This is where we cannibalize. Adapt the existing combat for the new chassis/weapon model.*

- [ ] **Chassis system**
  - [ ] Dogfighter CharacterBody3D (fast, nimble — adapt existing player controller)
  - [ ] Bomber CharacterBody3D (slow, tanky)
  - [ ] Chassis determines: speed, max heat, base armor, weapon slots
- [ ] **Weapon slot system**
  - [ ] Rework Loadout to be slot-based per chassis
  - [ ] L-Hand, R-Hand slots (both chassis)
  - [ ] L-Shoulder, R-Shoulder slots (dogfighter only)
  - [ ] Artillery slot (bomber only)
  - [ ] Weapons as abilities mapped to slots
- [ ] **Weapons (heat-focused)**
  - [ ] Most weapons = "empty" status effects that just add heat
  - [ ] Short-range weapons (dogfighter bread & butter) — adapt melee/punch system
  - [ ] Long-range weapons (bomber focus) — adapt projectile system
  - [ ] Artillery weapon (bomber exclusive) — high damage, slow, AoE?
  - [ ] Special status effect weapons can come later (not primary concern)
- [ ] **Procedural mech models**
  - [ ] Extend `generate_character.py` for dogfighter silhouette
  - [ ] Extend for bomber silhouette (bulkier, artillery mount)
  - [ ] Visual distinction between chassis types
- [ ] **AI mech behavior**
  - [ ] Dogfighter AI (close gap, strafe, stay nimble)
  - [ ] Bomber AI (maintain distance, line up artillery shots)
  - [ ] Fauna AI (simpler, aggressive swarm behavior)
- [ ] **Carrier combat target**
  - [ ] Carrier as destructible entity in combat arena
  - [ ] Reactor as targetable weak point
  - [ ] Automated defense nodes active during combat
  - [ ] Carrier armor (dogfighters bounce off, bombers penetrate)

---

## Phase 5 — UI Layer

*Strategic + combat UI.*

- [ ] **Overworld UI**
  - [ ] Hex grid info panel (terrain type, resources, threats)
  - [ ] Carrier status panel (nodes, resources, hangar count)
  - [ ] Threat indicators on map
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
