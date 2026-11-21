extends CanvasLayer
## The night HUD: intel ledger, alarm, job list, door prompt, debrief.
## Legibility contract: bright fill over an ink outline. Nothing permanent
## floats over the playfield - readouts live ON the wall rows (top = where you
## are and what you carry, bottom = rule, jobs, alarm), the rest is transient.

const INK := Color("14121c")
const COLOR_BONE := Color("ded6c7")
const COLOR_SODIUM := Color("e8b366")
const COLOR_RED := Color("e85145")
const COLOR_FOG := Color("a79bb0")
const COLOR_SLATE := Color("4a4e69")
const OFFICE := "res://scenes/office.tscn"
const JOB_SHORT := {"bug": "BUG THE PHONE", "documents": "STEAL DOCUMENTS", "ledger": "PHOTOGRAPH LEDGER", "evidence": "SECURE EVIDENCE"}

var _root: Control
var _ledger_pts: Label
var _alarm_name: Label
var _jobs: Label
var _where: Label
var _rule: Label
var _boons: Label
var _chain: Label
var _prompt: Label
var _flash: Label
var _fade: ColorRect
var _debrief: Control
var _debrief_text: Label
var _flash_tween: Tween


func _ready() -> void:
        _root = Control.new()
        _root.set_anchors_preset(Control.PRESET_FULL_RECT)
        _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(_root)

        # --- the top wall row (a sign on the building): where, and the ledger ---
        _where = _label(Vector2(0, 5), 640, 8, COLOR_FOG, HORIZONTAL_ALIGNMENT_CENTER)
        _ledger_pts = _label(Vector2(332, 5), 300, 8, COLOR_SODIUM, HORIZONTAL_ALIGNMENT_RIGHT)

        # --- boons carried, slim line under the portrait (top left) ---
        _boons = _label(Vector2(10, 52), 300, 8, COLOR_FOG, HORIZONTAL_ALIGNMENT_LEFT)

        # --- the bottom wall row (a strip on the baseboard): rule / jobs / alarm ---
        _rule = _label(Vector2(8, 341), 150, 8, COLOR_FOG, HORIZONTAL_ALIGNMENT_LEFT)
        _jobs = _label(Vector2(100, 341), 440, 8, COLOR_BONE, HORIZONTAL_ALIGNMENT_CENTER)
        _alarm_name = _label(Vector2(482, 341), 150, 8, COLOR_FOG, HORIZONTAL_ALIGNMENT_RIGHT)

        # --- the style chain (Hotline Miami), above the baseboard ---
        _chain = _label(Vector2(400, 304), 232, 10, COLOR_SODIUM, HORIZONTAL_ALIGNMENT_RIGHT)

        # --- back-door prompt ---
        _prompt = _label(Vector2(120, 286), 400, 11, COLOR_SODIUM, HORIZONTAL_ALIGNMENT_CENTER)
        _prompt.visible = false

        # --- alarm / event flash (top centre, under the wall sign) ---
        _flash = _label(Vector2(120, 34), 400, 10, COLOR_RED, HORIZONTAL_ALIGNMENT_CENTER)
        _flash.visible = false

        _build_debrief()

        # --- fade (the stairs down, the first frame of a night) ---
        _fade = ColorRect.new()
        _fade.set_anchors_preset(Control.PRESET_FULL_RECT)
        _fade.color = Color(0.08, 0.07, 0.11, 1.0)
        _fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _root.add_child(_fade)
        create_tween().tween_property(_fade, "color:a", 0.0, 0.12)   # restarts are instant

        Run.ledger_changed.connect(_refresh)
        Run.alarm_changed.connect(_on_alarm)
        Run.night_ended.connect(_on_night_ended)
        Run.boons_changed.connect(_refresh_boons)
        Run.style_changed.connect(_on_style)
        for door in get_tree().get_nodes_in_group("back_door"):
                door.prompt_changed.connect(_on_prompt)
        _refresh()
        _refresh_boons()
        _on_style(Run.chain, Run.style)
        _on_alarm(Run.alarm)


