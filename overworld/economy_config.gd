class_name EconomyConfig
## Centralized economy balance constants.
## One place to tweak all resource costs, harvest rates, and deploy costs.
##
## This is a static-method-only class — never instantiated.

# -- Deployment Fuel Costs (per chassis) -----------------------------------

const DOGFIGHTER_DEPLOY_FUEL: int = 5
const BOMBER_DEPLOY_FUEL: int = 8

# -- Module Resource Costs -------------------------------------------------
# Each returns a Dictionary of {&"metal": N, &"crystal": N}.

static func reactor_module_cost() -> Dictionary:
	return {&"metal": 1000, &"crystal": 500}

static func fabricator_module_cost() -> Dictionary:
	return {&"metal": 25, &"crystal": 15}

static func hangar_module_cost() -> Dictionary:
	return {&"metal": 20, &"crystal": 10}

static func harvester_module_cost() -> Dictionary:
	return {&"metal": 15, &"crystal": 5}

static func defense_module_cost() -> Dictionary:
	return {&"metal": 30, &"crystal": 20}

static func engine_module_cost() -> Dictionary:
	return {&"metal": 20, &"crystal": 10}

# -- Weapon Costs (added on top of chassis cost) ---------------------------
# Returns a Dictionary of {resource_type: amount} for the given weapon_id.

static func get_weapon_cost(weapon_id: StringName) -> Dictionary:
	match weapon_id:
		&"punch_amplifier": return {&"metal": 5}
		&"thermal_fist": return {&"metal": 8, &"crystal": 5}
		&"heat_cannon": return {&"metal": 10, &"crystal": 8}
		&"blaster": return {&"metal": 8, &"crystal": 3}
		&"scatter_blaster": return {&"metal": 10, &"crystal": 5}
		&"mortar": return {&"metal": 15, &"crystal": 10}
		&"artillery_mortar": return {&"metal": 20, &"crystal": 15}
		&"venom_fist": return {&"metal": 10, &"crystal": 10}
		&"cryo_cannon": return {&"metal": 12, &"crystal": 12}
		&"emp_mortar": return {&"metal": 18, &"crystal": 15}
		_: return {}

# -- Harvest Rate Multipliers by Phase -------------------------------------

const HARVEST_MULTIPLIER_EARLY: float = 1.0
const HARVEST_MULTIPLIER_MID: float = 1.25
const HARVEST_MULTIPLIER_LATE: float = 1.5
