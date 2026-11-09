// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float strength = 1.0;
uniform float seed = 0.0;
uniform bool face_on = false;
instance uniform float first_person_depth_scale = 1.0;
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
    vec2 cell = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(cell), hash(cell + vec2(1, 0)), f.x),
               mix(hash(cell + vec2(0, 1)), hash(cell + vec2(1, 1)), f.x), f.y);
}
void vertex() {
    if (face_on) {
        MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
    }
    Z_CLIP_SCALE = first_person_depth_scale;
}
void fragment() {
    vec2 p = UV + vec2(seed, seed * .73);
    float turbulence = noise(p * 9.0) * .65 + noise(p * 23.0) * .25 + noise(p * 47.0) * .10;
    float density;
    float hot;
    if (face_on) {
        float r = length(UV - .5) * 2.0;
        density = (1.0 - smoothstep(.12, .86, r + (turbulence - .5) * .30));
        density *= density;
        hot = 1.0 - r;
    } else {
        float y = 1.0 - UV.y;
        float bend = sin(y * 11.0 + seed) * .035 * y;
        float width = .045 + .28 * pow(sin(y * 3.14159265), .8) * (1.0 - y * .65);
        float edge = width - abs(UV.x - .5 + bend) + (turbulence - .5) * .19;
        density = smoothstep(-.035, .065, edge) * smoothstep(0.0, .06, y) * (1.0 - smoothstep(.55, 1.0, y));
        density *= .55 + .45 * turbulence;
        // Axial sheets fade when seen edge-on instead of drawing a hard line.
        density *= smoothstep(.08, .35, abs(dot(normalize(NORMAL), normalize(VIEW))));
        hot = clamp(edge * 6.0 + (1.0 - y) * .65, 0.0, 1.0);
    }
    vec3 color = mix(vec3(1.0, .42, .12), vec3(1.0, .88, .65), smoothstep(.05, .75, hot));
    color = mix(color, vec3(1.0, .97, .88), smoothstep(.72, 1.0, hot));
    ALBEDO = color * (face_on ? 1.5 : 1.4);
    EMISSION = vec3(0.0);
    ALPHA = density * strength;
}
