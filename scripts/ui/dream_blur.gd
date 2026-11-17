class_name DreamBlur
extends CompositorEffect

# Dreamfilter.bb UpdateBlur: the previous composited frame is drawn over the new 3D frame with alpha = BlurVolume and the
# result is copied back, so out[n] = mix(scene[n], out[n-1], BlurVolume): exponential ghost trails. The history lives in
# the camera's scene buffers; the HUD is drawn after the compositor and stays sharp. Forward+ / Mobile only.

const CONTEXT := &"dream_blur"
const HISTORY := &"history"
const MIN_VOLUME := 0.005

const SHADER_SOURCE := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(rgba16f, set = 0, binding = 1) uniform image2D history_image;
layout(push_constant, std430) uniform Params {
	vec2 size;
	float volume;
	float pad;
} params;

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(params.size.x) || px.y >= int(params.size.y)) {
		return;
	}
	vec4 scene = imageLoad(color_image, px);
	vec4 history = imageLoad(history_image, px);
	vec4 result = vec4(mix(scene.rgb, history.rgb, params.volume), scene.a);
	imageStore(color_image, px, result);
	imageStore(history_image, px, result);
}
"""

var volume := 0.0 : set = set_volume
var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _restart := true

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	enabled = false
	RenderingServer.call_on_render_thread(_create_pipeline)

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 0.95)
	var active := volume > MIN_VOLUME
	if not active:
		_restart = true
	enabled = active

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		if _pipeline.is_valid():
			_rd.free_rid(_pipeline)
		if _shader.is_valid():
			_rd.free_rid(_shader)

func _create_pipeline() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	var source := RDShaderSource.new()
	source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	source.source_compute = SHADER_SOURCE
	var spirv := _rd.shader_compile_spirv_from_source(source)
	if spirv.compile_error_compute != "":
		push_error("DreamBlur: " + spirv.compile_error_compute)
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	if _shader.is_valid():
		_pipeline = _rd.compute_pipeline_create(_shader)

func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	if not _pipeline.is_valid():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	var restart := _restart or _history_size(buffers) != size
	if restart:
		buffers.clear_context(CONTEXT)
		buffers.create_texture(CONTEXT, HISTORY, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
				RenderingDevice.TEXTURE_USAGE_STORAGE_BIT, RenderingDevice.TEXTURE_SAMPLES_1, size, buffers.get_view_count(), 1, false, false)
		_restart = false
	var push := PackedFloat32Array([size.x, size.y, 0.0 if restart else volume, 0.0])
	for view in buffers.get_view_count():
		var color := RDUniform.new()
		color.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		color.binding = 0
		color.add_id(buffers.get_color_layer(view))
		var history := RDUniform.new()
		history.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		history.binding = 1
		history.add_id(buffers.get_texture_slice(CONTEXT, HISTORY, view, 0, 1, 1))
		var uniform_set := UniformSetCacheRD.get_cache(_shader, 0, [color, history])
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipeline)
		_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
		_rd.compute_list_set_push_constant(list, push.to_byte_array(), push.size() * 4)
		_rd.compute_list_dispatch(list, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
		_rd.compute_list_end()

func _history_size(buffers: RenderSceneBuffersRD) -> Vector2i:
	if not buffers.has_texture(CONTEXT, HISTORY):
		return Vector2i.ZERO
	return buffers.get_texture_slice_size(CONTEXT, HISTORY, 0)
