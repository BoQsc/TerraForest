uniform float clock_seconds = 0.0;
uniform vec3 eye_world = vec3(0.0,0.0,0.0);
uniform float far_distance = 2200.0;
uniform float wind_amount = 0.0;
float pixel_noise(vec2 pixel,float seed){return fract(52.9829189*fract(dot(floor(pixel),vec2(0.06711056,0.00583715))+seed*0.61803398875));}
float transition_weight(vec4 packet){
 if(abs(packet.z)<0.5)return 1.0;
 // Signed cyclic delta: a start rounded slightly ahead of the shader clock is
 // the beginning of a fade, NOT a 4096-second-old, already completed fade.
 float elapsed=mod(clock_seconds-packet.y+2048.0,4096.0)-2048.0;
 float a=smoothstep(0.0,1.0,clamp(elapsed/max(packet.w,0.001),0.0,1.0));
 return packet.z>0.0?a:1.0-a;
}
bool transition_reject(vec2 pixel,vec4 state){
 if(abs(state.w)<0.5)return false;
 float noise=pixel_noise(pixel,state.x);
 // Incoming owns [0,a); outgoing owns [a,1). The previous implementation
 // used noise<weight for BOTH sides, leaving half the overlap empty at a=0.5.
 return state.w<0.0 ? noise<1.0-state.y : noise>=state.y;
}
vec3 sway(vec3 p,float seed){float h=clamp(p.y/18.47127,0.0,1.0);p.x+=wind_amount*h*h*sin(clock_seconds*0.65+seed*6.283185);return p;}
