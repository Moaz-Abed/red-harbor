extends Node
## Red Harbor - the run (autoload "Run").
##
## Everything that has to outlive a scene change lives here: the lead you
## picked in the office, the intel ledger, the alarm ladder, the banked
## score. One night is  OFFICE (briefing)  ->  FLOOR 1  ->  back-door
## decision  ->  [FLOOR 2]  ->  DEBRIEF  ->  OFFICE   (roadmap 4.2 / 4.3).
##
## Intel is the only resource and comes in three tiers worth escalating
## points: GOSSIP 1, LEADS 3, EVIDENCE 8. Intel stays UNBANKED until you
## walk out of the back door. If you are caught the case goes cold: you keep
## only a small insurance share (INSURANCE) of what you were carrying.
##
## The alarm ladder is tier by tier (roadmap: "more guards, faster patrols,
## lockdown"):
##   0 CALM       nothing changes
##   1 ALERTED    +1 guard arrives at the last known position
##   2 HUNT       patrols 30% faster, wider flashlight reach, shorter pauses
##   3 LOCKDOWN   +1 more guard, patrols 50% faster, hunters 20% faster, and
##                the back door's lower floor is SEALED
## Every NEW spotting raises the ladder one tier (a 4 s cooldown stops one
## long chase from counting three times). It never falls during a night.
##
## `active` is only true while a night is being played; with it false every
## multiplier reads 1.0, so the old street-block probe scene (main.tscn)
## and its tests are untouched by the ladder.

signal alarm_changed(tier: int)
signal ledger_changed
signal night_ended(result: Dictionary)

enum Tier { GOSSIP, LEADS, EVIDENCE }
const TIER_NAMES: Array[String] = ["GOSSIP", "LEADS", "EVIDENCE"]
const TIER_POINTS: Array[int] = [1, 3, 8]

# The three jobs of the roadmap, plus the lower-floor evidence grab.
# "time" = seconds the PI must hold E next to the prop.
const TASKS := {
	"bug": {"label": "BUG THE PHONE", "done": "PHONE BUGGED", "tier": Tier.GOSSIP, "time": 1.2},
	"documents": {"label": "STEAL DOCUMENTS", "done": "DOCUMENTS STOLEN", "tier": Tier.LEADS, "time": 2.0},
	"ledger": {"label": "PHOTOGRAPH THE LEDGER", "done": "LEDGER PHOTOGRAPHED", "tier": Tier.LEADS, "time": 2.6},
	"evidence": {"label": "SECURE EVIDENCE", "done": "EVIDENCE SECURED", "tier": Tier.EVIDENCE, "time": 3.0},
}

const ALARM_NAMES: Array[String] = ["CALM", "ALERTED", "HUNT", "LOCKDOWN"]
const MAX_ALARM := 3
const ALARM_EXTRA_GUARDS: Array[int] = [0, 1, 1, 2]
const ALARM_PATROL: Array[float] = [1.0, 1.0, 1.3, 1.5]
const ALARM_CHASE: Array[float] = [1.0, 1.0, 1.1, 1.2]
const ALARM_RANGE: Array[float] = [1.0, 1.0, 1.15, 1.3]
const ALARM_PAUSE: Array[float] = [1.0, 1.0, 0.55, 0.4]
const SPOT_COOLDOWN := 4.0
const INSURANCE := 0.2        # share of unbanked points kept when caught

# Three leads, each tied to a district and a case file (roadmap 4.2).
# tasks   = the jobs dealt onto floor 1
# guards  = patrols on floor 1 (the lower floor adds one)
# evidence = evidence cases waiting on the lower floor
const LEADS: Array[Dictionary] = [
	{
		"id": "radio", "case_no": "CASE 311", "title": "VOICES ON THE WIRE",
		"district": "RADIO QUARTER", "building": "STATE RADIO HOUSE",
		"blurb": "Someone is feeding the evening bulletin lines the censors never wrote. The proof is on the wire.",
		"tasks": ["bug", "bug", "documents"], "guards": 2, "evidence": 2, "danger": "LOW",
	},
	{
		"id": "ministry", "case_no": "CASE 114", "title": "THE MISSING CLERK",
		"district": "MINISTRY ROW", "building": "RAIL QUOTAS MINISTRY",
		"blurb": "A clerk who audited the quota books vanished on Tuesday. Her files are still in the building.",
		"tasks": ["documents", "documents", "bug"], "guards": 3, "evidence": 2, "danger": "MEDIUM",
	},
	{
		"id": "customs", "case_no": "CASE 207", "title": "THE RED TIDE LEDGER",
		"district": "HARBOR DISTRICT", "building": "CUSTOMS HOUSE",
		"blurb": "Containers that never docked, signed for by men who do not exist. Photograph the ledger.",
		"tasks": ["ledger", "ledger", "bug"], "guards": 4, "evidence": 3, "danger": "HIGH",
	},
]

