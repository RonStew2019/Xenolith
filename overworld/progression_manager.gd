extends Node
class_name ProgressionManager
## Drives the early → mid → late game progression curve.
##
## Tracks player milestones (threats defeated, mechs built, turns elapsed)
## and reconfigures [ThreatManager] when the player crosses a phase
## threshold.  Auto-discovers siblings in [method _ready].
##
## Phase transitions are checked whenever a tracked metric changes.  Each
## phase adjusts threat density, enemy carrier spawn chance, and fauna
## difficulty — keeping the experience matched to what the player can
## handle.
##
## Place this node BEFORE [ThreatManager] in the scene tree so its
## [method _ready] can configure initial-hive and spawn parameters before
## ThreatManager's deferred [method ThreatManager._spawn_initial_hives].

# -- Phase Enum ------------------------------------------------------------

## The three progression phases of the game.
enum Phase {
	## Fauna only, low threat count, scavenge resources, build first mechs.
	EARLY,
	## Weak enemy carriers start appearing, carrier expansion encouraged.
	MID,
	## Strong enemy carriers, high threat density, fully kitted hangar.
	LATE,
}

# -- Signals ---------------------------------------------------------------

## Emitted when the game transitions to a new phase.
signal phase_changed(new_phase: Phase, old_phase: Phase)

# -- Tracked Metrics -------------------------------------------------------

## Total threats the player has defeated (fauna + carriers).
var threats_defeated: int = 0

## Subset of [member threats_defeated] that were enemy carriers.
var enemy_carriers_defeated: int = 0

## Total mechs the player has fabricated.
var mechs_built: int = 0

## Turn counter — mirrors [ThreatManager]'s turn count.
var turns_elapsed: int = 0

# -- Phase Transition Thresholds -------------------------------------------

## EARLY → MID: threats defeated required.
const EARLY_TO_MID_THREATS: int = 2

## EARLY → MID: mechs built required.
const EARLY_TO_MID_MECHS: int = 1

## EARLY → MID: fallback turn count.
const EARLY_TO_MID_TURNS: int = 15

## MID → LATE: total threats defeated required.
const MID_TO_LATE_THREATS: int = 5

## MID → LATE: enemy carriers defeated required.
const MID_TO_LATE_CARRIERS: int = 1

## MID → LATE: fallback turn count.
const MID_TO_LATE_TURNS: int = 40

# -- Phase Names (for logging) ---------------------------------------------

## Human-readable phase names keyed by enum value.
const PHASE_NAMES: Dictionary = {
	Phase.EARLY: "EARLY",
	Phase.MID: "MID",
	Phase.LATE: "LATE",
}

# -- State -----------------------------------------------------------------

## Current progression phase.
var _current_phase: Phase = Phase.EARLY

## Reference to [ThreatManager] (auto-discovered sibling).
var _threat_manager: ThreatManager = null

## Reference to [Carrier] (auto-discovered sibling).
var _carrier: Carrier = null

## Reference to [EngagementManager] (auto-discovered sibling).
var _engagement_manager: EngagementManager = null

# -- Lifecycle -------------------------------------------------------------

func _ready() -> void:
	if get_parent() == null:
		push_warning("[ProgressionManager] No parent — disabled")
		return

	_threat_manager = get_parent().get_node_or_null(
		"ThreatManager"
	) as ThreatManager
	_carrier = get_parent().get_node_or_null("Carrier") as Carrier
	_engagement_manager = get_parent().get_node_or_null(
		"EngagementManager"
	) as EngagementManager

	if _threat_manager == null:
		push_warning("[ProgressionManager] No ThreatManager sibling — disabled")
		return

	# Apply EARLY-phase config before ThreatManager spawns initial hives
	# (ThreatManager defers hive spawn to after the first process frame).
	_apply_phase_config(Phase.EARLY)

	# Listen to threat turns for the elapsed-turn fallback.
	_threat_manager.turn_processed.connect(_on_turn_processed)

	# Listen to engagement outcomes for kill tracking.
	if _engagement_manager != null:
		_engagement_manager.engagement_resolved.connect(
			_on_engagement_resolved
		)
	else:
		push_warning("[ProgressionManager] No EngagementManager — kill tracking disabled")

	# Listen to mech fabrication for build tracking.
	if _carrier != null:
		var build_queue: BuildQueue = _carrier.get_build_queue()
		if build_queue != null:
			build_queue.build_completed.connect(_on_mech_built)
		else:
			push_warning("[ProgressionManager] No BuildQueue on Carrier — build tracking disabled")
	else:
		push_warning("[ProgressionManager] No Carrier sibling — build tracking disabled")

	print("[ProgressionManager] Ready — starting in %s phase" % PHASE_NAMES[_current_phase])


# -- Public API ------------------------------------------------------------

## Return the current progression phase.
func get_phase() -> Phase:
	return _current_phase


