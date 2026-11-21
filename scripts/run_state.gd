extends Node
## Red Harbor - the run (autoload "Run").
##
## Everything that has to outlive a scene change lives here: the three cases
## on the board, the case you took, the boons you picked, the intel ledger,
## the alarm ladder, the style chain - and, across launches, your favors and
## the permanent upgrades you bought with them (user://red_harbor.cfg).
##
## HADES, NOT A MENU. Every briefing deals THREE DIFFERENT cases from a pool
## of archetypes. They differ in the ways that change how a night is PLAYED:
##   * jobs     - what you steal / bug / photograph (and how long each takes)
##   * a RULE   - a district rule that bends the whole night
##                  QUIET HOURS   no rule
##                  ON AIR        dashes and takedowns are LOUD (noise_made)
##                  CURFEW        the alarm climbs by itself; intel pays x2
##                  BLACKOUT      lights out: short beams, faster patrols
##                  HIGH SECURITY +1 guard; intel pays x1.5
##                  SEALED VAULT  no lower floor; the evidence is on floor 1
##   * a REWARD - FAVORS (permanent upgrades) or an extra BOON pick
## and every night deals a different building. On top of that you pick a
## BOON before the night starts (Hades' boons): a run-long modifier that
## bends movement, jobs, noise or the alarm. Same case, different boon,
## different night.
##
## One night = one run (roadmap 4.3): OFFICE (pick case + boon) -> FLOOR 1
## -> back-door decision -> [FLOOR 2] -> DEBRIEF. Intel is only banked when
## you walk out; caught = the case goes cold, you keep an insurance share.
##
## `active` is true only while a night is being played; with it false every
## multiplier reads 1.0, so the street-probe scene (main.tscn) and its tests
## are untouched.

signal alarm_changed(tier: int)
signal ledger_changed
signal night_ended(result: Dictionary)
signal noise_made(pos: Vector2, radius: float)
signal boons_changed
signal style_changed(chain: int, style: int)
signal second_chance_used

enum Tier { GOSSIP, LEADS, EVIDENCE }
const TIER_NAMES: Array[String] = ["GOSSIP", "LEADS", "EVIDENCE"]
const TIER_POINTS: Array[int] = [1, 3, 8]

# The jobs. "time" = seconds the PI must hold E next to the prop.
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
const CURFEW_EVERY := 40.0    # seconds between the CURFEW rule's bells
const CHAIN_WINDOW := 6.0     # seconds to keep a style chain alive
const NOISE_DASH := 120.0     # px radius of a dash under ON AIR
const NOISE_TAKEDOWN := 80.0

# District rules (see the header). "mult" scales every intel point.
const RULES := {
	"quiet": {"name": "QUIET HOURS", "text": "No special rules. Just you, the building and the night.", "mult": 1.0},
	"noise": {"name": "ON AIR", "text": "Dashes and takedowns are LOUD: guards nearby come to look.", "mult": 1.0},
	"curfew": {"name": "CURFEW", "text": "The alarm climbs by itself every 40 s. Intel pays DOUBLE.", "mult": 2.0},
	"blackout": {"name": "BLACKOUT", "text": "Lights out: beams are short, but patrols run 25% faster.", "mult": 1.0},
	"heavy": {"name": "HIGH SECURITY", "text": "One more guard on every floor. Intel pays x1.5.", "mult": 1.5},
	"sealed": {"name": "SEALED VAULT", "text": "No lower floor. The evidence case is on THIS floor.", "mult": 1.0},
}
const RULE_RISK := {"quiet": 0, "noise": 0, "curfew": 1, "blackout": 1, "heavy": 1, "sealed": 0}

