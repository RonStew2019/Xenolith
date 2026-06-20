extends RefCounted
class_name WeaponRegistry
## Static registry mapping weapon ID [StringName]s to [Ability] factories.
##
## Each weapon is identified by a unique [StringName] (e.g.
## [code]&"punch_amplifier"[/code]).  Call [method create_weapon] to get a
## fresh [Ability] instance ready to assign to a loadout slot.
##
## To register a new weapon:
##   1. Create an [Ability] subclass in [code]combat/abilities/[/code].
##   2. Add a match branch in [method create_weapon].


## Create a fresh [Ability] for the given weapon ID.
##
## [param weapon_id] — registered weapon identifier.[br]
## [param slot_name] — the chassis slot this weapon will occupy (for future
## per-slot tuning; currently unused).[br]
## Returns [code]null[/code] with a warning for unknown IDs.
static func create_weapon(weapon_id: StringName, _slot_name: StringName) -> Ability:
	match weapon_id:
		&"punch_amplifier":
			return PunchAmplifierAbility.new()
		&"heat_cannon":
			return HeatCannonAbility.new()
		_:
			push_warning("WeaponRegistry: unknown weapon_id '%s'" % weapon_id)
			return null