func _process(_delta: float) -> void:
        # the rule chip doubles as the CURFEW countdown
        if _rule == null or not Run.active:
                return
        var r: String = Run.rule()
        var txt: String = Run.RULES[r]["name"]
        if r == "curfew":
                var host := get_parent()
                if host != null and "curfew_left" in host:
                        txt += "  %ds" % ceili(host.curfew_left)
        if _rule.text != txt:
                _rule.text = txt
                var col := COLOR_FOG
                match r:
                        "noise", "heavy":
                                col = COLOR_RED
                        "curfew":
                                col = COLOR_SODIUM
                        "quiet":
                                col = COLOR_BONE
                _rule.add_theme_color_override("font_color", col)


func _refresh_boons() -> void:
        var names: Array[String] = []
        for id in Run.boons:
                names.append(Run.boon_by_id(id)["name"])
        _boons.text = " · ".join(names)


func _on_style(chain: int, style: int) -> void:
        _chain.text = "" if (chain == 0 and style == 0) else ("CHAIN x%d   STYLE %d" % [maxi(chain, 1), style] if chain > 0 else "STYLE %d" % style)


func bind_world() -> void:
        # night.gd deals the jobs AFTER this HUD is ready (children ready first),
        # so it calls this once the plan is on the floor.
        for t in get_tree().get_nodes_in_group("task_spots"):
                if not t.completed.is_connected(_on_task_done):
                        t.completed.connect(_on_task_done)
        _refresh()


func _exit_tree() -> void:
        for sig in [Run.ledger_changed, Run.alarm_changed, Run.night_ended]:
                for c in sig.get_connections():
                        if c["callable"].get_object() == self:
                                sig.disconnect(c["callable"])


func _label(pos: Vector2, width: float, size: int, color: Color, align: int) -> Label:
        var l := Label.new()
        l.position = pos
        l.size = Vector2(width, size + 6)
        l.horizontal_alignment = align as HorizontalAlignment
        l.add_theme_font_size_override("font_size", size)
        l.add_theme_color_override("font_color", color)
        l.add_theme_color_override("font_outline_color", INK)
        l.add_theme_constant_override("outline_size", 2)
        l.modulate = Color.WHITE
        l.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _root.add_child(l)
        return l


func _build_debrief() -> void:
        _debrief = Control.new()
        _debrief.set_anchors_preset(Control.PRESET_FULL_RECT)
        _debrief.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _debrief.visible = false
        _root.add_child(_debrief)
        var dim := ColorRect.new()
        dim.set_anchors_preset(Control.PRESET_FULL_RECT)
        dim.color = Color(0.06, 0.05, 0.09, 0.82)
        dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _debrief.add_child(dim)
        var panel := ColorRect.new()
        panel.position = Vector2(150, 50)
        panel.size = Vector2(340, 260)
        panel.color = Color("1c1a2a")
        panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _debrief.add_child(panel)
        var edge := ColorRect.new()
        edge.position = Vector2(149, 49)
        edge.size = Vector2(342, 262)
        edge.color = COLOR_SLATE
        edge.show_behind_parent = true
        edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _debrief.add_child(edge)
        _debrief.move_child(edge, 1)
        _debrief_text = Label.new()
        _debrief_text.position = Vector2(166, 60)
        _debrief_text.size = Vector2(308, 240)
        _debrief_text.add_theme_font_size_override("font_size", 11)
        _debrief_text.add_theme_color_override("font_color", COLOR_BONE)
        _debrief_text.add_theme_color_override("font_outline_color", INK)
        _debrief_text.add_theme_constant_override("outline_size", 2)
        _debrief_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _debrief.add_child(_debrief_text)


# --- live readouts ------------------------------------------------------------------------

func _refresh() -> void:
        var lead: Dictionary = Run.case
        _where.text = "%s  ·  %s  ·  FLOOR %d" % [lead["district"], lead["building"], Run.floor_no]
        _ledger_pts.text = "INTEL %d PTS  ·  G %d  ·  L %d  ·  E %d" % [
                Run.unbanked_points(), Run.unbanked[0], Run.unbanked[1], Run.unbanked[2],
        ]
        _refresh_jobs()


