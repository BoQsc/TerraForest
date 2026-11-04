// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D wood_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wood_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float wood_normal_strength = 0.38;
void fragment() {
	bool wood = UV2.y > 0.5;
	ALBEDO = COLOR.rgb * (wood ? texture(wood_albedo, UV).rgb : vec3(1.0));
	METALLIC = COLOR.a;
	ROUGHNESS = UV2.x;
	NORMAL_MAP = wood ? texture(wood_normal, UV).rgb : vec3(0.5, 0.5, 1.0);
	NORMAL_MAP_DEPTH = wood ? wood_normal_strength : 0.0;
}
