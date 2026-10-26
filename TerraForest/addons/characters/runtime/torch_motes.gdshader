// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float clock=0.0;
uniform bool smoke=false;
varying float life;
void vertex() {
    float seed=INSTANCE_CUSTOM.x;
    life=fract(clock*(smoke ? .26 : .45)+seed);
    vec3 drift=vec3(sin(seed*81.0+life*5.0)*life*.13,life*(smoke ? .70 : .60),cos(seed*93.0+life*6.0)*life*.10);
    mat4 billboard=mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
    billboard[3].xyz+=drift;
    MODELVIEW_MATRIX=VIEW_MATRIX*billboard;
    VERTEX*=smoke ? .5+life*1.7 : 1.0-life*.5;
}
void fragment() {
    float radial=length(UV-.5)*2.0;
    float fade=sin(life*3.14159265);
    if(smoke) {
        ALBEDO=vec3(.16,.14,.12);
        ALPHA=pow(max(0.0,1.0-radial),2.0)*fade*.11;
    } else {
        ALBEDO=vec3(1.0,.30,.025);EMISSION=ALBEDO*3.0;
        ALPHA=(1.0-smoothstep(.2,1.0,radial))*fade*.85;
    }
}