# The case pool. Each night's board deals three with different rules.
# tasks = floor-1 jobs, guards = patrols, evidence = lower-floor cases.
const ARCHETYPES: Array[Dictionary] = [
	{
		"id": "radio", "title": "VOICES ON THE WIRE", "district": "RADIO QUARTER", "building": "STATE RADIO HOUSE",
		"blurb": "Someone feeds the bulletin lines the censors never wrote.",
		"tasks": ["bug", "bug", "documents"], "guards": 2, "evidence": 2, "rule": "noise",
		"reward": {"kind": "favors", "amount": 4},
	},
	{
		"id": "ministry", "title": "THE MISSING CLERK", "district": "MINISTRY ROW", "building": "RAIL QUOTAS MINISTRY",
		"blurb": "A clerk who audited the quota books vanished. Her files did not.",
		"tasks": ["documents", "documents", "bug"], "guards": 3, "evidence": 2, "rule": "quiet",
		"reward": {"kind": "boon"},
	},
	{
		"id": "customs", "title": "THE RED TIDE LEDGER", "district": "HARBOR DISTRICT", "building": "CUSTOMS HOUSE",
		"blurb": "Containers that never docked. Photograph the ledger. Be quick.",
		"tasks": ["ledger", "ledger", "bug"], "guards": 3, "evidence": 3, "rule": "curfew",
		"reward": {"kind": "favors", "amount": 3},
	},
	{
		"id": "telegraph", "title": "SIGNAL FIRE", "district": "TELEGRAPH EXCHANGE", "building": "CENTRAL TELEGRAPH",
		"blurb": "The Exchange goes dark at midnight. Somebody is counting on it.",
		"tasks": ["bug", "bug", "documents", "documents"], "guards": 3, "evidence": 2, "rule": "blackout",
		"reward": {"kind": "favors", "amount": 5},
	},
	{
		"id": "archive", "title": "THE PROMOTED INFORMANT", "district": "PARTY ARCHIVE", "building": "CENTRAL ARCHIVE",
		"blurb": "Three files, one name, and a Party-grade security detail.",
		"tasks": ["documents", "documents", "documents"], "guards": 3, "evidence": 2, "rule": "heavy",
		"reward": {"kind": "favors", "amount": 4},
	},
	{
		"id": "deaddrop", "title": "THE DEAD DROP", "district": "OLD PORT", "building": "BONDED WAREHOUSE 9",
		"blurb": "One sealed case in a sealed cellar. Take it and be gone.",
		"tasks": ["evidence", "bug", "documents"], "guards": 3, "evidence": 0, "rule": "sealed",
		"reward": {"kind": "boon"},
	},
]

# Boons: run-long modifiers (Hades' boons). "mods" keys are read by
# mult("..._mult") / add("..._add") - see those helpers.
const BOONS: Array[Dictionary] = [
	{"id": "soft_soles", "tag": "STEALTH", "name": "SOFT SOLES", "text": "Sneak 35% faster. Your noise is halved.", "mods": {"sneak_mult": 1.35, "noise_mult": 0.5}},
	{"id": "adrenaline", "tag": "MOVEMENT", "name": "ADRENALINE", "text": "Dash cooldown -40%.", "mods": {"dash_cd_mult": 0.6}},
	{"id": "long_coat", "tag": "MOVEMENT", "name": "LONG COAT", "text": "Your dash goes 35% further.", "mods": {"dash_time_mult": 1.35}},
	{"id": "fast_hands", "tag": "JOBS", "name": "FAST HANDS", "text": "Jobs take 30% less time.", "mods": {"job_time_mult": 0.7}},
	{"id": "escape_artist", "tag": "MOVEMENT", "name": "ESCAPE ARTIST", "text": "Crawl through tight spots 60% faster.", "mods": {"crawl_mult": 1.6}},
	{"id": "silver_tongue", "tag": "SURVIVAL", "name": "SILVER TONGUE", "text": "Caught? You keep 50% of what you carried.", "mods": {"insurance_add": 0.3}},
	{"id": "old_friend", "tag": "COMBAT", "name": "OLD FRIEND", "text": "Takedowns reach further and work from the side.", "mods": {"takedown_range_add": 10.0, "takedown_dot_add": 0.45}},
	{"id": "greed", "tag": "INTEL", "name": "GREED", "text": "Intel pays +25%. One more guard walks the floor.", "mods": {"intel_mult": 1.25, "guards_add": 1}},
	{"id": "runners_high", "tag": "MOVEMENT", "name": "RUNNER'S HIGH", "text": "You walk 12% faster.", "mods": {"move_mult": 1.12}},
	{"id": "cold_shoulder", "tag": "STEALTH", "name": "COLD SHOULDER", "text": "Guard beams reach 20% less far.", "mods": {"guard_range_mult": 0.8}},
	{"id": "lucky_coin", "tag": "SURVIVAL", "name": "LUCKY COIN", "text": "The first time you would be caught, you slip away.", "mods": {"second_chance": 1}},
]

