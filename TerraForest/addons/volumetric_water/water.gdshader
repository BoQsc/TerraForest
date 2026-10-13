// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode cull_disabled, depth_draw_always;

// Resolve transmission from the opaque scene once per pixel. Writing depth
// prevents stacked water faces from repeatedly tinting the same scene color.
// No SSR, second camera, refraction distortion, or geometry displacement.
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 water_color : source_color = vec3(0.08, 0.36, 0.34);
uniform float absorption : hint_range(0.05, 2.0) = 0.65;
// A small surface tint keeps bucket-sized shallow puddles readable.
uniform float surface_tint : hint_range(0.0, 0.3) = 0.22;
uniform float ripple_strength : hint_range(0.0, 0.12) = 0.035;
varying vec3 surface_world_normal;

void vertex() {
    surface_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
    float depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    ndc.z = depth * 2.0 - 1.0;
#endif
    vec4 behind = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    behind.xyz /= behind.w;
    // Distance through the water along this view ray, not nonlinear depth.
    float thickness = clamp(length(behind.xyz) - length(VERTEX), 0.0, 40.0);
    float transmission = exp(-absorption * thickness);
    vec3 n = normalize(surface_world_normal);
    float a = dot(UV, vec2(1.7, 1.1)) + TIME * 0.65;
    float b = dot(UV, vec2(-1.3, 2.2)) - TIME * 0.48;
    // Preserve vertical side normals; ripples perturb horizontal surfaces only.
    n = normalize(n + vec3(cos(a), 0.0, cos(b)) * ripple_strength * abs(n.y));
    NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
    if (!FRONT_FACING) NORMAL = -NORMAL;
    float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
    float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
    float through = transmission * (1.0 - fresnel) * (1.0 - surface_tint);
    ALBEDO = water_color * (1.0 - through) * 0.5;
    EMISSION = textureLod(scene_color, SCREEN_UV, 0.0).rgb * through + water_color * (1.0 - through) * 0.5;
    METALLIC = 0.0;
    ROUGHNESS = 0.24;
    SPECULAR = 0.5;
    // Clear shallows, progressively absorbed deep water, reflected grazing light.
    // Deliberately no alpha blending: nearest depth wins regardless of region
    // draw order. Transmission is already included in the resolved color.
}
