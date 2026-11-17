extends RefCounted
class_name GammaBlend
# Translucent and additive pictures blended the way Blitz3D does (on display values): see shaders/gamma_blend.gdshaderinc
# (mixed pictures: they read the screen) and shaders/gamma_add.gdshaderinc (additive pictures: the hardware's additive blend).

static var _fogged: Shader
static var _unfogged: Shader
static var _overlay: Shader
static var _add_fogged: Shader
static var _add_unfogged: Shader
static var _add_overlay: Shader
static var _white: Texture2D

# fog: false for the pictures the original draws without fog; overlay: ignores depth (the pocket dimension's plane).
static func make(texture: Texture2D, color: Color = Color.WHITE, additive: bool = false, billboard: bool = false, fog: bool = true, overlay: bool = false) -> ShaderMaterial:
	if _fogged == null:
		_fogged = load("res://shaders/gamma_blend.gdshader")
		_unfogged = load("res://shaders/gamma_blend_nofog.gdshader")
		_overlay = load("res://shaders/gamma_blend_overlay.gdshader")
		_add_fogged = load("res://shaders/gamma_add.gdshader")
		_add_unfogged = load("res://shaders/gamma_add_nofog.gdshader")
		_add_overlay = load("res://shaders/gamma_add_overlay.gdshader")
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(image)
	var material := ShaderMaterial.new()
	if additive:
		material.shader = _add_overlay if overlay else (_add_fogged if fog else _add_unfogged)
	else:
		material.shader = _overlay if overlay else (_fogged if fog else _unfogged)
	material.set_shader_parameter("tex", texture if texture != null else _white)
	material.set_shader_parameter("color", color)
	material.set_shader_parameter("additive", additive)
	material.set_shader_parameter("billboard", billboard)
	return material

# CreateDecal's sprite: alpha blended and, with EntityFX 0, lit like a model by the ambient and the shown room lights.
static func decal(texture: Texture2D, color: Color = Color.WHITE) -> ShaderMaterial:
	var material := make(texture, color)
	material.set_shader_parameter("entity_lit", true)
	return material