# The desk drawer: permanent upgrades bought with favors (Dead Cells' loop).
const SHOP: Array[Dictionary] = [
	{"id": "stride", "name": "LONG STRIDE", "text": "Dash +12% further, per level.", "max": 3, "costs": [6, 10, 15]},
	{"id": "soles", "name": "MUFFLED SOLES", "text": "Sneak +8%, noise -20%, per level.", "max": 3, "costs": [6, 10, 15]},
	{"id": "pockets", "name": "DEEP POCKETS", "text": "Insurance +10% per level.", "max": 3, "costs": [6, 10, 15]},
]

var active := false           # a night is in progress
var offers: Array[Dictionary] = []     # the board: three cases
var case: Dictionary = {}              # the case you took
var floor_no := 1             # 1 = the building, 2 = the lower floor
var unbanked: Array[int] = [0, 0, 0]   # intel carried, per tier
var boons: Array[String] = []
var alarm := 0
var alarm_peak := 0
var spots := 0
var takedowns := 0
var chain := 0
var style := 0
var carry_health := 100       # health travels down the stairs
var second_chance_ready := false
var session_banked := 0       # points banked across nights (this launch)
var nights_played := 0
var last_result := {}
var debug_seed := -1          # >= 0 pins the building deal (QA)
var favors := 0               # persistent
var meta := {"stride": 0, "soles": 0, "pockets": 0}   # persistent shop levels
var save_path := "user://red_harbor.cfg"
var _spot_cd := 0.0
var _chain_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	load_game()


func _process(delta: float) -> void:
	_spot_cd = maxf(_spot_cd - delta, 0.0)
	if _chain_t > 0.0:
		_chain_t -= delta
		if _chain_t <= 0.0 and chain != 0:
			chain = 0
			style_changed.emit(chain, style)


# --- the board -------------------------------------------------------------------

func roll_offers(rng_seed: int = -1) -> Array[Dictionary]:
	# Three DIFFERENT cases (always three different rules), each with its own
	# case number and a favors reward that varies. The building itself is
	# dealt fresh by every night (building_builder.gd).
	if rng_seed >= 0:
		_rng.seed = rng_seed
	var pool: Array = range(ARCHETYPES.size())
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	offers = []
	for k in 3:
		var a: Dictionary = ARCHETYPES[pool[k]].duplicate(true)
		a["case_no"] = "CASE %d" % _rng.randi_range(101, 399)
		if a["reward"]["kind"] == "favors":
			a["reward"]["amount"] = maxi(2, int(a["reward"]["amount"]) + _rng.randi_range(-1, 1))
		a["danger"] = danger_of(a)
		offers.append(a)
	return offers


func danger_of(c: Dictionary) -> String:
	var score: int = int(c["guards"]) + int(RULE_RISK[c["rule"]])
	if score <= 2:
		return "LOW"
	if score == 3:
		return "MEDIUM"
	return "HIGH"


func choose_case(idx: int) -> void:
	if offers.is_empty():
		roll_offers()
	case = offers[clampi(idx, 0, offers.size() - 1)]


func lead() -> Dictionary:
	# The case in play (the name the HUD and the night scene already use).
	if case.is_empty():
		if offers.is_empty():
			roll_offers()
		case = offers[0]
	return case


