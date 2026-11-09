// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float age = 0.0;
uniform float seed = 0.0;
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
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
    VERTEX *= .28 + age * 1.35;
    Z_CLIP_SCALE = first_person_depth_scale;
}
void fragment() {
    vec2 p = (UV - .5) * 2.0;
    vec2 warp = vec2(noise(p * 2.0 + seed), noise(p * 2.0 - seed)) - .5;
    float cloud = noise(p * 3.0 + warp * 2.0 + vec2(seed, -age * .7)) * .65;
    cloud += noise(p * 8.0 + seed - age) * .35;
    float edge = 1.0 - smoothstep(.15, 1.0, length(p + warp * .18));
    float fade = smoothstep(0.0, .04, age) * (1.0 - smoothstep(.08, .55, age));
    ALBEDO = vec3(.48, .49, .50);
    ALPHA = edge * smoothstep(.28, .72, cloud) * fade * .16;
}
