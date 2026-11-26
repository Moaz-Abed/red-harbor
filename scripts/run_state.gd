extends Node
## Run - the dealt case. One file lies open on the desk at a time. The bag
## holds the six files of the rotation and never repeats one until it has
## dealt all six; then it refills and shuffles. No economy, no upgrades -
## the office is a place to think, not to shop.

const CASES := [
	{
		"id": "morning_edition", "no": "244",
		"title": "THE MORNING EDITION", "district": "PRESS BUREAU",
		"building": "the printing annex",
		"blurb": "A columnist fell down a stairwell that only goes up. The censors cut the obituary to four lines and the paper never noticed.",
		"danger": "LOW", "fee": "180 FAVORS + EXPENSES",
	},
	{
		"id": "sodium_tide", "no": "251",
		"title": "THE SODIUM TIDE", "district": "HARBOR DISTRICT 9",
		"building": "the lighthouse keeper's room",
		"blurb": "The keeper logs ships that signal from the fog and never dock. The harbormaster says the sea is empty. The log is not.",
		"danger": "MEDIUM", "fee": "240 FAVORS + EXPENSES",
	},
	{
		"id": "quiet_week", "no": "263",
		"title": "A QUIET WEEK AT THE MINISTRY", "district": "MINISTRY OF LIGHT INDUSTRY",
		"building": "the ledger annex",
		"blurb": "Forty reams of ledger paper were eaten by something with hands. The night clerk heard chewing. The ministry heard nothing.",
		"danger": "LOW", "fee": "160 FAVORS",
	},
	{
		"id": "curfew_waltz", "no": "270",
		"title": "THE CURFEW WALTZ", "district": "THE OLD QUARTER",
		"building": "the glasshouse ballroom",
		"blurb": "Dancers after hours, every night, none of them registered. The caretaker swept up forty pairs of shoes and no dust.",
		"danger": "MEDIUM", "fee": "260 FAVORS + EXPENSES",
	},
	{
		"id": "glass_conference", "no": "278",
		"title": "THE GLASS CONFERENCE", "district": "THE TRADE HALL",
		"building": "the ninth floor meeting room",
		"blurb": "Nine delegates checked in. The table seats eight. Everyone remembers the ninth man and nobody will describe him.",
		"danger": "HIGH", "fee": "320 FAVORS + EXPENSES",
	},
	{
		"id": "terminal_sleep", "no": "282",
		"title": "TERMINAL 4 IS ASLEEP", "district": "FREIGHT TERMINAL 4",
		"building": "the cargo office",
		"blurb": "The night shift answers questions in unison and requests the same transfer. The freight moves at 03:00 with no engine attached.",
		"danger": "HIGH", "fee": "300 FAVORS + EXPENSES",
	},
]

var case := {}                    # the file on the desk, or {}
var _bag: Array[int] = []         # indices into CASES, dealt from the end
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func ensure_case() -> void:
	if case.is_empty():
		deal_case()


func deal_case(seed := -1) -> Dictionary:
	# a seed pins the whole deal - the bag shuffles, then deals from the end
	if seed >= 0:
		_rng.seed = seed
		_bag.clear()
	if _bag.is_empty():
		_bag.assign(range(CASES.size()))
		for i in range(_bag.size() - 1, 0, -1):
			var j: int = _rng.randi_range(0, i)
			var tmp: int = _bag[i]
			_bag[i] = _bag[j]
			_bag[j] = tmp
	case = CASES[_bag.pop_back()].duplicate(true)
	return case
