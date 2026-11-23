extends Node
## The run (autoload "Run"): the dealt case, your boons and, across launches,
## favors + permanent upgrades (user://red_harbor.cfg). One dealt case = one run.
##
## The board shuffles through ALL archetypes before repeating (a bag deal), and
## every archetype has a district RULE that changes how the night plays:
##   QUIET HOURS   clean job, no twists
##   ON AIR        every move is loud; guards hear you at range
##   CURFEW        a bell climbs the alarm every 40 s; intel pays double
##   BLACKOUT      short beams, fast patrols
##   HIGH SECURITY +1 guard, intel x1.5
##   SEALED VAULT  evidence is on the main floor, no basement
## Replayability comes from the combination of archetype + rule + chosen boon.

signal boons_changed
signal case_dealt
signal favor_changed(total: int)

enum Tier { GOSSIP, LEADS, EVIDENCE }
const TIER_POINTS: Array[int] = [1, 3, 8]

const TASKS := {
                "bug":       {"label": "BUG THE PHONE",         "tier": Tier.GOSSIP},
                "documents": {"label": "STEAL DOCUMENTS",        "tier": Tier.LEADS},
                "ledger":    {"label": "PHOTOGRAPH THE LEDGER",  "tier": Tier.LEADS},
                "evidence":  {"label": "SECURE EVIDENCE",        "tier": Tier.EVIDENCE},
}

# District rules: every archetype is paired with one.
const RULES := {
                "quiet":    {"name": "QUIET HOURS",    "text": "No conditions on the file. A clean job, on paper.",         "mult": 1.0},
                "noise":    {"name": "ON AIR",         "text": "The block is wired. Every step gets an ear.",               "mult": 1.0},
                "curfew":   {"name": "CURFEW",         "text": "A bell rings after dark. The alarm climbs with each toll.  Intel pays double.", "mult": 2.0},
                "blackout": {"name": "BLACKOUT",       "text": "The block runs dark. Short beams; fast patrols.",           "mult": 1.0},
                "heavy":    {"name": "HIGH SECURITY",  "text": "A Party-grade detail walks the block. Intel pays x1.5.",   "mult": 1.5},
                "sealed":   {"name": "SEALED VAULT",   "text": "One room holds everything. No basement, no second chances.","mult": 1.0},
}
const RULE_RISK := {"quiet": 0, "noise": 0, "curfew": 1, "blackout": 1, "heavy": 1, "sealed": 0}