## Return a human-readable name for the current phase.
func get_phase_name() -> String:
	return PHASE_NAMES.get(_current_phase, "UNKNOWN") as String


# -- Signal Handlers -------------------------------------------------------

## Track threat turns and check for time-based phase transitions.
func _on_turn_processed(turn_number: int) -> void:
	turns_elapsed = turn_number
	_check_phase_transition()


## Track engagement victories and the type of threat defeated.
func _on_engagement_resolved(result: Dictionary) -> void:
	var victory: bool = result.get("victory", false)
	if not victory:
		return

	threats_defeated += 1
	var threat_type: StringName = result.get("threat_type", &"")
	if threat_type == &"enemy_carrier":
		enemy_carriers_defeated += 1

	print("[ProgressionManager] Victory! Threats defeated: %d (carriers: %d)" % [
		threats_defeated, enemy_carriers_defeated,
	])
	_check_phase_transition()


## Track mech fabrication completions.
func _on_mech_built(_blueprint: MechBlueprint) -> void:
	mechs_built += 1
	print("[ProgressionManager] Mech built! Total: %d" % mechs_built)
	_check_phase_transition()


# -- Phase Transition Logic ------------------------------------------------

## Evaluate whether the player has met the criteria for the next phase.
##
## Transitions are one-way: EARLY → MID → LATE.  Each phase has a
## milestone-based trigger AND a turn-based fallback so the player is
## never stuck forever.
func _check_phase_transition() -> void:
	var new_phase: Phase = _current_phase

	match _current_phase:
		Phase.EARLY:
			var milestones_met: bool = (
				threats_defeated >= EARLY_TO_MID_THREATS
				and mechs_built >= EARLY_TO_MID_MECHS
			)
			if milestones_met or turns_elapsed >= EARLY_TO_MID_TURNS:
				new_phase = Phase.MID

		Phase.MID:
			var milestones_met: bool = (
				threats_defeated >= MID_TO_LATE_THREATS
				and enemy_carriers_defeated >= MID_TO_LATE_CARRIERS
			)
			if milestones_met or turns_elapsed >= MID_TO_LATE_TURNS:
				new_phase = Phase.LATE

		Phase.LATE:
			pass  # Terminal phase — nowhere to go.

	if new_phase != _current_phase:
		_transition_to(new_phase)


## Execute a phase transition: update state, reconfigure ThreatManager,
## and emit [signal phase_changed].
func _transition_to(new_phase: Phase) -> void:
	var old_phase: Phase = _current_phase
	_current_phase = new_phase
	_apply_phase_config(new_phase)
	phase_changed.emit(new_phase, old_phase)
	print("[ProgressionManager] Phase changed: %s → %s" % [
		PHASE_NAMES[old_phase], PHASE_NAMES[new_phase],
	])


# -- ThreatManager Configuration -------------------------------------------

## Push phase-appropriate parameters into [ThreatManager].
##
## This is called once on startup (EARLY) and again on each transition.
## All values match the design table in the progression spec.
func _apply_phase_config(phase: Phase) -> void:
	if _threat_manager == null:
		return

	match phase:
		Phase.EARLY:
			_threat_manager.max_threats = 4
			_threat_manager.spawn_interval_turns = 6
			_threat_manager.initial_hive_count = 2
			_threat_manager.enemy_carrier_chance = 0.0
			# No carriers in early game — ranges don't matter but set sane defaults.
			_threat_manager.carrier_strength_min = 1.0
			_threat_manager.carrier_strength_max = 1.0
			_threat_manager.fauna_threat_level_min = 0.5
			_threat_manager.fauna_threat_level_max = 1.5
			_threat_manager.fauna_swarm_strength_min = 0.5
			_threat_manager.fauna_swarm_strength_max = 1.0

		Phase.MID:
			_threat_manager.max_threats = 6
			_threat_manager.spawn_interval_turns = 5
			_threat_manager.enemy_carrier_chance = 0.4
			_threat_manager.carrier_strength_min = 1.0
			_threat_manager.carrier_strength_max = 3.0
			_threat_manager.fauna_threat_level_min = 1.0
			_threat_manager.fauna_threat_level_max = 2.0
			_threat_manager.fauna_swarm_strength_min = 1.0
			_threat_manager.fauna_swarm_strength_max = 1.5

		Phase.LATE:
			_threat_manager.max_threats = 8
			_threat_manager.spawn_interval_turns = 4
			_threat_manager.enemy_carrier_chance = 0.7
			_threat_manager.carrier_strength_min = 4.0
			_threat_manager.carrier_strength_max = 10.0
			_threat_manager.fauna_threat_level_min = 1.5
			_threat_manager.fauna_threat_level_max = 3.0
			_threat_manager.fauna_swarm_strength_min = 1.0
			_threat_manager.fauna_swarm_strength_max = 2.0

	print("[ProgressionManager] Applied %s config to ThreatManager" % PHASE_NAMES[phase])
