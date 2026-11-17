class_name EntityMaterial
extends ShaderMaterial
# The material of every model (shaders/entity.gdshaderinc: Blitz3D's vertex lighting in gamma space). It keeps the
# StandardMaterial3D property names the rest of the game sets on model materials (albedo_texture, albedo_color,
# shading_mode, transparency, cull_mode), so a duplicated and re-skinned material works as before.

static var _shaders: Dictionary = {}
static var _lock := Mutex.new()

@export var albedo_texture: Texture2D:
	set(value):
		albedo_texture = value
		set_shader_parameter("albedo_tex", value)
@export var albedo_color := Color.WHITE:
	set(value):
		albedo_color = value
		set_shader_parameter("tint", value)
@export var shading_mode := BaseMaterial3D.SHADING_MODE_PER_VERTEX:
	set(value):
		shading_mode = value
		set_shader_parameter("fullbright", value == BaseMaterial3D.SHADING_MODE_UNSHADED)
@export var vertex_color_use_as_albedo := false:
	set(value):
		vertex_color_use_as_albedo = value
		set_shader_parameter("use_vertex_color", value)
@export var alpha_scissor_threshold := 0.5:
	set(value):
		alpha_scissor_threshold = value
		set_shader_parameter("alpha_scissor", value)
@export var transparency := BaseMaterial3D.TRANSPARENCY_DISABLED:
	set(value):
		transparency = value
		_pick_shader()
@export var cull_mode := BaseMaterial3D.CULL_BACK:
	set(value):
		cull_mode = value
		_pick_shader()
@export var texture_filter := BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _init() -> void:
	_pick_shader()

func _pick_shader() -> void:
	var key := "%d/%d" % [transparency, cull_mode]
	_lock.lock()
	if not _shaders.has(key):
		var modes := ["unshaded", "fog_disabled", ["cull_back", "cull_front", "cull_disabled"][clampi(cull_mode, 0, 2)]]
		var define := ""
		match transparency:
			BaseMaterial3D.TRANSPARENCY_ALPHA:
				define = "#define ENTITY_ALPHA\n"
			BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
				define = "#define ENTITY_ALPHA\n"
				modes.append("depth_prepass_alpha")
			BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				define = "#define ENTITY_SCISSOR\n"
		var shader := Shader.new()
		shader.code = "shader_type spatial;\nrender_mode %s;\n%s#include \"res://shaders/entity.gdshaderinc\"\n" % [", ".join(modes), define]
		_shaders[key] = shader
	shader = _shaders[key]
	_lock.unlock()
	set_shader_parameter("albedo_tex", albedo_texture)
	set_shader_parameter("tint", albedo_color)
	set_shader_parameter("fullbright", shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
	set_shader_parameter("use_vertex_color", vertex_color_use_as_albedo)
	set_shader_parameter("alpha_scissor", alpha_scissor_threshold)
