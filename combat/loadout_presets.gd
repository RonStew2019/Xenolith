extends RefCounted
class_name LoadoutPresets
## Static registry of named loadout presets.
##
## Each preset is a named factory that returns a fully-configured [Loadout]
## with abilities mapped to action slots (ability_1 .. ability_4).
##
## To add a new preset:
##   1. Append its name to [member _names].
##   2. Add a match branch in [method create_loadout].

## Ordered list of preset names shown in the selection UI.
static var _names: Array[String] = [
	"Xenolith Mk.I",
	"Resonance Mk.I",
]


## Return the display-ordered list of available preset names.
static func get_preset_names() -> Array[String]:
	return _names.duplicate()


## Build a fresh [Loadout] for the given preset name.
## Returns an empty Loadout (with a warning) if the name is unknown.
static func create_loadout(preset_name: String) -> Loadout:
	var loadout := Loadout.new()
	match preset_name:
		"Xenolith Mk.I":
			loadout.add_ability(EnvenomAbility.new("ability_1"))
			loadout.add_ability(TunnelAbility.new("ability_2"))
			loadout.add_ability(CoilAbility.new("ability_3"))
			loadout.add_ability(CloneAbility.new("ability_4"))
		"Resonance Mk.I":
			loadout.add_ability(ResonantPunchAbility.new("ability_1"))
			loadout.add_ability(KnockbackAbility.new("ability_2"))
			loadout.add_ability(BlasterAbility.new("ability_3"))
			loadout.add_ability(MortarAbility.new("ability_4"))
		_:
			push_warning("LoadoutPresets: unknown preset '%s'" % preset_name)
	return loadout
