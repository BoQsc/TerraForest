shader_type spatial;
render_mode diffuse_burley;
varying vec3 world_pos;
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float ground_hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float ground_noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(ground_hash(i),ground_hash(i+vec2(1,0)),f.x),mix(ground_hash(i+vec2(0,1)),ground_hash(i+vec2(1)),f.x),f.y);}
void fragment(){
    float broad=ground_noise(world_pos.xz*0.045);
    float fine=ground_noise(world_pos.xz*1.2);
    vec3 grass=mix(vec3(0.105,0.14,0.063),vec3(0.19,0.22,0.105),broad);
    float trail=1.0-smoothstep(2.2,5.4,abs(world_pos.x-35.0*sin(world_pos.z*0.007)));
    vec3 soil=mix(vec3(0.20,0.16,0.115),vec3(0.34,0.29,0.21),fine);
    ALBEDO=mix(grass*(0.82+fine*0.30),soil,trail);
    ROUGHNESS=0.98;
    SPECULAR=0.12;
}
