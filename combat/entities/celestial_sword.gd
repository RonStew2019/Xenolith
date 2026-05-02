class_name CelestialSwordEntity
extends Area3D
## A celestial sword entity deployed into the world by a Celestial Armory
## ability.
##
## Part of the **Celestial Armory** loadout — three sword abilities that
## toggle between a passive self-buff ([CelestialSwordAuraEffect] on the
## wielder's reactor) and a deployed sword entity (this node) placed in
## the world.  When deployed, the ability removes the aura and spawns this
## entity; when recalled, the entity emits [signal recalled] and frees
## itself, and the ability re-applies the aura.
##
## [b]Skeleton:[/b] This base entity is an inert observer — it has no
## [ReactorCore], deals no damage, and applies no area effects.  Per-sword
## variants will extend the [method _on_body_entered] stub and/or add
## tick-driven area logic to implement their specific deployed behaviours
## (burning aura, frost zone, etc.).
##
## [b]Pattern reference:[/b] Follows the [ResonancePillar] entity pattern
## (joins [code]"characters"[/code] group, duck-typed [member caster]
## reference, visual mesh built in [method _ready]) but is deliberately
## simpler — no hosted [ReactorCore], no ability subscriptions, no
## replication logic.  Those layers will be added incrementally as the
## Celestial Armory design solidifies.
##
## [b]Collision model:[/b] [code]collision_layer = 0[/code] (invisible to
## other physics queries), [code]monitoring = true[/code] (detects bodies
## entering its sphere of influence), [code]monitorable = false[/code]
## (other areas cannot detect it).  The influence sphere is a 5.0 m radius
## [SphereShape3D] — per-sword variants will tune this radius and connect
## area-effect logic in [method _on_body_entered].

## Emitted when [method recall] is called, just before the entity frees
## itself.  The owning ability should connect to this to know when to
## re-apply the [CelestialSwordAuraEffect].
signal recalled

## Emitted when the sword is destroyed by an external source (future use).
## Not yet wired — reserved for when swords gain a [ReactorCore] and can
## be attacked by enemies.
signal destroyed

## The character that deployed this sword.  Attribution anchor for any
## effects the sword applies on behalf of its wielder.  Set by the
## spawning ability BEFORE the entity is added to the scene tree, so
## [method _ready] can rely on this being non-null.
var caster: Node = null

## Identifies which sword this entity represents (e.g. "Sword of Flame",
## "Sword of Frost").  Set by the spawning ability alongside [member caster].
var sword_name: String = ""

## Back-reference to the [CelestialSwordAbility] instance that spawned
## this entity.  Allows the entity to notify the ability of lifecycle
## events (destruction, recall) without going through signal plumbing
## alone.  May be null if the entity is spawned outside the normal
## ability flow (e.g. tests, debug).
var owning_ability = null

## Marker that lets character-only filters exclude sword entities from
## mech-only code paths, matching the [ResonancePillar] convention.
## Scanners that need mech-only behaviour check
## [code]node.get("is_sword_entity")[/code] and skip truthy results.
var is_sword_entity: bool = true

## Reference to the sword's visual mesh, stored so subclasses can animate
## or swap the material (e.g. elemental glow changes).
var _mesh_inst: MeshInstance3D = null


func _ready() -> void:
	# -- Collision configuration ----------------------------------------
	# The sword is a non-collidable observer: it detects bodies entering
	# its influence radius but is itself invisible to raycasts, physics
	# queries, and other area scans.
	collision_layer = 0
	monitoring = true
	monitorable = false

	# -- Group membership -----------------------------------------------
	# Join "characters" so AoE / projectile / AI scans can pick it up
	# uniformly with mechs and pillars.  The is_sword_entity marker lets
	# mech-only code paths filter it back out.
	add_to_group("characters")

	# -- Influence sphere (area detection) ------------------------------
	# 5.0 m radius sphere — bodies entering this volume will trigger
	# _on_body_entered once per-sword area effects are implemented.
	var sphere := SphereShape3D.new()
	sphere.radius = 5.0
	var col := CollisionShape3D.new()
	col.shape = sphere
	# Centre the sphere at sword mid-height so the influence volume is
	# roughly centred on the blade, not the ground anchor point.
	col.position.y = 0.75
	add_child(col)

	# -- Placeholder visual (emissive gold planted sword) ---------------
	# A thin vertical box representing the blade, tilted slightly forward
	# to evoke a sword planted point-down into the ground.
	_mesh_inst = MeshInstance3D.new()
	var blade := BoxMesh.new()
	blade.size = Vector3(0.15, 1.5, 0.05)
	_mesh_inst.mesh = blade

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.3)
	mat.emission_energy_multiplier = 3.0
	_mesh_inst.material_override = mat

	# Position the blade so its bottom sits near ground level, then tilt
	# it ~10° forward on the X axis to look like a planted sword.
	_mesh_inst.position.y = 0.75  # centre of 1.5 m blade
	_mesh_inst.rotation.x = deg_to_rad(-10.0)
	add_child(_mesh_inst)

	# -- Body-entered subscription --------------------------------------
	body_entered.connect(_on_body_entered)


## Recall the sword — emits [signal recalled] so the owning ability can
## react (re-apply aura, clear its entity reference, etc.), then frees
## the entity from the scene tree.
func recall() -> void:
	recalled.emit()
	queue_free()


## Stub handler for bodies entering the sword's influence sphere.
## Per-sword subclasses will override this to apply area effects (e.g.
## burning DoT, frost slow, lightning chain) to valid targets.
func _on_body_entered(_body: Node3D) -> void:
	# TODO: Per-sword area-of-influence logic goes here.
	# Pattern: validate target (skip caster, skip dead, skip other swords),
	# fetch reactor via body.get_reactor(), apply sword-specific effect.
	pass
