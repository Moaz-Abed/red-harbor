extends Node
## Screenshot harness for visual QA (run under xvfb, never headless).
## User args start after the `--` separator and use key=value:
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 \
##       res://tests/capture.tscn -- --scene=office --panel=case --out=/tmp/shot.png

const SCENES := {
        "menu": "res://scenes/menu.tscn",
        "office": "res://scenes/office.tscn",
        "night": "res://scenes/night.tscn",
        "main": "res://scenes/main.tscn",
}

var _args: Dictionary = {}
var _shot_count := 0


func _ready() -> void:
        for a in OS.get_cmdline_user_args():
                if a.find("=") != -1:
                        var kv := a.split("=", true, 1)
                        _args[kv[0].trim_prefix("--")] = kv[1]
                else:
                        _args[a.trim_prefix("--")] = "1"
        Run.save_path = "user://capture_save.cfg"
        Run.ensure_case()
        if _args.has("dump"):
                var of := FileAccess.open(str(_args["dump"]), FileAccess.WRITE)
                of.store_string(inst_of_office_text())
                of.close()
                print("CAPTURE: dumped case text")
                get_tree().quit()
                return
        var which: String = _args.get("scene", "office")
        var path: String = SCENES.get(which, which)
        print("CAPTURE: loading ", path)
        await get_tree().process_frame          # root is busy during _ready
        var inst: Node = load(path).instantiate()
        if _args.has("seed") and inst.get("deal_seed") != null:
                inst.set("deal_seed", int(_args["seed"]))
                Run.save_path = "user://capture_seed_save.cfg"
        get_tree().root.add_child(inst)
        await get_tree().process_frame
        await get_tree().process_frame
        if _args.has("panel"):
                if inst.has_method("open_panel"):
                        inst.open_panel(_args["panel"])
        if _args.has("strip"):
                for part in str(_args["strip"]).split(","):
                        _strip(inst, part.strip_edges())
                        await get_tree().process_frame
        if _args.has("start"):
                if inst.has_method("start_night"):
                        inst.start_night(false)
                        get_tree().current_scene = get_tree().root.get_node_or_null("Night")
        await _frames(int(_args.get("wait", 20)))
        await RenderingServer.frame_post_draw
        RenderingServer.force_draw(false, 2.0)
        _snap(str(_args.get("out", "/tmp/shot.png")))
        get_tree().quit()


func _strip(inst: Node, part: String) -> void:
        match part:
                "rain":
                        if inst.get("_rain_canvas") != null:
                                (inst.get("_rain_canvas") as Node).queue_free()
                                inst.set("_rain", [])
                "pause":
                        if inst.get("_pause") != null:
                                (inst.get("_pause") as Node).queue_free()
                "player":
                        if inst.get("_player") != null:
                                (inst.get("_player") as Node).queue_free()
                "tiles":
                        for c in inst.get_children():
                                if c is TileMapLayer:
                                        c.queue_free()
                "hud":
                        if inst.get("_hud") != null:
                                (inst.get("_hud") as Node).queue_free()
                "orphan":
                        # re-parent the panel out of the office HUD into a fresh layer
                        var panel: Node = inst.get("_panel")
                        if panel != null:
                                var fresh := CanvasLayer.new()
                                fresh.layer = 3
                                get_tree().root.add_child(fresh)
                                var box := Control.new()
                                box.set_anchors_preset(Control.PRESET_FULL_RECT)
                                box.mouse_filter = Control.MOUSE_FILTER_IGNORE
                                fresh.add_child(box)
                                panel.reparent(box)
        print("CAPTURE: stripped ", part)


func _frames(n: int) -> void:
        for i in n:
                await get_tree().process_frame


func inst_of_office_text() -> String:
        # mirror office.gd _case_text() on the current deal
        var c: Dictionary = Run.case
        var rule: Dictionary = Run.RULES[c["rule"]]
        var tally := {}
        for t in c["tasks"]:
                tally[t] = int(tally.get(t, 0)) + 1
        var jobs := ""
        for t in tally:
                jobs += "- %s%s\n" % [Run.TASKS[t]["label"], " x%d" % int(tally[t]) if int(tally[t]) > 1 else ""]
        var below := ("+%d PTS BELOW" % Run.evidence_potential(c)) if int(c["evidence"]) > 0 else "NO LOWER FLOOR"
        var r: Dictionary = c["reward"]
        var rew := "[+%d FAVORS]" % int(r["amount"]) if r["kind"] == "favors" else "[2 BOONS]"
        return "%s  ·  %s\n%s  ·  %s\n\n%s\n\n%s\n\nRULE: %s\n%s\n\n%d GUARDS  ·  DANGER %s\n%d PTS ON THE FLOOR  ·  %s  ·  %s" % [
                        c["case_no"], c["district"], c["title"], c["building"], c["blurb"],
                        jobs.strip_edges(), rule["name"], rule["text"],
                        c["guards"], c["danger"], Run.case_potential(c), below, rew]


func _snap(path: String) -> void:
        var img := get_viewport().get_texture().get_image()
        img.save_png(path)
        print("CAPTURE: saved ", path, " ", img.get_size())
        var colors := {}
        for y in [0, 180, 360, 540, 710]:
                for x in [0, 320, 640, 960, 1270]:
                        var c := img.get_pixel(x, y)
                        colors[c.to_html()] = colors.get(c.to_html(), 0) + 1
        print("CAPTURE: samples ", colors)
