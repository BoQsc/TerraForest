// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
varying float phase;
void vertex() {
    phase = sin(MODEL_MATRIX[3].x * .37 + MODEL_MATRIX[3].z * .71) * 9.0;
}
void fragment() {
    float height = 1.0 - UV.y;
    float clock = TIME * 3.0 + phase;
    float bend = sin(height * 9.0 - clock) * height * .11;
    bend += sin(height * 17.0 + clock * 1.3) * height * .035;
    float width = pow(max(0.0, 1.0 - height), .8) * .39;
    float distance = width - abs(UV.x - .5 + bend);
    float edge = smoothstep(-.015, .07, distance);
    float base = smoothstep(.0, .12, height) * (1.0 - smoothstep(.76, 1.0, height));
    float heat = clamp(distance * 4.0 + (1.0 - height) * .35, 0.0, 1.0);
    vec3 color = mix(vec3(.7, .055, .005), vec3(1.0, .46, .055), heat);
    ALBEDO = color;
    EMISSION = color * .4;
    ALPHA = edge * base * .9;
}
