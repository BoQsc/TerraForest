// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley;
uniform sampler2D noise_map: filter_linear_mipmap, repeat_enable;
varying float life;
varying float seed;
varying float dust;
void vertex(){
    life=INSTANCE_CUSTOM.x/max(.001,INSTANCE_CUSTOM.y);seed=fract(INSTANCE_CUSTOM.z);
    dust=step(1.5,INSTANCE_CUSTOM.z);
    vec4 center=VIEW_MATRIX*MODEL_MATRIX[3];
    float size=length(MODEL_MATRIX[0].xyz);
    float angle=seed*TAU;
    vec2 corner=mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)))*VERTEX.xy;
    center.xy+=corner*size*dust;
    POSITION=PROJECTION_MATRIX*center;
    // Lighting follows the camera-facing sheet, not the chip's spin basis.
    NORMAL=normalize(vec3(MODELVIEW_MATRIX[0].z,MODELVIEW_MATRIX[1].z,MODELVIEW_MATRIX[2].z));
}
void fragment(){
    if(dust<.5)discard;
    float noise=texture(noise_map,UV*.9+vec2(seed,seed*.37)).r;
    float radial=1.0-smoothstep(.1,1.0,length(UV*2.0-1.0));
    float envelope=smoothstep(0.0,.08,life)*(1.0-smoothstep(.15,1.0,life));
    ALBEDO=COLOR.rgb*1.3;ROUGHNESS=1.0;SPECULAR=0.0;
    ALPHA=radial*radial*smoothstep(.18,.78,noise)*envelope*.24;
}