# Ten case archetypes. The bag shuffles all ten before repeating.
# Each has a unique title, blurb, job set, guard count, evidence count,
# rule and reward — so no two consecutive nights ever feel the same.
const ARCHETYPES: Array[Dictionary] = [
                {
                                "id": "radio", "title": "VOICES ON THE WIRE",
                                "district": "RADIO QUARTER", "building": "STATE RADIO HOUSE",
                                "blurb": "Someone feeds the bulletin lines the censors never wrote. \nOne transmitter. One night.",
                                "tasks": ["bug", "bug", "documents"], "guards": 2, "evidence": 2, "rule": "noise",
                                "reward": {"kind": "favors", "amount": 4},
                },
                {
                                "id": "ministry", "title": "THE MISSING CLERK",
                                "district": "MINISTRY ROW", "building": "RAIL QUOTAS MINISTRY",
                                "blurb": "A clerk who audited the quota books vanished Tuesday.\nHer files did not.",
                                "tasks": ["documents", "documents", "bug"], "guards": 3, "evidence": 2, "rule": "quiet",
                                "reward": {"kind": "boon"},
                },
                {
                                "id": "customs", "title": "THE RED TIDE LEDGER",
                                "district": "HARBOR DISTRICT", "building": "CUSTOMS HOUSE",
                                "blurb": "Containers that never docked. Signed by men who do not exist.\nBe quick.",
                                "tasks": ["ledger", "ledger", "bug"], "guards": 3, "evidence": 3, "rule": "curfew",
                                "reward": {"kind": "favors", "amount": 3},
                },
                {
                                "id": "telegraph", "title": "SIGNAL FIRE",
                                "district": "TELEGRAPH EXCHANGE", "building": "CENTRAL TELEGRAPH",
                                "blurb": "The Exchange goes dark at midnight for maintenance.\nSomebody is counting on that.",
                                "tasks": ["bug", "bug", "documents", "documents"], "guards": 3, "evidence": 2, "rule": "blackout",
                                "reward": {"kind": "favors", "amount": 5},
                },
                {
                                "id": "archive", "title": "THE PROMOTED INFORMANT",
                                "district": "PARTY ARCHIVE", "building": "CENTRAL ARCHIVE",
                                "blurb": "Three files. One name. A security detail only the Party awards its own.",
                                "tasks": ["documents", "documents", "documents"], "guards": 3, "evidence": 2, "rule": "heavy",
                                "reward": {"kind": "favors", "amount": 4},
                },
                {
                                "id": "deaddrop", "title": "THE DEAD DROP",
                                "district": "OLD PORT", "building": "BONDED WAREHOUSE 9",
                                "blurb": "One sealed case in a sealed cellar. \nTake it and be gone before the morning shift.",
                                "tasks": ["evidence", "bug", "documents"], "guards": 3, "evidence": 0, "rule": "sealed",
                                "reward": {"kind": "boon"},
                },
                {
                                "id": "clinic", "title": "THE DOCTOR'S DEBT",
                                "district": "WORKERS MEDICAL DISTRICT", "building": "CLINIC 14",
                                "blurb": "The clinic writes cause-of-death for whoever pays.\nThe ledger is in the director's office.",
                                "tasks": ["ledger", "documents", "bug"], "guards": 2, "evidence": 2, "rule": "quiet",
                                "reward": {"kind": "favors", "amount": 3},
                },
                {
                                "id": "newspaper", "title": "THE MORNING EDITION",
                                "district": "PRESS BUREAU", "building": "STATE PUBLISHING HOUSE",
                                "blurb": "Every edition is approved before dawn. \nThe uncensored draft exists for forty minutes.",
                                "tasks": ["bug", "documents", "ledger"], "guards": 2, "evidence": 1, "rule": "noise",
                                "reward": {"kind": "boon"},
                },
                {
                                "id": "embassy", "title": "THE QUIET ATTACHÉ",
                                "district": "DIPLOMATIC QUARTER", "building": "CONSULATE ANNEX B",
                                "blurb": "He carries nothing through customs. He carries everything through the annexe.\nBug the room.",
                                "tasks": ["bug", "bug", "bug", "documents"], "guards": 4, "evidence": 2, "rule": "heavy",
                                "reward": {"kind": "favors", "amount": 6},
                },
                {
                                "id": "crematorium", "title": "ASHES TO ASHES",
                                "district": "OLD EASTERN DISTRICT", "building": "MUNICIPAL CREMATORIUM",
                                "blurb": "Some of the residents have paperwork that should not exist.\nNeither should the people it names.",
                                "tasks": ["documents", "evidence", "bug"], "guards": 3, "evidence": 2, "rule": "curfew",
                                "reward": {"kind": "favors", "amount": 4},
                },
]

