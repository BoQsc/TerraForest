shader_type spatial;
render_mode cull_disabled;
uniform vec3 water_color : source_color = vec3(0.035, 0.22, 0.25);
void fragment() {
    // Normal-only ripples keep the rendered mean surface at the queried fill level.
    float a = dot(UV, vec2(0.32, 0.21)) + TIME * 0.7;
    float b = dot(UV, vec2(-0.19, 0.37)) - TIME * 0.48;
    vec3 wave_normal = normalize(vec3(cos(a) * 0.12, 1.0, cos(b) * 0.09));
    NORMAL = normalize((VIEW_MATRIX * vec4(wave_normal, 0.0)).xyz);
    float grazing = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
    ALBEDO = mix(water_color * (0.96 + 0.04 * sin(a + b)), vec3(0.34, 0.52, 0.60), grazing * 0.65);
    METALLIC = 0.15;
    ROUGHNESS = 0.18;
    SPECULAR = 0.8;
}
