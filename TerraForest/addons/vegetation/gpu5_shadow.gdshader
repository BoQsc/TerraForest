shader_type spatial;
render_mode cull_disabled,depth_draw_opaque,unshaded;
#include "res://addons/vegetation/fade.gdshaderinc"
uniform sampler2DArray color_views : filter_linear_mipmap,repeat_disable;
uniform sampler2D outline_texture : filter_nearest,repeat_disable;
uniform vec3 sun_direction = vec3(0.5,0.8,0.3);
varying vec2 shadow_uv;
varying flat float shadow_layer;
varying flat vec4 state;
float elevation(float row){if(row<0.5)return -0.523598775598; if(row<1.5)return 0.0;if(row<2.5)return 0.523598775598;if(row<3.5)return 1.047197551197;return 1.483529864195;}
mat3 frame_basis(float layer){float az=mod(layer,64.0)*0.098174770425;float el=elevation(floor(layer/64.0));vec3 f=vec3(sin(az)*cos(el),sin(el),cos(az)*cos(el));vec3 r=vec3(cos(az),0.0,-sin(az));return mat3(r,cross(f,r),f);}
vec2 project_uv(mat3 b,vec3 p){return vec2(dot(b[0],p)/10.0+0.5,0.5-dot(b[1],p)/20.0);}
void vertex(){
 float sc=length(MODEL_MATRIX[1].xyz);
 mat3 axes=mat3(MODEL_MATRIX[0].xyz/sc,MODEL_MATRIX[1].xyz/sc,MODEL_MATRIX[2].xyz/sc);
 state=vec4(INSTANCE_CUSTOM.x,transition_weight(INSTANCE_CUSTOM),1.0,INSTANCE_CUSTOM.z);
 vec3 direction=normalize(sun_direction);vec3 v=normalize(transpose(axes)*direction);
 float az=mod(atan(v.x,v.z)+2.0*PI,2.0*PI)*64.0/(2.0*PI);
 float el=asin(clamp(v.y,-0.999999,0.999999));float r0=0.0;if(el>=0.0)r0=1.0;if(el>=0.523598775598)r0=2.0;if(el>=1.047197551197)r0=3.0;
 float er=clamp((el-elevation(r0))/(elevation(r0+1.0)-elevation(r0)),0.0,1.0);
 shadow_layer=(r0+(er>=0.5?1.0:0.0))*64.0+mod(floor(az+0.5),64.0);
 mat3 b=frame_basis(shadow_layer);
 vec2 screen=textureLod(outline_texture,vec2((VERTEX.z+0.5)/13.0,(shadow_layer+0.5)/320.0),0.0).xy;
 vec3 p=b[0]*screen.x+b[1]*screen.y;
 shadow_uv=project_uv(b,p);
 VERTEX=sway(p+vec3(0.0,9.23563575,0.0),INSTANCE_CUSTOM.x);NORMAL=b[2];
}
void fragment(){
 if(transition_reject(FRAGCOORD.xy,state))discard;
 float alpha=texture(color_views,vec3(shadow_uv,shadow_layer)).a;
 if(alpha<0.24)discard;
 ALPHA=alpha;ALPHA_SCISSOR_THRESHOLD=0.24;ALBEDO=vec3(0.05);ROUGHNESS=1.0;
}