var active := false           # a night is in progress
var lead_idx := 1
var floor_no := 1             # 1 = the building, 2 = the lower floor
var unbanked: Array[int] = [0, 0, 0]   # intel carried, per tier
var alarm := 0
var alarm_peak := 0
var spots := 0
var takedowns := 0
var carry_health := 100       # health travels down the stairs
var session_banked := 0       # points banked across nights (this launch)
var nights_played := 0
var last_result := {}
var debug_seed := -1          # >= 0 pins the building deal (QA)
var _spot_cd := 0.0


func _process(delta: float) -> void:
	_spot_cd = maxf(_spot_cd - delta, 0.0)


# --- leads ---------------------------------------------------------------------

func lead() -> Dictionary:
	return LEADS[clampi(lead_idx, 0, LEADS.size() - 1)]


func choose_lead(idx: int) -> void:
	lead_idx = clampi(idx, 0, LEADS.size() - 1)


func lead_potential(idx: int) -> int:
	# Points on floor 1 for a lead (the lower floor is the bonus gamble).
	var pts := 0
	for t in LEADS[idx]["tasks"]:
		pts += TIER_POINTS[TASKS[t]["tier"]]
	return pts


func evidence_potential(idx: int) -> int:
	return int(LEADS[idx]["evidence"]) * TIER_POINTS[Tier.EVIDENCE]


# --- the night -------------------------------------------------------------------

func begin_night() -> void:
	active = true
	floor_no = 1
	unbanked = [0, 0, 0]
	alarm = 0
	alarm_peak = 0
	spots = 0
	takedowns = 0
	carry_health = 100
	_spot_cd = 0.0
	last_result = {}
	ledger_changed.emit()
	alarm_changed.emit(0)


func enter_lower_floor(health: int) -> void:
	floor_no = 2
	carry_health = health


func on_restart() -> void:
	# R mid-night: the night is forfeit (nothing banked, no insurance), the
	# next deal is a fresh night on the same lead.
	if active:
		begin_night()


func add_intel(tier: int) -> void:
	unbanked[tier] += 1
	ledger_changed.emit()


func unbanked_points() -> int:
	var pts := 0
	for t in 3:
		pts += unbanked[t] * TIER_POINTS[t]
	return pts


func unbanked_count() -> int:
	return unbanked[0] + unbanked[1] + unbanked[2]


# --- the alarm ladder -----------------------------------------------------------

func register_spot() -> bool:
	# A guard just spotted the PI. Returns true when the ladder climbed.
	if not active:
		return false
	spots += 1
	if _spot_cd > 0.0:
		return false
	_spot_cd = SPOT_COOLDOWN
	return raise_alarm()


func raise_alarm() -> bool:
	if not active or alarm >= MAX_ALARM:
		return false
	alarm += 1
	alarm_peak = maxi(alarm_peak, alarm)
	alarm_changed.emit(alarm)
	return true


func note_takedown() -> void:
	if active:
		takedowns += 1


func extra_guards() -> int:
	return ALARM_EXTRA_GUARDS[alarm] if active else 0


func patrol_mult() -> float:
	return ALARM_PATROL[alarm] if active else 1.0


func chase_mult() -> float:
	return ALARM_CHASE[alarm] if active else 1.0


func range_mult() -> float:
	return ALARM_RANGE[alarm] if active else 1.0


func pause_mult() -> float:
	return ALARM_PAUSE[alarm] if active else 1.0


func lockdown() -> bool:
	return active and alarm >= MAX_ALARM


# --- the end of a night ---------------------------------------------------------

func finish(outcome: String) -> Dictionary:
	# outcome: "extracted" banks everything; "caught" keeps the insurance share.
	if not active:
		return last_result
	active = false
	nights_played += 1
	var carried := unbanked_points()
	var banked := carried
	var insurance := 0
	if outcome != "extracted":
		insurance = floori(carried * INSURANCE)
		banked = insurance
	session_banked += banked
	last_result = {
		"outcome": outcome,
		"lead": lead()["id"],
		"title": lead()["title"],
		"case_no": lead()["case_no"],
		"district": lead()["district"],
		"tiers": unbanked.duplicate(),
		"carried": carried,
		"banked": banked,
		"insurance": insurance,
		"alarm_peak": alarm_peak,
		"spots": spots,
		"takedowns": takedowns,
		"floor": floor_no,
		"session": session_banked,
	}
	night_ended.emit(last_result)
	return last_result
