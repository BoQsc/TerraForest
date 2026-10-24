shader_type particles;
render_mode disable_velocity, disable_force;
uniform int burst_count=23;
uniform vec3 surface_normal=vec3(0.0,1.0,0.0);
uniform vec4 tint=vec4(0.27,0.01,0.017,1.0);
uniform bool floor_enabled=false;
uniform vec4 floor_plane=vec4(0.0,1.0,0.0,0.0);
uint hash(uint value){value=((value>>16u)^value)*73244475u;value=((value>>16u)^value)*73244475u;return (value>>16u)^value;}
float random(inout uint seed){seed=hash(seed);return float(seed&65535u)/65535.0;}
void start(){
    ACTIVE=INDEX<uint(burst_count);
    uint seed=hash(NUMBER+RANDOM_SEED);
    bool mist=INDEX>=uint(burst_count-4);
    vec3 normal=normalize(surface_normal);
    vec3 tangent=normalize(cross(normal,abs(normal.y)<.9?vec3(0.0,1.0,0.0):vec3(1.0,0.0,0.0)));
    vec3 bitangent=cross(normal,tangent);
    float angle=random(seed)*TAU;
    vec3 spread=tangent*cos(angle)+bitangent*sin(angle);
    vec3 direction=normalize(normal*mix(.45,1.0,random(seed))+spread*random(seed)*.8+vec3(0.0,.18,0.0));
    VELOCITY=direction*mix(.6,1.8,random(seed))*(mist?.35:1.0);
    TRANSFORM=mat4(1.0);TRANSFORM[3].xyz=EMISSION_TRANSFORM[3].xyz+spread*random(seed)*.025;
    CUSTOM=vec4(0.0,mix(.5,.95,random(seed)),random(seed)+(mist?2.0:0.0),mix(.45,1.0,random(seed)));
    COLOR=tint*vec4(vec3(mix(.65,1.25,random(seed))),1.0);
}
void process(){
    CUSTOM.x+=DELTA/LIFETIME;
    if(CUSTOM.x>=CUSTOM.y)ACTIVE=false;
    bool mist=CUSTOM.z>1.5;
    VELOCITY+=vec3(0.0,mist?-.5:-7.0,0.0)*DELTA;
    VELOCITY*=max(0.0,1.0-DELTA*(mist?4.5:1.1));
    TRANSFORM[3].xyz+=VELOCITY*DELTA;
    if(floor_enabled && dot(floor_plane.xyz,TRANSFORM[3].xyz)+floor_plane.w<.006)ACTIVE=false;
    vec3 direction=normalize(VELOCITY+vec3(.00001));
    vec3 tangent=normalize(cross(direction,abs(direction.y)<.9?vec3(0.0,1.0,0.0):vec3(1.0,0.0,0.0)));
    float width=mist?mix(.13,.23,fract(CUSTOM.z))*(1.0+CUSTOM.x*1.6):.021*CUSTOM.w;
    float extent=mist?width:.032*CUSTOM.w*(1.0+min(length(VELOCITY),2.0)*.5);
    TRANSFORM[0].xyz=tangent*width;TRANSFORM[1].xyz=cross(direction,tangent)*width;TRANSFORM[2].xyz=direction*extent;
}