# Eleven boons: picked at the radio before each run.
const BOONS: Array[Dictionary] = [
                {"id": "soft_soles",    "tag": "STEALTH",   "name": "SOFT SOLES",     "text": "Sneak 35% faster. Your noise radius is halved.",     "mods": {"sneak_mult": 1.35, "noise_mult": 0.5}},
                {"id": "adrenaline",    "tag": "MOVEMENT",  "name": "ADRENALINE",     "text": "Dash cooldown drops 40%.",                           "mods": {"dash_cd_mult": 0.6}},
                {"id": "long_coat",     "tag": "MOVEMENT",  "name": "LONG COAT",      "text": "Your dash covers 35% more ground.",                  "mods": {"dash_time_mult": 1.35}},
                {"id": "fast_hands",    "tag": "JOBS",      "name": "FAST HANDS",     "text": "Every job takes 30% less time to complete.",         "mods": {"job_time_mult": 0.7}},
                {"id": "escape_artist", "tag": "MOVEMENT",  "name": "ESCAPE ARTIST",  "text": "Crawl through tight gaps 60% faster.",               "mods": {"crawl_mult": 1.6}},
                {"id": "silver_tongue", "tag": "SURVIVAL",  "name": "SILVER TONGUE",  "text": "Caught? Keep 50% of what you were carrying.",        "mods": {"insurance_add": 0.3}},
                {"id": "old_friend",    "tag": "COMBAT",    "name": "OLD FRIEND",     "text": "Takedowns reach further and work from the side.",     "mods": {"takedown_range_add": 10.0, "takedown_dot_add": 0.45}},
                {"id": "greed",         "tag": "INTEL",     "name": "GREED",          "text": "Intel pays +25%.\nOne more guard walks the floor.",   "mods": {"intel_mult": 1.25, "guards_add": 1}},
                {"id": "runners_high",  "tag": "MOVEMENT",  "name": "RUNNER'S HIGH",  "text": "You move 12% faster on your feet.",                  "mods": {"move_mult": 1.12}},
                {"id": "cold_shoulder", "tag": "STEALTH",   "name": "COLD SHOULDER",  "text": "Guard vision cones reach 20% less far.",             "mods": {"guard_range_mult": 0.8}},
                {"id": "lucky_coin",    "tag": "SURVIVAL",  "name": "LUCKY COIN",     "text": "The first capture this run, you walk.",              "mods": {"second_chance": 1}},
                {"id": "night_owl",     "tag": "INTEL",     "name": "NIGHT OWL",      "text": "CURFEW and BLACKOUT cases pay an extra favor on extraction.", "mods": {"dark_rule_favor": 2}},
                {"id": "press_badge",   "tag": "STEALTH",   "name": "PRESS BADGE",    "text": "You are not caught on a first spotting — just questioned. The second sighting alarms.", "mods": {"first_spot_free": 1}},
]

# The desk drawer: three permanent upgrades that persist across launches.
const SHOP: Array[Dictionary] = [
                {"id": "stride",  "name": "LONG STRIDE",    "text": "Dash +12% further, per level.",                 "max": 3, "costs": [6, 10, 15]},
                {"id": "soles",   "name": "MUFFLED SOLES",  "text": "Sneak +8%, noise -20%, per level.",             "max": 3, "costs": [6, 10, 15]},
                {"id": "pockets", "name": "DEEP POCKETS",   "text": "Insurance +10% of what you carried, per level.","max": 3, "costs": [6, 10, 15]},
]

# --- headline lines per case: shown on the newspaper and in the HUD ticker ---
const CASE_HEADLINES := {
                "radio":       ["SCHEDULES DISRUPTED BY SIGNAL FAULTS", "BUREAU CITES MAINTENANCE", "EVENING PROGRAMME DELAYED"],
                "ministry":    ["RAIL QUOTAS REVISED UPWARD FOR Q4",    "MISSING: NO COMMENT FROM MINISTRY", "RECORD EFFICIENCY PRAISED"],
                "customs":     ["PORT VOLUMES AT DECADE HIGH",          "INSPECTION UNIT RESTRUCTURED", "HARBOR LANE CLOSED FOR WORKS"],
                "telegraph":   ["EXCHANGE UNDERGOES PLANNED UPGRADE",   "COMMUNICATIONS MODERNISATION CONTINUES", "MIDNIGHT WINDOW ANNOUNCED"],
                "archive":     ["ARCHIVE RESTRICTS PUBLIC ACCESS",      "NEW SECURITY MEASURES PRAISED", "HONORARY APPOINTMENTS MADE"],
                "deaddrop":    ["WAREHOUSE FIRE RULED ACCIDENTAL",      "PORT AUTHORITY DENIES IRREGULARITIES", "CARGO DELAYS CONTINUE"],
                "clinic":      ["CLINIC 14 WINS MODEL WORKPLACE AWARD", "DOCTOR CITED FOR EXCELLENCE", "HEALTH BUREAU EXPANDS SERVICES"],
                "newspaper":   ["STATE PRESS CELEBRATES ANNIVERSARY",   "DISTRIBUTION AHEAD OF SCHEDULE", "PRINT QUOTA EXCEEDED AGAIN"],
                "embassy":     ["DIPLOMATIC TIES STRENGTHENED",         "JOINT DELEGATION WELCOMED", "ATTACHÉ PROGRAMME EXTENDED"],
                "crematorium": ["EASTERN DISTRICT RENEWAL PLAN PASSED", "OLD BUILDINGS TO MAKE WAY", "COMMUNITY CONSULTATION COMPLETE"],
}

