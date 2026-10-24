// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode diffuse_burley;
uniform float emission_strength=0.0;
varying float life;
void vertex(){life=INSTANCE_CUSTOM.x/max(0.001,INSTANCE_CUSTOM.y);}
void fragment(){
    float opacity=1.0-smoothstep(0.62,1.0,life);
    float noise=fract(52.9829189*fract(dot(floor(FRAGCOORD.xy),vec2(0.06711056,0.00583715))));
    if(opacity<=noise)discard;
    ALBEDO=COLOR.rgb;ROUGHNESS=0.96;SPECULAR=0.16;
    EMISSION=COLOR.rgb*emission_strength*(1.0-smoothstep(0.1,1.0,life));
}
