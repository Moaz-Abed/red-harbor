extends Node
## AmbientEvents — autoload "Ambient".
## Fires timed events inside the office to make it feel alive between cases:
## the phone rings (you can answer or let it go), the radio crackles with
## static and a one-liner, rain gusts at the window, something falls off the
## shelves. Each event modifies nothing — it is pure atmosphere. The optional
## phone call can carry intel (shown as a subtitle) but never forces you to act.
##
## The office scene connects to on_phone_ring and on_event and can play
## sfx/animation from there; this node only manages timers and state.

signal phone_ring                   # the phone rings; office connects animation
signal phone_answered(line: String, detail: String)  # player picked up
signal phone_ignored                # time ran out without answering
signal ambient_line(text: String)   # one-liner from the radio or city outside
signal rain_gust                    # window should rattle / intensify
signal shelf_drop                   # a small creak and slide sfx

const PHONE_RING_MIN := 25.0        # earliest a call can come in (seconds)
const PHONE_RING_MAX := 60.0        # latest
const RING_WINDOW := 8.0            # how long it rings before going to voicemail
const AMBIENT_MIN := 10.0
const AMBIENT_MAX := 30.0

# The informant's calls: the hook line for the panel, the sound that ends
# it. Pure atmosphere - never a task.
const CALLS := [
        {"line": "'Don't file the harbor one tonight.'",
                "detail": "A click, then the rain. The dial tone comes back bored."},
        {"line": "'The annex stairwell. They reordered the stairs after.'",
                "detail": "A click. Somewhere in the wire, a door that isn't there."},
        {"line": "'Terminal 4 is asleep. Do not wake the night shift.'",
                "detail": "Dial tone. It hums the third symphony, badly."},
        {"line": "'Your ninth delegate. He pays in fingerprints.'",
                "detail": "A click, then static shaped exactly like breathing."},
        {"line": "'The ballroom shoes came back polished. All forty pairs.'",
                "detail": "Dial tone. The rain in it falls upward."},
        {"line": "'Keep the lamp low tonight. The glass reads rooms.'",
                "detail": "A click. The line stays open long after it shouldn't."},
]

# Radio one-liners and city sounds that filter through the window.
const RADIO_LINES := [
        "...AND THE WEATHER SERVICE FORECASTS CONTINUED RAIN THROUGH THE WEEK...",
        "...TONIGHT'S PROGRAMME IS BROUGHT TO YOU BY THE MINISTRY OF LIGHT INDUSTRY...",
        "...WE REMIND CITIZENS THAT CURFEW HOURS REMAIN IN EFFECT AFTER 23:00...",
        "...REQUESTS FOR TRAVEL PERMITS MUST BE FILED NO LATER THAN FOURTEEN DAYS IN ADVANCE...",
        "...THE BUREAU CONFIRMS: ALL IS NORMAL. ALL IS WELL...",
        "...STATIC... STATIC... ...A PIANO PLAYS SOMETHING THAT SOUNDS LIKE A LULLABY...",
        "...YOU'RE LISTENING TO STATE RADIO, THE VOICE OF THE CITY...",
        "...THE PORT ANNOUNCES REVISED SHIPPING LANES EFFECTIVE IMMEDIATELY...",
        "...TONIGHT: A PERFORMANCE OF THE THIRD SYMPHONY, APPROVED FOR BROADCAST...",
        "...CRACKLE... ...SILENCE... ...CRACKLE...",
]

const CITY_LINES := [
        "A TRAM GROANS PAST OUTSIDE.",
        "SOMEWHERE BELOW, A DOOR SLAMS.",
        "RAIN PICKS UP AGAINST THE GLASS.",
        "THE BUILDING SETTLES. OLD IRON.",
        "A SIREN, FAR AWAY. THEN NOTHING.",
        "FOOTSTEPS IN THE HALL. THEY PASS.",
        "THE RADIATOR CLICKS AND TICKS.",
        "A CAR IDLES IN THE STREET. THEN LEAVES.",
]

var _rng := RandomNumberGenerator.new()
var _phone_timer: SceneTreeTimer
var _ambient_timer: SceneTreeTimer
var _ring_timer: SceneTreeTimer
var _ringing := false
var _office_active := false


func _ready() -> void:
        _rng.randomize()


# --- called by the office scene when the player enters / exits ------------------

func begin_office() -> void:
        _office_active = true
        _schedule_phone()
        _schedule_ambient()


func end_office() -> void:
        _office_active = false
        _ringing = false
        # timers expire naturally; we just stop reacting to them


# --- phone ---------------------------------------------------------------------

func _schedule_phone() -> void:
        if not _office_active:
                return
        var wait := _rng.randf_range(PHONE_RING_MIN, PHONE_RING_MAX)
        _phone_timer = get_tree().create_timer(wait)
        _phone_timer.timeout.connect(_on_phone_time, CONNECT_ONE_SHOT)


func _on_phone_time() -> void:
        if not _office_active:
                return
        _ringing = true
        phone_ring.emit()
        _ring_timer = get_tree().create_timer(RING_WINDOW)
        _ring_timer.timeout.connect(_on_ring_timeout, CONNECT_ONE_SHOT)


func _on_ring_timeout() -> void:
        if not _ringing:
                return
        _ringing = false
        phone_ignored.emit()
        _schedule_phone()


func answer_phone() -> Dictionary:
        # the office scene calls this when the player walks to the phone spot;
        # an empty call means nobody rang
        if not _ringing:
                return {}
        _ringing = false
        var call: Dictionary = CALLS[_rng.randi_range(0, CALLS.size() - 1)]
        phone_answered.emit(call["line"], call["detail"])
        _schedule_phone()
        return call


func is_ringing() -> bool:
        return _ringing


# --- ambient one-liners --------------------------------------------------------

func _schedule_ambient() -> void:
        if not _office_active:
                return
        var wait := _rng.randf_range(AMBIENT_MIN, AMBIENT_MAX)
        _ambient_timer = get_tree().create_timer(wait)
        _ambient_timer.timeout.connect(_on_ambient_time, CONNECT_ONE_SHOT)


func _on_ambient_time() -> void:
        if not _office_active:
                return
        var roll := _rng.randf()
        if roll < 0.40:
                ambient_line.emit(RADIO_LINES[_rng.randi_range(0, RADIO_LINES.size() - 1)])
        elif roll < 0.70:
                ambient_line.emit(CITY_LINES[_rng.randi_range(0, CITY_LINES.size() - 1)])
        elif roll < 0.85:
                rain_gust.emit()
        else:
                shelf_drop.emit()
        _schedule_ambient()
