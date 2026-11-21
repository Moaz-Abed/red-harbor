class_name Rig
extends Node
## One drawn character: clips cut from a 32x32 sprite sheet, three drawn views
## (down / up / side), phase-preserving playback and side-view mirroring.

var sprite: AnimatedSprite2D
var view := "down"
var face_left := false
var _anims := {}      # base -> {row, frames, fps, loop, views, side}
var _base := ""


## `anims`: base -> cfg. cfg.views = one clip per view at row + view index;
## cfg.side = the clip is DRAWN facing right (mirror with flip_h).
func setup(host: CanvasItem, sheet: Texture2D, frame: int, anims: Dictionary, first: String) -> void:
	_anims = anims
	var views := ["down", "up", "side"]
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for base in anims:
		var cfg: Dictionary = anims[base]
		if cfg.get("views", false):
			for v in views:
				_add_clip(sf, "%s_%s" % [base, v], sheet, frame, cfg, int(cfg["row"]) + views.find(v))
		else:
			_add_clip(sf, base, sheet, frame, cfg, int(cfg["row"]))
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = sf
	host.add_child(sprite)
	play(first, true)


func _add_clip(sf: SpriteFrames, clip: String, sheet: Texture2D, frame: int, cfg: Dictionary, row: int) -> void:
	sf.add_animation(clip)
	sf.set_animation_speed(clip, cfg["fps"])
	sf.set_animation_loop(clip, cfg["loop"])
	for col in int(cfg["frames"]):
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = Rect2(col * frame, row * frame, frame, frame)
		sf.add_frame(clip, at)


func play(base: String, force := false) -> void:
	var cfg: Dictionary = _anims.get(base, {})
	var clip := "%s_%s" % [base, view] if cfg.get("views", false) else base
	if force or sprite.animation != clip:
		# Same base, new view: keep the stride phase so turning never stutters.
		var keep := (not force) and base == _base
		var f := sprite.frame
		var prog := sprite.frame_progress
		sprite.play(clip)
		if keep:
			sprite.set_frame_and_progress(f, prog)
	_base = base
	sprite.flip_h = face_left and (view == "side" or cfg.get("side", false))


func set_facing(dir: Vector2) -> void:
	# 8-direction input -> one of the three drawn views. Near-diagonals keep
	# the current view so the sprite never flickers while steering a corner.
	if dir.length() < 0.1:
		return
	var ax := absf(dir.x)
	var ay := absf(dir.y)
	if ax > ay * 1.1:
		view = "side"
	elif ay > ax * 1.1:
		view = "down" if dir.y > 0.0 else "up"
	if ax > 0.2:
		face_left = dir.x < 0.0
