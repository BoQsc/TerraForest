// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled;
instance uniform float fade = 1.0;
instance uniform float seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p), f=fract(p);f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
    vec2 p=UV-.5;
    float n=noise(p*28.0+seed);
    float r=length(p)+(n-.5)*.055;
    float hole=1.0-smoothstep(.12,.19,r);
    float scuff=(1.0-smoothstep(.19,.44,r))*smoothstep(.32,.75,n)*.48;
    ALBEDO=mix(vec3(.22,.20,.17),vec3(.025,.021,.018),hole);
    ROUGHNESS=1.0;
    ALPHA=max(hole*.92,scuff)*fade;
}
