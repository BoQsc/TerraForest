// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform bool stone = false;
uniform sampler2D stone_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wind_strength : hint_range(0.0, 1.0) = 1.0;
varying float variation;
void vertex() {
    vec3 origin = MODEL_MATRIX[3].xyz;
    float phase = dot(origin.xz, vec2(0.71, 0.43));
    variation = 0.95 + 0.05 * sin(phase * 3.7);
    if (!stone) {
        float weight = clamp(VERTEX.y / 0.65, 0.0, 1.0);
        float sway = sin(TIME * 1.35 + phase) * 0.009 + sin(TIME * 2.1 + phase * 1.7) * 0.003;
        VERTEX.x += sway * weight * weight * wind_strength;
        VERTEX.z += sway * weight * weight * 0.55 * wind_strength;
    }
}
void fragment() {
    if (stone) {
        vec4 rock = texture(stone_color, UV);
        ALBEDO = rock.rgb * COLOR.rgb * variation;
        NORMAL_MAP = texture(stone_normal, UV).rgb;
        NORMAL_MAP_DEPTH = 0.55;
        ROUGHNESS = 0.94;
        SPECULAR = 0.24;
    } else {
        float edge = abs(UV.x - 0.5) * 2.0;
        float width = max(fwidth(UV.x), 0.008);
        float vein = 1.0 - smoothstep(width, width * 2.0, abs(UV.x - 0.5));
        float ribs = 0.96 + 0.04 * sin((UV.y - abs(UV.x - 0.5) * 0.35) * 95.0);
        ALBEDO = COLOR.rgb * variation * mix(1.0, 0.79, edge * edge) * ribs + COLOR.rgb * vein * 0.16;
        ROUGHNESS = 0.84;
        SPECULAR = 0.2;
        BACKLIGHT = COLOR.rgb * 0.18;
        if (!FRONT_FACING) { NORMAL = -NORMAL; }
    }
}
