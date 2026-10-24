// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform sampler2D boulder_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 cover_eye=vec3(0.0);
uniform float cover_clock=0.0;
uniform float distance_fade_start=100.0;
uniform float distance_fade_end=124.0;
varying float coverage;
varying float tint;
varying float variation;
varying vec3 rock_position;
varying vec3 rock_normal;
vec3 turn(vec3 p,vec3 axis,float angle){return p*cos(angle)+cross(axis,p)*sin(angle)+axis*dot(axis,p)*(1.0-cos(angle));}
float roll_angle(vec2 centre,float stage){return (stage<1.5?0.10:(stage<2.5?0.20:0.40))*(0.8+0.4*clamp(abs(centre.x)*2.0+abs(centre.y),0.0,1.0));}
float spread_distance(float stage){return stage<1.5?0.010:(stage<2.5?0.018:0.035);}
void vertex(){
    float stage=floor(INSTANCE_CUSTOM.y);
    float event=fract(INSTANCE_CUSTOM.y);
    bool tap=event>=0.5;
    float impact_angle=mod(event,0.5)/0.4*6.283185307;
    vec2 impact=vec2(cos(impact_angle),sin(impact_angle));
    float age=max(0.0,cover_clock-INSTANCE_CUSTOM.x);
    rock_position=VERTEX;rock_normal=NORMAL;
    variation=0.95+0.05*sin(dot(MODEL_MATRIX[3].xz,vec2(0.71,0.43))*3.7);
    if(stage>0.5){
        vec3 pivot=vec3(UV2.x,(COLOR.g-0.5)*0.4,UV2.y);
        vec2 direction=normalize(UV2);
        vec3 axis=vec3(direction.y,0.0,-direction.x);
        float seed=fract(sin(dot(UV2,vec2(127.1,311.7)))*43758.5453);
        float proximity=0.5+0.5*dot(direction,impact);
        // The struck side releases first; other chunks follow, with different
        // inertia. A short angular impulse rings down after ground contact.
        float delay=tap?0.0:0.025+0.14*(1.0-proximity)+seed*0.045;
        float time=max(0.0,age-delay);
        float t=clamp(time/(0.44+seed*0.16),0.0,1.0);
        float settle=tap?1.0:1.0-pow(1.0-t,3.0);
        float impulse=(tap?0.035:0.12)*(0.65+0.35*proximity)*exp(-7.0*time)*sin(17.0*time);
        float angle=roll_angle(UV2,stage)+impulse;
        vec3 start=VERTEX;
        vec3 start_normal=NORMAL;vec3 start_tangent=TANGENT;vec3 start_binormal=BINORMAL;
        if(stage>1.5){
            vec3 parent_pivot=CUSTOM0.xyz;
            vec2 parent_direction=normalize(parent_pivot.xz);
            vec3 parent_axis=vec3(parent_direction.y,0.0,-parent_direction.x);
            float parent_angle=roll_angle(parent_pivot.xz,stage-1.0);
            start=parent_pivot+turn(VERTEX-parent_pivot,parent_axis,parent_angle);
            start.xz+=parent_direction*spread_distance(stage-1.0);start.y+=CUSTOM0.w;
            start_normal=turn(NORMAL,parent_axis,parent_angle);start_tangent=turn(TANGENT,parent_axis,parent_angle);start_binormal=turn(BINORMAL,parent_axis,parent_angle);
        }
        vec3 target=pivot+turn(VERTEX-pivot,axis,angle);
        vec2 spread=direction*spread_distance(stage);
        spread+=direction*(tap?0.002:0.009)*sin(3.14159265*clamp(time/0.35,0.0,1.0))*exp(-3.0*time);
        target.xz+=spread;target.y+=(COLOR.a-0.5)*0.5+dot(INSTANCE_CUSTOM.zw,pivot.xz+spread);
        VERTEX=mix(start,target,settle);
        NORMAL=normalize(mix(start_normal,turn(NORMAL,axis,angle),settle));
        TANGENT=normalize(mix(start_tangent,turn(TANGENT,axis,angle),settle));
        BINORMAL=normalize(mix(start_binormal,turn(BINORMAL,axis,angle),settle));
    }
    // Every real hit has a restrained impact reaction, including hits between
    // fracture thresholds. Later hits preserve the already settled chunk pose.
    VERTEX.xz+=impact*0.0035*sin(age*43.0)*exp(-15.0*age);
    float distance_weight=1.0-smoothstep(distance_fade_start,distance_fade_end,distance(MODEL_MATRIX[3].xz,cover_eye.xz));
    coverage=distance_weight*(stage>2.5?1.0-smoothstep(1.8,2.6,age):1.0);
    tint=stage>0.5?COLOR.r:1.0;
}
void fragment(){
    float threshold=fract(52.9829189*fract(dot(floor(FRAGCOORD.xy),vec2(0.06711056,0.00583715))));
    if(coverage<=threshold)discard;
    // One local-space projection on each axis keeps freshly cut faces and
    // rounded surfaces at the same scale without stretched pole/cap UVs.
    vec3 weights=pow(abs(normalize(rock_normal)),vec3(4.0));weights/=max(0.0001,weights.x+weights.y+weights.z);
    vec3 p=rock_position*2.5;
    vec3 granite=texture(boulder_color,p.yz).rgb*weights.x+texture(boulder_color,p.xz).rgb*weights.y+texture(boulder_color,p.xy).rgb*weights.z;
    ALBEDO=granite*tint*variation;
    ROUGHNESS=0.94;SPECULAR=0.24;
}
