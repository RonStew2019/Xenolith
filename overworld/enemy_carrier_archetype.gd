extends Resource
class_name EnemyCarrierArchetype
## Static factory defining enemy carrier archetypes — Scout, Standard,
## and Fortress.
##
## Each archetype bundles visual identity (color, scale), combat stats
## (reactor multipliers, armor, defense), and a mech complement that
## determines what AI mechs the carrier deploys in combat.
##
## Selection is strength-based via [method for_strength]:
##   • strength 1.0–2.0 → Scout
##   • strength 2.1–5.0 → Standard
##   • strength 5.1+     → Fortress

# -- Properties ------------------------------------------------------------

## Internal identifier (e.g. &"Scout", &"Standard", &"Fortress").
var archetype_name: StringName = &""

## UI-facing name (e.g. &"Scout Carrier").
var display_name: StringName = &""

## Visual tint on the overworld and in the combat arena.
var color: Color = Color.WHITE

## Visual size multiplier for the carrier box mesh.
var box_scale: Vector3 = Vector3.ONE

## Multiplied by strength for combat reactor integrity.
var reactor_integrity_mult: float = 250.0

## Multiplied by strength for combat reactor max heat.
var reactor_max_heat_mult: float = 200.0

## Damage reduction in combat (0.0–1.0).
var armor: float = 0.5

## Passive defense turret strength in combat.
var defense_strength: float = 15.0

## Mechs this carrier deploys in combat.  Each entry:
## [code]{"chassis": &"dogfighter"|&"bomber", "weapon_preset": &"basic"|&"status_effect"}[/code]
var mech_complement: Array[Dictionary] = []

# -- Static Factories ------------------------------------------------------

## Fast, fragile scout — one light mech, low defense.
static func scout() -> EnemyCarrierArchetype:
	var a := EnemyCarrierArchetype.new()
	a.archetype_name = &"Scout"
	a.display_name = &"Scout Carrier"
	a.color = Color(0.9, 0.6, 0.15)
	a.box_scale = Vector3(0.7, 0.7, 0.7)
	a.reactor_integrity_mult = 150.0
	a.reactor_max_heat_mult = 120.0
	a.armor = 0.3
	a.defense_strength = 5.0
	a.mech_complement = [
		{"chassis": &"dogfighter", "weapon_preset": &"basic"},
	]
	return a


## Balanced workhorse — mixed mech wing, moderate defense.
static func standard() -> EnemyCarrierArchetype:
	var a := EnemyCarrierArchetype.new()
	a.archetype_name = &"Standard"
	a.display_name = &"Standard Carrier"
	a.color = Color(0.8, 0.2, 0.15)
	a.box_scale = Vector3(1.0, 1.0, 1.0)
	a.reactor_integrity_mult = 250.0
	a.reactor_max_heat_mult = 200.0
	a.armor = 0.5
	a.defense_strength = 15.0
	a.mech_complement = [
		{"chassis": &"dogfighter", "weapon_preset": &"basic"},
		{"chassis": &"dogfighter", "weapon_preset": &"basic"},
		{"chassis": &"bomber", "weapon_preset": &"basic"},
	]
	return a


## Lumbering fortress — heavy mech wing with status weapons, brutal defense.
static func fortress() -> EnemyCarrierArchetype:
	var a := EnemyCarrierArchetype.new()
	a.archetype_name = &"Fortress"
	a.display_name = &"Fortress Carrier"
	a.color = Color(0.5, 0.1, 0.1)
	a.box_scale = Vector3(1.4, 1.2, 1.4)
	a.reactor_integrity_mult = 400.0
	a.reactor_max_heat_mult = 350.0
	a.armor = 0.75
	a.defense_strength = 40.0
	a.mech_complement = [
		{"chassis": &"dogfighter", "weapon_preset": &"status_effect"},
		{"chassis": &"dogfighter", "weapon_preset": &"status_effect"},
		{"chassis": &"dogfighter", "weapon_preset": &"status_effect"},
		{"chassis": &"bomber", "weapon_preset": &"status_effect"},
		{"chassis": &"bomber", "weapon_preset": &"status_effect"},
	]
	return a


## Pick the archetype matching a given combat strength.
##
## [param strength] — carrier combat strength (1.0–10.0+).[br]
## Returns: Scout (1.0–2.0), Standard (2.1–5.0), or Fortress (5.1+).
static func for_strength(strength: float) -> EnemyCarrierArchetype:
	if strength <= 2.0:
		return scout()
	elif strength <= 5.0:
		return standard()
	else:
		return fortress()