func rule() -> String:
	return String(lead()["rule"])


func case_potential(c: Dictionary) -> int:
	var pts := 0
	for t in c["tasks"]:
		pts += TIER_POINTS[TASKS[t]["tier"]]
	return roundi(pts * float(RULES[c["rule"]]["mult"]))


func evidence_potential(c: Dictionary) -> int:
	return roundi(int(c["evidence"]) * TIER_POINTS[Tier.EVIDENCE] * float(RULES[c["rule"]]["mult"]))


# --- boons + upgrades ---------------------------------------------------------------

func offer_boons(n: int = 3) -> Array[Dictionary]:
	var free: Array = []
	for b in BOONS:
		if not boons.has(b["id"]):
			free.append(b)
	for i in range(free.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = free[i]
		free[i] = free[j]
		free[j] = tmp
	var out: Array[Dictionary] = []
	for k in mini(n, free.size()):
		out.append(free[k])
	return out


func add_boon(id: String) -> void:
	if boons.has(id):
		return
	boons.append(id)
	if id == "lucky_coin":
		second_chance_ready = true
	boons_changed.emit()


func boon_by_id(id: String) -> Dictionary:
	for b in BOONS:
		if b["id"] == id:
			return b
	return {}


func _meta_mods() -> Dictionary:
	var s: int = int(meta["stride"])
	var o: int = int(meta["soles"])
	var p: int = int(meta["pockets"])
	return {
		"dash_time_mult": 1.0 + 0.12 * s,
		"sneak_mult": 1.0 + 0.08 * o,
		"noise_mult": 1.0 - 0.2 * o,
		"insurance_add": 0.1 * p,
	}


func mult(key: String) -> float:
	# Product of every boon / upgrade modifier called `key` (1.0 when none).
	var m := 1.0
	for id in boons:
		var mods: Dictionary = boon_by_id(id).get("mods", {})
		if mods.has(key):
			m *= float(mods[key])
	var mm := _meta_mods()
	if mm.has(key):
		m *= float(mm[key])
	return m


func add(key: String) -> float:
	# Sum of every boon / upgrade modifier called `key` (0.0 when none).
	var a := 0.0
	for id in boons:
		var mods: Dictionary = boon_by_id(id).get("mods", {})
		if mods.has(key):
			a += float(mods[key])
	var mm := _meta_mods()
	if mm.has(key):
		a += float(mm[key])
	return a


func shop_cost(id: String) -> int:
	for s in SHOP:
		if s["id"] == id:
			var lvl: int = int(meta[id])
			return int(s["costs"][lvl]) if lvl < int(s["max"]) else -1
	return -1


func buy(id: String) -> bool:
	var cost := shop_cost(id)
	if cost < 0 or favors < cost:
		return false
	favors -= cost
	meta[id] = int(meta[id]) + 1
	save_game()
	return true


func save_game() -> void:
	var cf := ConfigFile.new()
	cf.set_value("red_harbor", "favors", favors)
	for k in meta:
		cf.set_value("meta", k, meta[k])
	cf.save(save_path)


func load_game() -> void:
	var cf := ConfigFile.new()
	if cf.load(save_path) != OK:
		return
	favors = int(cf.get_value("red_harbor", "favors", 0))
	for k in meta:
		meta[k] = clampi(int(cf.get_value("meta", k, 0)), 0, 3)


# --- the night -------------------------------------------------------------------------

func begin_night(keep_boons: bool = false) -> void:
	active = true
	floor_no = 1
	unbanked = [0, 0, 0]
	if not keep_boons:
		boons = []
	alarm = 0
	alarm_peak = 0
	spots = 0
	takedowns = 0
	chain = 0
	style = 0
	_chain_t = 0.0
	carry_health = 100
	second_chance_ready = boons.has("lucky_coin")
	_spot_cd = 0.0
	last_result = {}
	ledger_changed.emit()
	alarm_changed.emit(0)
	style_changed.emit(0, 0)


func enter_lower_floor(health: int) -> void:
	floor_no = 2
	carry_health = health


func on_restart() -> void:
	# R mid-night: the night is forfeit (nothing banked, no insurance) and the
	# next deal is a fresh building on the SAME case with the SAME boons.
	if active:
		begin_night(true)


func add_intel(tier: int) -> void:
	unbanked[tier] += 1
	ledger_changed.emit()


func score_mult() -> float:
	var m := float(RULES[rule()]["mult"]) if not case.is_empty() else 1.0
	return m * mult("intel_mult")


func unbanked_points() -> int:
	var pts := 0
	for t in 3:
		pts += unbanked[t] * TIER_POINTS[t]
	return roundi(pts * score_mult())


func unbanked_count() -> int:
	return unbanked[0] + unbanked[1] + unbanked[2]


func insurance_share() -> float:
	return minf(INSURANCE + add("insurance_add"), 0.9)


func guard_bonus() -> int:
	# Guards added on top of the case's own count (HIGH SECURITY, GREED).
	return (1 if rule() == "heavy" else 0) + int(add("guards_add"))


func can_descend() -> bool:
	return rule() != "sealed" and int(lead()["evidence"]) > 0


# --- style (the Hotline Miami chain) -----------------------------------------------------

func note_style(base: int = 100) -> void:
	# A takedown or a finished job inside the 6 s window keeps the chain going;
	# every link scores base x chain. Pure arcade: it never touches intel.
	if not active:
		return
	chain = chain + 1 if _chain_t > 0.0 else 1
	_chain_t = CHAIN_WINDOW
	style += base * mini(chain, 8)
	style_changed.emit(chain, style)


# --- noise (ON AIR) ------------------------------------------------------------------------

func make_noise(pos: Vector2, radius: float) -> void:
	if active and rule() == "noise":
		noise_made.emit(pos, radius * mult("noise_mult"))


# --- the alarm ladder -----------------------------------------------------------------------

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
		note_style(150)


func consume_second_chance() -> bool:
	if not active or not second_chance_ready:
		return false
	second_chance_ready = false
	second_chance_used.emit()
	return true


func extra_guards() -> int:
	return ALARM_EXTRA_GUARDS[alarm] if active else 0


func patrol_mult() -> float:
	if not active:
		return 1.0
	return ALARM_PATROL[alarm] * (1.25 if rule() == "blackout" else 1.0)


func chase_mult() -> float:
	return ALARM_CHASE[alarm] if active else 1.0


func range_mult() -> float:
	if not active:
		return 1.0
	return ALARM_RANGE[alarm] * (0.65 if rule() == "blackout" else 1.0) * mult("guard_range_mult")


func pause_mult() -> float:
	return ALARM_PAUSE[alarm] if active else 1.0


func lockdown() -> bool:
	return active and alarm >= MAX_ALARM


# --- the end of a night -----------------------------------------------------------------------

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
		insurance = floori(carried * insurance_share())
		banked = insurance
	session_banked += banked
	if outcome == "extracted" and alarm_peak == 0:
		style += 500        # a ghost run: nobody ever saw you
	var earned := floori(banked / 3.0)
	var reward: Dictionary = lead()["reward"]
	if outcome == "extracted" and reward["kind"] == "favors":
		earned += int(reward["amount"])
	favors += earned
	save_game()
	last_result = {
		"outcome": outcome,
		"lead": lead()["id"],
		"title": lead()["title"],
		"case_no": lead()["case_no"],
		"district": lead()["district"],
		"rule": rule(),
		"tiers": unbanked.duplicate(),
		"carried": carried,
		"banked": banked,
		"insurance": insurance,
		"favors": earned,
		"style": style,
		"alarm_peak": alarm_peak,
		"spots": spots,
		"takedowns": takedowns,
		"floor": floor_no,
		"session": session_banked,
	}
	night_ended.emit(last_result)
	return last_result
