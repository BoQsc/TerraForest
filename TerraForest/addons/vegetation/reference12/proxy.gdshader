shader_type spatial;
render_mode cull_disabled,depth_draw_opaque,diffuse_burley,specular_schlick_ggx;
#include "res://addons/vegetation/fade.gdshaderinc"
uniform sampler2DArray color_views : filter_linear_mipmap,repeat_disable;
uniform sampler2DArray normal_depth_views : filter_linear_mipmap,repeat_disable;
uniform sampler2D outline_texture : filter_nearest,repeat_disable;
uniform bool depth_shape = false;
uniform bool distant = false;
uniform bool shadow_only = false;
uniform vec3 sun_direction = vec3(0.5,0.8,0.3);
varying vec2 uv0;varying vec2 uv1;varying vec2 uv2;varying vec2 uv3;
varying flat vec4 layers;varying flat vec2 blend_view;
varying flat vec4 state;
varying flat vec3 axis_x;varying flat vec3 axis_y;varying flat vec3 axis_z;
// The array stores sRGB bytes. Decode explicitly, independently of driver sRGB-view support.
vec3 linear_color(vec3 c){return mix(c/12.92,pow((c+vec3(0.055))/1.055,vec3(2.4)),step(vec3(0.04045),c));}
float elevation(float row){if(row<0.5)return -0.523598775598; if(row<1.5)return 0.0;if(row<2.5)return 0.523598775598;if(row<3.5)return 1.047197551197;return 1.483529864195;}
mat3 frame_basis(float layer){float az=mod(layer,64.0)*0.098174770425;float el=elevation(floor(layer/64.0));vec3 f=vec3(sin(az)*cos(el),sin(el),cos(az)*cos(el));vec3 r=vec3(cos(az),0.0,-sin(az));return mat3(r,cross(f,r),f);}
vec2 project_uv(mat3 b,vec3 p){return vec2(dot(b[0],p)/10.0+0.5,0.5-dot(b[1],p)/20.0);}
vec3 depth_hit(mat3 b,vec3 p,float layer){vec2 uv=project_uv(b,p);float d=textureLod(normal_depth_views,vec3(uv,layer),0.0).a*24.0-12.0;return b*vec3((uv.x-0.5)*10.0,(0.5-uv.y)*20.0,d);}
void vertex(){
 float sc=length(MODEL_MATRIX[1].xyz);axis_x=MODEL_MATRIX[0].xyz/sc;axis_y=MODEL_MATRIX[1].xyz/sc;axis_z=MODEL_MATRIX[2].xyz/sc;mat3 world_axes=mat3(axis_x,axis_y,axis_z);
 vec3 center=(MODEL_MATRIX*vec4(0.0,9.23563575,0.0,1.0)).xyz;state=vec4(INSTANCE_CUSTOM.x,transition_weight(INSTANCE_CUSTOM),length(eye_world-center),INSTANCE_CUSTOM.z);
 vec3 direction=shadow_only?normalize(sun_direction):normalize(eye_world-center);vec3 v=normalize(transpose(world_axes)*direction);
 float az=mod(atan(v.x,v.z)+2.0*PI,2.0*PI)*64.0/(2.0*PI);float a0=floor(az);float a1=mod(a0+1.0,64.0);
 float el=asin(clamp(v.y,-0.999999,0.999999));float r0=0.0;if(el>=0.0)r0=1.0;if(el>=0.523598775598)r0=2.0;if(el>=1.047197551197)r0=3.0;
 float er=clamp((el-elevation(r0))/(elevation(r0+1.0)-elevation(r0)),0.0,1.0);blend_view=vec2(fract(az),er);layers=vec4(r0*64.0+a0,r0*64.0+a1,(r0+1.0)*64.0+a0,(r0+1.0)*64.0+a1);
 if(shadow_only){float row=r0+(er>=0.5?1.0:0.0);float l=row*64.0+mod(floor(az+0.5),64.0);layers=vec4(l);blend_view=vec2(0.0);}
 mat3 b0=frame_basis(layers.x),b1=frame_basis(layers.y),b2=frame_basis(layers.z),b3=frame_basis(layers.w);
 vec3 right=vec3(cos(az*2.0*PI/64.0),0.0,-sin(az*2.0*PI/64.0));vec3 up=cross(v,right);
 vec2 screen=vec2(VERTEX.x,VERTEX.y);
 if(!depth_shape){float u=(VERTEX.z+0.5)/13.0;vec2 s0=textureLod(outline_texture,vec2(u,(layers.x+0.5)/320.0),0.0).xy;vec2 s1=textureLod(outline_texture,vec2(u,(layers.y+0.5)/320.0),0.0).xy;vec2 s2=textureLod(outline_texture,vec2(u,(layers.z+0.5)/320.0),0.0).xy;vec2 s3=textureLod(outline_texture,vec2(u,(layers.w+0.5)/320.0),0.0).xy;screen=mix(mix(s0,s1,blend_view.x),mix(s2,s3,blend_view.x),blend_view.y);}
 if(shadow_only){right=b0[0];up=b0[1];v=b0[2];}
 vec3 p=right*screen.x+up*screen.y;
 if(depth_shape){vec3 h=mix(mix(depth_hit(b0,p,layers.x),depth_hit(b1,p,layers.y),blend_view.x),mix(depth_hit(b2,p,layers.z),depth_hit(b3,p,layers.w),blend_view.x),blend_view.y);p+=v*clamp(dot(h-p,v),-10.0,10.0);}
 uv0=project_uv(b0,p);uv1=project_uv(b1,p);uv2=project_uv(b2,p);uv3=project_uv(b3,p);
 VERTEX=sway(p+vec3(0.0,9.23563575,0.0),INSTANCE_CUSTOM.x);NORMAL=v;
}
void fragment(){
 if(transition_reject(FRAGCOORD.xy,state))discard;
 if(!shadow_only && pixel_noise(FRAGCOORD.yx,state.x+0.314)>1.0-smoothstep(far_distance*0.93,far_distance,state.z))discard;
 if(shadow_only){vec4 c=texture(color_views,vec3(uv0,layers.x));if(c.a<0.24)discard;ALPHA=c.a;ALPHA_SCISSOR_THRESHOLD=0.24;ALBEDO=vec3(0.05);ROUGHNESS=1.0;}
 else {
 vec4 weights=vec4((1.0-blend_view.x)*(1.0-blend_view.y),blend_view.x*(1.0-blend_view.y),(1.0-blend_view.x)*blend_view.y,blend_view.x*blend_view.y);
 vec4 c0;vec4 c1;vec4 c2=vec4(0.0);vec4 c3=vec4(0.0);vec3 n0;vec3 n1;vec3 n2=vec3(0.0);vec3 n3=vec3(0.0);
 if(distant){bool upper=pixel_noise(FRAGCOORD.xy,state.x+0.723)<blend_view.y;vec2 a=upper?uv2:uv0;vec2 b=upper?uv3:uv1;float l0=upper?layers.z:layers.x;float l1=upper?layers.w:layers.y;c0=texture(color_views,vec3(a,l0));c1=texture(color_views,vec3(b,l1));n0=texture(normal_depth_views,vec3(a,l0)).rgb;n1=texture(normal_depth_views,vec3(b,l1)).rgb;weights=vec4(1.0-blend_view.x,blend_view.x,0.0,0.0);}
 else{c0=texture(color_views,vec3(uv0,layers.x));c1=texture(color_views,vec3(uv1,layers.y));c2=texture(color_views,vec3(uv2,layers.z));c3=texture(color_views,vec3(uv3,layers.w));n0=texture(normal_depth_views,vec3(uv0,layers.x)).rgb;n1=texture(normal_depth_views,vec3(uv1,layers.y)).rgb;n2=texture(normal_depth_views,vec3(uv2,layers.z)).rgb;n3=texture(normal_depth_views,vec3(uv3,layers.w)).rgb;}
 vec4 w=weights*vec4(c0.a,c1.a,c2.a,c3.a);float alpha=dot(w,vec4(1.0));if(alpha<0.24)discard;
 ALPHA=alpha;ALPHA_SCISSOR_THRESHOLD=0.24;vec3 lit_color=linear_color(c0.rgb)*w.x+linear_color(c1.rgb)*w.y;if(!distant)lit_color+=linear_color(c2.rgb)*w.z+linear_color(c3.rgb)*w.w;ALBEDO=lit_color/max(alpha,0.001);
 vec3 n=normalize((n0*w.x+n1*w.y+n2*w.z+n3*w.w)/max(alpha,0.001)*2.0-1.0+vec3(0.00001));NORMAL=normalize(mat3(VIEW_MATRIX)*mat3(axis_x,axis_y,axis_z)*n);METALLIC=0.0;SPECULAR=0.18;ROUGHNESS=0.93;
 }
}
