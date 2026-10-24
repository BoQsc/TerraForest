// SPDX-License-Identifier: 0BSD
shader_type particles;
render_mode disable_velocity, disable_force;
uniform bool spark=false;
uniform bool breakup=false;
uniform int burst_count=14;
uniform int dust_count=4;
uniform vec3 surface_normal=vec3(0.0,1.0,0.0);
uniform vec4 tint=vec4(1.0);
uniform vec3 piece_scale=vec3(0.04);
uniform bool floor_enabled=false;
uniform vec4 floor_plane=vec4(0.0,1.0,0.0,0.0);
uint hash(uint x){x=((x>>16u)^x)*73244475u;x=((x>>16u)^x)*73244475u;return (x>>16u)^x;}
float random(inout uint seed){seed=hash(seed);return float(seed&65535u)/65535.0;}
mat3 rotation(vec3 axis,float a){float s=sin(a),c=cos(a),v=1.0-c;return mat3(vec3(axis.x*axis.x*v+c,axis.y*axis.x*v+axis.z*s,axis.z*axis.x*v-axis.y*s),vec3(axis.x*axis.y*v-axis.z*s,axis.y*axis.y*v+c,axis.z*axis.y*v+axis.x*s),vec3(axis.x*axis.z*v+axis.y*s,axis.y*axis.z*v-axis.x*s,axis.z*axis.z*v+c));}
void start(){
    ACTIVE=INDEX<uint(burst_count);
    uint seed=hash(NUMBER+RANDOM_SEED);
    bool dust=!spark && INDEX>=uint(burst_count-dust_count);
    vec3 n=normalize(surface_normal);
    vec3 u=normalize(cross(n,abs(n.y)<.9?vec3(0.0,1.0,0.0):vec3(1.0,0.0,0.0)));
    vec3 v=cross(n,u);float a=random(seed)*TAU;
    vec3 direction=normalize(n*mix(.15,.65,random(seed))+(u*cos(a)+v*sin(a))*mix(.3,1.0,random(seed))+vec3(0.0,spark?.05:.28,0.0));
    float speed=spark?mix(1.8,4.7,random(seed)):mix(.55,1.75,random(seed));
    VELOCITY=direction*speed*(dust?.25:1.0);
    TRANSFORM=mat4(1.0);TRANSFORM[3].xyz=EMISSION_TRANSFORM[3].xyz+(u*cos(a)+v*sin(a))*random(seed)*.065;
    CUSTOM=vec4(0.0,mix(.55,1.0,random(seed)),random(seed)+(dust?2.0:0.0),mix(.25,1.0,pow(random(seed),1.7)));
    float shade=mix(.72,1.18,random(seed));
    COLOR=tint*vec4(vec3(shade),1.0);
    // One angular phase integrated on GPU; ground friction slows it with motion.
    USERDATA1=vec4(random(seed)*TAU,mix(-16.0,16.0,random(seed)),0.0,0.0);
}
void process(){
    CUSTOM.x+=DELTA/LIFETIME;
    if(CUSTOM.x>=CUSTOM.y)ACTIVE=false;
    bool dust=CUSTOM.z>1.5;
    float seed=fract(CUSTOM.z);
    VELOCITY+=vec3(0.0,dust?-.45:-9.8,0.0)*DELTA;
    VELOCITY*=max(0.0,1.0-DELTA*(dust?3.5:(spark?1.3:.65)));
    TRANSFORM[3].xyz+=VELOCITY*DELTA;
    float radius=dust?.02:(spark?.002:.009*CUSTOM.w);
    float height=dot(floor_plane.xyz,TRANSFORM[3].xyz)+floor_plane.w-radius;
    if(floor_enabled && height<0.0){
        TRANSFORM[3].xyz-=floor_plane.xyz*height;
        float speed=dot(VELOCITY,floor_plane.xyz);
        if(speed<0.0)VELOCITY=(VELOCITY-floor_plane.xyz*speed)*.45-floor_plane.xyz*speed*.12;
        USERDATA1.y*=max(0.0,1.0-DELTA*25.0);
    }
    USERDATA1.x+=USERDATA1.y*DELTA;
    mat3 basis;
    if(spark){
        vec3 z=normalize(VELOCITY+vec3(.0001));vec3 x=normalize(cross(z,abs(z.y)<.9?vec3(0.0,1.0,0.0):vec3(1.0,0.0,0.0)));basis=mat3(x,cross(z,x),z);
    }else{basis=rotation(normalize(vec3(.3+seed,1.0,.5)),USERDATA1.x);}
    vec3 shape=piece_scale*CUSTOM.w*(breakup?1.12:1.0);
    if(spark)shape=vec3(piece_scale.x*mix(.7,1.2,seed),piece_scale.y,piece_scale.z*mix(.35,1.0,seed)*(1.0-CUSTOM.x*.75));
    if(dust)shape=vec3(mix(.12,.23,seed)*(1.0+CUSTOM.x*1.8));
    TRANSFORM[0].xyz=basis[0]*shape.x;TRANSFORM[1].xyz=basis[1]*shape.y;TRANSFORM[2].xyz=basis[2]*shape.z;
}
