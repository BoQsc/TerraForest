// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode cull_disabled, depth_draw_always, fog_disabled;

// Screen colour already includes environment fog. Applying fog to this resolved
// transmission again exposes submerged contact triangles as bands and patches.
// Resolve transmission from the opaque scene once per pixel. Writing depth
// prevents stacked water faces from repeatedly tinting the same scene color.
// No SSR, second camera, refraction distortion, or geometry displacement.
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 water_color : source_color = vec3(0.055, 0.23, 0.21);
uniform float absorption : hint_range(0.05, 2.0) = 0.4;
// A small surface tint keeps bucket-sized shallow puddles readable.
uniform float surface_tint : hint_range(0.0, 0.3) = 0.22;
// Linear RG slope data: one shared mipmapped texture, no extra render pass.
uniform sampler2D ripple_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.55;
uniform float ripple_scale = 0.25;
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
    // From inside the volume, submerged side/bottom exits reveal the opaque
    // scene already shaded by the underwater camera. Re-applying a surface
    // reflection here turns the terrain-contact tessellation into bright bands.
    bool submerged_exit = !FRONT_FACING && surface_world_normal.y < 0.5;
    if (submerged_exit) thickness = 0.0;
    float transmission = exp(-absorption * thickness);
    // At solid contact, the boundary converges to the already rendered terrain.
    // Fade surface lighting as well as tint; otherwise closed contact faces
    // create reflective bands across the lake bed.
    float contact_visibility = smoothstep(0.0, 0.25, thickness);
    vec3 n = normalize(surface_world_normal);
    vec2 ripple = texture(ripple_normal, UV * ripple_scale + TIME * vec2(0.007, -0.004)).rg * 2.0 - 1.0;
    // Ripples belong to the upper water surface. Viewing it from below still
    // preserves ripples, but excavated underside/contact faces stay unperturbed.
    n = normalize(n + vec3(ripple.x, 0.0, ripple.y) * ripple_strength * max(n.y, 0.0));
    NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
    if (!FRONT_FACING) NORMAL = -NORMAL;
    float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
    float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
    float through = transmission * (1.0 - fresnel * contact_visibility) * (1.0 - surface_tint * contact_visibility);
    ALBEDO = water_color * (1.0 - through) * 0.5;
    EMISSION = textureLod(scene_color, SCREEN_UV, 0.0).rgb * through + water_color * (1.0 - through) * 0.5;
    METALLIC = 0.0;
    ROUGHNESS = 0.16;
    // Godot's dielectric F0 = 0.16 * SPECULAR^2; water F0 is about 0.02.
    SPECULAR = 0.35 * contact_visibility;
    // Clear shallows, progressively absorbed deep water, reflected grazing light.
    // Deliberately no alpha blending: nearest depth wins regardless of region
    // draw order. Transmission is already included in the resolved color.
}
