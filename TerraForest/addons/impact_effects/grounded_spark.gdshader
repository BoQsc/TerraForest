// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
varying float life;
varying float seed;
void vertex(){
    life=INSTANCE_CUSTOM.x/max(0.001,INSTANCE_CUSTOM.y);seed=fract(INSTANCE_CUSTOM.z);
    // Camera-facing ribbon aligned with the projected velocity. It stays thin
    // from every viewpoint instead of exposing a glowing box's side faces.
    vec2 direction=normalize((VIEW_MATRIX*vec4(MODEL_MATRIX[2].xyz,0.0)).xy+vec2(.00001));
    vec2 side=vec2(-direction.y,direction.x);
    vec4 center=VIEW_MATRIX*MODEL_MATRIX[3];
    center.xy+=direction*VERTEX.y*length(MODEL_MATRIX[2].xyz)+side*VERTEX.x*length(MODEL_MATRIX[0].xyz);
    POSITION=PROJECTION_MATRIX*center;
}
void fragment(){
    float width=pow(max(0.0,1.0-abs(UV.x*2.0-1.0)),1.5);
    float tip=smoothstep(0.0,.18,UV.y)*(1.0-smoothstep(.65,1.0,UV.y));
    float fade=1.0-smoothstep(.12,1.0,life);
    vec3 hot=mix(vec3(1.0,.65,.24),vec3(1.0,.90,.66),seed);
    ALBEDO=mix(hot,vec3(.8,.13,.02),smoothstep(.1,.85,life))*1.8;
    ALPHA=width*tip*fade*.85;
}
