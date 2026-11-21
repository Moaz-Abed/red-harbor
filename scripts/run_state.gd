extends Node
## The run (autoload "Run"): the dealt case, the boons you carry and, across
## launches, favors + permanent upgrades (user://red_harbor.cfg). One dealt
## case = one run.

signal boons_changed

enum Tier { GOSSIP, LEADS, EVIDENCE }
const TIER_POINTS: Array[int] = [1, 3, 8]

# Jobs a case can ask for.
const TASKS := {
        "bug": {"label": "BUG THE PHONE", "tier": Tier.GOSSIP},
        "documents": {"label": "STEAL DOCUMENTS", "tier": Tier.LEADS},
        "ledger": {"label": "PHOTOGRAPH THE LEDGER", "tier": Tier.LEADS},
        "evidence": {"label": "SECURE EVIDENCE", "tier": Tier.EVIDENCE},
}


# District conditions, printed in the case file. "mult" scales the lead value.
const RULES := {
        "quiet": {"name": "QUIET HOURS", "text": "No conditions on the file. A clean job, on paper.", "mult": 1.0},
        "noise": {"name": "ON AIR", "text": "The block is wired for sound - every step gets an ear.", "mult": 1.0},
        "curfew": {"name": "CURFEW", "text": "A bell rings after dark, and everyone counts the bells.", "mult": 2.0},
        "blackout": {"name": "BLACKOUT", "text": "The block runs dark. Nobody sees far; nobody sees you.", "mult": 1.0},
        "heavy": {"name": "HIGH SECURITY", "text": "A Party-grade security detail walks the block.", "mult": 1.5},
        "sealed": {"name": "SEALED VAULT", "text": "One room holds everything. No basement, no way out but the door.", "mult": 1.0},
}
const RULE_RISK := {"quiet": 0, "noise": 0, "curfew": 1, "blackout": 1, "heavy": 1, "sealed": 0}

# The case pool. One is dealt per night (no repeats until all six are out).
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

# Boons: run-long modifiers picked at the office radio. "mods" keys are read by
# mult("..._mult") / add("..._add").
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

# The desk drawer: permanent upgrades bought with favors.
const SHOP: Array[Dictionary] = [
        {"id": "stride", "name": "LONG STRIDE", "text": "Dash +12% further, per level.", "max": 3, "costs": [6, 10, 15]},
        {"id": "soles", "name": "MUFFLED SOLES", "text": "Sneak +8%, noise -20%, per level.", "max": 3, "costs": [6, 10, 15]},
        {"id": "pockets", "name": "DEEP POCKETS", "text": "Insurance +10% per level.", "max": 3, "costs": [6, 10, 15]},
]

var case := {}                # the dealt case (not chosen)
var need_new_case := true     # the office deals the next file
var boons: Array[String] = []
var favors := 0               # persistent
var boon_picks_left := 0      # radio picks remaining for this case's prep
var meta := {"stride": 0, "soles": 0, "pockets": 0}   # persistent shop levels
var save_path := "user://red_harbor.cfg"
var _rng := RandomNumberGenerator.new()
var _bag: Array = []          # case indices; all six dealt before a refill
var _last_id := ""


func _ready() -> void:
        _rng.randomize()
        load_game()


# --- the dealt case ------------------------------------------------------------------

func deal_case(rng_seed: int = -1) -> Dictionary:
        # Deal ONE case from the bag; no repeats until every file has been dealt.
        # A seeded deal also starts a fresh bag (QA pins the whole deal).
        if rng_seed >= 0:
                _rng.seed = rng_seed
                _bag = []
        if _bag.is_empty():
                _bag = range(ARCHETYPES.size())
                _shuffle(_bag)
                if String(ARCHETYPES[_bag[0]]["id"]) == _last_id and _bag.size() > 1:
                        var tmp = _bag[0]
                        _bag[0] = _bag[1]
                        _bag[1] = tmp
        var idx: int = _bag.pop_front()
        _last_id = String(ARCHETYPES[idx]["id"])
        var c: Dictionary = ARCHETYPES[idx].duplicate(true)
        c["case_no"] = "CASE %d" % _rng.randi_range(101, 399)
        if c["reward"]["kind"] == "favors":
                c["reward"]["amount"] = maxi(2, int(c["reward"]["amount"]) + _rng.randi_range(-1, 1))
        c["danger"] = danger_of(c)
        case = c
        need_new_case = false
        boons = []
        boon_picks_left = boon_picks()
        return case


func ensure_case() -> void:
        if need_new_case or case.is_empty():
                deal_case()


func _shuffle(arr: Array) -> void:
        for i in range(arr.size() - 1, 0, -1):
                var j := _rng.randi_range(0, i)
                var tmp = arr[i]
                arr[i] = arr[j]
                arr[j] = tmp


func danger_of(c: Dictionary) -> String:
        var score: int = int(c["guards"]) + int(RULE_RISK[c["rule"]])
        if score <= 2:
                return "LOW"
        if score == 3:
                return "MEDIUM"
        return "HIGH"


func rule() -> String:
        return String(case.get("rule", "quiet"))


func case_potential(c: Dictionary) -> int:
        var pts := 0
        for t in c["tasks"]:
                pts += TIER_POINTS[TASKS[t]["tier"]]
        return roundi(pts * float(RULES[c["rule"]]["mult"]))


func evidence_potential(c: Dictionary) -> int:
        return roundi(int(c["evidence"]) * TIER_POINTS[Tier.EVIDENCE] * float(RULES[c["rule"]]["mult"]))


# --- boons + upgrades ------------------------------------------------------------------

func boon_picks() -> int:
        # A boon-reward case deals a second pick at the radio.
        return 2 if not case.is_empty() and case["reward"]["kind"] == "boon" else 1


func offer_boons(n: int = 3) -> Array[Dictionary]:
        var free: Array = []
        for b in BOONS:
                if not boons.has(b["id"]):
                        free.append(b)
        _shuffle(free)
        var out: Array[Dictionary] = []
        for k in mini(n, free.size()):
                out.append(free[k])
        return out


func add_boon(id: String) -> void:
        if boons.has(id):
                return
        boons.append(id)
        boon_picks_left = maxi(boon_picks_left - 1, 0)
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


