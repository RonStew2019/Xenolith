class_name ChassisPresets
## Static factory for pre-configured [MechChassis] and [MechBlueprint]
## instances.
##
## Centralises the balance numbers so there's one place to tweak stats.
## Call [code]ChassisPresets.dogfighter_chassis()[/code] etc. to get a
## fresh instance each time.

# -- Chassis Factories -----------------------------------------------------

## Fast, nimble, 4 weapon slots.  Cheaper and quicker to fabricate.
static func dogfighter_chassis() -> MechChassis:
	var c := MechChassis.new()
	c.chassis_name = &"Dogfighter"
	c.description = "Light frame built for speed and aggression. Four weapon hardpoints for close-range dominance."
	c.weapon_slots = [&"l_hand", &"r_hand", &"l_shoulder", &"r_shoulder"] as Array[StringName]
	c.base_speed = 10.0
	c.base_max_heat = 80.0
	c.base_integrity = 80.0
	c.resource_costs = {&"metal": 30, &"crystal": 10}
	c.build_time = 15.0
	return c


## Slow, tanky, 3 weapon slots (including artillery).  Expensive, long build.
static func bomber_chassis() -> MechChassis:
	var c := MechChassis.new()
	c.chassis_name = &"Bomber"
	c.description = "Heavy chassis with reinforced plating and an artillery mount. Slow but devastating at range."
	c.weapon_slots = [&"l_hand", &"r_hand", &"artillery"] as Array[StringName]
	c.base_speed = 5.0
	c.base_max_heat = 120.0
	c.base_integrity = 150.0
	c.resource_costs = {&"metal": 60, &"crystal": 30}
	c.build_time = 30.0
	return c

# -- Blueprint Factories ---------------------------------------------------

## A bare-bones dogfighter — punch amplifiers on both hands.
static func basic_dogfighter_blueprint() -> MechBlueprint:
	var bp := MechBlueprint.new()
	bp.blueprint_name = &"Basic Dogfighter"
	bp.chassis = dogfighter_chassis()
	bp.weapon_assignments = {
		&"l_hand": &"punch_amplifier",
		&"r_hand": &"punch_amplifier",
		&"l_shoulder": &"scatter_blaster",
		&"r_shoulder": &"scatter_blaster",
	}
	return bp


## A bare-bones bomber — punch amplifiers on hands, artillery mortar.
static func basic_bomber_blueprint() -> MechBlueprint:
	var bp := MechBlueprint.new()
	bp.blueprint_name = &"Basic Bomber"
	bp.chassis = bomber_chassis()
	bp.weapon_assignments = {
		&"l_hand": &"punch_amplifier",
		&"r_hand": &"punch_amplifier",
		&"artillery": &"artillery_mortar",
	}
	return bp
