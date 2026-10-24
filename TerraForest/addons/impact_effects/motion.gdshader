// SPDX-License-Identifier: 0BSD
shader_type particles;
render_mode disable_velocity, disable_force;
uniform bool spark=false;
uniform bool breakup=false;
uniform int burst_count=14;
uniform vec3 surface_normal=vec3(0.0,1.0,0.0);
uniform vec4 tint=vec4(1.0);
uniform vec3 piece_scale=vec3(0.05);
uniform bool floor_enabled=false;
uniform vec4 floor_plane=vec4(0.0,1.0,0.0,0.0);
uint hash(uint x){x=((x>>16u)^x)*73244475u;x=((x>>16u)^x)*73244475u;return (x>>16u)^x;}
float random(inout uint seed){seed=hash(seed);return float(seed&65535u)/65535.0;}
mat3 rotation(vec3 axis,float a){float s=sin(a),c=cos(a),v=1.0-c;return mat3(vec3(axis.x*axis.x*v+c,axis.y*axis.x*v+axis.z*s,axis.z*axis.x*v-axis.y*s),vec3(axis.x*axis.y*v-axis.z*s,axis.y*axis.y*v+c,axis.z*axis.y*v+axis.x*s),vec3(axis.x*axis.z*v+axis.y*s,axis.y*axis.z*v-axis.x*s,axis.z*axis.z*v+c));}
void start(){
    ACTIVE=INDEX<uint(burst_count);
    uint seed=hash(NUMBER+RANDOM_SEED);
    vec3 n=normalize(surface_normal);
    vec3 u=normalize(cross(n,abs(n.y)<0.9?vec3(0.0,1.0,0.0):vec3(1.0,0.0,0.0)));
    vec3 v=cross(n,u);float a=random(seed)*TAU;float spread=mix(0.15,1.0,random(seed));
    vec3 direction=normalize(n*mix(0.4,1.0,random(seed))+(u*cos(a)+v*sin(a))*spread+vec3(0.0,spark?0.1:0.45,0.0));
    VELOCITY=direction*(spark?mix(2.0,5.0,random(seed)):mix(0.7,2.2,random(seed)))*(breakup?1.15:1.0);
    TRANSFORM=mat4(1.0);TRANSFORM[3].xyz=EMISSION_TRANSFORM[3].xyz+(u*cos(a)+v*sin(a))*random(seed)*0.045;
    CUSTOM=vec4(0.0,mix(0.60,1.0,random(seed)),random(seed),mix(0.55,1.25,random(seed)));
    COLOR=tint*vec4(vec3(mix(0.7,1.15,random(seed))),1.0);
}
void process(){
    CUSTOM.x+=DELTA/LIFETIME;
    if(CUSTOM.x>=CUSTOM.y)ACTIVE=false;
    VELOCITY+=vec3(0.0,-9.8,0.0)*DELTA;
    VELOCITY*=max(0.0,1.0-DELTA*(spark?1.6:0.8));
    TRANSFORM[3].xyz+=VELOCITY*DELTA;
    float radius=spark?0.005:0.018*CUSTOM.w;
    float height=dot(floor_plane.xyz,TRANSFORM[3].xyz)+floor_plane.w-radius;
    if(floor_enabled && height<0.0){
        TRANSFORM[3].xyz-=floor_plane.xyz*height;
        float speed=dot(VELOCITY,floor_plane.xyz);
        if(speed<0.0)VELOCITY=(VELOCITY-floor_plane.xyz*speed)*0.60-floor_plane.xyz*speed*0.18;
    }
    mat3 basis;
    if(spark){
        vec3 z=normalize(VELOCITY+vec3(0.0001));vec3 x=normalize(cross(z,abs(z.y)<0.9?vec3(0.0,1.0,0.0):vec3(1.0,0.0,0.0)));basis=mat3(x,cross(z,x),z);
    }else{
        float spin=CUSTOM.z*TAU+CUSTOM.x*LIFETIME*(4.0+CUSTOM.z*8.0);
        basis=rotation(normalize(vec3(0.3+CUSTOM.z,1.0,0.5)),spin);
    }
    vec3 shape=piece_scale*CUSTOM.w*(breakup?1.2:1.0);
    if(!spark)shape*=vec3(mix(0.7,1.3,CUSTOM.z),mix(1.15,0.75,CUSTOM.z),mix(0.8,1.2,fract(CUSTOM.z*7.0)));
    TRANSFORM[0].xyz=basis[0]*shape.x;TRANSFORM[1].xyz=basis[1]*shape.y;TRANSFORM[2].xyz=basis[2]*shape.z;
}
