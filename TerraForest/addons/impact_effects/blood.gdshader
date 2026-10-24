shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley;
uniform sampler2D noise_map: filter_linear_mipmap, repeat_enable;
varying float life;
varying float seed;
varying float mist;
void vertex(){
    life=INSTANCE_CUSTOM.x/max(.001,INSTANCE_CUSTOM.y);
    seed=fract(INSTANCE_CUSTOM.z);mist=step(1.5,INSTANCE_CUSTOM.z);
    vec2 direction=normalize((VIEW_MATRIX*vec4(MODEL_MATRIX[2].xyz,0.0)).xy+vec2(.00001));
    vec2 side=vec2(-direction.y,direction.x);
    vec4 center=VIEW_MATRIX*MODEL_MATRIX[3];
    center.xy+=direction*VERTEX.y*length(MODEL_MATRIX[2].xyz)+side*VERTEX.x*length(MODEL_MATRIX[0].xyz);
    POSITION=PROJECTION_MATRIX*center;
    NORMAL=normalize(vec3(MODELVIEW_MATRIX[0].z,MODELVIEW_MATRIX[1].z,MODELVIEW_MATRIX[2].z));
}
void fragment(){
    float noise=texture(noise_map,UV+vec2(seed,seed*.37)).r;
    float radius=length(UV*2.0-1.0);
    float edge=1.0-smoothstep(mix(.55,.1,mist),1.0,radius+(noise-.5)*.25);
    float fade=1.0-smoothstep(mix(.5,.1,mist),1.0,life);
    ALBEDO=COLOR.rgb*mix(.85,1.15,noise);ROUGHNESS=.48;SPECULAR=.2;
    ALPHA=edge*fade*mix(.88,smoothstep(.2,.75,noise)*.24,mist);
}
