class_name Stage
extends Control
## PALCO — desenha o mundo num SubViewport de tamanho fixo (1280×640) e o compõe na tela com
## pós-processamento (brilho, cor, vinheta). O HUD fica fora, na resolução da janela.
##
## Camadas de visibilidade dos CanvasItems do mundo (CanvasItem.visibility_layer):
##   bit 1 = cena · bit 2 = emissivo (entra também no buffer de brilho).
## O buffer de brilho é um segundo SubViewport que olha o MESMO canvas, só com o bit 2, em meia
## resolução; dois passes de desfoque em 1/4 e a composição somam o halo por cima da cena.
## Um nó só entra no buffer se ele E os pais tiverem o bit 2: contêineres que não desenham usam LAYER_BOTH.

const LAYER_SCENE := 1
const LAYER_GLOW := 2
const LAYER_BOTH := 3

var scene_vp: SubViewport
var content: Node2D
var glow_vp: SubViewport
var blur_h: SubViewport
var blur_v: SubViewport
var screen: ColorRect
var mat: ShaderMaterial
var quality := 2
var _bloom := 0.0


func _init() -> void:
	name = "Stage"
	var sz := Vector2i(Bal.WORLD_W, Bal.WORLD_H)
	position = Vector2(0, Bal.HUD_TOP)
	size = Vector2(sz)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	scene_vp = _viewport("Scene", sz, false)
	content = Node2D.new()
	content.name = "Content"
	content.visibility_layer = LAYER_BOTH
	scene_vp.add_child(content)

	# ordem de criação = ordem de desenho no quadro: cena → brilho → desfoque H → desfoque V → tela
	glow_vp = _viewport("Glow", sz / 2, true)
	glow_vp.canvas_cull_mask = LAYER_GLOW
	var q := sz / 4
	blur_h = _blur_pass("BlurH", q, glow_vp.get_texture(), Vector2(1.7 / q.x, 0.0), 1.0)
	blur_v = _blur_pass("BlurV", q, blur_h.get_texture(), Vector2(0.0, 1.7 / q.y), 1.0)

	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/composite.gdshader")
	mat.set_shader_parameter("scene_tex", scene_vp.get_texture())
	mat.set_shader_parameter("bloom_tex", blur_v.get_texture())
	mat.set_shader_parameter("scene_size", Vector2(sz))
	screen = ColorRect.new()
	screen.name = "Screen"
	screen.size = Vector2(sz)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.material = mat
	add_child(screen)
	set_active(false)


func _ready() -> void:
	# só dá para apontar para o canvas da cena depois que os viewports entram na árvore
	glow_vp.world_2d = scene_vp.world_2d
	glow_vp.canvas_transform = Transform2D.IDENTITY.scaled(Vector2(0.5, 0.5))


func _viewport(vp_name: String, sz: Vector2i, transparent: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = vp_name
	vp.size = sz
	vp.transparent_bg = transparent
	vp.disable_3d = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	return vp


func _blur_pass(vp_name: String, sz: Vector2i, src: Texture2D, step_uv: Vector2, gain: float) -> SubViewport:
	var vp := _viewport(vp_name, sz, false)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/blur.gdshader")
	m.set_shader_parameter("src", src)
	m.set_shader_parameter("step_uv", step_uv)
	m.set_shader_parameter("gain", gain)
	var r := ColorRect.new()
	r.size = Vector2(sz)
	r.material = m
	vp.add_child(r)
	return vp


## Liga/desliga o desenho do palco (desligado nos menus: não gasta GPU).
func set_active(on: bool) -> void:
	visible = on
	scene_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	_update_glow(on)
	if not on:
		content.position = Vector2.ZERO


func _update_glow(on: bool) -> void:
	var glow_on := on and quality >= 1 and _bloom > 0.0
	var mode := SubViewport.UPDATE_ALWAYS if glow_on else SubViewport.UPDATE_DISABLED
	glow_vp.render_target_update_mode = mode
	blur_h.render_target_update_mode = mode
	blur_v.render_target_update_mode = mode
	mat.set_shader_parameter("bloom", _bloom if glow_on else 0.0)


## Aplica a cor/brilho do clima da missão (Ambience.PRESETS[...].grade) e o nível de qualidade.
func apply(grade: Dictionary, quality_level: int) -> void:
	quality = quality_level
	_bloom = float(grade.get("bloom", 0.0))
	mat.set_shader_parameter("saturation", float(grade.get("saturation", 1.0)))
	mat.set_shader_parameter("contrast", float(grade.get("contrast", 1.0)))
	var st: Color = grade.get("shadow_tint", Color.WHITE)
	var lt: Color = grade.get("light_tint", Color.WHITE)
	mat.set_shader_parameter("shadow_tint", Vector3(st.r, st.g, st.b))
	mat.set_shader_parameter("light_tint", Vector3(lt.r, lt.g, lt.b))
	mat.set_shader_parameter("vignette", float(grade.get("vignette", 0.0)) if quality >= 1 else 0.0)
	var hz: Color = grade.get("haze_color", Color.BLACK)
	mat.set_shader_parameter("haze_color", Vector3(hz.r, hz.g, hz.b))
	mat.set_shader_parameter("haze", float(grade.get("haze", 0.0)))
	mat.set_shader_parameter("heat", float(grade.get("heat", 0.0)) if quality >= 1 else 0.0)
	_update_glow(visible)


func set_shake(offset: Vector2) -> void:
	content.position = offset