# --- ambient phone lines spoken by the caller when the PI answers ---
const PHONE_LINES := [
                ["Wrong number. Don't call back.", ""],
                ["It's me. The place is watched. Don't go in before midnight.", "INTEL: delay gives you an extra minute before first patrol"],
                ["He moved the files. Third drawer. Left side.", "INTEL: documents are in a different room today"],
                ["They know someone's been asking. Be careful.", "WARNING: alarm tier starts at ALERTED tonight"],
                ["Your tab at Vasily's. Paid. Consider it a gift.", "REWARD: +2 FAVORS, no strings"],
                ["I can't talk. Don't trust the contact.", ""],
                ["The guard on the east wing called in sick. Somebody else is covering.", "INTEL: guard route shifted — east wing lighter"],
                ["Package is ready. Leave it where we agreed.", ""],
                ["Do you know what time it is?", ""],
                ["The case you're looking at — it goes higher than you think.", ""],
]

var case := {}                   # the dealt case (read by the office)
var need_new_case := true        # the office calls deal_case() when this is true
var boons: Array[String] = []    # ids of boons carried into the next run
var boon_picks_left := 0         # radio picks remaining for this case's prep
var favors := 0
var meta := {"stride": 0, "soles": 0, "pockets": 0}
var nights_played := 0           # total cases taken (shown in debrief)
var last_extraction := ""        # "extracted" | "caught" | "" - for the opening line
var last_favors_earned := 0

# --- bag shuffle: all archetypes before any repeat -------------------------------
var _bag: Array[int] = []        # indices into ARCHETYPES
var _rng := RandomNumberGenerator.new()
var save_path := "user://red_harbor.cfg"   # the smoke harness redirects this


func _ready() -> void:
                _rng.randomize()
                _load_save()


# --- case dealing ----------------------------------------------------------------

func deal_case(rng_seed: int = -1) -> Dictionary:
                # The bag guarantee: you will not see the same archetype twice until all ten
                # have come up. This means every streak of ten cases covers the full range.
                if rng_seed >= 0:
                                _rng.seed = rng_seed
                if _bag.is_empty():
                                _bag.assign(range(ARCHETYPES.size()))
                                for i in range(_bag.size() - 1, 0, -1):
                                                var j := _rng.randi_range(0, i)
                                                var tmp: int = _bag[i]; _bag[i] = _bag[j]; _bag[j] = tmp
                var idx: int = _bag.pop_back()
                case = ARCHETYPES[idx].duplicate(true)
                case["case_no"] = "CASE %d" % _rng.randi_range(100, 399)
                case["danger"] = _danger(case)
                boons = []
                boon_picks_left = boon_picks()
                need_new_case = false
                nights_played += 1
                case_dealt.emit()
                return case


func ensure_case() -> void:
                if need_new_case or case.is_empty():
                                deal_case()


func _danger(c: Dictionary) -> String:
                var score: int = int(c["guards"]) + int(RULE_RISK.get(c["rule"], 0))
                if score <= 2: return "LOW"
                if score == 3: return "MEDIUM"
                return "HIGH"


func rule() -> String:
                return String(case.get("rule", "quiet"))


