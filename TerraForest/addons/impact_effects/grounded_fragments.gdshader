// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D grain: source_color, filter_linear_mipmap, repeat_enable;
varying float life;
varying float seed;
varying float dust;
void vertex(){
    life=INSTANCE_CUSTOM.x/max(0.001,INSTANCE_CUSTOM.y);
    seed=fract(INSTANCE_CUSTOM.z);dust=step(1.5,INSTANCE_CUSTOM.z);
    if(dust>0.5)VERTEX=vec3(0.0);
    vec3 shape=mix(vec3(.83,1.0,1.08),vec3(1.14,.83,.91),seed);
    VERTEX*=shape;NORMAL=normalize(NORMAL/shape);
    UV=UV*0.55+vec2(seed,fract(seed*7.31));
}
void fragment(){
    float opacity=1.0-smoothstep(0.72,1.0,life);
    float dither=fract(52.9829189*fract(dot(floor(FRAGCOORD.xy),vec2(0.06711056,0.00583715))));
    if(dust>0.5 || opacity<=dither)discard;
    vec3 mineral=texture(grain,UV).rgb;
    float detail=clamp(dot(mineral,vec3(.2126,.7152,.0722))*3.6,.46,1.35);
    ALBEDO=COLOR.rgb*detail;
    ROUGHNESS=clamp(.93+(.7-detail)*.1,.8,1.0);SPECULAR=.12;
}
