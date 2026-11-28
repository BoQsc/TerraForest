// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform bool stone = false;
uniform float grass_detail_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 grass_detail_mean = vec3(1.0);
uniform sampler2D grass_detail : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D stone_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wind_strength : hint_range(0.0, 1.0) = 1.0;
uniform float distance_fade_start = 10000.0;
uniform float distance_fade_end = 11000.0;
uniform vec3 cover_eye = vec3(0.0);
uniform float cover_clock = 0.0;
// Enabled only for the grass mesh carrying complementary near/low geometry.
const bool near_lod_transition = false;
uniform float near_lod_metric = 703.74;
varying flat float near_lod_cut;
const bool cover_lod_transition = false;
const bool cover_lod_far_transition = false;
uniform vec4 cover_lod_edges = vec4(0.02225,0.0248,0.0745,0.0798);
varying flat vec2 cover_lod_interval;
const bool proxy_lod_transition = false;
const bool shadow_distance_transition = false;
uniform vec2 proxy_lod_edges = vec2(0.037,0.0448);
uniform vec2 shadow_fade_edges = vec2(36.0,48.0);
varying flat float proxy_lod_cut;
uniform float distant_self_shade : hint_range(0.0,1.0) = 0.28;
varying float canopy_shade;
varying float coverage;
varying float variation;
varying float root_shade;
void vertex() {
    vec3 origin = MODEL_MATRIX[3].xyz;
    vec3 near_delta = origin-cover_eye;
    float near_weight = near_lod_transition ? smoothstep(0.0002907025 * near_lod_metric * near_lod_metric, 0.00039204 * near_lod_metric * near_lod_metric, dot(near_delta,near_delta)) : 0.0;
    near_lod_cut = UV2.x < 0.5 ? -near_weight : 1.0+near_weight;
    if (cover_lod_transition) {
        vec4 limits = cover_lod_edges * near_lod_metric;
        float d2 = dot(near_delta,near_delta);
        float first = smoothstep(limits.x*limits.x,limits.y*limits.y,d2);
        float second = cover_lod_far_transition ? smoothstep(limits.z*limits.z,limits.w*limits.w,d2) : 0.0;
        cover_lod_interval = UV2.x < 0.5 ? vec2(first,1.0) : (UV2.x < 1.5 ? vec2(second,first) : vec2(0.0,second));
    }
    vec2 proxy_limits=proxy_lod_edges*near_lod_metric;
    proxy_lod_cut=proxy_lod_transition?smoothstep(proxy_limits.x*proxy_limits.x,proxy_limits.y*proxy_limits.y,dot(near_delta,near_delta)):0.0;
    float view_distance=distance(origin.xz,cover_eye.xz);
    float distance_weight = 1.0-smoothstep(distance_fade_start,distance_fade_end,view_distance);
    // Cheap canopy self-occlusion approximation, evaluated per vertex. It is
    // not a cast shadow and deliberately adds no shadow-map/depth/texture pass.
    float far_weight=smoothstep(24.0,56.0,view_distance);
    canopy_shade=1.0-distant_self_shade*far_weight*(1.0-smoothstep(0.0,0.9,UV.y));
    float age = cover_clock-INSTANCE_CUSTOM.x;
    coverage = distance_weight * (INSTANCE_CUSTOM.y>0.5?smoothstep(0.0,0.65,max(0.0,age)):1.0);
    if(shadow_distance_transition && IN_SHADOW_PASS) coverage*=1.0-smoothstep(shadow_fade_edges.x,shadow_fade_edges.y,view_distance);
    root_shade = mix(0.64, 1.0, smoothstep(0.015, 0.19, VERTEX.y));
    float phase = dot(origin.xz, vec2(0.71, 0.43));
    variation = 0.95 + 0.05 * sin(phase * 3.7);
    if (!stone) {
        float weight = clamp(VERTEX.y / 0.65, 0.0, 1.0);
        // Stable slight per-instance curvature; no new geometry or texture reads.
        vec2 bend=(fract(sin(vec2(phase,phase+19.7))*vec2(43758.5453,19642.349))-0.5)*0.07;
        VERTEX.xz+=bend*weight*weight;

        float sway = sin(TIME * 1.35 + phase) * 0.009 + sin(TIME * 2.1 + phase * 1.7) * 0.003;
        VERTEX.x += sway * weight * weight * wind_strength;
        VERTEX.z += sway * weight * weight * 0.55 * wind_strength;
    }
    if (proxy_lod_transition && !IN_SHADOW_PASS && proxy_lod_cut>=1.0) VERTEX=vec3(0.0);
    if (shadow_distance_transition && IN_SHADOW_PASS && coverage<=0.0) VERTEX=vec3(0.0);
    if (near_lod_transition && (UV2.x < 0.5 ? near_weight >= 1.0 : near_weight <= 0.0)) VERTEX = vec3(0.0);
    if (cover_lod_transition && cover_lod_interval.y <= cover_lod_interval.x) VERTEX = vec3(0.0);
}
void fragment() {
    // Opaque coverage dithering keeps depth writes and avoids alpha sorting/overdraw.
    float threshold=fract(52.9829189*fract(dot(floor(FRAGCOORD.xy),vec2(0.06711056,0.00583715))));
    if(coverage<=threshold)discard;
    if(proxy_lod_transition && !IN_SHADOW_PASS && threshold<proxy_lod_cut)discard;
    if (near_lod_transition && (near_lod_cut <= 0.0 ? threshold < -near_lod_cut : threshold >= near_lod_cut-1.0)) discard;
    if (cover_lod_transition && (threshold < cover_lod_interval.x || threshold >= cover_lod_interval.y)) discard;
    if (stone) {
        vec4 rock = texture(stone_color, UV);
        ALBEDO = rock.rgb * COLOR.rgb * variation;
        NORMAL_MAP = texture(stone_normal, UV).rgb;
        NORMAL_MAP_DEPTH = 0.55;
        ROUGHNESS = 0.94;
        SPECULAR = 0.24;
    } else {
        // MSAA can shade a covered thin triangle at a pixel-center location
        // outside that triangle. Bound the authored shading domain: extrapolated
        // UVs made this multiplier negative and produced moving black pixels.
        float edge = min(abs(UV.x - 0.5) * 2.0, 1.0);
        float width = max(fwidth(UV.x), 0.008);
        float vein = 1.0 - smoothstep(width, width * 2.0, abs(UV.x - 0.5));
        float ribs = 0.96 + 0.04 * sin((UV.y - abs(UV.x - 0.5) * 0.35) * 95.0);
        ALBEDO = COLOR.rgb * variation * mix(1.0, 0.79, edge * edge) * ribs + COLOR.rgb * vein * 0.16;
        ALBEDO *= clamp(root_shade,0.64,1.0);
        AO = mix(0.62,1.0,smoothstep(0.0,0.30,UV.y));
        AO_LIGHT_AFFECT = 0.35;
        if (grass_detail_strength > 0.0) {
            // UV.y runs root to tip; image top is the warm tip.
            // A blade is much narrower than it is long: sample a narrow surface strip.
            // Whole-square mapping stretches fine grain into painted vertical lines.
            float strip_start = clamp((variation - 0.95) * 14.0, 0.0, 0.7);
            vec3 detail = texture(grass_detail, vec2(strip_start + UV.x * 0.20, 1.0 - UV.y)).rgb;
            vec3 modulation = detail / max(grass_detail_mean, vec3(0.01));
            // Textured mode softens the old painted central rib instead of stacking it.
            vec3 textured = COLOR.rgb * variation * clamp(root_shade,0.64,1.0) * modulation * 0.90;
            ALBEDO = mix(ALBEDO, textured, grass_detail_strength);
        }
        ALBEDO *= clamp(canopy_shade,1.0-distant_self_shade,1.0);
        ROUGHNESS = mix(0.84, 0.94, grass_detail_strength);
        SPECULAR = mix(0.2, 0.12, grass_detail_strength);
        BACKLIGHT = COLOR.rgb * mix(0.18, 0.10, grass_detail_strength);
        // Godot already faces double-sided normals toward the viewer.
    }
}