func case_potential(c: Dictionary) -> int:
                # the lead value a clean job would pay out
                var pts := 0
                for t in c["tasks"]:
                        pts += TIER_POINTS[TASKS[t]["tier"]]
                return roundi(pts * float(RULES[c["rule"]]["mult"]))


func headline() -> String:
                # a randomly-picked headline for the case's newspaper / ticker
                var lines: Array = CASE_HEADLINES.get(case.get("id", ""), ["CITY NEWS"])
                return lines[_rng.randi_range(0, lines.size() - 1)]


func random_phone_call() -> Dictionary:
                # the ambient phone event: returns {line, detail}
                var i := _rng.randi_range(0, PHONE_LINES.size() - 1)
                return {"line": PHONE_LINES[i][0], "detail": PHONE_LINES[i][1]}


# --- boons -----------------------------------------------------------------------

func boon_picks() -> int:
                var r: Dictionary = case.get("reward", {})
                return 2 if r.get("kind", "") == "boon" else 1


func offer_boons(n: int = 3) -> Array[Dictionary]:
                var pool: Array = []
                for b in BOONS:
                                if not boons.has(b["id"]):
                                                pool.append(b)
                for i in range(pool.size() - 1, 0, -1):
                                var j := _rng.randi_range(0, i)
                                var tmp = pool[i]; pool[i] = pool[j]; pool[j] = tmp
                var out: Array[Dictionary] = []
                for k in mini(n, pool.size()):
                                out.append(pool[k])
                return out


func add_boon(id: String) -> void:
                if not boons.has(id):
                                boons.append(id)
                boon_picks_left = maxi(boon_picks_left - 1, 0)
                boons_changed.emit()


func boon_by_id(id: String) -> Dictionary:
                for b in BOONS:
                                if b["id"] == id:
                                                return b
                return {}


# --- modifiers (read by player, guard and task scripts) -------------------------

func mult(key: String) -> float:
                var m := 1.0
                for id in boons:
                                var mods: Dictionary = boon_by_id(id).get("mods", {})
                                if mods.has(key):
                                                m *= float(mods[key])
                m *= _meta_mult(key)
                return m


func add(key: String) -> float:
                var a := 0.0
                for id in boons:
                                var mods: Dictionary = boon_by_id(id).get("mods", {})
                                if mods.has(key):
                                                a += float(mods[key])
                return a


func _meta_mult(key: String) -> float:
                var s := int(meta["stride"]); var o := int(meta["soles"]); var p := int(meta["pockets"])
                match key:
                                "dash_time_mult": return 1.0 + 0.12 * s
                                "sneak_mult":     return 1.0 + 0.08 * o
                                "noise_mult":     return 1.0 - 0.20 * o
                                "insurance_add":  return 0.1 * p
                return 1.0


# --- favors and the shop --------------------------------------------------------

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
                _save()
                favor_changed.emit(favors)
                return true


func earn_favors(amount: int) -> void:
                favors += amount
                last_favors_earned = amount
                _save()
                favor_changed.emit(favors)


# --- save / load ----------------------------------------------------------------

func save_game() -> void:
                _save()


func load_game() -> void:
                _load_save()


func _save() -> void:
                var cf := ConfigFile.new()
                cf.set_value("rh", "favors", favors)
                cf.set_value("rh", "nights", nights_played)
                for k in meta:
                                cf.set_value("meta", k, meta[k])
                # save the bag state so it survives a relaunch
                cf.set_value("bag", "remaining", _bag)
                cf.save(save_path)


func _load_save() -> void:
                var cf := ConfigFile.new()
                if cf.load(save_path) != OK:
                                return
                favors = int(cf.get_value("rh", "favors", 0))
                nights_played = int(cf.get_value("rh", "nights", 0))
                for k in meta:
                                meta[k] = clampi(int(cf.get_value("meta", k, 0)), 0, 3)
                var saved_bag: Array = cf.get_value("bag", "remaining", [])
                if not saved_bag.is_empty():
                                _bag.assign(saved_bag)