func _refresh_jobs() -> void:
        var lead: Dictionary = Run.case
        var wanted: Array = lead["tasks"]
        if Run.floor_no >= 2:
                wanted = []
                for i in int(lead["evidence"]):
                        wanted.append("evidence")
        var left := {}
        for t in get_tree().get_nodes_in_group("task_spots"):
                if not t.is_queued_for_deletion():
                        left[t.task_type] = int(left.get(t.task_type, 0)) + 1
        var totals := {}
        for t in wanted:
                totals[t] = int(totals.get(t, 0)) + 1
        var bits: Array[String] = []
        for t in totals:
                var remaining := int(left.get(t, 0))
                var total := int(totals[t])
                var done_n := total - remaining
                var mark := "[x]" if remaining == 0 else ("[/]" if done_n > 0 else "[ ]")
                var pair := ""
                if total > 1:
                        pair = " %d/%d" % [done_n, total] if done_n > 0 else " x%d" % total
                bits.append("%s %s%s" % [mark, JOB_SHORT[t], pair])
        _jobs.text = "   ".join(bits)


func _on_task_done(_type: String) -> void:
        # The spot frees itself after emitting; refresh once it is gone.
        await get_tree().process_frame
        _refresh_jobs()


func _on_alarm(tier: int) -> void:
        _alarm_name.text = "ALARM  %s" % Run.ALARM_NAMES[tier]
        var col := COLOR_FOG
        if tier >= 1:
                col = COLOR_SODIUM
        if tier >= 2:
                col = COLOR_RED
        _alarm_name.add_theme_color_override("font_color", col)


func _on_prompt(text: String, kind: String) -> void:
        _prompt.visible = text != ""
        _prompt.text = text
        var col := COLOR_SODIUM
        if kind == "blocked":
                col = COLOR_RED
        _prompt.add_theme_color_override("font_color", col)
        _prompt.size.y = 14.0 * (text.count("\n") + 1) + 4


func flash(msg: String, color: Color = COLOR_RED) -> void:
        _flash.text = msg
        _flash.add_theme_color_override("font_color", color)
        _flash.visible = true
        if _flash_tween:
                _flash_tween.kill()
        _flash_tween = create_tween()
        _flash_tween.tween_interval(2.2)
        _flash_tween.tween_callback(func() -> void: _flash.visible = false)


func fade_out() -> void:
        create_tween().tween_property(_fade, "color:a", 1.0, 0.3)


# --- the debrief ----------------------------------------------------------------------------

func _on_night_ended(r: Dictionary) -> void:
        _prompt.visible = false
        _flash.visible = false
        var t: Array = r["tiers"]
        var lines: Array[String] = []
        if r["outcome"] == "extracted":
                lines.append("EXTRACTED - THE FILES BURN AT DAWN")
        else:
                lines.append("CAUGHT - THE CASE WENT COLD")
        lines.append("%s  %s" % [r["case_no"], r["title"]])
        lines.append(r["district"])
        lines.append("")
        for i in 3:
                lines.append("%-9s x%d   +%d" % [Run.TIER_NAMES[i], t[i], t[i] * Run.TIER_POINTS[i]])
        lines.append("")
        lines.append("CARRIED %d PTS" % r["carried"])
        if r["outcome"] == "extracted":
                lines.append("BANKED  %d PTS" % r["banked"])
        else:
                lines.append("INSURANCE  %d PTS  (%d%% of what you carried)" % [r["insurance"], int(Run.INSURANCE * 100.0)])
        lines.append("")
        lines.append("ALARM PEAK %s   SPOTTED x%d   TAKEDOWNS x%d" % [Run.ALARM_NAMES[r["alarm_peak"]], r["spots"], r["takedowns"]])
        lines.append("STYLE %d   FAVORS +%d   SESSION %d PTS" % [r["style"], r["favors"], r["session"]])
        lines.append("")
        lines.append("[R] again - same case, new building     [ENTER] the office")
        _debrief_text.text = "\n".join(lines)
        # a beat so the caught / extract animation lands before the panel
        await get_tree().create_timer(0.35).timeout
        _debrief.visible = true


func _unhandled_input(event: InputEvent) -> void:
        if _debrief != null and _debrief.visible and event.is_action_pressed("ui_accept"):
                get_viewport().set_input_as_handled()
                if get_tree().current_scene != null and get_tree().current_scene.get_node_or_null("NightHud") == self:
                        get_tree().change_scene_to_file(OFFICE)
