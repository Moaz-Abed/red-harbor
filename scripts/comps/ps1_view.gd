class_name Ps1View
extends Node
## The PS1 tube: a 480x270 SubViewport renders the 3D world through one
## camera, the frame is upscaled nearest onto the 640x360 canvas, then the
## dither / scanline / vignette post goes on top. The game world, the follow
## camera and the HUD all live OUTSIDE this node - it is only the screen.

const W := 480
const H := 270
const POST := preload("res://shaders/ps1_post.gdshader")

var camera: Camera3D
var _view: SubViewport


func tube() -> SubViewport:
        # the low-res buffer the world renders into; environments belong here
        return _view


func _ready() -> void:
        _view = SubViewport.new()
        _view.size = Vector2i(W, H)
        _view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
        _view.positional_shadow_atlas_size = 0
        add_child(_view)
        camera = Camera3D.new()
        camera.fov = 64.0
        camera.near = 0.1
        camera.far = 90.0
        _view.add_child(camera)
        camera.make_current()
        var layer := CanvasLayer.new()
        layer.layer = 1
        add_child(layer)
        var frame := TextureRect.new()
        frame.texture = _view.get_texture()
        frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        frame.set_anchors_preset(Control.PRESET_FULL_RECT)
        frame.stretch_mode = TextureRect.STRETCH_SCALE
        frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
        layer.add_child(frame)
        var post := ColorRect.new()
        post.set_anchors_preset(Control.PRESET_FULL_RECT)
        post.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var mat := ShaderMaterial.new()
        mat.shader = POST
        post.material = mat
        layer.add_child(post)
